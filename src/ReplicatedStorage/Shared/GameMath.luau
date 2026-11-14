--!strict
-- Pure game math (no services, no yielding) so it is shared by the authoritative server,
-- the client's preview UI and the offline Lune test-suite.

local Config = script.Parent.Parent:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))

export type Rng = () -> number -- returns [0, 1)

export type PetRecord = {
	uid: string,
	species: string,
	material: string,
	size: string,
	equipped: boolean?,
	locked: boolean?,
}

export type ThrowParams = {
	strength: number,
	foodPower: number,
	foodLuck: number,
	foodCraving: string,
	charge: number,
	allowSweetSpot: boolean,
	streak: number,
	zoneCravings: { [string]: string },
	weatherSizeLuck: number,
	weatherMaterialLuck: number,
	weatherCravingBonus: number,
	rng: Rng,
}

export type ThrowResult = {
	charge: number,
	sweetSpot: boolean,
	rawDistance: number,
	distance: number,
	zone: string,
	celestial: boolean,
	cravingMatched: boolean,
	zoneCraving: string,
	streak: number,
	comboMult: number,
	materialLuck: number,
	sizeLuck: number,
	species: string,
	material: string,
	size: string,
	bonusCoins: number,
}

local GameMath = {}

function GameMath.clamp(x: number, lo: number, hi: number): number
	if x ~= x then -- NaN guard
		return lo
	end
	return math.clamp(x, lo, hi)
end

-- Triangle wave 0 -> 1 -> 0. `elapsed` is seconds since the charge began.
function GameMath.chargeAt(elapsed: number): number
	local cycle = GameConfig.ChargeCycle
	local t = (math.max(elapsed, 0) % cycle) / cycle
	if t < 0.5 then
		return t * 2
	end
	return 2 - t * 2
end

function GameMath.isSweetSpot(charge: number): boolean
	return charge >= GameConfig.SweetSpotMin
end

function GameMath.rawDistance(strength: number, foodPower: number, charge: number, sweetSpot: boolean): number
	local base = GameConfig.BaseThrowDistance + math.sqrt(math.max(strength, 0)) * GameConfig.StrengthDistanceScale
	local chargeFactor = GameConfig.MinChargeFactor + (1 - GameConfig.MinChargeFactor) * GameMath.clamp(charge, 0, 1)
	local d = base * foodPower * chargeFactor
	if sweetSpot then
		d *= GameConfig.SweetSpotDistanceMult
	end
	return d
end

function GameMath.flightFactor(biome: BiomeConfig.Biome, gustRoll: number): number
	local wind = biome.wind + biome.gust * GameMath.clamp(gustRoll, -1, 1)
	return math.max(0.2, (1 + wind) / biome.gravity)
end

-- Walks the throw "energy" through each biome; wind/gravity stretch or shrink each segment.
-- Returns landing distance and the zone id (biome id, "Space" or "Moon").
function GameMath.resolveFlight(raw: number, gusts: { number }?): (number, string)
	local remaining = math.max(raw, 0)
	local pos = 0
	for i, biome in BiomeConfig.Biomes do
		local factor = GameMath.flightFactor(biome, if gusts then gusts[i] or 0 else 0)
		local length = biome.endDistance - biome.startDistance
		local reach = remaining * factor
		if reach < length then
			return pos + reach, biome.id
		end
		remaining -= length / factor
		pos += length
	end
	local distance = pos + remaining
	if distance >= BiomeConfig.MoonDistance then
		return distance, "Moon"
	end
	return distance, "Space"
end

