--!strict
-- Builds the eight snacks from primitive parts (no Toolbox / mesh assets). Each snack
-- has its own silhouette so it reads at a glance in the shop, in the hand and in flight:
-- a round berry with a leaf crown, a bone with knobs, a curved chili, a five-point
-- cookie, a fluted tart, a T-bone steak, a drumstick with a small flame and a nugget
-- with an orbit ring.
--
-- Two forms:
--   build(id, origin, scale)  -> Model, every part anchored (shop previews, the stall).
--   buildRig(id, scale)       -> the core Part; the other parts are its children, welded
--                                to it, so moving the anchored core moves the whole snack
--                                (held snack, flight, cutscenes).
-- Snacks are authored in "snack units" centred on the origin, about 2 units across;
-- every unit is multiplied by `scale` (1 = about 1.8 studs).

local Config = script.Parent.Parent:WaitForChild("Config")
local FoodConfig = require(Config:WaitForChild("FoodConfig"))

local FoodModelBuilder = {}

local CREAM = Color3.fromRGB(246, 236, 214)
local LEAF = Color3.fromRGB(96, 168, 80)
local LEAF_DARK = Color3.fromRGB(64, 128, 60)
local CRUST = Color3.fromRGB(214, 160, 92)
local CHAR = Color3.fromRGB(92, 44, 36)
local FLAME = Color3.fromRGB(255, 170, 40)
local FLAME_TIP = Color3.fromRGB(255, 236, 140)

type Kind = "Block" | "Ball" | "Cyl" | "Wedge" | "Egg"

type Ctx = {
	parts: { BasePart },
	origin: CFrame,
	s: number,
}

local function add(ctx: Ctx, kind: Kind, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = if kind == "Cyl" then Enum.PartType.Cylinder elseif kind == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
		if kind == "Egg" then
			-- Non-uniform round shapes: a Block with a Sphere mesh.
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		p = part
	end
	p.Name = name
	p.Size = size * ctx.s
	p.CFrame = ctx.origin * CFrame.new(cf.Position * ctx.s) * cf.Rotation
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	table.insert(ctx.parts, p)
	return p
end

local rad = math.rad

-- Each recipe adds the core first (the largest piece: it carries the trail and outline).
local RECIPES: { [string]: (Ctx, Color3) -> () } = {}

RECIPES.BerryBite = function(ctx, c)
	add(ctx, "Ball", "Core", Vector3.one * 1.6, CFrame.new(), c)
	for i, a in { 20, 140, 260, 80, 200, 320 } do
		local y = if i <= 3 then 0.25 else -0.3
		local r = if i <= 3 then 0.74 else 0.72
		local dir = CFrame.Angles(0, rad(a), 0) * CFrame.new(0, y, -r)
		add(ctx, "Ball", "Seed", Vector3.one * 0.16, dir, CREAM)
	end
	for i = 0, 2 do
		add(ctx, "Wedge", "Leaf", Vector3.new(0.1, 0.26, 0.44), CFrame.new(0, 0.8, 0) * CFrame.Angles(0, rad(i * 120), 0) * CFrame.new(0, 0, -0.2) * CFrame.Angles(rad(-25), 0, 0), LEAF)
	end
	add(ctx, "Cyl", "Stem", Vector3.new(0.4, 0.12, 0.12), CFrame.new(0, 0.98, 0) * CFrame.Angles(0, 0, rad(80)), LEAF_DARK)
end

RECIPES.MeatyBone = function(ctx, c)
	add(ctx, "Egg", "Core", Vector3.new(1.5, 1.0, 1.05), CFrame.new(0.05, 0, 0), Color3.fromRGB(196, 92, 70))
	add(ctx, "Cyl", "Shaft", Vector3.new(2.2, 0.42, 0.42), CFrame.new(), c)
	for _, x in { -1.1, 1.1 } do
		for _, z in { -0.2, 0.2 } do
			add(ctx, "Ball", "Knob", Vector3.one * 0.5, CFrame.new(x, 0, z), c)
		end
	end
	add(ctx, "Egg", "Shine", Vector3.new(0.7, 0.18, 0.4), CFrame.new(-0.05, 0.43, -0.18), Color3.fromRGB(226, 130, 100))
end

RECIPES.ChiliPop = function(ctx, c)
	-- Three tapering segments bend into a hook; the green cap and stem sit on the wide end.
	add(ctx, "Egg", "Core", Vector3.new(1.0, 0.85, 0.85), CFrame.new(-0.45, 0.1, 0) * CFrame.Angles(0, 0, rad(-8)), c)
	add(ctx, "Egg", "Body", Vector3.new(0.9, 0.66, 0.66), CFrame.new(0.25, -0.05, 0) * CFrame.Angles(0, 0, rad(-22)), c)
	add(ctx, "Egg", "Tip", Vector3.new(0.6, 0.42, 0.42), CFrame.new(0.78, -0.33, 0) * CFrame.Angles(0, 0, rad(-45)), c)
	add(ctx, "Cyl", "Cap", Vector3.new(0.2, 0.7, 0.7), CFrame.new(-0.98, 0.15, 0), LEAF)
	add(ctx, "Cyl", "Stem", Vector3.new(0.45, 0.14, 0.14), CFrame.new(-1.15, 0.3, 0) * CFrame.Angles(0, 0, rad(-40)), LEAF_DARK)
	add(ctx, "Egg", "Shine", Vector3.new(0.5, 0.12, 0.2), CFrame.new(-0.35, 0.47, -0.2), Color3.fromRGB(255, 150, 120))
end

RECIPES.StarCookie = function(ctx, c)
	add(ctx, "Cyl", "Core", Vector3.new(0.36, 1.0, 1.0), CFrame.Angles(0, 0, rad(90)), CRUST)
	for i = 0, 4 do
		local yaw = CFrame.Angles(0, rad(i * 72), 0)
		-- A square turned 45 degrees and half sunk into the disc leaves a sharp point.
		add(ctx, "Block", "Point", Vector3.new(0.6, 0.36, 0.6), yaw * CFrame.new(0, 0, -0.62) * CFrame.Angles(0, rad(45), 0), CRUST)
		add(ctx, "Ball", "Icing", Vector3.one * 0.2, yaw * CFrame.new(0, 0.2, -0.62), c)
	end
	add(ctx, "Cyl", "Glaze", Vector3.new(0.08, 0.72, 0.72), CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, rad(90)), c)
	add(ctx, "Ball", "Sprinkle", Vector3.one * 0.12, CFrame.new(0.14, 0.27, -0.1), CREAM)
	add(ctx, "Ball", "Sprinkle", Vector3.one * 0.12, CFrame.new(-0.16, 0.27, 0.12), CREAM)
