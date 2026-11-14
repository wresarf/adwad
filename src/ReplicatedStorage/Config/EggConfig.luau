--!strict
-- Exclusive Safari Eggs. They are opened with Paw Tokens, which can only be earned by
-- playing (never bought with Robux or Gems), and the odds below are shown in full before
-- every hatch. A hatch always gives a Normal / Normal pet: luck, weather, combos and
-- boosts never change egg odds, so the displayed table is the final table.

local Config = script.Parent
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))

export type EggEntry = { species: string, chance: number } -- chance in percent
export type Egg = {
	id: string,
	name: string,
	description: string,
	currency: string,
	cost: number,
	shell: Color3,
	spots: Color3,
	entries: { EggEntry },
}

local EggConfig = {}

EggConfig.Currency = "PawTokens"
EggConfig.CurrencyName = "Paw Tokens"

-- How Paw Tokens are earned (server-side only).
EggConfig.TokenRewards = {
	Quest = 1, -- every quest completed
	ZoneFirst = 2, -- first landing in each zone
	NewSpecies = 1, -- first catch of a species
	CatchMilestone = 1, -- every CatchMilestoneEvery catches
}
EggConfig.CatchMilestoneEvery = 50

EggConfig.Eggs = {
	{
		id = "SafariEgg",
		name = "Safari Egg",
		description = "Savanna friends you can't catch by throwing.",
		currency = "PawTokens",
		cost = 3,
		shell = Color3.fromRGB(240, 226, 196),
		spots = Color3.fromRGB(150, 110, 70),
		entries = {
			{ species = "ZebraFoal", chance = 45 },
			{ species = "Hippo", chance = 30 },
			{ species = "Toucan", chance = 20 },
			{ species = "LionCub", chance = 5 },
		},
	},
	{
		id = "RoyalEgg",
		name = "Royal Savanna Egg",
		description = "The rarest residents of the park.",
		currency = "PawTokens",
		cost = 10,
		shell = Color3.fromRGB(246, 214, 140),
		spots = Color3.fromRGB(196, 120, 60),
		entries = {
			{ species = "Giraffe", chance = 60 },
			{ species = "Elephant", chance = 32 },
			{ species = "SunmaneLion", chance = 8 },
		},
	},
} :: { Egg }

local byId: { [string]: Egg } = {}
for _, e in EggConfig.Eggs do
	byId[e.id] = e
end

function EggConfig.get(id: any): Egg?
	return if type(id) == "string" then byId[id] else nil
end

-- True when an egg's price can be paid (directly or indirectly) with Robux. Such eggs are
-- "paid random items" and the server gates them behind PolicyService.
function EggConfig.isPaidRandom(egg: Egg): boolean
	return MonetizationConfig.PurchasableCurrencies[egg.currency] == true
end

-- Server-side gate for a hatch. `wallet` maps currency -> balance. Paid random eggs
-- (priced in a Robux-purchasable currency) are refused whenever PolicyService says paid
-- random items are restricted for the player, or the policy could not be read.
function EggConfig.hatchCheck(egg: Egg, wallet: { [string]: number }, paidRandomRestricted: boolean): (boolean, string)
	if EggConfig.isPaidRandom(egg) and paidRandomRestricted then
		return false, "This egg isn't available in your region"
	end
	if not MonetizationConfig.EarnOnlyCurrencies[egg.currency] and not MonetizationConfig.PurchasableCurrencies[egg.currency] then
		return false, "This egg isn't available"
	end
	local balance = wallet[egg.currency] or 0
	if balance < egg.cost then
		local name = if egg.currency == EggConfig.Currency then EggConfig.CurrencyName else egg.currency
		return false, string.format("Need %d more %s", egg.cost - balance, name)
	end
	return true, ""
end

-- Picks an entry for a uniform roll r in [0, 1).
function EggConfig.pick(egg: Egg, r: number): string
	local acc = 0
	local target = math.clamp(r, 0, 0.999999) * 100
	for _, e in egg.entries do
		acc += e.chance
		if target < acc then
			return e.species
		end
	end
	return egg.entries[#egg.entries].species
end

-- Returns a list of problems (empty = valid). Run by the test-suite and at server start.
function EggConfig.validate(): { string }
	local problems = {}
	for _, egg in EggConfig.Eggs do
		local total = 0
		for _, e in egg.entries do
			total += e.chance
			local pet = PetConfig.get(e.species)
			if not pet then
				table.insert(problems, egg.id .. ": unknown species " .. e.species)
			elseif pet.zone ~= PetConfig.EggZone then
				table.insert(problems, egg.id .. ": " .. e.species .. " is not egg-exclusive")
			end
		end
		if math.abs(total - 100) > 1e-9 then
			table.insert(problems, string.format("%s: odds sum to %s%%, not 100%%", egg.id, tostring(total)))
		end
		if not MonetizationConfig.EarnOnlyCurrencies[egg.currency] and not MonetizationConfig.PurchasableCurrencies[egg.currency] then
			table.insert(problems, egg.id .. ": unknown currency " .. egg.currency)
		end
		if egg.cost <= 0 or egg.cost ~= math.floor(egg.cost) then
			table.insert(problems, egg.id .. ": cost must be a positive integer")
		end
	end
	return problems
end

return EggConfig
