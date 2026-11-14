--!strict
-- Client sound player. Two SoundGroups (Effects, Music) follow the player's Sfx / Music
-- settings. Every play makes a short-lived Sound that cleans itself up; per-cue
-- cooldowns, per-cue concurrency and a global voice cap keep rapid actions (held Train,
-- charge ticks) from stacking into noise. Spatial cues play from an invisible anchor at
-- the world position so distant landings fade out.

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SoundConfig"))

local Sound = {}
Sound.__index = Sound

export type Player = typeof(setmetatable(
	{} :: {
		sfx: SoundGroup,
		music: SoundGroup,
		voices: number,
		perCue: { [string]: number },
		lastPlay: { [string]: number },
		sfxOn: boolean,
		musicOn: boolean,
		track: Sound?,
	},
	Sound
))

local function group(name: string, volume: number): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = volume
	g.Parent = SoundService
	return g
end

function Sound.new(): Player
	local self = setmetatable({
		sfx = group("SnackEffects", 1),
		music = group("SnackMusic", SoundConfig.MusicVolume),
		voices = 0,
		perCue = {},
		lastPlay = {},
		sfxOn = true,
		musicOn = true,
		track = nil,
	}, Sound)
	return self
end

function Sound.setEnabled(self: Player, sfx: boolean, music: boolean)
	self.sfxOn = sfx
	self.sfx.Volume = if sfx then 1 else 0
	if music ~= self.musicOn or (music and not self.track) then
		self.musicOn = music
		self:_music()
	end
end

-- Starts / stops the optional music track (only when an id is configured).
function Sound._music(self: Player)
	if not self.musicOn or not SoundConfig.isConfigured(SoundConfig.MusicId) then
		if self.track then
			self.track:Destroy()
			self.track = nil
		end
		return
	end
	if self.track then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "Music"
	s.SoundId = "rbxassetid://" .. tostring(SoundConfig.MusicId)
	s.Looped = true
	s.Volume = 1
	s.SoundGroup = self.music
	s.Parent = self.music
	s:Play()
	self.track = s
end

local function release(self: Player, name: string)
	self.voices = math.max(0, self.voices - 1)
	self.perCue[name] = math.max(0, (self.perCue[name] or 1) - 1)
end

-- Plays a cue. `at` makes it spatial (if the cue allows), `pitch` scales every note.
function Sound.play(self: Player, name: string, at: Vector3?, pitch: number?)
	if not self.sfxOn then
		return
	end
	local cue = SoundConfig.Cues[name]
	if not cue then
		return
	end
	local now = os.clock()
	if cue.cooldown and now - (self.lastPlay[name] or -1e9) < cue.cooldown then
		return
	end
	if (self.perCue[name] or 0) >= (cue.maxConcurrent or 3) or self.voices >= SoundConfig.MaxVoices then
		return
	end
	self.lastPlay[name] = now
	local anchor: Attachment? = nil
	if at and cue.spatial then
		local terrain = Workspace:FindFirstChildOfClass("Terrain")
		if terrain then
			local a = Instance.new("Attachment")
			a.Name = "SoundAt"
			a.WorldPosition = at
			a.Parent = terrain
			anchor = a
		end
	end
	for _, note in cue.notes do
		self.voices += 1
		self.perCue[name] = (self.perCue[name] or 0) + 1
		local function fire()
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = SoundConfig.path(cue.file)
			s.Volume = cue.volume * (note.volume or 1)
			s.PlaybackSpeed = note.speed * (pitch or 1)
			s.SoundGroup = self.sfx
			local at3 = anchor
			if at3 then
				s.RollOffMode = Enum.RollOffMode.InverseTapered
				s.RollOffMinDistance = 12
				s.RollOffMaxDistance = SoundConfig.SpatialRange
				s.Parent = at3
			else
				s.Parent = self.sfx
			end
			local done = false
			local function finish()
				if done then
					return
				end
				done = true
				release(self, name)
				s:Destroy()
			end
			s.Ended:Connect(finish)
			s:Play()
			task.delay(4, finish) -- safety net if Ended never fires
		end
		if note.delay and note.delay > 0 then
			task.delay(note.delay, fire)
		else
			fire()
		end
	end
	if anchor then
		local a = anchor
		task.delay(5, function()
			a:Destroy()
		end)
	end
end

function Sound.destroy(self: Player)
	if self.track then
		self.track:Destroy()
		self.track = nil
	end
end

return Sound
