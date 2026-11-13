--!strict
-- DataStore persistence. Every DataStore call is wrapped in pcall with retries; when the
-- DataStore is unavailable (e.g. Studio without API access) the game stays fully playable
-- and simply reports that progress will not be saved.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local DataService = {}

local MAX_ATTEMPTS = 3

local store: GlobalDataStore? = nil
local storeError: string? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result
	else
		storeError = tostring(result)
		warn("[SnackForce] DataStore unavailable, progress will not persist:", storeError)
	end
end

local function key(userId: number): string
	return "player_" .. tostring(userId)
end

function DataService.isAvailable(): boolean
	return store ~= nil
end

-- Returns (data, canSave). canSave=false means loading failed: never overwrite the real
-- save with fresh defaults.
function DataService.load(userId: number): (PlayerData.Data, boolean)
	local ds = store
	if not ds then
		return PlayerData.defaults(), false
	end
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(function()
			return ds:GetAsync(key(userId))
		end)
		if ok then
			return PlayerData.sanitize(result), true
		end
		local msg = tostring(result)
		warn(string.format("[SnackForce] Load attempt %d failed for %d: %s", attempt, userId, msg))
		if string.find(msg, "API", 1, true) or string.find(msg, "403", 1, true) then
			break -- Studio without API access: retrying will not help
		end
		task.wait(attempt)
	end
	return PlayerData.defaults(), false
end

function DataService.save(userId: number, data: PlayerData.Data): boolean
	local ds = store
	if not ds then
		return false
	end
	local payload = table.clone(data)
	payload.version = GameConfig.DataVersion
	for attempt = 1, MAX_ATTEMPTS do
		local ok, err = pcall(function()
			ds:UpdateAsync(key(userId), function()
				return payload
			end)
		end)
		if ok then
			return true
		end
		warn(string.format("[SnackForce] Save attempt %d failed for %d: %s", attempt, userId, tostring(err)))
		if attempt < MAX_ATTEMPTS then
			task.wait(attempt)
		end
	end
	return false
end

return DataService
