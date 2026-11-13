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
		if math.abs(pos.X) < 110 and pos.Z < -40 and pos.Z > -260 and math.abs(pos.X) > 20 then
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
	local throwCF = buildThrowLine(root)
	buildBiomes(root)
	local plots = buildPlots(root)
	root.Parent = parent
	return {
		root = root,
		throwLineCenter = Vector3.new(0, 0, WorldBuilder.ThrowLineZ - 12),
		throwLineCFrame = throwCF,
		hubSpawnCFrame = hubSpawn,
		plots = plots,
		partCount = partCount,
	}
end

-- Convenience for other modules: world position for a landing distance.
function WorldBuilder.landingPosition(distance: number, lateral: number): Vector3
	return Vector3.new(lateral, 0, WorldBuilder.ThrowLineZ + distance)
end

local _ = GameConfig
return WorldBuilder
