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
local GameMath = req(RS.Shared.GameMath)
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
	for _, n in { "BiomeConfig", "PetConfig", "MutationConfig", "FoodConfig" } do
		eq(Cfg:FindFirstChild(n).ClassName, "ModuleScript", n)
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
	eq(#RemoteContract.Remotes, 10, "contract size")
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
	for i = 1, 400 do
		pets[i] = { uid = "dup", species = if i % 2 == 0 then "Bunbun" else "FakePet", material = "Gold", size = "Huge", equipped = true }
	end
	local d = PlayerData.sanitize({ coins = 1e30, pets = pets, equippedFood = "MegaSteak", ownedFoods = { MegaSteak = true, Hacked = true }, settings = { AutoThrow = true, AutoSkipRarity = "Bogus" } })
	eq(d.coins, 1e15)
	eq(#d.pets, GameConfig.MaxPets)
	eq(Inventory.equippedCount(d), GameConfig.PlotPedestals)
	local seen = {}
	for _, p in d.pets do
		ok(not seen[p.uid], "unique uids")
		seen[p.uid] = true
	end
	eq(d.equippedFood, "MegaSteak")
	eq(d.ownedFoods.Hacked, nil)
	eq(d.settings.AutoThrow, false, "auto-throw needs unlock")
	eq(d.settings.AutoSkipRarity, "Epic")
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
	for _, key in { "coins", "strength", "income", "bestDistance", "streak", "comboMult", "equippedFood", "ownedFoods", "pets", "settings" } do
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
	local cravings = {}
	for _, z in BiomeConfig.allCravingZones() do
		cravings[z] = BiomeConfig.cravingOptions(z)[1]
	end
	while t < 6 * 3600 and not reached.Moon do
		t += 1
		d.coins += Inventory.totalIncome(d)
		for _ = 1, trainPerSec do
			d.strength += GameMath.trainGain(d.strength)
		end
		if t % throwEvery == 0 then
			local food = FoodConfig.get(d.equippedFood)
			local r = GameMath.computeThrow({ strength = d.strength, foodPower = food.power, foodLuck = food.luck, foodCraving = food.craving, charge = if rng() < 0.5 then 0.95 else 0.8, allowSweetSpot = true, streak = streak, zoneCravings = cravings, weatherSizeLuck = 1, weatherMaterialLuck = 1, weatherCravingBonus = 1, rng = rng })
			streak = r.streak
			d.coins += r.bonusCoins
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
		if t % 60 == 0 then
			Inventory.fuseAll(d)
			Inventory.equipBest(d, 8)
			d.settings.AutoSellRarity = "Uncommon"
			Inventory.sellMatching(d)
		end
	end
	for _, b in BiomeConfig.Biomes do
		ok(reached[b.id], "never reached " .. b.id)
	end
	ok(reached.Dunes < 10 * 60, "Dunes should be reached within 10 minutes")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
