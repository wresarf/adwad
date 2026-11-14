--!strict
-- Global tuning shared by server (authoritative) and client (visuals only).

export type Weather = {
	id: string,
	name: string,
	description: string,
	sizeLuck: number,
	materialLuck: number,
	cravingBonus: number,
	color: Color3,
}

local GameConfig = {}

GameConfig.DataStoreName = "SnackForce_PetToss_v1"
GameConfig.DataVersion = 4
GameConfig.AutosaveInterval = 60

-- Charge meter: a triangle wave 0 -> 1 -> 0 over ChargeCycle seconds.
GameConfig.ChargeCycle = 1.6
GameConfig.SweetSpotMin = 0.9 -- charge >= this (up to 1.0) is a "sweet spot" release
GameConfig.SweetSpotDistanceMult = 1.25
GameConfig.SweetSpotLuckMult = 1.35
GameConfig.MinChargeTime = 0.12
GameConfig.MaxChargeTime = 12

-- Throwing
GameConfig.BaseThrowDistance = 40
GameConfig.StrengthDistanceScale = 2.5 -- distance += sqrt(strength) * scale
GameConfig.MinChargeFactor = 0.35 -- charge 0 still throws 35% distance
GameConfig.ThrowCooldown = 0.75
GameConfig.ThrowLineRadius = 70 -- max studs from the Throw Line to throw manually
-- World anchors shared by server (validation) and client (guides, previews).
GameConfig.ThrowLineCenter = Vector3.new(0, 0, -12)
GameConfig.GymCenter = Vector3.new(-92, 0, -46)
GameConfig.GymRadius = 26
GameConfig.GymMultiplier = 2 -- training inside the Gym gives double strength

-- Auto-throw (late game)
GameConfig.AutoThrowUnlockDistance = 1250 -- reach Toxic Swamp to unlock
GameConfig.AutoThrowInterval = 3.5
GameConfig.AutoThrowCharge = 0.85 -- never a sweet spot: manual skill stays better

-- Training (holding TRAIN repeats at TrainRepeat seconds)
GameConfig.TrainCooldown = 0.12
GameConfig.TrainRepeat = 0.16

-- Economy
GameConfig.StartingCoins = 25
GameConfig.StartingStrength = 10
GameConfig.MaxPets = 150
GameConfig.PlotPedestals = 8
GameConfig.SellSeconds = 20 -- a pet sells for this many seconds of its income (min 5)
GameConfig.CravingMatchCoins = 15 -- base coin bonus for a craving match

-- Rewards
GameConfig.DiscoverySeconds = 40 -- first catch of a species pays this many seconds of its base income
GameConfig.DiscoveryMinCoins = 25
GameConfig.OfflineRate = 0.25 -- share of plot income earned while away
GameConfig.OfflineMinSeconds = 120
GameConfig.OfflineMaxSeconds = 2 * 3600
GameConfig.LeaderboardInterval = 5

-- Weather: an event starts every WeatherInterval seconds and lasts WeatherDuration.
GameConfig.WeatherInterval = 90
GameConfig.WeatherDuration = 45
GameConfig.FirstWeatherDelay = 90

GameConfig.Weather = {
	{
		id = "TitanStorm",
		name = "Titan Storm",
		description = "3x Size Luck!",
		sizeLuck = 3,
		materialLuck = 1,
		cravingBonus = 1,
		color = Color3.fromRGB(120, 90, 255),
	},
	{
		id = "FeastFrenzy",
		name = "Feast Frenzy",
		description = "2x Craving Bonus!",
		sizeLuck = 1,
		materialLuck = 1,
		cravingBonus = 2,
		color = Color3.fromRGB(255, 140, 60),
	},
	{
		id = "PrismAurora",
		name = "Prism Aurora",
		description = "4x Material Luck!",
		sizeLuck = 1,
		materialLuck = 4,
		cravingBonus = 1,
		color = Color3.fromRGB(60, 230, 200),
	},
} :: { Weather }

-- Remote rate limits: tokens per second and burst size.
GameConfig.RateLimits = {
	ThrowFood = { rate = 4, burst = 6 },
	TrainStrength = { rate = 12, burst = 15 },
	BuyFood = { rate = 4, burst = 6 },
	EquipBest = { rate = 2, burst = 3 },
	FusePets = { rate = 4, burst = 6 },
	AutoSell = { rate = 2, burst = 3 },
	ToggleSetting = { rate = 5, burst = 8 },
	StorePurchase = { rate = 2, burst = 4 },
	HatchEgg = { rate = 3, burst = 5 },
	ManagePet = { rate = 6, burst = 10 },
	BuyUpgrade = { rate = 4, burst = 6 },
}

GameConfig.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
GameConfig.RarityColors = {
	Common = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(90, 220, 110),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(180, 90, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Mythic = Color3.fromRGB(255, 70, 120),
	Secret = Color3.fromRGB(40, 255, 230),
}

function GameConfig.rarityIndex(name: string?): number
	if name == nil then
		return 0
	end
	for i, r in GameConfig.Rarities do
		if r == name then
			return i
		end
	end
	return 0
end

function GameConfig.getWeather(id: string?): Weather?
	if id == nil then
		return nil
	end
	for _, w in GameConfig.Weather do
		if w.id == id then
			return w
		end
	end
	return nil
end

return GameConfig
