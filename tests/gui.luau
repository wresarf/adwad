--!nocheck
-- Dev tool + test helper: builds the REAL client HUD (Client/Hud + Client/Panels from the
-- built place) headlessly with fake engine services, then lays it out and draws it as
-- SVG. The layout engine is an approximation of Roblox's (Size/Position/AnchorPoint,
-- UIPadding, UIListLayout, UIGridLayout, AutomaticSize with estimated text metrics,
-- ScrollingFrame clipping, Sibling ZIndex). Text widths are estimated, fonts are
-- substitutes, and 3D previews are drawn with tests/render3d.luau. Use it to review
-- composition and catch overlaps, not as a pixel-accurate screenshot.
--
--   lune run tests/gui.luau <scenario> <out.svg> [width height touch]
-- Scenarios: hud, charging, pets, shop, upgrades, store, eggs, hatch, fuse, catch, catchpreview,
--            training, zone, away, welcome, settings, index, help

local Runtime = require("./runtime")
local Render3D = require("./render3d")

local Gui = {}
local Enum = Runtime.roblox.Enum

------------------------------------------------------------------ fake engine

local function signal()
	local s = {}
	function s:Connect(fn)
		return { Disconnect = function() end, Connected = true }
	end
	function s:Once(fn)
		return self:Connect(fn)
	end
	function s:Wait() end
	return s
end

local installed = false
local function installShims(R)
	if installed then
		return
	end
	installed = true
	for _, ev in { "Activated", "MouseButton1Down", "MouseButton1Up", "MouseButton1Click", "MouseEnter", "MouseLeave" } do
		R.implementProperty("GuiButton", ev, function()
			return signal()
		end)
	end
	for _, ev in { "InputBegan", "InputEnded", "InputChanged" } do
		R.implementProperty("GuiObject", ev, function()
			return signal()
		end)
	end
	R.implementProperty("Instance", "Destroying", function()
		return signal()
	end)
	R.implementMethod("Instance", "GetPropertyChangedSignal", function()
		return signal()
	end)
	R.implementMethod("Instance", "AddTag", function() end)
end

-- Builds a module loader whose `game` hands out fake client services.
function Gui.boot(placePath: string, viewport, touch: boolean)
	local game = Runtime.loadPlace(placePath)
	local R = Runtime.roblox
	installShims(R)
	local luau = require("@lune/luau")
	local camera = { ViewportSize = viewport }
	function camera:GetPropertyChangedSignal()
		return signal()
	end
	local fakeWorkspace = {
		CurrentCamera = camera,
		GetPropertyChangedSignal = function()
			return signal()
		end,
		GetServerTimeNow = function()
			return 1000
		end,
	}
	local services = {
		UserInputService = { TouchEnabled = touch, KeyboardEnabled = not touch, GamepadEnabled = false },
		GuiService = {
			ReducedMotionEnabled = false,
			GetGuiInset = function()
				return R.Vector2.new(0, 0), R.Vector2.new(0, 0)
			end,
		},
		TweenService = {
			Create = function(_, inst, _info, props)
				return {
					Play = function()
						for k, v in props do
							inst[k] = v
						end
					end,
					Completed = signal(),
					Cancel = function() end,
				}
			end,
		},
		Workspace = fakeWorkspace,
		RunService = { RenderStepped = signal(), Heartbeat = signal(), IsStudio = function()
			return true
		end },
		Players = { LocalPlayer = {} },
	}
	local fakeGame = setmetatable({}, {
		__index = function(_, k)
			if k == "GetService" then
				return function(_, name)
					return services[name] or game:GetService(name)
				end
			end
			return game[k]
		end,
	})
	local cache = {}
	local function load(inst)
		if cache[inst] then
			return cache[inst]
		end
		local env = {
			game = fakeGame,
			workspace = fakeWorkspace,
			script = inst,
			Instance = R.Instance,
			Vector3 = R.Vector3,
			Vector2 = R.Vector2,
			CFrame = R.CFrame,
			Color3 = R.Color3,
			Enum = R.Enum,
			UDim = R.UDim,
			UDim2 = R.UDim2,
			ColorSequence = R.ColorSequence,
			ColorSequenceKeypoint = R.ColorSequenceKeypoint,
			NumberSequence = R.NumberSequence,
			NumberSequenceKeypoint = R.NumberSequenceKeypoint,
			NumberRange = R.NumberRange,
			BrickColor = R.BrickColor,
			TweenInfo = { new = function()
				return {}
			end },
			Random = Random,
			task = {
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
			},
			warn = function() end,
			os = os,
		}
		env.require = function(t)
			return load(t)
		end
		local chunk = luau.load(inst.Source, { debugName = inst:GetFullName(), environment = env })
		local result = chunk()
		cache[inst] = result
		return result
	end
	return { game = game, R = R, load = load }
