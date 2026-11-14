--!nocheck
-- Dev tool: renders review images of the built place without Roblox Studio.
--   lune run tests/snapshots.luau pets  <out.svg>            every species, 3/4 view
--   lune run tests/snapshots.luau world <out.svg> ex ey ez tx ty tz [fov] [w] [h]
-- Images are approximations from tests/render3d.luau (see its header), not screenshots.
local fs = require("@lune/fs")
local process = require("@lune/process")
local Runtime = require("./runtime")
local Render3D = require("./render3d")
local game = Runtime.loadPlace(process.env.PLACE or "SnackForce_PetToss.rbxl")
local R = Runtime.roblox
local RS = game:GetService("ReplicatedStorage")
local mode, out = process.args[1], process.args[2]

if mode == "pets" then
	local PetConfig = Runtime.requireModule(RS.Config.PetConfig)
	local Builder = Runtime.requireModule(RS.Shared.PetModelBuilder)
	local material = process.args[3] or "Normal"
	local size = process.args[4] or "Normal"
	local cols, cell = 7, 200
	local rows = math.ceil(#PetConfig.Pets / cols)
	local parts = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="100%%" height="100%%" fill="#f6efe0"/>', cols * cell, rows * (cell + 24)) }
	for i, pet in PetConfig.Pets do
		local model, h, w = Builder.build(pet.id, material, size, R.CFrame.new())
		local cf, fov = Builder.portraitCamera(h, w)
		local cam = Render3D.camera(cf.Position, cf.Position + cf.LookVector * 10, fov, cell, cell)
		local body = Render3D.render({ model }, cam, { roblox = R })
		local x, y = ((i - 1) % cols) * cell, ((i - 1) // cols) * (cell + 24)
		table.insert(parts, string.format('<g transform="translate(%d,%d)"><rect x="6" y="6" width="%d" height="%d" rx="14" fill="#fcf9f2" stroke="#d2c4a8"/>%s<text x="%d" y="%d" font-family="sans-serif" font-size="14" font-weight="700" text-anchor="middle" fill="#2e2a26">%s (%s)</text></g>', x, y, cell - 12, cell - 12, body, cell / 2, cell + 14, pet.name, pet.archetype))
	end
	table.insert(parts, "</svg>")
	fs.writeFile(out, table.concat(parts, "\n"))
	print("pets", #PetConfig.Pets)
elseif mode == "world" then
	local WB = Runtime.requireModule(game:GetService("ServerScriptService").Server.WorldBuilder)
	WB.build(game:GetService("Workspace"))
	local a = {}
	for i = 3, 11 do
		a[i] = tonumber(process.args[i])
	end
	local cam = Render3D.camera(R.Vector3.new(a[3], a[4], a[5]), R.Vector3.new(a[6], a[7], a[8]), a[9] or 70, a[10] or 1280, a[11] or 720)
	local svg = Render3D.svg({ game:GetService("Workspace").SnackWorld }, cam, { roblox = R, bigSize = 120 })
	fs.writeFile(out, svg)
	print("world ok")
end
