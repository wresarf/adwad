--!strict
-- Pure inventory rules operating on a PlayerData.Data table: catching, equipping,
-- three-duplicate material fusion and rarity auto-sell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))
local GameMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameMath"))

local Inventory = {}

Inventory.FuseCount = 3

function Inventory.newPet(data: any, species: string, material: string, size: string): any
	local rec = {
		uid = "p" .. data.nextUid,
		species = species,
		material = material,
		size = size,
		equipped = false,
		locked = false,
	}
	data.nextUid += 1
	return rec
end

function Inventory.equippedCount(data: any): number
	local n = 0
	for _, p in data.pets do
		if p.equipped then
			n += 1
		end
	end
	return n
end

function Inventory.totalIncome(data: any): number
	local total = 0
	for _, p in data.pets do
		if p.equipped then
			total += GameMath.petIncome(p)
		end
	end
	return total
end

-- `capacity` defaults to the base limit; the server passes the session's real capacity
-- (Big Backpack owners get more).
function Inventory.isFull(data: any, capacity: number?): boolean
	return #data.pets >= (capacity or GameConfig.MaxPets)
end

function Inventory.shouldAutoSell(data: any, rec: any): boolean
	local threshold = data.settings.AutoSellRarity
	if threshold == "Off" then
		return false
	end
	if data.settings.KeepMutated and GameMath.isMutated(rec) then
		return false
	end
	local _, idx = GameMath.overallRarity(rec)
	return idx <= GameConfig.rarityIndex(threshold)
end

-- Adds a freshly caught pet. Returns ("kept" | "sold" | "full", coinsEarned).
function Inventory.catch(data: any, rec: any, slots: number, capacity: number?): (string, number)
	data.totalCatches += 1
	data.discovered[rec.species] = true
	if Inventory.shouldAutoSell(data, rec) then
		local value = GameMath.sellValue(rec)
		data.coins += value
		return "sold", value
	end
	if Inventory.isFull(data, capacity) then
		local value = GameMath.sellValue(rec)
		data.coins += value
		return "full", value
	end
	if Inventory.equippedCount(data) < slots then
		rec.equipped = true
	end
	table.insert(data.pets, rec)
	return "kept", 0
end

-- Adds a hatched or purchased pet (never auto-sold). Caller checks capacity first.
function Inventory.grant(data: any, rec: any, slots: number)
	data.discovered[rec.species] = true
	if Inventory.equippedCount(data) < slots then
		rec.equipped = true
	end
	table.insert(data.pets, rec)
end

-- Equips the `slots` highest-income pets. Returns the number equipped.
function Inventory.equipBest(data: any, slots: number): number
	local sorted: { any } = table.clone(data.pets)
	table.sort(sorted, function(a, b)
		local ia, ib = GameMath.petIncome(a), GameMath.petIncome(b)
		if ia == ib then
			return a.uid < b.uid
		end
		return ia > ib
	end)
	for _, p in data.pets do
		p.equipped = false
	end
	local n = math.min(slots, #sorted)
	for i = 1, n do
		sorted[i].equipped = true
	end
	return n
end

-- Sells every unequipped, unlocked pet that matches the auto-sell rules.
function Inventory.sellMatching(data: any): (number, number)
	local kept = {}
	local count, coins = 0, 0
	for _, p in data.pets do
		if not p.equipped and not p.locked and Inventory.shouldAutoSell(data, p) then
			count += 1
			coins += GameMath.sellValue(p)
		else
			table.insert(kept, p)
		end
	end
	data.pets = kept
	data.coins += coins
	return count, coins
end

-- Fuses three identical pets (species + material + size) into the next material tier.
function Inventory.fuse(data: any, key: string): (boolean, any)
	local matches = {}
	for i, p in data.pets do
		if GameMath.fuseKey(p) == key and not p.locked then
			table.insert(matches, i)
		end
	end
	if #matches < Inventory.FuseCount then
		return false, "Need 3 identical pets to fuse"
	end
	local first = data.pets[matches[1]]
	local nextMat = MutationConfig.nextMaterial(first.material)
	if not nextMat then
		return false, "Rainbow is already the best material"
	end
	-- Prefer consuming unequipped copies.
	table.sort(matches, function(a, b)
		local ea, eb = data.pets[a].equipped and 1 or 0, data.pets[b].equipped and 1 or 0
		if ea == eb then
			return a < b
		end
		return ea < eb
	end)
	local consumed = {}
	local wasEquipped = false
	for i = 1, Inventory.FuseCount do
		consumed[matches[i]] = true
		wasEquipped = wasEquipped or data.pets[matches[i]].equipped
	end
	local kept = {}
	for i, p in data.pets do
		if not consumed[i] then
			table.insert(kept, p)
		end
	end
	data.pets = kept
	local rec = Inventory.newPet(data, first.species, nextMat.id, first.size)
	rec.equipped = wasEquipped
	table.insert(data.pets, rec)
	data.discovered[first.species] = true
	return true, rec
end

-- Repeatedly fuses every eligible group (cascading Gold -> Diamond ...). Returns fusions made.
function Inventory.fuseAll(data: any): number
	local made = 0
	for _ = 1, 500 do
		local counts: { [string]: number } = {}
		local target: string? = nil
		for _, p in data.pets do
			if not p.locked and MutationConfig.nextMaterial(p.material) then
				local k = GameMath.fuseKey(p)
				counts[k] = (counts[k] or 0) + 1
				if counts[k] >= Inventory.FuseCount then
					target = k
					break
				end
			end
		end
		if not target then
			break
		end
		local ok = Inventory.fuse(data, target)
		if not ok then
			break
		end
		made += 1
	end
	return made
end

return Inventory
