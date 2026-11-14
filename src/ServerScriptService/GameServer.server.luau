--!strict
-- Snack Force: Pet Toss - authoritative game server.
-- Owns all math/RNG, currency, inventory and persistence. Clients only send intents.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
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
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local EggConfig = require(Config:WaitForChild("EggConfig"))
local UpgradeConfig = require(Config:WaitForChild("UpgradeConfig"))
local GameMath = require(Shared:WaitForChild("GameMath"))
local Progression = require(Shared:WaitForChild("Progression"))
local RemoteContract = require(Shared:WaitForChild("RemoteContract"))

local ServerModules = script.Parent:WaitForChild("Server")
local WorldBuilder = require(ServerModules:WaitForChild("WorldBuilder"))
local PlayerData = require(ServerModules:WaitForChild("PlayerData"))
local DataService = require(ServerModules:WaitForChild("DataService"))
local Inventory = require(ServerModules:WaitForChild("Inventory"))
local PlotService = require(ServerModules:WaitForChild("PlotService"))
local WeatherService = require(ServerModules:WaitForChild("WeatherService"))
local RateLimiter = require(ServerModules:WaitForChild("RateLimiter"))
local MarketService = require(ServerModules:WaitForChild("MarketService"))
local Receipts = require(ServerModules:WaitForChild("Receipts"))
local SaveGate = require(ServerModules:WaitForChild("SaveGate"))

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
local StorePurchase = remote("StorePurchase") :: RemoteFunction
local HatchEgg = remote("HatchEgg") :: RemoteFunction
local ManagePet = remote("ManagePet") :: RemoteFunction
local BuyUpgrade = remote("BuyUpgrade") :: RemoteFunction

------------------------------------------------------------------ world

local world = WorldBuilder.build(Workspace)
local plots = PlotService.new(world.plots)
local limiter = RateLimiter.new(GameConfig.RateLimits)
local rng = Random.new()
local market = MarketService.new(MarketplaceService, PolicyService)
do
	local problems = EggConfig.validate()
	assert(#problems == 0, "EggConfig invalid: " .. table.concat(problems, "; "))
end
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
	passes: { [string]: boolean }, -- verified server-side each session, never saved
	receiptBusy: number,
	pendingReceipts: { [string]: boolean },
	paidRandomRestricted: boolean,
	-- Set when the player starts leaving: receipts are no longer accepted and, once the
	-- releasing save has run, no other write may re-take the session lock.
	leaving: boolean,
	released: boolean,
}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}

local weather: WeatherService.WeatherService

local function markFull(s: Session)
	s.dirtyFull = true
end

local function coinRushActive(s: Session): boolean
	return (s.data.boosts.CoinRush or 0) > os.time()
end

local function incomeMultiplier(s: Session): number
	local mult = 1
	if s.passes.DoubleCoins then
		mult *= MonetizationConfig.DoubleCoinsMult
	end
	if coinRushActive(s) then
		mult *= MonetizationConfig.CoinRushMult
	end
	return mult
end

local function recomputeIncome(s: Session)
	s.income = Inventory.totalIncome(s.data) * incomeMultiplier(s)
end

local function capacity(s: Session): number
	return GameConfig.MaxPets + (if s.passes.BigBackpack then MonetizationConfig.BackpackBonus else 0)
end

local function autoThrowAvailable(s: Session): boolean
	return s.data.autoThrowUnlocked or s.passes.EarlyAutoThrow == true
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
		autoThrowUnlocked = autoThrowAvailable(s),
		gems = d.gems,
		pawTokens = d.pawTokens,
		coinRushEndsAt = if coinRushActive(s) then d.boosts.CoinRush else 0,
		incomeMult = incomeMultiplier(s),
		receiptPending = s.receiptBusy > 0,
		equippedFood = d.equippedFood,
		canSave = s.canSave,
		quest = Progression.questSnapshot(d, s.income) or false, -- false = quest line finished
		questsDone = math.max(0, d.questIndex - 1),
		totalThrows = d.totalThrows,
	}
	if full then
		state.ownedFoods = d.ownedFoods
		state.pets = d.pets
		state.settings = d.settings
		state.discovered = d.discovered
		state.plotIndex = if s.plot then s.plot.index else nil
		state.maxPets = capacity(s)
		state.passes = s.passes
		state.store = market:catalog()
		state.paidRandomRestricted = s.paidRandomRestricted
		state.slots = GameConfig.PlotPedestals
		state.stats = d.stats
		state.zonesReached = d.zonesReached
		state.upgrades = d.upgrades
	end
	return state
