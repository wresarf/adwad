--!strict
-- Builds pet models from primitive parts (no Toolbox / mesh assets).
-- Every part is anchored + non-colliding, positioned relative to `origin` (the point
-- the pet stands on). Used by the server for plot pedestals and the client for reveals.
--
-- Modeling language ("toy safari"): chunky rounded-cube heads and bodies, stubby legs,
-- big glossy eyes with a highlight and soft cheeks, small add-on ears / horns / tails.
-- Pets are authored in "pet units" facing -Z with the feet on Y = 0; every unit is
-- multiplied by BaseScale x size.scale. Ellipsoids are Block parts with a Sphere
-- SpecialMesh (Roblox forces Ball parts to be uniform spheres).

local Config = script.Parent.Parent:WaitForChild("Config")
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))

local PetModelBuilder = {}

PetModelBuilder.BaseScale = 2

local INK = Color3.fromRGB(38, 32, 34) -- eyes, noses, mouths
local WHITE = Color3.fromRGB(255, 255, 255)
local CREAM = Color3.fromRGB(250, 244, 230)
local CHEEK = Color3.fromRGB(244, 150, 150)

type Ctx = {
	model: Model,
	origin: CFrame,
	s: number,
	body: Color3,
	accent: Color3,
	mat: MutationConfig.Material,
	top: number,
	half: number, -- widest horizontal half-extent from the centre (unscaled), for framing
}

type Kind = "Block" | "Ball" | "Cyl" | "Wedge"

local function tint(base: Color3, mat: MutationConfig.Material): Color3
	if mat.color == nil then
		return base
	end
	return base:Lerp(mat.color, 0.8)
end

-- Adds one part. `cf` is in unscaled pet units relative to the origin. `keep` parts
-- (eyes, highlights, cheeks, noses) stay plain plastic so faces read on every material.
local function add(ctx: Ctx, kind: Kind, name: string, size: Vector3, cf: CFrame, color: Color3, keep: boolean?): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = if kind == "Cyl" then Enum.PartType.Cylinder else Enum.PartType.Block
		if kind == "Ball" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		p = part
	end
	p.Name = name
	p.Size = size * ctx.s
	p.CFrame = ctx.origin * CFrame.new(cf.Position * ctx.s) * cf.Rotation
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if keep then
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
	else
		p.Color = tint(color, ctx.mat)
		p.Material = ctx.mat.partMaterial
		p.Transparency = ctx.mat.transparency
		p.Reflectance = if ctx.mat.tier >= 2 then 0.15 else 0
	end
	-- Track the highest point (unscaled) for the returned height.
	local top = cf.Position.Y
		+ 0.5 * (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z)
	if top > ctx.top then
		ctx.top = top
	end
	local hx = math.abs(cf.Position.X) + 0.5 * (math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z)
	local hz = math.abs(cf.Position.Z) + 0.5 * (math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z)
	ctx.half = math.max(ctx.half, hx, hz)
	p.Parent = ctx.model
	return p
end

local function blob(ctx: Ctx, name: string, size: Vector3, pos: Vector3, color: Color3, keep: boolean?): BasePart
	return add(ctx, "Ball", name, size, CFrame.new(pos), color, keep)
end

-- Cylinder of diameter `d` from `a` to `b` (legs, tails, necks, trunks, horns).
local function stick(ctx: Ctx, name: string, a: Vector3, b: Vector3, d: number, color: Color3, keep: boolean?): BasePart
	local dir = b - a
	local len = dir.Magnitude
	-- lookAt is degenerate when looking straight up, so pick another up-vector then.
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	return add(ctx, "Cyl", name, Vector3.new(len, d, d), cf, color, keep)
end

