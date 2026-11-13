--!strict
-- The quest line doubles as onboarding: one active quest at a time, completed
-- automatically by the server (Shared/Progression evaluates it) and paid instantly.
-- `stat` names are resolved by Progression.statValue. `focus` tells the client where to
-- point the guide beam / which HUD button to pulse.

export type Quest = {
	id: string,
	title: string,
	hint: string,
	stat: string,
	target: number,
	reward: number,
	focus: string?, -- "ThrowLine" | "Gym" | "Shop" | "Pets" | "Index"
}

local QuestConfig = {}

QuestConfig.Quests = {
	{ id = "Train10", title = "Warm Up", hint = "Hold Q or TRAIN to build strength (2x inside the Gym!)", stat = "trains", target = 10, reward = 30, focus = "Gym" },
	{ id = "FirstThrow", title = "First Toss", hint = "Go to the Throw Line, hold E or THROW, then let go", stat = "throws", target = 1, reward = 40, focus = "ThrowLine" },
	{ id = "Sweet1", title = "Sweet Spot!", hint = "Let go while the meter is in the green SWEET zone", stat = "sweetSpots", target = 1, reward = 60, focus = "ThrowLine" },
	{ id = "Craving1", title = "Feed a Craving", hint = "Land in a biome that craves your snack (see Cravings board)", stat = "cravingMatches", target = 1, reward = 80, focus = "ThrowLine" },
	{ id = "Catch5", title = "Pet Pals", hint = "Catch 5 pets. Each one earns coins on your plot", stat = "catches", target = 5, reward = 100, focus = "ThrowLine" },
	{ id = "Strength300", title = "Getting Strong", hint = "Reach 300 strength. Stronger arms throw further", stat = "strength", target = 300, reward = 150, focus = "Gym" },
	{ id = "Food2", title = "Snack Upgrade", hint = "Buy the Meaty Bone in the Food Shop", stat = "foods", target = 2, reward = 150, focus = "Shop" },
	{ id = "Dunes", title = "Desert Run", hint = "Throw 200m to reach the Sizzle Dunes", stat = "distance", target = 200, reward = 300, focus = "ThrowLine" },
	{ id = "Streak3", title = "Combo x3", hint = "Match cravings on 3 throws in a row", stat = "bestStreak", target = 3, reward = 400, focus = "ThrowLine" },
	{ id = "Discover8", title = "Collector", hint = "Discover 8 different species (check the Pet Index)", stat = "discovered", target = 8, reward = 600, focus = "Index" },
	{ id = "Mutation1", title = "Mutant Catch", hint = "Catch a Gold+ material or Huge+ size pet", stat = "mutations", target = 1, reward = 500, focus = "ThrowLine" },
	{ id = "Fuse1", title = "Fusion!", hint = "Fuse 3 identical pets in Pets & Fuse", stat = "fusions", target = 1, reward = 800, focus = "Pets" },
	{ id = "Income50", title = "Pet Tycoon", hint = "Earn 50 coins/sec. Use Equip Best on your plot", stat = "income", target = 50, reward = 1000, focus = "Pets" },
	{ id = "Tundra", title = "Brrr!", hint = "Throw 450m to reach Frostbite Peaks", stat = "distance", target = 450, reward = 2500, focus = "ThrowLine" },
	{ id = "Food4", title = "Gourmet", hint = "Own 4 snacks from the Food Shop", stat = "foods", target = 4, reward = 4000, focus = "Shop" },
	{ id = "Volcano", title = "Hot Stuff", hint = "Throw 800m to reach the Magma Fields", stat = "distance", target = 800, reward = 8000, focus = "ThrowLine" },
	{ id = "Epic1", title = "Epic Find", hint = "Catch an Epic or rarer pet", stat = "bestRarity", target = 4, reward = 10000, focus = "ThrowLine" },
	{ id = "Swamp", title = "Toxic Toss", hint = "Throw 1,250m to reach the Toxic Swamp and unlock Auto-Throw", stat = "distance", target = 1250, reward = 25000, focus = "ThrowLine" },
	{ id = "Streak8", title = "Max Combo", hint = "Reach an 8-throw streak for 10x mutation odds", stat = "bestStreak", target = 8, reward = 40000, focus = "ThrowLine" },
	{ id = "Nuclear", title = "Hazard Zone", hint = "Throw 1,800m to reach the Nuclear Wasteland", stat = "distance", target = 1800, reward = 80000, focus = "ThrowLine" },
	{ id = "Space", title = "Lift Off", hint = "Throw 2,500m to leave the planet!", stat = "distance", target = 2500, reward = 150000, focus = "ThrowLine" },
	{ id = "Moon", title = "Moonshot", hint = "Throw 3,600m to land on the Moon", stat = "distance", target = 3600, reward = 400000, focus = "ThrowLine" },
	{ id = "Discover25", title = "Snack Force Legend", hint = "Discover 25 species", stat = "discovered", target = 25, reward = 1000000, focus = "Index" },
} :: { Quest }

QuestConfig.Stats = {
	"trains",
	"throws",
	"sweetSpots",
	"cravingMatches",
	"catches",
	"strength",
	"foods",
	"distance",
	"bestStreak",
	"discovered",
	"mutations",
	"fusions",
	"income",
	"bestRarity",
}

function QuestConfig.get(index: number): Quest?
	return QuestConfig.Quests[index]
end

return QuestConfig