end

local function notifyReward(s: Session, title: string, text: string, coins: number, color: string?, tokens: number?, milestone: boolean?)
	CatchEffect:FireClient(s.player, { kind = "reward", title = title, text = text, coins = coins, color = color, tokens = tokens or 0, milestone = milestone == true })
end

local function giveTokens(s: Session, amount: number)
	if amount > 0 then
		s.data.pawTokens = math.min(s.data.pawTokens + amount, 1e6)
	end
end

-- Pays out every quest that the player's current stats already satisfy.
local function checkQuests(s: Session)
	local done = Progression.advanceQuests(s.data, s.income)
	for _, q in done do
		giveTokens(s, EggConfig.TokenRewards.Quest)
		notifyReward(s, "Quest complete", q.title, q.reward, "Gold", EggConfig.TokenRewards.Quest, false)
	end
	if #done > 0 then
		markFull(s)
	end
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

-- Saves now (see Server/SaveGate): waits for an in-flight save so a receipt is never
-- reported as saved by a write that started before it was recorded, and treats a
-- releasing save as the session's last write.
local function saveSession(s: Session, release: boolean?): boolean
	return SaveGate.save(s, release, function(rel: boolean?): boolean
		return DataService.save(s.player.UserId, s.data, rel)
	end, function(t: number)
		task.wait(t)
	end, os.clock)
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function nearThrowLine(player: Player): boolean
	local pos = rootPosition(player)
	return pos ~= nil and Progression.nearThrowLine(pos)
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
	result.bonusCoins = math.floor(result.bonusCoins * UpgradeConfig.cravingCoinMultiplier(d.upgrades))
	d.coins += result.bonusCoins
	local stats = d.stats
	if result.sweetSpot then
		stats.sweetSpots += 1
	end
	if result.cravingMatched then
		stats.cravingMatches += 1
	end
	stats.bestStreak = math.max(stats.bestStreak, result.streak)

	-- First landing in a zone pays a one-off reward.
	local zoneReward = 0
	if not d.zonesReached[result.zone] then
		d.zonesReached[result.zone] = true
		zoneReward = BiomeConfig.zoneReward(result.zone)
		d.coins += zoneReward
		giveTokens(s, EggConfig.TokenRewards.ZoneFirst)
	end
	local newRecord = result.distance > d.bestDistance
	if newRecord then
		d.bestDistance = result.distance
	end
	local unlockedAuto = false
	if not d.autoThrowUnlocked and d.bestDistance >= GameConfig.AutoThrowUnlockDistance then
		d.autoThrowUnlocked = true
		unlockedAuto = not s.passes.EarlyAutoThrow
	end

	local rec = Inventory.newPet(d, result.species, result.material, result.size)
	local newSpecies = not d.discovered[rec.species]
	local discoveryReward = if newSpecies then Progression.discoveryReward(rec.species) else 0
	d.coins += discoveryReward
	local tokens = 0
	if newSpecies then
		tokens += EggConfig.TokenRewards.NewSpecies
	end
	if zoneReward > 0 then
		tokens += EggConfig.TokenRewards.ZoneFirst
	end
	local outcome, soldFor = Inventory.catch(d, rec, GameConfig.PlotPedestals, capacity(s))
	if d.totalCatches % EggConfig.CatchMilestoneEvery == 0 then
		tokens += EggConfig.TokenRewards.CatchMilestone
		giveTokens(s, EggConfig.TokenRewards.CatchMilestone)
	end
	giveTokens(s, if newSpecies then EggConfig.TokenRewards.NewSpecies else 0)
	local rarity, rarityIndex = GameMath.overallRarity(rec)
	if GameMath.isMutated(rec) then
		stats.mutations += 1
	end
	stats.bestRarity = math.max(stats.bestRarity, rarityIndex)
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
		newSpecies = newSpecies,
		discoveryReward = discoveryReward,
		zoneFirst = zoneReward > 0,
		zoneReward = zoneReward,
		zoneName = BiomeConfig.zoneName(result.zone),
		tokens = tokens,
		goldenTrail = s.passes.GoldenTrail == true,
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
	local pos = rootPosition(player)
	local mult = (if pos and Progression.inGym(pos) then GameConfig.GymMultiplier else 1) * UpgradeConfig.trainMultiplier(s.data.upgrades)
	s.data.strength += GameMath.trainGain(s.data.strength) * mult
	s.data.stats.trains += 1
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
	local function reveal(rec: any, made: number)
		local rarity, rarityIndex = GameMath.overallRarity(rec)
		CatchEffect:FireClient(s.player, { kind = "hatch", source = "fuse", pet = rec, rarity = rarity, rarityIndex = rarityIndex, income = GameMath.petIncome(rec), fusions = made })
	end
	if key == "ALL" then
		local made, best = Inventory.fuseAll(s.data)
		if made == 0 then
			return false, "No groups of 3 identical pets"
		end
		s.data.stats.fusions += made
		refreshPlot(s)
		markFull(s)
		if best then
			reveal(best, made)
		end
		return true, string.format("Fused %d time%s", made, if made == 1 then "" else "s")
	end
	local ok, res = Inventory.fuse(s.data, key)
	if not ok then
		return false, res
	end
	s.data.stats.fusions += 1
	refreshPlot(s)
	markFull(s)
	reveal(res, 1)
	local pet = PetConfig.get(res.species)
	return true, string.format("Fused into %s %s", res.material, if pet then pet.name else "pet")