-- Rounded box: two crossed blocks plus four edge cylinders. `axis` is the direction the
-- rounded edges run along ("Z" rounds the silhouette seen from the front, "X" the
-- silhouette seen from the side). Returns the main block.
local function roundBox(ctx: Ctx, name: string, size: Vector3, cf: CFrame, r: number, axis: "X" | "Z", color: Color3): BasePart
	local main
	if axis == "Z" then
		main = add(ctx, "Block", name, Vector3.new(size.X - 2 * r, size.Y, size.Z), cf, color)
		add(ctx, "Block", name .. "Core", Vector3.new(size.X, size.Y - 2 * r, size.Z), cf, color)
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				add(ctx, "Cyl", name .. "Edge", Vector3.new(size.Z, 2 * r, 2 * r), cf * CFrame.new(sx * (size.X / 2 - r), sy * (size.Y / 2 - r), 0) * CFrame.Angles(0, math.pi / 2, 0), color)
			end
		end
	else
		main = add(ctx, "Block", name, Vector3.new(size.X, size.Y, size.Z - 2 * r), cf, color)
		add(ctx, "Block", name .. "Core", Vector3.new(size.X, size.Y - 2 * r, size.Z), cf, color)
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				add(ctx, "Cyl", name .. "Edge", Vector3.new(size.X, 2 * r, 2 * r), cf * CFrame.new(0, sy * (size.Y / 2 - r), sz * (size.Z / 2 - r)), color)
			end
		end
	end
	return main
end

-- The shared face: two big glossy eyes with a highlight and two soft cheeks.
-- `at` is the point on the front surface between the eyes (facing -Z).
local function face(ctx: Ctx, at: Vector3, spread: number, cheekAt: Vector3?, cheekSpread: number?)
	local ch = cheekAt or (at + Vector3.new(0, -0.15, 0))
	local cs = cheekSpread or (spread + 0.08)
	for _, side in { -1, 1 } do
		local e = at + Vector3.new(side * spread, 0, -0.02)
		blob(ctx, "Eye", Vector3.new(0.17, 0.22, 0.09), e, INK, true)
		blob(ctx, "EyeShine", Vector3.new(0.07, 0.08, 0.04), e + Vector3.new(side * 0.03, 0.05, -0.04), WHITE, true)
		local cheek = blob(ctx, "Cheek", Vector3.new(0.15, 0.08, 0.04), ch + Vector3.new(side * cs, 0, -0.01), CHEEK, true)
		cheek.Transparency = 0.15
	end
end

local function legs(ctx: Ctx, h: number, d: number, x: number, zf: number, zb: number, color: Color3)
	for _, sx in { -1, 1 } do
		for _, z in { zf, zb } do
			stick(ctx, "Leg", Vector3.new(sx * x, 0, z), Vector3.new(sx * x, h, z), d, color)
		end
	end
end

-- Mirrored upright triangle ear (a wedge turned so the triangle faces forward).
local function pointyEar(ctx: Ctx, side: number, pos: Vector3, h: number, w: number, color: Color3): BasePart
	return add(ctx, "Wedge", "Ear", Vector3.new(0.1, h, w), CFrame.new(pos) * CFrame.Angles(0, side * math.pi / 2, 0), color)
end

local function lighter(c: Color3, t: number): Color3
	return c:Lerp(CREAM, t)
end

local builders: { [string]: (Ctx) -> BasePart } = {}

builders.Pup = function(ctx)
	legs(ctx, 0.34, 0.24, 0.26, -0.3, 0.3, ctx.body)
	local body = roundBox(ctx, "Body", Vector3.new(0.8, 0.58, 1.0), CFrame.new(0, 0.6, 0), 0.18, "X", ctx.body)
	roundBox(ctx, "Head", Vector3.new(0.86, 0.74, 0.68), CFrame.new(0, 1.18, -0.42), 0.2, "Z", ctx.body)
	blob(ctx, "Snout", Vector3.new(0.42, 0.26, 0.22), Vector3.new(0, 1.0, -0.78), lighter(ctx.body, 0.55))
	blob(ctx, "Nose", Vector3.new(0.16, 0.11, 0.08), Vector3.new(0, 1.08, -0.89), INK, true)
	for _, side in { -1, 1 } do
		add(ctx, "Ball", "Ear", Vector3.new(0.14, 0.48, 0.3), CFrame.new(side * 0.46, 1.25, -0.4) * CFrame.Angles(0, 0, side * 0.25), ctx.accent)
	end
	stick(ctx, "Tail", Vector3.new(0, 0.75, 0.45), Vector3.new(0, 1.1, 0.62), 0.12, ctx.accent)
	face(ctx, Vector3.new(0, 1.22, -0.76), 0.2, nil, 0.3)
	return body
end

