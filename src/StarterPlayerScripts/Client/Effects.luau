--!strict
-- Client-only visuals for the "toy safari park" look: snack wind-up while charging, the
-- flight arc, landing dust + pet pop-in, reward bursts, skippable space/moon cutscenes,
-- the quest guide chevron, the best-distance flag, weather and ambient pet animation.
--
-- Style rules: soft palette, no permanent Neon (any glow is transient and fades), and
-- strong celebrations (flash, big confetti, camera moves) only for milestones: Epic+
-- rarity, a new best, or Space/Moon. Reduced motion (system setting or the player's
-- ReduceMotion setting, checked live) removes shake, camera follow, flashes and bounces.
--
-- Everything is created locally under the SnackLocalFX folder and cleaned up on
-- skip/finish/destroy.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetModelBuilder = require(Shared:WaitForChild("PetModelBuilder"))
local GameMath = require(Shared:WaitForChild("GameMath"))

local Effects = {}
Effects.__index = Effects
Effects.BaseFov = 70

local Palette = {
	Ivory = Color3.fromRGB(246, 239, 224),
	Charcoal = Color3.fromRGB(46, 42, 38),
	Leaf = Color3.fromRGB(76, 166, 76),
	Amber = Color3.fromRGB(242, 169, 59),
	Terracotta = Color3.fromRGB(214, 110, 80),
	Teal = Color3.fromRGB(70, 150, 150),
	Sand = Color3.fromRGB(222, 196, 150),
	Cream = Color3.fromRGB(250, 242, 222),
	Stone = Color3.fromRGB(150, 140, 128),
}
Effects.Palette = Palette

-- Engine-bundled particle textures (no uploaded assets).
local TEX_SOFT = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local FONT = Enum.Font.FredokaOne
local DOTS = 10

-- `blocking` sequences own the camera (followed throws, cutscenes): input such as E or
-- Space skips them. Background flights (auto-throws, short throws) are non-blocking.
type Sequence = { cancelled: boolean, cleanups: { () -> () }, finished: boolean, blocking: boolean }

------------------------------------------------------------------ helpers

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function localPart(parent: Instance, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function ns(points: { { number } }): NumberSequence
	local kps = {}
	for _, pt in points do
		table.insert(kps, NumberSequenceKeypoint.new(pt[1], pt[2], pt[3] or 0))
	end
	return NumberSequence.new(kps)
end

local function rarityColor(rarity: any): Color3
	return (GameConfig.RarityColors :: any)[rarity] or Palette.Ivory
end

-- "3612" -> "3,612 m"
local function metres(n: number): string
	local s = tostring(math.floor(math.max(n, 0) + 0.5))
	local out = (s:reverse():gsub("(%d%d%d)", "%1,")):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out .. " m"
end

-- "THROW LINE" -> "Throw line" (labels should not shout).
local function softCase(s: string): string
	if s:upper() ~= s or s:lower() == s then
		return s
	end
	return (s:lower():gsub("^%l", string.upper))
end

local function petTitle(rec: any): string
	if type(rec) ~= "table" then
		return ""
	end
	local parts = {}
	if rec.size and rec.size ~= "Normal" then
		table.insert(parts, rec.size)
	end
	if rec.material and rec.material ~= "Normal" then
		table.insert(parts, rec.material)
	end
	local pet = PetConfig.get(rec.species)
	table.insert(parts, if pet then pet.name else "pet")
	return table.concat(parts, " ")
end

local function label(parent: Instance, size: UDim2, offset: Vector3, text: string, color: Color3): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeColor3 = Palette.Charcoal
	l.TextStrokeTransparency = 0.35
	l.Text = text
	l.Parent = gui
	gui.Parent = parent
	return gui, l
end

-- Throw arc shared by the flight and the charge preview so they agree.
local function arcFor(distance: number): (number, number)
	local d = math.min(math.max(distance, 0), BiomeConfig.SpaceDistance)
	local duration = math.clamp(0.8 + d / 700, 0.8, 3.2)
	local biome = BiomeConfig.biomeAtDistance(d)
	local height = math.clamp(d * 0.28 / biome.gravity, 12, 450)
	return duration, height
end

local function arcPoint(a: Vector3, b: Vector3, height: number, t: number): Vector3
	return a:Lerp(b, t) + Vector3.new(0, 4 * height * t * (1 - t), 0)
end

local function noise3(t: number, seed: number): Vector3
	return Vector3.new(math.noise(t, seed, 0.5), math.noise(t, seed + 17, 1.5), 0)
end

local function rootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

------------------------------------------------------------------ construction

function Effects.new(hud: any, getState: () -> any)
	local self = setmetatable({}, Effects) :: any
	self.hud = hud
	self.getState = getState
	self.alive = true
	self.seq = nil :: Sequence?
	self.connections = {} :: { RBXScriptConnection }
	self.anims = {} :: { [() -> ()]: boolean }
	self.reducedAt = -1
	self.reducedCached = false
	self.folder = Instance.new("Folder")
	self.folder.Name = "SnackLocalFX"
	self.folder.Parent = Workspace

	self.tint = Instance.new("ColorCorrectionEffect")
	self.tint.Name = "SnackWeatherTint"
	self.tint.Parent = Lighting
	-- Gentle bloom: highlights soften without turning every bright part into a lamp.
	self.bloom = Instance.new("BloomEffect")
	self.bloom.Name = "SnackBloom"
	self.bloom.Intensity = 0.35
	self.bloom.Size = 20
	self.bloom.Threshold = 1.9
	self.bloom.Parent = Lighting
	self.atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not self.atmosphere then
		local a = Instance.new("Atmosphere")
		a.Density = 0.28
		a.Offset = 0.2
		a.Haze = 1.2
		a.Glare = 0.3
		a.Color = Color3.fromRGB(236, 226, 206)
		a.Decay = Color3.fromRGB(150, 160, 170)
		a.Parent = Lighting
		self.atmosphere = a
	end
	self.baseAtmosphereColor = self.atmosphere.Color
	self.weatherPart = nil :: Part?
	self.weatherEmitter = nil :: ParticleEmitter?
	self.weatherRate = 0
	self.weatherConn = nil :: RBXScriptConnection?
	self.weatherColor = nil :: Color3?
	self.sunRays = Instance.new("SunRaysEffect")
	self.sunRays.Name = "SnackSunRays"
	self.sunRays.Intensity = 0.04
	self.sunRays.Spread = 0.6
	self.sunRays.Parent = Lighting
	self.guide = nil :: any
	self.charge = nil :: any
	self.lastRelease = nil :: { pos: Vector3, time: number }?
	self.shakeStop = nil :: (() -> ())?
	self.bestMarker = nil :: Model?
	self.bestMarkerDistance = 0
	return self
end

-- System reduced-motion OR the player's ReduceMotion setting. Cached for 0.25 s so it
-- can be called every frame and still follows changes mid-session.
function Effects:_reduced(): boolean
	local now = os.clock()
	if now - self.reducedAt < 0.25 then
		return self.reducedCached
	end
	self.reducedAt = now
	local reduced = false
	local ok, system = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	if ok and system == true then
		reduced = true
	else
		local state = self.getState and self.getState()
		local settings = type(state) == "table" and state.settings
		reduced = type(settings) == "table" and settings.ReduceMotion == true
	end
	self.reducedCached = reduced
	return reduced
end

function Effects:_settings(): { [string]: any }
	local state: any = self.getState() or {}
	return if type(state.settings) == "table" then state.settings else {}
end

-- Per-frame animation not tied to a sequence. `step(alpha, elapsed, dt)`; `done` always
-- runs (on completion, error or destroy). Returns a stop function.
function Effects:_animate(duration: number, step: (number, number, number) -> (), done: (() -> ())?): () -> ()
	local start = os.clock()
	local conn: RBXScriptConnection? = nil
	local stopped = false
	local function stop()
		if stopped then
			return
		end
		stopped = true
		if conn then
			conn:Disconnect()
		end
		self.anims[stop] = nil
		if done then
			local ok, err = pcall(done :: any)
			if not ok then
				warn("[SnackForce] FX anim cleanup failed:", err)
			end
		end
	end
	self.anims[stop] = true
	conn = RunService.RenderStepped:Connect(function(dt)
		local elapsed = os.clock() - start
		local a = if duration > 0 then math.min(elapsed / duration, 1) else 1
		local ok, err = pcall(step :: any, a, elapsed, dt)
		if not ok then
			warn("[SnackForce] FX anim failed:", err)
			stop()
		elseif a >= 1 then
			stop()
		end
	end)
	return stop
end

-- Destroys `inst` after `t` seconds (no-op if already gone).
local function expire(inst: Instance, t: number)
	task.delay(t, function()
		inst:Destroy()
	end)
end

-- One-shot particle burst from an invisible anchor (box of `size`) at `position`.
function Effects:_burst(position: Vector3, size: Vector3, count: number, life: number, configure: (ParticleEmitter) -> ())
	if count <= 0 then
		return
	end
	local anchor = localPart(self.folder, Enum.PartType.Block, size, CFrame.new(position), Palette.Ivory)
	anchor.Name = "FxBurst"
	anchor.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightEmission = 0
	e.LightInfluence = 1
	configure(e)
	e.Parent = anchor
	e:Emit(count)
	expire(anchor, life + 0.4)
end

function Effects:_count(n: number): number
	return if self:_reduced() then math.min(n, math.max(2, math.floor(n * 0.25))) else n
end

------------------------------------------------------------------ sequences

function Effects:isPlaying(): boolean
	local seq = self.seq
	return seq ~= nil and seq.blocking
end

function Effects:_begin(blocking: boolean): Sequence
	self:skip()
	local seq: Sequence = { cancelled = false, cleanups = {}, finished = false, blocking = blocking }
	self.seq = seq
	return seq
end

function Effects:_finish(seq: Sequence)
	if seq.finished then
		return
	end
	seq.finished = true
	for i = #seq.cleanups, 1, -1 do
		local ok, err = pcall(seq.cleanups[i] :: any)
		if not ok then
			warn("[SnackForce] FX cleanup failed:", err)
		end
	end
	table.clear(seq.cleanups)
	if self.seq == seq then
		self.seq = nil
	end
end

function Effects:skip()
	local seq = self.seq
	if seq then
		seq.cancelled = true
		self:_finish(seq)
	end
end

-- Waits `t` seconds unless the sequence is cancelled first. Returns false if cancelled.
local function waitFor(seq: Sequence, t: number): boolean
	local deadline = os.clock() + t
	while os.clock() < deadline do
		if seq.cancelled then
			return false
		end
		task.wait()
	end
	return not seq.cancelled
end

local function takeCamera(seq: Sequence): Camera?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local prevType = camera.CameraType
	local prevFov = Effects.BaseFov -- never restore a mid-tween (punched) FOV
	camera.CameraType = Enum.CameraType.Scriptable
	table.insert(seq.cleanups, function()
		camera.FieldOfView = prevFov
		camera.CameraType = if prevType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else prevType
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end)
	return camera
end

-- Binds a per-frame updater to the sequence. Returns a function that stops it early
-- (each phase must stop before the next one takes over the camera).
local function bind(seq: Sequence, fn: (dt: number) -> ()): () -> ()
	local conn = RunService.RenderStepped:Connect(fn)
	local function stop()
		conn:Disconnect()
	end
	table.insert(seq.cleanups, stop)
	return stop
end

------------------------------------------------------------------ snack + small effects

function Effects:_foodPart(parent: Instance, foodId: string?, withTrail: boolean): Part
	local food = FoodConfig.get(foodId) or FoodConfig.Foods[1]
	local shape = if food.shape == "Block" then Enum.PartType.Block elseif food.shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Ball
	local size = if shape == Enum.PartType.Cylinder then Vector3.new(2.6, 1.3, 1.3) else Vector3.new(1.6, 1.6, 1.6)
	local p = localPart(parent, shape, size, CFrame.new(), food.color, Enum.Material.SmoothPlastic)
	p.Name = "FlyingFood"
	if withTrail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.55, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.55, 0)
		a1.Parent = p
		local trail = Instance.new("Trail")
		trail.Name = "Streak"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.FaceCamera = true
		trail.Lifetime = 0.3
		trail.MinLength = 0.05
		trail.LightEmission = 0.1
		trail.LightInfluence = 0.6
		trail.WidthScale = ns({ { 0, 1 }, { 1, 0.1 } })
		trail.Color = ColorSequence.new(food.color:Lerp(Palette.Ivory, 0.3), Palette.Ivory)
		trail.Transparency = ns({ { 0, 0.3 }, { 0.6, 0.75 }, { 1, 1 } })
		trail.Parent = p
	end
	return p
