--!strict
-- Central developer-product receipt processing (MarketplaceService.ProcessReceipt).
-- Pure apart from the injected dependencies, so the test-suite drives it with fakes.
--
-- Rules (Roblox "player data purchasing" pattern):
--   * A receipt is granted at most once: its PurchaseId is stored in the player's save.
--   * The grant and the PurchaseId are saved together BEFORE returning PurchaseGranted.
--     If the save fails both are rolled back and NotProcessedYet is returned, so Roblox
--     retries later (next purchase or rejoin). Nothing is ever granted from
--     PromptProductPurchaseFinished.
--   * Sessions that cannot save (DataStore down, save locked elsewhere) never grant.
--   * Gem spending is blocked while a receipt save is in flight so a rollback can never
--     leave the balance inconsistent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("MonetizationConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

export type Decision = "Granted" | "NotProcessedYet"

export type Session = {
	data: PlayerData.Data,
	canSave: boolean,
	receiptBusy: number,
	pendingReceipts: { [string]: boolean },
}

export type Deps = {
	findSession: (userId: number) -> Session?,
	isPresent: (userId: number) -> boolean,
	save: (Session) -> boolean,
	onGranted: (Session, MonetizationConfig.Product) -> (),
	wait: (number) -> (),
	now: () -> number,
	sessionTimeout: number?,
}

local Receipts = {}
Receipts.__index = Receipts

export type Processor = typeof(setmetatable({} :: { deps: Deps }, Receipts))

function Receipts.new(deps: Deps): Processor
	return setmetatable({ deps = deps }, Receipts)
end

function Receipts.process(self: Processor, info: { [string]: any }): Decision
	local deps = self.deps
	local userId = info.PlayerId
	local productId = info.ProductId
	local purchaseId = info.PurchaseId
	if type(userId) ~= "number" or type(productId) ~= "number" or purchaseId == nil then
		return "NotProcessedYet"
	end
	purchaseId = tostring(purchaseId)
	local product = MonetizationConfig.productById(productId)
	if not product then
		warn("[SnackForce] Receipt for unknown product id " .. tostring(productId))
		return "NotProcessedYet"
	end

	-- The player may still be loading: wait for their session while they are here.
	local session = deps.findSession(userId)
	local waited = 0
	local timeout = deps.sessionTimeout or 30
	while not session and deps.isPresent(userId) and waited < timeout do
		deps.wait(0.5)
		waited += 0.5
		session = deps.findSession(userId)
	end
	if not session or not session.canSave then
		return "NotProcessedYet"
	end
	local data = session.data
	if data.receipts[purchaseId] then
		return "Granted" -- already fulfilled (e.g. retried after a lost acknowledgement)
	end
	if session.pendingReceipts[purchaseId] then
		return "NotProcessedYet" -- the same receipt is mid-save in this server
	end

	session.pendingReceipts[purchaseId] = true
	session.receiptBusy += 1
	data.gems += product.gems
	PlayerData.recordReceipt(data, purchaseId, deps.now())
	local ok, saved = pcall(deps.save, session)
	session.receiptBusy -= 1
	session.pendingReceipts[purchaseId] = nil
	if ok and saved then
		deps.onGranted(session, product)
		return "Granted"
	end
	data.gems = math.max(0, data.gems - product.gems)
	data.receipts[purchaseId] = nil
	return "NotProcessedYet"
end

return Receipts