-- Sitting cat: upright body, straight front legs, haunches, tail curled on the ground.
-- The pose keeps its silhouette apart from the standing Pup.
builders.Kitty = function(ctx)
	for _, side in { -1, 1 } do
		blob(ctx, "Haunch", Vector3.new(0.34, 0.4, 0.5), Vector3.new(side * 0.27, 0.2, 0.12), ctx.body)
		stick(ctx, "Leg", Vector3.new(side * 0.15, 0, -0.26), Vector3.new(side * 0.15, 0.5, -0.2), 0.17, ctx.body)
		blob(ctx, "Paw", Vector3.new(0.2, 0.1, 0.24), Vector3.new(side * 0.15, 0.05, -0.32), lighter(ctx.body, 0.5))
	end
	local body = roundBox(ctx, "Body", Vector3.new(0.64, 0.68, 0.56), CFrame.new(0, 0.5, 0.04), 0.2, "Z", ctx.body)
	blob(ctx, "Bib", Vector3.new(0.38, 0.36, 0.08), Vector3.new(0, 0.62, -0.25), lighter(ctx.body, 0.6))
	roundBox(ctx, "Head", Vector3.new(0.9, 0.7, 0.64), CFrame.new(0, 1.12, -0.12), 0.22, "Z", ctx.body)
	for _, side in { -1, 1 } do
		pointyEar(ctx, side, Vector3.new(side * 0.28, 1.58, -0.14), 0.34, 0.3, ctx.accent)
		-- whiskers: two thin sticks per side
		for _, dy in { 0.02, -0.04 } do
			stick(ctx, "Whisker", Vector3.new(side * 0.2, 1.0 + dy, -0.45), Vector3.new(side * 0.5, 1.02 + dy * 2, -0.44), 0.025, INK, true)
		end
	end
	add(ctx, "Block", "Stripe", Vector3.new(0.08, 0.04, 0.3), CFrame.new(-0.1, 1.47, -0.15), ctx.accent)
	add(ctx, "Block", "Stripe", Vector3.new(0.08, 0.04, 0.3), CFrame.new(0.1, 1.47, -0.15), ctx.accent)
	blob(ctx, "Nose", Vector3.new(0.12, 0.08, 0.06), Vector3.new(0, 1.02, -0.45), Color3.fromRGB(236, 130, 140), true)
	-- Tail wraps around the right side along the ground, tip up at the front.
	stick(ctx, "Tail", Vector3.new(0.1, 0.07, 0.34), Vector3.new(0.48, 0.07, 0.06), 0.13, ctx.accent)
	stick(ctx, "TailTip", Vector3.new(0.48, 0.07, 0.06), Vector3.new(0.44, 0.2, -0.26), 0.12, ctx.accent)
	face(ctx, Vector3.new(0, 1.15, -0.44), 0.21)
	return body
end

builders.Bunny = function(ctx)
	-- Sitting: taller body, big flat hind feet, long ears.
	for _, side in { -1, 1 } do
		stick(ctx, "Leg", Vector3.new(side * 0.2, 0, -0.32), Vector3.new(side * 0.2, 0.3, -0.32), 0.18, ctx.body)
		blob(ctx, "Foot", Vector3.new(0.26, 0.18, 0.5), Vector3.new(side * 0.36, 0.09, 0.08), ctx.body)
	end
	local body = roundBox(ctx, "Body", Vector3.new(0.8, 0.74, 0.86), CFrame.new(0, 0.5, 0.05), 0.22, "X", ctx.body)
	roundBox(ctx, "Head", Vector3.new(0.8, 0.68, 0.62), CFrame.new(0, 1.14, -0.3), 0.22, "Z", ctx.body)
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * 0.18, 1.78, -0.3) * CFrame.Angles(0, 0, side * -0.14)
		add(ctx, "Ball", "Ear", Vector3.new(0.2, 0.78, 0.12), cf, ctx.body)
		add(ctx, "Ball", "EarInner", Vector3.new(0.11, 0.56, 0.04), cf * CFrame.new(0, -0.02, -0.06), ctx.accent)
	end
	blob(ctx, "Nose", Vector3.new(0.11, 0.08, 0.06), Vector3.new(0, 1.05, -0.62), ctx.accent, true)
	add(ctx, "Block", "Teeth", Vector3.new(0.1, 0.08, 0.03), CFrame.new(0, 0.96, -0.615), WHITE, true)
	blob(ctx, "Tail", Vector3.new(0.3, 0.3, 0.3), Vector3.new(0, 0.42, 0.5), WHITE)
	face(ctx, Vector3.new(0, 1.18, -0.61), 0.19)
	return body
