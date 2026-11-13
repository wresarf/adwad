--!strict
-- Save schema, defaults and defensive sanitising of anything loaded from the DataStore.
-- Pure (no services) so it is covered by the offline test-suite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))

export type Settings = {
	AutoThrow: boolean,
	AutoSkipRarity: string, -- rarity name or "Off"
	KeepMutated: boolean,
	ShowCutscenes: boolean,
	AutoSellRarity: string, -- rarity name or "Off"
}

export type Data = {
	version: number,
	coins: number,
	strength: number,
	bestDistance: number,
	totalThrows: number,
	totalCatches: number,
	autoThrowUnlocked: boolean,
	ownedFoods: { [string]: boolean },
	equippedFood: string,
	pets: { any },
	nextUid: number,
	discovered: { [string]: boolean },
	settings: Settings,
}

local PlayerData = {}

function PlayerData.defaults(): Data
	return {
		version = GameConfig.DataVersion,
		coins = GameConfig.StartingCoins,
		strength = GameConfig.StartingStrength,
		bestDistance = 0,
		totalThrows = 0,
		totalCatches = 0,
		autoThrowUnlocked = false,
		ownedFoods = { [FoodConfig.DefaultFood] = true },
		equippedFood = FoodConfig.DefaultFood,
		pets = {},
		nextUid = 1,
		discovered = {},
		settings = {
			AutoThrow = false,
			AutoSkipRarity = "Epic",
			KeepMutated = true,
			ShowCutscenes = true,
			AutoSellRarity = "Off",
		},
	}
end

local function num(v: any, default: number, lo: number, hi: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return math.clamp(v, lo, hi)
end

function PlayerData.isRarityOrOff(v: any): boolean
	return v == "Off" or (type(v) == "string" and GameConfig.rarityIndex(v) > 0)
end

-- Accepts any value (possibly corrupt / older version) and returns a valid Data table.
function PlayerData.sanitize(raw: any): Data
	local d = PlayerData.defaults()
	if type(raw) ~= "table" then
		return d
	end
	d.coins = num(raw.coins, d.coins, 0, 1e15)
	d.strength = num(raw.strength, d.strength, 0, 1e9)
	d.bestDistance = num(raw.bestDistance, 0, 0, 1e7)
	d.totalThrows = math.floor(num(raw.totalThrows, 0, 0, 1e12))
	d.totalCatches = math.floor(num(raw.totalCatches, 0, 0, 1e12))
	d.autoThrowUnlocked = raw.autoThrowUnlocked == true or d.bestDistance >= GameConfig.AutoThrowUnlockDistance

	if type(raw.ownedFoods) == "table" then
		for id, owned in raw.ownedFoods do
			if owned == true and FoodConfig.get(id) then
				d.ownedFoods[id] = true
			end
		end
	end
	if FoodConfig.get(raw.equippedFood) and d.ownedFoods[raw.equippedFood] then
		d.equippedFood = raw.equippedFood
	end

	if type(raw.discovered) == "table" then
		for id, v in raw.discovered do
			if v == true and PetConfig.get(id) then
				d.discovered[id] = true
			end
		end
	end

	-- UIDs are reassigned on load so a corrupted save can never produce duplicates.
	d.nextUid = 1
	local equippedCount = 0
	if type(raw.pets) == "table" then
		for _, p in raw.pets do
			if #d.pets >= GameConfig.MaxPets then
				break
			end
			if type(p) == "table" and PetConfig.get(p.species) and MutationConfig.getMaterial(p.material) and MutationConfig.getSize(p.size) then
				local uid = "p" .. d.nextUid
				d.nextUid += 1
				local equipped = p.equipped == true and equippedCount < GameConfig.PlotPedestals
				if equipped then
					equippedCount += 1
				end
				table.insert(d.pets, {
					uid = uid,
					species = p.species,
					material = p.material,
					size = p.size,
					equipped = equipped,
					locked = p.locked == true,
				})
				d.discovered[p.species] = true
			end
		end
	end

	local s = raw.settings
	if type(s) == "table" then
		if type(s.AutoThrow) == "boolean" then
			d.settings.AutoThrow = s.AutoThrow and d.autoThrowUnlocked
		end
		if PlayerData.isRarityOrOff(s.AutoSkipRarity) then
			d.settings.AutoSkipRarity = s.AutoSkipRarity
		end
		if type(s.KeepMutated) == "boolean" then
			d.settings.KeepMutated = s.KeepMutated
		end
		if type(s.ShowCutscenes) == "boolean" then
			d.settings.ShowCutscenes = s.ShowCutscenes
		end
		if PlayerData.isRarityOrOff(s.AutoSellRarity) then
			d.settings.AutoSellRarity = s.AutoSellRarity
		end
	end
	return d
end

return PlayerData
