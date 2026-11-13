--!strict
-- Builds pet models from primitive parts (no Toolbox / mesh assets).
-- Every part is anchored + non-colliding, positioned relative to `origin` (the point
-- the pet stands on). Used by the server for plot pedestals and the client for reveals.

local Config = script.Parent.Parent:WaitForChild("Config")
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))

local PetModelBuilder = {}

PetModelBuilder.BaseScale = 2

local BLACK = Color3.fromRGB(25, 25, 30)
local WHITE = Color3.fromRGB(255, 255, 255)

type Ctx = {
	model: Model,
	origin: CFrame,
	s: number,
	body: Color3,
	accent: Color3,
	mat: MutationConfig.Material,
}

local function tint(base: Color3, mat: MutationConfig.Material): Color3
	if mat.color == nil then
		return base
	end
	return base:Lerp(mat.color, 0.8)
end

local function add(
	ctx: Ctx,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	keepMaterial: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size * ctx.s
	p.CFrame = ctx.origin * CFrame.new(offset.Position * ctx.s) * offset.Rotation
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if keepMaterial then
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
	else
		p.Color = tint(color, ctx.mat)
		p.Material = ctx.mat.partMaterial
		p.Transparency = ctx.mat.transparency
		p.Reflectance = if ctx.mat.tier >= 2 then 0.15 else 0
	end
	p.Parent = ctx.model
	return p
end

local function ball(ctx: Ctx, name: string, d: number, x: number, y: number, z: number, color: Color3, keep: boolean?): Part
	return add(ctx, name, Enum.PartType.Ball, Vector3.new(d, d, d), CFrame.new(x, y, z), color, keep)
end

local CHEEK = Color3.fromRGB(255, 140, 170)

local function eyes(ctx: Ctx, y: number, z: number, spread: number, d: number)
	for _, side in { -1, 1 } do
		ball(ctx, "Eye", d, side * spread, y, z, BLACK, true)
		ball(ctx, "Shine", d * 0.35, side * spread + d * 0.15, y + d * 0.2, z - d * 0.35, WHITE, true)
		local cheek = ball(ctx, "Cheek", d * 0.75, side * (spread + d * 0.75), y - d * 1.1, z + d * 0.15, CHEEK, true)
		cheek.Transparency = 0.25
	end
end

local builders: { [string]: (Ctx) -> Part } = {}

builders.Pup = function(ctx)
	local body = ball(ctx, "Body", 1, 0, 0.5, 0, ctx.body)
	ball(ctx, "Head", 0.8, 0, 1.15, -0.25, ctx.body)
	ball(ctx, "Snout", 0.38, 0, 1.05, -0.62, ctx.accent)
	ball(ctx, "Nose", 0.14, 0, 1.12, -0.8, BLACK, true)
	for _, side in { -1, 1 } do
		add(ctx, "Ear", Enum.PartType.Block, Vector3.new(0.18, 0.5, 0.3), CFrame.new(side * 0.42, 1.2, -0.2) * CFrame.Angles(0, 0, side * 0.35), ctx.accent)
		add(ctx, "Leg", Enum.PartType.Cylinder, Vector3.new(0.35, 0.22, 0.22), CFrame.new(side * 0.25, 0.12, -0.2) * CFrame.Angles(0, 0, math.pi / 2), ctx.accent)
	end
	add(ctx, "Tail", Enum.PartType.Cylinder, Vector3.new(0.5, 0.14, 0.14), CFrame.new(0, 0.75, 0.55) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 0.8), ctx.accent)
	eyes(ctx, 1.25, -0.58, 0.18, 0.15)
	return body
end

