--!nocheck
-- Dev tool: a tiny software renderer for the generated parts (no engine needed).
-- Perspective camera, painter's algorithm, flat Lambert shading. Boxes and wedges draw
-- per face; balls, sphere-meshed blocks and cylinders draw as the convex hull of sampled
-- surface points with a soft highlight. It is an approximation for reviewing silhouettes
-- and composition, NOT a Roblox screenshot (no shadows, textures, particles or decals).

local Render3D = {}

local function v3(x, y, z)
	return { x = x, y = y, z = z }
end
local function sub(a, b)
	return v3(a.x - b.x, a.y - b.y, a.z - b.z)
end
local function dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end
local function cross(a, b)
	return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end
local function norm(a)
	local m = math.sqrt(dot(a, a))
	return if m > 0 then v3(a.x / m, a.y / m, a.z / m) else v3(0, 1, 0)
end
local function fromV(v)
	return v3(v.X, v.Y, v.Z)
end

-- camera: eye, target, fov (deg), width, height
function Render3D.camera(eye, target, fov, w, h)
	local e, t = fromV(eye), fromV(target)
	local f = norm(sub(t, e))
	local r = norm(cross(f, v3(0, 1, 0)))
	local u = cross(r, f)
	return { e = e, f = f, r = r, u = u, w = w, h = h, k = (h / 2) / math.tan(math.rad(fov) / 2) }
end

local function project(cam, p)
	local d = sub(p, cam.e)
	local z = dot(d, cam.f)
	if z < 0.5 then
		return nil
	end
	return { cam.w / 2 + dot(d, cam.r) / z * cam.k, cam.h / 2 - dot(d, cam.u) / z * cam.k, z }
end

local function hull(points)
	table.sort(points, function(a, b)
		return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
	end)
	local function cr(o, a, b)
		return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
	end
	local lower, upper = {}, {}
	for _, q in points do
		while #lower >= 2 and cr(lower[#lower - 1], lower[#lower], q) <= 0 do
			table.remove(lower)
		end
		table.insert(lower, q)
	end
	for i = #points, 1, -1 do
		local q = points[i]
		while #upper >= 2 and cr(upper[#upper - 1], upper[#upper], q) <= 0 do
			table.remove(upper)
		end
		table.insert(upper, q)
	end
	table.remove(lower)
	table.remove(upper)
	for _, q in upper do
		table.insert(lower, q)
	end
	return lower
end

local function rgb(c, k, t)
	local function ch(v)
		return math.clamp(math.floor(v * k * 255 + 0.5), 0, 255)
	end
	return string.format("rgb(%d,%d,%d)", ch(c.R), ch(c.G), ch(c.B)), t
end

local SUN = norm(v3(-0.45, 0.85, -0.35))

local function shade(normal, material, neonName)
	if material == neonName then
		return 1.15
	end
	local l = dot(norm(normal), SUN)
	return 0.62 + 0.42 * math.max(0, l) + 0.08 * math.max(0, normal.y)
end

