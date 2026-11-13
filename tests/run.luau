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
			ok(not s:find("rbxassetid") and not s:find("InsertService") and not s:find("LoadAsset") and not s:find("http", 1, true), "asset reference in " .. inst:GetFullName())
		end
	end
end)

print("\n[remote contract]")
test("Remotes folder matches RemoteContract exactly", function()
	local folder = RS.Remotes
	eq(#folder:GetChildren(), #RemoteContract.Remotes, "remote count")
	eq(#RemoteContract.Remotes, 12, "contract size: 10 original remotes + StorePurchase + HatchEgg")
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
	for _, p in MonetizationConfig.GamePasses do
		eq(p.id, 0, p.key .. " id")
		eq(p.price, nil, p.key .. " price")
	end
	for _, p in MonetizationConfig.Products do
		eq(p.id, 0, p.key .. " id")
		ok(p.gems > 0)
	end
	eq(MonetizationConfig.passById(0), nil)
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
	for _, p in MonetizationConfig.GamePasses do
		local okp, msg = m:promptPass(player, p.key)
		eq(okp, false)
		eq(msg, "Not available yet")
		eq(m:ownsPass(player, p), false, "unset pass is never owned")
	end
	for _, p in MonetizationConfig.Products do
		eq((m:promptProduct(player, p.key)), false)
	end
	eq(calls.prompt, 0, "no purchase prompt for unset ids")
	for _, l in m:catalog().passes do
		eq(l.status, "unset")
		eq(l.price, nil)
	end
	-- Pretend a pass and a product were configured.
	local pass, product = MonetizationConfig.GamePasses[1], MonetizationConfig.Products[1]
	pass.id, product.id = 777, 888
	m:refreshPrices()
	eq(m:catalog().passes[1].status, "ok")
	eq(m:catalog().passes[1].price, 99, "price comes from MarketplaceService")
	ok((m:promptPass(player, pass.key)))
	ok((m:promptProduct(player, product.key)))
	eq(calls.prompt, 2)
	ok(m:ownsPass(player, pass))
	price.IsForSale = false
	m:refreshPrices()
	eq(m:catalog().products[1].status, "offsale")
	eq((m:promptProduct(player, product.key)), false, "off-sale items don't prompt")
	pass.id, product.id = 0, 0
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
	eq(GameConfig.DataVersion, 3)
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
	ok(serverSrc:find("market:ownsPass(player, pass)", 1, true), "pass purchases re-verified server-side")
	for _, inst in SP:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			for _, api in { "PromptGamePassPurchase", "PromptProductPurchase", "UserOwnsGamePassAsync", "ProcessReceipt" } do
				ok(not inst.Source:find(api, 1, true), "client must not use " .. api)
			end
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

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