builders.Kitty = function(ctx)
	local body = ball(ctx, "Body", 0.95, 0, 0.48, 0, ctx.body)
	ball(ctx, "Head", 0.82, 0, 1.15, -0.2, ctx.body)
	for _, side in { -1, 1 } do
		add(ctx, "Ear", Enum.PartType.Wedge, Vector3.new(0.12, 0.35, 0.3), CFrame.new(side * 0.25, 1.6, -0.2), ctx.accent)
		ball(ctx, "Whisker", 0.08, side * 0.3, 1.02, -0.55, WHITE, true)
	end
	add(ctx, "Tail", Enum.PartType.Cylinder, Vector3.new(0.9, 0.13, 0.13), CFrame.new(0, 0.9, 0.55) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 1.1), ctx.accent)
	ball(ctx, "Nose", 0.12, 0, 1.08, -0.6, Color3.fromRGB(255, 130, 160), true)
	eyes(ctx, 1.22, -0.55, 0.2, 0.17)
	return body
end

builders.Bunny = function(ctx)
	local body = ball(ctx, "Body", 1, 0, 0.5, 0, ctx.body)
	ball(ctx, "Head", 0.75, 0, 1.12, -0.2, ctx.body)
	for _, side in { -1, 1 } do
		add(ctx, "Ear", Enum.PartType.Cylinder, Vector3.new(0.75, 0.2, 0.2), CFrame.new(side * 0.16, 1.75, -0.15) * CFrame.Angles(0, 0, math.pi / 2 + side * 0.15), ctx.body)
		add(ctx, "EarInner", Enum.PartType.Cylinder, Vector3.new(0.55, 0.1, 0.1), CFrame.new(side * 0.16, 1.75, -0.24) * CFrame.Angles(0, 0, math.pi / 2 + side * 0.15), ctx.accent)
	end
	ball(ctx, "Tail", 0.35, 0, 0.5, 0.52, WHITE)
	ball(ctx, "Nose", 0.1, 0, 1.05, -0.56, ctx.accent, true)
	eyes(ctx, 1.18, -0.5, 0.17, 0.14)
	return body
end

builders.Chick = function(ctx)
	local body = ball(ctx, "Body", 1.15, 0, 0.6, 0, ctx.body)
	add(ctx, "Beak", Enum.PartType.Wedge, Vector3.new(0.25, 0.2, 0.3), CFrame.new(0, 0.85, -0.65) * CFrame.Angles(math.pi / 2, 0, 0), ctx.accent)
	for _, side in { -1, 1 } do
		add(ctx, "Wing", Enum.PartType.Ball, Vector3.new(0.18, 0.55, 0.5), CFrame.new(side * 0.6, 0.6, 0.05) * CFrame.Angles(0, 0, side * 0.3), ctx.body)
		add(ctx, "Foot", Enum.PartType.Block, Vector3.new(0.18, 0.06, 0.25), CFrame.new(side * 0.2, 0.03, -0.1), ctx.accent)
	end
	ball(ctx, "Tuft", 0.25, 0, 1.22, -0.05, ctx.accent)
	eyes(ctx, 1.0, -0.5, 0.2, 0.15)
	return body
end

builders.Slime = function(ctx)
	local body = add(ctx, "Body", Enum.PartType.Ball, Vector3.new(1.4, 1.05, 1.4), CFrame.new(0, 0.52, 0), ctx.body)
	if ctx.mat.tier == 1 then
		body.Transparency = 0.2
	end
	ball(ctx, "Core", 0.45, 0.15, 0.55, 0.1, ctx.accent)
	ball(ctx, "Drip", 0.3, -0.5, 0.15, -0.4, ctx.body)
	ball(ctx, "Gloss", 0.2, 0.3, 0.85, -0.45, WHITE, true)
	eyes(ctx, 0.75, -0.62, 0.22, 0.18)
	return body
end

builders.Dragon = function(ctx)
	local body = add(ctx, "Body", Enum.PartType.Ball, Vector3.new(1, 0.9, 1.25), CFrame.new(0, 0.55, 0), ctx.body)
	ball(ctx, "Head", 0.75, 0, 1.2, -0.45, ctx.body)
	ball(ctx, "Snout", 0.42, 0, 1.1, -0.82, ctx.body)
	ball(ctx, "Belly", 0.7, 0, 0.45, -0.25, ctx.accent)
	for _, side in { -1, 1 } do
		add(ctx, "Wing", Enum.PartType.Wedge, Vector3.new(0.08, 0.7, 0.8), CFrame.new(side * 0.7, 1.0, 0.15) * CFrame.Angles(0, 0, side * -0.6), ctx.accent)
		add(ctx, "Horn", Enum.PartType.Wedge, Vector3.new(0.1, 0.35, 0.18), CFrame.new(side * 0.2, 1.62, -0.35), ctx.accent)
	end
	add(ctx, "Tail", Enum.PartType.Cylinder, Vector3.new(0.9, 0.22, 0.22), CFrame.new(0, 0.4, 0.85) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 0.3), ctx.body)
	eyes(ctx, 1.32, -0.75, 0.2, 0.15)
	return body
