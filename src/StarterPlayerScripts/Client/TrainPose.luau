--!strict
-- Procedural training pose: an overhead press on the player's own character, layered on
-- the Motor6D C0 of the shoulders (and elbows on R15). Animations keep driving
-- Motor6D.Transform, so walking/idle still play underneath; stop() puts every C0 back
-- exactly as it was. No animation assets are needed, so it works on R6 and R15 rigs.
--
-- Press cycle `s` (0..1): 0 = "goal post" (upper arms out, forearms up), 1 = arms
-- straight overhead.

local TrainPose = {}
TrainPose.__index = TrainPose

TrainPose.Period = 0.9 -- seconds per rep cycle
TrainPose.MaxSession = 180 -- a tapped session pauses itself after this many seconds

type Joint = { motor: Motor6D, base: CFrame, kind: string, side: number }

export type Pose = typeof(setmetatable({} :: { joints: { Joint }, weight: number }, TrainPose))

type Spec = { part: string, joint: string, kind: string, side: number }

local R15: { Spec } = {
	{ part = "RightUpperArm", joint = "RightShoulder", kind = "shoulder", side = 1 },
	{ part = "LeftUpperArm", joint = "LeftShoulder", kind = "shoulder", side = -1 },
	{ part = "RightLowerArm", joint = "RightElbow", kind = "elbow", side = 1 },
	{ part = "LeftLowerArm", joint = "LeftElbow", kind = "elbow", side = -1 },
}
local R6: { Spec } = {
	{ part = "Torso", joint = "Right Shoulder", kind = "r6shoulder", side = 1 },
	{ part = "Torso", joint = "Left Shoulder", kind = "r6shoulder", side = -1 },
}

-- Smooth 0 -> 1 -> 0 press for a time in seconds.
function TrainPose.phase(t: number): number
	return (1 - math.cos(2 * math.pi * t / TrainPose.Period)) / 2
end

-- Joint offset (applied after the rig's own C0) for one joint at press amount `s`.
-- R15 joints are axis-aligned: +Z rolls the right arm out to the side, -Z the left.
-- R6 shoulders are turned 90 degrees, so the same sideways raise is -X for both.
function TrainPose.offset(kind: string, side: number, s: number): CFrame
	local r = math.rad
	if kind == "shoulder" then
		return CFrame.Angles(0, 0, side * r(95 + 70 * s))
	elseif kind == "elbow" then
		return CFrame.Angles(0, 0, side * r(5 + 90 * (1 - s)))
	elseif kind == "r6shoulder" then
		return CFrame.Angles(-r(100 + 70 * s), 0, 0)
	end
	return CFrame.identity
end

function TrainPose.new(character: Model): Pose
	local joints: { Joint } = {}
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local r15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
	local specs: { Spec } = if r15 then R15 else R6
	for _, j in specs do
		local part = character:FindFirstChild(j.part)
		local motor = part and part:FindFirstChild(j.joint)
		if motor and motor:IsA("Motor6D") then
			table.insert(joints, { motor = motor, base = motor.C0, kind = j.kind, side = j.side })
		end
	end
	return setmetatable({ joints = joints, weight = 0 }, TrainPose)
end

-- Blends toward the pose (`weight` 0..1) at press amount `s`.
function TrainPose.apply(self: Pose, s: number, weight: number)
	self.weight = math.clamp(weight, 0, 1)
	for _, j in self.joints do
		if j.motor.Parent then
			j.motor.C0 = j.base * CFrame.identity:Lerp(TrainPose.offset(j.kind, j.side, s), self.weight)
		end
	end
end

-- Restores every joint exactly (safe to call twice, or after the character is gone).
function TrainPose.stop(self: Pose)
	for _, j in self.joints do
		if j.motor.Parent then
			j.motor.C0 = j.base
		end
	end
	table.clear(self.joints)
	self.weight = 0
end

return TrainPose
