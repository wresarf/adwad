--!strict
-- Procedurally builds the whole map from primitive parts: Spawn Hub, Throw Line, six
-- biome zones and six player plots. Deterministic (seeded) so every server looks the same.
-- Uses only Instance/datatype APIs so it can also run headless in the Lune test-suite.
--
-- Art direction: a "toy safari park". Chunky rounded toy shapes, a warm natural palette
-- (cream, warm wood, sand, leaf green, terracotta, muted teal, amber), small upright
-- cream signs with charcoal text, and Neon only where something really glows (lava, a
-- reactor core). The throw lane (|x| <= LaneHalf, +Z from the Throw Line) stays clear:
-- only flat lane markings and short distance posts live inside it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local PetModelBuilder = require(Shared:WaitForChild("PetModelBuilder"))

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
-- Landings happen within +-60 studs of the lane centre; keep this strip free of props.
WorldBuilder.LaneHalf = 72

local seed = 1
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function randRange(a: number, b: number): number
	return a + (b - a) * rand()
end

local partCount = 0

------------------------------------------------------------------ palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local C = {
	cream = rgb(246, 238, 220),
	ivory = rgb(252, 249, 240),
	sand = rgb(226, 206, 162),
	sandDark = rgb(206, 180, 134),
	straw = rgb(222, 186, 108),
	wood = rgb(176, 122, 78),
	woodLight = rgb(206, 162, 114),
	woodDark = rgb(122, 84, 58),
	leaf = rgb(118, 168, 88),
	leafDark = rgb(88, 138, 72),
	leafLight = rgb(152, 192, 106),
	grass = rgb(132, 180, 98),
	terracotta = rgb(204, 112, 80),
	terracottaDark = rgb(168, 88, 64),
	teal = rgb(86, 158, 150),
	tealDark = rgb(64, 124, 120),
	amber = rgb(234, 172, 66),
	charcoal = rgb(54, 48, 46),
	stone = rgb(178, 170, 156),
	stoneDark = rgb(132, 124, 114),
	steel = rgb(158, 158, 160),
	rubber = rgb(66, 62, 60),
	water = rgb(104, 168, 168),
	rose = rgb(214, 136, 128),
	snow = rgb(242, 244, 240),
	lava = rgb(236, 112, 46),
}

local SM = Enum.Material

------------------------------------------------------------------ primitives

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
	part.Material = p.material or SM.SmoothPlastic
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

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return makePart({ name = name, size = size, cframe = cf, color = color, material = material, canCollide = collide, parent = parent })
end