end)

ManagePet.OnServerInvoke = guard("ManagePet", function(s, action: any, key: any)
	if type(action) ~= "string" or not RemoteContract.PetActions[action] or type(key) ~= "string" or #key > 80 then
		return false, "Invalid request"
	end
	local d = s.data
	if #Inventory.group(d, key) == 0 then
		return false, "You don't have that pet anymore"
	end
	local ok, msg = false, ""
	if action == "Equip" then
		ok, msg = Inventory.equipOne(d, key, GameConfig.PlotPedestals)
	elseif action == "Unequip" then
		ok, msg = Inventory.unequipOne(d, key)
	elseif action == "Lock" or action == "Unlock" then
		Inventory.setLocked(d, key, action == "Lock")
		ok, msg = true, if action == "Lock" then "Locked: never sold or fused" else "Unlocked"
	elseif action == "Sell" then
		local sold, res = Inventory.sellOne(d, key)
		if not sold then
			return false, res
		end
		ok, msg = true, "Sold for " .. GameMath.formatNumber(res) .. " coins"
	end
	if ok then
		refreshPlot(s)
		markFull(s)
	end
	return ok, msg
end)

BuyUpgrade.OnServerInvoke = guard("BuyUpgrade", function(s, id: any)
	local upgrade = UpgradeConfig.get(id)
	if not upgrade then
		return false, "Unknown upgrade"
	end
	local d = s.data
	local level = d.upgrades[upgrade.id] or 0
	local price = UpgradeConfig.nextPrice(upgrade, level)
	if not price then
		return false, upgrade.name .. " is maxed"
	end
	if d.coins < price then
		return false, "Need " .. GameMath.formatNumber(price - d.coins) .. " more coins"
	end
	d.coins -= price
	d.upgrades[upgrade.id] = level + 1
	markFull(s)
	return true, string.format("%s level %d", upgrade.name, level + 1)
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
	if name == "AutoThrow" and value == true and not autoThrowAvailable(s) then
		return false, "Reach the Toxic Swamp (" .. GameConfig.AutoThrowUnlockDistance .. "m) to unlock Auto-Throw"
	end
	(s.data.settings :: any)[name] = value
	markFull(s)
	return true, name .. " updated"
end)

------------------------------------------------------------------ store + eggs

local function addPet(s: Session, species: string, material: string, size: string): (any, boolean)
	local d = s.data
	local rec = Inventory.newPet(d, species, material, size)
	local newSpecies = not d.discovered[species]
	Inventory.grant(d, rec, GameConfig.PlotPedestals)
	if newSpecies then
		giveTokens(s, EggConfig.TokenRewards.NewSpecies)
	end
	refreshPlot(s)
	return rec, newSpecies
end

