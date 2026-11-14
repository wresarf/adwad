-- Dev tool: renders a top-down SVG of the generated world from the built place.
-- Usage: lune run tests/map.luau <xMin> <xMax> <zMin> <zMax> <pixelsPerStud> <out.svg>
local fs = require("@lune/fs")
local process = require("@lune/process")
local Runtime = require("./runtime")
local game = Runtime.loadPlace("SnackForce_PetToss.rbxl")
local R = Runtime.roblox
local WB = Runtime.requireModule(game:GetService("ServerScriptService").Server.WorldBuilder)
WB.build(game:GetService("Workspace"))
local x0, x1, z0, z1 = tonumber(process.args[1]), tonumber(process.args[2]), tonumber(process.args[3]), tonumber(process.args[4])
local scale = tonumber(process.args[5]) or 2
local parts = {}
for _, d in game:GetService("Workspace").SnackWorld:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 0.95 then
		local cf, s = d.CFrame, d.Size
		local top = cf.Position.Y + math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
		table.insert(parts, { d = d, top = top })
	end
end
table.sort(parts, function(a, b) return a.top < b.top end)
local out = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" style="background:#223">', (x1 - x0) * scale, (z1 - z0) * scale) }
for _, p in parts do
	local d = p.d
	local cf, s = d.CFrame, d.Size
	local c = d.Color
	local col = string.format("rgb(%d,%d,%d)", c.R * 255, c.G * 255, c.B * 255)
	local isBall = d:IsA("Part") and d.Shape == R.Enum.PartType.Ball
	local isCyl = d:IsA("Part") and d.Shape == R.Enum.PartType.Cylinder
	if isCyl and math.abs(cf.RightVector.Y) > 0.9 then
		local pos = cf.Position
		table.insert(out, string.format('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="#000" stroke-width="0.3"/>', (pos.X - x0) * scale, (pos.Z - z0) * scale, s.Y / 2 * scale, col))
	elseif isBall then
		local pos = cf.Position
		table.insert(out, string.format('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s" stroke="#000" stroke-width="0.3"/>', (pos.X - x0) * scale, (pos.Z - z0) * scale, s.X / 2 * scale, s.Z / 2 * scale, col))
	else
		local pts = {}
		local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
		-- project the 8 corners, take convex-ish: use 4 corners of the face whose normal is most vertical
		local corners = {}
		for _, sx in { -1, 1 } do for _, sy in { -1, 1 } do for _, sz in { -1, 1 } do
			table.insert(corners, cf * R.Vector3.new(sx * hx, sy * hy, sz * hz))
		end end end
		-- convex hull in XZ (gift wrap)
		local P = {}
		for _, v in corners do table.insert(P, { v.X, v.Z }) end
		table.sort(P, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
		local function cross(o, a, b) return (a[1]-o[1])*(b[2]-o[2]) - (a[2]-o[2])*(b[1]-o[1]) end
		local lower, upper = {}, {}
		for _, q in P do while #lower >= 2 and cross(lower[#lower-1], lower[#lower], q) <= 0 do table.remove(lower) end table.insert(lower, q) end
		for i = #P, 1, -1 do local q = P[i] while #upper >= 2 and cross(upper[#upper-1], upper[#upper], q) <= 0 do table.remove(upper) end table.insert(upper, q) end
		table.remove(lower) table.remove(upper)
		for _, q in lower do table.insert(pts, string.format("%.1f,%.1f", (q[1] - x0) * scale, (q[2] - z0) * scale)) end
		for _, q in upper do table.insert(pts, string.format("%.1f,%.1f", (q[1] - x0) * scale, (q[2] - z0) * scale)) end
		table.insert(out, string.format('<polygon points="%s" fill="%s" stroke="#000" stroke-width="0.3"/>', table.concat(pts, " "), col))
	end
end
table.insert(out, "</svg>")
fs.writeFile(process.args[6], table.concat(out, "\n"))
print("ok", #parts)
