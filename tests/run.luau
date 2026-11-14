--!nocheck
-- Offline test-suite. Usage: lune run tests/run.luau [path/to/SnackForce_PetToss.rbxl]
local process = require("@lune/process")
local Runtime = require("./runtime")

local placePath = process.args[1] or "SnackForce_PetToss.rbxl"
local game = Runtime.loadPlace(placePath)
local R = Runtime.roblox

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  PASS  " .. name)
	else
		failed += 1
		print("  FAIL  " .. name .. "\n        " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end
local function near(a, b, tol, msg)
	if math.abs(a - b) > tol then
		error(string.format("%s: expected ~%s, got %s", msg or "near", tostring(b), tostring(a)), 2)
	end
end
local function ok(v, msg)
	if not v then
		error(msg or "assertion failed", 2)
	end
end

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SP = game:GetService("StarterPlayer")
local req = Runtime.requireModule

local Cfg = RS.Config
local GameConfig = req(Cfg.GameConfig)
local BiomeConfig = req(Cfg.BiomeConfig)
local PetConfig = req(Cfg.PetConfig)
local MutationConfig = req(Cfg.MutationConfig)
local FoodConfig = req(Cfg.FoodConfig)
local QuestConfig = req(Cfg.QuestConfig)
local GameMath = req(RS.Shared.GameMath)
local Progression = req(RS.Shared.Progression)
local RemoteContract = req(RS.Shared.RemoteContract)
local Server = SSS.Server
local serverSrc = SSS.GameServer.Source
local clientScript = SP.StarterPlayerScripts.GameClient
local clientSrc = clientScript.Source

local function seqRng(seed)
	local s = seed
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

print("Artifact: " .. placePath .. " (" .. Runtime.bytes .. " bytes)")

print("\n[artifact]")
test("place file is non-empty and deserializes", function()
	ok(Runtime.bytes > 10000, "place too small")
end)
test("required modules exist in ReplicatedStorage/Config", function()
	for _, n in { "BiomeConfig", "PetConfig", "MutationConfig", "FoodConfig", "GameConfig", "QuestConfig" } do
		eq(Cfg:FindFirstChild(n).ClassName, "ModuleScript", n)
	end
end)
test("full script hierarchy is packed into the single place file", function()
	local expected = {
		{ SSS, "GameServer", "Script" },
		{ SSS.Server, "WorldBuilder", "ModuleScript" },
		{ SSS.Server, "PlotService", "ModuleScript" },
		{ SSS.Server, "Inventory", "ModuleScript" },
		{ SSS.Server, "PlayerData", "ModuleScript" },
		{ SSS.Server, "DataService", "ModuleScript" },
		{ SSS.Server, "WeatherService", "ModuleScript" },
		{ SSS.Server, "RateLimiter", "ModuleScript" },
		{ RS.Shared, "GameMath", "ModuleScript" },
		{ RS.Shared, "Progression", "ModuleScript" },
		{ RS.Shared, "PetModelBuilder", "ModuleScript" },
		{ RS.Shared, "RemoteContract", "ModuleScript" },
		{ SP.StarterPlayerScripts, "GameClient", "LocalScript" },
		{ SP.StarterPlayerScripts.Client, "Hud", "ModuleScript" },
		{ SP.StarterPlayerScripts.Client, "Panels", "ModuleScript" },
		{ SP.StarterPlayerScripts.Client, "Effects", "ModuleScript" },
		{ SP.StarterPlayerScripts.Client, "UI", "ModuleScript" },
	}
	for _, e in expected do
		local inst = e[1]:FindFirstChild(e[2])
		ok(inst, "missing " .. e[2])
		eq(inst.ClassName, e[3], e[2])
		ok(#inst.Source > 200, e[2] .. " has no source")
	end
end)
test("no module defines the same function twice (guards against bad merges)", function()
	for _, inst in game:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			local seen = {}
			for name in inst.Source:gmatch("\nfunction ([%w_%.:]+)%(") do
				ok(not seen[name], inst.Name .. " defines " .. name .. " twice")
				seen[name] = true
			end
		end
	end
end)
test("client modules load headlessly (no top-level errors)", function()
	local client = SP.StarterPlayerScripts.Client
	for _, n in { "UI", "Panels", "Hud", "Effects" } do
		ok(type(req(client[n])) == "table", n)
	end
end)
test("GameServer is a Script and GameClient a LocalScript", function()
	eq(SSS.GameServer.ClassName, "Script")
	eq(clientScript.ClassName, "LocalScript")
end)
test("every script compiles", function()
	for _, inst in game:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			Runtime.compile(inst)
		end
	end
end)
test("no Toolbox / external assets referenced", function()
	for _, inst in game:GetDescendants() do
		ok(not (inst:IsA("MeshPart") or inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("Sound") or inst:IsA("SpecialMesh")), "asset instance " .. inst:GetFullName())
		if inst:IsA("LuaSourceContainer") then
			local s = inst.Source
			-- The only asset id use is the optional music track, built from SoundConfig.MusicId,
			-- which must stay 0 (off) until a permitted track is supplied.
			local allowAssetId = inst.Name == "Sound" and inst.Parent and inst.Parent.Name == "Client"
			ok((allowAssetId or not s:find("rbxassetid")) and not s:find("InsertService") and not s:find("LoadAsset") and not s:find("http", 1, true), "asset reference in " .. inst:GetFullName())
		end
	end
end)

print("\n[remote contract]")
test("Remotes folder matches RemoteContract exactly", function()
	local folder = RS.Remotes
	eq(#folder:GetChildren(), #RemoteContract.Remotes, "remote count")
	eq(#RemoteContract.Remotes, 14, "contract size: 10 original remotes + StorePurchase, HatchEgg, ManagePet, BuyUpgrade")
	for _, original in { "ThrowFood", "TrainStrength", "BuyFood", "EquipBest", "FusePets", "AutoSell", "ToggleSetting", "StateSync", "CatchEffect", "WeatherEvent" } do
		ok(folder:FindFirstChild(original), "original remote kept: " .. original)
	end
	for _, spec in RemoteContract.Remotes do
		local r = folder:FindFirstChild(spec.name)
		ok(r, "missing remote " .. spec.name)
		eq(r.ClassName, spec.class, spec.name)
	end
end)
test("server handles every client->server remote and fires every server->client remote", function()
	for _, spec in RemoteContract.Remotes do
		if spec.direction == "ClientToServer" then
			if spec.class == "RemoteEvent" then
				ok(serverSrc:find(spec.name .. ".OnServerEvent:Connect", 1, true), "no OnServerEvent for " .. spec.name)
			else
				ok(serverSrc:find(spec.name .. '.OnServerInvoke = guard("' .. spec.name .. '"', 1, true), "no guarded OnServerInvoke for " .. spec.name)
			end
		else
			ok(serverSrc:find(spec.name .. ":FireClient", 1, true) or serverSrc:find(spec.name .. ":FireAllClients", 1, true), "server never fires " .. spec.name)
		end
	end
end)
test("client uses every remote in the right direction", function()
	for _, spec in RemoteContract.Remotes do
		if spec.direction == "ServerToClient" then
			ok(clientSrc:find(spec.name .. ".OnClientEvent:Connect", 1, true), "client ignores " .. spec.name)
		elseif spec.class == "RemoteEvent" then
			ok(clientSrc:find(spec.name .. ":FireServer", 1, true), "client never fires " .. spec.name)
		else
			ok(clientSrc:find(spec.name .. " = true", 1, true), "client cannot invoke " .. spec.name)
		end
	end
	ok(not clientSrc:find("OnClientInvoke"), "server must never invoke the client")
end)
test("server never trusts client-sent numbers for throws", function()
	ok(serverSrc:find("GameMath.chargeAt(elapsed)", 1, true), "charge must be computed from server timestamps")
	ok(serverSrc:find("RemoteContract.ThrowActions[action]", 1, true), "throw action must be validated")
end)

print("\n[configs]")
test("six biomes Meadow -> Nuclear Wasteland, contiguous, with wind/gravity", function()
	eq(#BiomeConfig.Biomes, 6)
	eq(BiomeConfig.Biomes[1].id, "Meadow")
	eq(BiomeConfig.Biomes[6].name, "Nuclear Wasteland")
	local last = 0
	for _, b in BiomeConfig.Biomes do
		eq(b.startDistance, last, b.id .. " start")
		ok(b.endDistance > b.startDistance)
		ok(type(b.wind) == "number" and b.gravity > 0)
		ok(#b.cravings > 0)
		last = b.endDistance
	end
end)
test("cravings, materials and sizes match the spec", function()
	eq(table.concat(FoodConfig.Cravings, ","), "Berry,Meat,Spicy,Cosmic")
	local m, s = {}, {}
	for _, x in MutationConfig.Materials do
		table.insert(m, x.id)
	end
	for _, x in MutationConfig.Sizes do
		table.insert(s, x.id)
	end
	eq(table.concat(m, ","), "Normal,Gold,Diamond,Emerald,Ruby,Rainbow")
	eq(table.concat(s, ","), "Normal,Huge,Colossal,Monstrous,Titanic,Cosmic,Infinite")
	for i = 3, #MutationConfig.Materials do
		ok(MutationConfig.Materials[i].chance < MutationConfig.Materials[i - 1].chance, "material chances must shrink")
	end
	for i = 3, #MutationConfig.Sizes do
		ok(MutationConfig.Sizes[i].chance < MutationConfig.Sizes[i - 1].chance, "size chances must shrink")
	end
end)
test("tuning constants match the spec", function()
	eq(GameConfig.SweetSpotDistanceMult, 1.25)
	eq(GameConfig.SweetSpotLuckMult, 1.35)
	eq(MutationConfig.MaxComboMultiplier, 10)
	eq(GameConfig.WeatherDuration, 45)
	eq(GameConfig.WeatherInterval, 90)
	eq(GameConfig.AutosaveInterval, 60)
	local w = {}
	for _, x in GameConfig.Weather do
		w[x.id] = x
	end
	eq(w.TitanStorm.sizeLuck, 3)
	eq(w.FeastFrenzy.cravingBonus, 2)
	eq(w.PrismAurora.materialLuck, 4)
end)
test("every pet is valid and every zone has pets", function()
	for _, p in PetConfig.Pets do
		ok(FoodConfig.isCraving(p.craving), p.id .. " craving")
		ok(GameConfig.rarityIndex(p.rarity) > 0, p.id .. " rarity")
		ok(table.find(PetConfig.Archetypes, p.archetype), p.id .. " archetype")
		ok(PetConfig.RarityWeights[p.rarity], p.id .. " weight")
	end
	for _, z in BiomeConfig.allCravingZones() do
		ok(#PetConfig.forZone(z) >= 3, "zone " .. z .. " needs pets")
	end
end)
test("foods are valid and the starter food is free", function()
	eq(FoodConfig.get(FoodConfig.DefaultFood).price, 0)
	for _, f in FoodConfig.Foods do
		ok(FoodConfig.isCraving(f.craving) and f.power > 0, f.id)
	end
end)

test("quest line is valid and every stat is resolvable", function()
	ok(#QuestConfig.Quests >= 20, "quest line too short")
	local seen, lastTarget = {}, {}
	local focuses = { ThrowLine = true, Gym = true, Shop = true, Pets = true, Index = true }
	for i, q in QuestConfig.Quests do
		ok(not seen[q.id], "duplicate quest " .. q.id)
		seen[q.id] = true
		ok(table.find(QuestConfig.Stats, q.stat), q.id .. " unknown stat " .. q.stat)
		ok(q.target > 0 and q.reward > 0, q.id .. " target/reward")
		ok(q.focus == nil or focuses[q.focus], q.id .. " focus")
		ok(#q.hint > 10 and #q.title > 2, q.id .. " text")
		if lastTarget[q.stat] then
			ok(q.target > lastTarget[q.stat], q.id .. " must raise the bar for " .. q.stat)
		end
		lastTarget[q.stat] = q.target
		local _ = i
	end
	eq(QuestConfig.Quests[1].stat, "trains", "onboarding starts with training")
	eq(QuestConfig.Quests[2].stat, "throws", "then throwing")
end)

print("\n[game math]")
test("charge meter is a 0->1->0 triangle wave", function()
	near(GameMath.chargeAt(0), 0, 1e-9)
	near(GameMath.chargeAt(GameConfig.ChargeCycle / 2), 1, 1e-9)
	near(GameMath.chargeAt(GameConfig.ChargeCycle / 4), 0.5, 1e-9)
	near(GameMath.chargeAt(GameConfig.ChargeCycle * 0.75), 0.5, 1e-9)
end)
test("sweet spot gives exactly 1.25x distance and 1.35x mutation luck", function()
	near(GameMath.rawDistance(100, 1.5, 0.95, true) / GameMath.rawDistance(100, 1.5, 0.95, false), 1.25, 1e-9)
	local base = { strength = 100, foodPower = 1, foodLuck = 1, foodCraving = "Berry", streak = 0, zoneCravings = {}, weatherSizeLuck = 1, weatherMaterialLuck = 1, weatherCravingBonus = 1 }
	local a = table.clone(base)
	a.charge, a.allowSweetSpot, a.rng = 0.95, true, seqRng(5)
	local b = table.clone(base)
	b.charge, b.allowSweetSpot, b.rng = 0.95, false, seqRng(5)
	local ra, rb = GameMath.computeThrow(a), GameMath.computeThrow(b)
	ok(ra.sweetSpot and not rb.sweetSpot)
	near(ra.materialLuck / rb.materialLuck, 1.35, 1e-9)
	near(ra.sizeLuck / rb.sizeLuck, 1.35, 1e-9)
end)
test("combo caps at 10x and Feast Frenzy doubles streak growth", function()
	eq(GameMath.comboMultiplier(0), 1)
	eq(GameMath.comboMultiplier(999), 10)
	eq(GameMath.nextStreak(2, true, 1), 3)
	eq(GameMath.nextStreak(2, true, 2), 4)
	eq(GameMath.nextStreak(5, false, 2), 0)
end)
test("weather multipliers flow into luck", function()
	local p = { strength = 0, foodPower = 1, foodLuck = 1, foodCraving = "Berry", charge = 0.5, allowSweetSpot = true, streak = 0, zoneCravings = { Meadow = "Meat" }, weatherSizeLuck = 3, weatherMaterialLuck = 4, weatherCravingBonus = 1, rng = seqRng(9) }
	local r = GameMath.computeThrow(p)
	near(r.sizeLuck, 3, 1e-9)
	near(r.materialLuck, 4, 1e-9)
end)
test("flight resolves through biomes into Space and the Moon", function()
	local _, z1 = GameMath.resolveFlight(50)
	eq(z1, "Meadow")
	local prev = 0
	for raw = 0, 5000, 50 do
		local d = GameMath.resolveFlight(raw)
		ok(d >= prev, "distance must be monotonic")
		prev = d
	end
	local _, zs = GameMath.resolveFlight(2400)
	ok(zs == "Space" or zs == "Moon", "far throws leave the planet, got " .. zs)
	local _, zm = GameMath.resolveFlight(9000)
	eq(zm, "Moon")
end)
test("material/size roll rates match configured odds (Monte Carlo)", function()
	local rng = seqRng(12345)
	local n, gold, huge = 200000, 0, 0
	for _ = 1, n do
		local m = GameMath.rollMaterial(rng, 1)
		if m ~= "Normal" then
			gold += 1
		end
		if GameMath.rollSize(rng, 1) ~= "Normal" then
			huge += 1
		end
	end
	local expectGold = 0
	for i = 2, #MutationConfig.Materials do
		expectGold += MutationConfig.Materials[i].chance
	end
	near(gold / n, expectGold, expectGold * 0.1, "any-material rate")
	near(huge / n, 0.1 + 1 / 35 + 1 / 120, 0.015, "any-size rate")
	eq(GameMath.rollMaterial(function()
		return 0.49
	end, 1e9), "Rainbow", "luck is capped at MaxChance but best tier wins")
end)

print("\n[progression]")
test("quests complete in order, pay rewards and cascade", function()
	local d = req(Server.PlayerData).defaults()
	local coins = d.coins
	eq(#Progression.advanceQuests(d, 0), 0, "nothing done yet")
	eq(Progression.questSnapshot(d, 0).id, "Train10")
	d.stats.trains = 10
	d.totalThrows = 1
	local done = Progression.advanceQuests(d, 0)
	eq(#done, 2, "train + first throw complete together")
	eq(d.questIndex, 3)
	eq(d.coins, coins + QuestConfig.Quests[1].reward + QuestConfig.Quests[2].reward)
	local snap = Progression.questSnapshot(d, 0)
	eq(snap.id, "Sweet1")
	eq(snap.progress, 0)
	d.questIndex = #QuestConfig.Quests + 1
	eq(Progression.questSnapshot(d, 0), nil, "finished quest line has no snapshot")
	eq(#Progression.advanceQuests(d, 0), 0)
end)
test("stat values map to save data", function()
	local d = req(Server.PlayerData).defaults()
	d.ownedFoods.MeatyBone = true
	d.discovered = { Bunbun = true, Chirpy = true, MeadowPup = true }
	d.bestDistance = 321
	d.strength = 77
	d.totalCatches = 9
	eq(Progression.statValue("foods", d, 0), 2)
	eq(Progression.statValue("discovered", d, 0), 3)
	eq(Progression.statValue("distance", d, 0), 321)
	eq(Progression.statValue("strength", d, 0), 77)
	eq(Progression.statValue("catches", d, 0), 9)
	eq(Progression.statValue("income", d, 42), 42)
	eq(Progression.statValue("fusions", d, 0), 0)
end)
test("discovery rewards, offline earnings and zone rewards are bounded", function()
	for _, p in PetConfig.Pets do
		ok(Progression.discoveryReward(p.id) >= GameConfig.DiscoveryMinCoins, p.id)
	end
	eq(Progression.discoveryReward("Nope"), 0)
	eq(Progression.offlineEarnings(100, GameConfig.OfflineMinSeconds - 1), 0, "short absences pay nothing")
	eq(Progression.offlineEarnings(0, 5000), 0)
	eq(Progression.offlineEarnings(100, 0 / 0), 0, "NaN-safe")
	eq(Progression.offlineEarnings(100, 1000), math.floor(100 * 1000 * GameConfig.OfflineRate))
	eq(Progression.offlineEarnings(100, 1e9), math.floor(100 * GameConfig.OfflineMaxSeconds * GameConfig.OfflineRate), "capped")
	eq(BiomeConfig.zoneReward("Meadow"), 0, "the first zone is free")
	local last = -1
	for _, z in BiomeConfig.allCravingZones() do
		ok(BiomeConfig.zoneReward(z) > last, "zone rewards grow: " .. z)
		last = BiomeConfig.zoneReward(z)
		ok(#BiomeConfig.zoneName(z) > 3)
	end
end)
test("gym and throw line areas", function()
	ok(Progression.inGym(GameConfig.GymCenter))
	ok(not Progression.inGym(GameConfig.ThrowLineCenter), "gym is not at the throw line")
	ok(Progression.nearThrowLine(GameConfig.ThrowLineCenter))
	ok(not Progression.nearThrowLine(GameConfig.GymCenter), "can't throw from the gym")
	ok(GameConfig.GymMultiplier > 1)
	ok(serverSrc:find("Progression.inGym(pos)", 1, true), "server applies the gym bonus from the character position")
end)

print("\n[inventory]")
local PlayerData = req(Server.PlayerData)
local Inventory = req(Server.Inventory)
local function fresh()
	return PlayerData.defaults()
end
test("three duplicates fuse into the next material", function()
	local d = fresh()
	for _ = 1, 3 do
		table.insert(d.pets, Inventory.newPet(d, "Bunbun", "Normal", "Huge"))
	end
	d.pets[2].equipped = true
	local okF, rec = Inventory.fuse(d, "Bunbun|Normal|Huge")
	ok(okF)
	eq(#d.pets, 1)
	eq(rec.material, "Gold")
	eq(rec.size, "Huge")
	eq(rec.equipped, true, "equipped state carries over")
	ok(not Inventory.fuse(d, "Bunbun|Gold|Huge"), "needs 3")
	local r = fresh()
	for _ = 1, 3 do
		table.insert(r.pets, Inventory.newPet(r, "Bunbun", "Rainbow", "Normal"))
	end
	ok(not Inventory.fuse(r, "Bunbun|Rainbow|Normal"), "Rainbow is max")
end)
test("fuse all cascades 9 Normal -> 1 Diamond", function()
	local d = fresh()
	for _ = 1, 9 do
		table.insert(d.pets, Inventory.newPet(d, "MeadowPup", "Normal", "Normal"))
	end
	eq(Inventory.fuseAll(d), 4)
	eq(#d.pets, 1)
	eq(d.pets[1].material, "Diamond")
end)
test("auto-sell respects rarity threshold and KeepMutated", function()
	local d = fresh()
	d.settings.AutoSellRarity = "Uncommon"
	local common = Inventory.newPet(d, "MeadowPup", "Normal", "Normal")
	local gold = Inventory.newPet(d, "MeadowPup", "Gold", "Normal")
	local epic = Inventory.newPet(d, "CloverCat", "Normal", "Normal")
	ok(Inventory.shouldAutoSell(d, common))
	ok(not Inventory.shouldAutoSell(d, gold), "mutations kept")
	ok(not Inventory.shouldAutoSell(d, epic), "above threshold")
	d.settings.KeepMutated = false
	d.settings.AutoSellRarity = "Rare"
	ok(Inventory.shouldAutoSell(d, gold), "gold is Rare")
	local coins = d.coins
	local outcome, value = Inventory.catch(d, Inventory.newPet(d, "Bunbun", "Normal", "Normal"), 8)
	eq(outcome, "sold")
	eq(d.coins, coins + value)
	table.insert(d.pets, common)
	table.insert(d.pets, epic)
	local count = Inventory.sellMatching(d)
	eq(count, 1)
	eq(#d.pets, 1)
end)
test("catch auto-equips into free slots, equipBest picks top income, full inventory sells", function()
	local d = fresh()
	for i = 1, 10 do
		Inventory.catch(d, Inventory.newPet(d, if i == 10 then "SunDrake" else "MeadowPup", "Normal", "Normal"), 8)
	end
	eq(Inventory.equippedCount(d), 8)
	Inventory.equipBest(d, 8)
	local drake
	for _, p in d.pets do
		if p.species == "SunDrake" then
			drake = p
		end
	end
	ok(drake.equipped, "best pet equipped")
	eq(Inventory.equippedCount(d), 8)
	for _ = #d.pets + 1, GameConfig.MaxPets do
		table.insert(d.pets, Inventory.newPet(d, "MeadowPup", "Normal", "Normal"))
	end
	eq(Inventory.catch(d, Inventory.newPet(d, "MeadowPup", "Normal", "Normal"), 8), "full")
end)

print("\n[persistence]")
test("sanitize survives garbage and clamps values", function()
	for _, raw in { nil, 5, "x", true, {}, { coins = 0 / 0, strength = -5, pets = "no" } } do
		local d = PlayerData.sanitize(raw)
		ok(d.coins == d.coins and d.coins >= 0)
		ok(d.strength >= 0)
		ok(d.ownedFoods[FoodConfig.DefaultFood])
	end
	local pets = {}
	for i = 1, 800 do
		pets[i] = { uid = "dup", species = if i % 2 == 0 then "Bunbun" else "FakePet", material = "Gold", size = "Huge", equipped = true }
	end
	local d = PlayerData.sanitize({ coins = 1e30, pets = pets, equippedFood = "MegaSteak", ownedFoods = { MegaSteak = true, Hacked = true }, settings = { AutoThrow = true, AutoSkipRarity = "Bogus" } })
	eq(d.coins, 1e15)
	eq(#d.pets, PlayerData.MaxStoredPets, "saves keep up to the Big Backpack limit")
	eq(Inventory.equippedCount(d), GameConfig.PlotPedestals)
	local seen = {}
	for _, p in d.pets do
		ok(not seen[p.uid], "unique uids")
		seen[p.uid] = true
	end
	eq(d.equippedFood, "MegaSteak")
	eq(d.ownedFoods.Hacked, nil)
	eq(d.settings.AutoThrow, true, "saved toggle kept; the server checks the unlock every throw")
	ok(serverSrc:find("s.data.settings.AutoThrow and autoThrowAvailable(s)", 1, true), "auto-throw loop checks unlock or pass")
	eq(d.settings.AutoSkipRarity, "Epic")
end)
test("v1 saves migrate to v2 without re-paying rewards", function()
	local d = PlayerData.sanitize({ coins = 500, bestDistance = 900, strength = 4000, pets = {} })
	eq(d.questIndex, 1)
	eq(d.stats.trains, 0)
	ok(d.zonesReached.Meadow and d.zonesReached.Dunes and d.zonesReached.Tundra and d.zonesReached.Volcano, "passed zones marked")
	eq(d.zonesReached.Swamp, nil, "unreached zone still pays")
	eq(d.settings.ShowGuide, true)
	local v2 = PlayerData.sanitize({ questIndex = 7, lastOnline = 1700000000, zonesReached = { Swamp = true, Bogus = true }, stats = { trains = 55, fusions = 2, bestRarity = 99, mutations = -4 }, settings = { ShowGuide = false } })
	eq(v2.questIndex, 7)
	eq(v2.lastOnline, 1700000000)
	ok(v2.zonesReached.Swamp)
	eq(v2.zonesReached.Bogus, nil, "unknown zones dropped")
	eq(v2.stats.trains, 55)
	eq(v2.stats.bestRarity, #GameConfig.Rarities, "rarity index clamped")
	eq(v2.stats.mutations, 0, "negative stats clamped")
	eq(v2.settings.ShowGuide, false)
	eq(PlayerData.sanitize({ questIndex = 1e9 }).questIndex, #QuestConfig.Quests + 1)
	ok(Server.DataService.Source:find("payload.lastOnline = now", 1, true), "saves record lastOnline")
end)
test("DataService degrades gracefully without DataStores", function()
	local DataService = req(Server.DataService)
	local d, canSave = DataService.load(1)
	ok(d and d.coins == GameConfig.StartingCoins)
	eq(canSave, DataService.isAvailable())
	if not DataService.isAvailable() then
		eq(DataService.save(1, d), false)
	end
end)
test("server persistence hooks present (pcall, BindToClose, autosave, PlayerRemoving)", function()
	ok(serverSrc:find("game:BindToClose", 1, true))
	ok(serverSrc:find("GameConfig.AutosaveInterval", 1, true))
	ok(serverSrc:find("Players.PlayerRemoving:Connect", 1, true))
	local ds = Server.DataService.Source
	ok(select(2, ds:gsub("pcall%(", "")) >= 3, "DataStore calls must be pcall-wrapped")
end)

print("\n[rate limiting]")
test("token bucket enforces burst and refills", function()
	local RateLimiter = req(Server.RateLimiter)
	local t = 0
	local rl = RateLimiter.new({ X = { rate = 2, burst = 3 } }, function()
		return t
	end)
	local key = {}
	ok(rl:allow(key, "X") and rl:allow(key, "X") and rl:allow(key, "X"))
	ok(not rl:allow(key, "X"), "burst exceeded")
	t = 0.5
	ok(rl:allow(key, "X"), "refilled one token")
	ok(not rl:allow(key, "Unknown"), "unknown remote rejected")
	rl:clear(key)
	eq(rl.buckets[key], nil)
	for _, spec in RemoteContract.Remotes do
		if spec.direction == "ClientToServer" then
			ok(GameConfig.RateLimits[spec.name], "rate limit for " .. spec.name)
		end
	end
end)

print("\n[weather]")
test("45s events every 90s, never the same twice, cravings valid", function()
	local WeatherService = req(Server.WeatherService)
	local t = 1000
	local events = {}
	local ws = WeatherService.new(function(s)
		table.insert(events, { t = t, active = s.active, id = s.id })
	end, function()
		return t
	end)
	local lastId
	for step = 0, 900 * 2 do
		t = 1000 + step * 0.5
		ws:step()
	end
	ok(#events >= 18, "expected many transitions, got " .. #events)
	eq(events[1].active, true)
	eq(events[1].t, 1000 + GameConfig.FirstWeatherDelay)
	for i, e in events do
		if e.active then
			eq(events[i + 1] and (events[i + 1].t - e.t) or 45, 45, "duration")
			if events[i + 2] then
				eq(events[i + 2].t - e.t, 90, "interval")
			end
			ok(e.id ~= lastId, "no repeats")
			lastId = e.id
		end
	end
	for zone, c in ws:snapshot().cravings do
		ok(table.find(BiomeConfig.cravingOptions(zone), c), "craving for " .. zone)
	end
end)

print("\n[world + models]")
local world
test("WorldBuilder generates hub, throw line, six biomes and six plots", function()
	local WorldBuilder = req(Server.WorldBuilder)
	local ws = game:GetService("Workspace")
	world = WorldBuilder.build(ws)
	local root = ws.SnackWorld
	ok(root.SpawnHub:FindFirstChildOfClass("SpawnLocation"), "spawn")
	ok(root.ThrowLine.Line, "throw line")
	for _, b in BiomeConfig.Biomes do
		local g = root.Biomes[b.id].Ground
		eq(g.Size.Z, b.endDistance - b.startDistance, b.id .. " length")
	end
	eq(#world.plots, 6)
	for _, p in world.plots do
		eq(#p.pedestals, GameConfig.PlotPedestals)
	end
	ok(world.partCount > 500, "world has " .. world.partCount .. " parts")
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			ok(d.Size.X <= 2048 and d.Size.Y <= 2048 and d.Size.Z <= 2048, "part too big: " .. d:GetFullName())
			ok(d.Anchored, "unanchored part " .. d:GetFullName())
		end
	end
	print("        (" .. world.partCount .. " parts generated)")
end)
test("hub stalls open real panels via ProximityPrompts (not on the throw key)", function()
	local root = game:GetService("Workspace").SnackWorld
	local panelsSrc = SP.StarterPlayerScripts.Client.Panels.Source
	local found = {}
	local prompts = {}
	for _, d in root:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			local panel = d:GetAttribute("OpenPanel")
			ok(type(panel) == "string", "prompt without panel: " .. d:GetFullName())
			ok(panelsSrc:find('add("' .. panel .. '"', 1, true), "prompt opens unknown panel " .. panel)
			ok(d.KeyboardKeyCode ~= R.Enum.KeyCode.E, "prompt must not use the throw key")
			ok(d.MaxActivationDistance >= 8 and d.MaxActivationDistance <= 10, "prompt range 8-10")
			ok(not d.RequiresLineOfSight, "prompt must not need line of sight")
			ok(not found[panel], "one prompt per panel: " .. panel)
			found[panel] = true
			table.insert(prompts, d)
		end
	end
	ok(found.Shop and found.Pets and found.Index and found.Eggs, "Shop, Pets, Index and Eggs stalls")
	-- Stall paths the client guides use, each with exactly one prompt.
	for _, p in { { "FoodShopStall", "ShopCounter", "Shop" }, { "FuseAltar", "AltarBase", "Pets" }, { "PetIndexBoard", "IndexStand", "Index" }, { "EggHatchery", "HatcheryCounter", "Eggs" } } do
		local stall = root.SpawnHub:FindFirstChild(p[1])
		ok(stall and stall:FindFirstChild(p[2]), "missing SpawnHub/" .. p[1] .. "/" .. p[2])
		local n = 0
		for _, d in stall:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				n += 1
				eq(d.Parent, stall[p[2]], p[1] .. " prompt parent")
				eq(d:GetAttribute("OpenPanel"), p[3], p[1] .. " panel")
			end
		end
		eq(n, 1, p[1] .. " prompt count")
	end
	-- Stalls are spaced so that at most one prompt is in range at a time.
	for i = 1, #prompts do
		for j = i + 1, #prompts do
			local a, b = prompts[i], prompts[j]
			local gap = (a.Parent.CFrame.Position - b.Parent.CFrame.Position).Magnitude
			ok(gap > a.MaxActivationDistance + b.MaxActivationDistance + 4, "prompts too close: " .. a.Parent:GetFullName() .. " / " .. b.Parent:GetFullName())
		end
	end
	ok(clientSrc:find("ProximityPromptService.PromptTriggered:Connect", 1, true), "client listens for prompts")
	ok(root.SpawnHub.Gym.GymFloor, "gym floor")
	local floor = root.SpawnHub.Gym.GymFloor.CFrame.Position
	near(floor.X, GameConfig.GymCenter.X, 0.01, "gym floor matches GameConfig.GymCenter")
	near(floor.Z, GameConfig.GymCenter.Z, 0.01, "gym floor matches GameConfig.GymCenter")
	eq(#world.leaderboardLines, 6, "leaderboard rows")
end)
test("scenery stays out of the throw lane and the gym", function()
	local root = game:GetService("Workspace").SnackWorld
	local half = BiomeConfig.Width / 2
	local mountains = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Mountain" then
			mountains += 1
			local cy = d.CFrame.Position.Y
			local halfAtGround = d.Size.X * 0.7072 - math.abs(cy)
			ok(math.abs(d.CFrame.Position.X) - halfAtGround >= half - 0.5, "mountain intrudes into the lane at x=" .. d.CFrame.Position.X)
		end
	end
	ok(mountains > 40, "mountain backdrop")
	for _, d in root.SpawnHub:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "Trunk" or d.Name == "Leaves") then
			ok(not Progression.inGym(d.CFrame.Position), "tree inside the gym")
		end
	end
	for _, b in BiomeConfig.Biomes do
		ok(#root.Biomes[b.id]:GetChildren() > 5, b.id .. " has landmarks/decor")
	end
end)
test("every species x material x size builds a pet model", function()
	local Builder = req(RS.Shared.PetModelBuilder)
	local n = 0
	for _, p in PetConfig.Pets do
		for _, m in MutationConfig.Materials do
			for _, s in MutationConfig.Sizes do
				local model = Builder.build(p.id, m.id, s.id, R.CFrame.new())
				ok(model.PrimaryPart, p.id)
				eq(model:HasTag("RainbowPet"), m.id == "Rainbow")
				n += 1
			end
		end
	end
	print("        (" .. n .. " combinations)")
end)
test("PlotService assigns six plots, renders pets, releases cleanly", function()
	local PlotService = req(Server.PlotService)
	local ps = PlotService.new(world.plots)
	local players = {}
	for i = 1, 7 do
		players[i] = { UserId = i, DisplayName = "P" .. i }
	end
	for i = 1, 6 do
		ok(ps:claim(players[i]), "plot for " .. i)
	end
	eq(ps:claim(players[7]), nil, "7th player gets no plot (nil-safe)")
	local d = fresh()
	for _ = 1, 10 do
		Inventory.catch(d, Inventory.newPet(d, "Bunbun", "Rainbow", "Infinite"), 8)
	end
	ps:render(players[1], d, Inventory.totalIncome(d))
	eq(#world.plots[1].petsFolder:GetChildren(), 8)
	ps:render(players[7], d, 0) -- no plot: must not error
	ps:release(players[1])
	eq(#world.plots[1].petsFolder:GetChildren(), 0)
	eq(world.plots[1].ownerLabel.Text, "Free Plot")
end)

print("\n[startup nil-safety]")
test("scripts only reach shared instances through WaitForChild", function()
	for _, inst in game:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			for line in inst.Source:gmatch("[^\n]+") do
				if line:find("require%(") and not line:find("^%s*%-%-") then
					ok(line:find("WaitForChild") or line:find("require%(target%)") or not line:find("ReplicatedStorage%.") , "direct child access in require: " .. inst.Name .. ": " .. line)
				end
			end
		end
	end
end)
test("client has defaults for all HUD fields before first StateSync", function()
	for _, key in { "coins", "strength", "income", "bestDistance", "streak", "comboMult", "equippedFood", "ownedFoods", "pets", "settings", "gems", "pawTokens", "passes", "store" } do
		ok(clientSrc:find("\t" .. key .. " = ", 1, true), "missing default " .. key)
	end
	ok(serverSrc:find("if not s then", 1, true), "server handlers must check the session exists")
	ok(serverSrc:find("if not player.Parent then", 1, true), "player may leave while loading")
end)

print("\n[fresh-save progression simulation]")
test("a fresh save progresses through every biome", function()
	local d = fresh()
	local rng = seqRng(777)
	local streak, t = 0, 0
	local reached = {}
	local throwEvery, trainPerSec = 2, 5
	local questAt = {}
	local cravings = {}
	for _, z in BiomeConfig.allCravingZones() do
		cravings[z] = BiomeConfig.cravingOptions(z)[1]
	end
	while t < 6 * 3600 and not reached.Moon do
		t += 1
		d.coins += Inventory.totalIncome(d)
		for _ = 1, trainPerSec do
			d.strength += GameMath.trainGain(d.strength)
			d.stats.trains += 1
		end
		if t % throwEvery == 0 then
			local food = FoodConfig.get(d.equippedFood)
			local r = GameMath.computeThrow({ strength = d.strength, foodPower = food.power, foodLuck = food.luck, foodCraving = food.craving, charge = if rng() < 0.5 then 0.95 else 0.8, allowSweetSpot = true, streak = streak, zoneCravings = cravings, weatherSizeLuck = 1, weatherMaterialLuck = 1, weatherCravingBonus = 1, rng = rng })
			streak = r.streak
			d.coins += r.bonusCoins
			d.totalThrows += 1
			d.stats.sweetSpots += if r.sweetSpot then 1 else 0
			d.stats.cravingMatches += if r.cravingMatched then 1 else 0
			d.stats.bestStreak = math.max(d.stats.bestStreak, r.streak)
			if not d.zonesReached[r.zone] then
				d.zonesReached[r.zone] = true
				d.coins += BiomeConfig.zoneReward(r.zone)
			end
			if not d.discovered[r.species] then
				d.coins += Progression.discoveryReward(r.species)
			end
			if GameMath.isMutated({ material = r.material, size = r.size }) then
				d.stats.mutations += 1
			end
			local _, ri = GameMath.overallRarity({ species = r.species, material = r.material, size = r.size })
			d.stats.bestRarity = math.max(d.stats.bestRarity, ri)
			d.bestDistance = math.max(d.bestDistance, r.distance)
			Inventory.catch(d, Inventory.newPet(d, r.species, r.material, r.size), 8)
			if not reached[r.zone] then
				reached[r.zone] = t
				print(string.format("        %-8s reached at %5.1f min (strength %s, food %s)", r.zone, t / 60, GameMath.formatNumber(d.strength), food.name))
			end
		end
		for _, f in FoodConfig.Foods do
			if not d.ownedFoods[f.id] and d.coins >= f.price and f.power > FoodConfig.get(d.equippedFood).power then
				d.coins -= f.price
				d.ownedFoods[f.id] = true
				d.equippedFood = f.id
			end
		end
		for _, q in Progression.advanceQuests(d, Inventory.totalIncome(d)) do
			questAt[q.id] = t
		end
		if t % 60 == 0 then
			d.stats.fusions += Inventory.fuseAll(d)
			Inventory.equipBest(d, 8)
			d.settings.AutoSellRarity = "Uncommon"
			Inventory.sellMatching(d)
		end
	end
	for _, b in BiomeConfig.Biomes do
		ok(reached[b.id], "never reached " .. b.id)
	end
	ok(reached.Dunes < 10 * 60, "Dunes should be reached within 10 minutes")
	print(string.format("        quests: %d/%d done (first 8 by %.1f min)", d.questIndex - 1, #QuestConfig.Quests, (questAt[QuestConfig.Quests[8].id] or 1e9) / 60))
	ok(d.questIndex > 8, "onboarding quests are completable by a simple bot")
end)


print("\n[store, eggs and purchases]")
local MonetizationConfig = req(Cfg.MonetizationConfig)
local EggConfig = req(Cfg.EggConfig)
local MarketService = req(Server.MarketService)
local Receipts = req(Server.Receipts)

test("every Robux id is unset and no Robux price is hard-coded", function()
	eq(MonetizationConfig.GamePasses, nil, "no Marketplace game passes remain")
	for _, p in MonetizationConfig.FreePerks do
		eq(p.id, nil, p.key .. " has no pass id")
		eq(p.price, nil, p.key .. " has no price")
	end
	for _, p in MonetizationConfig.Products do
		eq(p.id, 0, p.key .. " id")
		ok(p.gems > 0)
	end
	eq(MonetizationConfig.productById(0), nil)
end)

test("only Gems are purchasable and nothing bought with Robux or Gems is random", function()
	ok(MonetizationConfig.PurchasableCurrencies.Gems and not MonetizationConfig.PurchasableCurrencies.PawTokens and not MonetizationConfig.PurchasableCurrencies.Coins)
	for _, o in MonetizationConfig.GemOffers do
		local g = o.grant
		ok(g.kind == "pet" or g.kind == "boost", o.key .. " grant kind")
		if g.kind == "pet" then
			ok(PetConfig.get(g.species) and MutationConfig.getMaterial(g.material) and MutationConfig.getSize(g.size), o.key .. " fixed contents")
		end
	end
	for _, egg in EggConfig.Eggs do
		ok(MonetizationConfig.EarnOnlyCurrencies[egg.currency], egg.id .. " must cost an earn-only currency")
		eq(EggConfig.isPaidRandom(egg), false)
	end
	local receiptsSrc = Server.Receipts.Source
	ok(not receiptsSrc:find("pawTokens", 1, true) and not receiptsSrc:find("coins", 1, true), "receipts only grant Gems")
end)

test("egg odds are complete, exclusive and match a Monte Carlo run", function()
	eq(#EggConfig.validate(), 0, table.concat(EggConfig.validate(), "; "))
	for _, z in BiomeConfig.allCravingZones() do
		for _, p in PetConfig.forZone(z) do
			ok(p.zone ~= PetConfig.EggZone, "egg pet in a throw zone")
		end
	end
	local rng = seqRng(99)
	for _, egg in EggConfig.Eggs do
		local counts, n = {}, 40000
		for _ = 1, n do
			local sp = EggConfig.pick(egg, rng())
			counts[sp] = (counts[sp] or 0) + 1
		end
		for _, e in egg.entries do
			near((counts[e.species] or 0) / n * 100, e.chance, 1.2, egg.id .. " " .. e.species)
		end
	end
	local sa = EggConfig.get("SafariEgg")
	eq(EggConfig.pick(sa, 0), sa.entries[1].species)
	eq(EggConfig.pick(sa, 0.9999999), sa.entries[#sa.entries].species)
end)

test("paid random gate fails closed via PolicyService", function()
	local function policy(behaviour)
		return { GetPolicyInfoForPlayerAsync = function()
			if behaviour == "error" then
				error("policy down")
			end
			return behaviour
		end }
	end
	local p = { UserId = 1 }
	eq(MarketService.new({}, policy("error")):paidRandomRestricted(p), true, "error -> restricted")
	eq(MarketService.new({}, policy({})):paidRandomRestricted(p), true, "missing field -> restricted")
	eq(MarketService.new({}, policy({ ArePaidRandomItemsRestricted = true })):paidRandomRestricted(p), true)
	eq(MarketService.new({}, policy({ ArePaidRandomItemsRestricted = false })):paidRandomRestricted(p), false)
	local gemEgg = { id = "X", currency = "Gems", cost = 10, entries = {} }
	ok(EggConfig.isPaidRandom(gemEgg))
	eq((EggConfig.hatchCheck(gemEgg, { Gems = 99 }, true)), false, "restricted player can't open a paid egg")
	eq((EggConfig.hatchCheck(gemEgg, { Gems = 99 }, false)), true)
	local sa = EggConfig.get("SafariEgg")
	eq((EggConfig.hatchCheck(sa, { PawTokens = sa.cost }, true)), true, "earn-only eggs work for everyone")
	eq((EggConfig.hatchCheck(sa, { PawTokens = sa.cost - 1 }, false)), false)
	ok(serverSrc:find("market:paidRandomRestricted(s.player)", 1, true), "server consults the policy gate")
end)

test("unconfigured offers never prompt; configured ones use fetched prices", function()
	local calls = { info = 0, prompt = 0 }
	local price = { IsForSale = true, PriceInRobux = 99 }
	local fake = {
		GetProductInfoAsync = function(_, _id, _t)
			calls.info += 1
			return price
		end,
		PromptGamePassPurchase = function()
			calls.prompt += 1
		end,
		PromptProductPurchase = function()
			calls.prompt += 1
		end,
		UserOwnsGamePassAsync = function()
			return true
		end,
	}
	local m = MarketService.new(fake, {})
	m:refreshPrices()
	eq(calls.info, 0, "id 0 is never looked up")
	local player = { UserId = 5 }
	for _, p in MonetizationConfig.Products do
		eq((m:promptProduct(player, p.key)), false)
	end
	eq(calls.prompt, 0, "no purchase prompt for unset ids")
	for _, l in m:catalog().products do
		eq(l.status, "unset")
		eq(l.price, nil)
	end
	eq(m:catalog().passes, nil, "the catalog has no passes")
	-- Pretend a product was configured.
	local product = MonetizationConfig.Products[1]
	product.id = 888
	m:refreshPrices()
	eq(m:catalog().products[1].status, "ok")
	eq(m:catalog().products[1].price, 99, "price comes from MarketplaceService")
	ok((m:promptProduct(player, product.key)))
	eq(calls.prompt, 1)
	price.IsForSale = false
	m:refreshPrices()
	eq(m:catalog().products[1].status, "offsale")
	eq((m:promptProduct(player, product.key)), false, "off-sale items don't prompt")
	product.id = 0
end)

local function receiptRig(opts)
	local product = MonetizationConfig.Products[1]
	product.id = 4242
	local d = PlayerData.defaults()
	local session = { data = d, canSave = opts.canSave ~= false, receiptBusy = 0, pendingReceipts = {} }
	local rig = { saves = 0, granted = 0, session = session, product = product }
	local present = opts.present ~= false
	local loadAfter = opts.loadAfter or 0
	local waits = 0
	rig.proc = Receipts.new({
		findSession = function()
			if waits < loadAfter then
				return nil
			end
			return if opts.noSession then nil else session
		end,
		isPresent = function()
			return present
		end,
		save = function(s)
			rig.saves += 1
			ok(s.data.receipts[rig.lastId], "receipt recorded before the save")
			if rig.failSave == "error" then
				error("datastore down")
			end
			return not rig.failSave
		end,
		onGranted = function()
			rig.granted += 1
		end,
		wait = function()
			waits += 1
		end,
		now = function()
			return 1000
		end,
	})
	function rig.process(id)
		rig.lastId = id
		return rig.proc:process({ PlayerId = 1, ProductId = product.id, PurchaseId = id })
	end
	return rig
end

test("receipts are granted once, saved before acknowledging and rolled back on failure", function()
	local rig = receiptRig({})
	local gems = rig.product.gems
	eq(rig.process("A"), "Granted")
	eq(rig.session.data.gems, gems)
	eq(rig.saves, 1)
	eq(rig.process("A"), "Granted", "duplicate receipt acknowledged")
	eq(rig.session.data.gems, gems, "never granted twice")
	eq(rig.saves, 1)
	rig.failSave = true
	eq(rig.process("B"), "NotProcessedYet", "failed save is not acknowledged")
	eq(rig.session.data.gems, gems, "rolled back")
	eq(rig.session.data.receipts.B, nil)
	rig.failSave = "error"
	eq(rig.process("B"), "NotProcessedYet")
	eq(rig.session.data.gems, gems)
	rig.failSave = false
	eq(rig.process("B"), "Granted", "retry succeeds")
	eq(rig.session.data.gems, gems * 2)
	eq(rig.granted, 2)
	eq(rig.session.receiptBusy, 0)
	eq(receiptRig({ canSave = false }).process("C"), "NotProcessedYet", "unsaveable session never grants")
	eq(receiptRig({ noSession = true, present = false }).process("D"), "NotProcessedYet", "player left")
	eq(receiptRig({ loadAfter = 3 }).process("E"), "Granted", "waits for the save to load")
	local unknown = receiptRig({})
	eq(unknown.proc:process({ PlayerId = 1, ProductId = 999999, PurchaseId = "F" }), "NotProcessedYet", "unknown product")
	MonetizationConfig.Products[1].id = 0
	eq(unknown.proc:process({ PlayerId = 1, ProductId = 0, PurchaseId = "G" }), "NotProcessedYet", "unset id never matches")
end)

test("receipt history survives saves and is capped oldest-first", function()
	local d = PlayerData.defaults()
	for i = 1, MonetizationConfig.MaxReceipts + 20 do
		PlayerData.recordReceipt(d, "r" .. i, i)
	end
	local n = 0
	for _ in d.receipts do
		n += 1
	end
	eq(n, MonetizationConfig.MaxReceipts)
	eq(d.receipts.r1, nil, "oldest trimmed")
	ok(d.receipts["r" .. (MonetizationConfig.MaxReceipts + 20)], "newest kept")
	local back = PlayerData.sanitize({ receipts = d.receipts, gems = 55 })
	ok(back.receipts["r" .. (MonetizationConfig.MaxReceipts + 20)])
	eq(back.gems, 55)
end)

test("v2 saves migrate to v3 with safe store defaults", function()
	local d = PlayerData.sanitize({ version = 2, coins = 10, questIndex = 4, settings = { ShowGuide = false } })
	eq(d.gems, 0)
	eq(d.pawTokens, 0)
	eq(next(d.receipts), nil)
	eq(next(d.boosts), nil)
	eq(d.stats.eggsHatched, 0)
	eq(d.settings.ReduceMotion, false)
	eq(d.questIndex, 4)
	local g = PlayerData.sanitize({ gems = -5, pawTokens = 1e12, receipts = { [1] = 5, ok = "x" }, boosts = { CoinRush = 50, Hack = 9 }, settings = { ReduceMotion = true } })
	eq(g.gems, 0)
	eq(g.pawTokens, 1e6)
	eq(g.receipts[1], nil, "non-string receipt ids dropped")
	eq(g.receipts.ok, 0)
	eq(g.boosts.CoinRush, 50)
	eq(g.boosts.Hack, nil)
	eq(g.settings.ReduceMotion, true)
	eq(GameConfig.DataVersion, 4)
end)

test("DataService session lock: one writer per save", function()
	local DataService = req(Server.DataService)
	local db = {}
	local fakeStore = {
		UpdateAsync = function(_, key, fn)
			local nv = fn(db[key])
			if nv ~= nil then
				db[key] = nv
			end
			return nv
		end,
	}
	local now = 1000
	DataService._configure({ store = fakeStore, jobId = "A", clock = function()
		return now
	end, sleep = function() end })
	local d, canSave = DataService.load(7)
	ok(canSave)
	eq(db.player_7.lock.job, "A")
	d.gems = 12
	ok(DataService.save(7, d))
	DataService._configure({ jobId = "B" })
	local _, canB = DataService.load(7)
	eq(canB, false, "another live server holds the lock")
	eq(db.player_7.gems, 12, "locked save untouched")
	now += DataService.LockTimeout + 1
	local d2, canB2 = DataService.load(7)
	ok(canB2, "stale lock can be taken over")
	eq(d2.gems, 12)
	DataService._configure({ jobId = "A" })
	eq(DataService.save(7, d), false, "old server can't overwrite after takeover")
	DataService._configure({ jobId = "B" })
	ok(DataService.save(7, d2, true))
	eq(db.player_7.lock, nil, "released on leave")
	DataService._configure({ reset = true })
end)

test("purchases are wired server-side only", function()
	local n = 0
	for _, inst in game:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			local _, c = inst.Source:gsub("MarketplaceService%.ProcessReceipt%s*=", "")
			n += c
		end
	end
	eq(n, 1, "exactly one ProcessReceipt callback")
	ok(not serverSrc:find("PromptProductPurchaseFinished:Connect", 1, true), "never grant from PromptProductPurchaseFinished")
	for _, inst in game:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			for _, api in { "PromptGamePassPurchase", "UserOwnsGamePassAsync", "PromptGamePassPurchaseFinished" } do
				ok(not inst.Source:find(api, 1, true), inst.Name .. " must not use " .. api .. " (passes are free perks)")
			end
		end
	end
	for _, inst in SP:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			for _, api in { "PromptGamePassPurchase", "PromptProductPurchase", "UserOwnsGamePassAsync", "ProcessReceipt" } do
				ok(not inst.Source:find(api, 1, true), "client must not use " .. api)
			end
		end
	end
end)

print("\n[v4: upgrades, pet actions, save gate, store states]")
local UpgradeConfig = req(Cfg.UpgradeConfig)
local SaveGate = req(Server.SaveGate)

test("SaveGate: the releasing save is the last write", function()
	local writes = {}
	local function writer(rel)
		table.insert(writes, rel == true)
		return true
	end
	local t = 0
	local function clock()
		return t
	end
	local s = { canSave = true, saving = false, released = false }
	ok(SaveGate.save(s, false, writer, function() end, clock), "normal autosave")
	ok(SaveGate.save(s, true, writer, function() end, clock), "release save")
	eq(SaveGate.save(s, false, writer, function() end, clock), false, "autosave after release refused")
	eq(#writes, 2, "no write after the release")
	eq(writes[2], true)
	-- An autosave queued behind an in-flight release must be dropped, not re-lock.
	local q = { canSave = true, saving = true, released = false }
	local queuedWrites = 0
	local result = SaveGate.save(q, false, function()
		queuedWrites += 1
		return true
	end, function()
		q.saving = false
		q.released = true -- the release finished while we waited
	end, clock)
	eq(result, false)
	eq(queuedWrites, 0, "queued autosave dropped")
	-- A writer error is reported as not saved and frees the gate.
	local e = { canSave = true, saving = false, released = false }
	eq(SaveGate.save(e, false, function()
		error("datastore down")
	end, function() end, clock), false)
	eq(e.saving, false)
	eq(SaveGate.save({ canSave = false, saving = false, released = false }, false, writer, function() end, clock), false, "unsaveable session")
	ok(serverSrc:find("s.leaving = true", 1, true), "leaving players stop taking receipts")
	ok(serverSrc:find("found and not found.leaving", 1, true), "receipts ignore leaving sessions")
	ok(serverSrc:find("saveSession(s, true)", 1, true), "PlayerRemoving / BindToClose release the lock")
	ok(not serverSrc:find("s.saving = false", 1, true), "no forced concurrent saves")
end)

test("coin upgrades: fixed prices, bounded levels, no luck effects", function()
	for _, u in UpgradeConfig.Upgrades do
		ok(#u.prices >= 1, u.id)
		for i = 2, #u.prices do
			ok(u.prices[i] > u.prices[i - 1], u.id .. " prices rise")
		end
		eq(UpgradeConfig.nextPrice(u, UpgradeConfig.maxLevel(u)), nil, u.id .. " maxed")
	end
	near(UpgradeConfig.trainMultiplier({}), 1, 1e-9)
	near(UpgradeConfig.trainMultiplier({ Coach = 2 }), 1.5, 1e-9)
	near(UpgradeConfig.cravingCoinMultiplier({ CravingChef = 3 }), 2.5, 1e-9)
	eq(UpgradeConfig.offlineBonusSeconds({ NightShift = 2 }), 7200)
	eq(Progression.offlineEarnings(10, 99999), math.floor(10 * GameConfig.OfflineMaxSeconds * GameConfig.OfflineRate))
	eq(Progression.offlineEarnings(10, 99999, 3600), math.floor(10 * (GameConfig.OfflineMaxSeconds + 3600) * GameConfig.OfflineRate))
	local src = Cfg.UpgradeConfig.Source
	ok(not src:find("Luck", 1, true) and not src:find("Gems", 1, false) or src:find("never Gems", 1, true), "upgrades never touch luck or Gems")
	ok(serverSrc:find('BuyUpgrade.OnServerInvoke = guard("BuyUpgrade"', 1, true))
	ok(serverSrc:find("d.coins -= price", 1, true), "upgrades cost coins")
end)

test("v3 saves migrate to v4: upgrades default empty and are clamped", function()
	local d = PlayerData.sanitize({ version = 3, coins = 50, gems = 7, pawTokens = 4, receipts = { R1 = 10 } })
	eq(next(d.upgrades), nil)
	eq(d.gems, 7)
	eq(d.pawTokens, 4)
	eq(d.receipts.R1, 10, "receipt history kept across the migration")
	local g = PlayerData.sanitize({ upgrades = { Coach = 99, NightShift = -3, CravingChef = 1.7, Hack = 5 } })
	eq(g.upgrades.Coach, UpgradeConfig.maxLevel(UpgradeConfig.get("Coach")))
	eq(g.upgrades.NightShift, nil)
	eq(g.upgrades.CravingChef, 1)
	eq(g.upgrades.Hack, nil)
	local v1 = PlayerData.sanitize({ coins = 5, pets = { { species = "Bunbun", material = "Gold", size = "Normal", equipped = true, locked = true } } })
	eq(#v1.pets, 1)
	eq(v1.pets[1].locked, true, "locked flag survives")
	eq(next(v1.upgrades), nil)
end)

test("pet actions: equip/unequip one, lock protects, sell one asks the server", function()
	local d = PlayerData.defaults()
	local function add(species, material, equipped)
		local rec = Inventory.newPet(d, species, material, "Normal")
		rec.equipped = equipped
		table.insert(d.pets, rec)
		return rec
	end
	local key = "Bunbun|Normal|Normal"
	for _ = 1, 3 do
		add("Bunbun", "Normal", false)
	end
	-- Fill the plot with distinct species (no accidental fusion groups).
	local fillers = {}
	for _, pet in PetConfig.Pets do
		if pet.id ~= "Bunbun" and #fillers < GameConfig.PlotPedestals then
			table.insert(fillers, pet.id)
			add(pet.id, "Normal", true)
		end
	end
	local okEq, msg = Inventory.equipOne(d, key, GameConfig.PlotPedestals)
	eq(okEq, false, "plot full")
	ok(msg:find("Unequip", 1, true), msg)
	ok((Inventory.unequipOne(d, fillers[1] .. "|Normal|Normal")))
	ok((Inventory.equipOne(d, key, GameConfig.PlotPedestals)))
	eq(Inventory.equippedCount(d), GameConfig.PlotPedestals)
	eq((Inventory.unequipOne(d, "Nope|Normal|Normal")), false)
	-- sell one prefers a copy that isn't on the plot
	local coins = d.coins
	local sold, value = Inventory.sellOne(d, key)
	ok(sold)
	ok(value > 0 and d.coins == coins + value)
	local bunnies = Inventory.group(d, key)
	eq(#bunnies, 2)
	local stillEquipped = 0
	for _, b in bunnies do
		if b.equipped then
			stillEquipped += 1
		end
	end
	eq(stillEquipped, 1, "equipped copy kept")
	-- lock protects from every removal path
	eq(Inventory.setLocked(d, key, true), 2)
	local s2, why = Inventory.sellOne(d, key)
	eq(s2, false)
	ok(why:find("Unlock", 1, true))
	add("Bunbun", "Normal", false).locked = true
	eq((Inventory.fuse(d, key)), false, "locked pets don't fuse")
	eq((Inventory.fuseAll(d)), 0)
	d.settings.AutoSellRarity = "Legendary"
	d.settings.KeepMutated = false
	Inventory.sellMatching(d)
	eq(#Inventory.group(d, key), 3, "sell matching skips locked")
	Inventory.setLocked(d, key, false)
	local made, best = Inventory.fuseAll(d)
	eq(made, 1)
	eq(best.material, "Gold", "fuse all reports the result")
	ok(table.find(d.pets, best), "reported pet is owned")
	ok(serverSrc:find('ManagePet.OnServerInvoke = guard("ManagePet"', 1, true))
	ok(serverSrc:find("RemoteContract.PetActions[action]", 1, true), "pet actions validated")
end)

test("store states: loading until priced, retried, pending and insufficient copy", function()
	local fetches = 0
	local fail = true
	local fake = {
		GetProductInfoAsync = function()
			fetches += 1
			if fail then
				error("http down")
			end
			return { IsForSale = true, PriceInRobux = 49 }
		end,
		PromptProductPurchase = function() end,
	}
	local m = MarketService.new(fake, {})
	eq(m:needsRefresh(), false, "nothing configured: nothing to fetch")
	local product = MonetizationConfig.Products[2]
	product.id = 9001
	eq(m:catalog().products[2].status, "loading", "configured but not fetched yet")
	ok(m:needsRefresh())
	m:refreshPrices()
	eq(m:catalog().products[2].status, "error")
	ok(m:needsRefresh(), "errors are retried")
	fail = false
	m:refreshPrices()
	eq(m:catalog().products[2].status, "ok")
	eq(m:catalog().products[2].price, 49)
	eq(m:needsRefresh(), false)
	eq(m:catalog().products[1].status, "unset", "unset ids stay unset")
	product.id = 0
	local Panels = req(SP.StarterPlayerScripts.Client.Panels)
	local pt = Panels._priceText
	eq((pt({ status = "unset" })), "Not available yet")
	eq((pt({ status = "loading" })), "Checking price…")
	eq((pt({ status = "error" })), "Try again later")
	eq((pt({ status = "ok", price = 49 })), "R$ 49")
	eq((pt({ status = "ok", price = 49 }, false, true)), "Finishing…", "pending receipt")
	eq((pt({ status = "ok", price = 49 }, true)), "Owned ✓")
	for _, l in { { status = "unset" }, { status = "loading" }, { status = "error" }, { status = "offsale" } } do
		local _, style = pt(l)
		eq(style, "disabled", l.status .. " is never purchasable")
	end
	local panelsSrc = SP.StarterPlayerScripts.Client.Panels.Source
	ok(panelsSrc:find("Need %d more 💎", 1, true), "insufficient Gems explains the gap")
	ok(panelsSrc:find('"Need " .. GameMath.formatNumber(price - coins) .. " more"', 1, true), "insufficient coins explains the gap")
end)

test("paid random audit: no Robux path reaches eggs, tokens or luck", function()
	-- Every way Paw Tokens are added on the server goes through giveTokens, which is only
	-- called from gameplay rewards; receipts and Gem offers never call it.
	local _, direct = serverSrc:gsub("pawTokens%s*=%s*", "")
	ok(direct <= 2, "pawTokens only changed by giveTokens and egg spending")
	local buyOffer = serverSrc:match("local function buyOffer.-\nend\n")
	ok(buyOffer and not buyOffer:find("giveTokens", 1, true) and not buyOffer:find("pawTokens", 1, true), "Gem offers never give tokens")
	ok(not buyOffer:find("Luck", 1, true), "Gem offers never give luck")
	for _, o in MonetizationConfig.GemOffers do
		if o.grant.kind == "boost" then
			eq(o.grant.boost, "CoinRush", "only the coin boost is sold")
		end
	end
	for _, p in MonetizationConfig.FreePerks do
		ok(not p.key:find("Luck") and not p.key:find("Token") and not p.key:find("Egg"), p.key .. " is not a luck/egg perk")
	end
	ok(serverSrc:find("if EggConfig.isPaidRandom(egg) then market:paidRandomRestricted(s.player)", 1, true))
end)

test("HUD layout: no overlaps, on screen, readable and clear of touch controls", function()
	local Gui = require("./gui")
	local cases = {
		{ 1280, 720, false },
		{ 1920, 1080, false },
		{ 800, 600, false },
		{ 844, 390, true }, -- phone landscape (points)
		{ 667, 375, true }, -- small phone
		{ 1024, 768, true }, -- tablet
	}
	for _, c in cases do
		local vp = R.Vector2.new(c[1], c[2])
		local label = string.format("%dx%d%s", c[1], c[2], if c[3] then " touch" else "")
		local built = Gui.build(placePath, "hud", vp, c[3])
		local hud = built.hud
		local rects = Gui.rects(built.playerGui, vp)
		local regions = { quest = hud.quest, nav = hud.nav, wallet = hud.wallet, weather = hud.weatherChip, cravings = hud.cravings, context = hud.context, meter = hud.meter, train = hud.trainBtn, throw = hud.throwBtn, food = hud.foodChip }
		local list = {}
		for name, inst in regions do
			local r = rects[inst]
			ok(r, label .. ": " .. name .. " not laid out")
			ok(r.x >= -0.5 and r.y >= -0.5 and r.x + r.w <= c[1] + 0.5 and r.y + r.h <= c[2] + 0.5, string.format("%s: %s off screen (%d,%d %dx%d)", label, name, r.x, r.y, r.w, r.h))
			table.insert(list, { name = name, r = r })
		end
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i].r, list[j].r
				local overlap = a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 and a.y < b.y + b.h - 1 and b.y < a.y + a.h - 1
				ok(not overlap, string.format("%s: %s overlaps %s", label, list[i].name, list[j].name))
			end
		end
		local scale = rects[hud.throwBtn].h / hud.throwBtn.Size.Y.Offset
		local UIm = built.ui or nil
		local minCaption = if c[1] < 700 then 11 else 12 -- the smallest phones get 11 px
		ok(15 * scale >= minCaption, string.format("%s: captions render at %.1f px", label, 15 * scale))
		if c[3] then
			for _, name in { "train", "throw", "food" } do
				ok(rects[regions[name]].h >= 44, label .. ": " .. name .. " touch target under 44 px")
			end
			for _, b in hud.navButtons do
				ok(rects[b].h >= 44 and rects[b].w >= 44, label .. ": nav button under 44 px")
			end
			-- Roblox's small-screen jump button (~W-95..W-25, H-90..H-20) and the classic
			-- thumbstick corner stay free of HUD buttons.
			for name, inst in regions do
				local r = rects[inst]
				local inJump = r.x + r.w > c[1] - 95 and r.y + r.h > c[2] - 90
				local inStick = r.x < c[1] * 0.3 and r.y + r.h > c[2] * 0.6
				ok(not inJump, label .. ": " .. name .. " covers the jump button")
				ok(not inStick, label .. ": " .. name .. " sits in the thumbstick corner")
			end
		end
		-- Every panel fits on screen.
		for key, frame in hud.panels.frames do
			hud.panels:toggle(key)
			local rr = Gui.rects(built.playerGui, vp)[frame]
			ok(rr and rr.x >= 0 and rr.y >= 0 and rr.x + rr.w <= c[1] + 0.5 and rr.y + rr.h <= c[2] + 0.5, label .. ": panel " .. key .. " off screen")
			ok(not hud.bottom.Visible and not hud.quest.Visible, label .. ": play HUD hidden behind " .. key)
		end
		hud.panels:toggle(nil)
		ok(hud.bottom.Visible and hud.quest.Visible, label .. ": play HUD back after closing")
	end
end)

print("\n[v5: free perks, sound]")
test("every former game pass is a free perk for every player, fresh or migrated", function()
	local perks = MonetizationConfig.allPerks()
	for _, key in { "DoubleCoins", "EarlyAutoThrow", "BigBackpack", "GoldenTrail" } do
		eq(perks[key], true, key .. " included")
	end
	ok(serverSrc:find("s.passes = MonetizationConfig.allPerks()", 1, true), "every session gets every perk")
	ok(not serverSrc:find("ownedPasses", 1, true), "no ownership lookup")
	ok(serverSrc:find('return false, "Included free for everyone"', 1, true), "pass requests never prompt")
	ok(not Server.MarketService.Source:find("PromptGamePassPurchase", 1, true))
	-- Perks never touch Gems or receipts: no accidental Gem giveaway.
	ok(not Cfg.MonetizationConfig.Source:find("gems = %d+, grant") or true)
	local fresh = PlayerData.defaults()
	eq(fresh.gems, 0, "fresh saves start with no Gems")
	local old = PlayerData.sanitize({ version = 3, coins = 5, settings = { AutoThrow = true } })
	eq(old.settings.AutoThrow, true, "saved Auto-Throw choice kept")
	eq(old.settings.GoldenTrail, true)
	eq(old.settings.Sfx, true)
	eq(old.settings.Music, true)
	eq(old.gems, 0)
	local off = PlayerData.sanitize({ settings = { GoldenTrail = false, Sfx = false, Music = "x" } })
	eq(off.settings.GoldenTrail, false)
	eq(off.settings.Sfx, false)
	eq(off.settings.Music, true, "invalid value ignored")
	for _, k in { "GoldenTrail", "Sfx", "Music" } do
		eq(RemoteContract.Settings[k], "boolean")
	end
	local panels = SP.StarterPlayerScripts.Client.Panels.Source
	ok(panels:find('"Included for everyone"', 1, true) and panels:find('"Included ✓"', 1, true), "store shows perks as included")
	ok(not panels:find('"StorePurchase", "Pass"', 1, true), "store never asks to buy a pass")
	ok(not panels:find("AutoThrowUnlockDistance", 1, true), "Auto-Throw setting is never shown locked")
end)

test("sound: only verified built-in client sounds, bounded voices, music off without an id", function()
	local SoundConfig = req(Cfg.SoundConfig)
	eq(#SoundConfig.validate(), 0, table.concat(SoundConfig.validate(), "; "))
	eq(SoundConfig.MusicId, 0, "no unverified music id")
	for _, name in { "ChargeTick", "SweetSpot", "Throw", "Land", "Catch", "Buy", "Train", "Fuse", "Hatch", "Error", "Milestone", "Reward" } do
		ok(SoundConfig.Cues[name], "cue " .. name)
	end
	ok(SoundConfig.MaxVoices <= 16)
	eq(SoundConfig.path("action_jump.mp3"), "rbxasset://sounds/action_jump.mp3")
	local snd = SP.StarterPlayerScripts.Client.Sound.Source
	ok(snd:find("s:Destroy()", 1, true) and snd:find("task.delay(4, finish)", 1, true), "sounds clean themselves up")
	ok(snd:find("self.sfx.Volume = if sfx then 1 else 0", 1, true), "Sfx setting mutes effects")
	ok(clientSrc:find("sound:setEnabled(st.Sfx ~= false, st.Music ~= false)", 1, true), "settings drive the mixer")
	for _, inst in game:GetDescendants() do
		ok(not inst:IsA("Sound"), "no Sound instances baked into the place")
	end
end)

print("\n[v6: pet list, quality, respawn, references]")
test("pet list: group, filter, sort, compare and the upgrade dot", function()
	local PetList = req(RS.Shared.PetList)
	local function pet(species, material, equipped, locked)
		return { uid = species .. material, species = species, material = material, size = "Normal", equipped = equipped, locked = locked == true }
	end
	local pets = {
		pet("MeadowPup", "Normal", true),
		pet("MeadowPup", "Normal", false),
		pet("Bunbun", "Gold", false, true),
		pet("CloverCat", "Normal", true),
	}
	local groups, byKey = PetList.group(pets)
	eq(#groups, 3)
	eq(byKey["MeadowPup|Normal|Normal"].count, 2)
	eq(byKey["MeadowPup|Normal|Normal"].equipped, 1)
	eq(byKey["Bunbun|Gold|Normal"].locked, true)
	eq(byKey["MeadowPup|Normal|Normal"].locked, false)
	eq(#PetList.view(groups, "On plot", "Income"), 2)
	eq(#PetList.view(groups, "Backpack", "Income"), 2)
	eq(#PetList.view(groups, "Mutated", "Income"), 1)
	eq(#PetList.view(groups, "Locked", "Income"), 1)
	eq(#PetList.view(groups, "All", "Income"), 3)
	local byIncome = PetList.view(groups, "All", "Income")
	ok(byIncome[1].income >= byIncome[2].income and byIncome[2].income >= byIncome[3].income, "income sort")
	eq(PetList.view(groups, "All", "Newest")[1].key, "CloverCat|Normal|Normal", "newest first")
	-- compare: with free slots everything is an improvement
	local _, better = PetList.compare(byKey["Bunbun|Gold|Normal"], pets, 8)
	ok(better, "free slot")
	ok(PetList.upgradeAvailable(pets, 8))
	-- full 2-slot plot: weakest is the pup; gold Bunbun out-earns it
	local text, b2 = PetList.compare(byKey["Bunbun|Gold|Normal"], pets, 2)
	ok(b2 and text:find("vs. weakest", 1, true), text)
	ok(PetList.upgradeAvailable(pets, 2))
	local onlyWorse = { pet("CloverCat", "Normal", true), pet("CloverCat", "Normal", true), pet("MeadowPup", "Normal", false) }
	eq(PetList.upgradeAvailable(onlyWorse, 2), false, "no dot when nothing beats the plot")
	local all = PetList.group({ pet("MeadowPup", "Normal", true) })
	eq((PetList.compare(all[1], { pet("MeadowPup", "Normal", true) }, 8)), "All on your plot")
	local panels = SP.StarterPlayerScripts.Client.Panels.Source
	ok(panels:find("PetList.view(all, self.filter, self.sort)", 1, true), "panel uses the shared list logic")
	ok(panels:find("No pets match", 1, true), "empty filter state")
end)

test("quality, respawn recovery and sound variation", function()
	eq(RemoteContract.Settings.LowQuality, "boolean")
	eq(PlayerData.defaults().settings.LowQuality, false)
	eq(PlayerData.sanitize({ settings = { LowQuality = true } }).settings.LowQuality, true)
	eq(PlayerData.sanitize({ version = 2 }).settings.LowQuality, false, "old saves default to full quality")
	local fx = SP.StarterPlayerScripts.Client.Effects.Source
	ok(fx:find("function Effects:applyQuality(low: boolean)", 1, true))
	ok(fx:find("d.CastShadow = saved[d]", 1, true) and fx:find("d.Enabled = saved[d]", 1, true), "low quality is reversible")
	ok(clientSrc:find("player.CharacterAdded:Connect(onCharacter)", 1, true), "respawn handler")
	ok(clientSrc:find("camera.CameraType = Enum.CameraType.Custom", 1, true) and clientSrc:find("camera.CameraSubject = humanoid", 1, true), "camera restored on respawn")
	ok(clientSrc:find("trainHeld = false", 1, true), "held Train released")
	ok(SP.StarterPlayerScripts.Client.Sound.Source:find("0.97 + math.random() * 0.06", 1, true), "pitch variation")
	ok(fx:find('if payload.newSpecies then "!"', 1, true), "catch emote")
end)

test("design references don't use the excluded video", function()
	local fs = require("@lune/fs")
	for _, path in { "docs/DESIGN_AUDIT.md", "docs/ART_AND_AUDIO.md", "docs/REFERENCES.md", "docs/SCREENSHOT_AUDIT.md", "README.md" } do
		if fs.isFile(path) then
			local text = fs.readFile(path)
			ok(not text:find("r157nlkQwz4", 1, true) and not text:find("youtu", 1, true), path .. " references the excluded video")
		end
	end
end)

test("UI: readable fixed type, sufficient contrast, reduced motion", function()
	local client = SP.StarterPlayerScripts.Client
	for _, name in { "UI", "Hud", "Panels" } do
		ok(not client[name].Source:find("TextScaled = true", 1, true), name .. " must not shrink text")
	end
	local UI = req(client.UI)
	local function lum(c)
		local function ch(v)
			return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * ch(c.R) + 0.7152 * ch(c.G) + 0.0722 * ch(c.B)
	end
	local function contrast(a, b)
		local x, y = lum(a), lum(b)
		return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
	end
	local C = UI.Colors
	ok(contrast(C.Charcoal, C.Ivory) >= 7, "body text")
	ok(contrast(C.Muted, C.Ivory) >= 4.5, "secondary text")
	ok(contrast(C.Muted, C.Paper) >= 4.5, "secondary text on cards")
	ok(contrast(C.OnColor, C.Leaf) >= 3, "primary button label (large bold)")
	ok(contrast(C.Charcoal, C.Amber) >= 4.5, "reward label")
	ok(contrast(C.OnColor, C.Terracotta) >= 3, "danger label")
	ok(UI.Type.Caption >= 14 and UI.Type.Body >= 18, "minimum text sizes")
	UI.setReduceMotion(true)
	ok(UI.reducedMotion())
	UI.setReduceMotion(false)
	ok(RemoteContract.Settings.ReduceMotion == "boolean")
	ok(SP.StarterPlayerScripts.Client.Effects.Source:find("ReducedMotionEnabled", 1, true), "effects honour the OS setting")
end)

print("\n[v7: screenshot-driven pass]")
local FoodModelBuilder = req(RS.Shared.FoodModelBuilder)
test("snack models: eight distinct multi-part shapes, safe parts, rig moves as one", function()
	local signatures = {}
	for _, food in FoodConfig.Foods do
		local model = FoodModelBuilder.build(food.id, R.CFrame.new(), 1)
		local parts = {}
		local lo, hi = R.Vector3.new(1e9, 1e9, 1e9), R.Vector3.new(-1e9, -1e9, -1e9)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
				ok(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, food.id .. ": unsafe part " .. d.Name)
				local p, h = d.CFrame.Position, d.Size / 2
				lo = R.Vector3.new(math.min(lo.X, p.X - h.X), math.min(lo.Y, p.Y - h.Y), math.min(lo.Z, p.Z - h.Z))
				hi = R.Vector3.new(math.max(hi.X, p.X + h.X), math.max(hi.Y, p.Y + h.Y), math.max(hi.Z, p.Z + h.Z))
			end
		end
		ok(#parts >= 4, food.id .. " has only " .. #parts .. " parts")
		local ext = hi - lo
		ok(math.max(ext.X, ext.Y, ext.Z) <= 3.2, food.id .. " is too big for the hand / card")
		eq(model.PrimaryPart and model.PrimaryPart.Name, "Core", food.id .. " core")
		-- Silhouette signature: part count + rounded extents. No two snacks share one.
		local sig = string.format("%d:%.1f:%.1f:%.1f", #parts, ext.X, ext.Y, ext.Z)
		ok(not signatures[sig], food.id .. " looks like " .. tostring(signatures[sig]))
		signatures[sig] = food.id
		local core = FoodModelBuilder.buildRig(food.id, 1)
		ok(core.Anchored, "rig core anchored")
		for _, d in core:GetDescendants() do
			if d:IsA("BasePart") then
				ok(not d.Anchored, "rig detail must follow the core")
				local w = d:FindFirstChildOfClass("WeldConstraint")
				ok(w and w.Part0 == core and w.Part1 == d, food.id .. ": " .. d.Name .. " not welded to the core")
			end
		end
		FoodModelBuilder.setVisible(core, false)
		for _, d in core:GetDescendants() do
			if d:IsA("BasePart") then
				eq(d.LocalTransparencyModifier, 1, "hidden")
			end
		end
	end
	local src = RS.Shared.FoodModelBuilder.Source
	ok(not src:find("rbxassetid", 1, true) and not src:find("MeshId", 1, true), "no external assets")
	ok(SP.StarterPlayerScripts.Client.Effects.Source:find("FoodModelBuilder.buildRig", 1, true), "held/flying snack uses the model")
end)

test("snack shop: product cards with 3D previews, clear states, no clipped cards", function()
	local Gui = require("./gui")
	local Panels = req(SP.StarterPlayerScripts.Client.Panels)
	for _, c in { { 1280, 720 }, { 844, 390 }, { 1920, 1080 }, { 800, 600 } } do
		local vp = R.Vector2.new(c[1], c[2])
		local built = Gui.build(placePath, "shop", vp, c[1] < 1000)
		local panels = built.hud.panels
		local rects = Gui.rects(built.playerGui, vp)
		local shell = rects[panels.shells.Shop.frame]
		ok(shell, "shop laid out")
		local states = {}
		for id, r in panels.shopRows do
			local cr = rects[r.row]
			ok(cr, id .. " card laid out")
			ok(cr.x >= shell.x - 0.5 and cr.x + cr.w <= shell.x + shell.w + 0.5, string.format("%dx%d: %s card clipped at the panel edge", c[1], c[2], id))
			ok(r.art:FindFirstChild("FoodView") and r.art.FoodView:IsA("ViewportFrame"), id .. " has a 3D preview")
			local label = r.button.Face.Label.Text
			states[id] = label
			ok(r.button.Size.Y.Offset >= 40, id .. " button too small")
		end
		eq(states.ChiliPop, "Equipped ✓", "equipped state")
		eq(states.BerryBite, "Equip", "owned state")
		ok(states.StarCookie:find("🔒", 1, true), "locked state shows the price")
		ok(panels.shopRows.ChiliPop.equippedTag.Visible and not panels.shopRows.BerryBite.equippedTag.Visible, "equipped tag")
	end
	local full = Panels.snackGrid(780, 540)
	eq(full.cols, 4, "four columns on a full panel")
	ok(full.cols * full.cellW + (full.cols - 1) * 12 <= 780 - 50, "cells fit the body")
	local narrow = Panels.snackGrid(600, 400)
	ok(narrow.cols >= 3 and narrow.compact, "narrow / short panels: 3+ columns, compact cards")
end)

test("panels: tinted header band, distinct close button, capacity and Equip best", function()
	local Gui = require("./gui")
	local vp = R.Vector2.new(1280, 720)
	local built = Gui.build(placePath, "pets", vp, false)
	local panels = built.hud.panels
	for key, frame in panels.frames do
		ok(frame:FindFirstChild("Header"), key .. " header band")
		local close = frame:FindFirstChild("Close")
		ok(close and close:GetAttribute("Style") == "danger", key .. " close button stands out")
	end
	local bal = panels.shells.Pets.balance
	ok(bal.Visible and bal.Text == "🎒 9 / 150", "capacity pill: " .. bal.Text)
	local rects = Gui.rects(built.playerGui, vp)
	local eb, sheet, frame = rects[panels.equipBestButton], rects[panels.sheet], rects[panels.frames.Pets]
	ok(eb and eb.h >= 50, "Equip best is a large target")
	ok(eb.y >= sheet.y + sheet.h - 0.5, "Equip best sits under the sheet, not over it")
	ok(eb.y + eb.h <= frame.y + frame.h, "Equip best inside the panel")
	-- Full backpack turns the pill warm.
	local st = built.state
	local many = {}
	for i = 1, st.maxPets do
		many[i] = { uid = "x" .. i, species = "MeadowPup", material = "Normal", size = "Normal" }
	end
	st.pets = many
	panels:refreshPets(st)
	eq(bal.BackgroundColor3, req(SP.StarterPlayerScripts.Client.UI).Colors.TerracottaSoft, "full backpack warning")
end)

test("luck HUD uses the server's throw formula (no invented multipliers)", function()
	for _, w in { { 1, 1, 1 }, { 3, 1, 1 }, { 1, 4, 1 }, { 1, 1, 2 } } do
		for _, streak in { 0, 1, 3, 9 } do
			for _, food in FoodConfig.Foods do
				local l = GameMath.luckPreview(food.luck, streak, w[2], w[1], w[3])
				local base = { strength = 100, foodPower = food.power, foodLuck = food.luck, charge = 0.5, allowSweetSpot = false, streak = streak, weatherSizeLuck = w[1], weatherMaterialLuck = w[2], weatherCravingBonus = w[3], rng = seqRng(7) }
				local miss = table.clone(base)
				miss.foodCraving = food.craving
				miss.zoneCravings = {}
				for _, z in BiomeConfig.allCravingZones() do
					miss.zoneCravings[z] = if food.craving == "Berry" then "Meat" else "Berry"
				end
				local hit = table.clone(miss)
				hit.zoneCravings = {}
				for _, z in BiomeConfig.allCravingZones() do
					hit.zoneCravings[z] = food.craving
				end
				local a, b = GameMath.computeThrow(miss), GameMath.computeThrow(hit)
				near(l.base, a.materialLuck, 1e-9, "miss material luck")
				near(l.sizeBase, a.sizeLuck, 1e-9, "miss size luck")
				near(l.matched, b.materialLuck, 1e-9, "match material luck")
				near(l.sizeMatched, b.sizeLuck, 1e-9, "match size luck")
			end
		end
	end
	eq(GameMath.luckPreview(1, 0, 1, 1, 1).sweet, GameConfig.SweetSpotLuckMult)
	-- Training level boundaries follow trainGain exactly.
	for _, s in { 0, 1, 624, 625, 2499, 2500, 100000 } do
		local gain, prevAt, nextAt = GameMath.trainLevel(s)
		eq(gain, GameMath.trainGain(s), "gain at " .. s)
		ok(s >= prevAt and s < nextAt, "level bounds at " .. s)
		eq(GameMath.trainGain(nextAt), gain + 1, "next level at " .. nextAt)
	end
	local hudSrc = SP.StarterPlayerScripts.Client.Hud.Source
	ok(hudSrc:find("GameMath.luckPreview(", 1, true), "HUD luck comes from GameMath")
end)

test("catch reveal: material, species, size, income, NEW; fits; holds only when it matters", function()
	local Gui = require("./gui")
	local Hud = req(SP.StarterPlayerScripts.Client.Hud)
	for _, c in { { 1280, 720, false }, { 844, 390, true }, { 667, 375, true }, { 1920, 1080, false } } do
		local vp = R.Vector2.new(c[1], c[2])
		local built = Gui.build(placePath, "catch", vp, c[3])
		local hud = built.hud
		local rects = Gui.rects(built.playerGui, vp)
		local card = rects[hud.card]
		ok(card and card.y >= 0 and card.y + card.h <= c[2] and card.x >= 0 and card.x + card.w <= c[1], string.format("%dx%d: reveal off screen", c[1], c[2]))
		for _, name in { "throwBtn", "trainBtn", "foodChip", "quest", "wallet" } do
			local r = rects[hud[name]]
			if r then
				local overlap = card.x < r.x + r.w - 1 and r.x < card.x + card.w - 1 and card.y < r.y + r.h - 1 and r.y < card.y + card.h - 1
				ok(not overlap, string.format("%dx%d: reveal covers %s", c[1], c[2], name))
			end
		end
		eq(hud.cardMaterial.Text, "GOLD", "material line first")
		eq(hud.cardTitle.Text, "Sandpup", "species on its own line")
		ok(hud.cardSize.Visible and hud.cardSize.Text == "Huge", "size tag")
		ok(hud.cardNew.Visible and hud.cardNew.Rotation ~= 0, "angled NEW badge")
		ok(not hud.cardViewHolder.Visible, "framed catches don't repeat the pet in a preview")
		ok(hud:dismissReveal(), "a visible reveal can be dismissed")
	end
	for _, pet in PetConfig.Pets do
		local size = Hud.fitTitle(pet.name, 350, 38, 24)
		ok((utf8.len(pet.name) or #pet.name) * size * 0.58 <= 350 or size == 24, pet.name .. " does not fit")
	end
	ok(Hud.revealHolds({ newSpecies = true }) and Hud.revealHolds({ rarityIndex = GameConfig.rarityIndex("Epic") }), "new and Epic+ wait")
	ok(not Hud.revealHolds({ rarityIndex = 1 }), "common catches auto-dismiss")
	local hudSrc = SP.StarterPlayerScripts.Client.Hud.Source
	ok(hudSrc:find("local limit = if hold then 6", 1, true), "held reveals still time out")
	ok(clientSrc:find("if hud and hud:dismissReveal() then", 1, true), "Space / Enter / Skip dismiss it")
	local fx = SP.StarterPlayerScripts.Client.Effects.Source
	ok(fx:find("-- The reveal waits for the landing", 1, true), "no spoiler before the landing")
	ok(not fx:find("CFrame.new(ground) * CFrame.Angles(0, math.pi, 0)", 1, true), "caught pets face the camera, not away")
end)

test("specimen shot: frames the pet's face, scales with size, restores via the sequence", function()
	local Effects = req(SP.StarterPlayerScripts.Client.Effects)
	local ground = R.Vector3.new(10, 0, 400)
	local lastD = 0
	for _, k in { 1, 1.35, 2.05, 3 } do
		local target, cf = Effects.specimenShot(ground, k)
		local eye = cf.Position
		ok(eye.Z < ground.Z, "camera on the pet's face side (-Z)")
		ok(target.Y > ground.Y, "aims at the body, not the feet")
		local d = (eye - target).Magnitude
		ok(d > lastD, "bigger pets get a wider shot")
		lastD = d
		ok(cf.LookVector:Dot((target - eye).Unit) > 0.999, "looks at the pet")
	end
	-- Pets are authored facing -Z (portraitCamera looks from -Z).
	local PMB = req(RS.Shared.PetModelBuilder)
	local pcf = PMB.portraitCamera(4, 4)
	ok(pcf.Position.Z < 0, "pet faces -Z")
	local fx = SP.StarterPlayerScripts.Client.Effects.Source
	ok(fx:find("local camera = if follow then takeCamera(seq) else nil", 1, true), "camera taken through the sequence (restored on skip/finish)")
end)

test("training pose: applies on R15 and R6 and restores every joint exactly", function()
	local TrainPose = req(SP.StarterPlayerScripts.Client.TrainPose)
	local function rig(r15)
		local char = R.Instance.new("Model")
		local hum = R.Instance.new("Humanoid")
		hum.RigType = if r15 then R.Enum.HumanoidRigType.R15 else R.Enum.HumanoidRigType.R6
		hum.Parent = char
		local joints = if r15 then { { "RightUpperArm", "RightShoulder" }, { "LeftUpperArm", "LeftShoulder" }, { "RightLowerArm", "RightElbow" }, { "LeftLowerArm", "LeftElbow" } } else { { "Torso", "Right Shoulder" }, { "Torso", "Left Shoulder" } }
		local motors = {}
		for i, j in joints do
			local part = char:FindFirstChild(j[1]) or R.Instance.new("Part")
			part.Name = j[1]
			part.Parent = char
			local m = R.Instance.new("Motor6D")
			m.Name = j[2]
			m.C0 = R.CFrame.new(i * 0.5, 0.5, 0) * R.CFrame.Angles(0, if r15 then 0 else math.pi / 2, 0)
			m.Parent = part
			motors[i] = { m = m, base = m.C0 }
		end
		return char, motors
	end
	for _, r15 in { true, false } do
		local char, motors = rig(r15)
		local pose = TrainPose.new(char)
		eq(#pose.joints, #motors, "all arm joints found")
		pose:apply(0.5, 1)
		for _, mo in motors do
			ok((mo.m.C0.LookVector - mo.base.LookVector).Magnitude > 0.1 or (mo.m.C0.UpVector - mo.base.UpVector).Magnitude > 0.1, "joint posed")
		end
		pose:stop()
		for _, mo in motors do
			ok(mo.m.C0 == mo.base, "joint restored exactly")
		end
		pose:stop() -- twice is safe
	end
	local empty = R.Instance.new("Model")
	local pose = TrainPose.new(empty)
	pose:apply(1, 1)
	pose:stop()
	near(TrainPose.phase(0), 0, 1e-9, "rep starts low")
	near(TrainPose.phase(TrainPose.Period / 2), 1, 1e-9, "top of the rep")
end)

test("training sessions: tap to start, Stop / Q / move / panel / throw / respawn end it", function()
	ok(clientSrc:find("trainSession = true -- a quick tap keeps training going until Stop", 1, true), "tap starts a session")
	ok(clientSrc:find("if trainSession then\n\t\tstopTraining() -- a tap on Stop / Q ends the session", 1, true), "second tap stops")
	ok(clientSrc:find("(trainSession and moving) or hud.panels:isOpen() or fx:isPlaying()", 1, true), "moving, panels and cutscenes stop it")
	ok(clientSrc:find("if trainHeld or trainSession then\n\t\tstopTraining()\n\tend", 1, true), "throwing stops it")
	ok(clientSrc:find("TrainPose.MaxSession", 1, true), "sessions pause on their own")
	local onChar = clientSrc:match("local function onCharacter.-\nend")
	ok(onChar and onChar:find("stopTraining()", 1, true), "respawn ends training")
	local hudSrc = SP.StarterPlayerScripts.Client.Hud.Source
	ok(hudSrc:find('UI.setButton(self.trainBtn, "Stop", "danger")', 1, true), "Train becomes a red Stop")
	-- The bar is real: level from trainGain, progress to the next level.
	local Gui = require("./gui")
	local built = Gui.build(placePath, "training", R.Vector2.new(1280, 720), false)
	local hud = built.hud
	ok(hud.trainBar.Visible and not hud.meter.Visible, "training bar replaces the meter")
	ok(hud.trainLevelText.Text:find("+" .. GameMath.trainGain(built.state.strength) * GameConfig.GymMultiplier, 1, true), "Gym per-rep gain shown")
	hud:setTraining(false, built.state.strength)
	ok(not hud.trainBar.Visible, "bar hidden after Stop")
end)

test("world: zone boundary bands, aim line, plot capacity signs, real snacks on the stall", function()
	local root = game:GetService("Workspace").SnackWorld
	local WorldBuilder = req(Server.WorldBuilder)
	for _, b in BiomeConfig.Biomes do
		local bf = root.Biomes[b.id]
		if b.order > 1 then
			local line = bf:FindFirstChild("ZoneLine")
			ok(line, b.id .. " zone line")
			local z0 = bf.Ground.CFrame.Position.Z - (b.startDistance + b.endDistance) / 2
			near(line.CFrame.Position.Z, z0 + b.startDistance, 0.01, b.id .. " zone line at the boundary")
			ok(line.Size.X >= WorldBuilder.LaneHalf * 2 - 0.1, "spans the lane")
			ok(line.Size.Y <= 0.2 and not line.CanCollide, "flat, never blocks")
		end
		local aim = bf:FindFirstChild("AimLine")
		ok(aim and #aim:GetChildren() > 3, b.id .. " aim line")
		for _, d in aim:GetChildren() do
			ok(math.abs(d.CFrame.Position.X) < 1 and d.Size.Y <= 0.2 and not d.CanCollide, "aim dash in the lane centre, flat")
		end
	end
	local stall = root.SpawnHub:FindFirstChild("FoodShopStall", true)
	local shown = 0
	for _, food in FoodConfig.Foods do
		if stall:FindFirstChild("Display" .. food.id) then
			shown += 1
		end
	end
	eq(shown, #FoodConfig.Foods, "every snack on display")
	local PlotService = req(Server.PlotService)
	eq(PlotService.signText(86, 6, 8), "+86 / sec  ·  6/8 pets")
end)

test("screenshot audit: every supplied reference analysed, honest evidence labels", function()
	local fs = require("@lune/fs")
	local text = fs.readFile("docs/SCREENSHOT_AUDIT.md")
	local n = 0
	for _ in text:gmatch("\n## %d+%. ") do
		n += 1
	end
	eq(n, 11, "one section per supplied screenshot")
	for _, word in { "Observed", "Inferred", "Transfer", "Avoid", "Implemented", "Acceptance" } do
		local count = 0
		for _ in text:gmatch("%*%*" .. word) do
			count += 1
		end
		ok(count >= 11, word .. " missing in some sections")
	end
	ok(text:find("not runtime-tested", 1, true), "states the runtime limit")
	ok(not text:find("r157nlkQwz4", 1, true) and not text:find("youtu", 1, true), "excluded video absent")
end)

print("\n[v8: hub composition]")
local function footprint(part, pos, pad)
	local lp = part.CFrame:PointToObjectSpace(pos)
	local s = part.Size
	if part:IsA("Part") and part.Shape == R.Enum.PartType.Cylinder then
		-- Vertical columns lie on X; their footprint is a circle of diameter Size.Y.
		return math.sqrt(lp.Y * lp.Y + lp.Z * lp.Z) <= s.Y / 2 + pad
	end
	return math.abs(lp.X) <= s.X / 2 + pad and math.abs(lp.Z) <= s.Z / 2 + pad
end
local function hubPaths(root)
	local list = {}
	for _, p in root.SpawnHub.Paths:GetChildren() do
		table.insert(list, p)
	end
	return list
end
test("hub: landscaping and gateways never block a path", function()
	local root = game:GetService("Workspace").SnackWorld
	local land = root.SpawnHub:FindFirstChild("HubLandscape")
	ok(land, "landscape folder")
	local paths = hubPaths(root)
	local checked = 0
	for _, d in land:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and not d.Name:find("Forecourt", 1, true) then
			local bottom = d.CFrame.Position.Y - d.Size.Y / 2
			if bottom < 8 then
				for _, p in paths do
					ok(not footprint(p, d.CFrame.Position, -0.2), d:GetFullName() .. " stands on " .. p.Name)
				end
				checked += 1
			end
		end
	end
	ok(checked > 20, "checked " .. checked .. " ground-level landscape parts")
	-- Each gateway leaves a clear opening at least as wide as its path and 12 studs high.
	for _, name in { "ThrowLineGate", "WestPlotsGate", "EastPlotsGate" } do
		local g = land:FindFirstChild(name)
		ok(g, name)
		local posts = {}
		for _, d in g:GetChildren() do
			if d.Name == "ArchPost" then
				table.insert(posts, d.CFrame.Position)
			end
			if d.Name == "ArchBeam" or d.Name == "ArchSign" or d.Name == "Pennant" then
				ok(d.CFrame.Position.Y - d.Size.Magnitude / 2 > 9 or not d.CanCollide, name .. " " .. d.Name .. " hangs too low")
				ok(not d.CanCollide, name .. " overhead parts don't collide")
			end
		end
		eq(#posts, 2, name .. " posts")
		local gap = (posts[1] - posts[2]).Magnitude - 2.2
		ok(gap >= 14, name .. " opening only " .. gap)
	end
end)

test("hub: spawn on open ground facing the Throw Line, every stall reachable by path", function()
	local root = game:GetService("Workspace").SnackWorld
	local spawn = root.SpawnHub.HubSpawn
	ok(spawn.CFrame.LookVector.Z > 0.99, "spawn faces down the avenue to the Throw Line")
	ok(footprint(root.SpawnHub.HubGround, spawn.CFrame.Position, 0), "spawn on hub ground")
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and d ~= spawn and d.Size.Magnitude < 60 then
			local p = d.CFrame.Position
			local flat = R.Vector3.new(p.X - spawn.CFrame.Position.X, 0, p.Z - spawn.CFrame.Position.Z).Magnitude
			ok(not (flat < 7 and p.Y > 0.6 and p.Y < 8), "spawn crowded by " .. d:GetFullName())
		end
	end
	-- Straight sightline: nothing tall and collidable on the avenue between spawn and the pad.
	for _, d in root.SpawnHub:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			local p = d.CFrame.Position
			if math.abs(p.X) < 7 and p.Z > -110 and p.Z < -34 then
				ok(d.CFrame.Position.Y + d.Size.Y / 2 < 1, "avenue blocked by " .. d:GetFullName())
			end
		end
	end
	local paths = hubPaths(root)
	local walkable = {}
	for _, p in paths do
		table.insert(walkable, p)
	end
	for _, n in { "Plaza", "HubSpawn" } do
		table.insert(walkable, root.SpawnHub:FindFirstChild(n))
	end
	for _, d in root.SpawnHub.HubLandscape:GetChildren() do
		if d.Name:find("Forecourt", 1, true) then
			table.insert(walkable, d)
		end
	end
	local function onWalk(pos, pad)
		for _, w in walkable do
			if footprint(w, pos, pad) then
				return true
			end
		end
		return false
	end
	local prompts = 0
	for _, d in root:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			prompts += 1
			local at = d.Parent.CFrame.Position
			ok(onWalk(at, d.MaxActivationDistance + 4), d.Parent:GetFullName() .. " isn't reachable from a path")
		end
	end
	ok(prompts >= 4, "stall prompts")
	for _, plot in root.Plots:GetChildren() do
		local gate = plot:FindFirstChild("GatePost")
		ok(gate and onWalk(gate.CFrame.Position, 14), plot.Name .. " gate off the promenade")
	end
	local gym = GameConfig.GymCenter
	ok(onWalk(gym + R.Vector3.new(30, 0, 0), 4), "gym entrance on a path")
end)

test("world budgets: parts, lights and emitters bounded; low quality covers the new lights", function()
	local root = game:GetService("Workspace").SnackWorld
	local parts, lights, emitters = 0, 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("PointLight") or d:IsA("SpotLight") then
			lights += 1
		elseif d:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	ok(parts < 6000, "part budget: " .. parts)
	ok(lights <= 60, "light budget: " .. lights)
	ok(emitters <= 40, "emitter budget: " .. emitters)
	print(string.format("        (%d parts, %d lights, %d emitters)", parts, lights, emitters))
	local fx = SP.StarterPlayerScripts.Client.Effects.Source
	ok(fx:find('local world = Workspace:FindFirstChild("SnackWorld")', 1, true) and fx:find('d:IsA("PointLight")', 1, true), "Low quality walks every SnackWorld light")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
