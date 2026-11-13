--!strict
-- Snack Force: Pet Toss - client entry point. Builds the HUD, forwards input intents to
-- the server and renders the server's results. No gameplay authority lives here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local GameMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameMath"))
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
	settings = { AutoThrow = false, AutoSkipRarity = "Epic", KeepMutated = true, ShowCutscenes = true, AutoSellRarity = "Off" },
	autoThrowUnlocked = false,
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

local function findWorldPart(path: { string }): BasePart?
	local node: Instance? = Workspace:FindFirstChild("SnackWorld")
	for _, name in path do
		if not node then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	if node and node:IsA("BasePart") then
		return node
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
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local offset = root.Position - Vector3.new(0, 0, -12)
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= GameConfig.ThrowLineRadius - 2
end

------------------------------------------------------------------ HUD + FX

local hud: any
local fx: any
local charging = false
local chargeStart = 0
local lastRelease = 0

local function teleportThrowLine()
	local pad = findWorldPart({ "ThrowLine", "LaunchPad" })
	if pad then
		teleport(CFrame.new(pad.Position + Vector3.new(0, 4, 0)))
	end
end

local function teleportPlot()
	local idx = state.plotIndex
	if not idx then
		hud:toast("All plots are taken - your pets still earn coins!", UI.Colors.Orange)
		return
	end
	local plotsFolder = Workspace:FindFirstChild("SnackWorld") and (Workspace.SnackWorld :: any):FindFirstChild("Plots")
	local plot = plotsFolder and plotsFolder:FindFirstChild("Plot" .. tostring(idx))
	local pad = plot and plot:FindFirstChild("Pad")
	if pad and pad:IsA("BasePart") then
		teleport(pad.CFrame * CFrame.new(0, 5, -24) * CFrame.Angles(0, math.pi, 0))
	end
end

local function throwDown()
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
		hud:toast("Walk to the Throw Line to throw! (or press Throw Line)", UI.Colors.Orange)
		return
	end
	charging = true
	chargeStart = os.clock()
	ThrowFood:FireServer("Begin")
end

local function throwUp()
	if not charging then
		return
	end
	charging = false
	lastRelease = os.clock()
	ThrowFood:FireServer("Release")
end

local lastTrain = 0
local function train()
	local now = os.clock()
	if now - lastTrain < GameConfig.TrainCooldown then
		return
	end
	lastTrain = now
	TrainStrength:FireServer()
	-- Optimistic feedback; the server's StateSync is authoritative.
	if hud then
		UI.pop(hud.trainBtn)
	end
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
	onTrain = train,
	teleportThrowLine = teleportThrowLine,
	teleportPlot = teleportPlot,
	onSkip = skip,
})
fx = Effects.new(hud, getState)
fx:startAmbient()
hud:update(state)
hud:toast("Loading your save...", UI.Colors.Blue)

------------------------------------------------------------------ input

local connections: { RBXScriptConnection } = {}

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
		train()
	end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR2 then
		throwUp()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- Releasing the THROW button anywhere on screen still releases the throw.
		throwUp()
	end
end))

table.insert(connections, RunService.RenderStepped:Connect(function()
	local charge = if charging then GameMath.chargeAt(os.clock() - chargeStart) else nil
	if charging and os.clock() - chargeStart > GameConfig.MaxChargeTime - 0.5 then
		throwUp()
	end
	hud:tick(charge)
end))

------------------------------------------------------------------ remotes

table.insert(connections, StateSync.OnClientEvent:Connect(function(incoming: any)
	if type(incoming) ~= "table" then
		return
	end
	for k, v in incoming do
		state[k] = v
	end
	if not state.loaded then
		state.loaded = true
		hud:toast("Welcome to Snack Force! Hold E at the Throw Line.", UI.Colors.Green)
	end
	hud:update(state)
end))

table.insert(connections, CatchEffect.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.notice) == "string" then
		hud:toast(payload.notice, UI.Colors.Red)
		return
	end
	if payload.sweetSpot then
		hud:toast("SWEET SPOT! x1.25 distance, x1.35 luck", UI.Colors.Green)
	end
	if payload.cravingMatched then
		hud:toast(string.format("Craving match! Combo x%s  (+%s coins)", tostring(payload.comboMult), GameMath.formatNumber(payload.bonusCoins or 0)), UI.Colors.Orange)
	end
	if payload.newRecord and payload.manual then
		hud:toast(string.format("NEW RECORD: %sm!", GameMath.formatNumber(payload.distance or 0)), UI.Colors.Blue)
	end
	if payload.unlockedAutoThrow then
		hud:toast("AUTO-THROW UNLOCKED! Turn it on in Settings.", UI.Colors.Purple)
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