local function buyOffer(s: Session, key: any): (boolean, string)
	local offer = MonetizationConfig.getOffer(key)
	if not offer then
		return false, "Unknown offer"
	end
	if s.receiptBusy > 0 then
		return false, "Finishing your last purchase..."
	end
	local d = s.data
	if d.gems < offer.gems then
		return false, string.format("Need %d more Gems", offer.gems - d.gems)
	end
	local grant = offer.grant
	if grant.kind == "pet" then
		local species, material, size = grant.species, grant.material or "Normal", grant.size or "Normal"
		if not species or not PetConfig.get(species) then
			return false, "Offer unavailable"
		end
		if Inventory.isFull(d, capacity(s)) then
			return false, "Your backpack is full"
		end
		d.gems -= offer.gems
		local rec = addPet(s, species, material, size)
		markFull(s)
		local rarity, rarityIndex = GameMath.overallRarity(rec)
		CatchEffect:FireClient(s.player, { kind = "hatch", source = "offer", pet = rec, rarity = rarity, rarityIndex = rarityIndex, income = GameMath.petIncome(rec) })
		return true, offer.name .. " added to your pets"
	elseif grant.kind == "boost" and grant.boost == "CoinRush" then
		local now = os.time()
		local current = math.max(d.boosts.CoinRush or 0, now)
		if current - now + (grant.seconds or 0) > MonetizationConfig.MaxBoostSeconds then
			return false, "Coin Rush is already at 24 hours"
		end
		d.gems -= offer.gems
		d.boosts.CoinRush = current + (grant.seconds or 0)
		refreshPlot(s)
		markFull(s)
		return true, "Coin Rush active: 2x plot coins"
	end
	return false, "Offer unavailable"
end

StorePurchase.OnServerInvoke = guard("StorePurchase", function(s, kind: any, key: any)
	if type(kind) ~= "string" or not RemoteContract.StoreKinds[kind] or type(key) ~= "string" or #key > 40 then
		return false, "Invalid request"
	end
	if kind == "Pass" then
		local pass = MonetizationConfig.getPass(key)
		if pass and s.passes[pass.key] then
			return false, "You already own this"
		end
		return market:promptPass(s.player, key)
	elseif kind == "Product" then
		if not s.canSave then
			return false, "Purchases need saving to work. Try again later"
		end
		return market:promptProduct(s.player, key)
	elseif kind == "Offer" then
		return buyOffer(s, key)
	end
	return false, "Invalid request"
end)

HatchEgg.OnServerInvoke = guard("HatchEgg", function(s, eggId: any)
	local egg = EggConfig.get(eggId)
	if not egg then
		return false, "Unknown egg"
	end
	local d = s.data
	-- Paid random eggs (none today: eggs cost earn-only Paw Tokens) would be gated by
	-- PolicyService here, failing closed.
	local restricted = if EggConfig.isPaidRandom(egg) then market:paidRandomRestricted(s.player) else false
	local can, why = EggConfig.hatchCheck(egg, { PawTokens = d.pawTokens, Gems = d.gems }, restricted)
	if not can then
		return false, why
	end
	if egg.currency == "Gems" and s.receiptBusy > 0 then
		return false, "Finishing your last purchase..."
	end
	if Inventory.isFull(d, capacity(s)) then
		return false, "Your backpack is full"
	end
	if egg.currency == "Gems" then
		d.gems -= egg.cost
	else
		d.pawTokens -= egg.cost
	end
	local species = EggConfig.pick(egg, rng:NextNumber())
	local rec, newSpecies = addPet(s, species, "Normal", "Normal")
	d.stats.eggsHatched += 1
	markFull(s)
	local rarity, rarityIndex = GameMath.overallRarity(rec)
	CatchEffect:FireClient(s.player, {
		kind = "hatch",
		source = "egg",
		eggId = egg.id,
		pet = rec,
		rarity = rarity,
		rarityIndex = rarityIndex,
		income = GameMath.petIncome(rec),
		newSpecies = newSpecies,
	})
	local pet = PetConfig.get(species)
	return true, "Hatched " .. (if pet then pet.name else "a pet")
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
		passes = {},
		receiptBusy = 0,
		pendingReceipts = {},
		paidRandomRestricted = true,
		leaving = false,
		released = false,
	}
	-- Pass ownership and policy are read server-side before the first sync; failures
	-- fail closed (not owned / restricted).
	s.passes = market:ownedPasses(player)
	s.paidRandomRestricted = market:paidRandomRestricted(player)
	if not player.Parent then
		return
	end
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

	-- Offline earnings only for real, loaded saves (never for fresh fallback data).
	local offline = 0
	if canSave and data.lastOnline > 0 then
		offline = Progression.offlineEarnings(s.income, os.time() - data.lastOnline, UpgradeConfig.offlineBonusSeconds(data.upgrades))
		data.coins += offline
	end
	checkQuests(s)
	sync(s)
	WeatherEvent:FireClient(player, weather:snapshot())
	if offline > 0 then
		notifyReward(s, "WELCOME BACK!", "Your pets earned coins while you were away", offline, "Green")
	end
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
	s.leaving = true
	for _, c in s.connections do
		c:Disconnect()
	end
	table.clear(s.connections)
	plots:release(player)
	market:forget(player)
	saveSession(s, true)
	sessions[player] = nil
