--!strict
-- Snack Force: Pet Toss - authoritative game server.
-- Owns all math/RNG, currency, inventory and persistence. Clients only send intents.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Config")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local GameMath = require(Shared:WaitForChild("GameMath"))
local RemoteContract = require(Shared:WaitForChild("RemoteContract"))

local ServerModules = script.Parent:WaitForChild("Server")
local WorldBuilder = require(ServerModules:WaitForChild("WorldBuilder"))
local PlayerData = require(ServerModules:WaitForChild("PlayerData"))
local DataService = require(ServerModules:WaitForChild("DataService"))
local Inventory = require(ServerModules:WaitForChild("Inventory"))
local PlotService = require(ServerModules:WaitForChild("PlotService"))
local WeatherService = require(ServerModules:WaitForChild("WeatherService"))
local RateLimiter = require(ServerModules:WaitForChild("RateLimiter"))

------------------------------------------------------------------ remotes

local function remote(name: string): Instance
	local r = RemotesFolder:WaitForChild(name, 10)
	assert(r, "Missing remote " .. name)
	return r
end

local ThrowFood = remote("ThrowFood") :: RemoteEvent
local TrainStrength = remote("TrainStrength") :: RemoteEvent
local BuyFood = remote("BuyFood") :: RemoteFunction
local EquipBest = remote("EquipBest") :: RemoteFunction
local FusePets = remote("FusePets") :: RemoteFunction
local AutoSell = remote("AutoSell") :: RemoteFunction
local ToggleSetting = remote("ToggleSetting") :: RemoteFunction
local StateSync = remote("StateSync") :: RemoteEvent
local CatchEffect = remote("CatchEffect") :: RemoteEvent
local WeatherEvent = remote("WeatherEvent") :: RemoteEvent

------------------------------------------------------------------ world

local world = WorldBuilder.build(Workspace)
local plots = PlotService.new(world.plots)
local limiter = RateLimiter.new(GameConfig.RateLimits)
local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

do
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.45
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
end

------------------------------------------------------------------ sessions

type Session = {
	player: Player,
	data: PlayerData.Data,
	canSave: boolean,
	plot: WorldBuilder.PlotInfo?,
	streak: number,
	chargeStart: number?,
	lastThrow: number,
	lastTrain: number,
	income: number,
	dirtyFull: boolean,
	dirtyStats: boolean,
	saving: boolean,
	connections: { RBXScriptConnection },
}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}

local weather: WeatherService.WeatherService

local function markFull(s: Session)
	s.dirtyFull = true
end

local function recomputeIncome(s: Session)
	s.income = Inventory.totalIncome(s.data)
end

local function refreshPlot(s: Session)
	recomputeIncome(s)
	plots:render(s.player, s.data, s.income)
end

local function buildState(s: Session, full: boolean): { [string]: any }
	local d = s.data
	local state: { [string]: any } = {
		full = full,
		coins = d.coins,
		strength = d.strength,
		income = s.income,
		bestDistance = d.bestDistance,
		streak = s.streak,
		comboMult = GameMath.comboMultiplier(s.streak),
		totalCatches = d.totalCatches,
		autoThrowUnlocked = d.autoThrowUnlocked,
		equippedFood = d.equippedFood,
		canSave = s.canSave,
	}
	if full then
		state.ownedFoods = d.ownedFoods
		state.pets = d.pets
		state.settings = d.settings
		state.discovered = d.discovered
		state.plotIndex = if s.plot then s.plot.index else nil
		state.maxPets = GameConfig.MaxPets
		state.slots = GameConfig.PlotPedestals
	end
	return state
end

local function sync(s: Session)
	if not s.player.Parent then
		return
	end
	local full = s.dirtyFull
	s.dirtyFull = false
	s.dirtyStats = false
	StateSync:FireClient(s.player, buildState(s, full))
end

local function saveSession(s: Session): boolean
	if not s.canSave or s.saving then
		return false
	end
	s.saving = true
	local ok = DataService.save(s.player.UserId, s.data)
	s.saving = false
	return ok
