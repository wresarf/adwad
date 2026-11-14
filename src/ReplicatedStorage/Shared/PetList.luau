--!strict
-- Pure helpers for the Pets panel: group identical pets, filter, sort and compare a group
-- with what is on the plot. Shared so the test-suite checks the same logic the UI uses.

local Config = script.Parent.Parent:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local GameMath = require(script.Parent:WaitForChild("GameMath"))

export type Group = {
	key: string,
	rec: any,
	count: number,
	equipped: number,
	income: number,
	rarityIndex: number,
	locked: boolean,
	mutated: boolean,
}

local PetList = {}

PetList.Filters = { "All", "On plot", "Backpack", "Mutated", "Locked" }
PetList.Sorts = { "Income", "Rarity", "Count", "Newest" }

function PetList.group(pets: { any }): ({ Group }, { [string]: Group })
	local byKey: { [string]: Group } = {}
	local order: { Group } = {}
	for i, p in pets do
		local key = GameMath.fuseKey(p)
		local g: any = byKey[key]
		if not g then
			local _, rIdx = GameMath.overallRarity(p)
			g = { key = key, rec = p, count = 0, equipped = 0, income = GameMath.petIncome(p), rarityIndex = rIdx, locked = true, mutated = GameMath.isMutated(p), newest = i }
			byKey[key] = g
			table.insert(order, g)
		end
		g.count += 1
		if p.equipped then
			g.equipped += 1
		end
		if not p.locked then
			g.locked = false
		end
		(g :: any).newest = i
	end
	return order, byKey
end

function PetList.matches(g: Group, filter: string): boolean
	if filter == "On plot" then
		return g.equipped > 0
	elseif filter == "Backpack" then
		return g.equipped < g.count
	elseif filter == "Mutated" then
		return g.mutated
	elseif filter == "Locked" then
		return g.locked
	end
	return true
end

function PetList.view(groups: { Group }, filter: string, sort: string): { Group }
	local out = {}
	for _, g in groups do
		if PetList.matches(g, filter) then
			table.insert(out, g)
		end
	end
	table.sort(out, function(a, b)
		if sort == "Rarity" and a.rarityIndex ~= b.rarityIndex then
			return a.rarityIndex > b.rarityIndex
		elseif sort == "Count" and a.count ~= b.count then
			return a.count > b.count
		elseif sort == "Newest" and (a :: any).newest ~= (b :: any).newest then
			return (a :: any).newest > (b :: any).newest
		end
		if a.income ~= b.income then
			return a.income > b.income
		end
		return a.key < b.key
	end)
	return out
end

-- Lowest income among pets on the plot, or nil when the plot has free slots.
function PetList.weakestOnPlot(pets: { any }, slots: number): number?
	local n, low = 0, math.huge
	for _, p in pets do
		if p.equipped then
			n += 1
			low = math.min(low, GameMath.petIncome(p))
		end
	end
	if n < slots then
		return nil
	end
	return low
end

-- How a group compares with the plot ("+X/s vs. weakest on plot", ...). Short: one line.
-- Returns (text, better) where better = placing it would raise income.
function PetList.compare(g: Group, pets: { any }, slots: number?): (string, boolean)
	local s = slots or GameConfig.PlotPedestals
	if g.equipped == g.count then
		return "All on your plot", false
	end
	local weakest = PetList.weakestOnPlot(pets, s)
	if not weakest then
		return "Free slot on your plot", true
	end
	local diff = g.income - weakest
	if diff > 1e-9 then
		return string.format("+%s/s vs. weakest on plot", GameMath.formatNumber(diff)), true
	elseif diff < -1e-9 then
		return string.format("−%s/s vs. weakest on plot", GameMath.formatNumber(-diff)), false
	end
	return "Same as weakest on plot", false
end

-- True when some backpack pet would beat the weakest plot pet (or a slot is free).
function PetList.upgradeAvailable(pets: { any }, slots: number): boolean
	local weakest = PetList.weakestOnPlot(pets, slots)
	for _, p in pets do
		if not p.equipped then
			if weakest == nil or GameMath.petIncome(p) > weakest + 1e-9 then
				return true
			end
		end
	end
	return false
end

return PetList
