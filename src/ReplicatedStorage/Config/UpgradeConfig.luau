--!strict
-- Permanent upgrades bought with earned coins (never Gems or Robux). Each level has a
-- fixed, shown price and a fixed, shown effect. None of them touch mutation luck, the
-- sweet spot, combos or weather, so the odds the game describes elsewhere stay exact.

export type Upgrade = {
	id: string,
	name: string,
	icon: string,
	effect: string, -- short per-level effect, shown in the shop
	prices: { number }, -- price of level 1, 2, ... (#prices = max level)
	step: number, -- effect per level (meaning depends on the upgrade)
}

local UpgradeConfig = {}

UpgradeConfig.Upgrades = {
	{
		id = "Coach",
		name = "Training Coach",
		icon = "💪",
		effect = "+25% strength per training",
		prices = { 750, 6000, 45000, 300000 },
		step = 0.25,
	},
	{
		id = "CravingChef",
		name = "Craving Chef",
		icon = "🍳",
		effect = "+50% coins from craving matches",
		prices = { 1500, 20000, 200000 },
		step = 0.5,
	},
	{
		id = "NightShift",
		name = "Night Shift",
		icon = "🌙",
		effect = "+1 h of offline earnings",
		prices = { 2000, 25000, 250000 },
		step = 3600,
	},
} :: { Upgrade }

local byId: { [string]: Upgrade } = {}
for _, u in UpgradeConfig.Upgrades do
	byId[u.id] = u
end

function UpgradeConfig.get(id: any): Upgrade?
	return if type(id) == "string" then byId[id] else nil
end

function UpgradeConfig.maxLevel(u: Upgrade): number
	return #u.prices
end

-- Price of the next level, or nil when maxed.
function UpgradeConfig.nextPrice(u: Upgrade, level: number): number?
	return u.prices[level + 1]
end

local function level(levels: { [string]: number }?, id: string): number
	local v = levels and levels[id]
	return if type(v) == "number" then v else 0
end

function UpgradeConfig.trainMultiplier(levels: { [string]: number }?): number
	return 1 + level(levels, "Coach") * byId.Coach.step
end

function UpgradeConfig.cravingCoinMultiplier(levels: { [string]: number }?): number
	return 1 + level(levels, "CravingChef") * byId.CravingChef.step
end

function UpgradeConfig.offlineBonusSeconds(levels: { [string]: number }?): number
	return level(levels, "NightShift") * byId.NightShift.step
end

return UpgradeConfig
