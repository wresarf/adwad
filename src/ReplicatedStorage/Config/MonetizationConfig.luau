--!strict
-- Every Robux offer in one place (Gem developer products only; former passes are free perks). IDs are 0 until the game is published and real passes /
-- developer products are created on the Creator Dashboard. An offer with id 0 is shown as
-- "Not available yet" and the server refuses to prompt it, so nothing here can be bought
-- by accident. Robux prices are never hard-coded: the server reads them from
-- MarketplaceService for configured IDs.
--
-- Currency design (see docs/DESIGN_AUDIT.md):
--   Coins      earned only. Never sold, never converted from Gems.
--   Paw Tokens earned only (quests, first landings, new species). The only egg currency.
--   Gems       the one Robux-purchasable currency. Gems only buy fixed, fully disclosed
--              items (a named pet with a named mutation, or a timed boost). Gems never buy
--              eggs, tokens, coins, foods, luck or anything with a random outcome.

-- Former game passes. Every perk is built in and free for every player: there is no
-- Marketplace pass, no id, no price and no ownership check.
export type Perk = {
	key: string,
	name: string,
	description: string,
	icon: string,
}

export type Product = {
	key: string,
	id: number,
	name: string,
	gems: number,
}

export type OfferGrant = {
	kind: "pet" | "boost",
	species: string?,
	material: string?,
	size: string?,
	boost: string?,
	seconds: number?,
}

export type GemOffer = {
	key: string,
	name: string,
	description: string,
	gems: number,
	grant: OfferGrant,
}

local MonetizationConfig = {}

MonetizationConfig.FreePerks = {
	{ key = "DoubleCoins", name = "Double Coins", description = "Your plot earns 2x coins.", icon = "2x" },
	{ key = "EarlyAutoThrow", name = "Auto-Throw", description = "Use Auto-Throw from the start.", icon = "A" },
	{ key = "BigBackpack", name = "Big Backpack", description = "Hold 150 more pets.", icon = "+" },
	{ key = "GoldenTrail", name = "Golden Trail", description = "A gold trail behind every snack.", icon = "*" },
} :: { Perk }

-- The perk set every session gets (a fresh table each time, never saved).
function MonetizationConfig.allPerks(): { [string]: boolean }
	local t = {}
	for _, p in MonetizationConfig.FreePerks do
		t[p.key] = true
	end
	return t
end

MonetizationConfig.Products = {
	{ key = "GemsSmall", id = 0, name = "Pouch of Gems", gems = 100 },
	{ key = "GemsMedium", id = 0, name = "Sack of Gems", gems = 550 },
	{ key = "GemsLarge", id = 0, name = "Chest of Gems", gems = 1200 },
} :: { Product }

-- Fixed-content Gem offers. What you see is exactly what you get.
MonetizationConfig.GemOffers = {
	{
		key = "GoldLionCub",
		name = "Gold Lion Cub",
		description = "One Lion Cub with the Gold material.",
		gems = 250,
		grant = { kind = "pet", species = "LionCub", material = "Gold", size = "Normal" },
	},
	{
		key = "HugeElephant",
		name = "Huge Baby Elephant",
		description = "One Baby Elephant, Huge size.",
		gems = 600,
		grant = { kind = "pet", species = "Elephant", material = "Normal", size = "Huge" },
	},
	{
		key = "CoinRush",
		name = "Coin Rush (30 min)",
		description = "Your plot earns 2x coins for 30 minutes. Stacks up to 24 hours.",
		gems = 120,
		grant = { kind = "boost", boost = "CoinRush", seconds = 30 * 60 },
	},
} :: { GemOffer }

-- Which currencies can be bought with Robux. Anything with a random outcome must never
-- be priced in one of these (enforced by EggConfig validation and the test-suite); if
-- that ever changes, the server's PolicyService gate applies automatically.
MonetizationConfig.PurchasableCurrencies = { Gems = true }
MonetizationConfig.EarnOnlyCurrencies = { Coins = true, PawTokens = true }

MonetizationConfig.BackpackBonus = 150
MonetizationConfig.DoubleCoinsMult = 2
MonetizationConfig.CoinRushMult = 2
MonetizationConfig.MaxBoostSeconds = 24 * 3600
MonetizationConfig.MaxReceipts = 500 -- newest purchase ids kept in the save for idempotency

local offersByKey: { [string]: GemOffer } = {}
for _, o in MonetizationConfig.GemOffers do
	offersByKey[o.key] = o
end

function MonetizationConfig.isConfigured(id: any): boolean
	return type(id) == "number" and id > 0 and id == math.floor(id)
end

-- Lookups read the lists live (they are tiny), so an id filled in later is picked up and
-- an unset id (0) can never match a real purchase.

function MonetizationConfig.getProduct(key: any): Product?
	for _, p in MonetizationConfig.Products do
		if p.key == key then
			return p
		end
	end
	return nil
end

function MonetizationConfig.productById(id: any): Product?
	if not MonetizationConfig.isConfigured(id) then
		return nil
	end
	for _, p in MonetizationConfig.Products do
		if p.id == id then
			return p
		end
	end
	return nil
end

function MonetizationConfig.getOffer(key: any): GemOffer?
	return if type(key) == "string" then offersByKey[key] else nil
end

return MonetizationConfig
