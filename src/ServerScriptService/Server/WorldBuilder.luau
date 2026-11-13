--!strict
-- Procedurally builds the whole map from primitive parts: Spawn Hub, Throw Line, six
-- biome zones and six player plots. Deterministic (seeded) so every server looks the same.
-- Uses only Instance/datatype APIs so it can also run headless in the Lune test-suite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))

export type PlotInfo = {
	index: number,
	model: Model,
	pad: Part,
	ownerLabel: TextLabel,
	incomeLabel: TextLabel,
	pedestals: { Part },
	petsFolder: Folder,
	spawnCFrame: CFrame,
}

export type WorldInfo = {
	root: Model,
	throwLineCenter: Vector3,
	throwLineCFrame: CFrame,
	hubSpawnCFrame: CFrame,
	plots: { PlotInfo },
	leaderboardLines: { TextLabel },
	partCount: number,
}

local WorldBuilder = {}

WorldBuilder.HubCenter = Vector3.new(0, 0, -150)
WorldBuilder.ThrowLineZ = 0

local seed = 1
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function randRange(a: number, b: number): number
	return a + (b - a) * rand()
end

local partCount = 0

type PartProps = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?,
	castShadow: boolean?,
	parent: Instance,
}

local function makePart(p: PartProps): Part
	local part = Instance.new("Part")
	part.Name = p.name or "Part"
	part.Anchored = true
	part.Shape = p.shape or Enum.PartType.Block
	part.Size = p.size
	part.CFrame = p.cframe
	part.Color = p.color
	part.Material = p.material or Enum.Material.SmoothPlastic
	part.Transparency = p.transparency or 0
	part.CanCollide = if p.canCollide == nil then true else p.canCollide
	if p.castShadow == false then
		part.CastShadow = false
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = p.parent
	partCount += 1
	return part
end