end

builders.Bear = function(ctx)
	local body = ball(ctx, "Body", 1.1, 0, 0.55, 0, ctx.body)
	ball(ctx, "Head", 0.85, 0, 1.25, -0.2, ctx.body)
	ball(ctx, "Snout", 0.38, 0, 1.15, -0.58, ctx.accent)
	ball(ctx, "Nose", 0.14, 0, 1.22, -0.75, BLACK, true)
	ball(ctx, "Belly", 0.7, 0, 0.5, -0.3, ctx.accent)
	for _, side in { -1, 1 } do
		ball(ctx, "Ear", 0.3, side * 0.35, 1.62, -0.15, ctx.body)
		ball(ctx, "Paw", 0.35, side * 0.42, 0.25, -0.35, ctx.body)
	end
	eyes(ctx, 1.35, -0.55, 0.2, 0.14)
	return body
end

builders.Frog = function(ctx)
	local body = add(ctx, "Body", Enum.PartType.Ball, Vector3.new(1.3, 0.8, 1.1), CFrame.new(0, 0.4, 0), ctx.body)
	ball(ctx, "Belly", 0.8, 0, 0.3, -0.25, ctx.accent)
	for _, side in { -1, 1 } do
		ball(ctx, "EyeBump", 0.42, side * 0.3, 0.85, -0.25, ctx.body)
		add(ctx, "Leg", Enum.PartType.Ball, Vector3.new(0.4, 0.25, 0.6), CFrame.new(side * 0.6, 0.12, 0.1), ctx.body)
	end
	add(ctx, "Mouth", Enum.PartType.Block, Vector3.new(0.6, 0.04, 0.04), CFrame.new(0, 0.5, -0.55), BLACK, true)
	eyes(ctx, 0.92, -0.42, 0.3, 0.2)
	return body
end

-- Returns the model and its approximate height in studs.
function PetModelBuilder.build(speciesId: string, materialId: string, sizeId: string, origin: CFrame): (Model, number)
	local pet = PetConfig.get(speciesId) or PetConfig.Pets[1]
	local mat = MutationConfig.getMaterial(materialId) or MutationConfig.Materials[1]
	local size = MutationConfig.getSize(sizeId) or MutationConfig.Sizes[1]
	local model = Instance.new("Model")
	model.Name = pet.name
	local s = PetModelBuilder.BaseScale * size.scale
	local ctx: Ctx = {
		model = model,
		origin = origin,
		s = s,
		body = pet.bodyColor,
		accent = pet.accentColor,
		mat = mat,
	}
	local builder = builders[pet.archetype] or builders.Pup
	local body = builder(ctx)
	model.PrimaryPart = body
	model:SetAttribute("Species", pet.id)
	model:SetAttribute("Material", mat.id)
	model:SetAttribute("Size", size.id)
	if mat.id == "Rainbow" then
		model:AddTag("RainbowPet")
	end
	if mat.tier >= 3 or size.tier >= 5 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "MutationSparkle"
		sparkle.Color = ColorSequence.new(mat.color or pet.accentColor)
		sparkle.LightEmission = 1
		sparkle.Rate = 6 + mat.tier * 2
		sparkle.Lifetime = NumberRange.new(0.6, 1.2)
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new(0.25 * size.scale, 0)
		sparkle.Parent = body
		local light = Instance.new("PointLight")
		light.Color = mat.color or pet.accentColor
		light.Range = 6 * size.scale
		light.Brightness = 1.5
		light.Parent = body
	end
	return model, 1.9 * s
end

return PetModelBuilder