function GameMath.comboMultiplier(streak: number): number
	local s = math.floor(GameMath.clamp(streak, 0, #MutationConfig.ComboMultipliers))
	return math.min(MutationConfig.ComboMultipliers[s] or 1, MutationConfig.MaxComboMultiplier)
end

function GameMath.nextStreak(streak: number, matched: boolean, cravingBonus: number): number
	if not matched then
		return 0
	end
	local step = math.max(1, math.floor(cravingBonus))
	return math.min(streak + step, #MutationConfig.ComboMultipliers)
end

local function rollTier<T>(list: { T }, rng: Rng, luck: number): T
	for i = #list, 2, -1 do
		local entry = list[i] :: any
		local chance = math.min(entry.chance * luck, MutationConfig.MaxChance)
		if rng() < chance then
			return list[i]
		end
	end
	return list[1]
end

function GameMath.rollMaterial(rng: Rng, luck: number): string
	return (rollTier(MutationConfig.Materials, rng, luck) :: MutationConfig.Material).id
end

function GameMath.rollSize(rng: Rng, luck: number): string
	return (rollTier(MutationConfig.Sizes, rng, luck) :: MutationConfig.Size).id
end

function GameMath.pickPet(rng: Rng, zoneId: string, foodCraving: string): PetConfig.Pet
	local pool = PetConfig.forZone(zoneId)
	if #pool == 0 then
		pool = PetConfig.forZone("Meadow")
	end
	local total = 0
	local weights = table.create(#pool, 0)
	for i, pet in pool do
		local w = (PetConfig.RarityWeights :: any)[pet.rarity] or 1
		if pet.craving == foodCraving then
			w *= PetConfig.CravingWeightBonus
		end
		weights[i] = w
		total += w
	end
	local roll = rng() * total
	for i, pet in pool do
		roll -= weights[i]
		if roll <= 0 then
			return pet
		end
	end
	return pool[#pool]
end

-- What the luck HUD shows, using exactly computeThrow's formula. The combo part depends
-- on where the snack lands, so both outcomes are returned: `base` (no craving match:
-- the streak resets) and `matched` (the streak grows). Sweet multiplies either one.
export type LuckPreview = { base: number, matched: number, sizeBase: number, sizeMatched: number, sweet: number, nextCombo: number }
function GameMath.luckPreview(foodLuck: number, streak: number, weatherMaterialLuck: number, weatherSizeLuck: number, weatherCravingBonus: number): LuckPreview
	local nextCombo = GameMath.comboMultiplier(GameMath.nextStreak(streak, true, weatherCravingBonus))
	local miss = GameMath.comboMultiplier(GameMath.nextStreak(streak, false, weatherCravingBonus))
	return {
		base = miss * weatherMaterialLuck * foodLuck,
		matched = nextCombo * weatherMaterialLuck * foodLuck,
		sizeBase = miss * weatherSizeLuck * foodLuck,
		sizeMatched = nextCombo * weatherSizeLuck * foodLuck,
		sweet = GameConfig.SweetSpotLuckMult,
		nextCombo = nextCombo,
	}
end

-- Training level: each level adds +1 strength per rep (trainGain). Returns the current
-- per-rep gain and the strength at which the next level starts.
function GameMath.trainLevel(strength: number): (number, number, number)
	local gain = GameMath.trainGain(strength)
	local prevAt = ((gain - 1) * 25) ^ 2
	local nextAt = (gain * 25) ^ 2
	return gain, prevAt, nextAt
end

function GameMath.computeThrow(p: ThrowParams, gusts: { number }?): ThrowResult
	local charge = GameMath.clamp(p.charge, 0, 1)
	local sweet = p.allowSweetSpot and GameMath.isSweetSpot(charge)
	local raw = GameMath.rawDistance(p.strength, p.foodPower, charge, sweet)
	local distance, zone = GameMath.resolveFlight(raw, gusts)
	local zoneCraving = p.zoneCravings[zone] or "Berry"
	local matched = zoneCraving == p.foodCraving
	local streak = GameMath.nextStreak(p.streak, matched, p.weatherCravingBonus)
	local combo = GameMath.comboMultiplier(streak)
	local sweetLuck = if sweet then GameConfig.SweetSpotLuckMult else 1
	local materialLuck = sweetLuck * combo * p.weatherMaterialLuck * p.foodLuck
	local sizeLuck = sweetLuck * combo * p.weatherSizeLuck * p.foodLuck
	local pet = GameMath.pickPet(p.rng, zone, p.foodCraving)
	local material = GameMath.rollMaterial(p.rng, materialLuck)
	local size = GameMath.rollSize(p.rng, sizeLuck)
	local bonus = 0
	if matched then
		bonus = math.floor(GameConfig.CravingMatchCoins * p.weatherCravingBonus * (1 + distance / 400))
	end
	return {
		charge = charge,
		sweetSpot = sweet,
		rawDistance = raw,
		distance = distance,
		zone = zone,
		celestial = zone == "Space" or zone == "Moon",
		cravingMatched = matched,
		zoneCraving = zoneCraving,
		streak = streak,
		comboMult = combo,
		materialLuck = materialLuck,
		sizeLuck = sizeLuck,
		species = pet.id,
		material = material,
		size = size,
		bonusCoins = bonus,
	}
end

function GameMath.petIncome(rec: { species: string, material: string, size: string }): number
	local pet = PetConfig.get(rec.species)
	local mat = MutationConfig.getMaterial(rec.material)
	local size = MutationConfig.getSize(rec.size)
	if not (pet and mat and size) then
		return 0
	end
	return pet.baseIncome * mat.incomeMult * size.incomeMult
end

function GameMath.sellValue(rec: { species: string, material: string, size: string }): number
	return math.max(5, math.floor(GameMath.petIncome(rec) * GameConfig.SellSeconds))
end

-- Overall rarity = best of species rarity, material rarity and size rarity.
function GameMath.overallRarity(rec: { species: string, material: string, size: string }): (string, number)
	local pet = PetConfig.get(rec.species)
	local mat = MutationConfig.getMaterial(rec.material)
	local size = MutationConfig.getSize(rec.size)
	local best = 1
	if pet then
		best = math.max(best, GameConfig.rarityIndex(pet.rarity))
	end
	if mat then
		best = math.max(best, GameConfig.rarityIndex(mat.rarity))
	end
	if size then
		best = math.max(best, GameConfig.rarityIndex(size.rarity))
	end
	return GameConfig.Rarities[best], best
end

function GameMath.isMutated(rec: { material: string, size: string }): boolean
	return rec.material ~= "Normal" or rec.size ~= "Normal"
end

function GameMath.fuseKey(rec: { species: string, material: string, size: string }): string
	return rec.species .. "|" .. rec.material .. "|" .. rec.size
end

function GameMath.trainGain(strength: number): number
	return 1 + math.floor(math.sqrt(math.max(strength, 0)) / 25)
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }
function GameMath.formatNumber(n: number): string
	if n ~= n then
		return "0"
	end
	local neg = n < 0
	n = math.abs(n)
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local s
	if i == 1 then
		s = tostring(math.floor(n))
	elseif n >= 100 then
		s = string.format("%d%s", math.floor(n), SUFFIXES[i])
	else
		s = string.format("%.1f%s", math.floor(n * 10) / 10, SUFFIXES[i])
	end
	return if neg then "-" .. s else s
end

return GameMath
