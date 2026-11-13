--!strict
-- Foods are permanent unlocks: buy once, then equip freely. Better foods fly further.

export type Food = {
	id: string,
	name: string,
	craving: string,
	power: number,
	luck: number,
	price: number,
	color: Color3,
	shape: string, -- "Ball" | "Block" | "Cylinder" visual hint
	description: string,
}

local FoodConfig = {}

FoodConfig.Cravings = { "Berry", "Meat", "Spicy", "Cosmic" }
FoodConfig.CravingColors = {
	Berry = Color3.fromRGB(235, 70, 150),
	Meat = Color3.fromRGB(200, 110, 70),
	Spicy = Color3.fromRGB(255, 80, 30),
	Cosmic = Color3.fromRGB(130, 90, 255),
}
FoodConfig.CravingIcons = {
	Berry = "🍓",
	Meat = "🍖",
	Spicy = "🌶️",
	Cosmic = "🌌",
}

FoodConfig.DefaultFood = "BerryBite"

FoodConfig.Foods = {
	{ id = "BerryBite", name = "Berry Bite", craving = "Berry", power = 1.0, luck = 1.0, price = 0, color = Color3.fromRGB(230, 60, 120), shape = "Ball", description = "A squishy starter snack." },
	{ id = "MeatyBone", name = "Meaty Bone", craving = "Meat", power = 1.15, luck = 1.0, price = 400, color = Color3.fromRGB(240, 225, 200), shape = "Cylinder", description = "Every pup's favourite." },
	{ id = "ChiliPop", name = "Chili Pop", craving = "Spicy", power = 1.3, luck = 1.05, price = 3000, color = Color3.fromRGB(255, 60, 30), shape = "Ball", description = "Hot enough to fly further." },
	{ id = "StarCookie", name = "Star Cookie", craving = "Cosmic", power = 1.5, luck = 1.1, price = 20000, color = Color3.fromRGB(150, 110, 255), shape = "Block", description = "Baked under a shooting star." },
	{ id = "BerryTart", name = "Golden Berry Tart", craving = "Berry", power = 1.8, luck = 1.15, price = 120000, color = Color3.fromRGB(255, 200, 60), shape = "Cylinder", description = "Glazed, gilded, aerodynamic." },
	{ id = "MegaSteak", name = "Mega Steak", craving = "Meat", power = 2.2, luck = 1.2, price = 600000, color = Color3.fromRGB(170, 50, 50), shape = "Block", description = "Thick-cut launch fuel." },
	{ id = "InfernoWing", name = "Inferno Wing", craving = "Spicy", power = 2.7, luck = 1.25, price = 3000000, color = Color3.fromRGB(255, 120, 0), shape = "Ball", description = "Leaves a trail of flames." },
	{ id = "NebulaNugget", name = "Nebula Nugget", craving = "Cosmic", power = 3.4, luck = 1.35, price = 15000000, color = Color3.fromRGB(70, 220, 255), shape = "Ball", description = "Breaks the sound barrier. And orbit." },
} :: { Food }

local byId: { [string]: Food } = {}
for _, f in FoodConfig.Foods do
	byId[f.id] = f
end

function FoodConfig.get(id: string?): Food?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function FoodConfig.isCraving(name: any): boolean
	return type(name) == "string" and FoodConfig.CravingColors[name] ~= nil
end

return FoodConfig