-- Ellipsoid: a Block with a Sphere SpecialMesh (Ball parts are forced to be uniform).
local function blob(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local p = makePart({ name = name, size = size, cframe = cf, color = color, material = material, canCollide = collide == true, parent = parent })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Vertical cylinder standing on `base` (the centre of its bottom face).
local function column(parent: Instance, name: string, base: Vector3, height: number, d: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return makePart({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, d, d),
		cframe = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		material = material,
		canCollide = collide,
		parent = parent,
	})
end

-- Horizontal cylinder through `center`, axis along `axis` ("X" or "Z").
local function rod(parent: Instance, name: string, center: Vector3, length: number, d: number, axis: "X" | "Z", color: Color3, material: Enum.Material?): Part
	local cf = if axis == "X" then CFrame.new(center) else CFrame.new(center) * CFrame.Angles(0, math.pi / 2, 0)
	return makePart({ name = name, shape = Enum.PartType.Cylinder, size = Vector3.new(length, d, d), cframe = cf, color = color, material = material, parent = parent })
end

-- Block spanning from `a` to `b` (rails, beams, paths).
local function span(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local len = (b - a).Magnitude
	return block(parent, name, Vector3.new(w, h, len), CFrame.lookAt((a + b) / 2, b), color, material, collide)
end

local function makeWedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = material or SM.SmoothPlastic
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

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
end

local function emitter(parent: Instance, color: Color3, rate: number, velocity: Vector3, lifetime: number, size: number, lightEmission: number?)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	e.Speed = NumberRange.new(velocity.Magnitude * 0.8, velocity.Magnitude * 1.2)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(velocity.X, 0, velocity.Z)
	e.SpreadAngle = Vector2.new(20, 20)
	e.Size = NumberSequence.new(size, 0)
	e.LightEmission = lightEmission or 0
	e.Transparency = NumberSequence.new(0.4, 1)
	e.Parent = parent
end

------------------------------------------------------------------ signs

type TextLine = { text: string, size: number, title: boolean? }

-- Charcoal-on-cream text on one face of `part`. `size` is each line's share of the height.
local function boardText(part: BasePart, face: Enum.NormalId, lines: { TextLine }, color: Color3?, maxDistance: number?): { TextLabel }
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 120
	gui.Parent = part
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = gui
	local labels = {}
	for i, l in lines do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, l.size)
		label.BackgroundTransparency = 1
		label.Text = l.text
		label.TextScaled = true
		label.Font = if l.title == false then Enum.Font.GothamMedium else Enum.Font.FredokaOne
		label.TextColor3 = color or C.charcoal
		label.TextStrokeTransparency = 1
		label.LayoutOrder = i
		label.Parent = gui
		table.insert(labels, label)
	end
	return labels
end

local function title(text: string): { TextLine }
	return { { text = text, size = 1 } }
end
local function titleSub(t: string, sub: string): { TextLine }
	return { { text = t, size = 0.58 }, { text = sub, size = 0.42, title = false } }
end

-- A small upright cream sign on two wooden posts. `base` is the ground point under it;
-- the text faces `facing`. Returns the board and its labels.
local function signBoard(parent: Instance, name: string, base: Vector3, facing: Vector3, w: number, h: number, lines: { TextLine }, bottom: number?, maxDistance: number?, tag: Color3?): (Part, { TextLabel })
	local b = bottom or 2.2
	local center = base + Vector3.new(0, b + h / 2, 0)
	local f = Vector3.new(facing.X, 0, facing.Z).Unit
	local cf = CFrame.lookAt(center, center + f)
	local board = block(parent, name, Vector3.new(w, h, 0.3), cf, C.cream)
	block(parent, name .. "Frame", Vector3.new(w + 0.5, h + 0.5, 0.3), cf * CFrame.new(0, 0, 0.25), C.woodDark, SM.Wood)
	for _, sx in { -1, 1 } do
		local postH = b + h + 0.4
		block(parent, "SignPost", Vector3.new(0.5, postH, 0.5), cf * CFrame.new(sx * (w / 2 - 0.5), (0.4 - b) / 2, 0.55), C.wood, SM.Wood)
	end
	if tag then
		block(parent, name .. "Tag", Vector3.new(w + 0.5, 0.45, 0.36), cf * CFrame.new(0, h / 2 + 0.2, 0.2), tag)
	end
	return board, boardText(board, Enum.NormalId.Front, lines, nil, maxDistance)
end

------------------------------------------------------------------ props

local function tree(parent: Instance, pos: Vector3, scale: number, leaves: Color3?)
	local leaf = leaves or C.leaf:Lerp(C.leafLight, rand() * 0.6)
	column(parent, "Trunk", pos, 6 * scale, 1.4 * scale, C.wood, SM.Wood)
	blob(parent, "Leaves", Vector3.new(7, 6, 7) * scale, CFrame.new(pos + Vector3.new(0, 7.8 * scale, 0)), leaf, SM.Grass)
	blob(parent, "Leaves", Vector3.new(4.6, 4, 4.6) * scale, CFrame.new(pos + Vector3.new(1.6 * scale, 10.2 * scale, 0.8 * scale)), leaf:Lerp(C.leafLight, 0.35), SM.Grass)
end

local function pine(parent: Instance, pos: Vector3, scale: number, snowy: boolean)
	column(parent, "Trunk", pos, 3 * scale, 1.1 * scale, C.woodDark, SM.Wood)
	local green = rgb(76, 122, 84)
	for i = 0, 2 do
		local d = (7 - i * 2) * scale
		column(parent, "PineTier", pos + Vector3.new(0, (2.6 + i * 2.6) * scale, 0), 2.4 * scale, d, if snowy and i == 2 then C.snow else green:Lerp(C.leaf, i * 0.15), SM.Grass)
	end
end

local function bush(parent: Instance, pos: Vector3, scale: number, color: Color3?)
	local c = color or C.leafDark:Lerp(C.leaf, rand())
	blob(parent, "Bush", Vector3.new(5, 3.6, 5) * scale, CFrame.new(pos + Vector3.new(0, 1.2 * scale, 0)), c, SM.Grass)
	blob(parent, "Bush", Vector3.new(3.4, 2.8, 3.4) * scale, CFrame.new(pos + Vector3.new(2 * scale, 1 * scale, 0.8 * scale)), c:Lerp(C.leafLight, 0.3), SM.Grass)
end

local BLOOMS = { C.cream, C.amber, C.terracotta, C.rose }
local function flowers(parent: Instance, pos: Vector3, scale: number)
	blob(parent, "FlowerLeaves", Vector3.new(3, 1.2, 3) * scale, CFrame.new(pos + Vector3.new(0, 0.3 * scale, 0)), C.leaf, SM.Grass)
	for i = 1, 2 do
		local a = rand() * math.pi * 2
		blob(parent, "Bloom", Vector3.new(0.9, 0.6, 0.9) * scale, CFrame.new(pos + Vector3.new(math.cos(a), 0.95, math.sin(a)) * scale), BLOOMS[1 + (i + math.floor(rand() * 4)) % #BLOOMS])
	end
end

local function rock(parent: Instance, pos: Vector3, color: Color3, scale: number, material: Enum.Material?)
	blob(parent, "Rock", Vector3.new(randRange(5, 8), randRange(3, 4.5), randRange(4, 7)) * scale, CFrame.new(pos + Vector3.new(0, 0.9 * scale, 0)) * CFrame.Angles(0, rand() * 6, 0), color, material or SM.Slate, true)
end

local function cloud(parent: Instance, pos: Vector3, scale: number)
	for i, o in { Vector3.new(0, 0, 0), Vector3.new(10, -2, 2), Vector3.new(-9, -2.5, -1) } do
		local d = (if i == 1 then 18 else 12) * scale
		local p = blob(parent, "Cloud", Vector3.new(d * 1.5, d * 0.7, d), CFrame.new(pos + o * scale), C.ivory)
		p.CastShadow = false
	end
end

-- Ridge of "mountains" (blocks rotated 45 degrees, half buried) as a backdrop.
local function mountain(parent: Instance, pos: Vector3, size: number, length: number, color: Color3, material: Enum.Material, cap: Color3?)
	makePart({ name = "Mountain", size = Vector3.new(size, size, length), cframe = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(45)), color = color, material = material, castShadow = false, parent = parent })
	if cap then
		local capSize = size * 0.32
		makePart({ name = "MountainCap", size = Vector3.new(capSize, capSize, length * 0.7), cframe = CFrame.new(pos + Vector3.new(0, size * 0.707 - capSize * 0.68, 0)) * CFrame.Angles(0, 0, math.rad(45)), color = cap, material = SM.Sand, castShadow = false, parent = parent })
	end
end

local function crate(parent: Instance, cf: CFrame, s: number): Part
	local c = block(parent, "Crate", Vector3.new(s, s, s), cf, C.woodLight, SM.WoodPlanks)
	block(parent, "CrateBand", Vector3.new(s + 0.1, 0.4, s + 0.1), cf * CFrame.new(0, s / 2 - 0.5, 0), C.woodDark, SM.Wood)
	return c
end

local function lampPost(parent: Instance, pos: Vector3, height: number)
	column(parent, "LampPost", pos, height, 0.6, C.woodDark, SM.Wood)
	local lantern = block(parent, "Lantern", Vector3.new(1.3, 1.6, 1.3), CFrame.new(pos + Vector3.new(0, height + 0.8, 0)), C.amber)
	block(parent, "LanternCap", Vector3.new(1.8, 0.35, 1.8), CFrame.new(pos + Vector3.new(0, height + 1.75, 0)), C.woodDark, SM.Wood)
	light(lantern, rgb(255, 214, 150), 20, 0.9)
end

local function bench(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	block(parent, "BenchSeat", Vector3.new(6, 0.4, 1.8), cf * CFrame.new(0, 1.8, 0), C.woodLight, SM.WoodPlanks)
	for _, x in { -2.3, 2.3 } do
		block(parent, "BenchLeg", Vector3.new(0.5, 1.6, 1.6), cf * CFrame.new(x, 0.8, 0), C.woodDark, SM.Wood)
	end
end

-- Egg on its straw nest; speckles sit on the ellipsoid surface.
local function nestEgg(parent: Instance, pos: Vector3, eggColor: Color3, speckColor: Color3, scale: number)
	column(parent, "Nest", pos, 0.8 * scale, 5.4 * scale, C.straw:Lerp(C.woodLight, 0.4), SM.Grass)
	column(parent, "NestStraw", pos + Vector3.new(0, 0.8 * scale, 0), 0.4 * scale, 4.4 * scale, C.straw, SM.Grass)
	local a, b = 1.5 * scale, 2.0 * scale
	local center = pos + Vector3.new(0, 0.9 * scale + b - 0.3 * scale, 0)
	blob(parent, "DecorEgg", Vector3.new(a * 2, b * 2, a * 2), CFrame.new(center), eggColor, SM.SmoothPlastic, true)
	for i = 1, 5 do
		local th = 0.5 + rand() * 1.3 -- polar angle from the top
		local ph = i / 5 * math.pi * 2 + rand() * 0.6
		local local_ = Vector3.new(math.sin(th) * math.cos(ph) * a, math.cos(th) * b, math.sin(th) * math.sin(ph) * a)
		local normal = Vector3.new(local_.X / (a * a), local_.Y / (b * b), local_.Z / (a * a)).Unit
		local p = center + local_
		local up = if math.abs(normal.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
		blob(parent, "Speckle", Vector3.new(0.7, 0.55, 0.16) * scale, CFrame.lookAt(p, p + normal, up), speckColor)
	end
end

------------------------------------------------------------------ hub layout

-- Areas where scattered trees must not grow (xMin, zMin, xMax, zMax) and circles (x, z, r).
local hubRects = {
	{ -72, -56, 132, 2 }, -- throw pad, gym spur and east connector
	{ -14, -114, 14, -30 }, -- avenue
	{ 22, -112, 66, -78 }, -- food shop
	{ -66, -112, -22, -78 }, -- egg hatchery
	{ -132, -160, 132, -140 }, -- cross path
	{ 104, -236, 200, -36 }, -- east promenade + plots
	{ -200, -236, -104, -70 }, -- west promenade + plots
	{ -18, -250, 18, -188 }, -- leaderboard
}
local hubCircles = {
	{ -92, -46, 32 }, -- gym
	{ 0, -150, 52 }, -- plaza
	{ -41, -191, 16 }, -- fuse altar
	{ 41, -191, 16 }, -- pet index
}
local function hubBlocked(pos: Vector3, margin: number): boolean
	for _, r in hubRects do
		if pos.X > r[1] - margin and pos.X < r[3] + margin and pos.Z > r[2] - margin and pos.Z < r[4] + margin then
			return true
		end
	end
	for _, c in hubCircles do
		if (Vector3.new(pos.X - c[1], 0, pos.Z - c[2])).Magnitude < c[3] + margin then
			return true
		end
	end
	return false
end

local function path(parent: Instance, name: string, a: Vector3, b: Vector3, w: number)
	span(parent, name, a + Vector3.new(0, 0.15, 0), b + Vector3.new(0, 0.15, 0), w, 0.3, C.sand, SM.Sand)
end

------------------------------------------------------------------ sections

local function buildHub(root: Instance): CFrame
	local hub = folder("SpawnHub", root)
	local c = WorldBuilder.HubCenter
	block(hub, "HubGround", Vector3.new(440, 4, 300), CFrame.new(c.X, -2, c.Z), C.grass, SM.Grass)

	-- Plaza with a terracotta ring around the fountain.
	column(hub, "Plaza", Vector3.new(c.X, 0, c.Z), 0.4, 80, C.cream:Lerp(C.sand, 0.35), SM.Slate)
	column(hub, "PlazaRing", Vector3.new(c.X, 0, c.Z), 0.45, 32, C.terracotta, SM.Brick)
	column(hub, "PlazaInner", Vector3.new(c.X, 0, c.Z), 0.5, 28, C.cream, SM.Slate)

	-- Paths: hub -> throw line, stalls, gym, plots, altar, index, leaderboard.
	local paths = folder("Paths", hub)
	path(paths, "PathToThrowLine", Vector3.new(0, 0, -112), Vector3.new(0, 0, -33), 16)
	path(paths, "PathToShop", Vector3.new(6, 0, -95), Vector3.new(36, 0, -95), 8)
	path(paths, "PathToHatchery", Vector3.new(-6, 0, -95), Vector3.new(-36, 0, -95), 8)
	path(paths, "PathToGym", Vector3.new(-6, 0, -46), Vector3.new(-68, 0, -46), 10)
	path(paths, "PathEastConnector", Vector3.new(6, 0, -46), Vector3.new(124, 0, -46), 10)
	path(paths, "PathWest", Vector3.new(-38, 0, c.Z), Vector3.new(-115, 0, c.Z), 12)
	path(paths, "PathEast", Vector3.new(38, 0, c.Z), Vector3.new(115, 0, c.Z), 12)
	path(paths, "PromenadeWest", Vector3.new(-120.5, 0, -232), Vector3.new(-120.5, 0, -74), 17)
	path(paths, "PromenadeEast", Vector3.new(120.5, 0, -232), Vector3.new(120.5, 0, -41), 17)
	for _, sx in { -1, 1 } do
		local dir = Vector3.new(sx * math.cos(math.rad(45)), 0, -math.sin(math.rad(45)))
		path(paths, if sx < 0 then "PathToAltar" else "PathToIndex", c + dir * 38, c + dir * 52, 8)
	end
	path(paths, "PathToLeaderboard", Vector3.new(0, 0, -188), Vector3.new(0, 0, -230), 8)

	-- Fountain: terracotta basin, teal water, a golden lion cub statue on top.
	local fountain = folder("Fountain", hub)
	column(fountain, "FountainBase", Vector3.new(c.X, 0.4, c.Z), 2.2, 20, C.terracotta, SM.Brick)
	column(fountain, "FountainRim", Vector3.new(c.X, 2.6, c.Z), 0.4, 20.6, C.cream, SM.Slate)
	local water = column(fountain, "FountainWater", Vector3.new(c.X, 2.3, c.Z), 0.5, 18.4, C.water, SM.Glass, false)
	water.Transparency = 0.25
	column(fountain, "FountainPillar", Vector3.new(c.X, 2.6, c.Z), 3.2, 3, C.cream, SM.Slate)
	local bowl = column(fountain, "FountainBowl", Vector3.new(c.X, 5.8, c.Z), 0.8, 7, C.terracotta, SM.Brick)
	emitter(bowl, rgb(210, 236, 236), 6, Vector3.new(0, 5, 0), 1.2, 0.6)
	local statue = PetModelBuilder.build("LionCub", "Gold", "Colossal", CFrame.new(c.X, 6.6, c.Z) * CFrame.Angles(0, math.pi, 0))
	statue.Name = "FountainStatue"
	statue.Parent = fountain
	for _, d in statue:GetDescendants() do
		if d:IsA("BasePart") then
			partCount += 1
			d.CanQuery = true
			local glints = d:FindFirstChildOfClass("ParticleEmitter")
			if glints then
				glints:Destroy()
			end
			local glow = d:FindFirstChildOfClass("PointLight")
			if glow then
				glow:Destroy()
			end
		end
	end

	-- Lamps and benches between the paths around the plaza.
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		lampPost(hub, c + dir * 43, 8)
		if i % 2 == 0 then
			bench(hub, c + dir * 36, math.atan2(dir.X, dir.Z))
		end
	end

	-- Planters along the avenue.
	for _, z in { -60, -80 } do
		for _, sx in { -1, 1 } do
			local p = Vector3.new(sx * 12, 0, z)
			block(hub, "Planter", Vector3.new(3.2, 1.4, 8), CFrame.new(p + Vector3.new(0, 0.7, 0)), C.woodLight, SM.WoodPlanks)
			blob(hub, "PlanterBush", Vector3.new(2.8, 1.8, 7.4), CFrame.new(p + Vector3.new(0, 1.5, 0)), C.leaf, SM.Grass)
			blob(hub, "Bloom", Vector3.new(0.9, 0.6, 0.9), CFrame.new(p + Vector3.new(0.3, 2.35, -2)), C.amber)
			blob(hub, "Bloom", Vector3.new(0.9, 0.6, 0.9), CFrame.new(p + Vector3.new(-0.3, 2.35, 1.6)), C.cream)
		end
	end

	-- Scattered toy trees, kept off paths, stalls, the gym and the plots.
	local placed = 0
	for _ = 1, 260 do
		if placed >= 26 then
			break
		end
		local pos = Vector3.new(randRange(-205, 205), 0, randRange(-288, -10))
		if not hubBlocked(pos, 6) then
			tree(hub, pos, randRange(0.9, 1.3))
			placed += 1
		end
	end
	for _ = 1, 10 do
		local pos = Vector3.new(randRange(-200, 200), 0, randRange(-285, -12))
		if not hubBlocked(pos, 4) then
			rock(hub, pos, C.stone, randRange(0.5, 0.9))
		end
	end

	-- Welcome sign facing the spawn.
	signBoard(hub, "WelcomeSign", Vector3.new(-15, 0, -110), Vector3.new(0.4, 0, -1), 10, 3.6, titleSub("SNACK FORCE", "Pet Toss Safari Park"), 2.4, 150)

	-- Direction signpost at the north edge of the plaza.
	local postBase = Vector3.new(13, 0, -111)
	column(hub, "Signpost", postBase, 9.2, 0.7, C.wood, SM.Wood)
	blob(hub, "SignpostCap", Vector3.new(1, 0.7, 1), CFrame.new(postBase + Vector3.new(0, 9.3, 0)), C.terracotta)
	local arrows = {
		{ text = "THROW LINE", to = Vector3.new(0, 0, -20), y = 8.2 },
		{ text = "GYM", to = GameConfig.GymCenter, y = 7.0 },
		{ text = "FOOD SHOP", to = Vector3.new(42, 0, -95), y = 5.8 },
		{ text = "HATCHERY", to = Vector3.new(-42, 0, -95), y = 4.6 },
		{ text = "PLOTS", to = Vector3.new(120, 0, -150), y = 3.4 },
	}
	for _, a in arrows do
		local d = Vector3.new(a.to.X - postBase.X, 0, a.to.Z - postBase.Z).Unit
		local center = postBase + Vector3.new(0, a.y, 0) + d * 2.9
		local cf = CFrame.fromMatrix(center, d, Vector3.new(0, 1, 0))
		local plank = block(hub, "SignArrow", Vector3.new(5.2, 1, 0.25), cf, C.cream, nil, false)
		makeWedge(hub, "SignArrowTip", Vector3.new(0.25, 1, 0.7), cf * CFrame.new(2.95, 0, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 0), C.terracotta)
		boardText(plank, Enum.NormalId.Front, title(a.text .. "  >"), nil, 80)
		boardText(plank, Enum.NormalId.Back, title("<  " .. a.text), nil, 80)
	end

	-- Low wooden fence around the hub's outer edge, with hedges along it.
	local runs = {
		{ Vector3.new(-218, 0, -298), Vector3.new(218, 0, -298) },
		{ Vector3.new(-218, 0, -298), Vector3.new(-218, 0, -2) },
		{ Vector3.new(218, 0, -298), Vector3.new(218, 0, -2) },
	}
	local decor = folder("HubDecor", hub)
	for _, run in runs do
		local a, b = run[1], run[2]
		for _, y in { 1.6, 3.2 } do
			span(decor, "FenceRail", a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), 0.5, 0.5, C.wood, SM.WoodPlanks)
		end
		local len = (b - a).Magnitude
		local posts = math.floor(len / 24)
		for k = 0, posts do
			local p = a:Lerp(b, k / posts)
			block(decor, "FencePost", Vector3.new(0.9, 4.2, 0.9), CFrame.new(p + Vector3.new(0, 2.1, 0)), C.woodDark, SM.Wood)
		end
	end
	for _ = 1, 26 do
		local side = rand()
		local pos
		if side < 0.4 then
			pos = Vector3.new(randRange(-205, 205), 0, randRange(-292, -284))
		elseif side < 0.7 then
			pos = Vector3.new(randRange(-212, -204), 0, randRange(-280, -20))
		else
			pos = Vector3.new(randRange(204, 212), 0, randRange(-280, -20))
		end
		if rand() < 0.7 then
			bush(decor, pos, randRange(0.9, 1.4))
		else
			flowers(decor, pos, randRange(0.9, 1.3))
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.6, 12)
	spawn.CFrame = CFrame.new(c.X, 0.55, c.Z + 30) * CFrame.Angles(0, math.pi, 0)
	spawn.Color = C.teal
	spawn.Material = SM.Slate
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = hub
	partCount += 1
	return CFrame.new(c.X, 5, c.Z + 30) * CFrame.Angles(0, math.pi, 0)
end

------------------------------------------------------------------ hub attractions

local function prompt(part: BasePart, action: string, object: string, panel: string)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	pp.KeyboardKeyCode = Enum.KeyCode.R -- E is reserved for throwing
	pp.GamepadKeyCode = Enum.KeyCode.ButtonY
	pp:SetAttribute("OpenPanel", panel)
	pp.Parent = part
end

-- A plate threaded on a bar: cylinder with its axis along `axis`.
local function plate(parent: Instance, center: Vector3, d: number, t: number, axis: "X" | "Z", color: Color3)
	rod(parent, "Plate", center, t, d, axis, color, SM.SmoothPlastic)
end

-- Dumbbell lying on a surface at height `surfaceY`, handle along `axis`.
local function dumbbell(parent: Instance, x: number, surfaceY: number, z: number, plateD: number, axis: "X" | "Z", color: Color3)
	local center = Vector3.new(x, surfaceY + plateD / 2, z)
	local handle = 1.8
	rod(parent, "DumbbellHandle", center, handle, 0.3, axis, C.steel, SM.Metal)
	local off = if axis == "X" then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	for _, s in { -1, 1 } do
		plate(parent, center + off * s * (handle / 2 - 0.2), plateD, 0.4, axis, color)
	end
end

local function buildGym(parent: Instance)
	local gym = folder("Gym", parent)
	local c = GameConfig.GymCenter
	local r = GameConfig.GymRadius
	local floorY = 0.8
	makePart({ name = "GymFloor", shape = Enum.PartType.Cylinder, size = Vector3.new(0.8, r * 2, r * 2), cframe = CFrame.new(c.X, 0.4, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = C.woodLight, material = SM.WoodPlanks, parent = gym })
	makePart({ name = "GymEdge", shape = Enum.PartType.Cylinder, size = Vector3.new(0.6, r * 2 + 1.4, r * 2 + 1.4), cframe = CFrame.new(c.X, 0.3, c.Z) * CFrame.Angles(0, 0, math.pi / 2), color = C.woodDark, material = SM.Wood, parent = gym })

	-- Low wooden fence with an opening towards the path (+X).
	local fence = folder("GymFence", gym)
	local postR = r - 0.7
	local posts = {}
	for i = 0, 11 do
		local a = math.rad(15 + i * 30)
		local p = Vector3.new(c.X + math.cos(a) * postR, floorY, c.Z + math.sin(a) * postR)
		local tall = i == 0 or i == 11
		block(fence, "FencePost", Vector3.new(0.7, if tall then 5 else 3.4, 0.7), CFrame.new(p + Vector3.new(0, if tall then 2.5 else 1.7, 0)), C.woodDark, SM.Wood)
		table.insert(posts, p)
	end
	for i = 1, 11 do
		local a, b = posts[i], posts[i + 1]
		for _, y in { 1.4, 2.9 } do
			span(fence, "FenceRail", a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), 0.35, 0.45, C.wood, SM.WoodPlanks)
		end
	end
	-- Crossbar over the entrance.
	span(fence, "GymGateBeam", posts[12] + Vector3.new(0, 4.8, 0), posts[1] + Vector3.new(0, 4.8, 0), 0.6, 0.6, C.wood, SM.Wood)
	signBoard(gym, "GymSign", Vector3.new(c.X + r + 4, 0, c.Z + 9), Vector3.new(1, 0, 0), 7.5, 3, titleSub("STRENGTH GYM", "2x training inside"), 2, 120, C.teal)

	-- Rubber mats under the heavy equipment.
	local mat = rgb(78, 120, 116)
	block(gym, "Mat", Vector3.new(10, 0.16, 6.5), CFrame.new(c.X, floorY + 0.08, c.Z - 14.5), mat, SM.Fabric)
	block(gym, "Mat", Vector3.new(9, 0.16, 8), CFrame.new(c.X, floorY + 0.08, c.Z + 14), mat, SM.Fabric)
	local top = floorY + 0.16

	-- Dumbbell rack (west side): two shelves spanning two end frames; every dumbbell's
	-- plates rest on a shelf.
	local rack = folder("DumbbellRack", gym)
	local rx = c.X - 17
	for _, dz in { -6, 6 } do
		block(rack, "RackFrame", Vector3.new(2.6, 3.8, 0.5), CFrame.new(rx, floorY + 1.9, c.Z + dz), C.wood, SM.Wood)
	end
	local lowTop, highTop = floorY + 1.6, floorY + 3.8
	block(rack, "RackShelf", Vector3.new(2.6, 0.3, 12), CFrame.new(rx, lowTop - 0.15, c.Z), C.woodLight, SM.WoodPlanks)
	block(rack, "RackShelf", Vector3.new(2.6, 0.3, 12), CFrame.new(rx, highTop - 0.15, c.Z), C.woodLight, SM.WoodPlanks)
	for i, dz in { -4.2, -1.4, 1.4, 4.2 } do
		dumbbell(rack, rx, lowTop, c.Z + dz, 1.4, "X", if i % 2 == 0 then C.terracotta else C.charcoal)
	end
	for _, dz in { -4.6, -2.3, 0, 2.3, 4.6 } do
		dumbbell(rack, rx, highTop, c.Z + dz, 1.0, "X", C.teal)
	end

	-- Squat stand: the bar rests on two J-hooks; plates are threaded on the bar.
	local sq = folder("SquatStand", gym)
	local sz = c.Z - 14
	local hookTop = top + 4.2
	for _, sx in { -1, 1 } do
		local x = c.X + sx * 2.8
		block(sq, "StandFoot", Vector3.new(0.9, 0.3, 3.2), CFrame.new(x, top + 0.15, sz), C.charcoal, SM.Metal)
		block(sq, "StandUpright", Vector3.new(0.6, 6.4, 0.6), CFrame.new(x, top + 3.2, sz), C.charcoal, SM.Metal)
		block(sq, "JHook", Vector3.new(0.6, 0.35, 0.9), CFrame.new(x, hookTop - 0.175, sz - 0.75), C.steel, SM.Metal)
	end
	local barY, barZ = hookTop + 0.175, sz - 0.75
	rod(sq, "Barbell", Vector3.new(c.X, barY, barZ), 9.4, 0.35, "X", C.steel, SM.Metal)
	for _, sx in { -1, 1 } do
		plate(sq, Vector3.new(c.X + sx * 3.4, barY, barZ), 3.2, 0.4, "X", C.terracotta)
		plate(sq, Vector3.new(c.X + sx * 3.82, barY, barZ), 2.5, 0.4, "X", C.charcoal)
		rod(sq, "Collar", Vector3.new(c.X + sx * 4.17, barY, barZ), 0.3, 0.6, "X", C.steel, SM.Metal)
	end

	-- Bench press: the bar rests on the two upright posts at the head of the bench.
	local bp = folder("BenchPress", gym)
	local bz = c.Z + 15
	block(bp, "BenchPad", Vector3.new(1.6, 0.5, 5), CFrame.new(c.X, top + 1.55, bz + 0.6), C.terracotta, SM.Fabric)
	for _, dz in { -1.4, 2.6 } do
		block(bp, "BenchLeg", Vector3.new(1.2, 1.3, 0.5), CFrame.new(c.X, top + 0.65, bz + dz), C.charcoal, SM.Metal)
	end
	local postTop = top + 3.6
	for _, sx in { -1, 1 } do
		block(bp, "BenchUpright", Vector3.new(0.5, 3.6, 0.5), CFrame.new(c.X + sx * 2.2, top + 1.8, bz - 2.3), C.charcoal, SM.Metal)
	end
	local bY = postTop + 0.175
	rod(bp, "BenchBar", Vector3.new(c.X, bY, bz - 2.3), 7.6, 0.35, "X", C.steel, SM.Metal)
	for _, sx in { -1, 1 } do
		plate(bp, Vector3.new(c.X + sx * 2.9, bY, bz - 2.3), 2.6, 0.4, "X", C.teal)
		plate(bp, Vector3.new(c.X + sx * 3.3, bY, bz - 2.3), 2.0, 0.35, "X", C.charcoal)
		rod(bp, "Collar", Vector3.new(c.X + sx * 3.6, bY, bz - 2.3), 0.25, 0.55, "X", C.steel, SM.Metal)
	end

	-- Pull-up bar: crossbar ends are set into the two posts.
	local pu = folder("PullUpBar", gym)
	local px, pz = c.X + 11, c.Z - 17
	for _, dx in { -3, 3 } do
		block(pu, "PullUpFoot", Vector3.new(0.9, 0.3, 2.6), CFrame.new(px + dx, top + 0.15, pz), C.charcoal, SM.Metal)
		block(pu, "PullUpPost", Vector3.new(0.6, 9, 0.6), CFrame.new(px + dx, top + 4.5, pz), C.wood, SM.Wood)
	end
	rod(pu, "PullUpBar", Vector3.new(px, top + 8.5, pz), 6.4, 0.3, "X", C.steel, SM.Metal)

	-- Punching bag hanging from an arm on a post.
	local pb = folder("PunchingBag", gym)
	local bx, bzz = c.X + 9, c.Z + 17
	block(pb, "BagStandBase", Vector3.new(3, 0.4, 3), CFrame.new(bx - 2.6, top + 0.2, bzz), C.charcoal, SM.Metal)
	block(pb, "BagStandPost", Vector3.new(0.6, 10, 0.6), CFrame.new(bx - 2.6, top + 5, bzz), C.charcoal, SM.Metal)
	block(pb, "BagArm", Vector3.new(3.2, 0.5, 0.5), CFrame.new(bx - 1.3, top + 9.75, bzz), C.charcoal, SM.Metal)
	block(pb, "BagChain", Vector3.new(0.15, 1.3, 0.15), CFrame.new(bx, top + 8.85, bzz), C.steel, SM.Metal)
	local bagTop = top + 8.2
	column(pb, "PunchingBag", Vector3.new(bx, bagTop - 4.2, bzz), 4.2, 2.2, C.terracotta, SM.Fabric)
	column(pb, "BagCap", Vector3.new(bx, bagTop - 0.3, bzz), 0.3, 2.3, C.cream, SM.Fabric)
	column(pb, "BagCap", Vector3.new(bx, bagTop - 4.2, bzz), 0.3, 2.3, C.cream, SM.Fabric)

	-- Plyo boxes.
	block(gym, "PlyoBox", Vector3.new(3, 2.4, 3), CFrame.new(c.X - 12, top + 1.2, c.Z + 13), C.woodLight, SM.WoodPlanks)
	block(gym, "PlyoBox", Vector3.new(2.4, 1.6, 2.4), CFrame.new(c.X - 12, top + 3.2, c.Z + 13) * CFrame.Angles(0, 0.3, 0), C.wood, SM.WoodPlanks)
end

type StallOptions = {
	counterName: string,
	stripe: Color3,
	sign: string,
	sub: string,
}

-- Wooden market stall: plank deck, counter, back wall, striped fabric awning and a
-- header sign. The front faces `facing`. Returns the counter and the stall CFrame.
local function stall(parent: Instance, center: Vector3, facing: Vector3, o: StallOptions): (Part, CFrame)
	local cf = CFrame.lookAt(center, center + facing)
	local W, D = 14, 9
	block(parent, "StallDeck", Vector3.new(W, 0.6, D), cf * CFrame.new(0, 0.3, 0), C.woodLight, SM.WoodPlanks)
	local wallH = 9
	block(parent, "StallBack", Vector3.new(W, wallH, 0.5), cf * CFrame.new(0, 0.6 + wallH / 2, D / 2 - 0.25), C.wood, SM.WoodPlanks)
	for _, sx in { -1, 1 } do
		block(parent, "StallSide", Vector3.new(0.5, 3.4, D - 1), cf * CFrame.new(sx * (W / 2 - 0.25), 0.6 + 1.7, 0.5), C.woodLight, SM.WoodPlanks)
	end
	-- Awning: from the top of the back wall down to 1.5 studs past the front edge.
	local backY, frontY = 0.6 + wallH, 8.2
	local backZ, frontZ = D / 2, -(D / 2 + 1.5)
	local dz, dy = backZ - frontZ, backY - frontY
	local len = math.sqrt(dz * dz + dy * dy)
	local ang = math.atan2(dy, dz)
	local stripes = 7
	local sw = W / stripes
	for i = 0, stripes - 1 do
		local x = -W / 2 + sw * (i + 0.5)
		local col = if i % 2 == 0 then o.stripe else C.cream
		block(parent, "Awning", Vector3.new(sw, 0.25, len), cf * CFrame.new(x, (backY + frontY) / 2, (backZ + frontZ) / 2) * CFrame.Angles(-ang, 0, 0), col, SM.Fabric)
		block(parent, "AwningValance", Vector3.new(sw, 0.8, 0.15), cf * CFrame.new(x, frontY - 0.45, frontZ + 0.05), col, SM.Fabric)
	end
	-- Front posts reach up to the underside of the awning.
	local postZ = -(D / 2 - 0.35)
	local postTop = frontY + (postZ - frontZ) / dz * dy - 0.05
	for _, sx in { -1, 1 } do
		block(parent, "StallPost", Vector3.new(0.7, postTop - 0.6, 0.7), cf * CFrame.new(sx * (W / 2 - 0.35), 0.6 + (postTop - 0.6) / 2, postZ), C.woodDark, SM.Wood)
	end
	local counterZ = -(D / 2 - 1.3)
	local counter = block(parent, o.counterName, Vector3.new(W - 3, 3.4, 1.8), cf * CFrame.new(0, 0.6 + 1.7, counterZ), C.wood, SM.WoodPlanks)
	block(parent, "CounterTop", Vector3.new(W - 2.6, 0.3, 2.3), cf * CFrame.new(0, 0.6 + 3.4 + 0.15, counterZ), C.cream)
	-- Header sign hung between the front posts, under the awning.
	local header = block(parent, "StallSign", Vector3.new(W - 2.2, 1.7, 0.3), cf * CFrame.new(0, postTop - 1.25, postZ), C.cream)
	boardText(header, Enum.NormalId.Front, titleSub(o.sign, o.sub), nil, 120)
	return counter, cf
end

local function buildShopStall(parent: Instance)
	local s = folder("FoodShopStall", parent)
	local counter, cf = stall(s, Vector3.new(42, 0, -95), Vector3.new(-1, 0, 0), { counterName = "ShopCounter", stripe = C.terracotta, sign = "FOOD SHOP", sub = "Snacks for stronger throws" })
	-- Giant toy snacks on the counter (counter top at y = 4.3).
	local y = 4.3
	blob(s, "GiantBerry", Vector3.new(1.8, 1.8, 1.8), cf * CFrame.new(-4, y + 0.85, -3.2), C.rose)
	blob(s, "BerryLeaf", Vector3.new(0.9, 0.3, 0.6), cf * CFrame.new(-4, y + 1.8, -3.2), C.leaf)
	rod(s, "GiantBone", (cf * CFrame.new(-1, y + 0.45, -3.2)).Position, 2.6, 0.7, "Z", C.cream)
	blob(s, "BoneKnob", Vector3.new(1.1, 1.0, 1.1), cf * CFrame.new(-2.3, y + 0.5, -3.2), C.cream)
	blob(s, "BoneKnob", Vector3.new(1.1, 1.0, 1.1), cf * CFrame.new(0.3, y + 0.5, -3.2), C.cream)
	blob(s, "GiantChili", Vector3.new(2.4, 1.0, 1.0), cf * CFrame.new(2.4, y + 0.5, -3.2) * CFrame.Angles(0, 0, 0.15), C.terracotta)
	makePart({ name = "GiantCookie", shape = Enum.PartType.Cylinder, size = Vector3.new(0.5, 2, 2), cframe = cf * CFrame.new(4.6, y + 1, -3.2) * CFrame.Angles(0, math.pi / 2, 0), color = C.amber, parent = s })
	-- Crates of snacks beside the stall.
	local c1 = crate(s, cf * CFrame.new(-9, 1.5, -2), 3)
	crate(s, cf * CFrame.new(-9.2, 4.0, -2) * CFrame.Angles(0, 0.3, 0), 2)
	crate(s, cf * CFrame.new(-9, 1.5, 1.4) * CFrame.Angles(0, -0.2, 0), 3)
	for i = 0, 2 do
		blob(s, "CrateSnack", Vector3.new(1, 1, 1), c1.CFrame * CFrame.new(-0.7 + i * 0.7, 1.8 + (i % 2) * 0.2, 0.8), if i == 1 then C.amber else C.rose)
	end
	prompt(counter, "Open Food Shop", "Snack Stall", "Shop")
end

local function buildHatchery(parent: Instance)
	local s = folder("EggHatchery", parent)
	local counter, cf = stall(s, Vector3.new(-42, 0, -95), Vector3.new(1, 0, 0), { counterName = "HatcheryCounter", stripe = C.teal, sign = "EGG HATCHERY", sub = "Hatch Safari pets" })
	-- Small eggs in a straw tray on the counter.
	local y = 4.3
	block(s, "EggTray", Vector3.new(6, 0.5, 1.6), cf * CFrame.new(0, y + 0.25, -3.2), C.straw, SM.Fabric)
	for i, col in { C.cream, C.teal:Lerp(C.cream, 0.5), C.amber:Lerp(C.cream, 0.4) } do
		blob(s, "TrayEgg", Vector3.new(1.1, 1.4, 1.1), cf * CFrame.new(-2 + (i - 1) * 2, y + 1.1, -3.2), col)
	end
	-- Big decorative speckled eggs on straw nests beside the stall (away from the path).
	nestEgg(s, (cf * CFrame.new(10.5, 0, -1)).Position, C.cream, C.terracotta, 1)
	nestEgg(s, (cf * CFrame.new(10, 0, 5.5)).Position, C.teal:Lerp(C.cream, 0.55), C.tealDark, 0.85)
	nestEgg(s, (cf * CFrame.new(-10, 0, 3)).Position, C.amber:Lerp(C.cream, 0.45), C.woodDark, 0.9)
	prompt(counter, "Open Hatchery", "Egg Hatchery", "Eggs")
end

local function buildFuseAltar(parent: Instance)
	local altar = folder("FuseAltar", parent)
	local hc = WorldBuilder.HubCenter
	local c = hc + Vector3.new(-41, 0, -41)
	local base = column(altar, "AltarBase", c, 1.2, 12, C.stone, SM.Slate)
	column(altar, "AltarStep", c + Vector3.new(0, 1.2, 0), 0.9, 8, C.cream, SM.Slate)
	column(altar, "AltarPlinth", c + Vector3.new(0, 2.1, 0), 2, 2.6, C.terracotta, SM.Brick)
	local crystal = block(altar, "FuseCrystal", Vector3.new(2, 2, 2), CFrame.new(c + Vector3.new(0, 5.4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), C.teal:Lerp(C.cream, 0.25), SM.Glass, false)
	crystal.Transparency = 0.15
	crystal.Reflectance = 0.15
	light(crystal, C.teal:Lerp(C.cream, 0.5), 14, 0.8)
	for i = 0, 2 do
		local a = math.rad(90 + i * 120)
		local p = c + Vector3.new(math.cos(a) * 4.6, 1.2, math.sin(a) * 4.6)
		column(altar, "OrbPillar", p, 2.2, 1.1, C.stone, SM.Slate)
		blob(altar, "FuseOrb", Vector3.new(1.4, 1.4, 1.4), CFrame.new(p + Vector3.new(0, 2.8, 0)), ({ C.amber, C.terracotta, C.teal })[i + 1])
	end
	local toPlaza = (hc - c).Unit
	signBoard(altar, "AltarSign", c - toPlaza * 1 + toPlaza:Cross(Vector3.new(0, 1, 0)) * 8.5, toPlaza, 7, 2.8, titleSub("PETS & FUSE", "3 alike make 1 better"), 1.6, 120, C.amber)
	prompt(base, "Pets & Fuse", "Fusion Altar", "Pets")
end

local function buildIndexBoard(parent: Instance)
	local board = folder("PetIndexBoard", parent)
	local hc = WorldBuilder.HubCenter
	local c = hc + Vector3.new(41, 0, -41)
	local toPlaza = (hc - c).Unit
	local cf = CFrame.lookAt(c, c + toPlaza)
	local stand = block(board, "IndexStand", Vector3.new(3.4, 3.4, 2.4), cf * CFrame.new(0, 1.7, 0), C.wood, SM.WoodPlanks)
	block(board, "IndexBase", Vector3.new(6, 0.4, 5), cf * CFrame.new(0, 0.2, 0), C.stone, SM.Slate)
	-- Open book on the lectern, tilted towards the reader.
	local book = cf * CFrame.new(0, 3.65, 0) * CFrame.Angles(math.rad(-15), 0, 0)
	block(board, "BookCover", Vector3.new(4.4, 0.25, 3), book, C.terracotta, SM.Fabric)
	for _, sx in { -1, 1 } do
		block(board, "Page", Vector3.new(2, 0.22, 2.7), book * CFrame.new(sx * 1.05, 0.2, 0) * CFrame.Angles(0, 0, sx * math.rad(-6)), C.ivory)
	end
	-- Notice board behind with pinned pet cards.
	signBoard(board, "IndexSign", (cf * CFrame.new(0, 0, 4)).Position, toPlaza, 8, 4.4, titleSub("PET INDEX", "Discover every species"), 2.2, 120, C.teal)
	prompt(stand, "Open Pet Index", "Pet Index", "Index")
end

local function buildLeaderboard(parent: Instance): { TextLabel }
	local lb = folder("Leaderboard", parent)
	local z = -234
	local cf = CFrame.lookAt(Vector3.new(0, 8, z), Vector3.new(0, 8, z + 10))
	local board = block(lb, "LeaderboardBoard", Vector3.new(18, 11, 0.4), cf, C.cream)
	block(lb, "LeaderboardFrame", Vector3.new(19, 12, 0.4), cf * CFrame.new(0, 0, 0.3), C.woodDark, SM.Wood)
	block(lb, "LeaderboardTag", Vector3.new(19, 0.6, 0.5), cf * CFrame.new(0, 6.2, 0.2), C.amber)
	for _, x in { -8, 8 } do
		block(lb, "LeaderboardLeg", Vector3.new(0.8, 13.6, 0.8), cf * CFrame.new(x, -1.2, 0.8), C.wood, SM.Wood)
	end
	local lines: { TextLine } = { { text = "TOP THROWS", size = 0.19 } }
	for i = 1, 6 do
		table.insert(lines, { text = string.format("%d. ---", i), size = 0.135, title = false })
	end
	local labels = boardText(board, Enum.NormalId.Front, lines, nil, 160)
	labels[2].Font = Enum.Font.FredokaOne
	local rows = {}
	for i = 2, #labels do
		labels[i].TextXAlignment = Enum.TextXAlignment.Left
		table.insert(rows, labels[i])
	end
	return rows
end

local function buildHubAttractions(root: Instance): { TextLabel }
	local hub = root:FindFirstChild("SpawnHub") or root
	buildGym(hub)
	buildShopStall(hub)
	buildHatchery(hub)
	buildFuseAltar(hub)
	buildIndexBoard(hub)
	return buildLeaderboard(hub)
end

local function buildThrowLine(root: Instance): CFrame
	local tl = folder("ThrowLine", root)
	local z = WorldBuilder.ThrowLineZ
	block(tl, "LaunchPad", Vector3.new(130, 1.4, 34), CFrame.new(0, 0.7, z - 17), C.woodLight, SM.WoodPlanks)
	block(tl, "PadStripe", Vector3.new(130, 1.5, 1.2), CFrame.new(0, 0.72, z - 33.4), C.terracotta)
	for _, x in { -64.4, 64.4 } do
		block(tl, "PadEdge", Vector3.new(1.2, 1.5, 34), CFrame.new(x, 0.72, z - 17), C.terracotta)
	end
	block(tl, "Line", Vector3.new(130, 1.6, 2), CFrame.new(0, 0.75, z - 1), C.ivory)
	block(tl, "LineTrim", Vector3.new(130, 1.55, 0.6), CFrame.new(0, 0.74, z - 2.3), C.teal)
	-- Invisible wall: players stay behind the line, food flies over it.
	makePart({ name = "LineBarrier", size = Vector3.new(130, 14, 1), cframe = CFrame.new(0, 7, z + 0.5), color = Color3.new(1, 0, 0), transparency = 1, parent = tl })

	-- Pennant posts mark both ends of the line.
	for _, sx in { -1, 1 } do
		local p = Vector3.new(sx * 66.5, 0, z - 1)
		column(tl, "LinePost", p, 7, 0.6, C.woodDark, SM.Wood)
		makeWedge(tl, "Pennant", Vector3.new(0.15, 1.8, 3), CFrame.new(p + Vector3.new(0, 6, -1.5)) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(0, 0, 0), C.terracotta, SM.Fabric)
	end
	signBoard(tl, "ThrowSign", Vector3.new(15, 0, z - 37), Vector3.new(0, 0, -1), 9, 3.2, titleSub("THROW LINE", "Hold E, release in the green"), 2, 120, C.terracotta)

	-- Snack crates at the back corners of the pad.
	for _, sx in { -1, 1 } do
		local cf = CFrame.new(sx * 55, 1.4, z - 28)
		local c1 = crate(tl, cf * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0.2 * sx, 0), 3)
		crate(tl, cf * CFrame.new(sx * 3.4, 1.25, 0.6) * CFrame.Angles(0, -0.3, 0), 2.5)
		blob(tl, "CrateSnack", Vector3.new(1.3, 1.3, 1.3), c1.CFrame * CFrame.new(0, 2.0, 0), C.rose)
	end
	lampPost(tl, Vector3.new(-10, 0, z - 36), 7)
	lampPost(tl, Vector3.new(10, 0, z - 36), 7)

	-- Low painted chevrons on the first stretch of the Meadow show the throw direction.
	local chevrons = folder("Chevrons", tl)
	for i = 0, 4 do
		local cz = z + 14 + i * 14
		for _, side in { -1, 1 } do
			makePart({ name = "Chevron", size = Vector3.new(8, 0.16, 1.2), cframe = CFrame.new(side * 3, 0.08, cz) * CFrame.Angles(0, side * math.rad(-35), 0), color = C.ivory, transparency = 0.25 + i * 0.12, canCollide = false, castShadow = false, parent = chevrons })
		end
	end
	return CFrame.new(0, 3.5, z - 12)
end

------------------------------------------------------------------ biomes

type Style = {
	ground: Color3,
	groundMat: Enum.Material,
	trim: Color3,
	trimMat: Enum.Material,
	hill: Color3,
	hillMat: Enum.Material,
	tag: Color3,
	cap: Color3?,
}

local Styles: { [string]: Style } = {
	Meadow = { ground = rgb(132, 180, 96), groundMat = SM.Grass, trim = C.wood, trimMat = SM.WoodPlanks, hill = rgb(108, 156, 86), hillMat = SM.Grass, tag = C.amber, cap = nil },
	Dunes = { ground = rgb(228, 200, 148), groundMat = SM.Sand, trim = rgb(196, 148, 100), trimMat = SM.Slate, hill = rgb(210, 166, 114), hillMat = SM.Sand, tag = C.terracotta, cap = nil },
	Tundra = { ground = rgb(234, 238, 234), groundMat = SM.Sand, trim = rgb(146, 172, 174), trimMat = SM.Slate, hill = rgb(168, 182, 184), hillMat = SM.Slate, tag = C.teal, cap = C.snow },
	Volcano = { ground = rgb(98, 74, 64), groundMat = SM.Slate, trim = C.terracottaDark, trimMat = SM.Brick, hill = rgb(112, 80, 68), hillMat = SM.Slate, tag = C.terracottaDark, cap = nil },
	Swamp = { ground = rgb(104, 116, 76), groundMat = SM.Grass, trim = C.woodDark, trimMat = SM.WoodPlanks, hill = rgb(88, 106, 72), hillMat = SM.Grass, tag = C.leafDark, cap = nil },
	Nuclear = { ground = rgb(150, 146, 114), groundMat = SM.Slate, trim = C.amber, trimMat = SM.SmoothPlastic, hill = rgb(126, 122, 100), hillMat = SM.Slate, tag = C.amber, cap = nil },
}

type BiomeDecorator = (parent: Instance, pos: Vector3) -> ()

local decorators: { [string]: BiomeDecorator } = {
	Meadow = function(parent, pos)
		local r = rand()
		if r < 0.4 then
			tree(parent, pos, randRange(1, 1.5))
		elseif r < 0.7 then
			flowers(parent, pos, randRange(1, 1.5))
		elseif r < 0.9 then
			bush(parent, pos, randRange(1, 1.5))
		else
			rock(parent, pos, C.stone, randRange(0.7, 1.1))
		end
	end,
	Dunes = function(parent, pos)
		local r = rand()
		if r < 0.4 then
			local s = randRange(0.9, 1.4)
			local green = rgb(110, 150, 92)
			column(parent, "Cactus", pos, 7 * s, 2.2 * s, green, SM.Grass)
			blob(parent, "CactusTop", Vector3.new(2.2, 1.4, 2.2) * s, CFrame.new(pos + Vector3.new(0, 7 * s, 0)), green, SM.Grass)
			local side = if rand() < 0.5 then -1 else 1
			column(parent, "CactusArm", pos + Vector3.new(side * 1.7 * s, 3.4 * s, 0), 2.6 * s, 1.3 * s, green, SM.Grass)
			rod(parent, "CactusElbow", pos + Vector3.new(side * 1.1 * s, 3.4 * s, 0), 1.6 * s, 1.3 * s, "X", green, SM.Grass)
		elseif r < 0.75 then
			blob(parent, "Dune", Vector3.new(26, 7, 20) * randRange(0.6, 1.3), CFrame.new(pos) * CFrame.Angles(0, rand() * 3, 0), rgb(222, 190, 136), SM.Sand)
		else
			rock(parent, pos, rgb(204, 160, 112), randRange(0.8, 1.3), SM.Sand)
		end
	end,
	Tundra = function(parent, pos)
		local r = rand()
		if r < 0.45 then
			pine(parent, pos, randRange(1, 1.5), true)
		elseif r < 0.7 then
			local s = randRange(0.8, 1.4)
			local ice = rgb(176, 214, 214)
			local p = block(parent, "IceCrystal", Vector3.new(2.2, 7, 2.2) * s, CFrame.new(pos + Vector3.new(0, 3 * s, 0)) * CFrame.Angles(0.15, rand() * 3, 0.2), ice, SM.Glass)
			p.Transparency = 0.2
			local q = block(parent, "IceCrystal", Vector3.new(1.6, 4.4, 1.6) * s, CFrame.new(pos + Vector3.new(1.6 * s, 1.8 * s, 0.4 * s)) * CFrame.Angles(-0.2, rand() * 3, -0.35), ice, SM.Glass)
			q.Transparency = 0.2
		else
			blob(parent, "SnowMound", Vector3.new(16, 5, 12) * randRange(0.6, 1.2), CFrame.new(pos), C.snow, SM.Sand)
		end
	end,
	Volcano = function(parent, pos)
		local r = rand()
		if r < 0.15 then
			local d = randRange(8, 14)
			column(parent, "PoolRim", pos, 0.5, d + 2.4, rgb(70, 54, 48), SM.Slate)
			column(parent, "LavaPool", pos + Vector3.new(0, 0.1, 0), 0.5, d, C.lava, SM.Neon, false)
		elseif r < 0.75 then
			rock(parent, pos, rgb(78, 60, 54):Lerp(C.terracottaDark, rand() * 0.4), randRange(1, 1.8))
		else
			local s = randRange(0.8, 1.2)
			column(parent, "Vent", pos, 3 * s, 7 * s, rgb(84, 64, 56), SM.Slate)
			column(parent, "VentTop", pos + Vector3.new(0, 3 * s, 0), 1.5 * s, 4.5 * s, rgb(96, 72, 62), SM.Slate)
		end
	end,
	Swamp = function(parent, pos)
		local r = rand()
		if r < 0.3 then
			local d = randRange(10, 16)
			local p = column(parent, "SwampPool", pos, 0.3, d, rgb(84, 120, 108), SM.Glass, false)
			p.Transparency = 0.15
			for i = 1, 2 do
				local a = rand() * 6.28
				column(parent, "LilyPad", pos + Vector3.new(math.cos(a), 0, math.sin(a)) * d * 0.25 + Vector3.new(0, 0.3, 0), 0.12, randRange(2, 3), C.leaf, SM.Grass, false)
				local _ = i
			end
		elseif r < 0.6 then
			local s = randRange(0.9, 1.5)
			column(parent, "Stalk", pos, 3.4 * s, 1.1 * s, C.cream)
			blob(parent, "Cap", Vector3.new(4.4, 2.4, 4.4) * s, CFrame.new(pos + Vector3.new(0, 3.6 * s, 0)), C.terracotta)
			blob(parent, "CapSpot", Vector3.new(0.9, 0.4, 0.9) * s, CFrame.new(pos + Vector3.new(0.8 * s, 4.75 * s, 0.4 * s)), C.cream)
		else
			local s = randRange(0.9, 1.4)
			for i = 0, 2 do
				local o = Vector3.new(math.cos(i * 2.1) * 0.7, 0, math.sin(i * 2.1) * 0.7) * s
				column(parent, "Reed", pos + o, (4 + i) * s, 0.25 * s, C.leafDark, SM.Grass, false)
				column(parent, "Cattail", pos + o + Vector3.new(0, (4 + i) * s, 0), 1.1 * s, 0.55 * s, C.woodDark, SM.Fabric, false)
			end
		end
	end,
	Nuclear = function(parent, pos)
		local r = rand()
		if r < 0.3 then
			local cf = CFrame.new(pos) * CFrame.Angles(0, rand() * 3, 0)
			column(parent, "Barrel", pos, 3.6, 2.8, C.amber, SM.SmoothPlastic)
			column(parent, "BarrelBand", pos + Vector3.new(0, 1.2, 0), 0.4, 2.9, C.charcoal)
			column(parent, "BarrelBand", pos + Vector3.new(0, 2.4, 0), 0.4, 2.9, C.charcoal)
			local _ = cf
		elseif r < 0.5 then
			local p = column(parent, "ToxicPuddle", pos, 0.25, randRange(8, 14), rgb(150, 178, 84), SM.Glass, false)
			p.Transparency = 0.1
		elseif r < 0.85 then
			rock(parent, pos, rgb(118, 116, 100), randRange(1, 1.6))
		else
			local s = randRange(1, 1.5)
			column(parent, "DeadTrunk", pos, 7 * s, 1 * s, rgb(110, 98, 84), SM.Wood)
			span(parent, "Branch", pos + Vector3.new(0, 5 * s, 0), pos + Vector3.new(2.6 * s, 7 * s, 0.6 * s), 0.6 * s, 0.6 * s, rgb(110, 98, 84), SM.Wood)
		end
	end,
}

------------------------------------------------------------------ biome landmarks

local function windmill(parent: Instance, pos: Vector3)
	column(parent, "WindmillTower", pos, 26, 11, C.cream, SM.Brick, true)
	column(parent, "WindmillRoof", pos + Vector3.new(0, 26, 0), 3, 12.5, C.terracotta, SM.Brick)
	column(parent, "WindmillRoof", pos + Vector3.new(0, 29, 0), 2.4, 8, C.terracotta, SM.Brick)
	column(parent, "WindmillRoof", pos + Vector3.new(0, 31.4, 0), 1.6, 3.5, C.terracottaDark, SM.Brick)
	block(parent, "WindmillDoor", Vector3.new(0.6, 5, 3.2), CFrame.new(pos + Vector3.new(5.4, 2.5, 0)), C.woodDark, SM.WoodPlanks)
	local hubPos = pos + Vector3.new(6.4, 22, 0)
	rod(parent, "WindmillHub", hubPos, 1.6, 2.2, "X", C.woodDark, SM.Wood)
	for i = 0, 3 do
		local a = i * math.pi / 2 + 0.4
		makePart({ name = "WindmillBlade", size = Vector3.new(0.5, 13, 3), cframe = CFrame.new(hubPos + Vector3.new(0.6, 0, 0)) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 7, 0), color = C.woodLight, material = SM.WoodPlanks, canCollide = false, parent = parent })
	end
end

local function barn(parent: Instance, pos: Vector3)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(-90), 0)
	block(parent, "Barn", Vector3.new(18, 11, 14), cf * CFrame.new(0, 5.5, 0), C.terracotta, SM.WoodPlanks)
	for _, s in { -1, 1 } do
		makeWedge(parent, "BarnRoof", Vector3.new(19, 6, 7.6), cf * CFrame.new(0, 14, s * 3.8) * CFrame.Angles(0, if s < 0 then 0 else math.pi, 0), C.woodDark, SM.WoodPlanks)
	end
	block(parent, "BarnDoor", Vector3.new(6, 8, 0.4), cf * CFrame.new(0, 4, -7.1), C.cream, SM.WoodPlanks)
	block(parent, "BarnDoorBrace", Vector3.new(0.5, 9.4, 0.3), cf * CFrame.new(0, 4, -7.35) * CFrame.Angles(0, 0, 0.62), C.terracottaDark, SM.Wood)
	for i = 0, 2 do
		local hp = (cf * CFrame.new(-6 + i * 4.4, 0, -10)).Position
		rod(parent, "HayBale", hp + Vector3.new(0, 1.6, 0), 3, 3.2, "X", C.straw, SM.Grass)
	end