end

builders.Chick = function(ctx)
	local body = roundBox(ctx, "Body", Vector3.new(0.92, 0.86, 0.86), CFrame.new(0, 0.53, 0), 0.26, "Z", ctx.body)
	for _, side in { -1, 1 } do
		add(ctx, "Block", "Foot", Vector3.new(0.18, 0.1, 0.26), CFrame.new(side * 0.2, 0.05, -0.12), ctx.accent)
		add(ctx, "Ball", "Wing", Vector3.new(0.14, 0.44, 0.46), CFrame.new(side * 0.47, 0.5, 0.04) * CFrame.Angles(0, 0, side * 0.25), ctx.body)
		add(ctx, "Ball", "Tuft", Vector3.new(0.1, 0.24, 0.1), CFrame.new(side * 0.05, 1.0, -0.05) * CFrame.Angles(0, 0, side * -0.45), ctx.accent)
	end
	add(ctx, "Wedge", "Beak", Vector3.new(0.2, 0.12, 0.16), CFrame.new(0, 0.6, -0.5), ctx.accent)
	add(ctx, "Wedge", "BeakLow", Vector3.new(0.2, 0.08, 0.12), CFrame.new(0, 0.5, -0.48) * CFrame.Angles(0, 0, math.pi), ctx.accent)
	face(ctx, Vector3.new(0, 0.7, -0.43), 0.22)
	return body
end

builders.Slime = function(ctx)
	-- Gumdrop: a squat cylinder skirt under a dome.
	local body = stick(ctx, "Body", Vector3.new(0, 0, 0), Vector3.new(0, 0.42, 0), 1.25, ctx.body)
	blob(ctx, "Dome", Vector3.new(1.25, 0.86, 1.25), Vector3.new(0, 0.42, 0), ctx.body)
	if ctx.mat.tier == 1 then
		for _, d in ctx.model:GetChildren() do
			if d:IsA("BasePart") then
				d.Transparency = 0.15
			end
		end
	end
	blob(ctx, "Core", Vector3.new(0.42, 0.42, 0.42), Vector3.new(0.12, 0.5, 0.12), ctx.accent)
	blob(ctx, "Drip", Vector3.new(0.28, 0.18, 0.28), Vector3.new(-0.5, 0.08, -0.36), ctx.body)
	blob(ctx, "Drip", Vector3.new(0.22, 0.14, 0.22), Vector3.new(0.56, 0.06, 0.2), ctx.body)
	blob(ctx, "Sprout", Vector3.new(0.16, 0.22, 0.16), Vector3.new(0, 0.9, 0), ctx.accent)
	blob(ctx, "Gloss", Vector3.new(0.18, 0.1, 0.12), Vector3.new(0.3, 0.74, -0.42), WHITE, true)
	face(ctx, Vector3.new(0, 0.42, -0.63), 0.24)
	return body
end

