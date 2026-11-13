--!strict
-- 45-second weather events every 90 seconds, plus rotating biome cravings.
-- Times use Workspace:GetServerTimeNow() so clients can show synced countdowns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))

export type Snapshot = {
	active: boolean,
	id: string?,
	name: string?,
	description: string?,
	endsAt: number,
	nextAt: number,
	sizeLuck: number,
	materialLuck: number,
	cravingBonus: number,
	cravings: { [string]: string },
}

local WeatherService = {}
WeatherService.__index = WeatherService

export type WeatherService = typeof(setmetatable(
	{} :: {
		active: any?,
		lastId: string?,
		endsAt: number,
		nextAt: number,
		cravings: { [string]: string },
		rng: Random,
		clock: () -> number,
		onChange: (Snapshot) -> (),
		running: boolean,
	},
	WeatherService
))

function WeatherService.new(onChange: (Snapshot) -> (), clock: (() -> number)?): WeatherService
	local clockFn: () -> number = clock or function()
		return workspace:GetServerTimeNow()
	end
	local self = setmetatable({
		active = nil,
		lastId = nil,
		endsAt = 0,
		nextAt = clockFn() + GameConfig.FirstWeatherDelay,
		cravings = {},
		rng = Random.new(),
		clock = clockFn,
		onChange = onChange,
		running = false,
	}, WeatherService)
	self:rollCravings()
	return self
end

function WeatherService.rollCravings(self: WeatherService)
	for _, zone in BiomeConfig.allCravingZones() do
		local options = BiomeConfig.cravingOptions(zone)
		self.cravings[zone] = options[self.rng:NextInteger(1, #options)]
	end
end

function WeatherService.snapshot(self: WeatherService): Snapshot
	local w = self.active
	return {
		active = w ~= nil,
		id = if w then w.id else nil,
		name = if w then w.name else nil,
		description = if w then w.description else nil,
		endsAt = self.endsAt,
		nextAt = self.nextAt,
		sizeLuck = if w then w.sizeLuck else 1,
		materialLuck = if w then w.materialLuck else 1,
		cravingBonus = if w then w.cravingBonus else 1,
		cravings = table.clone(self.cravings),
	}
end

-- Advances the schedule; returns true if something changed.
function WeatherService.step(self: WeatherService): boolean
	local now = self.clock()
	if self.active and now >= self.endsAt then
		self.active = nil
		self.onChange(self:snapshot())
		return true
	end
	if not self.active and now >= self.nextAt then
		local options = {}
		for _, w in GameConfig.Weather do
			if w.id ~= self.lastId then
				table.insert(options, w)
			end
		end
		local chosen = options[self.rng:NextInteger(1, #options)]
		self.active = chosen
		self.lastId = chosen.id
		self.endsAt = now + GameConfig.WeatherDuration
		self.nextAt = now + GameConfig.WeatherInterval
		self:rollCravings()
		self.onChange(self:snapshot())
		return true
	end
	return false
end

function WeatherService.start(self: WeatherService)
	if self.running then
		return
	end
	self.running = true
	task.spawn(function()
		while self.running do
			local ok, err = pcall(self.step, self)
			if not ok then
				warn("[SnackForce] Weather step failed:", err)
			end
			task.wait(0.5)
		end
	end)
end

function WeatherService.stop(self: WeatherService)
	self.running = false
end

return WeatherService