local function polyString(pts)
	local s = table.create(#pts)
	for i, q in pts do
		s[i] = string.format("%.1f,%.1f", q[1], q[2])
	end
	return table.concat(s, " ")
end

-- Collects drawable polygons for every visible BasePart under `roots`.
function Render3D.render(roots, cam, opts)
	opts = opts or {}
	local R = opts.roblox
	local Enum = R.Enum
	local neon = Enum.Material.Neon
	local items = {}
	local function push(depth, svg, layer)
		table.insert(items, { d = depth, s = svg, layer = layer or 0 })
	end
	local function partWorld(cf, x, y, z)
		local p = cf * R.Vector3.new(x, y, z)
		return v3(p.X, p.Y, p.Z)
	end
	local count = 0
	for _, root in roots do
		local list = root:GetDescendants()
		if root:IsA("BasePart") then
			table.insert(list, root)
		end
		for _, part in list do
			if part:IsA("BasePart") and part.Transparency < 0.97 then
				local cf, s = part.CFrame, part.Size
				local centre = fromV(cf.Position)
				local cp = project(cam, centre)
				local big = math.max(s.X, s.Y, s.Z) > (opts.bigSize or 60)
				if cp or big then
					count += 1
					local alpha = 1 - part.Transparency
					local mesh = part:FindFirstChildOfClass("SpecialMesh")
					local isBall = part:IsA("Part") and part.Shape == Enum.PartType.Ball
					local isCyl = part:IsA("Part") and part.Shape == Enum.PartType.Cylinder
					local isSphereMesh = mesh and mesh.MeshType == Enum.MeshType.Sphere
					local layer = if big then -1 else 0
					local depthBias = if big then 1e6 - centre.y * 10 else (cp and cp[3] or 1e5)
					if isBall or isSphereMesh or isCyl then
						-- Sample the surface and draw the projected hull.
						local pts = {}
						local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
						if mesh and mesh.Scale then
							hx, hy, hz = hx * mesh.Scale.X, hy * mesh.Scale.Y, hz * mesh.Scale.Z
						end
						if isBall then
							local r = math.min(s.X, s.Y, s.Z) / 2
							hx, hy, hz = r, r, r
						end
						if isCyl then
							for i = 0, 15 do
								local a = i / 16 * math.pi * 2
								for _, sx in { -1, 1 } do
									local q = project(cam, partWorld(cf, sx * hx, math.cos(a) * hy, math.sin(a) * hz))
									if q then
										table.insert(pts, q)
									end
								end
							end
						else
							for i = 0, 7 do
								local lat = (i / 7 - 0.5) * math.pi
								for j = 0, 11 do
									local lon = j / 12 * math.pi * 2
									local q = project(cam, partWorld(cf, math.cos(lat) * math.cos(lon) * hx, math.sin(lat) * hy, math.cos(lat) * math.sin(lon) * hz))
									if q then
										table.insert(pts, q)
									end
								end
							end
						end
						if #pts >= 3 then
							local h = hull(pts)
							local col = rgb(part.Color, shade(v3(0, 0.6, 0) , part.Material, neon))
							push(depthBias, string.format('<polygon points="%s" fill="%s" fill-opacity="%.2f"/>', polyString(h), col, alpha), layer)
							-- soft highlight toward the sun
							if not big and alpha > 0.5 then
								local hp = project(cam, partWorld(cf, -hx * 0.3, hy * 0.45, -hz * 0.3))
								if hp and cp then
									local rad = 0
									for _, q in h do
										rad = math.max(rad, math.sqrt((q[1] - cp[1]) ^ 2 + (q[2] - cp[2]) ^ 2))
									end
									push(depthBias - 0.01, string.format('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="white" fill-opacity="0.13"/>', hp[1], hp[2], rad * 0.35), layer)
								end
							end
						end
					else
						local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
						local faces
						if part:IsA("WedgePart") then
							-- wedge: slope from top-back to bottom-front (-Z is front)
							local A = { partWorld(cf, -hx, -hy, -hz), partWorld(cf, hx, -hy, -hz), partWorld(cf, hx, -hy, hz), partWorld(cf, -hx, -hy, hz) }
							local T = { partWorld(cf, -hx, hy, hz), partWorld(cf, hx, hy, hz) }
							faces = {
								{ A[1], A[2], A[3], A[4] },
								{ A[3], A[4], T[1], T[2] },
								{ A[1], A[2], T[2], T[1] },
								{ A[1], A[4], T[1] },
								{ A[2], A[3], T[2] },
							}
						else
							local c = {}
							for _, sx in { -1, 1 } do
								for _, sy in { -1, 1 } do
									for _, sz in { -1, 1 } do
										table.insert(c, partWorld(cf, sx * hx, sy * hy, sz * hz))
									end
								end
							end
							-- index: (sx,sy,sz) -> 1..8 in nested order
							local function I(sx, sy, sz)
								return c[(if sx > 0 then 4 else 0) + (if sy > 0 then 2 else 0) + (if sz > 0 then 1 else 0) + 1]
							end
							faces = {
								{ I(-1, 1, -1), I(1, 1, -1), I(1, 1, 1), I(-1, 1, 1) }, -- top
								{ I(-1, -1, -1), I(1, -1, -1), I(1, -1, 1), I(-1, -1, 1) }, -- bottom
								{ I(1, -1, -1), I(1, 1, -1), I(1, 1, 1), I(1, -1, 1) },
								{ I(-1, -1, -1), I(-1, 1, -1), I(-1, 1, 1), I(-1, -1, 1) },
								{ I(-1, -1, 1), I(1, -1, 1), I(1, 1, 1), I(-1, 1, 1) },
								{ I(-1, -1, -1), I(1, -1, -1), I(1, 1, -1), I(-1, 1, -1) },
							}
						end
						for _, f in faces do
							local n = norm(cross(sub(f[2], f[1]), sub(f[#f], f[1])))
							local mid = v3(0, 0, 0)
							for _, p in f do
								mid = v3(mid.x + p.x / #f, mid.y + p.y / #f, mid.z + p.z / #f)
							end
							if dot(n, sub(mid, centre)) < 0 then
								n = v3(-n.x, -n.y, -n.z)
							end
							if dot(n, sub(cam.e, mid)) > 0 then -- front facing
								local pts = {}
								local okAll = true
								for _, p in f do
									local q = project(cam, p)
									if not q then
										okAll = false
										break
									end
									table.insert(pts, q)
								end
								if okAll then
									local md = project(cam, mid)
									local col = rgb(part.Color, shade(n, part.Material, neon))
									push(if big then depthBias else (md and md[3] or depthBias), string.format('<polygon points="%s" fill="%s" fill-opacity="%.2f"/>', polyString(pts), col, alpha), layer)
								end
							end
						end
					end
				end
			end
		end
	end
	table.sort(items, function(a, b)
		if a.layer ~= b.layer then
			return a.layer < b.layer
		end
		return a.d > b.d
	end)
	local out = table.create(#items)
	for i, it in items do
		out[i] = it.s
	end
	return table.concat(out, "\n"), count
end

-- Whole SVG document with a sky gradient.
function Render3D.svg(roots, cam, opts)
	opts = opts or {}
	local body = Render3D.render(roots, cam, opts)
	local sky = opts.sky or { "#9fd3f0", "#e8f4f2" }
	return string.format(
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs><rect width="100%%" height="100%%" fill="%s"/>\n%s\n</svg>',
		cam.w, cam.h, cam.w, cam.h, sky[1], sky[2], if opts.flat then opts.flat else "url(#sky)", body
	)
end

Render3D.project = project
return Render3D
