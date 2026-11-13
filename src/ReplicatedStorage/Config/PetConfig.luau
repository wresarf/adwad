--!strict
-- Every pet species. Pets are built procedurally from parts (no Toolbox assets) by
-- Shared/PetModelBuilder using `archetype`, `bodyColor` and `accentColor`.

export type Pet = {
	id: string,
	name: string,
	zone: string, -- biome id or "Space" / "Moon"
	rarity: string,
	baseIncome: number,
	craving: string,
	archetype: string,
	bodyColor: Color3,
	accentColor: Color3,
}

local PetConfig = {}

-- Relative catch weights by rarity inside one landing zone.
PetConfig.RarityWeights = {
	Common = 60,
	Uncommon = 26,
	Rare = 10,
	Epic = 3.2,
	Legendary = 0.7,
	Mythic = 0.1,
	Secret = 0.02,
}
-- Pets whose craving matches the thrown food are this much more likely.
PetConfig.CravingWeightBonus = 2.5

PetConfig.Archetypes = { "Pup", "Kitty", "Bunny", "Chick", "Slime", "Dragon", "Bear", "Frog" }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

PetConfig.Pets = {
	-- Sunny Meadow
	{ id = "MeadowPup", name = "Meadow Pup", zone = "Meadow", rarity = "Common", baseIncome = 1, craving = "Meat", archetype = "Pup", bodyColor = rgb(230, 190, 140), accentColor = rgb(140, 90, 60) },
	{ id = "Bunbun", name = "Bunbun", zone = "Meadow", rarity = "Common", baseIncome = 1.2, craving = "Berry", archetype = "Bunny", bodyColor = rgb(250, 250, 250), accentColor = rgb(255, 170, 200) },
	{ id = "Chirpy", name = "Chirpy", zone = "Meadow", rarity = "Uncommon", baseIncome = 2, craving = "Berry", archetype = "Chick", bodyColor = rgb(255, 230, 80), accentColor = rgb(255, 150, 40) },
	{ id = "Honeybear", name = "Honeybear", zone = "Meadow", rarity = "Rare", baseIncome = 4, craving = "Berry", archetype = "Bear", bodyColor = rgb(200, 140, 60), accentColor = rgb(255, 210, 90) },
	{ id = "CloverCat", name = "Clover Cat", zone = "Meadow", rarity = "Epic", baseIncome = 9, craving = "Meat", archetype = "Kitty", bodyColor = rgb(120, 220, 120), accentColor = rgb(40, 130, 60) },
	-- Sizzle Dunes
	{ id = "Sandpup", name = "Sandpup", zone = "Dunes", rarity = "Common", baseIncome = 4, craving = "Meat", archetype = "Pup", bodyColor = rgb(240, 210, 150), accentColor = rgb(200, 150, 90) },
	{ id = "CactiFrog", name = "Cacti Frog", zone = "Dunes", rarity = "Common", baseIncome = 4.5, craving = "Spicy", archetype = "Frog", bodyColor = rgb(100, 180, 80), accentColor = rgb(255, 120, 170) },
	{ id = "Fennek", name = "Fennek", zone = "Dunes", rarity = "Uncommon", baseIncome = 7, craving = "Meat", archetype = "Kitty", bodyColor = rgb(255, 180, 100), accentColor = rgb(255, 245, 220) },
	{ id = "ScarabSlime", name = "Scarab Slime", zone = "Dunes", rarity = "Rare", baseIncome = 13, craving = "Spicy", archetype = "Slime", bodyColor = rgb(60, 160, 170), accentColor = rgb(255, 210, 60) },
	{ id = "SunDrake", name = "Sun Drake", zone = "Dunes", rarity = "Legendary", baseIncome = 45, craving = "Spicy", archetype = "Dragon", bodyColor = rgb(255, 170, 40), accentColor = rgb(255, 90, 40) },
	-- Frostbite Peaks
	{ id = "Snowpuff", name = "Snowpuff", zone = "Tundra", rarity = "Common", baseIncome = 12, craving = "Berry", archetype = "Bunny", bodyColor = rgb(235, 245, 255), accentColor = rgb(150, 200, 255) },
	{ id = "Penguino", name = "Penguino", zone = "Tundra", rarity = "Common", baseIncome = 13, craving = "Berry", archetype = "Chick", bodyColor = rgb(40, 50, 70), accentColor = rgb(255, 160, 40) },
	{ id = "FrostCub", name = "Frost Cub", zone = "Tundra", rarity = "Uncommon", baseIncome = 20, craving = "Spicy", archetype = "Bear", bodyColor = rgb(250, 250, 255), accentColor = rgb(120, 180, 240) },
	{ id = "IcicleCat", name = "Icicle Cat", zone = "Tundra", rarity = "Epic", baseIncome = 55, craving = "Spicy", archetype = "Kitty", bodyColor = rgb(150, 220, 255), accentColor = rgb(60, 120, 220) },
	{ id = "YetiPup", name = "Yeti Pup", zone = "Tundra", rarity = "Legendary", baseIncome = 120, craving = "Berry", archetype = "Pup", bodyColor = rgb(220, 230, 240), accentColor = rgb(80, 140, 220) },
	-- Magma Fields
	{ id = "EmberPup", name = "Ember Pup", zone = "Volcano", rarity = "Common", baseIncome = 35, craving = "Spicy", archetype = "Pup", bodyColor = rgb(200, 60, 30), accentColor = rgb(255, 180, 40) },
	{ id = "LavaSlime", name = "Lava Slime", zone = "Volcano", rarity = "Common", baseIncome = 38, craving = "Meat", archetype = "Slime", bodyColor = rgb(255, 100, 20), accentColor = rgb(255, 230, 80) },
	{ id = "CinderToad", name = "Cinder Toad", zone = "Volcano", rarity = "Uncommon", baseIncome = 60, craving = "Spicy", archetype = "Frog", bodyColor = rgb(80, 40, 40), accentColor = rgb(255, 90, 0) },
	{ id = "MagmaBear", name = "Magma Bear", zone = "Volcano", rarity = "Rare", baseIncome = 110, craving = "Meat", archetype = "Bear", bodyColor = rgb(60, 30, 30), accentColor = rgb(255, 120, 30) },
	{ id = "PyroDragon", name = "Pyro Dragon", zone = "Volcano", rarity = "Mythic", baseIncome = 900, craving = "Spicy", archetype = "Dragon", bodyColor = rgb(200, 30, 30), accentColor = rgb(255, 200, 40) },
	-- Toxic Swamp
	{ id = "GoopSlime", name = "Goop Slime", zone = "Swamp", rarity = "Common", baseIncome = 100, craving = "Berry", archetype = "Slime", bodyColor = rgb(140, 230, 60), accentColor = rgb(60, 120, 30) },
	{ id = "BogFrog", name = "Bog Frog", zone = "Swamp", rarity = "Common", baseIncome = 110, craving = "Berry", archetype = "Frog", bodyColor = rgb(80, 130, 60), accentColor = rgb(200, 255, 80) },
	{ id = "MireKitty", name = "Mire Kitty", zone = "Swamp", rarity = "Uncommon", baseIncome = 170, craving = "Cosmic", archetype = "Kitty", bodyColor = rgb(100, 70, 140), accentColor = rgb(170, 255, 70) },
	{ id = "SporeBun", name = "Spore Bun", zone = "Swamp", rarity = "Epic", baseIncome = 450, craving = "Berry", archetype = "Bunny", bodyColor = rgb(200, 120, 220), accentColor = rgb(120, 255, 120) },
	{ id = "HydraLing", name = "Hydraling", zone = "Swamp", rarity = "Legendary", baseIncome = 1000, craving = "Cosmic", archetype = "Dragon", bodyColor = rgb(50, 160, 90), accentColor = rgb(220, 255, 60) },
	-- Nuclear Wasteland
	{ id = "RadPup", name = "Rad Pup", zone = "Nuclear", rarity = "Common", baseIncome = 300, craving = "Meat", archetype = "Pup", bodyColor = rgb(170, 200, 60), accentColor = rgb(60, 60, 60) },
	{ id = "GlowSlime", name = "Glow Slime", zone = "Nuclear", rarity = "Common", baseIncome = 320, craving = "Cosmic", archetype = "Slime", bodyColor = rgb(210, 255, 40), accentColor = rgb(40, 80, 20) },
	{ id = "MutantChick", name = "Mutant Chick", zone = "Nuclear", rarity = "Uncommon", baseIncome = 500, craving = "Spicy", archetype = "Chick", bodyColor = rgb(200, 255, 120), accentColor = rgb(255, 60, 160) },
	{ id = "IsotopeBear", name = "Isotope Bear", zone = "Nuclear", rarity = "Epic", baseIncome = 1400, craving = "Cosmic", archetype = "Bear", bodyColor = rgb(90, 110, 60), accentColor = rgb(230, 255, 40) },
	{ id = "FalloutDrake", name = "Fallout Drake", zone = "Nuclear", rarity = "Mythic", baseIncome = 7000, craving = "Meat", archetype = "Dragon", bodyColor = rgb(60, 70, 50), accentColor = rgb(210, 255, 40) },
	-- Outer Space (throws past the Wasteland)
	{ id = "AstroPup", name = "Astro Pup", zone = "Space", rarity = "Rare", baseIncome = 2500, craving = "Cosmic", archetype = "Pup", bodyColor = rgb(240, 240, 255), accentColor = rgb(80, 120, 255) },
	{ id = "Cometkit", name = "Cometkit", zone = "Space", rarity = "Epic", baseIncome = 5000, craving = "Cosmic", archetype = "Kitty", bodyColor = rgb(60, 40, 120), accentColor = rgb(120, 220, 255) },
	{ id = "Nebulite", name = "Nebulite", zone = "Space", rarity = "Legendary", baseIncome = 12000, craving = "Spicy", archetype = "Slime", bodyColor = rgb(170, 70, 255), accentColor = rgb(255, 120, 220) },
	-- The Moon
	{ id = "MoonBun", name = "Moon Bun", zone = "Moon", rarity = "Epic", baseIncome = 15000, craving = "Cosmic", archetype = "Bunny", bodyColor = rgb(220, 220, 235), accentColor = rgb(160, 160, 190) },
	{ id = "LunarDragon", name = "Lunar Dragon", zone = "Moon", rarity = "Mythic", baseIncome = 60000, craving = "Cosmic", archetype = "Dragon", bodyColor = rgb(200, 210, 255), accentColor = rgb(255, 250, 200) },
	{ id = "VoidEmperor", name = "Void Emperor", zone = "Moon", rarity = "Secret", baseIncome = 250000, craving = "Cosmic", archetype = "Bear", bodyColor = rgb(20, 10, 40), accentColor = rgb(255, 60, 255) },
} :: { Pet }

local byId: { [string]: Pet } = {}
local byZone: { [string]: { Pet } } = {}
for _, p in PetConfig.Pets do
	byId[p.id] = p
	local list = byZone[p.zone]
	if not list then
		list = {}
		byZone[p.zone] = list
	end
	table.insert(list, p)
end

function PetConfig.get(id: string?): Pet?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function PetConfig.forZone(zoneId: string): { Pet }
	return byZone[zoneId] or {}
end

return PetConfig
