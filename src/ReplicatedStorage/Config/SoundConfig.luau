--!strict
-- Every sound the game plays. All effects use audio that ships inside the Roblox client
-- (`rbxasset://sounds/...`), so nothing is uploaded, nothing needs asset permissions and
-- nothing comes from the Toolbox. The file list was checked against the client's own
-- manifest (rbxManifest.txt in the MaximumADHD/Roblox-Client-Tracker mirror); see
-- docs/ART_AND_AUDIO.md. Distinct cues are made by pitch (PlaybackSpeed), volume and
-- layering: e.g. the reward chime is the slider tick played as a major arpeggio.
--
-- Music and ambience need real tracks, which the client does not ship. Their ids are 0
-- (off) until someone uploads or licenses a track they are allowed to use in this
-- experience; then set the id here and it plays in the Music group.

export type Note = { speed: number, delay: number?, volume: number? }
export type Cue = {
	file: string, -- one of BuiltIn
	volume: number,
	notes: { Note }, -- one entry per layered play
	spatial: boolean?, -- play at a world position (3D roll-off)
	maxConcurrent: number?,
	cooldown: number?, -- seconds between plays of this cue
}

local SoundConfig = {}

-- Built-in client sounds verified to exist in content/sounds.
SoundConfig.BuiltIn = {
	["volume_slider.ogg"] = true,
	["action_jump.mp3"] = true,
	["action_jump_land.mp3"] = true,
	["action_get_up.mp3"] = true,
	["action_swim.mp3"] = true,
	["action_falling.ogg"] = true,
	["action_footsteps_plastic.mp3"] = true,
	["impact_water.mp3"] = true,
	["impact_explosion_03.mp3"] = true,
}

local function arp(speeds: { number }, step: number, volume: number?): { Note }
	local out = {}
	for i, sp in speeds do
		table.insert(out, { speed = sp, delay = (i - 1) * step, volume = volume })
	end
	return out
end

-- Pitches for a major chord on the slider tick (1, 5/4, 3/2, 2).
local C, E, G, C2 = 1.0, 1.26, 1.5, 2.0

SoundConfig.Cues = {
	Click = { file = "volume_slider.ogg", volume = 0.18, notes = { { speed = 1.2 } }, cooldown = 0.05 },
	ChargeTick = { file = "volume_slider.ogg", volume = 0.12, notes = { { speed = 1 } }, maxConcurrent = 2 },
	SweetSpot = { file = "volume_slider.ogg", volume = 0.3, notes = arp({ G, C2 }, 0.05), cooldown = 0.3 },
	Throw = { file = "action_jump.mp3", volume = 0.45, notes = { { speed = 1.35 }, { speed = 0.9, delay = 0.03, volume = 0.5 } } },
	Land = { file = "action_jump_land.mp3", volume = 0.7, notes = { { speed = 0.85 } }, spatial = true },
	Splash = { file = "impact_water.mp3", volume = 0.5, notes = { { speed = 1.1 } }, spatial = true },
	Catch = { file = "volume_slider.ogg", volume = 0.28, notes = arp({ C, E, G }, 0.07) },
	Reward = { file = "volume_slider.ogg", volume = 0.3, notes = arp({ C, E, G, C2 }, 0.08), cooldown = 0.2 },
	Milestone = { file = "impact_explosion_03.mp3", volume = 0.18, notes = { { speed = 1.5 } }, cooldown = 1 },
	Buy = { file = "volume_slider.ogg", volume = 0.26, notes = arp({ E, G }, 0.06), cooldown = 0.1 },
	Error = { file = "volume_slider.ogg", volume = 0.26, notes = arp({ 0.75, 0.6 }, 0.09), cooldown = 0.25 },
	Train = { file = "action_jump_land.mp3", volume = 0.16, notes = { { speed = 1.9 } }, maxConcurrent = 2, cooldown = 0.1 },
	Fuse = { file = "impact_explosion_03.mp3", volume = 0.12, notes = { { speed = 2.2 } }, cooldown = 0.4 },
	Wobble = { file = "volume_slider.ogg", volume = 0.2, notes = { { speed = 0.8 } } },
	Hatch = { file = "impact_explosion_03.mp3", volume = 0.14, notes = { { speed = 1.8 } } },
	Weather = { file = "volume_slider.ogg", volume = 0.22, notes = arp({ G, E, C }, 0.12), cooldown = 2 },
} :: { [string]: Cue }

SoundConfig.SpatialRange = 220 -- studs: landings far down the lane fade out
SoundConfig.MaxVoices = 12 -- total effect sounds alive at once

-- Music / ambience: 0 = off. Only ids you are allowed to use in this experience.
SoundConfig.MusicId = 0
SoundConfig.MusicVolume = 0.25

function SoundConfig.isConfigured(id: any): boolean
	return type(id) == "number" and id > 0 and id == math.floor(id)
end

function SoundConfig.path(file: string): string
	return "rbxasset://sounds/" .. file
end

-- Problems with the cue table (empty = valid). Used by the test-suite.
function SoundConfig.validate(): { string }
	local problems = {}
	for name, cue in SoundConfig.Cues do
		if not SoundConfig.BuiltIn[cue.file] then
			table.insert(problems, name .. ": " .. cue.file .. " is not a verified built-in sound")
		end
		if #cue.notes == 0 or cue.volume <= 0 or cue.volume > 1 then
			table.insert(problems, name .. ": bad notes or volume")
		end
	end
	return problems
end

return SoundConfig
