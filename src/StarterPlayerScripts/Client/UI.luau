--!strict
-- Tiny UI toolkit: instance factory, rounded/stroked/gradient styling and button juice.

local TweenService = game:GetService("TweenService")

local UI = {}

UI.Font = Enum.Font.FredokaOne
UI.Colors = {
	Panel = Color3.fromRGB(32, 30, 58),
	PanelLight = Color3.fromRGB(52, 48, 92),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(190, 190, 215),
	Gold = Color3.fromRGB(255, 210, 60),
	Green = Color3.fromRGB(80, 220, 110),
	Red = Color3.fromRGB(255, 80, 90),
	Blue = Color3.fromRGB(70, 160, 255),
	Purple = Color3.fromRGB(170, 100, 255),
	Orange = Color3.fromRGB(255, 150, 50),
	Pink = Color3.fromRGB(255, 110, 180),
	Stroke = Color3.fromRGB(20, 16, 40),
}

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
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

function UI.stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color or UI.Colors.Stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UI.textStroke(parent: Instance, thickness: number?): UIStroke
	return UI.new("UIStroke", { Color = UI.Colors.Stroke, Thickness = thickness or 2, Parent = parent })
end

function UI.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return UI.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
		Parent = parent,
	})
end

function UI.padding(parent: Instance, px: number)
	UI.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function UI.tween(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function UI.label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?, props: { [string]: any }?): TextLabel
	local l = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = size,
		Position = pos,
		Text = text,
		Font = UI.Font,
		TextScaled = true,
		TextColor3 = color or UI.Colors.Text,
		Parent = parent,
	})
	UI.textStroke(l)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

function UI.panel(parent: Instance, size: UDim2, pos: UDim2, color: Color3?): Frame
	local f = UI.new("Frame", {
		Size = size,
		Position = pos,
		BackgroundColor3 = color or UI.Colors.Panel,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UI.corner(f, 14)
	UI.stroke(f)
	return f
end

-- A chunky cartoon button with hover/press feedback.
function UI.button(parent: Instance, text: string, color: Color3, size: UDim2, pos: UDim2): TextButton
	local b = UI.new("TextButton", {
		Size = size,
		Position = pos,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = text,
		Font = UI.Font,
		TextScaled = true,
		TextColor3 = UI.Colors.Text,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UI.corner(b, 12)
	UI.stroke(b)
	UI.gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	UI.textStroke(b)
	UI.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = b })
	local scale = UI.new("UIScale", { Scale = 1, Parent = b })
	b.MouseEnter:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1.06 })
	end)
	b.MouseLeave:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		UI.tween(scale, 0.06, { Scale = 0.94 })
	end)
	b.MouseButton1Up:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1.06 })
	end)
	return b
end

function UI.pop(obj: GuiObject)
	local scale = obj:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = obj })
	scale.Scale = 0.6
	UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

return UI