end

local function pyramid(parent: Instance, pos: Vector3, size: number)
	local steps = 6
	for i = 0, steps - 1 do
		local w = size * (1 - i / steps)
		local h = size / steps * 0.8
		block(parent, "Pyramid", Vector3.new(w, h, w), CFrame.new(pos + Vector3.new(0, (i + 0.5) * h, 0)), rgb(214, 176, 118):Lerp(rgb(234, 206, 150), i / steps), SM.Sand)
	end
	block(parent, "PyramidCap", Vector3.new(size / steps * 0.8, size / steps * 0.6, size / steps * 0.8), CFrame.new(pos + Vector3.new(0, size * 0.8 + size / steps * 0.3, 0)), C.amber)
end

local function palm(parent: Instance, pos: Vector3, scale: number)
	for i = 0, 2 do
		column(parent, "PalmTrunk", pos + Vector3.new(i * 0.7 * scale, i * 4.6 * scale, 0), 4.8 * scale, (1.7 - i * 0.2) * scale, C.wood, SM.Wood)
	end
	local top = pos + Vector3.new(1.6 * scale, 14.2 * scale, 0)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		blob(parent, "PalmLeaf", Vector3.new(2.4, 0.5, 9) * scale, CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-18), 0, 0) * CFrame.new(0, 0, -4 * scale), C.leaf, SM.Grass)
	end
