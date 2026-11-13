--!strict
-- Pure progression rules (quests, discovery, offline earnings, gym). No services and no
-- yielding, so the server, the client's previews and the Lune test-suite all share it.

local Config = script.Parent.Parent:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local QuestConfig = require(Config:WaitForChild("QuestConfig"))

export type QuestSnapshot = {
	index: number,
	total: number,
	id: string,
	title: string,
	hint: string,
	progress: number,
	target: number,
	reward: number,
	focus: string?,
}

local Progression = {}

local function count(t: { [any]: any }?): number
	local n = 0
	if t then
		for _ in t do
			n += 1
		end
	end
	return n
end

-- Current value of a quest stat for a PlayerData.Data table.
function Progression.statValue(stat: string, data: any, income: number): number
	local stats = data.stats or {}
	if stat == "throws" then
		return data.totalThrows or 0
	elseif stat == "catches" then
		return data.totalCatches or 0
	elseif stat == "strength" then
		return data.strength or 0
	elseif stat == "distance" then
		return data.bestDistance or 0
	elseif stat == "foods" then
		return count(data.ownedFoods)
	elseif stat == "discovered" then
		return count(data.discovered)
	elseif stat == "income" then
		return income
	end
	local v = stats[stat]
	return if type(v) == "number" then v else 0
end

function Progression.questSnapshot(data: any, income: number): QuestSnapshot?
	local index = data.questIndex or 1
	local q = QuestConfig.get(index)
	if not q then
		return nil
	end
	return {
		index = index,
		total = #QuestConfig.Quests,
		id = q.id,
		title = q.title,
		hint = q.hint,
		progress = math.min(Progression.statValue(q.stat, data, income), q.target),
		target = q.target,
		reward = q.reward,
		focus = q.focus,
	}
end

-- Completes every quest that is already satisfied (in order), paying rewards.
-- Returns the list of completed quests.
function Progression.advanceQuests(data: any, income: number): { QuestConfig.Quest }
	local done = {}
	data.questIndex = data.questIndex or 1
	while true do
		local q = QuestConfig.get(data.questIndex)
		if not q or Progression.statValue(q.stat, data, income) < q.target then
			break
		end
		data.questIndex += 1
		data.coins += q.reward
		table.insert(done, q)
	end
	return done
end

function Progression.discoveryReward(speciesId: string): number
	local pet = PetConfig.get(speciesId)
	if not pet then
		return 0
	end
	return math.max(GameConfig.DiscoveryMinCoins, math.floor(pet.baseIncome * GameConfig.DiscoverySeconds))
end

-- Coins earned while offline for `elapsed` seconds at `income` coins/sec.
function Progression.offlineEarnings(income: number, elapsed: number): number
	if income <= 0 or elapsed ~= elapsed or elapsed < GameConfig.OfflineMinSeconds then
		return 0
	end
	local seconds = math.min(elapsed, GameConfig.OfflineMaxSeconds)
	return math.floor(income * seconds * GameConfig.OfflineRate)
end

local function flatDistance(a: Vector3, b: Vector3): number
	local o = a - b
	return Vector3.new(o.X, 0, o.Z).Magnitude
end

function Progression.inGym(position: Vector3): boolean
	return flatDistance(position, GameConfig.GymCenter) <= GameConfig.GymRadius
end

function Progression.nearThrowLine(position: Vector3, slack: number?): boolean
	return flatDistance(position, GameConfig.ThrowLineCenter) <= GameConfig.ThrowLineRadius - (slack or 0)
end

return Progression