builders.Dragon = function(ctx)
	legs(ctx, 0.3, 0.24, 0.28, -0.32, 0.32, ctx.body)
	local body = roundBox(ctx, "Body", Vector3.new(0.84, 0.62, 1.08), CFrame.new(0, 0.58, 0), 0.2, "X", ctx.body)
	roundBox(ctx, "Head", Vector3.new(0.76, 0.66, 0.64), CFrame.new(0, 1.14, -0.5), 0.2, "Z", ctx.body)
	blob(ctx, "Snout", Vector3.new(0.5, 0.3, 0.3), Vector3.new(0, 0.98, -0.85), lighter(ctx.body, 0.25))
	for _, side in { -1, 1 } do
		stick(ctx, "Horn", Vector3.new(side * 0.2, 1.4, -0.48), Vector3.new(side * 0.25, 1.62, -0.36), 0.13, lighter(ctx.accent, 0.5))
		-- Raised bat wings: a big membrane plus a leading-edge bone, so the dragon's
		-- silhouette has a clear shape above its back.
		local wing = CFrame.new(side * 0.5, 1.22, 0.14) * CFrame.Angles(0, 0, side * -0.55)
		add(ctx, "Wedge", "Wing", Vector3.new(0.05, 0.9, 0.86), wing, ctx.accent)
		stick(ctx, "WingBone", (wing * CFrame.new(0, 0.45, 0.43)).Position, (wing * CFrame.new(0, -0.45, -0.43)).Position, 0.07, lighter(ctx.accent, 0.3))
	end
	add(ctx, "Wedge", "Spike", Vector3.new(0.06, 0.18, 0.24), CFrame.new(0, 0.97, 0.18), ctx.accent)
	stick(ctx, "Tail", Vector3.new(0, 0.55, 0.48), Vector3.new(0, 0.36, 1.02), 0.2, ctx.body)
	add(ctx, "Wedge", "TailTip", Vector3.new(0.06, 0.24, 0.26), CFrame.new(0, 0.45, 1.08) * CFrame.Angles(0, math.pi, 0), ctx.accent)
	face(ctx, Vector3.new(0, 1.24, -0.82), 0.19, nil, 0.3)
	return body
end

-- Sitting teddy: round upright body, feet stretched forward with paw pads, arms down.
builders.Bear = function(ctx)
	local body = roundBox(ctx, "Body", Vector3.new(0.92, 0.82, 0.74), CFrame.new(0, 0.46, 0.06), 0.28, "Z", ctx.body)
	blob(ctx, "Belly", Vector3.new(0.56, 0.5, 0.08), Vector3.new(0, 0.44, -0.31), lighter(ctx.body, 0.45))
	for _, side in { -1, 1 } do
		stick(ctx, "Leg", Vector3.new(side * 0.26, 0.15, -0.02), Vector3.new(side * 0.3, 0.15, -0.5), 0.3, ctx.body)
		add(ctx, "Cyl", "PawPad", Vector3.new(0.04, 0.24, 0.24), CFrame.new(side * 0.3, 0.15, -0.66) * CFrame.Angles(0, math.pi / 2, 0), ctx.accent)
		stick(ctx, "Arm", Vector3.new(side * 0.44, 0.68, -0.02), Vector3.new(side * 0.52, 0.32, -0.22), 0.22, ctx.body)
	end
	roundBox(ctx, "Head", Vector3.new(0.9, 0.78, 0.68), CFrame.new(0, 1.2, -0.06), 0.24, "Z", ctx.body)
	for _, side in { -1, 1 } do
		stick(ctx, "Ear", Vector3.new(side * 0.34, 1.6, -0.02), Vector3.new(side * 0.34, 1.6, -0.14), 0.3, ctx.body)
		stick(ctx, "EarInner", Vector3.new(side * 0.34, 1.59, -0.14), Vector3.new(side * 0.34, 1.59, -0.16), 0.17, ctx.accent)
	end
	blob(ctx, "Muzzle", Vector3.new(0.42, 0.3, 0.18), Vector3.new(0, 1.02, -0.4), ctx.accent)
	blob(ctx, "Nose", Vector3.new(0.16, 0.1, 0.08), Vector3.new(0, 1.1, -0.48), INK, true)
	blob(ctx, "Tail", Vector3.new(0.2, 0.2, 0.16), Vector3.new(0, 0.2, 0.44), ctx.body)
	face(ctx, Vector3.new(0, 1.26, -0.4), 0.2)
	return body
end

builders.Frog = function(ctx)
	for _, side in { -1, 1 } do
		stick(ctx, "Leg", Vector3.new(side * 0.34, 0, -0.3), Vector3.new(side * 0.34, 0.16, -0.3), 0.16, ctx.body)
		blob(ctx, "HindLeg", Vector3.new(0.34, 0.24, 0.62), Vector3.new(side * 0.58, 0.12, 0.08), ctx.body)
		blob(ctx, "EyeBump", Vector3.new(0.38, 0.34, 0.34), Vector3.new(side * 0.28, 0.7, -0.24), ctx.body)
	end
	local body = roundBox(ctx, "Body", Vector3.new(1.14, 0.54, 0.94), CFrame.new(0, 0.38, 0), 0.2, "X", ctx.body)
	blob(ctx, "Belly", Vector3.new(0.56, 0.16, 0.06), Vector3.new(0, 0.22, -0.47), ctx.accent)
	add(ctx, "Block", "Mouth", Vector3.new(0.56, 0.03, 0.03), CFrame.new(0, 0.42, -0.48), INK, true)
	face(ctx, Vector3.new(0, 0.72, -0.41), 0.28, Vector3.new(0, 0.5, -0.47), 0.4)
	return body
