--!strict
-- Material and size mutations. `chance` is the base per-catch probability before luck.
-- Rolls go rarest-first so a lucky roll always yields the best tier it qualifies for.

export type Material = {
	id: string,
	tier: number,
	chance: number,
	incomeMult: number,
	rarity: string,
	color: Color3?,
	partMaterial: Enum.Material,
	transparency: number,
}

export type Size = {
	id: string,
	tier: number,
	chance: number,
	incomeMult: number,
	rarity: string,
	scale: number,
}

local MutationConfig = {}

MutationConfig.Materials = {
	{ id = "Normal", tier = 1, chance = 1, incomeMult = 1, rarity = "Common", color = nil, partMaterial = Enum.Material.SmoothPlastic, transparency = 0 },
	{ id = "Gold", tier = 2, chance = 1 / 12, incomeMult = 2, rarity = "Rare", color = Color3.fromRGB(255, 200, 50), partMaterial = Enum.Material.Metal, transparency = 0 },
	{ id = "Diamond", tier = 3, chance = 1 / 45, incomeMult = 4, rarity = "Epic", color = Color3.fromRGB(150, 230, 255), partMaterial = Enum.Material.Glass, transparency = 0.15 },
	{ id = "Emerald", tier = 4, chance = 1 / 150, incomeMult = 8, rarity = "Legendary", color = Color3.fromRGB(40, 210, 110), partMaterial = Enum.Material.Glass, transparency = 0.1 },
	{ id = "Ruby", tier = 5, chance = 1 / 500, incomeMult = 16, rarity = "Mythic", color = Color3.fromRGB(230, 30, 70), partMaterial = Enum.Material.Glass, transparency = 0.1 },
	{ id = "Rainbow", tier = 6, chance = 1 / 2000, incomeMult = 40, rarity = "Secret", color = Color3.fromRGB(255, 255, 255), partMaterial = Enum.Material.Neon, transparency = 0 },
} :: { Material }

MutationConfig.Sizes = {
	{ id = "Normal", tier = 1, chance = 1, incomeMult = 1, rarity = "Common", scale = 1 },
	{ id = "Huge", tier = 2, chance = 1 / 10, incomeMult = 1.75, rarity = "Uncommon", scale = 1.35 },
	{ id = "Colossal", tier = 3, chance = 1 / 35, incomeMult = 3, rarity = "Rare", scale = 1.7 },
	{ id = "Monstrous", tier = 4, chance = 1 / 120, incomeMult = 6, rarity = "Epic", scale = 2.05 },
	{ id = "Titanic", tier = 5, chance = 1 / 400, incomeMult = 12, rarity = "Legendary", scale = 2.4 },
	{ id = "Cosmic", tier = 6, chance = 1 / 1500, incomeMult = 30, rarity = "Mythic", scale = 2.75 },
	{ id = "Infinite", tier = 7, chance = 1 / 7500, incomeMult = 100, rarity = "Secret", scale = 3.1 },
} :: { Size }

-- No single roll can ever be better than this probability, however lucky.
MutationConfig.MaxChance = 0.5

-- Craving combo: consecutive craving matches build a streak. Index = streak (0..n).
MutationConfig.ComboMultipliers = { [0] = 1, 1.5, 2, 3, 4, 5, 6.5, 8, 10 }
MutationConfig.MaxComboMultiplier = 10

local materialsById: { [string]: Material } = {}
for _, m in MutationConfig.Materials do
	materialsById[m.id] = m
end
local sizesById: { [string]: Size } = {}
for _, s in MutationConfig.Sizes do
	sizesById[s.id] = s
end

function MutationConfig.getMaterial(id: string?): Material?
	if type(id) ~= "string" then
		return nil
	end
	return materialsById[id]
end

function MutationConfig.getSize(id: string?): Size?
	if type(id) ~= "string" then
		return nil
	end
	return sizesById[id]
end

function MutationConfig.nextMaterial(id: string): Material?
	local m = materialsById[id]
	if not m then
		return nil
	end
	return MutationConfig.Materials[m.tier + 1]
end

return MutationConfig