end

------------------------------------------------------------------ purchases

local receipts = Receipts.new({
	findSession = function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		local found = if player then sessions[player] else nil
		-- A leaving player's save is being released: let Roblox retry on their next join.
		return if found and not found.leaving then found :: any else nil
	end,
	isPresent = function(userId: number)
		return Players:GetPlayerByUserId(userId) ~= nil
	end,
	save = function(rs: any)
		return saveSession(rs :: Session)
	end,
	onGranted = function(rs: any, product)
		local session = rs :: Session
		markFull(session)
		notifyReward(session, "Purchase complete", string.format("+%d Gems", product.gems), 0, "Green", 0, false)
	end,
	wait = function(t: number)
		task.wait(t)
	end,
	now = os.time,
})

-- The single ProcessReceipt callback for the whole game. Grants are only ever made here.
MarketplaceService.ProcessReceipt = function(info)
	local ok, decision = pcall(receipts.process, receipts, info)
	if ok and decision == "Granted" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not ok then
		warn("[SnackForce] ProcessReceipt error:", decision)
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Pass purchases made in this server: re-verify ownership server-side before applying.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	local s = sessions[player]
	local pass = MonetizationConfig.passById(passId)
	if not (s and pass and wasPurchased) then
		return
	end
	if market:ownsPass(player, pass) then
		s.passes[pass.key] = true
		refreshPlot(s)
		markFull(s)
		notifyReward(s, "Pass unlocked", pass.name, 0, "Green", 0, true)
	end
end)

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
		local nowUnix = os.time()
		for player, s in sessions do
			local rush = s.data.boosts.CoinRush
			if rush and rush > 0 and rush <= nowUnix then
				(s.data.boosts :: any).CoinRush = nil
				refreshPlot(s)
				s.dirtyFull = true
			end
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

-- Batched state replication (at most 4x per second per player). Quests are evaluated
-- here because every stat change marks the session dirty.
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, s in sessions do
			if s.dirtyFull or s.dirtyStats then
				local ok, err = pcall(function()
					checkQuests(s)
					sync(s)
				end)
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
			if s.data.settings.AutoThrow and autoThrowAvailable(s) and now - s.lastThrow >= GameConfig.AutoThrowInterval then
				local ok, err = pcall(performThrow :: any, s, GameConfig.AutoThrowCharge, false)
				if not ok then
					warn("[SnackForce] auto-throw failed:", err)
					s.lastThrow = now
				end
			end
		end
	end
end)

-- Hub leaderboard: best throws among players in this server.
task.spawn(function()
	while true do
		local rows = {}
		for player, s in sessions do
			table.insert(rows, { name = player.DisplayName, best = s.data.bestDistance })
		end
		table.sort(rows, function(a, b)
			return a.best > b.best
		end)
		for i, line in world.leaderboardLines do
			local r = rows[i]
			line.Text = if r then string.format("%d. %s  -  %sm", i, r.name, GameMath.formatNumber(r.best)) else string.format("%d. ---", i)
		end
		task.wait(GameConfig.LeaderboardInterval)
	end
end)

-- Autosave every 60 seconds.
task.spawn(function()
	while true do
		task.wait(GameConfig.AutosaveInterval)
		for _, s in sessions do
			if not s.leaving then
				task.spawn(saveSession, s)
			end
		end
	end
end)

-- Robux prices for configured offers: fetched at start, retried quickly while any are
-- still loading or errored, then refreshed every 10 minutes. Clients get the new
-- catalog with their next full sync. With every id unset this makes no requests.
task.spawn(function()
	while true do
		local ok, err = pcall(function()
			market:refreshPrices()
		end)
		if not ok then
			warn("[SnackForce] price refresh failed:", err)
		end
		for _, s in sessions do
			markFull(s)
		end
		task.wait(if market:needsRefresh() then 30 else 600)
	end
end)

game:BindToClose(function()
	weather:stop()
	if RunService:IsStudio() and not DataService.isAvailable() then
		return
	end
	-- Final releasing save for everyone: it waits for any in-flight save, then drops the
	-- session lock so players can load straight away on the server they move to.
	local pending = 0
	for _, s in sessions do
		pending += 1
		task.spawn(function()
			s.leaving = true
			saveSession(s, true)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

print(string.format("[SnackForce] Server ready - world built with %d parts, %d plots", world.partCount, #world.plots))