end

-- Soft sand/cream dust puff on the ground.
function Effects:_dust(ground: Vector3, scale: number, tint: Color3?)
	local a = if tint then Palette.Sand:Lerp(tint, 0.35) else Palette.Sand
	self:_burst(ground + Vector3.new(0, 0.4, 0), Vector3.new(2.5, 0.2, 2.5) * scale, self:_count(math.floor(14 * scale)), 1.3, function(e)
		e.Texture = TEX_SOFT
		e.Color = ColorSequence.new(a, Palette.Cream)
		e.Transparency = ns({ { 0, 0.6 }, { 0.2, 0.35 }, { 1, 1 } })
		e.Size = ns({ { 0, 1.2 * scale }, { 1, 4.5 * scale } })
		e.Lifetime = NumberRange.new(0.7, 1.3)
		e.Speed = NumberRange.new(5 * scale, 13 * scale)
		e.SpreadAngle = Vector2.new(80, 80)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, -5, 0)
		e.Drag = 5
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-40, 40)
	end)
end

-- Thin ring on the ground that expands and fades (short fade only when reduced).
function Effects:_groundRing(ground: Vector3, color: Color3, scale: number)
	local segments = 18
	local holder = Instance.new("Folder")
	holder.Name = "LandingRing"
	holder.Parent = self.folder
	local parts = {}
	for i = 1, segments do
		local p = localPart(holder, Enum.PartType.Block, Vector3.new(1, 0.08, 0.35), CFrame.new(ground), color)
		p.Transparency = 0.3
		parts[i] = p
	end
	local reduced = self:_reduced()
	local r0, r1 = 1.6 * scale, (if reduced then 3.5 else 9.5) * scale
	local y = ground.Y + 0.07
	self:_animate(if reduced then 0.35 else 0.75, function(a: number, _: number, _: number)
		local e = 1 - (1 - a) ^ 4 -- ease-out quart, no overshoot
		local r = r0 + (r1 - r0) * (if reduced then 0 else e)
		local width = 0.45 * (1 - e) + 0.12
		local len = (2 * math.pi * r / segments) * 1.08
		for i, p in parts do
			local ang = (i / segments) * math.pi * 2
			p.Size = Vector3.new(len, 0.08, width)
			p.CFrame = CFrame.new(ground.X + math.cos(ang) * r, y, ground.Z + math.sin(ang) * r) * CFrame.Angles(0, -ang + math.pi / 2, 0)
			p.Transparency = 0.3 + 0.7 * a
		end
	end, function()
		holder:Destroy()
	end)
end

