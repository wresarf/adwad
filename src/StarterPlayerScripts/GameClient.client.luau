--!strict
-- Snack Force: Pet Toss - client entry point. Builds the HUD, forwards input intents to
-- the server and renders the server's results. No gameplay authority lives here.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameMath = require(Shared:WaitForChild("GameMath"))
local Progression = require(Shared:WaitForChild("Progression"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ClientModules = script.Parent:WaitForChild("Client")
local Hud = require(ClientModules:WaitForChild("Hud"))
local Effects = require(ClientModules:WaitForChild("Effects"))
local UI = require(ClientModules:WaitForChild("UI"))

local ThrowFood = Remotes:WaitForChild("ThrowFood") :: RemoteEvent
local TrainStrength = Remotes:WaitForChild("TrainStrength") :: RemoteEvent
local StateSync = Remotes:WaitForChild("StateSync") :: RemoteEvent
local CatchEffect = Remotes:WaitForChild("CatchEffect") :: RemoteEvent
local WeatherEvent = Remotes:WaitForChild("WeatherEvent") :: RemoteEvent

local INVOKABLE = { BuyFood = true, EquipBest = true, FusePets = true, AutoSell = true, ToggleSetting = true }

------------------------------------------------------------------ state

-- Safe defaults until the first StateSync arrives (startup nil-safety).
local state: { [string]: any } = {
	coins = 0,
	strength = 0,
	income = 0,
	bestDistance = 0,
	streak = 0,
	comboMult = 1,
	equippedFood = FoodConfig.DefaultFood,
	ownedFoods = { [FoodConfig.DefaultFood] = true },
	pets = {},
	discovered = {},
	settings = { AutoThrow = false, AutoSkipRarity = "Epic", KeepMutated = true, ShowCutscenes = true, ShowGuide = true, AutoSellRarity = "Off" },
	autoThrowUnlocked = false,
	quest = nil,
	questsDone = 0,
	totalThrows = 0,
	stats = {},
	zonesReached = {},
	loaded = false,
}

local function getState()
	return state
end

local function invoke(name: string, ...: any): (boolean, string)
	if not INVOKABLE[name] then
		return false, "Unknown action"
	end
	local remote = Remotes:FindFirstChild(name)
	if not (remote and remote:IsA("RemoteFunction")) then
		return false, "Server not ready"
	end
	local args = table.pack(...)
	local ok, a, b = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return false, "Connection problem, try again"
	end
	return a == true, if type(b) == "string" then b else (if a then "Done" else "Failed")
end

------------------------------------------------------------------ world helpers

local function findWorld(path: { string }): Instance?
	local node: Instance? = Workspace:FindFirstChild("SnackWorld")
	for _, name in path do
		if not node then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	return node
end

local function worldPosition(path: { string }): Vector3?
	local node = findWorld(path)
	if node and node:IsA("BasePart") then
		return node.Position
	end
	return nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function teleport(cf: CFrame)
	local character = player.Character
	if character and character.PrimaryPart then
		character:PivotTo(cf)
	end
end

local function nearThrowLine(): boolean
	local root = rootPart()
	return root ~= nil and Progression.nearThrowLine(root.Position, 2)
end

local function inGym(): boolean
	local root = rootPart()
	return root ~= nil and Progression.inGym(root.Position)
end

------------------------------------------------------------------ HUD + FX

local hud: any
local fx: any
local charging = false
local chargeStart = 0
local lastRelease = 0
local trainHeld = false
local lastTrain = 0
-- The pointer/touch that started a THROW or TRAIN press. Only that same input releases
-- it, so lifting another finger (e.g. off the thumbstick) never fires the throw early.
local throwInput: InputObject? = nil
local trainInput: InputObject? = nil

local function teleportThrowLine()
	local c = GameConfig.ThrowLineCenter
	teleport(CFrame.new(c + Vector3.new(0, 4, -4)))
end

local function teleportGym()
	local c = GameConfig.GymCenter
	teleport(CFrame.lookAt(c + Vector3.new(8, 4, 0), c + Vector3.new(30, 4, 0)))
end

local function teleportPlot()
	if not state.loaded then
		hud:toast("Still loading your plot...", UI.Colors.Blue)
		return
	end
	local idx = state.plotIndex
	if not idx then
		hud:toast("All plots are taken: your pets still earn coins!", UI.Colors.Orange)
		return
	end
	local pad = findWorld({ "Plots", "Plot" .. tostring(idx), "Pad" })
	if pad and pad:IsA("BasePart") then
		teleport(pad.CFrame * CFrame.new(0, 5, -24) * CFrame.Angles(0, math.pi, 0))
	end
end

local function throwDown(input: InputObject?)
	if fx and fx:isPlaying() then
		fx:skip()
		return
	end
	if charging then
		return
	end
	if os.clock() - lastRelease < GameConfig.ThrowCooldown then
		return
	end
	if not nearThrowLine() then
		hud:toast("Walk to the Throw Line to throw! (or Teleport: Throw)", UI.Colors.Orange)
		hud:pulse("ThrowLine")
		return
	end
	charging = true
	chargeStart = os.clock()
	throwInput = input
	ThrowFood:FireServer("Begin")
end

local function throwUp()
	if not charging then
		return
	end
	charging = false
	throwInput = nil
	lastRelease = os.clock()
	local charge = GameMath.chargeAt(lastRelease - chargeStart)
	ThrowFood:FireServer("Release")
	fx:setCharging(nil)
	fx:punch(if GameMath.isSweetSpot(charge) then 1.2 else 0.5)
end

local function train()
	local now = os.clock()
	if now - lastTrain < GameConfig.TrainCooldown then
		return
	end
	lastTrain = now
	TrainStrength:FireServer()
	-- Optimistic feedback only; the server's StateSync is authoritative.
	local boosted = inGym()
	local gain = GameMath.trainGain(state.strength or 0) * (if boosted then GameConfig.GymMultiplier else 1)
	fx:trainPop(gain, boosted)
	UI.pop(hud.trainBtn)
end

local function trainDown(input: InputObject?)
	trainHeld = true
	trainInput = input
	train()
end

local function trainUp()
	trainHeld = false
	trainInput = nil
end

local function sameInput(held: InputObject?, input: InputObject): boolean
	if held == nil then
		return false
	end
	if held == input then
		return true
	end
	-- Mouse button objects are shared per button, compare by type to be safe.
	return held.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1
end

local function skip()
	if fx then
		fx:skip()
	end
end

hud = Hud.new(playerGui, {
	invoke = invoke,
	getState = getState,
	onThrowDown = throwDown,
	onThrowUp = throwUp,
	onTrainDown = trainDown,
	onTrainUp = trainUp,
	teleportThrowLine = teleportThrowLine,
	teleportPlot = teleportPlot,
	teleportGym = teleportGym,
	onSkip = skip,
})
fx = Effects.new(hud, getState)
fx:startAmbient()
hud:update(state)
hud:toast("Loading your save...", UI.Colors.Blue)

-- Throw preview shown on the meter: same math as the server, without random gusts.
local function previewText(charge: number): string
	local food = FoodConfig.get(state.equippedFood) or FoodConfig.Foods[1]
	local raw = GameMath.rawDistance(state.strength or 0, food.power, charge, GameMath.isSweetSpot(charge))
	local distance, zone = GameMath.resolveFlight(raw)
	return string.format("~%sm  %s", GameMath.formatNumber(distance), BiomeConfig.zoneName(zone))
end

------------------------------------------------------------------ quest guide

local function focusTarget(focus: string?): (Vector3?, string?)
	if focus == "ThrowLine" then
		return GameConfig.ThrowLineCenter + Vector3.new(0, 2, -6), "THROW LINE"
	elseif focus == "Gym" then
		return GameConfig.GymCenter + Vector3.new(0, 2, 0), "GYM"
	elseif focus == "Shop" then
		return worldPosition({ "SpawnHub", "FoodShopStall", "ShopCounter" }), "FOOD SHOP"
	elseif focus == "Pets" then
		return worldPosition({ "SpawnHub", "FuseAltar", "AltarBase" }), "PETS & FUSE"
	elseif focus == "Index" then
		return worldPosition({ "SpawnHub", "PetIndexBoard", "IndexStand" }), "PET INDEX"
	end
	return nil, nil
end

local lastGuide = 0
local lastPulse = 0
local function updateGuide()
	local now = os.clock()
	if now - lastGuide < 0.1 then
		return
	end
	lastGuide = now
	local q = state.quest
	local settings = state.settings or {}
	local root = rootPart()
	local gym = inGym()
	hud:setGym(gym)

	-- Context hint above the meter.
	local hint = ""
	if not state.loaded then
		hint = "Loading..."
	elseif charging then
		hint = ""
	elseif gym then
		hint = "Hold Q / TRAIN: double strength in here!"
	elseif not nearThrowLine() then
		hint = "Walk to the Throw Line to throw (Teleport: Throw)"
	elseif (state.totalThrows or 0) == 0 then
		hint = "Hold E or THROW, let go in the green zone!"
	end
	hud:setContext(hint)

	local target, label = nil, nil
	if q and settings.ShowGuide ~= false and state.loaded then
		target, label = focusTarget(q.focus)
		-- Throwing quests only need a guide while away from the Throw Line.
		if q.focus == "ThrowLine" and nearThrowLine() then
			target = nil
		end
		if target and root and (root.Position - target).Magnitude < 16 then
			target = nil
		end
		if (q.focus == "Shop" or q.focus == "Pets" or q.focus == "Index") and now - lastPulse > 3 then
			lastPulse = now
			hud:pulse(q.focus)
		end
	end
	fx:setGuide(target, label)
end

------------------------------------------------------------------ input

local connections: { RBXScriptConnection } = {}

local HOTKEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.F] = "Shop",
	[Enum.KeyCode.G] = "Pets",
	[Enum.KeyCode.N] = "Index",
	[Enum.KeyCode.H] = "Help",
}

