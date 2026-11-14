--!strict
-- DataStore persistence with session locking. Every DataStore call is wrapped in pcall
-- with retries; when the DataStore is unavailable (e.g. Studio without API access) the
-- game stays fully playable and simply reports that progress will not be saved.
--
-- Session lock: the save holds `lock = { job, time }`. A server only loads a save it can
-- lock (free, its own, or stale), and every write is refused if another live server holds
-- the lock. That makes this server the only writer while the player is here, which is
-- what lets ProcessReceipt treat "saved" as "durably granted".

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local DataService = {}

DataService.MaxAttempts = 3
DataService.LockTimeout = 5 * 60 -- a lock not refreshed for this long belongs to a dead server
DataService.LockRetries = 6 -- wait for another server to release the lock (rejoin / teleport)
DataService.LockRetryDelay = 3

-- Minimal surface we use, so tests can inject a fake store.
export type Store = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
}

local store: Store? = nil
local storeError: string? = nil
local jobId = "studio"
do
	local ok, id = pcall(function()
		return game.JobId
	end)
	if ok and type(id) == "string" and id ~= "" then
		jobId = id
	end
end
local clock: () -> number = os.time
local sleep: (number) -> () = function(t)
	task.wait(t)
end

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result :: any
	else
		storeError = tostring(result)
		warn("[SnackForce] DataStore unavailable, progress will not persist:", storeError)
	end
end

-- Test hook: swap in a fake store, job id, clock and sleep.
function DataService._configure(opts: { store: Store?, reset: boolean?, jobId: string?, clock: (() -> number)?, sleep: ((number) -> ())? })
	if opts.store ~= nil then
		store = opts.store
	end
	if opts.reset then
		store = nil
	end
	jobId = opts.jobId or jobId
	clock = opts.clock or clock
	sleep = opts.sleep or sleep
end

local function key(userId: number): string
	return "player_" .. tostring(userId)
end

function DataService.isAvailable(): boolean
	return store ~= nil
end

local function lockedByOther(raw: any, now: number): boolean
	local lock = type(raw) == "table" and raw.lock or nil
	if type(lock) ~= "table" or type(lock.job) ~= "string" or type(lock.time) ~= "number" then
		return false
	end
	return lock.job ~= jobId and now - lock.time < DataService.LockTimeout
end

local function isApiError(msg: string): boolean
	return string.find(msg, "API", 1, true) ~= nil or string.find(msg, "403", 1, true) ~= nil
end

-- Returns (data, canSave). canSave=false means loading failed or another server holds the
-- save: never overwrite the real save with fresh defaults.
function DataService.load(userId: number): (PlayerData.Data, boolean)
	local ds = store
	if not ds then
		return PlayerData.defaults(), false
	end
	local attempt = 0
	local lockWaits = 0
	while attempt < DataService.MaxAttempts do
		attempt += 1
		local blocked = false
		local loaded: any = nil
		local ok, err = pcall(function()
			ds:UpdateAsync(key(userId), function(raw)
				local now = clock()
				if lockedByOther(raw, now) then
					blocked = true
					return nil -- cancel: leave the other server's save untouched
				end
				local value: any = if type(raw) == "table" then table.clone(raw) else PlayerData.defaults()
				value.lock = { job = jobId, time = now }
				loaded = value
				return value
			end)
		end)
		if ok and blocked then
			lockWaits += 1
			if lockWaits > DataService.LockRetries then
				warn(string.format("[SnackForce] Save for %d is locked by another server", userId))
				return PlayerData.defaults(), false
			end
			attempt -= 1 -- waiting for a lock is not a failed attempt
			sleep(DataService.LockRetryDelay)
		elseif ok then
			return PlayerData.sanitize(loaded), true
		else
			local msg = tostring(err)
			warn(string.format("[SnackForce] Load attempt %d failed for %d: %s", attempt, userId, msg))
			if isApiError(msg) then
				break -- Studio without API access: retrying will not help
			end
			sleep(attempt)
		end
	end
	return PlayerData.defaults(), false
end

-- Writes the save if this server still owns the lock. `release` drops the lock (player
-- leaving). Returns true only when the data is durably stored.
function DataService.save(userId: number, data: PlayerData.Data, release: boolean?): boolean
	local ds = store
	if not ds then
		return false
	end
	local payload: any = table.clone(data)
	payload.version = GameConfig.DataVersion
	for attempt = 1, DataService.MaxAttempts do
		local refused = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key(userId), function(raw)
				local now = clock()
				if lockedByOther(raw, now) then
					refused = true
					return nil
				end
				payload.lastOnline = now
				payload.lock = if release then nil else { job = jobId, time = now }
				return payload
			end)
		end)
		if ok then
			if refused then
				warn(string.format("[SnackForce] Save for %d refused: another server owns it", userId))
				return false
			end
			return true
		end
		warn(string.format("[SnackForce] Save attempt %d failed for %d: %s", attempt, userId, tostring(err)))
		if attempt < DataService.MaxAttempts then
			sleep(attempt)
		end
	end
	return false
end

return DataService