end

local function igloo(parent: Instance, pos: Vector3)
	blob(parent, "Igloo", Vector3.new(26, 22, 26), CFrame.new(pos), C.snow, SM.Sand)
	rod(parent, "IglooTunnel", pos + Vector3.new(0, 3, -12), 8, 8, "Z", C.snow, SM.Sand)
	rod(parent, "IglooDoor", pos + Vector3.new(0, 3, -16.05), 0.2, 5, "Z", C.charcoal)
end

local function snowman(parent: Instance, pos: Vector3, scale: number)
	blob(parent, "SnowBase", Vector3.one * 6 * scale, CFrame.new(pos + Vector3.new(0, 2.6 * scale, 0)), C.snow, SM.Sand, true)
	blob(parent, "SnowBody", Vector3.one * 4.4 * scale, CFrame.new(pos + Vector3.new(0, 6.6 * scale, 0)), C.snow, SM.Sand)
	blob(parent, "SnowHead", Vector3.one * 3.2 * scale, CFrame.new(pos + Vector3.new(0, 9.6 * scale, 0)), C.snow, SM.Sand)
	rod(parent, "CarrotNose", pos + Vector3.new(0, 9.6 * scale, -1.9 * scale), 1.2 * scale, 0.45 * scale, "Z", C.terracotta)
	column(parent, "Scarf", pos + Vector3.new(0, 8.1 * scale, 0), 0.7 * scale, 3.4 * scale, C.teal, SM.Fabric, false)
