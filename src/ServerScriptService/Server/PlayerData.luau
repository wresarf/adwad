--!strict
-- Save schema, defaults and defensive sanitising of anything loaded from the DataStore.
-- Pure (no services) so it is covered by the offline test-suite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))

export type Settings = {
	AutoThrow: boolean,
	AutoSkipRarity: string, -- rarity name or "Off"
	KeepMutated: boolean,
	ShowCutscenes: boolean,
	ShowGuide: boolean,
	ReduceMotion: boolean,
	AutoSellRarity: string, -- rarity name or "Off"
}

-- Lifetime counters used by quests (Shared/Progression.statValue).
export type Stats = {
	trains: number,
	sweetSpots: number,
	cravingMatches: number,
	bestStreak: number,
	mutations: number,
	fusions: number,
	bestRarity: number,
	eggsHatched: number,
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
	stats: Stats,
	questIndex: number,
	zonesReached: { [string]: boolean },
	lastOnline: number, -- os.time() of the last save, for offline earnings
	-- v3
	gems: number, -- the only Robux-purchasable currency
	pawTokens: number, -- earn-only egg currency
	receipts: { [string]: number }, -- PurchaseId -> os.time() granted (idempotency)
	boosts: { [string]: number }, -- boost id -> os.time() it expires
}

local PlayerData = {}

PlayerData.StatKeys = { "trains", "sweetSpots", "cravingMatches", "bestStreak", "mutations", "fusions", "bestRarity", "eggsHatched" }
PlayerData.BoostIds = { "CoinRush" }
-- Highest pet count a save may hold (Big Backpack owners). Capacity for new pets is
-- enforced per session, so a save is never truncated just because a pass check failed.
PlayerData.MaxStoredPets = GameConfig.MaxPets + MonetizationConfig.BackpackBonus

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
			ShowGuide = true,
			ReduceMotion = false,
			AutoSellRarity = "Off",
		},
		stats = {
			trains = 0,
			sweetSpots = 0,
			cravingMatches = 0,
			bestStreak = 0,
			mutations = 0,
			fusions = 0,
			bestRarity = 0,
			eggsHatched = 0,
		},
		questIndex = 1,
		zonesReached = {},
		lastOnline = 0,
		gems = 0,
		pawTokens = 0,
		receipts = {},
		boosts = {},
	}
end

-- Records a granted purchase and trims the oldest records beyond MaxReceipts.
function PlayerData.recordReceipt(data: Data, purchaseId: string, now: number)
	data.receipts[purchaseId] = now
	local n = 0
	for _ in data.receipts do
		n += 1
	end
	if n <= MonetizationConfig.MaxReceipts then
		return
	end
	local list = {}
	for id, t in data.receipts do
		table.insert(list, { id = id, t = t })
	end
	table.sort(list, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.id < b.id
	end)
	for i = 1, n - MonetizationConfig.MaxReceipts do
		data.receipts[list[i].id] = nil
	end
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
			if #d.pets >= PlayerData.MaxStoredPets then
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
		-- Kept as saved: whether Auto-Throw may actually run (distance unlock or pass) is
		-- checked by the server every time.
		if type(s.AutoThrow) == "boolean" then
			d.settings.AutoThrow = s.AutoThrow
		end
		if type(s.ReduceMotion) == "boolean" then
			d.settings.ReduceMotion = s.ReduceMotion
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
		if type(s.ShowGuide) == "boolean" then
			d.settings.ShowGuide = s.ShowGuide
		end
		if PlayerData.isRarityOrOff(s.AutoSellRarity) then
			d.settings.AutoSellRarity = s.AutoSellRarity
		end
	end

	-- v2 fields (absent in v1 saves, which simply start the quest line from the top).
	if type(raw.stats) == "table" then
		for _, key in PlayerData.StatKeys do
			(d.stats :: any)[key] = math.floor(num(raw.stats[key], 0, 0, 1e12))
		end
	end
	d.stats.bestRarity = math.min(d.stats.bestRarity, #GameConfig.Rarities)
	d.questIndex = math.floor(num(raw.questIndex, 1, 1, #QuestConfig.Quests + 1))
	d.lastOnline = math.floor(num(raw.lastOnline, 0, 0, 1e11))
	if type(raw.zonesReached) == "table" then
		for _, zone in BiomeConfig.allCravingZones() do
			if raw.zonesReached[zone] == true then
				d.zonesReached[zone] = true
			end
		end
	end
	-- Zones already passed (e.g. v1 saves) never pay their first-landing reward again.
	for _, b in BiomeConfig.Biomes do
		if d.bestDistance > b.startDistance then
			d.zonesReached[b.id] = true
		end
	end
	if d.bestDistance >= BiomeConfig.SpaceDistance then
		d.zonesReached.Space = true
	end
	if d.bestDistance >= BiomeConfig.MoonDistance then
		d.zonesReached.Moon = true
	end

	-- v3 fields (absent in v1/v2 saves).
	d.gems = math.floor(num(raw.gems, 0, 0, 1e9))
	d.pawTokens = math.floor(num(raw.pawTokens, 0, 0, 1e6))
	if type(raw.receipts) == "table" then
		for id, t in raw.receipts do
			if type(id) == "string" and #id > 0 and #id <= 100 then
				d.receipts[id] = math.floor(num(t, 0, 0, 1e11))
			end
		end
		-- Re-apply the cap (and its oldest-first trimming) to whatever was loaded.
		local first = next(d.receipts)
		if first then
			PlayerData.recordReceipt(d, first, d.receipts[first])
		end
	end
	if type(raw.boosts) == "table" then
		for _, id in PlayerData.BoostIds do
			local v = raw.boosts[id]
			if type(v) == "number" then
				d.boosts[id] = math.floor(num(v, 0, 0, 1e11))
			end
		end
	end
	return d
end

return PlayerData