end

local function nearThrowLine(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local offset = root.Position - world.throwLineCenter
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= GameConfig.ThrowLineRadius
end

------------------------------------------------------------------ throwing

local function performThrow(s: Session, charge: number, manual: boolean)
	local d = s.data
	local food = FoodConfig.get(d.equippedFood) or FoodConfig.Foods[1]
	local w = weather:snapshot()
	local gusts = {}
	for i = 1, #BiomeConfig.Biomes do
		gusts[i] = rng:NextNumber(-1, 1)
	end
	local result = GameMath.computeThrow({
		strength = d.strength,
		foodPower = food.power,
		foodLuck = food.luck,
		foodCraving = food.craving,
		charge = charge,
		allowSweetSpot = manual,
		streak = s.streak,
		zoneCravings = w.cravings,
		weatherSizeLuck = w.sizeLuck,
		weatherMaterialLuck = w.materialLuck,
		weatherCravingBonus = w.cravingBonus,
		rng = roll,
	}, gusts)

	s.streak = result.streak
	s.lastThrow = os.clock()
	d.totalThrows += 1
	d.coins += result.bonusCoins
	local newRecord = result.distance > d.bestDistance
	if newRecord then
		d.bestDistance = result.distance
	end
	local unlockedAuto = false
	if not d.autoThrowUnlocked and d.bestDistance >= GameConfig.AutoThrowUnlockDistance then
		d.autoThrowUnlocked = true
		unlockedAuto = true
	end

	local rec = Inventory.newPet(d, result.species, result.material, result.size)
	local outcome, soldFor = Inventory.catch(d, rec, GameConfig.PlotPedestals)
	local rarity, rarityIndex = GameMath.overallRarity(rec)
	if outcome == "kept" and rec.equipped then
		refreshPlot(s)
	end
	markFull(s)

	local cutscene: string? = nil
	if result.zone == "Moon" then
		cutscene = "moon"
	elseif result.zone == "Space" then
		cutscene = "space"
	end

	CatchEffect:FireClient(s.player, {
		manual = manual,
		distance = result.distance,
		zone = result.zone,
		charge = result.charge,
		sweetSpot = result.sweetSpot,
		cravingMatched = result.cravingMatched,
		zoneCraving = result.zoneCraving,
		foodId = food.id,
		streak = result.streak,
		comboMult = result.comboMult,
		bonusCoins = result.bonusCoins,
		pet = rec,
		rarity = rarity,
		rarityIndex = rarityIndex,
		income = GameMath.petIncome(rec),
		outcome = outcome,
		soldFor = soldFor,
		newRecord = newRecord,
		unlockedAutoThrow = unlockedAuto,
		cutscene = cutscene,
		lateral = rng:NextNumber(-60, 60),
	})
end

local function onThrowFood(player: Player, action: any)
	local s = sessions[player]
	if not s then
		return
	end
	if type(action) ~= "string" or not RemoteContract.ThrowActions[action] then
		return
	end
	if not limiter:allow(player, "ThrowFood") then
		return
	end
	local now = os.clock()
	if action == "Begin" then
		s.chargeStart = now
		return
	end
	-- Release
	local started = s.chargeStart
	s.chargeStart = nil
	if not started then
		return
	end
	local elapsed = now - started
	if elapsed < GameConfig.MinChargeTime or elapsed > GameConfig.MaxChargeTime then
		return
	end
	if now - s.lastThrow < GameConfig.ThrowCooldown then
		return
	end
	if not nearThrowLine(player) then
		return
	end
	performThrow(s, GameMath.chargeAt(elapsed), true)
end

------------------------------------------------------------------ other remotes

local function onTrain(player: Player)
	local s = sessions[player]
	if not s or not limiter:allow(player, "TrainStrength") then
		return
	end
	local now = os.clock()
	if now - s.lastTrain < GameConfig.TrainCooldown then
		return
	end
	s.lastTrain = now
	s.data.strength += GameMath.trainGain(s.data.strength)
	s.dirtyStats = true
end

local function guard(name: string, handler: (Session, ...any) -> (boolean, string))
	return function(player: Player, ...: any): (boolean, string)
		local s = sessions[player]
		if not s then
			return false, "Still loading your save..."
		end
		if not limiter:allow(player, name) then
			return false, "Slow down!"
		end
		local ok, a, b = pcall(handler, s, ...)
		if not ok then
			warn("[SnackForce] " .. name .. " handler error:", a)
			return false, "Something went wrong"
		end
		return a, b
	end
end

BuyFood.OnServerInvoke = guard("BuyFood", function(s, foodId: any)
	if type(foodId) ~= "string" or #foodId > 40 then
		return false, "Invalid food"
	end
	local food = FoodConfig.get(foodId)
	if not food then
		return false, "Unknown food"
	end
	local d = s.data
	if not d.ownedFoods[food.id] then
		if d.coins < food.price then
			return false, "Need " .. GameMath.formatNumber(food.price - d.coins) .. " more coins"
		end
		d.coins -= food.price
		d.ownedFoods[food.id] = true
	end
	d.equippedFood = food.id
	markFull(s)
	return true, "Equipped " .. food.name
end)

EquipBest.OnServerInvoke = guard("EquipBest", function(s)
	local n = Inventory.equipBest(s.data, GameConfig.PlotPedestals)
	refreshPlot(s)
	markFull(s)
	return true, string.format("Equipped your best %d pets", n)
end)

FusePets.OnServerInvoke = guard("FusePets", function(s, key: any)
	if type(key) ~= "string" or #key > 80 then
		return false, "Invalid fuse request"
	end
	if key == "ALL" then
		local made = Inventory.fuseAll(s.data)
		if made == 0 then
			return false, "No groups of 3 identical pets"
		end
		refreshPlot(s)
		markFull(s)
		return true, string.format("Fused %d time%s!", made, if made == 1 then "" else "s")
	end
	local ok, res = Inventory.fuse(s.data, key)
	if not ok then
		return false, res
	end
	refreshPlot(s)
	markFull(s)
	local pet = PetConfig.get(res.species)
	return true, string.format("Fused into %s %s!", res.material, if pet then pet.name else "pet")
end)

AutoSell.OnServerInvoke = guard("AutoSell", function(s, threshold: any, sellNow: any)
	if not PlayerData.isRarityOrOff(threshold) then
		return false, "Invalid rarity"
	end
	if threshold ~= "Off" and GameConfig.rarityIndex(threshold) > GameConfig.rarityIndex("Legendary") then
		return false, "Mythic and Secret pets can't be auto-sold"
	end
	s.data.settings.AutoSellRarity = threshold
	local msg = if threshold == "Off" then "Auto-sell off" else "Auto-selling " .. threshold .. " and below"
	if sellNow == true and threshold ~= "Off" then
		local count, coins = Inventory.sellMatching(s.data)
		msg ..= string.format(" - sold %d for %s coins", count, GameMath.formatNumber(coins))
	end
	markFull(s)
	return true, msg
end)

ToggleSetting.OnServerInvoke = guard("ToggleSetting", function(s, name: any, value: any)
	if type(name) ~= "string" then
		return false, "Invalid setting"
	end
	local kind = (RemoteContract.Settings :: { [string]: string })[name]
	if kind == "boolean" then
		if type(value) ~= "boolean" then
			return false, "Invalid value"
		end
	elseif kind == "rarityOrOff" then
		if not PlayerData.isRarityOrOff(value) then
			return false, "Invalid value"
		end
	else
		return false, "Unknown setting"
	end
	if name == "AutoThrow" and value == true and not s.data.autoThrowUnlocked then
		return false, "Reach the Toxic Swamp (" .. GameConfig.AutoThrowUnlockDistance .. "m) to unlock Auto-Throw"
	end
	(s.data.settings :: any)[name] = value
	markFull(s)
	return true, name .. " updated"
end)

ThrowFood.OnServerEvent:Connect(onThrowFood)
TrainStrength.OnServerEvent:Connect(onTrain)

------------------------------------------------------------------ weather

weather = WeatherService.new(function(snapshot)
	WeatherEvent:FireAllClients(snapshot)
end)
weather:start()

------------------------------------------------------------------ player lifecycle

local function onPlayerAdded(player: Player)
	if sessions[player] or loading[player] then
		return
	end
	loading[player] = true
	local data, canSave = DataService.load(player.UserId)
	loading[player] = nil
	if not player.Parent then
		return -- left while loading
	end
	local s: Session = {
		player = player,
		data = data,
		canSave = canSave,
		plot = nil,
		streak = 0,
		chargeStart = nil,
		lastThrow = 0,
		lastTrain = 0,
		income = 0,
		dirtyFull = true,
		dirtyStats = false,
		saving = false,
		connections = {},
	}
	sessions[player] = s
	s.plot = plots:claim(player)
	refreshPlot(s)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local best = Instance.new("IntValue")
	best.Name = "Best (m)"
	best.Value = math.floor(data.bestDistance)
	best.Parent = leaderstats
	local caught = Instance.new("IntValue")
	caught.Name = "Caught"
	caught.Value = data.totalCatches
	caught.Parent = leaderstats
	leaderstats.Parent = player

	sync(s)
	WeatherEvent:FireClient(player, weather:snapshot())
	if not canSave then
		CatchEffect:FireClient(player, { notice = if DataService.isAvailable() then "Couldn't load your save - progress this session won't be saved." else "DataStores unavailable (Studio?) - progress won't be saved." })
	end
end

local function onPlayerRemoving(player: Player)
	local s = sessions[player]
	limiter:clear(player)
	if not s then
		return
	end
	for _, c in s.connections do
		c:Disconnect()
	end
	table.clear(s.connections)
	plots:release(player)
	saveSession(s)
	sessions[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

------------------------------------------------------------------ loops

-- Passive income + leaderstats, once per second.
task.spawn(function()
	while true do
		task.wait(1)
		for player, s in sessions do
			if s.income > 0 then
				s.data.coins += s.income
				s.dirtyStats = true
			end
			local ls = player:FindFirstChild("leaderstats")
			if ls then
				local best = ls:FindFirstChild("Best (m)") :: IntValue?
				local caught = ls:FindFirstChild("Caught") :: IntValue?
				if best then
					best.Value = math.floor(s.data.bestDistance)
				end
				if caught then
					caught.Value = s.data.totalCatches
				end
			end
		end
	end
end)

-- Batched state replication (at most 4x per second per player).
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, s in sessions do
			if s.dirtyFull or s.dirtyStats then
				local ok, err = pcall(sync :: any, s)
				if not ok then
					warn("[SnackForce] sync failed:", err)
				end
			end
		end
	end
end)

-- Late-game Auto-Throw (no sweet-spot bonus, fixed charge).
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		for _, s in sessions do
			if s.data.settings.AutoThrow and s.data.autoThrowUnlocked and now - s.lastThrow >= GameConfig.AutoThrowInterval then
				local ok, err = pcall(performThrow :: any, s, GameConfig.AutoThrowCharge, false)
				if not ok then
					warn("[SnackForce] auto-throw failed:", err)
					s.lastThrow = now
				end
			end
		end
	end
end)

-- Autosave every 60 seconds.
task.spawn(function()
	while true do
		task.wait(GameConfig.AutosaveInterval)
		for _, s in sessions do
			task.spawn(saveSession, s)
		end
	end
end)

game:BindToClose(function()
	weather:stop()
	if RunService:IsStudio() and not DataService.isAvailable() then
		return
	end
	local pending = 0
	for _, s in sessions do
		pending += 1
		task.spawn(function()
			s.saving = false -- force a final save even if an autosave is mid-flight
			saveSession(s)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

print(string.format("[SnackForce] Server ready - world built with %d parts, %d plots", world.partCount, #world.plots))