end

local function bigVolcano(parent: Instance, pos: Vector3)
	for i = 0, 4 do
		local d = 90 - i * 15
		column(parent, "VolcanoTier", pos + Vector3.new(0, i * 11, 0), 11, d, rgb(96, 70, 60):Lerp(C.terracottaDark, i / 6), SM.Slate)
	end
	local crater = column(parent, "VolcanoCrater", pos + Vector3.new(0, 55, 0), 0.6, 16, C.lava, SM.Neon, false)
	emitter(crater, rgb(150, 140, 136), 6, Vector3.new(0, 14, 0), 4, 6)
	light(crater, rgb(255, 140, 70), 50, 1.6)
	-- Lava streams down the sides (they genuinely glow).
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.4
		makePart({ name = "LavaStream", size = Vector3.new(3, 0.5, 40), cframe = CFrame.new(pos + Vector3.new(math.cos(a) * 24, 29, math.sin(a) * 24)) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(48), 0, 0), color = C.lava, material = SM.Neon, canCollide = false, parent = parent })
	end
end

local function coolingTower(parent: Instance, pos: Vector3)
	for i = 0, 4 do
		local d = 30 - math.abs(i - 3) * 3
		column(parent, "CoolingTower", pos + Vector3.new(0, i * 10, 0), 10, d, rgb(214, 206, 188):Lerp(rgb(188, 180, 164), i / 5), SM.Slate)
	end
	column(parent, "HazardStripe", pos + Vector3.new(0, 34, 0), 2, 28.4, C.terracotta)
	local top = makePart({ name = "TowerSteam", size = Vector3.new(20, 1, 20), cframe = CFrame.new(pos + Vector3.new(0, 52, 0)), color = Color3.new(1, 1, 1), transparency = 1, canCollide = false, parent = parent })
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(rgb(240, 240, 232))
	e.Rate = 8
	e.Lifetime = NumberRange.new(4, 6)
	e.Speed = NumberRange.new(5, 8)
	e.Size = NumberSequence.new(6, 14)
	e.Transparency = NumberSequence.new(0.5, 1)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(15, 15)
	e.Parent = top
