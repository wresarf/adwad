--!strict
-- Snack Force design system: "toy safari park".
-- Warm ivory surfaces, charcoal text, leaf-green primary actions, amber for rewards.
-- One display font (FredokaOne) for titles only; Builder Sans for everything people read.
-- Text never uses TextScaled: sizes come from a small type scale on a 1280x720 logical
-- canvas that the HUD scales to the screen.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PetModelBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetModelBuilder"))

local UI = {}

UI.Display = Enum.Font.FredokaOne
UI.Font = Enum.Font.BuilderSansBold
UI.FontMedium = Enum.Font.BuilderSansMedium
UI.FontHeavy = Enum.Font.BuilderSansExtraBold

UI.Type = {
	Caption = 15,
	Small = 17,
	Body = 19,
	Label = 21,
	Title = 26,
	Display = 34,
}

UI.Space = { xs = 4, s = 8, m = 12, l = 16, xl = 24 }
UI.Radius = { s = 8, m = 12, l = 18, pill = 999 }

UI.Colors = {
	-- surfaces
	Ivory = Color3.fromRGB(246, 239, 224),
	Paper = Color3.fromRGB(252, 249, 242),
	Sand = Color3.fromRGB(234, 223, 199),
	Line = Color3.fromRGB(210, 196, 168),
	Shadow = Color3.fromRGB(60, 44, 28),
	-- text
	Charcoal = Color3.fromRGB(46, 42, 38),
	Muted = Color3.fromRGB(104, 96, 86),
	OnColor = Color3.fromRGB(255, 255, 255),
	-- accents
	Leaf = Color3.fromRGB(60, 142, 64),
	LeafDark = Color3.fromRGB(40, 104, 46),
	LeafSoft = Color3.fromRGB(214, 234, 204),
	Amber = Color3.fromRGB(242, 169, 59),
	AmberDark = Color3.fromRGB(184, 118, 24),
	AmberSoft = Color3.fromRGB(252, 230, 190),
	Terracotta = Color3.fromRGB(196, 92, 64),
	TerracottaSoft = Color3.fromRGB(244, 212, 198),
	Teal = Color3.fromRGB(52, 128, 130),
	TealSoft = Color3.fromRGB(204, 230, 228),
	Plum = Color3.fromRGB(122, 86, 140),
	Disabled = Color3.fromRGB(204, 196, 182),
	Scrim = Color3.fromRGB(30, 24, 18),
}
local C = UI.Colors
-- Legacy names used by older call sites; mapped onto the palette.
C.Green = C.Leaf
C.Red = C.Terracotta
C.Blue = C.Teal
C.Orange = C.Amber
C.Gold = C.Amber
C.Purple = C.Plum
C.Pink = C.Terracotta
C.Panel = C.Ivory
C.PanelLight = C.Sand
C.Text = C.Charcoal
C.Stroke = C.Line
C.Dark = C.Charcoal

------------------------------------------------------------------ motion

local reduceMotionSetting = false

function UI.setReduceMotion(on: boolean)
	reduceMotionSetting = on
end

function UI.reducedMotion(): boolean
	if reduceMotionSetting then
		return true
	end
	local ok, v = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and v == true
end

function UI.tween(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = if UI.reducedMotion() then 0 else time
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- A small "pop" for attention. Under reduced motion it does nothing.
function UI.pop(obj: GuiObject, amount: number?)
	if UI.reducedMotion() then
		return
	end
	local scale = obj:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = obj })
	scale.Scale = 1 - (amount or 0.08)
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

------------------------------------------------------------------ primitives

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if props then
		local parent = props.Parent
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
		if children then
			for _, c in children do
				c.Parent = inst
			end
		end
		if parent then
			inst.Parent = parent
		end
	end
	return inst
end

function UI.corner(parent: Instance, radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or UI.Radius.m), Parent = parent })
end

function UI.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color or C.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Soft legibility outline for text drawn straight over the 3D world.
function UI.textOutline(label: Instance, thickness: number?)
	UI.new("UIStroke", { Color = C.Scrim, Thickness = thickness or 1.5, Transparency = 0.35, Parent = label })
end

function UI.padding(parent: Instance, top: number, right: number?, bottom: number?, left: number?)
	UI.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
		Parent = parent,
	})
end