-- Light paper confetti (only for milestones; cheap ballistic sim in one loop).
function Effects:_confetti(origin: Vector3, accent: Color3, count: number, power: number)
	local colors = { accent, Palette.Amber, Palette.Leaf, Palette.Terracotta, Palette.Teal, Palette.Ivory }
	local rng = Random.new()
	local holder = Instance.new("Folder")
	holder.Name = "Confetti"
	holder.Parent = self.folder
	local bits = {}
	for i = 1, count do
		local p = localPart(holder, Enum.PartType.Block, Vector3.new(0.5, 0.05, 0.3) * (0.8 + power * 0.2), CFrame.new(origin), colors[(i - 1) % #colors + 1])
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(1.3, 2.4), rng:NextNumber(-1, 1))
		bits[i] = {
			part = p,
			pos = origin,
			vel = dir.Unit * rng:NextNumber(14, 24) * power,
			rot = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-4, 4), rng:NextNumber(-9, 9)),
			phase = rng:NextNumber(0, 6),
		}
	end
	self:_animate(1.8, function(a: number, elapsed: number, dt: number)
		local step = math.min(dt, 1 / 20)
		local fade = math.clamp((a - 0.65) / 0.35, 0, 1)
		for _, b in bits do
			b.vel = b.vel * (1 - math.min(2.6 * step, 0.5)) + Vector3.new(0, -26 * step, 0)
			b.pos = b.pos + (b.vel + Vector3.new(math.sin(elapsed * 9 + b.phase) * 1.5, 0, 0)) * step
			b.rot = b.rot * CFrame.Angles(b.spin.X * step, b.spin.Y * step, b.spin.Z * step)
			b.part.CFrame = CFrame.new(b.pos) * b.rot
			b.part.Transparency = fade
		end
	end, function()
		holder:Destroy()
	end)
end

-- Coin sparkles for every catch; confetti + flash only for milestones.
function Effects:_reward(position: Vector3, payload: any, milestone: boolean)
	local idx = payload.rarityIndex or 1
	local accent = rarityColor(payload.rarity)
	local count = if milestone then 16 else 4 + math.min(idx, 3) * 2
	self:_burst(position + Vector3.new(0, 1.5, 0), Vector3.one * 1.5, self:_count(count), 1.1, function(e)
		e.Texture = TEX_SPARK
		e.Color = ColorSequence.new(Palette.Amber, Palette.Ivory:Lerp(accent, 0.3))
		e.LightEmission = 0.35
		e.Transparency = ns({ { 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 } })
		e.Size = ns({ { 0, 0.1 }, { 0.15, 0.8 }, { 1, 0 } })
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(6, 13)
		e.SpreadAngle = Vector2.new(55, 55)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, -20, 0)
		e.Drag = 1.5
		e.RotSpeed = NumberRange.new(-120, 120)
	end)
	if milestone and not self:_reduced() then
		local big = idx >= GameConfig.rarityIndex("Legendary") or payload.cutscene ~= nil
		self:_confetti(position + Vector3.new(0, 2, 0), accent, if big then 40 else 26, if big then 1.25 else 1)
	end
end

function Effects:_isMilestone(payload: any): boolean
	return (payload.rarityIndex or 1) >= GameConfig.rarityIndex("Epic") or (payload.newRecord == true and payload.manual == true) or payload.cutscene ~= nil
end

-- Reward burst + short toasts + (milestones only) a soft screen flash.
function Effects:_celebrate(payload: any, position: Vector3?)
	if not self.alive then
		return
	end
	local idx = payload.rarityIndex or 1
	local color = rarityColor(payload.rarity)
	local epic = idx >= GameConfig.rarityIndex("Epic")
	local newBest = payload.newRecord == true and payload.manual == true
	local milestone = self:_isMilestone(payload)
	if position then
		self:_reward(position, payload, milestone)
	end
	if epic then
		self.hud:toast(string.format("%s catch!", tostring(payload.rarity)), color)
	end
	if newBest then
		self.hud:toast("New best: " .. metres(payload.distance or 0), Palette.Amber)
	end
	if milestone and not self:_reduced() then
		local strength = if idx >= GameConfig.rarityIndex("Mythic") then 0.4 elseif idx >= GameConfig.rarityIndex("Legendary") then 0.3 elseif epic then 0.22 else 0.15
		self.hud:flash(if epic then color else Palette.Amber, strength)
	end
end

-- Collects the pet's parts relative to its pivot for squash-and-stretch.
local function partRig(model: Model): { { part: BasePart, rel: CFrame, size: Vector3, ball: boolean } }
	local pivot = model:GetPivot()
	local rig = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(rig, { part = d, rel = pivot:ToObjectSpace(d.CFrame), size = d.Size, ball = d:IsA("Part") and d.Shape == Enum.PartType.Ball })
		end
	end
	return rig
end

local function axisScale(v: Vector3, s: Vector3): number
	return Vector3.new(v.X * s.X, v.Y * s.Y, v.Z * s.Z).Magnitude
end

local function poseRig(rig: { { part: BasePart, rel: CFrame, size: Vector3, ball: boolean } }, base: CFrame, s: Vector3)
	for _, c in rig do
		local p = c.rel.Position
		c.part.CFrame = base * CFrame.new(p.X * s.X, p.Y * s.Y, p.Z * s.Z) * c.rel.Rotation
		if c.ball then
			c.part.Size = c.size * ((s.X + s.Y + s.Z) / 3)
		else
			c.part.Size = Vector3.new(c.size.X * axisScale(c.rel.XVector, s), c.size.Y * axisScale(c.rel.YVector, s), c.size.Z * axisScale(c.rel.ZVector, s))
		end
	end
end