end

local function reactor(parent: Instance, pos: Vector3)
	column(parent, "ReactorBase", pos, 4, 34, rgb(196, 188, 170), SM.Slate)
	blob(parent, "ReactorDome", Vector3.new(30, 26, 30), CFrame.new(pos + Vector3.new(0, 4, 0)), rgb(222, 216, 200), SM.Slate, true)
	-- The reactor core window: one of the few things that really glows.
	local core = rod(parent, "ReactorCore", pos + Vector3.new(14.6, 8, 0), 1, 6, "X", rgb(170, 220, 96), SM.Neon)
	core.CanCollide = false
	light(core, rgb(190, 240, 120), 30, 1.2)
end

local function giantMushroom(parent: Instance, pos: Vector3)
	column(parent, "GiantStalk", pos, 30, 6, C.cream)
	blob(parent, "GiantCap", Vector3.new(36, 14, 36), CFrame.new(pos + Vector3.new(0, 32, 0)), C.terracotta, SM.SmoothPlastic, true)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		blob(parent, "CapSpot", Vector3.new(5, 2, 5), CFrame.new(pos + Vector3.new(math.cos(a) * 11, 37, math.sin(a) * 11)), C.cream)
	end
end

local function boardwalk(parent: Instance, x: number, z0: number, z1: number)
	block(parent, "Boardwalk", Vector3.new(6, 0.5, z1 - z0), CFrame.new(x, 1.4, (z0 + z1) / 2), C.woodLight, SM.WoodPlanks)
	local n = math.floor((z1 - z0) / 20)
	for k = 0, n do
		for _, sx in { -1, 1 } do
			column(parent, "BoardwalkPost", Vector3.new(x + sx * 2.7, 0, z0 + (z1 - z0) * k / n), 2.6, 0.6, C.woodDark, SM.Wood)
		end
	end