function UI.list(parent: Instance, gap: number, horizontal: boolean?, align: Enum.HorizontalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		Padding = UDim.new(0, gap),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

export type TextOpts = {
	size: number?,
	color: Color3?,
	font: Enum.Font?,
	align: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	wrap: boolean?,
	auto: Enum.AutomaticSize?,
	order: number?,
	z: number?,
	name: string?,
}

-- Text at a fixed size from the type scale. Long text wraps instead of shrinking.
function UI.text(parent: Instance, text: string, size: UDim2, pos: UDim2?, opts: TextOpts?): TextLabel
	local o: TextOpts = opts or {}
	local l = UI.new("TextLabel", {
		Name = o.name or "Text",
		BackgroundTransparency = 1,
		Size = size,
		Position = pos or UDim2.new(),
		Text = text,
		Font = o.font or UI.Font,
		TextSize = o.size or UI.Type.Body,
		TextColor3 = o.color or C.Charcoal,
		TextXAlignment = o.align or Enum.TextXAlignment.Left,
		TextYAlignment = o.alignY or Enum.TextYAlignment.Center,
		TextWrapped = o.wrap ~= false,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = o.auto or Enum.AutomaticSize.None,
		LayoutOrder = o.order or 0,
		ZIndex = o.z or 1,
		Parent = parent,
	})
	return l
end

-- Legacy helper kept for older call sites (now fixed-size text, no scaling).
function UI.label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?, props: { [string]: any }?): TextLabel
	local l = UI.text(parent, text, size, pos, { color = color, align = Enum.TextXAlignment.Center })
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

-- An ivory surface with a hairline edge (no heavy cartoon outline).
function UI.surface(parent: Instance, size: UDim2, pos: UDim2?, color: Color3?, radius: number?): Frame
	local r = radius or UI.Radius.l
	local f = UI.new("Frame", {
		Size = size,
		Position = pos or UDim2.new(),
		BackgroundColor3 = color or C.Ivory,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UI.corner(f, r)
	UI.stroke(f, C.Line, 1, 0.2)
	return f
end

UI.panel = function(parent: Instance, size: UDim2, pos: UDim2, color: Color3?): Frame
	return UI.surface(parent, size, pos, color)
end

export type ButtonStyle = "primary" | "secondary" | "reward" | "danger" | "ghost" | "disabled"

local STYLES: { [string]: { bg: Color3, lip: Color3, text: Color3 } } = {
	primary = { bg = C.Leaf, lip = C.LeafDark, text = C.OnColor },
	secondary = { bg = C.Paper, lip = C.Line, text = C.Charcoal },
	reward = { bg = C.Amber, lip = C.AmberDark, text = C.Charcoal },
	danger = { bg = C.Terracotta, lip = Color3.fromRGB(150, 66, 44), text = C.OnColor },
	ghost = { bg = C.Sand, lip = C.Line, text = C.Charcoal },
	disabled = { bg = C.Disabled, lip = Color3.fromRGB(176, 168, 152), text = C.Muted },
}

-- A toy button: rounded, a darker bottom "lip", press sinks it. Minimum 44px tall.
function UI.button(parent: Instance, text: string, style: any, size: UDim2, pos: UDim2?, textSize: number?): TextButton
	local styleName: string = if type(style) == "string" then style else "secondary"
	local b = UI.new("TextButton", {
		Size = size,
		Position = pos or UDim2.new(),
		BackgroundColor3 = STYLES[styleName].lip,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		Parent = parent,
	})
	UI.corner(b, UI.Radius.m)
	local face = UI.new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -4),
		BackgroundColor3 = STYLES[styleName].bg,
		BorderSizePixel = 0,
		Parent = b,
	})
	UI.corner(face, UI.Radius.m)
	local label = UI.text(face, text, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), {
		size = textSize or UI.Type.Label,
		color = STYLES[styleName].text,
		align = Enum.TextXAlignment.Center,
		name = "Label",
	})
	label.TextWrapped = true
	b:SetAttribute("Style", styleName)
	b.MouseButton1Down:Connect(function()
		face.Position = UDim2.fromOffset(0, 3)
	end)
	b.MouseButton1Up:Connect(function()
		face.Position = UDim2.new()
	end)
	b.MouseLeave:Connect(function()
		face.Position = UDim2.new()
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			face.Position = UDim2.new()
		end
	end)
	-- Color-only for legacy callers passing a Color3: keep it readable.
	if typeof(style) == "Color3" then
		face.BackgroundColor3 = style
		b.BackgroundColor3 = (style :: Color3):Lerp(Color3.new(0, 0, 0), 0.25)
	end
	return b
end

function UI.setButton(b: TextButton, text: string?, style: string?)
	local face = b:FindFirstChild("Face") :: Frame?
	local label = face and face:FindFirstChild("Label") :: TextLabel?
	if text and label then
		label.Text = text
	end
	if style and face and STYLES[style] and b:GetAttribute("Style") ~= style then
		b:SetAttribute("Style", style)
		face.BackgroundColor3 = STYLES[style].bg
		b.BackgroundColor3 = STYLES[style].lip
		if label then
			label.TextColor3 = STYLES[style].text
		end
	end
	b.Active = style ~= "disabled"
	b.AutoButtonColor = false