end

RECIPES.BerryTart = function(ctx, c)
	add(ctx, "Cyl", "Core", Vector3.new(0.6, 1.9, 1.9), CFrame.Angles(0, 0, rad(90)), c, Enum.Material.SmoothPlastic)
	for i = 0, 9 do
		add(ctx, "Ball", "Flute", Vector3.one * 0.34, CFrame.Angles(0, rad(i * 36), 0) * CFrame.new(0, 0.12, -0.9), CRUST)
	end
	add(ctx, "Cyl", "Filling", Vector3.new(0.12, 1.5, 1.5), CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(220, 56, 96))
	for i, p in { Vector3.new(0, 0.48, 0), Vector3.new(0.4, 0.44, 0.22), Vector3.new(-0.36, 0.44, 0.28), Vector3.new(0.05, 0.44, -0.42) } do
		add(ctx, "Ball", "Berry" .. i, Vector3.one * (if i == 1 then 0.42 else 0.34), CFrame.new(p), Color3.fromRGB(176, 30, 74))
	end
	add(ctx, "Wedge", "Leaf", Vector3.new(0.1, 0.18, 0.4), CFrame.new(0.05, 0.72, 0.05), LEAF)
end

RECIPES.MegaSteak = function(ctx, c)
	add(ctx, "Egg", "Core", Vector3.new(2.0, 0.5, 1.45), CFrame.new(), c)
	add(ctx, "Egg", "Fat", Vector3.new(2.06, 0.42, 0.5), CFrame.new(0.02, 0, 0.6), CREAM)
	add(ctx, "Block", "BoneLong", Vector3.new(0.16, 0.16, 1.1), CFrame.new(0.15, 0.24, -0.05), CREAM)
	add(ctx, "Block", "BoneCross", Vector3.new(0.9, 0.16, 0.16), CFrame.new(0.15, 0.24, -0.58), CREAM)
	for i = -1, 1 do
		add(ctx, "Block", "Grill", Vector3.new(0.09, 0.06, 1.0), CFrame.new(-0.45 + i * 0.32, 0.25, -0.05) * CFrame.Angles(0, rad(35), 0), CHAR)
	end
end

