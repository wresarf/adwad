--!strict
-- Six throw biomes laid out along +Z starting at the Throw Line (Z = 0).
-- Distance in "meters" equals studs along Z. Each biome bends the flight:
--   flightFactor = (1 + wind + gust) / gravity
-- Food passing through a biome travels flightFactor studs per unit of throw energy.

export type Biome = {
	id: string,
	name: string,
	order: number,
	startDistance: number,
	endDistance: number,
	wind: number,
	gust: number,
	gravity: number,
	groundColor: Color3,
	accentColor: Color3,
	material: Enum.Material,
	cravings: { string },
	description: string,
	reward: number, -- coins for the first landing in this zone
	fogColor: Color3, -- client atmosphere tint while the camera is over this biome
	fogDensity: number,
}

local BiomeConfig = {}

BiomeConfig.Width = 360
BiomeConfig.Biomes = {
	{
		id = "Meadow",
		name = "Sunny Meadow",
		order = 1,
		startDistance = 0,
		endDistance = 200,
		wind = 0,
		gust = 0.02,
		gravity = 1,
		groundColor = Color3.fromRGB(110, 200, 90),
		accentColor = Color3.fromRGB(255, 230, 90),
		material = Enum.Material.Grass,
		cravings = { "Berry", "Meat" },
		description = "Calm breeze, normal gravity",
		reward = 0,
		fogColor = Color3.fromRGB(200, 225, 255),
		fogDensity = 0.26,
	},
	{
		id = "Dunes",
		name = "Sizzle Dunes",
		order = 2,
		startDistance = 200,
		endDistance = 450,
		wind = 0.08,
		gust = 0.04,
		gravity = 1,
		groundColor = Color3.fromRGB(235, 200, 120),
		accentColor = Color3.fromRGB(90, 170, 80),
		material = Enum.Material.Sand,
		cravings = { "Meat", "Spicy" },
		description = "Warm tailwind (+8%)",
		reward = 150,
		fogColor = Color3.fromRGB(255, 215, 160),
		fogDensity = 0.3,
	},
	{
		id = "Tundra",
		name = "Frostbite Peaks",
		order = 3,
		startDistance = 450,
		endDistance = 800,
		wind = -0.12,
		gust = 0.05,
		gravity = 1.05,
		groundColor = Color3.fromRGB(225, 240, 255),
		accentColor = Color3.fromRGB(140, 200, 255),
		material = Enum.Material.Snow,
		cravings = { "Berry", "Spicy" },
		description = "Icy headwind (-12%), heavy air",
		reward = 800,
		fogColor = Color3.fromRGB(230, 240, 255),
		fogDensity = 0.38,
	},
	{
		id = "Volcano",
		name = "Magma Fields",
		order = 4,
		startDistance = 800,
		endDistance = 1250,
		wind = 0.15,
		gust = 0.06,
		gravity = 1,
		groundColor = Color3.fromRGB(70, 45, 40),
		accentColor = Color3.fromRGB(255, 110, 30),
		material = Enum.Material.Basalt,
		cravings = { "Spicy", "Meat" },
		description = "Lava updrafts (+15%)",
		reward = 3000,
		fogColor = Color3.fromRGB(255, 120, 70),
		fogDensity = 0.36,
	},
	{
		id = "Swamp",
		name = "Toxic Swamp",
		order = 5,
		startDistance = 1250,
		endDistance = 1800,
		wind = -0.05,
		gust = 0.06,
		gravity = 0.9,
		groundColor = Color3.fromRGB(60, 90, 50),
		accentColor = Color3.fromRGB(150, 255, 60),
		material = Enum.Material.Mud,
		cravings = { "Berry", "Cosmic" },
		description = "Thick fumes (-5%), light gravity",
		reward = 10000,
		fogColor = Color3.fromRGB(140, 200, 90),
		fogDensity = 0.42,
	},
	{
		id = "Nuclear",
		name = "Nuclear Wasteland",
		order = 6,
		startDistance = 1800,
		endDistance = 2500,
		wind = 0.1,
		gust = 0.1,
		gravity = 0.7,
		groundColor = Color3.fromRGB(95, 100, 70),
		accentColor = Color3.fromRGB(210, 255, 40),
		material = Enum.Material.Slate,
		cravings = { "Cosmic", "Spicy", "Meat" },
		description = "Radioactive gusts, 0.7x gravity",
		reward = 30000,
		fogColor = Color3.fromRGB(200, 255, 90),
		fogDensity = 0.4,
	},
} :: { Biome }

-- Throws that fly past the last biome leave the planet.
BiomeConfig.SpaceDistance = 2500
BiomeConfig.MoonDistance = 3600
BiomeConfig.Celestial = {
	Space = { id = "Space", name = "Outer Space", color = Color3.fromRGB(40, 30, 90), cravings = { "Cosmic" }, reward = 75000 },
	Moon = { id = "Moon", name = "The Moon", color = Color3.fromRGB(200, 200, 215), cravings = { "Cosmic" }, reward = 200000 },
}

function BiomeConfig.get(id: string?): Biome?
	for _, b in BiomeConfig.Biomes do
		if b.id == id then
			return b
		end
	end
	return nil
end

function BiomeConfig.biomeAtDistance(distance: number): Biome
	for _, b in BiomeConfig.Biomes do
		if distance < b.endDistance then
			return b
		end
	end
	return BiomeConfig.Biomes[#BiomeConfig.Biomes]
end

-- Every biome plus the celestial landing zones, which also have cravings.
function BiomeConfig.allCravingZones(): { string }
	local list = {}
	for _, b in BiomeConfig.Biomes do
		table.insert(list, b.id)
	end
	table.insert(list, "Space")
	table.insert(list, "Moon")
	return list
end

function BiomeConfig.zoneName(zoneId: string?): string
	local b = BiomeConfig.get(zoneId)
	if b then
		return b.name
	end
	local c = if zoneId then (BiomeConfig.Celestial :: any)[zoneId] else nil
	return if c then c.name else (zoneId or "?")
end

function BiomeConfig.zoneReward(zoneId: string): number
	local b = BiomeConfig.get(zoneId)
	if b then
		return b.reward
	end
	local c = (BiomeConfig.Celestial :: any)[zoneId]
	return if c then c.reward else 0
end

function BiomeConfig.cravingOptions(zoneId: string): { string }
	local b = BiomeConfig.get(zoneId)
	if b then
		return b.cravings
	end
	local c = (BiomeConfig.Celestial :: any)[zoneId]
	if c then
		return c.cravings
	end
	return { "Berry" }
end

return BiomeConfig