table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return then
		if fx:isPlaying() then
			skip()
		end
		return
	end
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR2 then
		throwDown()
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonX then
		trainDown()
	elseif HOTKEYS[input.KeyCode] then
		hud.panels:toggle(HOTKEYS[input.KeyCode])
	end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR2 then
		throwUp()
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonX then
		trainUp()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- Releasing the press that started THROW / TRAIN anywhere on screen releases it.
		if sameInput(throwInput, input) then
			throwUp()
		end
		if sameInput(trainInput, input) then
			trainUp()
		end
	end
end))

-- World stalls (Food Shop, Fusion Altar, Pet Index) open their panel.
table.insert(connections, ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then
		return
	end
	local panel = prompt:GetAttribute("OpenPanel")
	if type(panel) == "string" then
		hud.panels:toggle(panel)
	end
end))

table.insert(connections, RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local charge = if charging then GameMath.chargeAt(now - chargeStart) else nil
	if charging and now - chargeStart > GameConfig.MaxChargeTime - 0.5 then
		throwUp()
		charge = nil
	end
	if trainHeld and now - lastTrain >= GameConfig.TrainRepeat then
		train()
	end
	fx:setCharging(charge, state.equippedFood)
	hud:tick(charge, if charge then previewText(charge) else nil)
	updateGuide()
end))