end

------------------------------------------------------------------ layout

local function textWidth(text: string, size: number, font): number
	local w = 0
	for _, cp in utf8.codes(text) do
		if cp > 0x2190 then
			w += size * 1.05 -- emoji / symbols
		elseif cp == 32 then
			w += size * 0.26
		elseif cp >= 65 and cp <= 90 then
			w += size * 0.6
		else
			w += size * 0.5
		end
	end
	local name = tostring(font)
	if name:find("FredokaOne") then
		w *= 1.06
	end
	return w
end

local function wrapLines(text: string, size: number, font, maxW: number, wrap: boolean): { string }
	local lines = {}
	for para in (text .. "\n"):gmatch("(.-)\n") do
		if not wrap or maxW <= 0 then
			table.insert(lines, para)
		else
			local line = ""
			for word in para:gmatch("%S+") do
				local candidate = if line == "" then word else line .. " " .. word
				if line ~= "" and textWidth(candidate, size, font) > maxW then
					table.insert(lines, line)
					line = word
				else
					line = candidate
				end
			end
			table.insert(lines, line)
		end
	end
	return lines
end

local function isText(inst)
	return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
end

local function padding(inst)
	local p = inst:FindFirstChildOfClass("UIPadding")
	if not p then
		return 0, 0, 0, 0
	end
	return p.PaddingTop.Offset, p.PaddingRight.Offset, p.PaddingBottom.Offset, p.PaddingLeft.Offset
end

local function guiChildren(inst)
	local out = {}
	for i, c in inst:GetChildren() do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(out, { inst = c, order = i })
		end
	end
	return out
end

local function layoutOf(inst)
	return inst:FindFirstChildOfClass("UIListLayout"), inst:FindFirstChildOfClass("UIGridLayout")
end

local function sorted(kids)
	table.sort(kids, function(a, b)
		if a.inst.LayoutOrder ~= b.inst.LayoutOrder then
			return a.inst.LayoutOrder < b.inst.LayoutOrder
		end
		return a.order < b.order
	end)
	return kids
end

local measure