end

local function hazardSign(parent: Instance, pos: Vector3, text: string)
	signBoard(parent, "HazardSign", pos, Vector3.new(0, 0, -1), 5, 3, titleSub(text, "Keep to the lane"), 2, 120, C.amber)
end

local Z0 = WorldBuilder.ThrowLineZ
local landmarks: { [string]: (Instance) -> () } = {
	Meadow = function(parent)
		windmill(parent, Vector3.new(-132, 0, Z0 + 110))
		barn(parent, Vector3.new(132, 0, Z0 + 70))
	end,
	Dunes = function(parent)
		pyramid(parent, Vector3.new(132, 0, Z0 + 330), 64)
		local oasis = Vector3.new(-128, 0, Z0 + 300)
		column(parent, "OasisSand", oasis, 0.3, 36, rgb(214, 184, 130), SM.Sand)
		local water = column(parent, "Oasis", oasis + Vector3.new(0, 0.1, 0), 0.4, 28, C.water, SM.Glass, false)
		water.Transparency = 0.15
		for i = 0, 3 do
			palm(parent, oasis + Vector3.new(math.cos(i * 1.6) * 17, 0, math.sin(i * 1.6) * 17), randRange(0.9, 1.2))
		end
	end,
	Tundra = function(parent)
		igloo(parent, Vector3.new(128, 0, Z0 + 560))
		for i = 0, 2 do
			snowman(parent, Vector3.new(-96 - i * 12, 0, Z0 + 520 + i * 60), randRange(0.9, 1.2))
		end
		local pond = column(parent, "FrozenPond", Vector3.new(-130, 0, Z0 + 700), 0.4, 34, rgb(180, 214, 214), SM.Glass)
		pond.Transparency = 0.1
	end,
	Volcano = function(parent)
		bigVolcano(parent, Vector3.new(130, 0, Z0 + 1020))
		-- A lava creek crossing the lane: flat, low, and it glows.
		makePart({ name = "LavaRiver", size = Vector3.new(BiomeConfig.Width - 8, 0.3, 10), cframe = CFrame.new(0, 0.15, Z0 + 940), color = C.lava, material = SM.Neon, canCollide = false, parent = parent })
		for _, sx in { -1, 1 } do
			block(parent, "LavaBank", Vector3.new(BiomeConfig.Width - 8, 0.5, 1.6), CFrame.new(0, 0.25, Z0 + 940 + sx * 5.6), rgb(70, 54, 48), SM.Slate, false)
		end
	end,
	Swamp = function(parent)
		giantMushroom(parent, Vector3.new(-124, 0, Z0 + 1500))
		giantMushroom(parent, Vector3.new(132, 0, Z0 + 1680))
		boardwalk(parent, -100, Z0 + 1320, Z0 + 1440)
	end,
	Nuclear = function(parent)
		coolingTower(parent, Vector3.new(132, 0, Z0 + 2050))
		coolingTower(parent, Vector3.new(-132, 0, Z0 + 2300))
		reactor(parent, Vector3.new(-130, 0, Z0 + 2050))
		for i = 0, 3 do
			hazardSign(parent, Vector3.new(if i % 2 == 0 then -WorldBuilder.LaneHalf - 8 else WorldBuilder.LaneHalf + 8, 0, Z0 + 1850 + i * 150), "RADIATION")
		end
	end,
}

-- Flat, non-colliding ground disc (lane tone patches and biome blends). Flat so the
-- landing lane stays a clean read from the Throw Line.
local function groundPatch(parent: Instance, x: number, z: number, d: number, color: Color3, material: Enum.Material)
	return makePart({ name = "GroundPatch", shape = Enum.PartType.Cylinder, size = Vector3.new(0.14, d, d), cframe = CFrame.new(x, 0.07, z) * CFrame.Angles(0, 0, math.pi / 2), color = color, material = material, canCollide = false, castShadow = false, parent = parent })
end

-- A tall gate pylon at a biome boundary, flag in the biome's colour, just outside the lane.
local function gatePylon(parent: Instance, pos: Vector3, style: Style, side: number)
	column(parent, "PylonBase", pos, 1.2, 4.2, style.trim, style.trimMat, true)
	block(parent, "Pylon", Vector3.new(1.6, 17, 1.6), CFrame.new(pos + Vector3.new(0, 9.7, 0)), C.woodDark, SM.Wood, true)
	blob(parent, "PylonCap", Vector3.new(2.6, 2.6, 2.6), CFrame.new(pos + Vector3.new(0, 18.6, 0)), style.tag)
	-- The flag hangs toward the lane edge so both sides frame the gate.
	block(parent, "PylonFlag", Vector3.new(5.4, 3.6, 0.2), CFrame.new(pos + Vector3.new(-side * 3.4, 15.4, 0)), style.tag, SM.Fabric, false)
	block(parent, "PylonFlagStripe", Vector3.new(5.4, 0.6, 0.22), CFrame.new(pos + Vector3.new(-side * 3.4, 14.2, 0)), C.ivory, SM.Fabric, false)
end