local function makeWedge(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = material
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	partCount += 1
	return w
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A SurfaceGui text sign on the -Z (Front) face of `part`.
local function signText(part: BasePart, text: string, color: Color3, face: Enum.NormalId?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 40)
	label.Parent = gui
	return label
end

local function emitter(parent: Instance, color: Color3, rate: number, velocity: Vector3, lifetime: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	e.Speed = NumberRange.new(velocity.Magnitude * 0.8, velocity.Magnitude * 1.2)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(velocity.X, 0, velocity.Z)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Size = NumberSequence.new(size, 0)
	e.LightEmission = 0.6
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Parent = parent
end

------------------------------------------------------------------ props

local function tree(parent: Instance, pos: Vector3, trunk: Color3, leaves: Color3, scale: number)
	makePart({ name = "Trunk", shape = Enum.PartType.Cylinder, size = Vector3.new(8 * scale, 1.6 * scale, 1.6 * scale), cframe = CFrame.new(pos + Vector3.new(0, 4 * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = trunk, material = Enum.Material.Wood, parent = parent })
	makePart({ name = "Leaves", shape = Enum.PartType.Ball, size = Vector3.one * 7 * scale, cframe = CFrame.new(pos + Vector3.new(0, 9 * scale, 0)), color = leaves, material = Enum.Material.Grass, parent = parent })
	makePart({ name = "Leaves", shape = Enum.PartType.Ball, size = Vector3.one * 4.5 * scale, cframe = CFrame.new(pos + Vector3.new(2 * scale, 11.5 * scale, 1 * scale)), color = leaves:Lerp(Color3.new(1, 1, 1), 0.12), material = Enum.Material.Grass, parent = parent })
end

local function flower(parent: Instance, pos: Vector3, color: Color3)
	makePart({ name = "Stem", size = Vector3.new(0.3, 1.6, 0.3), cframe = CFrame.new(pos + Vector3.new(0, 0.8, 0)), color = Color3.fromRGB(60, 150, 50), canCollide = false, parent = parent })
	makePart({ name = "Bloom", shape = Enum.PartType.Ball, size = Vector3.one * 1, cframe = CFrame.new(pos + Vector3.new(0, 1.7, 0)), color = color, material = Enum.Material.Neon, canCollide = false, parent = parent })
end

local function cactus(parent: Instance, pos: Vector3, scale: number)
	local green = Color3.fromRGB(70, 150, 70)
	makePart({ name = "Cactus", shape = Enum.PartType.Cylinder, size = Vector3.new(10 * scale, 2.4 * scale, 2.4 * scale), cframe = CFrame.new(pos + Vector3.new(0, 5 * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = green, material = Enum.Material.Grass, parent = parent })
	makePart({ name = "Arm", shape = Enum.PartType.Cylinder, size = Vector3.new(4 * scale, 1.5 * scale, 1.5 * scale), cframe = CFrame.new(pos + Vector3.new(2 * scale, 6 * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = green, material = Enum.Material.Grass, parent = parent })
	makePart({ name = "Flower", shape = Enum.PartType.Ball, size = Vector3.one * 1.2 * scale, cframe = CFrame.new(pos + Vector3.new(0, 10.2 * scale, 0)), color = Color3.fromRGB(255, 110, 170), material = Enum.Material.Neon, canCollide = false, parent = parent })
end

local function dune(parent: Instance, pos: Vector3, color: Color3, scale: number)
	makePart({ name = "Dune", shape = Enum.PartType.Ball, size = Vector3.new(30, 12, 30) * scale, cframe = CFrame.new(pos + Vector3.new(0, -2, 0)), color = color, material = Enum.Material.Sand, parent = parent })
end

local function iceSpike(parent: Instance, pos: Vector3, scale: number)
	local h = 10 * scale
	local base = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rand() * math.pi * 2, 0)
	for i = 0, 3 do
		makeWedge("IceSpike", Vector3.new(3 * scale, h, 1.5 * scale), base * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, -0.75 * scale), Color3.fromRGB(170, 220, 255), Enum.Material.Ice, parent)
	end
end

local function rock(parent: Instance, pos: Vector3, color: Color3, material: Enum.Material, scale: number)
	makePart({ name = "Rock", size = Vector3.new(randRange(4, 9), randRange(3, 7), randRange(4, 9)) * scale, cframe = CFrame.new(pos + Vector3.new(0, 1.5 * scale, 0)) * CFrame.Angles(rand(), rand() * 6, rand() * 0.5), color = color, material = material, parent = parent })
end

local function pool(parent: Instance, pos: Vector3, color: Color3, diameter: number, emit: boolean)
	local p = makePart({ name = "Pool", shape = Enum.PartType.Cylinder, size = Vector3.new(0.4, diameter, diameter), cframe = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = color, material = Enum.Material.Neon, canCollide = false, parent = parent })
	if emit then
		emitter(p, color, 3, Vector3.new(0, 4, 0), 2, 0.8)
	end
end

local function mushroom(parent: Instance, pos: Vector3, cap: Color3, scale: number)
	makePart({ name = "Stalk", shape = Enum.PartType.Cylinder, size = Vector3.new(4 * scale, 1.2 * scale, 1.2 * scale), cframe = CFrame.new(pos + Vector3.new(0, 2 * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(230, 220, 200), parent = parent })
	makePart({ name = "Cap", shape = Enum.PartType.Ball, size = Vector3.new(5, 2.5, 5) * scale, cframe = CFrame.new(pos + Vector3.new(0, 4.2 * scale, 0)), color = cap, material = Enum.Material.Neon, parent = parent })
end

local function deadTree(parent: Instance, pos: Vector3, color: Color3, scale: number)
	makePart({ name = "DeadTrunk", size = Vector3.new(1.4, 12, 1.4) * scale, cframe = CFrame.new(pos + Vector3.new(0, 6 * scale, 0)) * CFrame.Angles(0, 0, randRange(-0.15, 0.15)), color = color, material = Enum.Material.Wood, parent = parent })
	makePart({ name = "Branch", size = Vector3.new(6, 0.8, 0.8) * scale, cframe = CFrame.new(pos + Vector3.new(1.5 * scale, 9 * scale, 0)) * CFrame.Angles(0, 0, 0.6), color = color, material = Enum.Material.Wood, parent = parent })
end

local function barrel(parent: Instance, pos: Vector3)
	local b = makePart({ name = "Barrel", shape = Enum.PartType.Cylinder, size = Vector3.new(4, 3, 3), cframe = CFrame.new(pos + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(230, 200, 30), material = Enum.Material.Metal, parent = parent })
	makePart({ name = "Band", shape = Enum.PartType.Cylinder, size = Vector3.new(0.6, 3.1, 3.1), cframe = b.CFrame, color = Color3.fromRGB(30, 30, 30), material = Enum.Material.Metal, parent = parent })
	makePart({ name = "Ooze", shape = Enum.PartType.Ball, size = Vector3.new(2, 0.6, 2), cframe = CFrame.new(pos + Vector3.new(0, 4, 0)), color = Color3.fromRGB(180, 255, 40), material = Enum.Material.Neon, canCollide = false, parent = parent })
end

-- Small interactable landmark: a ProximityPrompt the client turns into "open panel".
local function prompt(part: BasePart, action: string, object: string, panel: string)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R -- E is reserved for throwing
	pp.GamepadKeyCode = Enum.KeyCode.ButtonY
	pp:SetAttribute("OpenPanel", panel)
	pp.Parent = part
end

local function ball(parent: Instance, name: string, d: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return makePart({ name = name, shape = Enum.PartType.Ball, size = d, cframe = CFrame.new(pos), color = color, material = material, canCollide = collide == true, parent = parent })
end

local function cloud(parent: Instance, pos: Vector3, scale: number)
	local white = Color3.fromRGB(255, 255, 255)
	for i, o in { Vector3.new(0, 0, 0), Vector3.new(9, -2, 3), Vector3.new(-9, -2, -2), Vector3.new(3, 3, -4) } do
		local d = (if i == 1 then 16 else 11) * scale
		makePart({ name = "Cloud", shape = Enum.PartType.Ball, size = Vector3.new(d * 1.4, d, d), cframe = CFrame.new(pos + o * scale), color = white, material = Enum.Material.SmoothPlastic, transparency = 0.08, canCollide = false, castShadow = false, parent = parent })
	end
end

-- Ridge of "mountains" (blocks rotated 45 degrees, half buried) as a biome backdrop.
local function mountain(parent: Instance, pos: Vector3, size: number, length: number, color: Color3, material: Enum.Material, cap: Color3?)
	makePart({ name = "Mountain", size = Vector3.new(size, size, length), cframe = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(45)), color = color, material = material, castShadow = false, parent = parent })
	if cap then
		local capSize = size * 0.32
		makePart({ name = "MountainCap", size = Vector3.new(capSize, capSize, length * 0.7), cframe = CFrame.new(pos + Vector3.new(0, size * 0.707 - capSize * 0.68, 0)) * CFrame.Angles(0, 0, math.rad(45)), color = cap, material = Enum.Material.Snow, castShadow = false, parent = parent })
	end
end

local function bush(parent: Instance, pos: Vector3, color: Color3, scale: number)
	ball(parent, "Bush", Vector3.new(6, 4.5, 6) * scale, pos + Vector3.new(0, 1.5 * scale, 0), color, Enum.Material.Grass, true)
	ball(parent, "Bush", Vector3.new(4, 3.5, 4) * scale, pos + Vector3.new(2.4 * scale, 1.2 * scale, 1 * scale), color:Lerp(Color3.new(1, 1, 1), 0.1), Enum.Material.Grass)
	if rand() < 0.5 then
		ball(parent, "Berry", Vector3.one * 0.9 * scale, pos + Vector3.new(-1 * scale, 3.4 * scale, -1.6 * scale), Color3.fromRGB(235, 60, 110), Enum.Material.SmoothPlastic)
	end
end

local reservedHub = {
	{ -124, -78, -60, -14 }, -- Gym      (xMin, zMin, xMax, zMax)
	{ 60, -78, 124, -14 }, -- Food Shop
	{ -40, -252, 40, -218 }, -- Leaderboard
}
local function hubReserved(pos: Vector3): boolean
	for _, r in reservedHub do
		if pos.X > r[1] and pos.X < r[3] and pos.Z > r[2] and pos.Z < r[4] then
			return true
		end
	end
	return false
end

------------------------------------------------------------------ sections

local function buildHub(root: Instance): CFrame
	local hub = folder("SpawnHub", root)
	local c = WorldBuilder.HubCenter
	makePart({ name = "HubGround", size = Vector3.new(440, 4, 300), cframe = CFrame.new(c.X, -2, c.Z), color = Color3.fromRGB(120, 205, 100), material = Enum.Material.Grass, parent = hub })
	makePart({ name = "Plaza", shape = Enum.PartType.Cylinder, size = Vector3.new(1, 150, 150), cframe = CFrame.new(c.X, 0.5, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(245, 235, 210), material = Enum.Material.Pavement, parent = hub })
	makePart({ name = "PlazaRing", shape = Enum.PartType.Cylinder, size = Vector3.new(1.1, 120, 120), cframe = CFrame.new(c.X, 0.55, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(255, 180, 90), material = Enum.Material.Pavement, parent = hub })
	makePart({ name = "PlazaInner", shape = Enum.PartType.Cylinder, size = Vector3.new(1.2, 100, 100), cframe = CFrame.new(c.X, 0.6, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(250, 240, 220), material = Enum.Material.Pavement, parent = hub })

	-- Paths from the plaza to the Throw Line and plots.
	makePart({ name = "PathToThrowLine", size = Vector3.new(26, 1, 100), cframe = CFrame.new(0, 0.5, -60), color = Color3.fromRGB(240, 220, 180), material = Enum.Material.Pavement, parent = hub })
	makePart({ name = "PathWest", size = Vector3.new(110, 1, 18), cframe = CFrame.new(-110, 0.5, c.Z), color = Color3.fromRGB(240, 220, 180), material = Enum.Material.Pavement, parent = hub })
	makePart({ name = "PathEast", size = Vector3.new(110, 1, 18), cframe = CFrame.new(110, 0.5, c.Z), color = Color3.fromRGB(240, 220, 180), material = Enum.Material.Pavement, parent = hub })

	-- Food fountain centerpiece.
	makePart({ name = "FountainBase", shape = Enum.PartType.Cylinder, size = Vector3.new(3, 34, 34), cframe = CFrame.new(c.X, 2, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(120, 180, 255), material = Enum.Material.Marble, parent = hub })
	local water = makePart({ name = "FountainWater", shape = Enum.PartType.Cylinder, size = Vector3.new(0.5, 30, 30), cframe = CFrame.new(c.X, 3.4, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(90, 200, 255), material = Enum.Material.Glass, transparency = 0.3, canCollide = false, parent = hub })
	emitter(water, Color3.fromRGB(160, 230, 255), 25, Vector3.new(0, 18, 0), 1.6, 1.2)
	makePart({ name = "FountainPillar", shape = Enum.PartType.Cylinder, size = Vector3.new(14, 4, 4), cframe = CFrame.new(c.X, 9, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(250, 250, 255), material = Enum.Material.Marble, parent = hub })
	local donut = makePart({ name = "GiantDonut", shape = Enum.PartType.Cylinder, size = Vector3.new(3, 12, 12), cframe = CFrame.new(c.X, 19, c.Z) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromRGB(255, 130, 190), material = Enum.Material.SmoothPlastic, parent = hub })
	makePart({ name = "DonutHole", shape = Enum.PartType.Cylinder, size = Vector3.new(3.2, 4.5, 4.5), cframe = donut.CFrame, color = Color3.fromRGB(120, 180, 255), material = Enum.Material.Neon, canCollide = false, parent = hub })
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		makePart({ name = "Sprinkle", size = Vector3.new(0.6, 1.8, 0.6), cframe = donut.CFrame * CFrame.Angles(a, 0, 0) * CFrame.new(1.6, 4.2, 0) * CFrame.Angles(0, 0, a), color = Color3.fromHSV(i / 8, 0.7, 1), material = Enum.Material.Neon, canCollide = false, parent = hub })
	end

	-- Title sign facing players who spawn.
	local signPost = makePart({ name = "TitleSign", size = Vector3.new(60, 14, 2), cframe = CFrame.new(c.X, 26, c.Z + 60), color = Color3.fromRGB(255, 120, 60), material = Enum.Material.SmoothPlastic, parent = hub })
	signText(signPost, "SNACK FORCE: PET TOSS", Color3.fromRGB(255, 250, 230))
	for _, x in { -27, 27 } do
		makePart({ name = "SignPole", size = Vector3.new(2, 20, 2), cframe = CFrame.new(c.X + x, 10, c.Z + 60), color = Color3.fromRGB(110, 70, 50), material = Enum.Material.Wood, parent = hub })
	end

	-- Lamp posts around the plaza.
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local pos = c + Vector3.new(math.cos(a) * 80, 0, math.sin(a) * 80)
		makePart({ name = "LampPole", shape = Enum.PartType.Cylinder, size = Vector3.new(12, 0.8, 0.8), cframe = CFrame.new(pos + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(60, 60, 80), material = Enum.Material.Metal, parent = hub })
		local bulb = makePart({ name = "LampBulb", shape = Enum.PartType.Ball, size = Vector3.one * 2.2, cframe = CFrame.new(pos + Vector3.new(0, 12.5, 0)), color = Color3.fromHSV(i / 10, 0.4, 1), material = Enum.Material.Neon, parent = hub })
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.2
		light.Color = bulb.Color
		light.Parent = bulb
	end
	for i = 1, 24 do
		local a = rand() * math.pi * 2
		local r = randRange(85, 130)
		local pos = c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r * 0.9)
		if math.abs(pos.X) < 110 and pos.Z < -40 and pos.Z > -260 and math.abs(pos.X) > 20 and not hubReserved(pos) then
			tree(hub, pos, Color3.fromRGB(120, 80, 50), Color3.fromHSV(0.28 + rand() * 0.1, 0.6, 0.75), randRange(0.8, 1.2))
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(c.X, 1.2, c.Z + 30) * CFrame.Angles(0, math.pi, 0)
	spawn.Color = Color3.fromRGB(255, 220, 90)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = hub
	partCount += 1
	return CFrame.new(c.X, 5, c.Z + 30) * CFrame.Angles(0, math.pi, 0)
end

------------------------------------------------------------------ hub attractions

local function buildGym(parent: Instance)
	local gym = folder("Gym", parent)
	local c = GameConfig.GymCenter
	local r = GameConfig.GymRadius
	makePart({ name = "GymFloor", shape = Enum.PartType.Cylinder, size = Vector3.new(0.8, r * 2, r * 2), cframe = CFrame.new(c.X, 0.4, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(70, 60, 90), material = Enum.Material.Rubber, parent = gym })
	makePart({ name = "GymRing", shape = Enum.PartType.Cylinder, size = Vector3.new(0.7, r * 2 + 2, r * 2 + 2), cframe = CFrame.new(c.X, 0.35, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(255, 90, 120), material = Enum.Material.Neon, canCollide = false, parent = gym })
	-- Arch facing the path (+X side) with the 2x sign.
	local archX = c.X + r - 2
	for _, dz in { -10, 10 } do
		makePart({ name = "GymPillar", size = Vector3.new(2.5, 18, 2.5), cframe = CFrame.new(archX, 9, c.Z + dz), color = Color3.fromRGB(255, 90, 120), parent = gym })
	end
	local sign = makePart({ name = "GymSign", size = Vector3.new(1.5, 7, 24), cframe = CFrame.new(archX, 19, c.Z), color = Color3.fromRGB(60, 40, 80), parent = gym })
	signText(sign, "STRENGTH GYM\n2x TRAINING", Color3.fromRGB(255, 230, 120), Enum.NormalId.Right)
	signText(sign, "STRENGTH GYM", Color3.fromRGB(255, 230, 120), Enum.NormalId.Left)
	-- Dumbbell rack.
	for i = 0, 3 do
		local pos = c + Vector3.new(-14, 0, -12 + i * 8)
		makePart({ name = "Rack", size = Vector3.new(3, 3, 6), cframe = CFrame.new(pos + Vector3.new(0, 2.3, 0)), color = Color3.fromRGB(50, 50, 60), material = Enum.Material.Metal, parent = gym })
		makePart({ name = "Bar", shape = Enum.PartType.Cylinder, size = Vector3.new(4, 0.5, 0.5), cframe = CFrame.new(pos + Vector3.new(0, 4.2, 0)) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromRGB(200, 200, 210), material = Enum.Material.Metal, parent = gym })
		for _, dz in { -2, 2 } do
			makePart({ name = "Weight", shape = Enum.PartType.Cylinder, size = Vector3.new(0.8, 2.4, 2.4), cframe = CFrame.new(pos + Vector3.new(0, 4.2, dz)) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromHSV(i / 4, 0.7, 0.9), parent = gym })
		end
	end
	-- Punching bags on a frame.
	for i, dz in { -8, 8 } do
		local pos = c + Vector3.new(4, 0, dz)
		makePart({ name = "BagPost", size = Vector3.new(1, 14, 1), cframe = CFrame.new(pos + Vector3.new(-3, 7, 0)), color = Color3.fromRGB(60, 60, 70), material = Enum.Material.Metal, parent = gym })
		makePart({ name = "BagArm", size = Vector3.new(4, 0.8, 0.8), cframe = CFrame.new(pos + Vector3.new(-1, 13.6, 0)), color = Color3.fromRGB(60, 60, 70), material = Enum.Material.Metal, parent = gym })
		makePart({ name = "PunchingBag", shape = Enum.PartType.Cylinder, size = Vector3.new(6, 2.8, 2.8), cframe = CFrame.new(pos + Vector3.new(0, 9.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = if i == 1 then Color3.fromRGB(220, 60, 60) else Color3.fromRGB(60, 120, 230), material = Enum.Material.Fabric, parent = gym })
	end
	-- Bench press.
	local bench = c + Vector3.new(-4, 0, 16)
	makePart({ name = "Bench", size = Vector3.new(8, 1, 2.5), cframe = CFrame.new(bench + Vector3.new(0, 2.2, 0)), color = Color3.fromRGB(40, 40, 50), material = Enum.Material.Fabric, parent = gym })
	makePart({ name = "BenchBar", shape = Enum.PartType.Cylinder, size = Vector3.new(7, 0.4, 0.4), cframe = CFrame.new(bench + Vector3.new(-2, 4.5, 0)) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromRGB(200, 200, 210), material = Enum.Material.Metal, parent = gym })
	for _, dz in { -3.2, 3.2 } do
		makePart({ name = "Plate", shape = Enum.PartType.Cylinder, size = Vector3.new(0.6, 3, 3), cframe = CFrame.new(bench + Vector3.new(-2, 4.5, dz)) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromRGB(255, 200, 60), parent = gym })
	end
end

local function buildShopStall(parent: Instance)
	local stall = folder("FoodShopStall", parent)
	local c = Vector3.new(92, 0, -46)
	-- Counter faces -X (towards the path).
	local counter = makePart({ name = "ShopCounter", size = Vector3.new(6, 4, 22), cframe = CFrame.new(c.X - 6, 2, c.Z), color = Color3.fromRGB(200, 140, 80), material = Enum.Material.WoodPlanks, parent = stall })
	makePart({ name = "CounterTop", size = Vector3.new(7, 0.6, 23), cframe = CFrame.new(c.X - 6, 4.3, c.Z), color = Color3.fromRGB(250, 240, 220), parent = stall })
	makePart({ name = "StallBack", size = Vector3.new(1.5, 16, 26), cframe = CFrame.new(c.X + 8, 8, c.Z), color = Color3.fromRGB(255, 200, 120), material = Enum.Material.WoodPlanks, parent = stall })
	for _, dz in { -12, 12 } do
		makePart({ name = "StallPost", size = Vector3.new(1.5, 18, 1.5), cframe = CFrame.new(c.X - 8, 9, c.Z + dz), color = Color3.fromRGB(150, 100, 60), material = Enum.Material.Wood, parent = stall })
	end
	-- Striped awning.
	for i = 0, 7 do
		makePart({ name = "Awning", size = Vector3.new(19, 0.6, 3.25), cframe = CFrame.new(c.X - 0.5, 18.5, c.Z - 11.4 + i * 3.25) * CFrame.Angles(0, 0, math.rad(-12)), color = if i % 2 == 0 then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(255, 250, 240), parent = stall })
	end
	local sign = makePart({ name = "ShopSign", size = Vector3.new(1, 6, 22), cframe = CFrame.new(c.X - 9.5, 22.5, c.Z), color = Color3.fromRGB(255, 150, 50), parent = stall })
	signText(sign, "FOOD SHOP", Color3.new(1, 1, 1), Enum.NormalId.Left)
	signText(sign, "FOOD SHOP", Color3.new(1, 1, 1), Enum.NormalId.Right)
	-- Giant snacks on display.
	ball(stall, "GiantBerry", Vector3.one * 4, c + Vector3.new(-6, 6.6, -7), Color3.fromRGB(230, 60, 120), Enum.Material.SmoothPlastic)
	makePart({ name = "GiantBone", shape = Enum.PartType.Cylinder, size = Vector3.new(6, 1.6, 1.6), cframe = CFrame.new(c + Vector3.new(-6, 5.6, 0)) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromRGB(240, 225, 200), parent = stall })
	ball(stall, "GiantChili", Vector3.new(2.4, 2.4, 4.5), c + Vector3.new(-6, 6, 7), Color3.fromRGB(255, 60, 30), Enum.Material.SmoothPlastic)
	makePart({ name = "GiantCookie", size = Vector3.new(3, 3, 3), cframe = CFrame.new(c + Vector3.new(2, 24.5, 0)) * CFrame.Angles(0.4, 0.6, 0.2), color = Color3.fromRGB(150, 110, 255), material = Enum.Material.Neon, canCollide = false, parent = stall })
	prompt(counter, "Open Food Shop", "Snack Stall", "Shop")
end

local function buildFuseAltar(parent: Instance)
	local altar = folder("FuseAltar", parent)
	local c = WorldBuilder.HubCenter + Vector3.new(-48, 0, -45)
	local base = makePart({ name = "AltarBase", shape = Enum.PartType.Cylinder, size = Vector3.new(2, 16, 16), cframe = CFrame.new(c + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(90, 70, 140), material = Enum.Material.Marble, parent = altar })
	makePart({ name = "AltarStep", shape = Enum.PartType.Cylinder, size = Vector3.new(1.5, 10, 10), cframe = CFrame.new(c + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(150, 110, 220), material = Enum.Material.Marble, parent = altar })
	local crystal = makePart({ name = "FuseCrystal", size = Vector3.new(3.5, 3.5, 3.5), cframe = CFrame.new(c + Vector3.new(0, 10, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color = Color3.fromRGB(200, 120, 255), material = Enum.Material.Neon, canCollide = false, parent = altar })
	emitter(crystal, Color3.fromRGB(220, 160, 255), 10, Vector3.new(0, 3, 0), 1.6, 0.6)
	local light = Instance.new("PointLight")
	light.Color = crystal.Color
	light.Range = 20
	light.Brightness = 2
	light.Parent = crystal
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2
		ball(altar, "FuseOrb", Vector3.one * 1.6, c + Vector3.new(math.cos(a) * 5, 6, math.sin(a) * 5), Color3.fromHSV(0.75 + i * 0.07, 0.6, 1), Enum.Material.Neon)
		makePart({ name = "OrbPillar", size = Vector3.new(0.8, 2.5, 0.8), cframe = CFrame.new(c + Vector3.new(math.cos(a) * 5, 4.3, math.sin(a) * 5)), color = Color3.fromRGB(240, 235, 255), material = Enum.Material.Marble, parent = altar })
	end
	local sign = makePart({ name = "AltarSign", size = Vector3.new(16, 4, 1), cframe = CFrame.new(c + Vector3.new(0, 16, 0)) * CFrame.Angles(0, math.pi, 0), color = Color3.fromRGB(90, 60, 150), canCollide = false, parent = altar })
	signText(sign, "PETS & FUSE", Color3.new(1, 1, 1))
	signText(sign, "PETS & FUSE", Color3.new(1, 1, 1), Enum.NormalId.Back)
	prompt(base, "Pets & Fuse", "Fusion Altar", "Pets")
end

local function buildIndexBoard(parent: Instance)
	local board = folder("PetIndexBoard", parent)
	local c = WorldBuilder.HubCenter + Vector3.new(48, 0, -45)
	local stand = makePart({ name = "IndexStand", size = Vector3.new(10, 3, 6), cframe = CFrame.new(c + Vector3.new(0, 1.5, 0)), color = Color3.fromRGB(70, 110, 170), material = Enum.Material.Marble, parent = board })
	-- An open book: two tilted pages.
	for _, side in { -1, 1 } do
		makePart({ name = "Page", size = Vector3.new(7, 0.6, 9), cframe = CFrame.new(c + Vector3.new(side * 3.4, 6, 0)) * CFrame.Angles(0, 0, side * math.rad(-14)), color = Color3.fromRGB(255, 250, 235), parent = board })
		makePart({ name = "Cover", size = Vector3.new(7.4, 0.4, 9.4), cframe = CFrame.new(c + Vector3.new(side * 3.4, 5.55, 0)) * CFrame.Angles(0, 0, side * math.rad(-14)), color = Color3.fromRGB(70, 160, 255), parent = board })
	end
	makePart({ name = "BookPost", size = Vector3.new(1.2, 3.5, 1.2), cframe = CFrame.new(c + Vector3.new(0, 4, 0)), color = Color3.fromRGB(50, 80, 140), parent = board })
	local sign = makePart({ name = "IndexSign", size = Vector3.new(16, 4, 1), cframe = CFrame.new(c + Vector3.new(0, 14, 0)) * CFrame.Angles(0, math.pi, 0), color = Color3.fromRGB(40, 90, 170), canCollide = false, parent = board })
	signText(sign, "PET INDEX", Color3.new(1, 1, 1))
	signText(sign, "PET INDEX", Color3.new(1, 1, 1), Enum.NormalId.Back)
	ball(board, "IndexStar", Vector3.one * 2.2, c + Vector3.new(0, 10, 0), Color3.fromRGB(255, 230, 90), Enum.Material.Neon)
	prompt(stand, "Open Pet Index", "Pet Index", "Index")
end

local function buildLeaderboard(parent: Instance): { TextLabel }
	local lb = folder("Leaderboard", parent)
	local z = -236
	-- Rotated so the Front (text) face points +Z, towards the plaza.
	local board = makePart({ name = "LeaderboardBoard", size = Vector3.new(40, 26, 2), cframe = CFrame.new(0, 17, z) * CFrame.Angles(0, math.pi, 0), color = Color3.fromRGB(35, 30, 70), parent = lb })
	makePart({ name = "LeaderboardFrame", size = Vector3.new(43, 29, 1.6), cframe = CFrame.new(0, 17, z - 0.6), color = Color3.fromRGB(255, 200, 60), material = Enum.Material.Neon, parent = lb })
	for _, x in { -18, 18 } do
		makePart({ name = "LeaderboardLeg", size = Vector3.new(2, 6, 2), cframe = CFrame.new(x, 3, z), color = Color3.fromRGB(60, 50, 90), parent = lb })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = gui
	local function row(text: string, order: number, height: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, 0, 0, height)
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextScaled = true
		l.Font = Enum.Font.FredokaOne
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.3
		l.LayoutOrder = order
		l.Parent = gui
		return l
	end
	row("TOP THROWS (this server)", 0, 80, Color3.fromRGB(255, 220, 80))
	local lines = {}
	for i = 1, 6 do
		table.insert(lines, row(string.format("%d. ---", i), i, 58, if i == 1 then Color3.fromRGB(255, 230, 120) else Color3.fromRGB(235, 235, 255)))
	end
	return lines
end

local function buildHubDecor(parent: Instance)
	local decor = folder("HubDecor", parent)
	local c = WorldBuilder.HubCenter
	-- Bunting between the plaza lamps (same ring as buildHub).
	for i = 1, 10 do
		local a1, a2 = i / 10 * math.pi * 2, (i + 1) / 10 * math.pi * 2
		local p1 = c + Vector3.new(math.cos(a1) * 80, 11.8, math.sin(a1) * 80)
		local p2 = c + Vector3.new(math.cos(a2) * 80, 11.8, math.sin(a2) * 80)
		local mid = (p1 + p2) / 2
		local len = (p2 - p1).Magnitude
		local basis = CFrame.lookAt(mid, p2)
		makePart({ name = "BuntingString", size = Vector3.new(0.2, 0.2, len), cframe = basis, color = Color3.fromRGB(250, 250, 250), canCollide = false, castShadow = false, parent = decor })
		for f = 1, 6 do
			local t = (f - 0.5) / 6 - 0.5
			makeWedge("Flag", Vector3.new(0.15, 2.2, 2.4), basis * CFrame.new(0, -1.2, t * len) * CFrame.Angles(0, 0, math.pi), Color3.fromHSV((i * 6 + f) % 7 / 7, 0.65, 1), Enum.Material.SmoothPlastic, decor)
		end
	end
	-- Balloons drifting over the plaza.
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local pos = c + Vector3.new(math.cos(a) * randRange(30, 60), randRange(32, 48), math.sin(a) * randRange(30, 60))
		ball(decor, "Balloon", Vector3.new(4, 5, 4), pos, Color3.fromHSV(i / 12, 0.6, 1), Enum.Material.SmoothPlastic)
		makePart({ name = "BalloonString", size = Vector3.new(0.1, 8, 0.1), cframe = CFrame.new(pos - Vector3.new(0, 6.5, 0)), color = Color3.fromRGB(240, 240, 240), canCollide = false, castShadow = false, parent = decor })
	end
	-- Fence around the hub's outer edge.
	local fenceColor = Color3.fromRGB(255, 245, 230)
	local runs = {
		{ Vector3.new(-218, 0, -298), Vector3.new(218, 0, -298) },
		{ Vector3.new(-218, 0, -298), Vector3.new(-218, 0, -2) },
		{ Vector3.new(218, 0, -298), Vector3.new(218, 0, -2) },
	}
	for _, run in runs do
		local a, b = run[1], run[2]
		local len = (b - a).Magnitude
		local basis = CFrame.lookAt((a + b) / 2, b)
		for _, y in { 2, 4 } do
			makePart({ name = "FenceRail", size = Vector3.new(0.6, 0.6, len), cframe = basis + Vector3.new(0, y, 0), color = fenceColor, material = Enum.Material.WoodPlanks, parent = decor })
		end
		local posts = math.floor(len / 24)
		for k = 0, posts do
			local p = a:Lerp(b, k / posts)
			makePart({ name = "FencePost", size = Vector3.new(1, 5.5, 1), cframe = CFrame.new(p + Vector3.new(0, 2.75, 0)), color = fenceColor, material = Enum.Material.WoodPlanks, parent = decor })
		end
	end
	-- Hedges and flower beds along the fence.
	for _ = 1, 40 do
		local side = rand()
		local pos
		if side < 0.4 then
			pos = Vector3.new(randRange(-205, 205), 0, randRange(-292, -280))
		elseif side < 0.7 then
			pos = Vector3.new(randRange(-212, -200), 0, randRange(-280, -20))
		else
			pos = Vector3.new(randRange(200, 212), 0, randRange(-280, -20))
		end
		if rand() < 0.6 then
			bush(decor, pos, Color3.fromHSV(0.28 + rand() * 0.06, 0.6, 0.65), randRange(0.8, 1.4))
		else
			flower(decor, pos, Color3.fromHSV(rand(), 0.6, 1))
		end
	end
	-- Paths from the plaza to the north and south plot rows.
	for _, z in { -80, -220 } do
		for _, sx in { -1, 1 } do
			makePart({ name = "PlotPath", size = Vector3.new(74, 1, 14), cframe = CFrame.new(sx * 91, 0.5, z), color = Color3.fromRGB(240, 220, 180), material = Enum.Material.Pavement, parent = decor })
		end
	end
	-- Signposts at the plaza edge.
	local post = makePart({ name = "Signpost", size = Vector3.new(1, 10, 1), cframe = CFrame.new(18, 5, -100), color = Color3.fromRGB(120, 80, 50), material = Enum.Material.Wood, parent = decor })
	local arrows = {
		{ text = "^ THROW LINE ^", y = 3.2, hue = 0 },
		{ text = "GYM 2x >", y = 1.2, hue = 0.2 },
		{ text = "< FOOD SHOP", y = -0.8, hue = 0.4 },
	}
	for _, a in arrows do
		local plank = makePart({ name = "SignArrow", size = Vector3.new(7, 1.6, 0.4), cframe = post.CFrame * CFrame.new(0, a.y, 0), color = Color3.fromHSV(a.hue, 0.6, 0.95), canCollide = false, parent = decor })
		signText(plank, a.text, Color3.new(1, 1, 1))
	end
end

local function buildHubAttractions(root: Instance): { TextLabel }
	local hub = root:FindFirstChild("SpawnHub") or root
	buildGym(hub)
	buildShopStall(hub)
	buildFuseAltar(hub)
	buildIndexBoard(hub)
	buildHubDecor(hub)
	return buildLeaderboard(hub)
end

local function buildThrowLine(root: Instance): CFrame
	local tl = folder("ThrowLine", root)
	local z = WorldBuilder.ThrowLineZ
	makePart({ name = "LaunchPad", size = Vector3.new(130, 1.4, 34), cframe = CFrame.new(0, 0.7, z - 17), color = Color3.fromRGB(70, 80, 120), material = Enum.Material.DiamondPlate, parent = tl })
	makePart({ name = "PadStripe", size = Vector3.new(130, 1.5, 3), cframe = CFrame.new(0, 0.72, z - 33), color = Color3.fromRGB(255, 210, 60), material = Enum.Material.SmoothPlastic, parent = tl })
	local line = makePart({ name = "Line", size = Vector3.new(130, 1.6, 2), cframe = CFrame.new(0, 0.75, z - 1), color = Color3.fromRGB(255, 70, 90), material = Enum.Material.Neon, canCollide = true, parent = tl })
	emitter(line, Color3.fromRGB(255, 120, 140), 20, Vector3.new(0, 6, 0), 1, 0.6)
	-- Invisible wall: players stay behind the line, food flies over it.
	makePart({ name = "LineBarrier", size = Vector3.new(130, 14, 1), cframe = CFrame.new(0, 7, z + 0.5), color = Color3.new(1, 0, 0), transparency = 1, parent = tl })

	local arch = folder("Arch", tl)
	for _, x in { -64, 64 } do
		makePart({ name = "ArchPillar", size = Vector3.new(4, 24, 4), cframe = CFrame.new(x, 12, z - 2), color = Color3.fromRGB(255, 255, 255), material = Enum.Material.SmoothPlastic, parent = arch })
		makePart({ name = "ArchCap", shape = Enum.PartType.Ball, size = Vector3.one * 6, cframe = CFrame.new(x, 25, z - 2), color = Color3.fromRGB(255, 70, 90), material = Enum.Material.Neon, parent = arch })
	end
	local banner = makePart({ name = "ArchBanner", size = Vector3.new(124, 8, 1.5), cframe = CFrame.new(0, 22, z - 2.8), color = Color3.fromRGB(255, 90, 110), material = Enum.Material.SmoothPlastic, parent = arch })
	signText(banner, "THROW LINE  •  Hold E / THROW", Color3.fromRGB(255, 255, 255))
	local backBanner = makePart({ name = "ArchBannerBack", size = Vector3.new(124, 8, 0.2), cframe = CFrame.new(0, 22, z - 1.9) * CFrame.Angles(0, math.pi, 0), color = Color3.fromRGB(255, 90, 110), canCollide = false, parent = arch })
	signText(backBanner, "SNACK FORCE", Color3.fromRGB(255, 255, 255))

	-- Snack crates and launch cannons for flavour.
	for i, x in { -50, -30, 30, 50 } do
		makePart({ name = "SnackCrate", size = Vector3.new(5, 5, 5), cframe = CFrame.new(x, 3.9, z - 26) * CFrame.Angles(0, i * 0.4, 0), color = Color3.fromRGB(190, 130, 70), material = Enum.Material.WoodPlanks, parent = tl })
		makePart({ name = "CrateSnack", shape = Enum.PartType.Ball, size = Vector3.one * 2.5, cframe = CFrame.new(x, 7.4, z - 26), color = Color3.fromHSV(i / 4, 0.7, 1), material = Enum.Material.SmoothPlastic, parent = tl })
	end
	-- Snack cannons at both ends of the pad, aimed down the lane.
	for _, x in { -60, 60 } do
		makePart({ name = "CannonBase", size = Vector3.new(6, 3, 6), cframe = CFrame.new(x, 2.9, z - 8), color = Color3.fromRGB(60, 60, 80), material = Enum.Material.Metal, parent = tl })
		local barrel = makePart({ name = "CannonBarrel", shape = Enum.PartType.Cylinder, size = Vector3.new(9, 3.4, 3.4), cframe = CFrame.new(x, 6.5, z - 7) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(35)), color = Color3.fromRGB(255, 200, 60), material = Enum.Material.Metal, parent = tl })
		makePart({ name = "CannonRim", shape = Enum.PartType.Cylinder, size = Vector3.new(1, 4, 4), cframe = barrel.CFrame * CFrame.new(4.5, 0, 0), color = Color3.fromRGB(255, 90, 110), material = Enum.Material.Neon, canCollide = false, parent = tl })
	end
	-- Glowing chevrons on the first stretch of the Meadow show the throw direction.
	local chevrons = folder("Chevrons", tl)
	for i = 0, 5 do
		local cz = z + 14 + i * 14
		for _, side in { -1, 1 } do
			makePart({ name = "Chevron", size = Vector3.new(9, 0.25, 1.6), cframe = CFrame.new(side * 3.4, 0.12, cz) * CFrame.Angles(0, side * math.rad(-35), 0), color = Color3.fromRGB(255, 240, 120), material = Enum.Material.Neon, transparency = 0.2 + i * 0.1, canCollide = false, castShadow = false, parent = chevrons })
		end
	end
	-- Pad edge lights.
	for i = 0, 12 do
		local x = -60 + i * 10
		ball(tl, "PadLight", Vector3.one * 1.2, Vector3.new(x, 1.6, z - 33), Color3.fromHSV(i / 13, 0.6, 1), Enum.Material.Neon)
	end
	return CFrame.new(0, 3.5, z - 12)
end

type BiomeDecorator = (parent: Instance, pos: Vector3, biome: BiomeConfig.Biome) -> ()

local decorators: { [string]: BiomeDecorator } = {
	Meadow = function(parent, pos, biome)
		local r = rand()
		if r < 0.35 then
			tree(parent, pos, Color3.fromRGB(120, 80, 50), Color3.fromHSV(0.27 + rand() * 0.08, 0.65, 0.8), randRange(0.9, 1.5))
		elseif r < 0.85 then
			flower(parent, pos, Color3.fromHSV(rand(), 0.6, 1))
		else
			rock(parent, pos, Color3.fromRGB(150, 150, 140), Enum.Material.Slate, 0.6)
		end
	end,
	Dunes = function(parent, pos, biome)
		local r = rand()
		if r < 0.4 then
			cactus(parent, pos, randRange(0.8, 1.4))
		elseif r < 0.75 then
			dune(parent, pos, biome.groundColor:Lerp(Color3.new(1, 0.9, 0.7), 0.2), randRange(0.6, 1.4))
		else
			rock(parent, pos, Color3.fromRGB(200, 150, 100), Enum.Material.Sandstone, 1)
		end
	end,
	Tundra = function(parent, pos, biome)
		local r = rand()
		if r < 0.45 then
			iceSpike(parent, pos, randRange(0.8, 1.8))
		elseif r < 0.75 then
			tree(parent, pos, Color3.fromRGB(90, 70, 60), Color3.fromRGB(230, 245, 255), randRange(1, 1.4))
		else
			dune(parent, pos, Color3.fromRGB(245, 250, 255), randRange(0.5, 1))
		end
	end,
	Volcano = function(parent, pos, biome)
		local r = rand()
		if r < 0.35 then
			pool(parent, pos, Color3.fromRGB(255, 110, 20), randRange(8, 20), rand() < 0.5)
		elseif r < 0.8 then
			rock(parent, pos, Color3.fromRGB(45, 35, 35), Enum.Material.Basalt, randRange(1, 2))
		else
			local cone = makePart({ name = "MiniVolcano", shape = Enum.PartType.Ball, size = Vector3.new(26, 18, 26), cframe = CFrame.new(pos), color = Color3.fromRGB(60, 40, 35), material = Enum.Material.Basalt, parent = parent })
			local top = makePart({ name = "Crater", shape = Enum.PartType.Ball, size = Vector3.new(8, 3, 8), cframe = CFrame.new(pos + Vector3.new(0, 8, 0)), color = Color3.fromRGB(255, 120, 20), material = Enum.Material.Neon, canCollide = false, parent = parent })
			emitter(top, Color3.fromRGB(255, 140, 40), 8, Vector3.new(0, 20, 0), 2, 1.5)
			local _ = cone
		end
	end,
	Swamp = function(parent, pos, biome)
		local r = rand()
		if r < 0.35 then
			pool(parent, pos, Color3.fromRGB(140, 255, 50), randRange(8, 18), rand() < 0.5)
		elseif r < 0.65 then
			mushroom(parent, pos, Color3.fromHSV(0.75 + rand() * 0.2, 0.7, 1), randRange(0.8, 1.6))
		else
			deadTree(parent, pos, Color3.fromRGB(70, 60, 50), randRange(0.8, 1.4))
		end
	end,
	Nuclear = function(parent, pos, biome)
		local r = rand()
		if r < 0.3 then
			barrel(parent, pos)
		elseif r < 0.55 then
			pool(parent, pos, Color3.fromRGB(200, 255, 40), randRange(10, 24), rand() < 0.4)
		elseif r < 0.8 then
			rock(parent, pos, Color3.fromRGB(90, 90, 80), Enum.Material.CorrodedMetal, randRange(1, 2))
		else
			deadTree(parent, pos, Color3.fromRGB(50, 50, 45), randRange(1, 1.6))
		end
	end,
}

------------------------------------------------------------------ biome landmarks

local function windmill(parent: Instance, pos: Vector3)
	makePart({ name = "WindmillTower", shape = Enum.PartType.Cylinder, size = Vector3.new(34, 12, 12), cframe = CFrame.new(pos + Vector3.new(0, 17, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(250, 240, 225), material = Enum.Material.Brick, parent = parent })
	makePart({ name = "WindmillRoof", shape = Enum.PartType.Ball, size = Vector3.new(14, 10, 14), cframe = CFrame.new(pos + Vector3.new(0, 35, 0)), color = Color3.fromRGB(200, 70, 60), parent = parent })
	local hubPos = pos + Vector3.new(7, 30, 0)
	ball(parent, "WindmillHub", Vector3.one * 3, hubPos, Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	for i = 0, 3 do
		local a = i * math.pi / 2 + 0.3
		makePart({ name = "WindmillBlade", size = Vector3.new(0.6, 22, 4), cframe = CFrame.new(hubPos + Vector3.new(0.8, 0, 0)) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 11, 0), color = Color3.fromRGB(240, 230, 210), material = Enum.Material.WoodPlanks, canCollide = false, parent = parent })
	end
end

local function rainbowArch(parent: Instance, z: number, radius: number)
	local colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 240, 90), Color3.fromRGB(100, 220, 110), Color3.fromRGB(80, 160, 255), Color3.fromRGB(170, 100, 255) }
	local segments = 18
	for band, color in colors do
		local r = radius - (band - 1) * 3
		for i = 0, segments - 1 do
			local a = (i + 0.5) / segments * math.pi
			local seg = 2 * r * math.sin(math.pi / segments / 2) + 0.6
			makePart({ name = "Rainbow", size = Vector3.new(seg, 3, 3), cframe = CFrame.new(math.cos(a) * r, math.sin(a) * r - 6, z) * CFrame.Angles(0, 0, a + math.pi / 2), color = color, material = Enum.Material.Neon, transparency = 0.15, canCollide = false, castShadow = false, parent = parent })
		end
	end
end

local function pyramid(parent: Instance, pos: Vector3, size: number)
	local steps = 7
	for i = 0, steps - 1 do
		local w = size * (1 - i / steps)
		makePart({ name = "Pyramid", size = Vector3.new(w, size / steps * 0.9, w), cframe = CFrame.new(pos + Vector3.new(0, (i + 0.5) * size / steps * 0.9, 0)), color = Color3.fromRGB(225, 185, 110):Lerp(Color3.fromRGB(255, 225, 150), i / steps), material = Enum.Material.Sandstone, parent = parent })
	end
	ball(parent, "PyramidGem", Vector3.one * size * 0.08, pos + Vector3.new(0, size * 0.92, 0), Color3.fromRGB(80, 230, 255), Enum.Material.Neon)
end

local function palm(parent: Instance, pos: Vector3, scale: number)
	for i = 0, 4 do
		makePart({ name = "PalmTrunk", shape = Enum.PartType.Cylinder, size = Vector3.new(3.4 * scale, (1.6 - i * 0.12) * scale, (1.6 - i * 0.12) * scale), cframe = CFrame.new(pos + Vector3.new(i * 0.5 * scale, (1.7 + i * 3.2) * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2 - 0.1), color = Color3.fromRGB(150, 110, 70), material = Enum.Material.Wood, parent = parent })
	end
	local top = pos + Vector3.new(2.5 * scale, 16 * scale, 0)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		makePart({ name = "PalmLeaf", size = Vector3.new(1.6 * scale, 0.4 * scale, 9 * scale), cframe = CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(25), 0, 0) * CFrame.new(0, 0, -4 * scale), color = Color3.fromRGB(60, 170, 70), material = Enum.Material.Grass, canCollide = false, parent = parent })
	end
	for i = 0, 2 do
		ball(parent, "Coconut", Vector3.one * 1.3 * scale, top + Vector3.new(math.cos(i * 2.1) * 1.2 * scale, -1 * scale, math.sin(i * 2.1) * 1.2 * scale), Color3.fromRGB(110, 70, 40), Enum.Material.Wood)
	end
end

local function igloo(parent: Instance, pos: Vector3)
	ball(parent, "Igloo", Vector3.new(26, 22, 26), pos, Color3.fromRGB(240, 248, 255), Enum.Material.Ice, true)
	makePart({ name = "IglooDoor", shape = Enum.PartType.Cylinder, size = Vector3.new(8, 8, 8), cframe = CFrame.new(pos + Vector3.new(0, 2, -12)) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromRGB(225, 240, 255), material = Enum.Material.Ice, parent = parent })
	makePart({ name = "IglooHole", shape = Enum.PartType.Cylinder, size = Vector3.new(8.2, 5, 5), cframe = CFrame.new(pos + Vector3.new(0, 2, -12)) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromRGB(40, 60, 90), parent = parent })
end

local function snowman(parent: Instance, pos: Vector3, scale: number)
	local white = Color3.fromRGB(250, 252, 255)
	ball(parent, "SnowBase", Vector3.one * 6 * scale, pos + Vector3.new(0, 2.6 * scale, 0), white, Enum.Material.Snow, true)
	ball(parent, "SnowBody", Vector3.one * 4.4 * scale, pos + Vector3.new(0, 6.6 * scale, 0), white, Enum.Material.Snow, true)
	ball(parent, "SnowHead", Vector3.one * 3.2 * scale, pos + Vector3.new(0, 9.6 * scale, 0), white, Enum.Material.Snow, true)
	makePart({ name = "CarrotNose", shape = Enum.PartType.Cylinder, size = Vector3.new(1.6 * scale, 0.5 * scale, 0.5 * scale), cframe = CFrame.new(pos + Vector3.new(0, 9.6 * scale, -1.9 * scale)) * CFrame.Angles(0, math.pi / 2, 0), color = Color3.fromRGB(255, 140, 40), canCollide = false, parent = parent })
	makePart({ name = "Scarf", shape = Enum.PartType.Cylinder, size = Vector3.new(0.8 * scale, 3.6 * scale, 3.6 * scale), cframe = CFrame.new(pos + Vector3.new(0, 8.3 * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(220, 50, 60), material = Enum.Material.Fabric, canCollide = false, parent = parent })
end

local function bigVolcano(parent: Instance, pos: Vector3)
	local rockColor = Color3.fromRGB(55, 40, 38)
	for i = 0, 5 do
		local d = 90 - i * 13
		makePart({ name = "VolcanoTier", shape = Enum.PartType.Cylinder, size = Vector3.new(11, d, d), cframe = CFrame.new(pos + Vector3.new(0, 5 + i * 10, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = rockColor:Lerp(Color3.fromRGB(90, 50, 40), i / 6), material = Enum.Material.Basalt, parent = parent })
	end
	local crater = makePart({ name = "VolcanoCrater", shape = Enum.PartType.Cylinder, size = Vector3.new(2, 18, 18), cframe = CFrame.new(pos + Vector3.new(0, 61, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(255, 120, 20), material = Enum.Material.Neon, canCollide = false, parent = parent })
	emitter(crater, Color3.fromRGB(255, 150, 50), 20, Vector3.new(0, 40, 0), 3, 3)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Range = 60
	light.Brightness = 3
	light.Parent = crater
	-- Lava streams down the sides.
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + 0.4
		makePart({ name = "LavaStream", size = Vector3.new(4, 0.6, 52), cframe = CFrame.new(pos + Vector3.new(math.cos(a) * 26, 32, math.sin(a) * 26)) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(48), 0, 0), color = Color3.fromRGB(255, 100, 20), material = Enum.Material.Neon, canCollide = false, parent = parent })
	end
end

local function coolingTower(parent: Instance, pos: Vector3)
	for i = 0, 4 do
		local d = 30 - math.abs(i - 3) * 3
		makePart({ name = "CoolingTower", shape = Enum.PartType.Cylinder, size = Vector3.new(10, d, d), cframe = CFrame.new(pos + Vector3.new(0, 5 + i * 10, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(170, 170, 160):Lerp(Color3.fromRGB(120, 120, 110), i / 5), material = Enum.Material.Concrete, parent = parent })
	end
	makePart({ name = "HazardStripe", shape = Enum.PartType.Cylinder, size = Vector3.new(2, 31, 31), cframe = CFrame.new(pos + Vector3.new(0, 18, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(240, 210, 30), parent = parent })
	local top = makePart({ name = "TowerSteam", size = Vector3.new(20, 1, 20), cframe = CFrame.new(pos + Vector3.new(0, 52, 0)), color = Color3.new(1, 1, 1), transparency = 1, canCollide = false, parent = parent })
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(220, 255, 160), Color3.fromRGB(240, 240, 240))
	e.Rate = 12
	e.Lifetime = NumberRange.new(4, 6)
	e.Speed = NumberRange.new(6, 10)
	e.Size = NumberSequence.new(6, 16)
	e.Transparency = NumberSequence.new(0.4, 1)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(15, 15)
	e.Parent = top
end

local function hazardSign(parent: Instance, pos: Vector3, text: string)
	makePart({ name = "HazardPole", size = Vector3.new(1, 10, 1), cframe = CFrame.new(pos + Vector3.new(0, 5, 0)), color = Color3.fromRGB(70, 70, 70), material = Enum.Material.Metal, parent = parent })
	local board = makePart({ name = "HazardSign", size = Vector3.new(10, 6, 0.6), cframe = CFrame.new(pos + Vector3.new(0, 11, 0)) * CFrame.Angles(0, math.pi, 0), color = Color3.fromRGB(240, 210, 30), parent = parent })
	signText(board, text, Color3.fromRGB(30, 30, 30), Enum.NormalId.Back)
end

local function giantMushroomTree(parent: Instance, pos: Vector3)
	makePart({ name = "GiantStalk", shape = Enum.PartType.Cylinder, size = Vector3.new(40, 7, 7), cframe = CFrame.new(pos + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(220, 210, 190), parent = parent })
	local cap = ball(parent, "GiantCap", Vector3.new(44, 16, 44), pos + Vector3.new(0, 42, 0), Color3.fromRGB(180, 70, 220), Enum.Material.Neon, true)
	local light = Instance.new("PointLight")
	light.Color = cap.Color
	light.Range = 50
	light.Brightness = 1.5
	light.Parent = cap
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		ball(parent, "CapSpot", Vector3.new(5, 2, 5), pos + Vector3.new(math.cos(a) * 14, 48, math.sin(a) * 14), Color3.fromRGB(255, 240, 255), Enum.Material.SmoothPlastic)
	end
end

local landmarks: { [string]: (Instance, BiomeConfig.Biome) -> () } = {
	Meadow = function(parent, biome)
		windmill(parent, Vector3.new(-130, 0, 110))
		rainbowArch(parent, WorldBuilder.ThrowLineZ + 150, 150)
		windmill(parent, Vector3.new(135, 0, 60))
	end,
	Dunes = function(parent, biome)
		pyramid(parent, Vector3.new(130, 0, WorldBuilder.ThrowLineZ + 330), 70)
		pool(parent, Vector3.new(-125, 0, WorldBuilder.ThrowLineZ + 300), Color3.fromRGB(60, 200, 255), 30, false)
		for i = 0, 3 do
			palm(parent, Vector3.new(-125 + math.cos(i * 1.6) * 20, 0, WorldBuilder.ThrowLineZ + 300 + math.sin(i * 1.6) * 20), randRange(0.9, 1.3))
		end
	end,
	Tundra = function(parent, biome)
		igloo(parent, Vector3.new(125, 0, WorldBuilder.ThrowLineZ + 560))
		for i = 0, 4 do
			snowman(parent, Vector3.new(-90 + i * 8, 0, WorldBuilder.ThrowLineZ + 520 + i * 40), randRange(0.9, 1.3))
		end
	end,
	Volcano = function(parent, biome)
		bigVolcano(parent, Vector3.new(125, 0, WorldBuilder.ThrowLineZ + 1020))
		makePart({ name = "LavaRiver", size = Vector3.new(BiomeConfig.Width - 8, 0.3, 14), cframe = CFrame.new(0, 0.15, WorldBuilder.ThrowLineZ + 940), color = Color3.fromRGB(255, 110, 20), material = Enum.Material.Neon, canCollide = false, parent = parent })
	end,
	Swamp = function(parent, biome)
		giantMushroomTree(parent, Vector3.new(-120, 0, WorldBuilder.ThrowLineZ + 1500))
		giantMushroomTree(parent, Vector3.new(130, 0, WorldBuilder.ThrowLineZ + 1680))
	end,
	Nuclear = function(parent, biome)
		coolingTower(parent, Vector3.new(130, 0, WorldBuilder.ThrowLineZ + 2050))
		coolingTower(parent, Vector3.new(-130, 0, WorldBuilder.ThrowLineZ + 2250))
		for i = 0, 3 do
			hazardSign(parent, Vector3.new(if i % 2 == 0 then -60 else 60, 0, WorldBuilder.ThrowLineZ + 1850 + i * 150), "DANGER\nRADIATION")
		end
	end,
}

local function buildBiomes(root: Instance)
	local biomesFolder = folder("Biomes", root)
	local width = BiomeConfig.Width
	for _, biome in BiomeConfig.Biomes do
		local bf = folder(biome.id, biomesFolder)
		local length = biome.endDistance - biome.startDistance
		local midZ = WorldBuilder.ThrowLineZ + (biome.startDistance + biome.endDistance) / 2
		local ground = makePart({ name = "Ground", size = Vector3.new(width, 4, length), cframe = CFrame.new(0, -2, midZ), color = biome.groundColor, material = biome.material, parent = bf })
		ground:SetAttribute("BiomeId", biome.id)
		-- Side rails so the zone reads as a lane from above.
		for _, x in { -width / 2, width / 2 } do
			makePart({ name = "Rail", size = Vector3.new(4, 3, length), cframe = CFrame.new(x, 1.5, midZ), color = biome.accentColor, material = Enum.Material.SmoothPlastic, parent = bf })
		end

		-- Entry gate with biome info.
		local gateZ = WorldBuilder.ThrowLineZ + biome.startDistance + (if biome.order == 1 then 30 else 4)
		for _, x in { -width / 2 + 8, width / 2 - 8 } do
			makePart({ name = "GatePillar", size = Vector3.new(6, 40, 6), cframe = CFrame.new(x, 20, gateZ), color = biome.accentColor, material = Enum.Material.SmoothPlastic, parent = bf })
		end
		local gate = makePart({ name = "GateSign", size = Vector3.new(120, 18, 2), cframe = CFrame.new(0, 46, gateZ), color = biome.accentColor:Lerp(Color3.new(0, 0, 0), 0.35), material = Enum.Material.SmoothPlastic, parent = bf })
		local windTxt = string.format("%s  |  Wind %+d%%  Gravity %.2fx", biome.description, math.floor(biome.wind * 100), biome.gravity)
		signText(gate, string.format("%d. %s\n%s", biome.order, biome.name, windTxt), Color3.new(1, 1, 1))
		makePart({ name = "GateBeam", size = Vector3.new(width - 16, 3, 3), cframe = CFrame.new(0, 38, gateZ), color = biome.accentColor, material = Enum.Material.Neon, canCollide = false, parent = bf })

		-- Wind particles show tailwind (+Z) or headwind (-Z).
		local windDir = if biome.wind >= 0 then 1 else -1
		for i = 1, 3 do
			local wp = makePart({ name = "WindEmitter", size = Vector3.new(width - 40, 1, 1), cframe = CFrame.new(0, 6 + i * 6, midZ + (i - 2) * length / 3), color = Color3.new(1, 1, 1), transparency = 1, canCollide = false, parent = bf })
			emitter(wp, biome.accentColor:Lerp(Color3.new(1, 1, 1), 0.5), 4 + math.abs(biome.wind) * 40, Vector3.new(0, 1, windDir * (10 + math.abs(biome.wind) * 120)), 3, 0.9)
		end

		-- Decorations (keep the centre lane clear for landing markers).
		local deco = folder("Decor", bf)
		local count = math.floor(length / 7)
		local decorate = decorators[biome.id]
		for _ = 1, count do
			local x = randRange(-width / 2 + 12, width / 2 - 12)
			if math.abs(x) < 26 then
				x += if x < 0 then -26 else 26
			end
			local z = WorldBuilder.ThrowLineZ + randRange(biome.startDistance + 12, biome.endDistance - 8)
			if decorate then
				decorate(deco, Vector3.new(x, 0, z), biome)
			end
		end
	end

	-- Landmarks, mountain backdrops beyond the side walls and clouds overhead.
	local scenery = folder("Scenery", biomesFolder)
	for _, biome in BiomeConfig.Biomes do
		local bf = biomesFolder:FindFirstChild(biome.id) or biomesFolder
		local landmark = landmarks[biome.id]
		if landmark then
			landmark(bf, biome)
		end
		local rockColor = biome.groundColor:Lerp(Color3.new(0, 0, 0), 0.3)
		local cap = if biome.id == "Meadow" or biome.id == "Tundra" or biome.id == "Dunes" then Color3.fromRGB(250, 252, 255) else nil
		local mat = if biome.id == "Tundra" then Enum.Material.Glacier elseif biome.id == "Volcano" then Enum.Material.Basalt else Enum.Material.Rock
		local z = WorldBuilder.ThrowLineZ + biome.startDistance + 30
		while z < WorldBuilder.ThrowLineZ + biome.endDistance do
			for _, side in { -1, 1 } do
				local size = randRange(70, 130)
				mountain(scenery, Vector3.new(side * (BiomeConfig.Width / 2 + size * 0.6 + rand() * 30), -size * 0.12, z + randRange(-15, 15)), size, randRange(70, 110), rockColor:Lerp(biome.accentColor, rand() * 0.15), mat, if cap and size > 95 then cap else nil)
			end
			z += 75
		end
		for _ = 1, 5 do
			cloud(scenery, Vector3.new(randRange(-170, 170), randRange(130, 190), WorldBuilder.ThrowLineZ + randRange(biome.startDistance, biome.endDistance)), randRange(0.9, 1.6))
		end
	end
	-- Hub backdrop: hills behind the plots and clouds over the plaza.
	for z = -280, -20, 65 do
		for _, side in { -1, 1 } do
			local size = randRange(60, 100)
			mountain(scenery, Vector3.new(side * (222 + size * 0.6 + rand() * 20), -size * 0.12, z), size, randRange(60, 90), Color3.fromRGB(90, 160, 80), Enum.Material.Grass, nil)
		end
	end
	for _ = 1, 6 do
		cloud(scenery, Vector3.new(randRange(-200, 200), randRange(110, 160), randRange(-300, -40)), randRange(1, 1.6))
	end

	-- Distance markers every 100 studs.
	local markers = folder("DistanceMarkers", biomesFolder)
	local last = BiomeConfig.Biomes[#BiomeConfig.Biomes].endDistance
	for d = 100, last, 100 do
		local z = WorldBuilder.ThrowLineZ + d
		local biome = BiomeConfig.biomeAtDistance(d - 0.5)
		makePart({ name = "MarkerLine", size = Vector3.new(BiomeConfig.Width - 8, 0.2, 1.5), cframe = CFrame.new(0, 0.1, z), color = Color3.new(1, 1, 1), material = Enum.Material.Neon, transparency = 0.45, canCollide = false, parent = markers })
		local post = makePart({ name = "Marker" .. d, size = Vector3.new(14, 7, 1), cframe = CFrame.new(-BiomeConfig.Width / 2 + 16, 9, z) * CFrame.Angles(0, math.pi, 0), color = biome.accentColor:Lerp(Color3.new(0, 0, 0), 0.5), parent = markers })
		signText(post, d .. "m", Color3.new(1, 1, 1), Enum.NormalId.Back)
		makePart({ name = "MarkerPole", size = Vector3.new(1, 6, 1), cframe = CFrame.new(-BiomeConfig.Width / 2 + 16, 3, z), color = Color3.fromRGB(60, 60, 70), parent = markers })
	end

	-- The end of the world: a launch ramp to space.
	local endZ = WorldBuilder.ThrowLineZ + last
	makeWedge("SpaceRamp", Vector3.new(BiomeConfig.Width, 30, 60), CFrame.new(0, 15, endZ - 30), Color3.fromRGB(80, 60, 160), Enum.Material.Neon, biomesFolder)
	local edge = makePart({ name = "EdgeOfTheWorld", size = Vector3.new(160, 22, 2), cframe = CFrame.new(0, 48, endZ - 4) * CFrame.Angles(0, math.pi, 0), color = Color3.fromRGB(40, 20, 80), parent = biomesFolder })
	signText(edge, "EDGE OF THE WORLD\nBeyond: SPACE (2500m)  •  THE MOON (3600m)", Color3.fromRGB(200, 220, 255), Enum.NormalId.Back)

	-- Invisible walls along the long sides (one segment per biome: parts max out at 2048 studs).
	for _, b in BiomeConfig.Biomes do
		local len = b.endDistance - b.startDistance
		for _, x in { -BiomeConfig.Width / 2 - 2, BiomeConfig.Width / 2 + 2 } do
			makePart({ name = "SideWall", size = Vector3.new(2, 80, len), cframe = CFrame.new(x, 40, WorldBuilder.ThrowLineZ + (b.startDistance + b.endDistance) / 2), color = Color3.new(1, 1, 1), transparency = 1, parent = biomesFolder })
		end
	end
end

local function buildPlots(root: Instance): { PlotInfo }
	local plotsFolder = folder("Plots", root)
	local plots: { PlotInfo } = {}
	local positions = {
		Vector3.new(-160, 0, -80),
		Vector3.new(-160, 0, -150),
		Vector3.new(-160, 0, -220),
		Vector3.new(160, 0, -80),
		Vector3.new(160, 0, -150),
		Vector3.new(160, 0, -220),
	}
	local palette = {
		Color3.fromRGB(255, 120, 120),
		Color3.fromRGB(255, 190, 90),
		Color3.fromRGB(120, 220, 120),
		Color3.fromRGB(110, 170, 255),
		Color3.fromRGB(190, 120, 255),
		Color3.fromRGB(255, 130, 210),
	}
	for i, pos in positions do
		local model = Instance.new("Model")
		model.Name = "Plot" .. i
		model:SetAttribute("PlotIndex", i)
		model.Parent = plotsFolder
		-- Local -Z faces the hub path.
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0, pos.Z))
		local color = palette[i]
		local pad = makePart({ name = "Pad", size = Vector3.new(66, 1.2, 62), cframe = cf * CFrame.new(0, 0.6, 0), color = color:Lerp(Color3.new(1, 1, 1), 0.55), material = Enum.Material.SmoothPlastic, parent = model })
		for _, edge in { { 0, -31, 66, 2 }, { 0, 31, 66, 2 }, { -33, 0, 2, 62 }, { 33, 0, 2, 62 } } do
			makePart({ name = "Border", size = Vector3.new(edge[3], 1.8, edge[4]), cframe = cf * CFrame.new(edge[1], 0.9, edge[2]), color = color, material = Enum.Material.SmoothPlastic, parent = model })
		end
		model.PrimaryPart = pad

		-- Owner sign at the back of the plot.
		local sign = makePart({ name = "OwnerSign", size = Vector3.new(36, 10, 1.5), cframe = cf * CFrame.new(0, 13, 26), color = color:Lerp(Color3.new(0, 0, 0), 0.3), parent = model })
		local ownerLabel = signText(sign, "Free Plot", Color3.new(1, 1, 1))
		for _, x in { -16, 16 } do
			makePart({ name = "SignPole", size = Vector3.new(1.5, 13, 1.5), cframe = cf * CFrame.new(x, 6.5, 26), color = Color3.fromRGB(90, 60, 45), material = Enum.Material.Wood, parent = model })
		end
		local incomeBoard = makePart({ name = "IncomeBoard", size = Vector3.new(24, 4, 1), cframe = cf * CFrame.new(0, 5, 26), color = Color3.fromRGB(30, 30, 50), parent = model })
		local incomeLabel = signText(incomeBoard, "+0 / sec", Color3.fromRGB(255, 230, 90))

		-- Pedestals in two rows of four.
		local pedestals: { Part } = {}
		local pedFolder = folder("Pedestals", model)
		local n = 0
		for row = 0, 1 do
			for col = 0, 3 do
				n += 1
				local local_ = CFrame.new(-21 + col * 14, 0, -10 + row * 18)
				makePart({ name = "PedestalBase", shape = Enum.PartType.Cylinder, size = Vector3.new(1, 9, 9), cframe = cf * local_ * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.pi / 2), color = color, material = Enum.Material.SmoothPlastic, parent = pedFolder })
				local ped = makePart({ name = "Pedestal" .. n, shape = Enum.PartType.Cylinder, size = Vector3.new(2.4, 7, 7), cframe = cf * local_ * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0, math.pi / 2), color = Color3.fromRGB(250, 250, 255), material = Enum.Material.Marble, parent = pedFolder })
				table.insert(pedestals, ped)
			end
		end
		-- Entrance arch with the plot number, lamps and trees at the back corners.
		for _, x in { -30, 30 } do
			makePart({ name = "ArchPost", size = Vector3.new(2, 14, 2), cframe = cf * CFrame.new(x, 7, -31), color = color, parent = model })
			local lamp = makePart({ name = "PlotLamp", shape = Enum.PartType.Ball, size = Vector3.one * 2.4, cframe = cf * CFrame.new(x, 15, -31), color = color:Lerp(Color3.new(1, 1, 1), 0.5), material = Enum.Material.Neon, canCollide = false, parent = model })
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 22
			light.Brightness = 1.2
			light.Parent = lamp
			tree(model, (cf * CFrame.new(x * 1.1, 0, 36)).Position, Color3.fromRGB(120, 80, 50), Color3.fromHSV(0.27 + rand() * 0.08, 0.6, 0.75), randRange(0.9, 1.2))
		end
		local archSign = makePart({ name = "PlotArch", size = Vector3.new(62, 3.4, 1.2), cframe = cf * CFrame.new(0, 13, -31), color = color:Lerp(Color3.new(0, 0, 0), 0.2), canCollide = false, parent = model })
		signText(archSign, "PLOT " .. i, Color3.new(1, 1, 1))
		makePart({ name = "PlotGlow", size = Vector3.new(60, 0.2, 1), cframe = cf * CFrame.new(0, 1.3, -29.5), color = color, material = Enum.Material.Neon, canCollide = false, parent = model })

		local petsFolder = folder("Pets", model)
		table.insert(plots, {
			index = i,
			model = model,
			pad = pad,
			ownerLabel = ownerLabel,
			incomeLabel = incomeLabel,
			pedestals = pedestals,
			petsFolder = petsFolder,
			spawnCFrame = cf * CFrame.new(0, 4, -24) * CFrame.Angles(0, math.pi, 0),
		})
	end
	return plots
end

-- Builds the world under `parent` (normally Workspace). Safe to call once per server.
function WorldBuilder.build(parent: Instance): WorldInfo
	seed = 424242
	partCount = 0
	local root = Instance.new("Model")
	root.Name = "SnackWorld"
	local hubSpawn = buildHub(root)
	local leaderboardLines = buildHubAttractions(root)
	local throwCF = buildThrowLine(root)
	buildBiomes(root)
	local plots = buildPlots(root)
	root.Parent = parent
	return {
		root = root,
		throwLineCenter = GameConfig.ThrowLineCenter,
		throwLineCFrame = throwCF,
		hubSpawnCFrame = hubSpawn,
		plots = plots,
		leaderboardLines = leaderboardLines,
		partCount = partCount,
	}
end

-- Convenience for other modules: world position for a landing distance.
function WorldBuilder.landingPosition(distance: number, lateral: number): Vector3
	return Vector3.new(lateral, 0, WorldBuilder.ThrowLineZ + distance)
end

return WorldBuilder