end

------------------------------------------------------------------ Safari egg exclusives

builders.Lion = function(ctx)
	legs(ctx, 0.32, 0.26, 0.27, -0.3, 0.3, ctx.body)
	local body = roundBox(ctx, "Body", Vector3.new(0.84, 0.62, 1.02), CFrame.new(0, 0.6, 0.02), 0.2, "X", ctx.body)
	-- Mane ring framing the head.
	stick(ctx, "Mane", Vector3.new(0, 1.2, -0.3), Vector3.new(0, 1.2, -0.52), 1.24, ctx.accent)
	roundBox(ctx, "Head", Vector3.new(0.8, 0.72, 0.6), CFrame.new(0, 1.2, -0.48), 0.22, "Z", ctx.body)
	for _, side in { -1, 1 } do
		stick(ctx, "Ear", Vector3.new(side * 0.3, 1.58, -0.5), Vector3.new(side * 0.3, 1.58, -0.62), 0.22, ctx.body)
	end
	blob(ctx, "Muzzle", Vector3.new(0.44, 0.28, 0.16), Vector3.new(0, 1.03, -0.79), lighter(ctx.body, 0.6))
	blob(ctx, "Nose", Vector3.new(0.15, 0.1, 0.07), Vector3.new(0, 1.11, -0.87), Color3.fromRGB(120, 70, 55), true)
	stick(ctx, "Tail", Vector3.new(0, 0.7, 0.5), Vector3.new(0, 0.42, 0.95), 0.1, ctx.body)
	blob(ctx, "TailTuft", Vector3.new(0.22, 0.22, 0.22), Vector3.new(0, 0.4, 0.98), ctx.accent)
	face(ctx, Vector3.new(0, 1.26, -0.78), 0.19, nil, 0.3)
	return body
end

builders.Elephant = function(ctx)
	legs(ctx, 0.36, 0.32, 0.3, -0.3, 0.32, ctx.body)
	local body = roundBox(ctx, "Body", Vector3.new(1.0, 0.8, 1.06), CFrame.new(0, 0.74, 0.04), 0.26, "X", ctx.body)
	roundBox(ctx, "Head", Vector3.new(0.84, 0.78, 0.66), CFrame.new(0, 1.32, -0.42), 0.24, "Z", ctx.body)
	for _, side in { -1, 1 } do
		-- Big flappy ears, turned slightly outward, with a pink inner disc.
		local ear = CFrame.new(side * 0.58, 1.3, -0.36) * CFrame.Angles(0, side * 0.45, 0)
		add(ctx, "Cyl", "Ear", Vector3.new(0.08, 0.86, 0.86), ear * CFrame.Angles(0, math.pi / 2, 0), ctx.body)
		add(ctx, "Cyl", "EarInner", Vector3.new(0.02, 0.6, 0.6), ear * CFrame.new(0, -0.02, -0.05) * CFrame.Angles(0, math.pi / 2, 0), ctx.accent)
		stick(ctx, "Tusk", Vector3.new(side * 0.16, 1.0, -0.72), Vector3.new(side * 0.19, 0.9, -0.88), 0.07, CREAM, true)
	end
	-- Trunk drops from the face and curls forward.
	stick(ctx, "Trunk", Vector3.new(0, 1.12, -0.76), Vector3.new(0, 0.72, -0.9), 0.22, ctx.body)
	stick(ctx, "TrunkTip", Vector3.new(0, 0.74, -0.9), Vector3.new(0, 0.7, -1.08), 0.18, ctx.body)
	face(ctx, Vector3.new(0, 1.42, -0.75), 0.21, Vector3.new(0, 1.26, -0.75), 0.3)
	return body
end