-- Base size from Size against the parent's content size, then AutomaticSize growth.
measure = function(inst, parentW, parentH)
	local sz = inst.Size
	local w = parentW * sz.X.Scale + sz.X.Offset
	local h = parentH * sz.Y.Scale + sz.Y.Offset
	local auto = inst.AutomaticSize
	local autoX = auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY
	local autoY = auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY
	if not (autoX or autoY) then
		return w, h
	end
	local pt, pr, pb, pl = padding(inst)
	local cw, ch = 0, 0
	if isText(inst) and inst.Text ~= "" then
		local maxW = if autoX then 0 else w - pl - pr
		local lines = wrapLines(inst.Text, inst.TextSize, inst.Font, maxW, inst.TextWrapped and not autoX)
		for _, l in lines do
			cw = math.max(cw, textWidth(l, inst.TextSize, inst.Font))
		end
		ch = #lines * inst.TextSize * 1.18
	end
	local list, grid = layoutOf(inst)
	local innerW = (if autoX then 0 else w) - pl - pr
	local kids = sorted(guiChildren(inst))
	if list then
		local gap = list.Padding.Offset
		local horiz = list.FillDirection == Enum.FillDirection.Horizontal
		local total, cross = 0, 0
		for i, k in kids do
			local kw, kh = measure(k.inst, math.max(innerW, 0), 0)
			if horiz then
				total += kw + (if i > 1 then gap else 0)
				cross = math.max(cross, kh)
			else
				total += kh + (if i > 1 then gap else 0)
				cross = math.max(cross, kw)
			end
		end
		if horiz then
			cw, ch = math.max(cw, total), math.max(ch, cross)
		else
			cw, ch = math.max(cw, cross), math.max(ch, total)
		end
	elseif grid then
		local cell, pad = grid.CellSize, grid.CellPadding
		local colsN = math.max(1, math.floor((innerW + pad.X.Offset) / (cell.X.Offset + pad.X.Offset)))
		local rows = math.ceil(#kids / colsN)
		ch = math.max(ch, rows * cell.Y.Offset + math.max(0, rows - 1) * pad.Y.Offset)
		cw = math.max(cw, math.min(#kids, colsN) * (cell.X.Offset + pad.X.Offset))
	else
		for _, k in kids do
			local kw, kh = measure(k.inst, math.max(innerW, 0), 0)
			local p = k.inst.Position
			cw = math.max(cw, p.X.Offset + kw)
			ch = math.max(ch, p.Y.Offset + kh)
		end
	end
	if autoX then
		w = math.max(w, cw + pl + pr)
	end
	if autoY then
		h = math.max(h, ch + pt + pb)
	end
	return w, h
end

-- Assigns absolute rects: node.rect = {x, y, w, h}. Returns a flat list in draw order.
local function place(inst, x, y, w, h, clip, out, depth)
	local node = { inst = inst, x = x, y = y, w = w, h = h, clip = clip, depth = depth }
	table.insert(out, node)
	local pt, pr, pb, pl = padding(inst)
	local cx, cy, cwid, chei = x + pl, y + pt, w - pl - pr, h - pt - pb
	local childClip = clip
	if inst:IsA("ScrollingFrame") or (inst:IsA("GuiObject") and inst.ClipsDescendants) then
		childClip = { x, y, w, h }
	end
	local list, grid = layoutOf(inst)
	local kids = guiChildren(inst)
	-- Sibling ZIndex draw order (stable).
	local drawOrder = {}
	if list then
		sorted(kids)
		local gap = list.Padding.Offset
		local horiz = list.FillDirection == Enum.FillDirection.Horizontal
		local sizes, total = {}, 0
		for i, k in kids do
			local kw, kh = measure(k.inst, cwid, chei)
			sizes[i] = { kw, kh }
			total += (if horiz then kw else kh) + (if i > 1 then gap else 0)
		end
		local cursor = if horiz then cx else cy
		if horiz and list.HorizontalAlignment == Enum.HorizontalAlignment.Center then
			cursor = cx + (cwid - total) / 2
		elseif horiz and list.HorizontalAlignment == Enum.HorizontalAlignment.Right then
			cursor = cx + cwid - total
		end
		for i, k in kids do
			local kw, kh = sizes[i][1], sizes[i][2]
			local kx, ky
			if horiz then
				kx = cursor
				ky = if list.VerticalAlignment == Enum.VerticalAlignment.Center then cy + (chei - kh) / 2 elseif list.VerticalAlignment == Enum.VerticalAlignment.Bottom then cy + chei - kh else cy
				cursor += kw + gap
			else
				ky = cursor
				kx = if list.HorizontalAlignment == Enum.HorizontalAlignment.Center then cx + (cwid - kw) / 2 elseif list.HorizontalAlignment == Enum.HorizontalAlignment.Right then cx + cwid - kw else cx
				cursor += kh + gap
			end
			table.insert(drawOrder, { k = k, r = { kx, ky, kw, kh } })
		end
	elseif grid then
		sorted(kids)
		local cell, pad = grid.CellSize, grid.CellPadding
		local cwC, chC = cell.X.Offset + cwid * cell.X.Scale, cell.Y.Offset
		local colsN = math.max(1, math.floor((cwid + pad.X.Offset) / (cwC + pad.X.Offset)))
		for i, k in kids do
			local col, row = (i - 1) % colsN, (i - 1) // colsN
			table.insert(drawOrder, { k = k, r = { cx + col * (cwC + pad.X.Offset), cy + row * (chC + pad.Y.Offset), cwC, chC } })
		end
	else
		for _, k in kids do
			local kw, kh = measure(k.inst, cwid, chei)
			local p, a = k.inst.Position, k.inst.AnchorPoint
			local kx = cx + cwid * p.X.Scale + p.X.Offset - a.X * kw
			local ky = cy + chei * p.Y.Scale + p.Y.Offset - a.Y * kh
			table.insert(drawOrder, { k = k, r = { kx, ky, kw, kh } })
		end
	end
	table.sort(drawOrder, function(a, b)
		if a.k.inst.ZIndex ~= b.k.inst.ZIndex then
			return a.k.inst.ZIndex < b.k.inst.ZIndex
		end
		return a.k.order < b.k.order
	end)
	for _, d in drawOrder do
		local sc = d.k.inst:FindFirstChildOfClass("UIScale")
		local s = if sc then sc.Scale else 1
		if sc and (d.k.inst.Name == "Root" or d.k.inst.Name == "Popups") then
			-- The HUD's scaled layers: lay out at logical size, draw scaled.
			local lw, lh = d.r[3], d.r[4]
			local sub = {}
			place(d.k.inst, 0, 0, lw, lh, nil, sub, depth + 1)
			table.insert(out, { group = sub, scale = s, x = d.r[1], y = d.r[2] })
		else
			place(d.k.inst, d.r[1], d.r[2], d.r[3], d.r[4], childClip, out, depth + 1)
		end
	end
	return out
end

------------------------------------------------------------------ drawing

local function col(c)
	return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function esc(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
local function fontAttrs(font)
	local name = tostring(font)
	if name:find("FredokaOne") then
		return "'Fredoka One','Fredoka','Baloo 2','Nunito',sans-serif", 700
	elseif name:find("ExtraBold") or name:find("Heavy") then
		return "'Builder Sans','Inter','Noto Sans',sans-serif", 800
	elseif name:find("Medium") then
		return "'Builder Sans','Inter','Noto Sans',sans-serif", 500
	end
	return "'Builder Sans','Inter','Noto Sans',sans-serif", 700
end

local clipId = 0
local function draw(nodes, svg, R)
	for _, n in nodes do
		if n.group then
			table.insert(svg, string.format('<g transform="translate(%.1f,%.1f) scale(%.4f)">', n.x, n.y, n.scale))
			draw(n.group, svg, R)
			table.insert(svg, "</g>")
		else
			local inst = n.inst
			local open = false
			if n.clip then
				clipId += 1
				table.insert(svg, string.format('<clipPath id="c%d"><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f"/></clipPath><g clip-path="url(#c%d)">', clipId, n.clip[1], n.clip[2], n.clip[3], n.clip[4], clipId))
				open = true
			end
			if inst:IsA("GuiObject") then
				local corner = inst:FindFirstChildOfClass("UICorner")
				local r = if corner then math.min(corner.CornerRadius.Offset + corner.CornerRadius.Scale * math.min(n.w, n.h), n.w / 2, n.h / 2) else 0
				local stroke = nil
				for _, c in inst:GetChildren() do
					if c:IsA("UIStroke") and c.Enabled ~= false then
						stroke = c
					end
				end
				local bgT = inst.BackgroundTransparency
				if bgT < 0.99 and not inst:IsA("ViewportFrame") then
					local st = ""
					if stroke and not isText(inst) or (stroke and isText(inst) and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border) then
						st = string.format(' stroke="%s" stroke-opacity="%.2f" stroke-width="%.1f"', col(stroke.Color), 1 - stroke.Transparency, stroke.Thickness)
					end
					table.insert(svg, string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s" fill-opacity="%.2f"%s/>', n.x, n.y, math.max(n.w, 0), math.max(n.h, 0), r, col(inst.BackgroundColor3), 1 - bgT, st))
				elseif stroke and not isText(inst) then
					table.insert(svg, string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="none" stroke="%s" stroke-opacity="%.2f" stroke-width="%.1f"/>', n.x, n.y, n.w, n.h, r, col(stroke.Color), 1 - stroke.Transparency, stroke.Thickness))
				end
				if inst:IsA("ViewportFrame") then
					local cam = inst:FindFirstChildOfClass("Camera") -- (Lune lacks the CurrentCamera ref)
					local model = inst:FindFirstChildOfClass("Model")
					if cam and model and n.w > 4 and n.h > 4 then
						local cf = cam.CFrame
						local c3 = Render3D.camera(cf.Position, cf.Position + cf.LookVector * 10, cam.FieldOfView, n.w, n.h)
						local body = Render3D.render({ model }, c3, { roblox = R })
						table.insert(svg, string.format('<g transform="translate(%.1f,%.1f)">%s</g>', n.x, n.y, body))
					end
				end
				if isText(inst) and inst.Text ~= "" and inst.TextTransparency < 0.99 then
					local pt, pr, pb, pl = padding(inst)
					local tx, ty, tw, th = n.x + pl, n.y + pt, n.w - pl - pr, n.h - pt - pb
					local lines = wrapLines(inst.Text, inst.TextSize, inst.Font, tw, inst.TextWrapped)
					local lh = inst.TextSize * 1.18
					local total = #lines * lh
					local y0 = if inst.TextYAlignment == Enum.TextYAlignment.Top then ty elseif inst.TextYAlignment == Enum.TextYAlignment.Bottom then ty + th - total else ty + (th - total) / 2
					local anchor, ax = "start", tx
					if inst.TextXAlignment == Enum.TextXAlignment.Center then
						anchor, ax = "middle", tx + tw / 2
					elseif inst.TextXAlignment == Enum.TextXAlignment.Right then
						anchor, ax = "end", tx + tw
					end
					local family, weight = fontAttrs(inst.Font)
					local outline = ""
					if stroke and stroke.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Border then
						outline = string.format(' stroke="%s" stroke-opacity="%.2f" stroke-width="%.1f" paint-order="stroke"', col(stroke.Color), 1 - stroke.Transparency, stroke.Thickness * 2)
					end
					for i, l in lines do
						table.insert(svg, string.format('<text x="%.1f" y="%.1f" font-family="%s" font-weight="%d" font-size="%d" fill="%s" fill-opacity="%.2f" text-anchor="%s"%s>%s</text>', ax, y0 + (i - 1) * lh + inst.TextSize * 0.92, family, weight, inst.TextSize, col(inst.TextColor3), 1 - inst.TextTransparency, anchor, outline, esc(l)))
					end
				end
			end
			if open then
				table.insert(svg, "</g>")
			end
		end
	end
end

-- Lays out every ScreenGui under `playerGui` for a viewport and returns an SVG string.
function Gui.svg(playerGui, viewport, R, background: string?)
	local svg = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', viewport.X, viewport.Y, viewport.X, viewport.Y) }
	if background then
		table.insert(svg, background)
	end
	local nodes = {}
	for _, sg in playerGui:GetChildren() do
		if sg:IsA("ScreenGui") and sg.Enabled then
			place(sg, 0, 0, viewport.X, viewport.Y, nil, nodes, 0)
		end
	end
	draw(nodes, svg, R)
	table.insert(svg, "</svg>")
	return table.concat(svg, "\n")
end

-- Absolute (screen-space) rects of named top-level HUD regions, for overlap checks.
function Gui.rects(playerGui, viewport)
	local nodes = {}
	for _, sg in playerGui:GetChildren() do
		if sg:IsA("ScreenGui") then
			place(sg, 0, 0, viewport.X, viewport.Y, nil, nodes, 0)
		end
	end
	local found = {}
	local function walk(list, ox, oy, s)
		for _, n in list do
			if n.group then
				walk(n.group, n.x, n.y, n.scale)
			elseif n.inst then
				found[n.inst] = { x = ox + n.x * s, y = oy + n.y * s, w = n.w * s, h = n.h * s }
			end
		end
	end
	walk(nodes, 0, 0, 1)
	return found
end

------------------------------------------------------------------ scenarios

-- A believable mid-game state for the HUD and panels.
function Gui.sampleState(game)
	local RS = game:GetService("ReplicatedStorage")
	local pets = {}
	local list = { { "MeadowPup", "Normal", "Normal", true }, { "MeadowPup", "Normal", "Normal", false }, { "MeadowPup", "Normal", "Normal", false }, { "Bunbun", "Gold", "Normal", true }, { "Honeybear", "Normal", "Huge", true }, { "CloverCat", "Diamond", "Normal", true }, { "Sandpup", "Normal", "Normal", true }, { "CactiFrog", "Normal", "Normal", false }, { "SunDrake", "Normal", "Normal", true } }
	for i, p in list do
		table.insert(pets, { uid = "p" .. i, species = p[1], material = p[2], size = p[3], equipped = p[4], locked = i == 6 })
	end
	return {
		full = true,
		loaded = true,
		coins = 18450,
		strength = 1240,
		income = 86,
		incomeMult = 1,
		bestDistance = 512,
		streak = 3,
		comboMult = 3,
		equippedFood = "ChiliPop",
		ownedFoods = { BerryBite = true, MeatyBone = true, ChiliPop = true },
		pets = pets,
		discovered = { MeadowPup = true, Bunbun = true, Honeybear = true, CloverCat = true, Sandpup = true, CactiFrog = true, SunDrake = true, ZebraFoal = true },
		settings = { AutoThrow = false, AutoSkipRarity = "Epic", KeepMutated = true, ShowCutscenes = true, ShowGuide = true, ReduceMotion = false, AutoSellRarity = "Common" },
		autoThrowUnlocked = true,
		quest = { id = "Dunes", index = 9, total = 23, title = "Desert Run", hint = "Throw 300 m to reach Sizzle Dunes", progress = 240, target = 300, reward = 2500, focus = "ThrowLine" },
		questsDone = 8,
		totalThrows = 60,
		stats = {},
		zonesReached = { Meadow = true, Dunes = true },
		gems = 140,
		pawTokens = 5,
		passes = {},
		store = {
			passes = {
				{ key = "DoubleCoins", name = "Double Coins", description = "Your plot earns 2x coins.", icon = "2x", status = "unset" },
				{ key = "EarlyAutoThrow", name = "Auto-Throw Pass", description = "Use Auto-Throw from the start.", icon = "A", status = "loading" },
				{ key = "BigBackpack", name = "Big Backpack", description = "Hold 150 more pets.", icon = "+", status = "ok", price = 199 },
				{ key = "GoldenTrail", name = "Golden Trail", description = "A gold trail behind every snack. Looks only.", icon = "*", status = "unset" },
			},
			products = {
				{ key = "GemsSmall", name = "Pouch of Gems", description = "100 Gems", gems = 100, status = "unset" },
				{ key = "GemsMedium", name = "Sack of Gems", description = "550 Gems", gems = 550, status = "unset" },
				{ key = "GemsLarge", name = "Chest of Gems", description = "1200 Gems", gems = 1200, status = "unset" },
			},
		},
		coinRushEndsAt = 0,
		maxPets = 150,
		slots = 8,
		plotIndex = 2,
		upgrades = { Coach = 1 },
		receiptPending = false,
		canSave = true,
	}
end

function Gui.build(placePath, scenario, viewport, touch)
	local env = Gui.boot(placePath, viewport, touch)
	local R = env.R
	local SP = env.game:GetService("StarterPlayer")
	local client = SP.StarterPlayerScripts.Client
	local Hud = env.load(client.Hud)
	local playerGui = R.Instance.new("PlayerGui")
	local state = Gui.sampleState(env.game)
	local ctx = {
		invoke = function()
			return true, "ok"
		end,
		getState = function()
			return state
		end,
		onThrowDown = function() end,
		onThrowUp = function() end,
		onTrainDown = function() end,
		onTrainUp = function() end,
		teleportThrowLine = function() end,
		teleportPlot = function() end,
		teleportGym = function() end,
		onSkip = function() end,
	}
	local hud = Hud.new(playerGui, ctx)
	hud:update(state)
	hud:setWeather({ active = true, id = "FeastFrenzy", name = "Feast Frenzy", description = "2x Craving Bonus!", endsAt = 1032, cravings = { Meadow = "Berry", Dunes = "Spicy", Tundra = "Meat", Volcano = "Spicy", Swamp = "Cosmic", Nuclear = "Meat", Space = "Cosmic", Moon = "Berry" } })
	hud:setAway(false)
	hud:setContext("Hold to charge")
	hud:tick(nil, nil)
	if scenario == "charging" then
		hud:setContext("Release now")
		hud:tick(0.94, "About 540 m · Sizzle Dunes")
	elseif scenario == "pets" then
		hud.panels:toggle("Pets")
		hud.panels:select("MeadowPup|Normal|Normal")
	elseif scenario == "shop" then
		hud.panels:toggle("Shop")
	elseif scenario == "upgrades" then
		hud.panels:toggle("Shop")
		hud.panels:setShopTab("Upgrades")
	elseif scenario == "store" then
		hud.panels:toggle("Store")
	elseif scenario == "eggs" then
		hud.panels:toggle("Eggs")
	elseif scenario == "settings" then
		hud.panels:toggle("Settings")
	elseif scenario == "index" then
		hud.panels:toggle("Index")
	elseif scenario == "help" then
		hud.panels:toggle("Help")
	elseif scenario == "welcome" then
		hud:showWelcome()
	elseif scenario == "hatch" then
		hud:showHatch({ kind = "hatch", source = "egg", eggId = "SafariEgg", pet = { species = "LionCub", material = "Normal", size = "Normal" }, rarity = "Legendary", rarityIndex = 5, income = 60, newSpecies = true })
	elseif scenario == "fuse" then
		hud:showHatch({ kind = "hatch", source = "fuse", pet = { species = "MeadowPup", material = "Gold", size = "Normal" }, rarity = "Uncommon", rarityIndex = 2, income = 3, fusions = 1 })
	elseif scenario == "catch" then
		hud:renderCard({ pet = { species = "Sandpup", material = "Gold", size = "Huge", equipped = true }, rarity = "Rare", distance = 344, zoneName = "Sizzle Dunes", sweetSpot = true, income = 42, newSpecies = true, discoveryReward = 120, tokens = 1, outcome = "kept", framed = true })
		hud.card.Visible = true
	elseif scenario == "catchpreview" then
		hud:renderCard({ pet = { species = "CloverCat", material = "Diamond", size = "Colossal", equipped = false }, rarity = "Epic", rarityIndex = 4, distance = 182, zoneName = "Sunny Meadow", income = 210, outcome = "kept" })
		hud.card.Visible = true
	elseif scenario == "training" then
		hud:setAway(true)
		hud:setGym(true)
		hud:setTraining(true, state.strength)
		hud:setContext("Training · press Q or Stop to finish")
	elseif scenario == "zone" then
		hud:zoneBanner("Dunes")
	elseif scenario == "away" then
		hud:setAway(true)
		hud:setContext("")
	end
	return { hud = hud, playerGui = playerGui, R = R, state = state }
end

-- CLI
local process = require("@lune/process")
local SCENARIOS = { hud = true, charging = true, pets = true, shop = true, upgrades = true, store = true, eggs = true, settings = true, index = true, help = true, welcome = true, hatch = true, fuse = true, catch = true, catchpreview = true, training = true, zone = true, away = true }
if SCENARIOS[process.args[1] or ""] and process.args[2] then
	local fs = require("@lune/fs")
	local w, h = tonumber(process.args[3]) or 1280, tonumber(process.args[4]) or 720
	local touch = process.args[5] == "touch"
	local R = Runtime.roblox
	local vp = R.Vector2.new(w, h)
	local built = Gui.build(process.env.PLACE or "SnackForce_PetToss.rbxl", process.args[1], vp, touch)
	-- Backdrop: a flat park-like sky/ground so HUD contrast reads as it would in game.
	local bg = string.format('<rect width="%d" height="%d" fill="#8fc6e8"/><rect y="%d" width="%d" height="%d" fill="#7fb26a"/><rect x="%d" y="%d" width="%d" height="%d" fill="#e9d9b5"/>', w, h, h * 0.55, w, h * 0.45, w * 0.42, h * 0.55, w * 0.16, h * 0.45)
	fs.writeFile(process.args[2], Gui.svg(built.playerGui, vp, R, bg))
	print("gui ok", process.args[1], w, h, if touch then "touch" else "desktop")
end

return Gui
