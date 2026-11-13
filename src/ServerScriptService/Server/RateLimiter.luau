--!strict
-- Per-player token buckets keyed by remote name. Call :clear(player) on leave.

export type Bucket = { tokens: number, last: number }
export type Limits = { [string]: { rate: number, burst: number } }

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: { limits: Limits, buckets: { [any]: { [string]: Bucket } }, clock: () -> number }, RateLimiter))

function RateLimiter.new(limits: Limits, clock: (() -> number)?): RateLimiter
	return setmetatable({ limits = limits, buckets = {}, clock = clock or os.clock }, RateLimiter)
end

-- Returns true if the call is allowed (and consumes a token).
function RateLimiter.allow(self: RateLimiter, key: any, remote: string): boolean
	local limit = self.limits[remote]
	if not limit then
		return false -- unknown remotes are always rejected
	end
	local perKey = self.buckets[key]
	if not perKey then
		perKey = {}
		self.buckets[key] = perKey
	end
	local now = self.clock()
	local b = perKey[remote]
	if not b then
		b = { tokens = limit.burst, last = now }
		perKey[remote] = b
	end
	b.tokens = math.min(limit.burst, b.tokens + (now - b.last) * limit.rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function RateLimiter.clear(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

return RateLimiter