builders.Giraffe = function(ctx)
	legs(ctx, 0.92, 0.16, 0.22, -0.32, 0.3, ctx.body)
	local body = roundBox(ctx, "Body", Vector3.new(0.68, 0.54, 0.96), CFrame.new(0, 1.14, 0), 0.18, "X", ctx.body)
	stick(ctx, "Neck", Vector3.new(0, 1.2, -0.3), Vector3.new(0, 2.44, -0.46), 0.28, ctx.body)
	roundBox(ctx, "Head", Vector3.new(0.54, 0.48, 0.6), CFrame.new(0, 2.6, -0.54), 0.16, "Z", ctx.body)
	blob(ctx, "Muzzle", Vector3.new(0.42, 0.3, 0.26), Vector3.new(0, 2.48, -0.84), lighter(ctx.body, 0.5))
	for _, side in { -1, 1 } do
		stick(ctx, "Ossicone", Vector3.new(side * 0.12, 2.8, -0.48), Vector3.new(side * 0.15, 3.02, -0.48), 0.07, ctx.accent)
		blob(ctx, "OssiconeKnob", Vector3.new(0.12, 0.12, 0.12), Vector3.new(side * 0.15, 3.04, -0.48), ctx.accent)
	end
	-- Blocky toy spots: each block pokes through both flanks.
	add(ctx, "Block", "Spot", Vector3.new(0.72, 0.2, 0.22), CFrame.new(0, 1.2, -0.22), ctx.accent)
	add(ctx, "Block", "Spot", Vector3.new(0.72, 0.18, 0.2), CFrame.new(0, 1.06, 0.18), ctx.accent)
	add(ctx, "Block", "Spot", Vector3.new(0.72, 0.16, 0.18), CFrame.new(0, 1.26, 0.32), ctx.accent)
	face(ctx, Vector3.new(0, 2.66, -0.84), 0.16, Vector3.new(0, 2.5, -0.84), 0.26)
	return body
end

builders.Hippo = function(ctx)
	legs(ctx, 0.26, 0.32, 0.34, -0.32, 0.32, ctx.body)
	local body = roundBox(ctx, "Body", Vector3.new(1.12, 0.76, 1.14), CFrame.new(0, 0.62, 0.04), 0.28, "X", ctx.body)
	roundBox(ctx, "Head", Vector3.new(0.9, 0.6, 0.56), CFrame.new(0, 1.06, -0.56), 0.2, "Z", ctx.body)
	-- Wide muzzle with nostrils on top and two little teeth.
	local muzzle = lighter(ctx.body, 0.25)
	blob(ctx, "Muzzle", Vector3.new(1.04, 0.5, 0.46), Vector3.new(0, 0.9, -0.88), muzzle)
	for _, side in { -1, 1 } do
		blob(ctx, "Nostril", Vector3.new(0.1, 0.05, 0.08), Vector3.new(side * 0.18, 1.14, -0.96), INK, true)
		blob(ctx, "Ear", Vector3.new(0.14, 0.14, 0.1), Vector3.new(side * 0.32, 1.38, -0.5), ctx.accent)
		add(ctx, "Block", "Tooth", Vector3.new(0.08, 0.1, 0.05), CFrame.new(side * 0.2, 0.72, -1.03), CREAM, true)
	end
	stick(ctx, "Tail", Vector3.new(0, 0.7, 0.6), Vector3.new(0, 0.5, 0.72), 0.08, ctx.body)
	face(ctx, Vector3.new(0, 1.25, -0.84), 0.22, Vector3.new(0, 0.92, -1.1), 0.34)
	return body
end

