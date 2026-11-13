--!strict
-- Client-only visuals: food flight + camera follow, skippable space/moon cutscenes,
-- weather atmosphere and ambient pet animation. Everything created here is local and
-- tracked so it can be cleaned up on skip/finish.

local CollectionService = game:GetService("CollectionService")
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

-- `blocking` sequences own the camera (followed throws, cutscenes): input such as E or
-- Space skips them. Background flights (auto-throws, short throws) are non-blocking.
type Sequence = { cancelled: boolean, cleanups: { () -> () }, finished: boolean, blocking: boolean }

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
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
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

function Effects.new(hud: any, getState: () -> any)
	local self = setmetatable({}, Effects) :: any
	self.hud = hud
	self.getState = getState
	self.seq = nil :: Sequence?
	self.connections = {} :: { RBXScriptConnection }
	self.folder = Instance.new("Folder")
	self.folder.Name = "SnackLocalFX"
	self.folder.Parent = Workspace

	self.tint = Instance.new("ColorCorrectionEffect")
	self.tint.Name = "SnackWeatherTint"
	self.tint.Parent = Lighting
	self.bloom = Instance.new("BloomEffect")
	self.bloom.Name = "SnackBloom"
	self.bloom.Intensity = 0.6
	self.bloom.Size = 24
	self.bloom.Threshold = 1.6
	self.bloom.Parent = Lighting
	self.atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not self.atmosphere then
		local a = Instance.new("Atmosphere")
		a.Density = 0.28
		a.Offset = 0.2
		a.Haze = 1.2
		a.Glare = 0.3
		a.Color = Color3.fromRGB(200, 220, 255)
		a.Decay = Color3.fromRGB(120, 140, 200)
		a.Parent = Lighting
		self.atmosphere = a
	end
	self.baseAtmosphereColor = self.atmosphere.Color
	self.weatherPart = nil :: Part?
	self.weatherConn = nil :: RBXScriptConnection?
	self.weatherColor = nil :: Color3?
	self.sunRays = Instance.new("SunRaysEffect")
	self.sunRays.Name = "SnackSunRays"
	self.sunRays.Intensity = 0.06
	self.sunRays.Spread = 0.6
	self.sunRays.Parent = Lighting
	self.guide = nil :: any
	self.held = nil :: Part?
	self.bestMarker = nil :: Model?
	self.bestMarkerDistance = 0
	return self
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
local function wait(seq: Sequence, t: number): boolean
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

------------------------------------------------------------------ throw visuals

function Effects:_foodPart(parent: Instance, foodId: string?): Part
	local food = FoodConfig.get(foodId) or FoodConfig.Foods[1]
	local shape = if food.shape == "Block" then Enum.PartType.Block elseif food.shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Ball
	local size = if shape == Enum.PartType.Cylinder then Vector3.new(2.6, 1.3, 1.3) else Vector3.new(1.6, 1.6, 1.6)
	local p = localPart(parent, shape, size, CFrame.new(), food.color, Enum.Material.SmoothPlastic)
	p.Name = "FlyingFood"
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.LightEmission = 0.8
	trail.Color = ColorSequence.new(food.color, Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = p
	local light = Instance.new("PointLight")
	light.Color = food.color
	light.Range = 10
	light.Parent = p
	return p
end

function Effects:_burst(position: Vector3, color: Color3, scale: number)
	local ring = localPart(self.folder, Enum.PartType.Cylinder, Vector3.new(0.3, 2, 2), CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon)
	tween(ring, 0.6, { Size = Vector3.new(0.3, 26 * scale, 26 * scale), Transparency = 1 })
	local emitterPart = localPart(self.folder, Enum.PartType.Block, Vector3.one, CFrame.new(position + Vector3.new(0, 1, 0)), color)
	emitterPart.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.Speed = NumberRange.new(15, 35)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Size = NumberSequence.new(1.2 * scale, 0)
	e.LightEmission = 0.7
	e.Rate = 0
	e.Parent = emitterPart
	e:Emit(45)
	task.delay(1.6, function()
		ring:Destroy()
		emitterPart:Destroy()
	end)
end

function Effects:_spawnCaughtPet(payload: any, position: Vector3): Model?
	local rec = payload.pet
	if type(rec) ~= "table" then
		return nil
	end
	local model, height = PetModelBuilder.build(rec.species, rec.material, rec.size, CFrame.new(position) * CFrame.Angles(0, math.pi, 0))
	model.Parent = self.folder
	local primary = model.PrimaryPart
	if primary then
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 40)
		gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextStrokeTransparency = 0
		l.TextColor3 = (GameConfig.RarityColors :: any)[payload.rarity] or Color3.new(1, 1, 1)
		local pet = PetConfig.get(rec.species)
		l.Text = (payload.rarity or "") .. "! " .. (if pet then pet.name else "")
		l.Parent = gui
		gui.Parent = primary
	end
	-- Pop-in bounce
	local base = model:GetPivot()
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if not model.Parent or t > 0.8 then
			conn:Disconnect()
			if model.Parent then
				model:PivotTo(base)
			end
			return
		end
		local y = math.abs(math.sin(t * 8)) * (0.8 - t) * 6
		model:PivotTo(base * CFrame.new(0, y, 0) * CFrame.Angles(0, t * 8, 0))
	end)
	task.delay(4, function()
		if model.Parent then
			model:Destroy()
		end
	end)
	return model