local function setFade(model: Model, gui: BillboardGui?, a: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = a
		end
	end
	if gui then
		for _, l in gui:GetChildren() do
			if l:IsA("TextLabel") then
				l.TextTransparency = a
				l.TextStrokeTransparency = 0.35 + 0.65 * a
			end
		end
	end
end

-- The caught pet pops up from the landing spot with a squash-and-stretch hop
-- (a short fade-in when reduced motion is on), then fades out after a few seconds.
function Effects:_spawnCaughtPet(payload: any, ground: Vector3, parent: Instance?): Model?
	local rec = payload.pet
	if type(rec) ~= "table" or not self.alive then
		return nil
	end
	local model, height = PetModelBuilder.build(rec.species, rec.material, rec.size, CFrame.new(ground) * CFrame.Angles(0, math.pi, 0))
	model.Parent = parent or self.folder
	local gui: BillboardGui? = nil
	local primary = model.PrimaryPart
	if primary then
		local text = (if payload.rarity then tostring(payload.rarity) .. " " else "") .. petTitle(rec)
		local g = label(primary, UDim2.fromOffset(240, 36), Vector3.new(0, height + 0.5, 0), text, rarityColor(payload.rarity):Lerp(Palette.Ivory, 0.15))
		gui = g
	end
	local base = model:GetPivot()
	local rig = partRig(model)
	if self:_reduced() then
		setFade(model, gui, 1)
		self:_animate(0.25, function(a: number, _: number, _: number)
			setFade(model, gui, 1 - a)
		end, function()
			if model.Parent then
				setFade(model, gui, 0)
			end
		end)
	else
		local hop = math.clamp(height * 0.35, 1.2, 6)
		poseRig(rig, base, Vector3.one * 0.2)
		self:_animate(0.85, function(_: number, t: number, _: number)
			if not model.Parent then
				return
			end
			local u, sy, y = 1, 1, 0
			if t < 0.1 then
				local q = t / 0.1
				u = 0.2 + 0.8 * (1 - (1 - q) ^ 2)
				sy = 1.25
			elseif t < 0.5 then
				local q = (t - 0.1) / 0.4
				y = hop * 4 * q * (1 - q)
				sy = 1 + 0.16 * math.abs(1 - 2 * q) -- stretch with speed, round at the apex
			else
				local r = (t - 0.5) / 0.35
				sy = 1 - 0.22 * (1 - r) ^ 2 * math.cos(r * math.pi * 2.5) -- land squash, small rebound
			end
			local sxz = 1 / math.sqrt(sy)
			poseRig(rig, base * CFrame.new(0, y, 0), Vector3.new(sxz, sy, sxz) * u)
		end, function()
			if model.Parent then
				poseRig(rig, base, Vector3.one)
			end
		end)
	end
	task.delay(4, function()
		if not model.Parent then
			return
		end
		self:_animate(0.4, function(a: number, _: number, _: number)
			if model.Parent then
				setFade(model, gui, a)
			end
		end, function()
			model:Destroy()
		end)
	end)
	return model
end

-- Distance label where a snack landed, plus a faint fading column for far throws.
function Effects:_landingMarker(ground: Vector3, payload: any)
	local color = Palette.Ivory:Lerp(rarityColor(payload.rarity), 0.45)
	local anchor = localPart(self.folder, Enum.PartType.Block, Vector3.one * 0.2, CFrame.new(ground + Vector3.new(0, 0.1, 0)), Palette.Ivory)
	anchor.Name = "LandingMarker"
	anchor.Transparency = 1
	if (payload.distance or 0) > 120 then
		local column = localPart(anchor, Enum.PartType.Cylinder, Vector3.new(36, 1, 1), CFrame.new(ground + Vector3.new(0, 18, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.ForceField)
		column.Name = "LandingColumn"
		column.Transparency = 0.15
		tween(column, 2.6, { Transparency = 1 }, Enum.EasingStyle.Sine)
	end
	local text = metres(payload.distance or 0) .. (if payload.sweetSpot then "  ·  sweet spot" else "")
	local gui, l = label(anchor, UDim2.fromOffset(180, 32), Vector3.new(0, 7, 0), text, Palette.Ivory)
	gui.MaxDistance = 3000
	if not self:_reduced() then
		tween(gui, 2.8, { StudsOffsetWorldSpace = Vector3.new(0, 9, 0) }, Enum.EasingStyle.Sine)
	end
	task.delay(2.2, function()
		if l.Parent then
			tween(l, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
	expire(anchor, 3)
end

-- Landing beat: dust, ring, marker, then the pet hop and the reward.
function Effects:_land(ground: Vector3, payload: any)
	local biome = BiomeConfig.biomeAtDistance(math.max(ground.Z, 0))
	local idx = payload.rarityIndex or 1
	self:_dust(ground, 1, biome.groundColor)
	self:_groundRing(ground, Palette.Ivory:Lerp(rarityColor(payload.rarity), math.min(0.15 + idx * 0.1, 0.7)), 1)
	self:_landingMarker(ground, payload)
	task.delay(0.08, function()
		if self.alive then
			self:_spawnCaughtPet(payload, ground, nil)
		end
	end)
	task.delay(0.2, function()
		self:_celebrate(payload, ground)
	end)
end

------------------------------------------------------------------ best distance flag

-- Flag + dashed line at the player's best distance (matte materials, no glow).
function Effects:setBestDistance(distance: number)
	if distance <= 0 or math.abs(distance - self.bestMarkerDistance) < 1 then
		return
	end
	local improved = self.bestMarkerDistance > 0
	self.bestMarkerDistance = distance
	if self.bestMarker then
		self.bestMarker:Destroy()
	end
	local shown = math.min(distance, BiomeConfig.SpaceDistance - 5)
	local model = Instance.new("Model")
	model.Name = "BestThrowFlag"
	local base = Vector3.new(BiomeConfig.Width / 2 - 30, 0, shown)
	localPart(model, Enum.PartType.Cylinder, Vector3.new(0.3, 3.2, 3.2), CFrame.new(base + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), Palette.Ivory)
	local pole = localPart(model, Enum.PartType.Cylinder, Vector3.new(16, 0.4, 0.4), CFrame.new(base + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 112, 78), Enum.Material.Wood)
	pole.Name = "Pole"
	local flag = Instance.new("WedgePart")
	flag.Name = "Pennant"
	flag.Size = Vector3.new(0.2, 3.4, 6)
	flag.CFrame = CFrame.new(base + Vector3.new(0, 14.2, -3.2))
	flag.Color = Palette.Amber
	flag.Material = Enum.Material.SmoothPlastic
	flag.Anchored = true
	flag.CanCollide = false
	flag.CanQuery = false
	flag.CanTouch = false
	flag.CastShadow = false
	flag.Parent = model
	-- Dashed line across the track.
	local dashes = 17
	local span = BiomeConfig.Width - 20
	for i = 1, dashes do
		local x = -span / 2 + (i - 0.5) * span / dashes
		local d = localPart(model, Enum.PartType.Block, Vector3.new(span / dashes * 0.55, 0.06, 0.6), CFrame.new(x, 0.05, shown), Palette.Amber)
		d.Transparency = 0.45
	end
	local gui = label(pole, UDim2.fromOffset(180, 40), Vector3.new(0, 10, 0), "Best " .. metres(distance), Palette.Ivory)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 600
	model.Parent = self.folder
	self.bestMarker = model
	if improved then
		self:_burst(base + Vector3.new(0, 14, -3), Vector3.one * 2, self:_count(10), 1.2, function(e)
			e.Texture = TEX_SPARK
			e.Color = ColorSequence.new(Palette.Amber, Palette.Ivory)
			e.LightEmission = 0.3
			e.Size = ns({ { 0, 0.6 }, { 1, 0 } })
			e.Lifetime = NumberRange.new(0.6, 1.1)
			e.Speed = NumberRange.new(3, 7)
			e.SpreadAngle = Vector2.new(180, 180)
		end)
	end
end

------------------------------------------------------------------ charging

function Effects:_endCharge(released: boolean)
	local h: any = self.charge
	if not h then
		return
	end
	self.charge = nil
	if released and h.part.Parent then
		local pos = h.part.Position
		self.lastRelease = { pos = pos, time = os.clock() }
		self:_burst(pos, Vector3.one * 0.6, self:_count(7), 0.7, function(e)
			e.Texture = TEX_SOFT
			e.Color = ColorSequence.new(Palette.Cream, Palette.Sand)
			e.Transparency = ns({ { 0, 0.45 }, { 1, 1 } })
			e.Size = ns({ { 0, 0.5 }, { 1, 1.8 } })
			e.Lifetime = NumberRange.new(0.35, 0.6)
			e.Speed = NumberRange.new(4, 8)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Drag = 6
		end)
	end
	h.part:Destroy()
	h.dots:Destroy()
end

-- The held snack wobbles and squashes with charge, wind-up motes gather around it, and a
-- faint dotted arc previews the throw. The sweet spot adds a soft green outline + sparkle.
function Effects:setCharging(charge: number?, foodId: string?)
	if charge == nil then
		self:_endCharge(true)
		return
	end
	local character = Players.LocalPlayer.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local h: any = self.charge
	if h and (h.foodId ~= foodId or not h.part.Parent) then
		self:_endCharge(false)
		h = nil
	end
	if not h then
		local part: Part = self:_foodPart(self.folder, foodId, false)
		part.Name = "HeldSnack"
		local att = Instance.new("Attachment")
		att.Parent = part
		local motes = Instance.new("ParticleEmitter")
		motes.Name = "WindUp"
		motes.Texture = TEX_SPARK
		motes.Rate = 0
		motes.Shape = Enum.ParticleEmitterShape.Sphere
		motes.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		motes.Speed = NumberRange.new(2, 4)
		motes.Lifetime = NumberRange.new(0.35, 0.55)
		motes.Size = ns({ { 0, 0 }, { 0.3, 0.3 }, { 1, 0 } })
		motes.Transparency = ns({ { 0, 0.4 }, { 1, 1 } })
		motes.Color = ColorSequence.new(Palette.Cream, Palette.Amber)
		motes.LightEmission = 0.2
		motes.Parent = att
		local hl = Instance.new("Highlight")
		hl.Name = "SweetSpot"
		hl.Adornee = part
		hl.Enabled = false
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillColor = Palette.Leaf
		hl.FillTransparency = 0.7
		hl.OutlineColor = Palette.Ivory
		hl.OutlineTransparency = 0.25
		hl.Parent = part
		local dots = Instance.new("Folder")
		dots.Name = "ArcPreview"
		dots.Parent = self.folder
		local dotParts = {}
		for i = 1, DOTS do
			local d = localPart(dots, Enum.PartType.Ball, Vector3.one * 0.4, CFrame.new(), Palette.Ivory)
			d.Transparency = 1
			dotParts[i] = d
		end
		h = {
			part = part,
			base = part.Size,
			motes = motes,
			highlight = hl,
			dots = dots,
			dotParts = dotParts,
			foodId = foodId,
			start = os.clock(),
			sweet = false,
		}
		self.charge = h
	end
	local reduced = self:_reduced()
	local t = os.clock() - h.start
	local sweet = GameMath.isSweetSpot(charge)
	local part: Part = h.part

	-- Wobble + squash, faster and stronger as the charge builds.
	local freq = 5 + 9 * charge
	local amp = if reduced then 0 else 0.08 + 0.22 * charge
	local sq = if reduced then 0 else (0.03 + 0.1 * charge) * math.sin(t * freq * 2)
	local grow = 0.85 + charge * 0.35
	if part.Shape == Enum.PartType.Ball then
		part.Size = h.base * grow * (1 + sq * 0.6)
	else
		part.Size = h.base * grow * Vector3.new(1 + sq * 0.5, 1 - sq, 1 + sq * 0.5)
	end
	part.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - 0.45, 0.35 * charge) * CFrame.Angles(math.sin(t * freq) * amp, 0, math.cos(t * freq * 0.7) * amp * 0.6)
	h.motes.Rate = if reduced then 0 else 3 + 26 * charge * charge

	if sweet ~= h.sweet then
		h.sweet = sweet
		h.highlight.Enabled = sweet
		h.motes.Color = if sweet then ColorSequence.new(Palette.Ivory, Palette.Leaf) else ColorSequence.new(Palette.Cream, Palette.Amber)
		if sweet then
			h.highlight.FillTransparency = 0.35
			tween(h.highlight, 0.25, { FillTransparency = 0.7 })
			self:_burst(part.Position, Vector3.one * 0.5, self:_count(9), 0.6, function(e)
				e.Texture = TEX_SPARK
				e.Color = ColorSequence.new(Palette.Ivory, Palette.Leaf)
				e.LightEmission = 0.3
				e.Size = ns({ { 0, 0.45 }, { 1, 0 } })
				e.Lifetime = NumberRange.new(0.3, 0.5)
				e.Speed = NumberRange.new(5, 9)
				e.SpreadAngle = Vector2.new(180, 180)
				e.Drag = 4
			end)
		end
	end

	-- Dotted arc preview: the first stretch of the predicted arc, marching outward.
	local state: any = self.getState() or {}
	local food = FoodConfig.get(foodId) or FoodConfig.Foods[1]
	local raw = GameMath.rawDistance(state.strength or 0, food.power, charge, sweet)
	local distance = GameMath.resolveFlight(raw)
	local _, height = arcFor(distance)
	local start = part.Position
	local landing = Vector3.new(start.X, 0.6, math.min(distance, BiomeConfig.SpaceDistance))
	local reach = math.clamp(70 / math.max(landing.Z - start.Z, 1), 0.02, 1)
	local phase = if reduced then 0 else (t * 1.4) % 1
	local dotColor = if sweet then Palette.Ivory:Lerp(Palette.Leaf, 0.5) else Palette.Ivory
	for i, d in h.dotParts do
		local f = (i - 1 + phase) / DOTS
		d.CFrame = CFrame.new(arcPoint(start, landing, height, f * reach))
		d.Color = dotColor
		d.Transparency = 0.35 + 0.6 * f + (if i == 1 then 0.6 * (1 - phase) else 0)
	end
end

------------------------------------------------------------------ release + training

-- Small FOV kick (and a soft shake on strong releases). Skipped with reduced motion.
function Effects:punch(strength: number)
	local camera = Workspace.CurrentCamera
	if not camera or self:isPlaying() or self:_reduced() then
		return
	end
	local fov = Effects.BaseFov
	camera.FieldOfView = fov + 4 * strength
	tween(camera, 0.3, { FieldOfView = fov }, Enum.EasingStyle.Quad)
	local humanoid = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and strength >= 1 then
		if self.shakeStop then
			self.shakeStop()
		end
		local seed = math.random() * 100
		self.shakeStop = self:_animate(0.22, function(a: number, elapsed: number, _: number)
			if humanoid.Parent then
				humanoid.CameraOffset = noise3(elapsed * 30, seed) * (1 - a) ^ 2 * 0.35 * strength
			end
		end, function()
			humanoid.CameraOffset = Vector3.zero
		end)
	end
end

-- Floating "+N" above the character when training.
function Effects:trainPop(amount: number, boosted: boolean)
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local offset = Vector3.new(math.random(-12, 12) / 10, 2.4, 0)
	local gui, l = label(self.folder, UDim2.fromOffset(if boosted then 110 else 90, if boosted then 34 else 28), offset, "+" .. tostring(amount), if boosted then Palette.Leaf:Lerp(Palette.Ivory, 0.2) else Palette.Amber)
	gui.Adornee = head
	if self:_reduced() then
		tween(l, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
	else
		tween(gui, 0.8, { StudsOffsetWorldSpace = offset + Vector3.new(0, 2.5, 0) }, Enum.EasingStyle.Quart)
		tween(l, 0.8, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	expire(gui, 0.85)
end

------------------------------------------------------------------ quest guide

function Effects:_destroyGuide()
	local g = self.guide
	if not g then
		return
	end
	self.guide = nil :: any
	g.conn:Disconnect()
	g.folder:Destroy()
	g.a0:Destroy() -- lives on the character, not in the folder
end

-- Soft bobbing amber chevron over a world target plus a faint beam from the character.
-- nil hides it.
function Effects:setGuide(target: Vector3?, text: string?)
	if target == nil then
		self:_destroyGuide()
		return
	end
	local g: any = self.guide
	if not g then
		local folder = Instance.new("Folder")
		folder.Name = "QuestGuide"
		folder.Parent = self.folder
		local anchor = localPart(folder, Enum.PartType.Block, Vector3.one * 0.2, CFrame.new(target), Palette.Amber)
		anchor.Name = "GuideAnchor"
		anchor.Transparency = 1
		-- Two stacked down-pointing chevrons (each two angled bars).
		local arms = {}
		for row = 0, 1 do
			for side = -1, 1, 2 do
				local p = localPart(folder, Enum.PartType.Block, Vector3.new(0.5, 2, 0.5) * (1 - row * 0.25), CFrame.new(), if row == 0 then Palette.Amber else Palette.Amber:Lerp(Palette.Ivory, 0.35))
				p.Transparency = if row == 0 then 0.05 else 0.4
				table.insert(arms, { part = p, offset = CFrame.new(side * 0.6 * (1 - row * 0.25), 0.7 + row * 1.25, 0) * CFrame.Angles(0, 0, -side * math.rad(40)) }) -- bottoms meet: "V"
			end
		end
		local disc = localPart(folder, Enum.PartType.Cylinder, Vector3.new(0.08, 5, 5), CFrame.new(), Palette.Amber)
		disc.Name = "GuideDisc"
		disc.Transparency = 0.8
		local a1 = Instance.new("Attachment")
		a1.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Palette.Ivory, Palette.Amber)
		beam.Transparency = ns({ { 0, 1 }, { 0.12, 0.7 }, { 1, 0.8 } })
		beam.LightEmission = 0
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Width0 = 0.25
		beam.Width1 = 0.35
		beam.Segments = 10
		beam.Parent = folder
		local _, l = label(anchor, UDim2.fromOffset(200, 34), Vector3.new(0, 4.6, 0), "", Palette.Ivory)
		g = { folder = folder, anchor = anchor, arms = arms, disc = disc, a0 = Instance.new("Attachment"), beam = beam, label = l, target = target }
		local start = os.clock()
		g.conn = RunService.RenderStepped:Connect(function()
			local reduced = self:_reduced()
			local t = os.clock() - start
			local bob = if reduced then 0 else math.sin(t * 2.2) * 0.4
			local pos = g.target + Vector3.new(0, 2.6 + bob, 0)
			local camera = Workspace.CurrentCamera
			local look = if camera then Vector3.new(camera.CFrame.Position.X, pos.Y, camera.CFrame.Position.Z) else pos + Vector3.zAxis
			local cf = if (look - pos).Magnitude > 0.1 then CFrame.lookAt(pos, look) else CFrame.new(pos)
			g.anchor.CFrame = CFrame.new(pos)
			for _, arm in g.arms do
				arm.part.CFrame = cf * arm.offset
			end
			local ground = g.target - Vector3.new(0, 1.9, 0)
			local pulse = if reduced then 1 else 1 + math.sin(t * 2.2) * 0.08
			g.disc.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2)
			g.disc.Size = Vector3.new(0.08, 5 * pulse, 5 * pulse)
		end)
		self.guide = g
	end
	g.target = target
	local root = rootPart()
	if root and g.a0.Parent ~= root then
		-- Recreate on the new character after a respawn; never leave one behind.
		g.a0:Destroy()
		local a0 = Instance.new("Attachment")
		a0.Name = "SnackGuideAttachment"
		a0.Parent = root
		g.a0 = a0
	end
	g.beam.Attachment0 = g.a0
	g.beam.Enabled = root ~= nil and not self:isPlaying()
	local dist = if root then math.floor((root.Position - target).Magnitude) else 0
	g.label.Text = string.format("%s  %d m", softCase(text or "Go here"), dist)
end

------------------------------------------------------------------ flight

-- Food arcs from the player to the landing spot. Camera follows on manual throws; the
-- post-landing orbit is reserved for milestones.
function Effects:_flight(payload: any, follow: boolean)
	local seq = self:_begin(follow)
	local root = rootPart()
	local rel: any = self.lastRelease
	local startPos = if rel and os.clock() - rel.time < 1.5 then rel.pos elseif root then root.Position + Vector3.new(0, 3, 0) else Vector3.new(0, 5, -10)
	self.lastRelease = nil
	local distance = math.min(payload.distance or 0, BiomeConfig.SpaceDistance)
	local landing = Vector3.new(payload.lateral or 0, 0.6, distance)
	local ground = Vector3.new(landing.X, 0, landing.Z)
	local duration, height = arcFor(distance)
	local food: Part = self:_foodPart(self.folder, payload.foodId, true)
	food.CFrame = CFrame.new(startPos) -- before the first render, so the trail starts here
	local trail = food:FindFirstChildOfClass("Trail")
	if trail then
		local speed = (landing - startPos).Magnitude / duration
		trail.Lifetime = math.clamp(30 / math.max(speed, 1), 0.08, 0.3)
	end
	local shadow = localPart(self.folder, Enum.PartType.Cylinder, Vector3.new(0.06, 2.4, 2.4), CFrame.new(), Palette.Charcoal)
	shadow.Name = "SnackShadow"
	shadow.Transparency = 1
	table.insert(seq.cleanups, function()
		food:Destroy()
		shadow:Destroy()
	end)
	local camera = if follow then takeCamera(seq) else nil
	if camera then
		self.hud:setSkipOnly(true)
		table.insert(seq.cleanups, function()
			self.hud:setSkipOnly(false)
		end)
	end
	local start = os.clock()
	local landed = false
	local stopFlight = bind(seq, function(dt)
		local t = math.min((os.clock() - start) / duration, 1)
		local pos = arcPoint(startPos, landing, height, t)
		food.CFrame = CFrame.new(pos) * CFrame.Angles(t * 25, t * 17, 0)
		-- A soft ground shadow makes the arc readable from any angle.
		local alt = math.max(pos.Y, 0)
		local d = 2.6 / (1 + alt / 25)
		shadow.Size = Vector3.new(0.06, d, d)
		shadow.CFrame = CFrame.new(pos.X, 0.05, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
		shadow.Transparency = 0.6 + 0.4 * math.clamp(alt / 80, 0, 1)
		if camera then
			local behind = pos + Vector3.new(0, 14 + height * 0.1, -36)
			camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(behind, pos), 1 - math.exp(-dt * 14))
		end
		if t >= 1 and not landed then
			landed = true
		end
	end)
	task.spawn(function()
		while not landed and not seq.cancelled do
			task.wait()
		end
		stopFlight()
		food.Transparency = 1
		shadow.Transparency = 1
		self:_land(ground, payload)
		if not seq.cancelled and camera then
			local target = ground + Vector3.new(0, 3, 0)
			if self:_isMilestone(payload) then
				local orbitStart = os.clock()
				bind(seq, function(dt)
					local a = (os.clock() - orbitStart) * 0.6
					local goal = CFrame.lookAt(target + Vector3.new(math.sin(a) * 22, 10, -math.cos(a) * 22), target)
					camera.CFrame = camera.CFrame:Lerp(goal, 1 - math.exp(-dt * 8))
				end)
				waitFor(seq, 1.4)
			else
				-- Calm catch: ease to a resting view of the landing, then hand back.
				bind(seq, function(dt)
					local goal = CFrame.lookAt(target + Vector3.new(0, 11, -26), target)
					camera.CFrame = camera.CFrame:Lerp(goal, 1 - math.exp(-dt * 6))
				end)
				waitFor(seq, 0.7)
			end
		end
		self:_finish(seq)
	end)
end

------------------------------------------------------------------ cutscenes

-- One emitter instead of hundreds of parts: stars on a big sphere plus a soft nebula.
local function sky(parent: Instance, center: Vector3, kind: string)
	local shell = localPart(parent, Enum.PartType.Ball, Vector3.one * 1500, CFrame.new(center), Palette.Charcoal)
	shell.Name = "SkyShell"
	shell.Transparency = 1
	local function layer(count: number, configure: (ParticleEmitter) -> ())
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.Speed = NumberRange.new(0)
		e.Lifetime = NumberRange.new(30)
		e.LockedToPart = true
		e.LightInfluence = 0
		configure(e)
		e.Parent = shell
		e:Emit(count)
	end
	layer(170, function(e)
		e.Texture = TEX_SPARK
		e.Color = ColorSequence.new(Palette.Ivory, Color3.fromRGB(200, 225, 230))
		e.LightEmission = 1
		e.Size = ns({ { 0, 5, 2.5 }, { 1, 5, 2.5 } })
		e.Transparency = ns({ { 0, 0.25, 0.25 }, { 1, 0.25, 0.25 } })
		e.RotSpeed = NumberRange.new(-15, 15)
	end)
	local tints: { Color3 } = if kind == "moon" then { Palette.Teal, Color3.fromRGB(90, 100, 150) } else { Palette.Teal, Palette.Terracotta }
	for _, tint in tints do
		layer(6, function(e)
			e.Texture = TEX_SOFT
			e.Color = ColorSequence.new(tint)
			e.LightEmission = 0.5
			e.Size = ns({ { 0, 100 }, { 1, 100 } })
			e.Transparency = ns({ { 0, 0.82, 0.06 }, { 1, 0.82, 0.06 } })
			e.Rotation = NumberRange.new(0, 360)
		end)
	end
end

-- A flat disc lying on a sphere's surface (cylinders are X-aligned).
local function surfaceDisc(parent: Instance, center: Vector3, radius: number, dir: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material): Part
	local side = dir:Cross(if math.abs(dir.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis).Unit
	local pos = center + dir * radius
	return localPart(parent, Enum.PartType.Cylinder, Vector3.new(thickness, diameter, diameter), CFrame.fromMatrix(pos, dir, side), color, material)
end

local function buildMoonSet(scene: Instance, base: Vector3): Vector3
	local moonColor = Color3.fromRGB(206, 200, 188)
	local moon = localPart(scene, Enum.PartType.Ball, Vector3.one * 900, CFrame.new(base - Vector3.new(0, 450, 0)), moonColor, Enum.Material.Slate)
	local rng = Random.new(3)
	for _ = 1, 14 do
		local offset = Vector3.new(rng:NextNumber(-140, 140), 0, rng:NextNumber(-60, 220))
		if offset.Magnitude > 18 then
			local dir = (base + offset - moon.Position).Unit
			local d = rng:NextNumber(10, 34)
			surfaceDisc(scene, moon.Position, 449.6, dir, d * 1.25, 1.2, moonColor:Lerp(Palette.Ivory, 0.25), Enum.Material.Slate)
			surfaceDisc(scene, moon.Position, 449.9, dir, d, 1.2, moonColor:Lerp(Palette.Charcoal, 0.25), Enum.Material.Slate)
		end
	end
	-- Earth: muted ocean, leafy continents and a faint atmosphere shell.
	local earthPos = base + Vector3.new(-260, 150, 560)
	localPart(scene, Enum.PartType.Ball, Vector3.one * 160, CFrame.new(earthPos), Color3.fromRGB(70, 128, 160), Enum.Material.SmoothPlastic)
	for _, o in { Vector3.new(30, 25, -45), Vector3.new(-40, -10, -50), Vector3.new(10, -45, -40) } do
		localPart(scene, Enum.PartType.Ball, Vector3.one * 70, CFrame.new(earthPos + o * 0.9), Palette.Leaf, Enum.Material.Grass)
	end
	localPart(scene, Enum.PartType.Ball, Vector3.one * 34, CFrame.new(earthPos + Vector3.new(-20, 60, -45)), Palette.Ivory, Enum.Material.SmoothPlastic)
	local air = localPart(scene, Enum.PartType.Ball, Vector3.one * 176, CFrame.new(earthPos), Palette.Teal, Enum.Material.ForceField)
	air.Transparency = 0.3
	return base
end

local function buildSpaceSet(scene: Instance, base: Vector3): Vector3
	-- Terracotta planet with a two-band ring and a soft teal atmosphere.
	local planetPos = base + Vector3.new(160, -260, 520)
	localPart(scene, Enum.PartType.Ball, Vector3.one * 420, CFrame.new(planetPos), Palette.Terracotta, Enum.Material.SmoothPlastic)
	localPart(scene, Enum.PartType.Ball, Vector3.one * 300, CFrame.new(planetPos + Vector3.new(-30, 50, -70)), Palette.Terracotta:Lerp(Palette.Amber, 0.3), Enum.Material.SmoothPlastic)
	local air = localPart(scene, Enum.PartType.Ball, Vector3.one * 440, CFrame.new(planetPos), Palette.Teal, Enum.Material.ForceField)
	air.Transparency = 0.35
	local tilt = CFrame.new(planetPos) * CFrame.Angles(0.35, 0.2, 0.18)
	for band = 0, 1 do
		local r = if band == 0 then 280 else 345
		local w = if band == 0 then 40 else 60
		local color = if band == 0 then Palette.Ivory else Palette.Amber
		local segments = 22
		for i = 1, segments do
			local a = (i / segments) * math.pi * 2
			local p = localPart(scene, Enum.PartType.Block, Vector3.new(2 * math.pi * r / segments * 1.04, 1.5, w), tilt * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0), color, Enum.Material.Glass)
			p.Transparency = if band == 0 then 0.55 else 0.4
		end
	end
	localPart(scene, Enum.PartType.Ball, Vector3.one * 46, CFrame.new(base + Vector3.new(-220, 120, 420)), Palette.Ivory, Enum.Material.Slate)
	-- Drifting rocks and the little asteroid the pet lands on.
	local rng = Random.new(11)
	for _ = 1, 12 do
		local p = base + Vector3.new(rng:NextNumber(-150, 150), rng:NextNumber(-50, 90), rng:NextNumber(-20, 220))
		if (p - base).Magnitude > 30 then
			local s = rng:NextNumber(3, 13)
			localPart(scene, Enum.PartType.Block, Vector3.new(s, s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.7, 1.2)), CFrame.new(p) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), Palette.Stone, Enum.Material.Slate)
		end
	end
	localPart(scene, Enum.PartType.Cylinder, Vector3.new(5, 18, 18), CFrame.new(base - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Palette.Stone, Enum.Material.Slate)
	localPart(scene, Enum.PartType.Cylinder, Vector3.new(4, 12, 12), CFrame.new(base - Vector3.new(0, 5.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Palette.Stone:Lerp(Palette.Charcoal, 0.3), Enum.Material.Slate)
	return base
end

-- Returns true if the pet reveal was reached (false when skipped earlier).
function Effects:_cutscene(payload: any): boolean
	local seq = self:_begin(true)
	local kind = payload.cutscene
	local camera = takeCamera(seq)
	if not camera then
		self:_finish(seq)
		return false
	end
	local scene = Instance.new("Folder")
	scene.Name = "Cutscene"
	scene.Parent = self.folder
	table.insert(seq.cleanups, function()
		scene:Destroy()
	end)
	-- Night sky + soft tint and clear air, restored on cleanup.
	local prevClock, prevBright, prevAmbient = Lighting.ClockTime, Lighting.Brightness, Lighting.OutdoorAmbient
	local atmo: Atmosphere? = self.atmosphere
	local prevDensity = if atmo then atmo.Density else 0
	local fx = Instance.new("ColorCorrectionEffect")
	fx.Name = "SnackCutsceneTint"
	fx.TintColor = if kind == "moon" then Color3.fromRGB(232, 232, 242) else Color3.fromRGB(236, 226, 238)
	fx.Saturation = 0.1
	fx.Contrast = 0.05
	fx.Parent = Lighting
	table.insert(seq.cleanups, function()
		Lighting.ClockTime = prevClock
		Lighting.Brightness = prevBright
		Lighting.OutdoorAmbient = prevAmbient
		if atmo then
			atmo.Density = prevDensity
		end
		fx:Destroy()
	end)
	self.hud:setCutscene(true, if kind == "moon" then "To the Moon" else "Into space", metres(payload.distance or 0))
	table.insert(seq.cleanups, function()
		self.hud:setCutscene(false, "", "")
	end)

	-- Phase 1: launch from the throw line into the sky.
	local launchFrom = Vector3.new(0, 6, 0)
	local launchTo = Vector3.new(0, 900, 1400)
	self:_dust(Vector3.new(0, 0, -4), 1.6, Palette.Sand)
	local food: Part = self:_foodPart(scene, payload.foodId, true)
	food.Size = food.Size * 2
	food.CFrame = CFrame.new(launchFrom)
	local foodTrail = food:FindFirstChildOfClass("Trail")
	local t0 = os.clock()
	local seed = math.random() * 100
	local stopLaunch = bind(seq, function()
		local reduced = self:_reduced()
		local t = math.min((os.clock() - t0) / 1.8, 1)
		local pos = launchFrom:Lerp(launchTo, t * t)
		food.CFrame = CFrame.new(pos) * CFrame.Angles(t * 30, 0, t * 20)
		local shake = if reduced then Vector3.zero else noise3(t * 14, seed) * 0.9 * (1 - t)
		local eye = Vector3.new(30, 25, -60):Lerp(pos + Vector3.new(0, -20, -60), t * 0.85)
		camera.CFrame = CFrame.lookAt(eye, pos) * CFrame.new(shake)
		camera.FieldOfView = if reduced then Effects.BaseFov else Effects.BaseFov + t * 15
		Lighting.ClockTime = prevClock + (24 - prevClock) * math.min(t * 1.2, 1)
	end)
	if not waitFor(seq, 1.8) then
		return false
	end
	stopLaunch()

	-- Phase 2: build the celestial set far above the map.
	local base = Vector3.new(0, 6000, 9000)
	Lighting.ClockTime = 0
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 118, 128)
	if atmo then
		atmo.Density = 0
	end
	sky(scene, base, kind)
	local petPos = if kind == "moon" then buildMoonSet(scene, base) else buildSpaceSet(scene, base)
	-- Teleport without drawing a streak across the sky.
	if foodTrail then
		foodTrail.Enabled = false
		task.delay(0.05, function()
			if foodTrail.Parent then
				foodTrail:Clear()
				foodTrail.Enabled = true
			end
		end)
	end
	food.CFrame = CFrame.new(petPos + Vector3.new(0, 80, -120))
	tween(food, 0.6, { CFrame = CFrame.new(petPos + Vector3.new(0, 1.5, 0)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local orbitStart = os.clock()
	bind(seq, function()
		local speed = if self:_reduced() then 0.2 else 0.45
		local a = (os.clock() - orbitStart) * speed
		local target = petPos + Vector3.new(0, 4, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(a) * 34, 12, -math.cos(a) * 34), target)
		camera.FieldOfView = Effects.BaseFov
	end)
	if not waitFor(seq, 0.65) then
		return false
	end
	food.Transparency = 1
	local dustTint = if kind == "moon" then Color3.fromRGB(206, 200, 188) else Palette.Stone
	self:_dust(petPos, 1.3, dustTint)
	self:_groundRing(petPos, Palette.Ivory:Lerp(rarityColor(payload.rarity), 0.5), 1.2)
	self:_spawnCaughtPet(payload, petPos, scene)
	self:_celebrate(payload, petPos)
	self.hud:setCutscene(true, string.format("%s catch", tostring(payload.rarity or "New")), petTitle(payload.pet))
	if not waitFor(seq, 3) then
		return true
	end
	self:_finish(seq)
	return true
end

------------------------------------------------------------------ entry point

-- Entry point from GameClient for every CatchEffect payload.
function Effects:playCatch(payload: any)
	local settings = self:_settings()
	local showFx = settings.ShowCutscenes ~= false
	-- Auto-throws never take over the camera with a cutscene (they repeat every few seconds).
	if payload.cutscene and showFx and payload.manual ~= true then
		self.hud:toast(if payload.cutscene == "moon" then "Auto-throw reached the Moon" else "Auto-throw reached space", Palette.Teal)
	elseif payload.cutscene and showFx then
		local threshold = settings.AutoSkipRarity or "Off"
		local autoSkip = threshold ~= "Off" and (payload.rarityIndex or 1) < GameConfig.rarityIndex(threshold)
		if autoSkip then
			self.hud:toast(string.format("Cutscene skipped (below %s)", tostring(threshold)), Palette.Teal)
		else
			task.spawn(function()
				local revealed = self:_cutscene(payload)
				if not revealed then
					self:_celebrate(payload, nil)
				end
				self.hud:showCatch(payload)
			end)
			return
		end
	end
	local follow = showFx and not self:_reduced() and payload.manual == true and (payload.distance or 0) > 120 and not self:isPlaying()
	if payload.manual or not self:isPlaying() then
		self:_flight(payload, follow)
	else
		task.delay(0.8, function()
			self:_celebrate(payload, nil)
		end)
	end
	self.hud:showCatch(payload)
end

------------------------------------------------------------------ weather

function Effects:setWeather(w: any)
	if self.weatherPart then
		self.weatherPart:Destroy()
		self.weatherPart = nil :: any
		self.weatherEmitter = nil :: any
	end
	if self.weatherConn then
		self.weatherConn:Disconnect()
		self.weatherConn = nil :: any
	end
	local def = if w and w.active then GameConfig.getWeather(w.id) else nil
	self.weatherColor = if def then def.color else nil
	if not def then
		tween(self.tint, 2, { TintColor = Color3.new(1, 1, 1), Saturation = 0.05, Contrast = 0.03 })
		return
	end
	tween(self.tint, 2, { TintColor = Color3.new(1, 1, 1):Lerp(def.color, 0.15), Saturation = 0.12, Contrast = 0.06 })
	local part = localPart(self.folder, Enum.PartType.Block, Vector3.new(160, 1, 160), CFrame.new(), Color3.new(1, 1, 1))
	part.Transparency = 1
	part.Name = "WeatherEmitter"
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Bottom
	e.LightEmission = 0.15
	e.LightInfluence = 0.6
	e.Lifetime = NumberRange.new(2.5, 3.5)
	e.Transparency = ns({ { 0, 1 }, { 0.1, 0.25 }, { 0.8, 0.4 }, { 1, 1 } })
	local rate = 0
	if def.id == "TitanStorm" then
		e.Color = ColorSequence.new(def.color:Lerp(Palette.Ivory, 0.5), Palette.Ivory)
		rate = 70
		e.Speed = NumberRange.new(40, 60)
		e.Size = ns({ { 0, 0.5 }, { 1, 0.3 } })
		e.Squash = ns({ { 0, 2 }, { 1, 2 } })
	elseif def.id == "FeastFrenzy" then
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Palette.Terracotta),
			ColorSequenceKeypoint.new(0.5, Palette.Amber),
			ColorSequenceKeypoint.new(1, Palette.Cream),
		})
		rate = 40
		e.Speed = NumberRange.new(10, 16)
		e.Size = ns({ { 0, 1 }, { 1, 0.6 } })
		e.RotSpeed = NumberRange.new(-180, 180)
	else
		e.Texture = TEX_SPARK
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Palette.Teal:Lerp(Palette.Ivory, 0.3)),
			ColorSequenceKeypoint.new(0.5, Palette.Leaf:Lerp(Palette.Ivory, 0.3)),
			ColorSequenceKeypoint.new(1, Palette.Amber:Lerp(Palette.Ivory, 0.3)),
		})
		rate = 45
		e.LightEmission = 0.35
		e.Speed = NumberRange.new(5, 10)
		e.Size = ns({ { 0, 0.8 }, { 1, 0 } })
	end
	self.weatherRate = rate
	e.Rate = if self:_reduced() then rate * 0.3 else rate
	e.Parent = part
	self.weatherPart = part
	self.weatherEmitter = e
	self.weatherConn = RunService.Heartbeat:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera and part.Parent then
			part.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
			e.Rate = if self:_reduced() then self.weatherRate * 0.3 else self.weatherRate
		end
	end)