end

function UI.buttonLabel(b: TextButton): TextLabel?
	local face = b:FindFirstChild("Face")
	return face and face:FindFirstChild("Label") :: TextLabel?
end

-- A small rounded tag ("Owned", "On plot", "New", rarity names).
function UI.tag(parent: Instance, text: string, bg: Color3, fg: Color3?, pos: UDim2?, order: number?): TextLabel
	local t = UI.new("TextLabel", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = pos or UDim2.new(),
		BackgroundColor3 = bg,
		Text = text,
		Font = UI.Font,
		TextSize = UI.Type.Caption,
		TextColor3 = fg or C.Charcoal,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	UI.corner(t, 12)
	UI.padding(t, 0, 10, 0, 10)
	return t
end

-- Readable foreground for a background (rarity colours vary a lot).
function UI.onColor(bg: Color3): Color3
	local l = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
	return if l > 0.6 then C.Charcoal else C.OnColor
end

function UI.progressBar(parent: Instance, size: UDim2, pos: UDim2, color: Color3): (Frame, Frame, TextLabel)
	local bar = UI.new("Frame", { Size = size, Position = pos, BackgroundColor3 = C.Sand, BorderSizePixel = 0, Parent = parent })
	UI.corner(bar, UI.Radius.pill)
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, BorderSizePixel = 0, Parent = bar })
	UI.corner(fill, UI.Radius.pill)
	local label = UI.text(bar, "", UDim2.new(1, -12, 1, 0), UDim2.fromOffset(6, 0), {
		size = UI.Type.Caption,
		color = C.Charcoal,
		align = Enum.TextXAlignment.Right,
		z = (bar.ZIndex or 1) + 1,
	})
	return bar, fill, label
end

function UI.setProgress(fill: Frame, alpha: number)
	local a = if alpha ~= alpha then 0 else math.clamp(alpha, 0, 1)
	fill.Size = UDim2.fromScale(a, 1)
	fill.Visible = a > 0.001
end

-- Key-cap hint ("E", "Q") shown on buttons for keyboard players.
function UI.keycap(parent: Instance, key: string, pos: UDim2, z: number?): TextLabel
	local k = UI.new("TextLabel", {
		Size = UDim2.fromOffset(26, 26),
		Position = pos,
		BackgroundColor3 = C.Paper,
		BackgroundTransparency = 0.1,
		Text = key,
		Font = UI.FontHeavy,
		TextSize = UI.Type.Caption,
		TextColor3 = C.Charcoal,
		ZIndex = z or 3,
		Name = "Keycap",
		Parent = parent,
	})
	UI.corner(k, 6)
	return k
end

------------------------------------------------------------------ 3D previews

-- A ViewportFrame showing a procedurally built pet. `silhouette` hides it (Index).
function UI.petViewport(parent: Instance, rec: { species: string, material: string?, size: string? }, size: UDim2, pos: UDim2, silhouette: boolean?): ViewportFrame
	local vp = UI.new("ViewportFrame", {
		Size = size,
		Position = pos,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 180, 170),
		LightColor = Color3.fromRGB(255, 248, 236),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		Parent = parent,
	})
	-- Size is normalised so every pet fills the frame; mutations still show their material.
	local model, height = PetModelBuilder.build(rec.species, rec.material or "Normal", "Normal", CFrame.new())
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("PointLight") then
			d:Destroy()
		elseif silhouette and d:IsA("BasePart") then
			d.Color = Color3.fromRGB(120, 108, 92)
			d.Material = Enum.Material.SmoothPlastic
			d.Transparency = 0
			d.Reflectance = 0
		end
	end
	model.Parent = vp
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local target = Vector3.new(0, height * 0.45, 0)
	camera.CFrame = CFrame.lookAt(target + Vector3.new(height * 0.95, height * 0.35, -height * 1.7), target)
	camera.Parent = vp
	vp.CurrentCamera = camera
	return vp
end

-- Full-screen colour wash for milestone moments. Skipped under reduced motion.
function UI.flash(parent: Instance, color: Color3, strength: number?)
	if UI.reducedMotion() then
		return
	end
	local f = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 1 - (strength or 0.35), BorderSizePixel = 0, ZIndex = 40, Parent = parent })
	UI.tween(f, 0.6, { BackgroundTransparency = 1 }).Completed:Connect(function()
		f:Destroy()
	end)
end

return UI