local function buildBiomes(root: Instance)
	local biomesFolder = folder("Biomes", root)
	local width = BiomeConfig.Width
	local lane = WorldBuilder.LaneHalf
	for _, biome in BiomeConfig.Biomes do
		local style = Styles[biome.id] or Styles.Meadow
		local bf = folder(biome.id, biomesFolder)
		local length = biome.endDistance - biome.startDistance
		local midZ = Z0 + (biome.startDistance + biome.endDistance) / 2
		local ground = block(bf, "Ground", Vector3.new(width, 4, length), CFrame.new(0, -2, midZ), style.ground, style.groundMat)
		ground:SetAttribute("BiomeId", biome.id)
		-- Low curbs at the outer edges and flat painted lines marking the landing lane.
		for _, sx in { -1, 1 } do
			block(bf, "Curb", Vector3.new(1.6, 1.4, length), CFrame.new(sx * (width / 2 - 0.8), 0.7, midZ), style.trim, style.trimMat)
			makePart({ name = "LaneLine", size = Vector3.new(0.8, 0.1, length), cframe = CFrame.new(sx * lane, 0.05, midZ), color = C.ivory, transparency = 0.3, canCollide = false, castShadow = false, parent = bf })
		end

		-- Quiet tonal patches inside the lane so the field reads as ground, not a flat sheet.
		local tones = folder("LaneTones", bf)
		for _ = 1, math.floor(length / 28) do
			local tone = if rand() < 0.5 then style.ground:Lerp(C.ivory, randRange(0.05, 0.1)) else style.ground:Lerp(C.charcoal, randRange(0.04, 0.08))
			groundPatch(tones, randRange(-lane + 8, lane - 8), Z0 + randRange(biome.startDistance + 10, biome.endDistance - 10), randRange(10, 26), tone, style.groundMat)
		end
		-- Biome blend: patches of the previous ground spill across the boundary, and a gate
		-- pylon pair marks the border from far down the lane.
		local prev = BiomeConfig.Biomes[biome.order - 1]
		if prev then
			local prevStyle = Styles[prev.id] or Styles.Meadow
			local blend = folder("Blend", bf)
			local edge = Z0 + biome.startDistance
			for i = 1, 34 do
				local t = rand()
				local z = edge + (t - 0.5) * 50
				local color = if z < edge then style.ground:Lerp(prevStyle.ground, 0.25) else prevStyle.ground:Lerp(style.ground, 0.35)
				groundPatch(blend, randRange(-width / 2 + 6, width / 2 - 6), z, randRange(8, 20), color, if z < edge then style.groundMat else prevStyle.groundMat)
				local _ = i
			end
			for _, sx in { -1, 1 } do
				gatePylon(bf, Vector3.new(sx * (lane + 5), 0, edge), style, sx)
			end
		end

		-- Small entry signs beside the lane on both sides, facing the throw line.
		local gateZ = Z0 + biome.startDistance + (if biome.order == 1 then 30 else 6)
		local info = string.format("Wind %+d%%  ·  Gravity %.2fx", math.floor(biome.wind * 100 + 0.5), biome.gravity)
		for _, sx in { -1, 1 } do
			signBoard(bf, "BiomeSign", Vector3.new(sx * (lane + 10), 0, gateZ), Vector3.new(0, 0, -1), 11, 4, titleSub(string.format("%d  %s", biome.order, biome.name), info), 2.2, 220, style.tag)
		end

		-- Soft wind streaks show tailwind (+Z) or headwind (-Z).
		local windDir = if biome.wind >= 0 then 1 else -1
		for i = 1, 3 do
			local wp = makePart({ name = "WindEmitter", size = Vector3.new(width - 60, 1, 1), cframe = CFrame.new(0, 6 + i * 6, midZ + (i - 2) * length / 3), color = Color3.new(1, 1, 1), transparency = 1, canCollide = false, parent = bf })
			emitter(wp, rgb(250, 248, 240), 2 + math.abs(biome.wind) * 20, Vector3.new(0, 1, windDir * (10 + math.abs(biome.wind) * 120)), 3, 0.6)
		end

		-- Decorations live outside the landing lane.
		local deco = folder("Decor", bf)
		-- Denser near the lane edge (the band players actually see while throwing).
		local count = math.floor(length / 6)
		local decorate = decorators[biome.id]
		for i = 1, count do
			local sx = if rand() < 0.5 then -1 else 1
			local near = i % 3 ~= 0
			local x = sx * (if near then randRange(lane + 14, lane + 46) else randRange(lane + 46, width / 2 - 10))
			local z = Z0 + randRange(biome.startDistance + 12, biome.endDistance - 8)
			if decorate then
				decorate(deco, Vector3.new(x, 0, z))
			end
		end
	end

	-- Landmarks, mountain backdrops beyond the side walls and clouds overhead.
	local scenery = folder("Scenery", biomesFolder)
	for _, biome in BiomeConfig.Biomes do
		local style = Styles[biome.id] or Styles.Meadow
		local bf = biomesFolder:FindFirstChild(biome.id) or biomesFolder
		local landmark = landmarks[biome.id]
		if landmark then
			landmark(bf)
		end
		local z = Z0 + biome.startDistance + 30
		while z < Z0 + biome.endDistance do
			for _, side in { -1, 1 } do
				local size = randRange(70, 130)
				mountain(scenery, Vector3.new(side * (BiomeConfig.Width / 2 + size * 0.6 + rand() * 30), -size * 0.12, z + randRange(-15, 15)), size, randRange(70, 110), style.hill:Lerp(style.ground, rand() * 0.25), style.hillMat, if style.cap and size > 95 then style.cap else nil)
			end
			z += 75
		end
		for _ = 1, 3 do
			cloud(scenery, Vector3.new(randRange(-170, 170), randRange(130, 190), Z0 + randRange(biome.startDistance, biome.endDistance)), randRange(0.9, 1.5))
		end
	end
	-- Hub backdrop: green hills behind the plots and clouds over the plaza.
	for z = -280, -20, 65 do
		for _, side in { -1, 1 } do
			local size = randRange(60, 100)
			mountain(scenery, Vector3.new(side * (222 + size * 0.6 + rand() * 20), -size * 0.12, z), size, randRange(60, 90), rgb(108, 156, 86):Lerp(C.leafLight, rand() * 0.3), SM.Grass, nil)
		end
	end
	for _ = 1, 4 do
		cloud(scenery, Vector3.new(randRange(-200, 200), randRange(110, 160), randRange(-300, -40)), randRange(1, 1.5))
	end

	-- Distance markers every 100 studs: a faint painted line and two short posts.
	local markers = folder("DistanceMarkers", biomesFolder)
	local last = BiomeConfig.Biomes[#BiomeConfig.Biomes].endDistance
	for d = 100, last - 1, 100 do
		local z = Z0 + d
		makePart({ name = "MarkerLine", size = Vector3.new(lane * 2, 0.12, 1), cframe = CFrame.new(0, 0.06, z), color = C.ivory, transparency = 0.45, canCollide = false, castShadow = false, parent = markers })
		for _, sx in { -1, 1 } do
			local x = sx * (lane + 2)
			column(markers, "MarkerPole", Vector3.new(x, 0, z), 4.4, 0.6, C.woodDark, SM.Wood)
			local cf = CFrame.lookAt(Vector3.new(x, 4.6, z), Vector3.new(x, 4.6, z - 10))
			local post = block(markers, "Marker" .. d, Vector3.new(4.4, 1.9, 0.3), cf, C.cream, nil, false)
			boardText(post, Enum.NormalId.Front, title(d .. "m"), nil, 300)
			boardText(post, Enum.NormalId.Back, title(d .. "m"), nil, 300)
		end
	end

	-- The end of the world: a wooden launch ramp to space.
	local endZ = Z0 + last
	makeWedge(biomesFolder, "SpaceRamp", Vector3.new(lane * 2, 18, 50), CFrame.new(0, 9, endZ - 25), C.woodLight, SM.WoodPlanks)
	for _, sx in { -1, 1 } do
		block(biomesFolder, "RampRail", Vector3.new(1.4, 1.4, 52), CFrame.new(sx * (lane + 0.7), 0.7, endZ - 25), C.terracotta)
	end
	signBoard(biomesFolder, "EdgeOfTheWorld", Vector3.new(-(lane + 12), 0, endZ - 60), Vector3.new(0, 0, -1), 12, 4.4, titleSub("EDGE OF THE WORLD", "Space 2500m  ·  The Moon 3600m"), 2.4, 300, C.teal)

	-- Invisible walls along the long sides (one segment per biome: parts max out at 2048 studs).
	for _, b in BiomeConfig.Biomes do
		local len = b.endDistance - b.startDistance
		for _, x in { -BiomeConfig.Width / 2 - 2, BiomeConfig.Width / 2 + 2 } do
			makePart({ name = "SideWall", size = Vector3.new(2, 80, len), cframe = CFrame.new(x, 40, Z0 + (b.startDistance + b.endDistance) / 2), color = Color3.new(1, 1, 1), transparency = 1, parent = biomesFolder })
		end
	end
end

------------------------------------------------------------------ plots

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
	-- One muted accent per plot (pedestal rims, gate sign, pennant).
	local palette = { C.terracotta, C.amber, C.leafDark, C.teal, rgb(150, 116, 150), C.rose }
	for i, pos in positions do
		local model = Instance.new("Model")
		model.Name = "Plot" .. i
		model:SetAttribute("PlotIndex", i)
		model.Parent = plotsFolder
		-- Local -Z faces the hub path.
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0, pos.Z))
		local accent = palette[i]
		local pad = block(model, "Pad", Vector3.new(66, 1.2, 62), cf * CFrame.new(0, 0.6, 0), rgb(146, 190, 106), SM.Grass)
		-- Wooden border with an entrance gap at the front.
		for _, e in { { 0, 31, 66, 1.4 }, { -33, 0, 1.4, 62 }, { 33, 0, 1.4, 62 }, { -20, -31, 26, 1.4 }, { 20, -31, 26, 1.4 } } do
			block(model, "Border", Vector3.new(e[3], 1.8, e[4]), cf * CFrame.new(e[1], 1.5, e[2]), C.wood, SM.WoodPlanks)
		end
		block(model, "PlotPath", Vector3.new(12, 0.2, 40), cf * CFrame.new(0, 1.3, -11), C.sand, SM.Sand)
		model.PrimaryPart = pad

		-- Owner sign and income board at the back, facing the entrance.
		local signCF = cf * CFrame.new(0, 0, 25) * CFrame.Angles(0, math.pi, 0)
		local backBase = signCF.Position + Vector3.new(0, 1.2, 0)
		local _, ownerLabels = signBoard(model, "OwnerSign", backBase, -cf.LookVector, 16, 3.6, title("Free Plot"), 4, 150, accent)
		local incomeBoard = block(model, "IncomeBoard", Vector3.new(10, 1.8, 0.3), CFrame.lookAt(backBase + Vector3.new(0, 2.6, 0), backBase + Vector3.new(0, 2.6, 0) - cf.LookVector), C.cream)
		local incomeLabel = boardText(incomeBoard, Enum.NormalId.Front, title("+0 / sec"), C.woodDark, 150)[1]

		-- Pedestals: wooden stumps with a cream top, in two rows of four.
		local pedestals: { Part } = {}
		local pedFolder = folder("Pedestals", model)
		local n = 0
		for row = 0, 1 do
			for col = 0, 3 do
				n += 1
				local local_ = CFrame.new(-21 + col * 14, 0, -6 + row * 16)
				makePart({ name = "PedestalBase", shape = Enum.PartType.Cylinder, size = Vector3.new(1.6, 8, 8), cframe = cf * local_ * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color = C.wood, material = SM.Wood, parent = pedFolder })
				makePart({ name = "PedestalRim", shape = Enum.PartType.Cylinder, size = Vector3.new(0.5, 7.2, 7.2), cframe = cf * local_ * CFrame.new(0, 3.05, 0) * CFrame.Angles(0, 0, math.pi / 2), color = accent, material = SM.SmoothPlastic, parent = pedFolder })
				local ped = makePart({ name = "Pedestal" .. n, shape = Enum.PartType.Cylinder, size = Vector3.new(1, 6.6, 6.6), cframe = cf * local_ * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.pi / 2), color = C.cream, material = SM.SmoothPlastic, parent = pedFolder })
				table.insert(pedestals, ped)
			end
		end

		-- Entrance gate with the plot number and two lanterns.
		local gateZ = -31
		for _, x in { -7, 7 } do
			block(model, "GatePost", Vector3.new(1.2, 10, 1.2), cf * CFrame.new(x, 6.2, gateZ), C.woodDark, SM.Wood)
			local lantern = block(model, "PlotLantern", Vector3.new(1, 1.3, 1), cf * CFrame.new(x, 8.5, gateZ - 1.1), C.amber, nil, false)
			light(lantern, rgb(255, 214, 150), 16, 0.8)
		end
		block(model, "GateBeam", Vector3.new(16, 1, 1.2), cf * CFrame.new(0, 11.7, gateZ), C.wood, SM.Wood)
		local gateSign = block(model, "PlotArch", Vector3.new(8, 2.2, 0.3), cf * CFrame.new(0, 9.8, gateZ - 0.75), C.cream, nil, false)
		boardText(gateSign, Enum.NormalId.Front, title("PLOT " .. i), nil, 150)
		block(model, "PlotArchTag", Vector3.new(8.4, 0.4, 0.34), cf * CFrame.new(0, 11.05, gateZ - 0.75), accent, nil, false)
		-- Trees in the back corners.
		for _, x in { -27, 27 } do
			tree(model, (cf * CFrame.new(x, 1.2, 26)).Position, randRange(0.9, 1.1))
		end

		local petsFolder = folder("Pets", model)
		table.insert(plots, {
			index = i,
			model = model,
			pad = pad,
			ownerLabel = ownerLabels[1],
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
