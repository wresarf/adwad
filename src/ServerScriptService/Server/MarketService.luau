--!strict
-- MarketplaceService / PolicyService wrapper: game pass ownership, Robux prices for the
-- store, purchase prompts and the paid-random-items policy gate. Services are injectable
-- for the test-suite. Every Roblox call is pcall'd; failures fail closed (not owned, not
-- purchasable, paid random items restricted).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("MonetizationConfig"))

export type Status = string -- "unset" | "ok" | "offsale" | "error"
export type Listing = {
	key: string,
	name: string,
	description: string,
	status: Status,
	price: number?, -- Robux, only when status == "ok"
	gems: number?,
	icon: string?,
}

local MarketService = {}
MarketService.__index = MarketService

type Self = {
	marketplace: any,
	policy: any,
	prices: { [string]: { status: Status, price: number? } },
	policyCache: { [Player]: boolean },
}
export type Market = typeof(setmetatable({} :: Self, MarketService))

function MarketService.new(marketplace: any, policy: any): Market
	return setmetatable({ marketplace = marketplace, policy = policy, prices = {}, policyCache = {} } :: Self, MarketService)
end

local function productInfo(marketplace: any, id: number, infoType: Enum.InfoType): (boolean, any)
	-- GetProductInfoAsync replaces the deprecated GetProductInfo; fall back for older engines.
	local ok, info = pcall(function()
		return marketplace:GetProductInfoAsync(id, infoType)
	end)
	if ok then
		return true, info
	end
	return pcall(function()
		return marketplace:GetProductInfo(id, infoType)
	end)
end

-- Fetches Robux prices for every configured pass / product. Unconfigured ids are never
-- looked up and stay "unset" (shown as "Not available yet", no prompt).
function MarketService.refreshPrices(self: Market)
	local function fetch(kind: string, key: string, id: number, infoType: Enum.InfoType)
		local slot = kind .. ":" .. key
		if not MonetizationConfig.isConfigured(id) then
			self.prices[slot] = { status = "unset" }
			return
		end
		local ok, info = productInfo(self.marketplace, id, infoType)
		if not ok or type(info) ~= "table" then
			self.prices[slot] = { status = "error" }
		elseif info.IsForSale == false or type(info.PriceInRobux) ~= "number" then
			self.prices[slot] = { status = "offsale" }
		else
			self.prices[slot] = { status = "ok", price = info.PriceInRobux }
		end
	end
	for _, p in MonetizationConfig.GamePasses do
		fetch("pass", p.key, p.id, Enum.InfoType.GamePass)
	end
	for _, p in MonetizationConfig.Products do
		fetch("product", p.key, p.id, Enum.InfoType.Product)
	end
end

local function priceOf(self: Market, slot: string): (Status, number?)
	local entry = self.prices[slot]
	if not entry then
		return "unset", nil
	end
	return entry.status, entry.price
end

-- Store listing sent to clients (no ids: the client never prompts by itself).
function MarketService.catalog(self: Market): { passes: { Listing }, products: { Listing } }
	local passes, products = {}, {}
	for _, p in MonetizationConfig.GamePasses do
		local status, price = priceOf(self, "pass:" .. p.key)
		table.insert(passes, { key = p.key, name = p.name, description = p.description, icon = p.icon, status = status, price = price })
	end
	for _, p in MonetizationConfig.Products do
		local status, price = priceOf(self, "product:" .. p.key)
		table.insert(products, { key = p.key, name = p.name, description = string.format("%d Gems", p.gems), gems = p.gems, status = status, price = price })
	end
	return { passes = passes, products = products }
end

-- Server-side ownership check. Unconfigured passes are never owned.
function MarketService.ownsPass(self: Market, player: Player, pass: MonetizationConfig.GamePass): boolean
	if not MonetizationConfig.isConfigured(pass.id) then
		return false
	end
	local ok, owns = pcall(function()
		return self.marketplace:UserOwnsGamePassAsync(player.UserId, pass.id)
	end)
	return ok and owns == true
end

function MarketService.ownedPasses(self: Market, player: Player): { [string]: boolean }
	local owned = {}
	for _, pass in MonetizationConfig.GamePasses do
		if self:ownsPass(player, pass) then
			owned[pass.key] = true
		end
	end
	return owned
end

local function promptable(self: Market, slot: string, id: number): (boolean, string)
	if not MonetizationConfig.isConfigured(id) then
		return false, "Not available yet"
	end
	local status = priceOf(self, slot)
	if status == "offsale" then
		return false, "Not on sale right now"
	end
	return true, ""
end

function MarketService.promptPass(self: Market, player: Player, key: any): (boolean, string)
	local pass = MonetizationConfig.getPass(key)
	if not pass then
		return false, "Unknown item"
	end
	local can, why = promptable(self, "pass:" .. pass.key, pass.id)
	if not can then
		return false, why
	end
	local ok = pcall(function()
		self.marketplace:PromptGamePassPurchase(player, pass.id)
	end)
	return ok, if ok then "Opening purchase..." else "Store unavailable, try again"
end

function MarketService.promptProduct(self: Market, player: Player, key: any): (boolean, string)
	local product = MonetizationConfig.getProduct(key)
	if not product then
		return false, "Unknown item"
	end
	local can, why = promptable(self, "product:" .. product.key, product.id)
	if not can then
		return false, why
	end
	local ok = pcall(function()
		self.marketplace:PromptProductPurchase(player, product.id)
	end)
	return ok, if ok then "Opening purchase..." else "Store unavailable, try again"
end

-- PolicyService gate for paid random items. Fails closed: if the policy can't be read,
-- the player is treated as restricted.
function MarketService.paidRandomRestricted(self: Market, player: Player): boolean
	local cached = self.policyCache[player]
	if cached ~= nil then
		return cached
	end
	local ok, info = pcall(function()
		return self.policy:GetPolicyInfoForPlayerAsync(player)
	end)
	local restricted = not ok or type(info) ~= "table" or info.ArePaidRandomItemsRestricted ~= false
	if ok then
		self.policyCache[player] = restricted -- only cache real answers, retry after errors
	end
	return restricted
end

function MarketService.forget(self: Market, player: Player)
	self.policyCache[player] = nil
end

return MarketService