end

-- Glowing beacon + distance label where a snack landed (stays a few seconds).
function Effects:_landingBeacon(position: Vector3, payload: any)
	local color = (GameConfig.RarityColors :: any)[payload.rarity] or Color3.new(1, 1, 1)
	local beam = localPart(self.folder, Enum.PartType.Cylinder, Vector3.new(90, 2.2, 2.2), CFrame.new(position + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon)
	beam.Transparency = 0.35
	beam.Name = "LandingBeacon"
	local ring = localPart(self.folder, Enum.PartType.Cylinder, Vector3.new(0.2, 9, 9), CFrame.new(position + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon)
	ring.Transparency = 0.3
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 4000
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextStrokeTransparency = 0
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = string.format("%dm%s", math.floor(payload.distance or 0), if payload.sweetSpot then " SWEET!" else "")
	l.Parent = gui
	gui.Parent = ring
	tween(beam, 3.5, { Transparency = 1, Size = Vector3.new(90, 0.4, 0.4) }, Enum.EasingStyle.Sine)
	task.delay(3.6, function()
		beam:Destroy()
		ring:Destroy()
	end)
end

-- Persistent flag at the player's best distance.
function Effects:setBestDistance(distance: number)
	if distance <= 0 or math.abs(distance - self.bestMarkerDistance) < 1 then
		return
	end
	self.bestMarkerDistance = distance
	if self.bestMarker then
		self.bestMarker:Destroy()
	end
	local shown = math.min(distance, BiomeConfig.SpaceDistance - 5)
	local model = Instance.new("Model")
	model.Name = "BestThrowFlag"
	local base = Vector3.new(BiomeConfig.Width / 2 - 30, 0, shown)
	localPart(model, Enum.PartType.Block, Vector3.new(0.6, 18, 0.6), CFrame.new(base + Vector3.new(0, 9, 0)), Color3.fromRGB(240, 240, 240), Enum.Material.Metal)
	local flag = localPart(model, Enum.PartType.Block, Vector3.new(0.3, 4, 7), CFrame.new(base + Vector3.new(0, 16, -3.6)), Color3.fromRGB(255, 200, 40), Enum.Material.Neon)
	localPart(model, Enum.PartType.Block, Vector3.new(BiomeConfig.Width - 20, 0.15, 0.8), CFrame.new(0, 0.12, shown), Color3.fromRGB(255, 200, 40), Enum.Material.Neon).Transparency = 0.4
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 600
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextStrokeTransparency = 0
	l.TextColor3 = Color3.fromRGB(255, 220, 80)
	l.Text = "YOUR BEST " .. math.floor(distance) .. "m"
	l.Parent = gui
	gui.Parent = flag
	model.Parent = self.folder
	self.bestMarker = model
end

-- The snack grows in the player's hand while charging (local only).
function Effects:setCharging(charge: number?, foodId: string?)
	if charge == nil then
		if self.held then
			self.held:Destroy()
			self.held = nil :: any
		end
		return
	end
	local character = Players.LocalPlayer.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	if not self.held then
		self.held = self:_foodPart(self.folder, foodId)
	end
	local held = self.held :: Part
	local grow = 0.7 + charge * 0.6
	held.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - 0.4, 0) * CFrame.Angles(os.clock() * 4, 0, 0)
	local base = if held.Shape == Enum.PartType.Cylinder then Vector3.new(2.6, 1.3, 1.3) else Vector3.new(1.6, 1.6, 1.6)
	held.Size = base * grow
	local light = held:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = if GameMath.isSweetSpot(charge) then 4 else 1
		light.Range = if GameMath.isSweetSpot(charge) then 16 else 8
	end
end

-- Brief FOV kick + shake when a throw is released.
function Effects:punch(strength: number)
	local camera = Workspace.CurrentCamera
	if not camera or self:isPlaying() then
		return
	end
	local fov = Effects.BaseFov
	camera.FieldOfView = fov + 6 * strength
	tween(camera, 0.35, { FieldOfView = fov }, Enum.EasingStyle.Quad)
	local humanoid = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and strength >= 1 then
		local start = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t > 0.25 or not humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
				conn:Disconnect()
				return
			end
			local m = (0.25 - t) * 1.6 * strength
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * m
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
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(110, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(math.random(-15, 15) / 10, 2.5, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextStrokeTransparency = 0
	l.TextColor3 = if boosted then Color3.fromRGB(255, 120, 200) else Color3.fromRGB(255, 120, 120)
	l.Text = "+" .. tostring(amount) .. " 💪"
	l.Parent = gui
	gui.Adornee = head
	gui.Parent = self.folder
	tween(gui, 0.8, { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) })
	tween(l, 0.8, { TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(0.85, function()
		gui:Destroy()
	end)
end

-- Guide beam from the character to a world target (quest focus). nil hides it.
function Effects:setGuide(target: Vector3?, label: string?)
	local g: any = self.guide
	if target == nil then
		if g then
			g.folder:Destroy()
			g.a0:Destroy() -- lives on the character, not in the folder
			self.guide = nil :: any
		end
		return
	end
	if not g then
		local folder = Instance.new("Folder")
		folder.Name = "QuestGuide"
		folder.Parent = self.folder
		local anchor = localPart(folder, Enum.PartType.Ball, Vector3.one * 2, CFrame.new(target), Color3.fromRGB(255, 230, 90), Enum.Material.Neon)
		anchor.Transparency = 0.2
		local a1 = Instance.new("Attachment")
		a1.Parent = anchor
		local a0 = Instance.new("Attachment")
		a0.Name = "GuideAttachment"
		local beam = Instance.new("Beam")
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 160, 60))
		beam.Transparency = NumberSequence.new(0.2, 0.6)
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Width0 = 0.6
		beam.Width1 = 1.4
		beam.Segments = 20
		beam.CurveSize0 = 0
		beam.Parent = folder
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(200, 46)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextStrokeTransparency = 0
		l.TextColor3 = Color3.fromRGB(255, 230, 90)
		l.Parent = gui
		gui.Parent = anchor
		g = { folder = folder, anchor = anchor, a0 = a0, beam = beam, label = l, target = target }
		self.guide = g
	end
	g.target = target
	g.anchor.CFrame = CFrame.new(target + Vector3.new(0, 3 + math.sin(os.clock() * 3) * 0.6, 0))
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and g.a0.Parent ~= root then
		-- The old attachment is destroyed with the previous character after a respawn.
		local moved = pcall(function()
			g.a0.Parent = root
		end)
		if not moved then
			g.a0 = Instance.new("Attachment")
			g.a0.Name = "GuideAttachment"
			g.a0.Parent = root
		end
	end
	g.beam.Attachment0 = g.a0
	g.beam.Enabled = root ~= nil and not self:isPlaying()
	local dist = if root and root:IsA("BasePart") then math.floor((root.Position - target).Magnitude) else 0
	g.label.Text = string.format("%s  %dm", label or "GO", dist)
end

-- Food arcs from the player to the landing spot. Camera follows on manual throws.
function Effects:_flight(payload: any, follow: boolean)
	local seq = self:_begin(follow)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local startPos = if root then root.Position + Vector3.new(0, 3, 0) else Vector3.new(0, 5, -10)
	local distance = math.min(payload.distance or 0, BiomeConfig.SpaceDistance)
	local landing = Vector3.new(payload.lateral or 0, 0.6, distance)
	local duration = math.clamp(0.8 + distance / 700, 0.8, 3.2)
	local biome = BiomeConfig.biomeAtDistance(distance)
	local height = math.clamp(distance * 0.28 / biome.gravity, 12, 450)
	local food = self:_foodPart(self.folder, payload.foodId)
	table.insert(seq.cleanups, function()
		food:Destroy()
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
	local stopFlight = bind(seq, function()
		local t = math.min((os.clock() - start) / duration, 1)
		local pos = startPos:Lerp(landing, t) + Vector3.new(0, 4 * height * t * (1 - t), 0)
		food.CFrame = CFrame.new(pos) * CFrame.Angles(t * 25, t * 17, 0)
		if camera then
			local behind = pos + Vector3.new(0, 14 + height * 0.1, -36)
			camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(behind, pos), 0.25)
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
		local color = (FoodConfig.get(payload.foodId) or FoodConfig.Foods[1]).color
		self:_burst(landing, color, if payload.rarityIndex and payload.rarityIndex >= 5 then 2 else 1)
		self:_spawnCaughtPet(payload, landing)
		self:_landingBeacon(landing, payload)
		if not seq.cancelled then
			food.Transparency = 1
			if camera then
				local orbitStart = os.clock()
				bind(seq, function()
					local a = (os.clock() - orbitStart) * 0.6
					local target = landing + Vector3.new(0, 3, 0)
					camera.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(a) * 22, 10, -math.cos(a) * 22), target)
				end)
				wait(seq, 1.3)
			end
		end
		self:_finish(seq)
	end)
