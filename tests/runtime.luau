--!nocheck
-- Minimal headless Roblox runtime for Lune: loads the BUILT place file and executes its
-- ModuleScripts with a Roblox-like environment (game, script, require, datatypes).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Runtime = {}

-- Lune does not implement WaitForChild; emulate it for already-present children.
roblox.implementMethod("Instance", "WaitForChild", function(self, name, _timeout)
	local child = self:FindFirstChild(name)
	if not child then
		error(string.format("WaitForChild: %s is missing child %q", self:GetFullName(), name), 2)
	end
	return child
end)

-- Deterministic stand-in for Roblox's Random datatype.
local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ s = (seed or os.clock() * 1e6) % 2147483646 + 1 }, Random)
end
function Random:_next()
	self.s = (self.s * 16807) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * self:_next()
end
function Random:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end
function Random:NextUnitVector()
	local v = roblox.Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1))
	return if v.Magnitude > 0 then v.Unit else roblox.Vector3.new(0, 1, 0)
end

local taskShim = {
	wait = function()
		return 0
	end,
	spawn = function(f, ...)
		return f(...)
	end,
	defer = function(f, ...)
		return f(...)
	end,
	delay = function() end,
}

Runtime.warnings = {}

function Runtime.loadPlace(path: string)
	local bytes = fs.readFile(path)
	local game = roblox.deserializePlace(bytes)
	local cache = {}
	local loadingSet = {}

	local function makeEnv(scriptInst)
		local env
		env = {
			game = game,
			workspace = game:GetService("Workspace"),
			script = scriptInst,
			Instance = roblox.Instance,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			NumberRange = roblox.NumberRange,
			BrickColor = roblox.BrickColor,
			Random = Random,
			task = taskShim,
			warn = function(...)
				table.insert(Runtime.warnings, table.concat(table.pack(...) :: any, " "))
			end,
		}
		env.require = function(target)
			if typeof(target) == "Instance" then
				return Runtime.requireModule(target)
			end
			error("require expects a ModuleScript instance, got " .. typeof(target))
		end
		return env
	end

	function Runtime.requireModule(inst)
		if cache[inst] ~= nil then
			return cache[inst]
		end
		assert(inst.ClassName == "ModuleScript", "not a ModuleScript: " .. inst:GetFullName())
		assert(not loadingSet[inst], "cyclic require: " .. inst:GetFullName())
		loadingSet[inst] = true
		local chunk = luau.load(inst.Source, { debugName = inst:GetFullName(), environment = makeEnv(inst) })
		local result = chunk()
		loadingSet[inst] = nil
		cache[inst] = result
		return result
	end

	function Runtime.compile(inst)
		return luau.compile(inst.Source)
	end

	Runtime.game = game
	Runtime.bytes = #bytes
	return game
end

Runtime.roblox = roblox
return Runtime