------------------------------------------------------------------ remotes

table.insert(connections, StateSync.OnClientEvent:Connect(function(incoming: any)
	if type(incoming) ~= "table" then
		return
	end
	for k, v in incoming do
		state[k] = v
	end
	if incoming.quest == false then
		state.quest = nil -- quest line finished
	end
	if not state.loaded then
		state.loaded = true
		if (state.totalThrows or 0) == 0 and (state.questsDone or 0) == 0 then
			hud:showWelcome()
		else
			hud:toast("Welcome back to Snack Force!", UI.Colors.Green)
		end
	end
	hud:update(state)
	fx:setBestDistance(state.bestDistance or 0)
end))

table.insert(connections, CatchEffect.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.notice) == "string" then
		hud:toast(payload.notice, UI.Colors.Red)
		return
	end
	if payload.kind == "reward" then
		hud:showReward(payload)
		return
	end
	if payload.sweetSpot then
		hud:toast("SWEET SPOT! x1.25 distance, x1.35 luck", UI.Colors.Green)
	end
	if payload.cravingMatched then
		hud:toast(string.format("Craving match! Combo x%s", tostring(payload.comboMult)), UI.Colors.Orange)
	end
	if payload.newRecord and payload.manual then
		hud:toast(string.format("NEW RECORD: %sm!", GameMath.formatNumber(payload.distance or 0)), UI.Colors.Blue)
	end
	if payload.unlockedAutoThrow then
		hud:showReward({ title = "AUTO-THROW UNLOCKED!", text = "Turn it on in Settings", coins = 0, color = "Purple" })
	end
	if payload.zoneFirst then
		hud:showReward({ title = "NEW ZONE REACHED!", text = payload.zoneName or "", coins = payload.zoneReward or 0, color = "Blue" })
	end
	local coins = (payload.bonusCoins or 0) + (payload.discoveryReward or 0) + (payload.soldFor or 0)
	if coins > 0 then
		task.delay(0.9, function()
			hud:coinPopup(coins)
		end)
	end
	fx:playCatch(payload)
end))

table.insert(connections, WeatherEvent.OnClientEvent:Connect(function(w: any)
	if type(w) ~= "table" then
		return
	end
	local wasActive = hud.weather and hud.weather.active
	hud:setWeather(w)
	fx:setWeather(w)
	if w.active and not wasActive then
		local def = GameConfig.getWeather(w.id)
		hud:toast(string.format("WEATHER: %s - %s", w.name or "?", w.description or ""), if def then def.color else UI.Colors.Purple)
	elseif not w.active and wasActive then
		hud:toast("The weather has cleared. Cravings changed!", UI.Colors.PanelLight)
	end
end))

-- Clean up if this script is ever removed (e.g. during testing).
script.Destroying:Connect(function()
	for _, c in connections do
		c:Disconnect()
	end
	fx:destroy()
	hud:destroy()
end)