end

------------------------------------------------------------------ cutscenes

local function starField(parent: Instance, center: Vector3, radius: number, count: number)
	local rng = Random.new(7)
	for _ = 1, count do
		local dir = rng:NextUnitVector()
		localPart(parent, Enum.PartType.Ball, Vector3.one * rng:NextNumber(1.5, 5), CFrame.new(center + dir * radius), Color3.fromHSV(rng:NextNumber(0.5, 0.75), rng:NextNumber(0, 0.4), 1), Enum.Material.Neon)
	end
end

function Effects:_cutscene(payload: any)
	local seq = self:_begin(true)
	local kind = payload.cutscene
	local camera = takeCamera(seq)
	if not camera then
		self:_finish(seq)
		self.hud:showCatch(payload)
		return
	end
	local scene = Instance.new("Folder")
	scene.Name = "Cutscene"
	scene.Parent = self.folder
	table.insert(seq.cleanups, function()
		scene:Destroy()
	end)
	-- Night sky (default skybox shows stars at night) + tint, restored on cleanup.
	local prevClock, prevBright = Lighting.ClockTime, Lighting.Brightness
	local fx = Instance.new("ColorCorrectionEffect")
	fx.TintColor = if kind == "moon" then Color3.fromRGB(210, 215, 255) else Color3.fromRGB(200, 170, 255)
	fx.Saturation = 0.25
	fx.Parent = Lighting
	table.insert(seq.cleanups, function()
		Lighting.ClockTime = prevClock
		Lighting.Brightness = prevBright
		fx:Destroy()
	end)
	self.hud:setCutscene(true, if kind == "moon" then "TO THE MOON!" else "INTO SPACE!", string.format("%sm throw!", tostring(math.floor(payload.distance or 0))))
	table.insert(seq.cleanups, function()
		self.hud:setCutscene(false, "", "")
	end)

	-- Phase 1: launch from the throw line into the sky.
	local food: Part = self:_foodPart(scene, payload.foodId)
	food.Size = food.Size * 2
	local launchFrom = Vector3.new(0, 6, 0)
	local launchTo = Vector3.new(0, 900, 1400)
	local t0 = os.clock()
	local stopLaunch = bind(seq, function()
		local t = math.min((os.clock() - t0) / 1.8, 1)
		local pos = launchFrom:Lerp(launchTo, t * t)
		food.CFrame = CFrame.new(pos) * CFrame.Angles(t * 30, 0, t * 20)
		camera.CFrame = CFrame.lookAt(Vector3.new(30, 25, -60):Lerp(pos + Vector3.new(0, -20, -60), t * 0.85), pos)
		camera.FieldOfView = 70 + t * 20
		Lighting.ClockTime = prevClock + (24 - prevClock) * math.min(t * 1.2, 1)
	end)
	if not wait(seq, 1.8) then
		return
	end
	stopLaunch()

	-- Phase 2: build the celestial set far above the map.
	local base = Vector3.new(0, 6000, 9000)
	Lighting.ClockTime = 0
	starField(scene, base, 700, 140)
	local petPos: Vector3
	if kind == "moon" then
		local moon = localPart(scene, Enum.PartType.Ball, Vector3.one * 900, CFrame.new(base - Vector3.new(0, 452, 0)), Color3.fromRGB(190, 190, 200), Enum.Material.Slate)
		local rng = Random.new(3)
		for _ = 1, 26 do
			local offset = Vector3.new(rng:NextNumber(-120, 120), 0, rng:NextNumber(-120, 120))
			local dir = (base + offset - moon.Position).Unit
			localPart(scene, Enum.PartType.Ball, Vector3.new(rng:NextNumber(8, 30), 3, rng:NextNumber(8, 30)), CFrame.lookAt(moon.Position + dir * 449, moon.Position + dir * 500) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(140, 140, 155), Enum.Material.Slate)
		end
		local earth = localPart(scene, Enum.PartType.Ball, Vector3.one * 160, CFrame.new(base + Vector3.new(-260, 140, 520)), Color3.fromRGB(60, 120, 255), Enum.Material.SmoothPlastic)
		localPart(scene, Enum.PartType.Ball, Vector3.new(80, 60, 90), CFrame.new(earth.Position + Vector3.new(30, 20, -50)), Color3.fromRGB(80, 200, 90), Enum.Material.Grass)
		petPos = base + Vector3.new(0, 0, 0)
	else
		local planet = localPart(scene, Enum.PartType.Ball, Vector3.one * 420, CFrame.new(base + Vector3.new(120, -300, 380)), Color3.fromRGB(140, 80, 255), Enum.Material.SmoothPlastic)
		localPart(scene, Enum.PartType.Cylinder, Vector3.new(4, 700, 700), CFrame.new(planet.Position) * CFrame.Angles(0.3, 0, math.pi / 2 + 0.25), Color3.fromRGB(255, 200, 255), Enum.Material.Neon).Transparency = 0.55
		local rng = Random.new(11)
		for _ = 1, 18 do
			local p = base + Vector3.new(rng:NextNumber(-140, 140), rng:NextNumber(-60, 80), rng:NextNumber(-60, 200))
			localPart(scene, Enum.PartType.Block, Vector3.new(rng:NextNumber(4, 14), rng:NextNumber(4, 12), rng:NextNumber(4, 14)), CFrame.new(p) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), Color3.fromRGB(110, 100, 120), Enum.Material.Slate)
		end
		petPos = base
	end
	local platform = localPart(scene, Enum.PartType.Cylinder, Vector3.new(1, 14, 14), CFrame.new(petPos - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 230, 120), Enum.Material.Neon)
	platform.Transparency = if kind == "moon" then 1 else 0.3
	food.CFrame = CFrame.new(petPos + Vector3.new(0, 80, -120))
	tween(food :: any, 0.6, { CFrame = CFrame.new(petPos + Vector3.new(0, 2, 0)) }, Enum.EasingStyle.Quad)
	local orbitStart = os.clock()
	bind(seq, function()
		local a = (os.clock() - orbitStart) * 0.5
		local target = petPos + Vector3.new(0, 4, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(a) * 34, 12, -math.cos(a) * 34), target)
		camera.FieldOfView = 70
	end)
	if not wait(seq, 0.65) then
		return
	end
	food.Transparency = 1
	self:_burst(petPos, Color3.fromRGB(200, 180, 255), 2)
	local model = self:_spawnCaughtPet(payload, petPos)
	if model then
		model.Parent = scene
	end
	local rec = payload.pet or {}
	local pet = PetConfig.get(rec.species)
	local mut = {}
	if rec.size and rec.size ~= "Normal" then
		table.insert(mut, rec.size)
	end
	if rec.material and rec.material ~= "Normal" then
		table.insert(mut, rec.material)
	end
	self.hud:setCutscene(true, string.upper(payload.rarity or "") .. " CATCH!", (if #mut > 0 then table.concat(mut, " ") .. " " else "") .. (if pet then pet.name else ""))
	if not wait(seq, 3) then
		return
	end
	self:_finish(seq)
end

-- Entry point from GameClient for every CatchEffect payload.
function Effects:celebrate(payload: any)
	local idx = payload.rarityIndex or 1
	if idx >= GameConfig.rarityIndex("Legendary") then
		local color = (GameConfig.RarityColors :: any)[payload.rarity] or Color3.new(1, 1, 1)
		self.hud:flash(color, if idx >= GameConfig.rarityIndex("Mythic") then 0.65 else 0.45)
		self.hud:toast(string.format("%s CATCH!", string.upper(payload.rarity or "")), color)
	end
end

function Effects:playCatch(payload: any)
	task.delay(if payload.cutscene then 0 else 0.8, function()
		self:celebrate(payload)
	end)
	local state: any = self.getState() or {}
	local settings = state.settings or {}
	local showFx = settings.ShowCutscenes ~= false
	-- Auto-throws never take over the camera with a cutscene (they repeat every few seconds).
	if payload.cutscene and showFx and payload.manual ~= true then
		self.hud:toast(string.format("Auto-Throw reached %s!", if payload.cutscene == "moon" then "the Moon" else "Space"), Color3.fromRGB(170, 100, 255))
	elseif payload.cutscene and showFx then
		local threshold = settings.AutoSkipRarity or "Off"
		local autoSkip = threshold ~= "Off" and (payload.rarityIndex or 1) < GameConfig.rarityIndex(threshold)
		if autoSkip then
			self.hud:toast(string.format("%s cutscene auto-skipped (below %s)", if payload.cutscene == "moon" then "Moon" else "Space", threshold), Color3.fromRGB(110, 110, 160))
		else
			task.spawn(function()
				self:_cutscene(payload)
				self.hud:showCatch(payload)
			end)
			return
		end
	end
	local follow = showFx and payload.manual == true and (payload.distance or 0) > 120 and not self:isPlaying()
	if payload.manual or not self:isPlaying() then
		self:_flight(payload, follow)
	end
	self.hud:showCatch(payload)
end

------------------------------------------------------------------ weather

function Effects:setWeather(w: any)
	if self.weatherPart then
		self.weatherPart:Destroy()
		self.weatherPart = nil :: any
	end
	if self.weatherConn then
		self.weatherConn:Disconnect()
		self.weatherConn = nil :: any
	end
	local def = if w and w.active then GameConfig.getWeather(w.id) else nil
	self.weatherColor = if def then def.color else nil
	if not def then
		tween(self.tint, 2, { TintColor = Color3.new(1, 1, 1), Saturation = 0.1, Contrast = 0.05 })
		return
	end
	tween(self.tint, 2, { TintColor = Color3.new(1, 1, 1):Lerp(def.color, 0.25), Saturation = 0.3, Contrast = 0.1 })
	local part = localPart(self.folder, Enum.PartType.Block, Vector3.new(160, 1, 160), CFrame.new(), Color3.new(1, 1, 1))
	part.Transparency = 1
	part.Name = "WeatherEmitter"
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Bottom
	e.LightEmission = 0.8
	e.Lifetime = NumberRange.new(2.5, 3.5)
	e.Transparency = NumberSequence.new(0.1, 0.9)
	if def.id == "TitanStorm" then
		e.Color = ColorSequence.new(def.color, Color3.fromRGB(255, 255, 255))
		e.Rate = 80
		e.Speed = NumberRange.new(40, 60)
		e.Size = NumberSequence.new(0.6, 0.3)
	elseif def.id == "FeastFrenzy" then
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 200)),
		})
		e.Rate = 50
		e.Speed = NumberRange.new(12, 20)
		e.Size = NumberSequence.new(1.2, 0.6)
		e.RotSpeed = NumberRange.new(-180, 180)
	else
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(80, 255, 120)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 160, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 255)),
		})
		e.Rate = 60
		e.Speed = NumberRange.new(6, 12)
		e.Size = NumberSequence.new(0.8, 0)
	end
	e.Parent = part
	self.weatherPart = part
	self.weatherConn = RunService.Heartbeat:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera and part.Parent then
			part.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
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
		for model, base in bases do
			if not model.Parent then
				bases[model] = nil
			elseif (base.Position - camPos).Magnitude < 180 then
				local phase = (base.Position.X + base.Position.Z) * 0.1
				model:PivotTo(base * CFrame.new(0, math.sin(now * 2 + phase) * 0.35 + 0.35, 0) * CFrame.Angles(0, math.sin(now * 0.8 + phase) * 0.25, 0))
			end
		end
		self:_updateAmbience(camPos)
		-- Rainbow material cycles through the spectrum.
		local hue = (now * 0.25) % 1
		for _, m in CollectionService:GetTagged("RainbowPet") do
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") and p.Name ~= "Eye" and p.Name ~= "Shine" and p.Name ~= "Nose" and p.Name ~= "Cheek" then
					p.Color = Color3.fromHSV((hue + p.Position.Y * 0.03) % 1, 0.75, 1)
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
		color = color:Lerp(self.weatherColor, 0.45)
		density += 0.05
	end
	a.Color = a.Color:Lerp(color, 0.08)
	a.Density = a.Density + (density - a.Density) * 0.08
end

function Effects:destroy()
	self:skip()
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	if self.weatherConn then
		self.weatherConn:Disconnect()
	end
	self.folder:Destroy()
	self.tint:Destroy()
	self.bloom:Destroy()
	self.sunRays:Destroy()
end

return Effects