RECIPES.InfernoWing = function(ctx, c)
	add(ctx, "Egg", "Core", Vector3.new(1.25, 1.1, 1.1), CFrame.new(-0.2, 0, 0), c)
	add(ctx, "Egg", "Taper", Vector3.new(0.8, 0.7, 0.7), CFrame.new(0.4, 0, 0), c)
	add(ctx, "Cyl", "Bone", Vector3.new(0.6, 0.24, 0.24), CFrame.new(0.9, 0, 0), CREAM)
	add(ctx, "Ball", "Knob", Vector3.one * 0.32, CFrame.new(1.2, 0.08, 0), CREAM)
	add(ctx, "Ball", "Knob", Vector3.one * 0.32, CFrame.new(1.2, -0.1, 0.06), CREAM)
	add(ctx, "Egg", "Crisp", Vector3.new(0.6, 0.16, 0.4), CFrame.new(-0.25, 0.53, -0.1), Color3.fromRGB(200, 84, 20))
	-- A small flame: the one glowing bit (kept small so the shape stays the read).
	add(ctx, "Wedge", "Flame", Vector3.new(0.12, 0.6, 0.36), CFrame.new(-0.35, 0.82, 0) * CFrame.Angles(0, rad(90), 0), FLAME, Enum.Material.Neon)
	add(ctx, "Wedge", "FlameTip", Vector3.new(0.1, 0.38, 0.22), CFrame.new(0.0, 0.72, 0.05) * CFrame.Angles(0, rad(90), 0), FLAME_TIP, Enum.Material.Neon)
end

RECIPES.NebulaNugget = function(ctx, c)
	add(ctx, "Egg", "Core", Vector3.new(1.3, 1.05, 1.15), CFrame.new(), c)
	add(ctx, "Egg", "Crust", Vector3.new(0.6, 0.3, 0.5), CFrame.new(0.25, 0.42, -0.15), Color3.fromRGB(150, 236, 255))
	add(ctx, "Ball", "Speck", Vector3.one * 0.14, CFrame.new(-0.35, 0.25, -0.5), Color3.fromRGB(255, 255, 255))
	add(ctx, "Ball", "Speck", Vector3.one * 0.12, CFrame.new(0.4, -0.2, -0.5), Color3.fromRGB(190, 160, 255))
	-- Tilted orbit ring of small beads plus a tiny moon.
	local tilt = CFrame.Angles(rad(18), 0, rad(-22))
	for i = 0, 13 do
		add(ctx, "Ball", "Ring", Vector3.one * 0.13, tilt * CFrame.Angles(0, rad(i * (360 / 14)), 0) * CFrame.new(0, 0, -1.0), Color3.fromRGB(196, 176, 255))
	end
	add(ctx, "Ball", "Moon", Vector3.one * 0.3, tilt * CFrame.Angles(0, rad(50), 0) * CFrame.new(0, 0, -1.0), CREAM)
end

local function run(id: string?, origin: CFrame, scale: number?): (Ctx, FoodConfig.Food)
	local food = FoodConfig.get(id) or FoodConfig.Foods[1]
	local ctx: Ctx = { parts = {}, origin = origin, s = scale or 1 }
	local recipe = RECIPES[food.id] or RECIPES.BerryBite
	recipe(ctx, food.color)
	return ctx, food
end

-- Anchored model (shop previews, world props). PrimaryPart is the core.
function FoodModelBuilder.build(id: string?, origin: CFrame?, scale: number?): Model
	local ctx, food = run(id, origin or CFrame.new(), scale)
	local model = Instance.new("Model")
	model.Name = food.id
	for _, p in ctx.parts do
		p.Parent = model
	end
	model.PrimaryPart = ctx.parts[1]
	return model
end

-- Moving snack: the anchored core with every other part welded to it as a child.
function FoodModelBuilder.buildRig(id: string?, scale: number?): Part
	local ctx = run(id, CFrame.new(), scale)
	local core = ctx.parts[1] :: Part
	for i = 2, #ctx.parts do
		local p = ctx.parts[i]
		p.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = core
		weld.Part1 = p
		weld.Parent = p
		p.Parent = core
	end
	return core
end

-- Hides or shows every part of a rig (the core keeps its children).
function FoodModelBuilder.setVisible(core: BasePart, visible: boolean)
	local t = if visible then 0 else 1
	core.LocalTransparencyModifier = t
	for _, d in core:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = t
		end
	end
end

-- Camera for a 3/4 product shot of a model built at the origin with scale 1.
function FoodModelBuilder.portraitCamera(): (CFrame, number)
	local eye = Vector3.new(2.1, 1.9, -3.5)
	return CFrame.lookAt(eye, Vector3.new(0, -0.05, 0)), 34
end

FoodModelBuilder.Recipes = RECIPES
return FoodModelBuilder