builders.Toucan = function(ctx)
	local body = roundBox(ctx, "Body", Vector3.new(0.76, 1.0, 0.72), CFrame.new(0, 0.62, 0), 0.26, "Z", ctx.body)
	for _, side in { -1, 1 } do
		add(ctx, "Block", "Foot", Vector3.new(0.14, 0.1, 0.24), CFrame.new(side * 0.16, 0.05, -0.08), Color3.fromRGB(110, 140, 200))
		add(ctx, "Ball", "Wing", Vector3.new(0.12, 0.6, 0.5), CFrame.new(side * 0.4, 0.6, 0.06) * CFrame.Angles(0, 0, side * 0.15), lighter(ctx.body, 0.1))
	end
	add(ctx, "Block", "Tail", Vector3.new(0.3, 0.08, 0.46), CFrame.new(0, 0.3, 0.5) * CFrame.Angles(math.rad(25), 0, 0), ctx.body)
	blob(ctx, "Bib", Vector3.new(0.52, 0.36, 0.08), Vector3.new(0, 0.6, -0.36), CREAM)
	-- The big two-tone beak: orange top, golden bottom, dark tip.
	blob(ctx, "Beak", Vector3.new(0.32, 0.26, 0.76), Vector3.new(0, 0.86, -0.66), ctx.accent)
	blob(ctx, "BeakLow", Vector3.new(0.26, 0.14, 0.58), Vector3.new(0, 0.74, -0.6), Color3.fromRGB(250, 214, 80))
	blob(ctx, "BeakTip", Vector3.new(0.16, 0.18, 0.16), Vector3.new(0, 0.82, -1.0), ctx.body)
	face(ctx, Vector3.new(0, 0.94, -0.36), 0.25)
	return body
end

builders.Zebra = function(ctx)
	legs(ctx, 0.56, 0.18, 0.22, -0.34, 0.34, ctx.body)
	local body = roundBox(ctx, "Body", Vector3.new(0.68, 0.58, 1.08), CFrame.new(0, 0.84, 0.04), 0.2, "X", ctx.body)
	stick(ctx, "Neck", Vector3.new(0, 0.96, -0.36), Vector3.new(0, 1.42, -0.48), 0.34, ctx.body)
	roundBox(ctx, "Head", Vector3.new(0.52, 0.54, 0.66), CFrame.new(0, 1.52, -0.6), 0.16, "Z", ctx.body)
	blob(ctx, "Muzzle", Vector3.new(0.4, 0.24, 0.2), Vector3.new(0, 1.34, -0.92), ctx.accent)
	add(ctx, "Block", "Mane", Vector3.new(0.1, 0.18, 0.66), CFrame.lookAt(Vector3.new(0, 1.46, -0.34), Vector3.new(0, 1.8, -0.52)), ctx.accent)
	for _, side in { -1, 1 } do
		pointyEar(ctx, side, Vector3.new(side * 0.16, 1.86, -0.44), 0.22, 0.14, ctx.body)
	end
	-- Stripes: blocks through the flat flanks of the body, plus one across the brow.
	for _, z in { -0.26, 0.04, 0.34 } do
		add(ctx, "Block", "Stripe", Vector3.new(0.72, 0.36, 0.08), CFrame.new(0, 0.86, z) * CFrame.Angles(math.rad(-12), 0, 0), ctx.accent)
	end
	stick(ctx, "Tail", Vector3.new(0, 1.0, 0.56), Vector3.new(0, 0.62, 0.7), 0.08, ctx.accent)
	face(ctx, Vector3.new(0, 1.62, -0.93), 0.15, Vector3.new(0, 1.47, -0.93), 0.21)
	return body
end

-- Returns the model, its height and its widest horizontal extent (both in studs).
function PetModelBuilder.build(speciesId: string, materialId: string, sizeId: string, origin: CFrame): (Model, number, number)
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
		top = 0,
		half = 0,
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
		-- A few soft glints, not a firework.
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "MutationSparkle"
		sparkle.Color = ColorSequence.new(mat.color or pet.accentColor)
		sparkle.LightEmission = 0.4
		sparkle.Rate = 1.5 + mat.tier * 0.5
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Speed = NumberRange.new(0.4, 1.2)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new(0.14 * size.scale, 0)
		sparkle.Transparency = NumberSequence.new(0.25, 1)
		sparkle.Parent = body
		local light = Instance.new("PointLight")
		light.Color = mat.color or pet.accentColor
		light.Range = 4 * size.scale
		light.Brightness = 0.6
		light.Parent = body
	end
	return model, ctx.top * s, ctx.half * 2 * s
end

-- Camera for a 3/4 portrait that fits the whole pet (tall giraffes and wide frogs
-- alike). Used by the UI previews and the review renders.
function PetModelBuilder.portraitCamera(height: number, width: number): (CFrame, number)
	local fit = math.max(height, width * 0.85)
	local target = Vector3.new(0, height * 0.45, 0)
	return CFrame.lookAt(target + Vector3.new(fit * 0.95, fit * 0.35, -fit * 1.7), target), 40
end

return PetModelBuilder