end

------------------------------------------------------------------ ambient

function Effects:startAmbient()
	local bases: { [Model]: CFrame } = {}
	local function track(inst: Instance)
		if inst:IsA("Model") then
			bases[inst] = inst:GetPivot()
		end
	end
	for _, m in CollectionService:GetTagged("PlotPet") do
		track(m)
	end
	table.insert(self.connections, CollectionService:GetInstanceAddedSignal("PlotPet"):Connect(function(inst)
		task.defer(track, inst) -- wait for parts to replicate
	end))
	table.insert(self.connections, CollectionService:GetInstanceRemovedSignal("PlotPet"):Connect(function(inst)
		bases[inst :: Model] = nil
	end))
	local acc = 0
	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 24 then
			return
		end
		acc = 0
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local calm = if self:_reduced() then 0.35 else 1
		for model, base in bases do
			if not model.Parent then
				bases[model] = nil
			elseif (base.Position - camPos).Magnitude < 180 then
				local phase = (base.Position.X + base.Position.Z) * 0.1
				model:PivotTo(base * CFrame.new(0, (math.sin(now * 2 + phase) * 0.35 + 0.35) * calm, 0) * CFrame.Angles(0, math.sin(now * 0.8 + phase) * 0.25 * calm, 0))
			end
		end
		self:_updateAmbience(camPos)
		-- Rainbow material drifts slowly through a softened spectrum.
		local hue = (now * 0.12) % 1
		for _, m in CollectionService:GetTagged("RainbowPet") do
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") and p.Name ~= "Eye" and p.Name ~= "Shine" and p.Name ~= "Nose" and p.Name ~= "Cheek" then
					p.Color = Color3.fromHSV((hue + p.Position.Y * 0.03) % 1, 0.55, 0.95)
				end
			end
		end
	end))
end

-- Atmosphere follows the biome under the camera, blended with the active weather colour.
function Effects:_updateAmbience(camPos: Vector3)
	local a = self.atmosphere
	if not a or self:isPlaying() then
		return
	end
	local color = self.baseAtmosphereColor
	local density = 0.28
	if camPos.Z > 0 then
		local biome = BiomeConfig.biomeAtDistance(camPos.Z)
		color = biome.fogColor
		density = biome.fogDensity
	end
	if self.weatherColor then
		color = color:Lerp(self.weatherColor, 0.3)
		density += 0.04
	end
	a.Color = a.Color:Lerp(color, 0.08)
	a.Density = a.Density + (density - a.Density) * 0.08
end

function Effects:destroy()
	self.alive = false
	self:skip()
	self:_endCharge(false)
	self:_destroyGuide()
	local stops = {}
	for stop in self.anims do
		table.insert(stops, stop)
	end
	for _, stop in stops do
		stop()
	end
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	if self.weatherConn then
		self.weatherConn:Disconnect()
		self.weatherConn = nil :: any
	end
	self.folder:Destroy()
	self.tint:Destroy()
	self.bloom:Destroy()
	self.sunRays:Destroy()
end

return Effects
