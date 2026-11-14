--!strict
-- Main HUD. One focused primary action (Throw) at the bottom centre, secondary actions
-- next to it, a single context line, a wallet at the top, the quest card top-left, a
-- uniform navigation rail on the left and optional cravings details on the right.
-- Authored on a 1280x720 logical canvas and scaled to the viewport (larger minimum on
-- touch devices, compact mode for small screens).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local EggConfig = require(Config:WaitForChild("EggConfig"))
local GameMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameMath"))

local UI = require(script.Parent:WaitForChild("UI"))
local Panels = require(script.Parent:WaitForChild("Panels"))

local C = UI.Colors
local T = UI.Type

export type Ctx = {
	invoke: (name: string, ...any) -> (boolean, string),
	getState: () -> any,
	onThrowDown: (InputObject?) -> (),
	onThrowUp: () -> (),
	onTrainDown: (InputObject?) -> (),
	onTrainUp: () -> (),
	teleportThrowLine: () -> (),
	teleportPlot: () -> (),
	teleportGym: () -> (),
	onSkip: () -> (),
}

local Hud = {}
Hud.__index = Hud

local NAV: { { key: string, icon: string, label: string, hotkey: string? } } = {
	{ key = "Shop", icon = "🍓", label = "Snacks", hotkey = "F" },
	{ key = "Eggs", icon = "🥚", label = "Eggs", hotkey = "B" },
	{ key = "Pets", icon = "🐾", label = "Pets", hotkey = "G" },
	{ key = "Index", icon = "📖", label = "Index", hotkey = "N" },
	{ key = "Store", icon = "💎", label = "Store", hotkey = nil },
	{ key = "Travel", icon = "🧭", label = "Travel", hotkey = "T" },
	{ key = "Settings", icon = "⚙️", label = "Settings", hotkey = nil },
	{ key = "Help", icon = "❔", label = "Help", hotkey = "H" },
}

local function rarityColor(name: string?): Color3
	return (GameConfig.RarityColors :: any)[name or "Common"] or C.Muted
end

local function mutationText(rec: any): string
	local mut = {}
	if rec.size and rec.size ~= "Normal" then
		table.insert(mut, rec.size)
	end
	if rec.material and rec.material ~= "Normal" then
		table.insert(mut, rec.material)
	end
	return if #mut > 0 then table.concat(mut, " ") .. " " else ""
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Hud.new(playerGui: PlayerGui, ctx: Ctx)
	local self = setmetatable({}, Hud) :: any
	self.ctx = ctx
	self.toasts = {}
	self.cardQueue = {}
	self.cardBusy = false
	self.rewardQueue = {}
	self.rewardBusy = false
	self.connections = {}
	self.cravingsOpen = false
	self.compact = false
	self.navButtons = {}
	self.menuButtons = self.navButtons -- legacy name used by pulse()
	self.awayFromLine = false
	self.inGym = false

	local gui = UI.new("ScreenGui", {
		Name = "SnackHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = playerGui,
	})
	self.gui = gui

	local root = UI.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local uiScale = UI.new("UIScale", { Parent = root })
	self.root = root
	-- Toasts, rewards and popups live on their own layer: above panels and still visible
	-- while a cutscene hides the main HUD.
	local popups = UI.new("Frame", { Name = "Popups", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = gui })
	local popupScale = UI.new("UIScale", { Parent = popups })
	self.popups = popups

	------------------------------------------------ wallet (top centre)
	local wallet = UI.surface(root, UDim2.fromOffset(0, 44), UDim2.new(0.5, 0, 0, 8), C.Ivory, UI.Radius.pill)
	wallet.AnchorPoint = Vector2.new(0.5, 0)
	wallet.AutomaticSize = Enum.AutomaticSize.X
	UI.padding(wallet, 0, 16, 0, 12)
	UI.list(wallet, 18, true)
	local function walletItem(icon: string, order: number, tip: string): (Frame, TextLabel)
		local item = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Name = tip, Parent = wallet })
		UI.list(item, 6, true)
		UI.text(item, icon, UDim2.fromOffset(24, 44), nil, { size = T.Label, align = Enum.TextXAlignment.Center, order = 1 })
		local value = UI.text(item, "0", UDim2.fromOffset(0, 44), nil, { size = T.Label, font = UI.FontHeavy, auto = Enum.AutomaticSize.X, wrap = false, order = 2 })
		return item, value
	end
	local _, coins = walletItem("🪙", 1, "Coins")
	self.coinsLabel = coins
	local incomeItem = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = wallet })
	self.incomeLabel = UI.text(incomeItem, "+0/s", UDim2.fromOffset(0, 44), nil, { size = T.Small, color = C.Muted, auto = Enum.AutomaticSize.X, wrap = false })
	local _, gems = walletItem("💎", 3, "Gems")
	self.gemsLabel = gems
	local _, tokens = walletItem("🐾", 4, "Paw Tokens")
	self.tokensLabel = tokens
	self.wallet = wallet
	self.popupHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 120), Position = UDim2.new(0.5, -110, 0, 56), Parent = popups })

	------------------------------------------------ weather (under the wallet)
	local weatherChip = UI.surface(root, UDim2.fromOffset(0, 30), UDim2.new(0.5, 0, 0, 58), C.Paper, UI.Radius.pill)
	weatherChip.AnchorPoint = Vector2.new(0.5, 0)
	weatherChip.AutomaticSize = Enum.AutomaticSize.X
	UI.padding(weatherChip, 0, 14, 0, 10)
	UI.list(weatherChip, 8, true)
	local weatherDot = UI.new("Frame", { Size = UDim2.fromOffset(12, 12), BackgroundColor3 = C.Muted, LayoutOrder = 1, Parent = weatherChip })
	UI.corner(weatherDot, 6)
	self.weatherDot = weatherDot
	self.weatherText = UI.text(weatherChip, "", UDim2.fromOffset(0, 30), nil, { size = T.Small, auto = Enum.AutomaticSize.X, wrap = false, order = 2 })
	self.weatherChip = weatherChip

	------------------------------------------------ quest card (top left)
	local quest = UI.surface(root, UDim2.fromOffset(300, 0), UDim2.fromOffset(12, 8), C.Ivory)
	quest.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(quest, 12, 14, 14, 14)
	UI.list(quest, 4)
	local questTop = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Parent = quest })
	self.questHeader = UI.text(questTop, "Quest", UDim2.new(1, -90, 1, 0), nil, { size = T.Caption, color = C.Muted, font = UI.Font })
	local rewardChip = UI.tag(questTop, "", C.AmberSoft, C.Charcoal, UDim2.new(1, 0, 0, -2))
	rewardChip.AnchorPoint = Vector2.new(1, 0)
	self.questReward = rewardChip
	self.questTitle = UI.text(quest, "Loading your save", UDim2.new(1, 0, 0, 28), nil, { size = T.Title, font = UI.Display, order = 2 })
	self.questHint = UI.text(quest, "", UDim2.new(1, 0, 0, 0), nil, { size = T.Small, color = C.Muted, font = UI.FontMedium, auto = Enum.AutomaticSize.Y, order = 3 })
	local barHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 4, Parent = quest })
	local _, questFill, questBarText = UI.progressBar(barHolder, UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 6), C.Leaf)
	self.questFill = questFill
	self.questBarText = questBarText
	self.quest = quest
	local questTap = UI.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = quest })
	questTap.Activated:Connect(function()
		self.questCollapsed = not self.questCollapsed
		self.questHint.Visible = not self.questCollapsed
	end)

	------------------------------------------------ navigation rail (left)
	local nav = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(160, 400), Position = UDim2.fromOffset(12, 178), Parent = root })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(74, 64), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	self.nav = nav
	for i, item in NAV do
		local b = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.Ivory, BorderSizePixel = 0, LayoutOrder = i, Name = item.key, Parent = nav })
		UI.corner(b, UI.Radius.m)
		UI.stroke(b, C.Line, 1, 0.2)
		UI.text(b, item.icon, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 6), { size = T.Title, align = Enum.TextXAlignment.Center })
		UI.text(b, item.label, UDim2.new(1, -4, 0, 20), UDim2.fromOffset(2, 38), { size = T.Caption, align = Enum.TextXAlignment.Center, name = "NavLabel" })
		if item.hotkey and not UserInputService.TouchEnabled then
			local k = UI.keycap(b, item.hotkey, UDim2.new(1, -22, 0, 3))
			k.Size = UDim2.fromOffset(18, 18)
			k.TextSize = 12
		end
		local badge = UI.new("Frame", { Name = "Badge", Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = C.Amber, Visible = false, ZIndex = 3, Parent = b })
		UI.corner(badge, 6)
		UI.stroke(badge, C.Paper, 2)
		b.Activated:Connect(function()
			self:onNav(item.key)
		end)
		self.navButtons[item.key] = b
	end

	-- Travel popover.
	local travel = UI.surface(root, UDim2.fromOffset(220, 0), UDim2.fromOffset(176, 178), C.Ivory)
	travel.AutomaticSize = Enum.AutomaticSize.Y
	travel.Visible = false
	travel.ZIndex = 8
	UI.padding(travel, 10)
	UI.list(travel, 8)
	UI.text(travel, "Travel to", UDim2.new(1, 0, 0, 22), nil, { size = T.Small, color = C.Muted, order = 0 })
	local function travelButton(text: string, order: number, fn: () -> ()): TextButton
		local b = UI.button(travel, text, "secondary", UDim2.new(1, 0, 0, 46))
		b.LayoutOrder = order
		b.Activated:Connect(function()
			travel.Visible = false
			fn()
		end)
		return b
	end
	travelButton("Throw Line", 1, ctx.teleportThrowLine)
	travelButton("Gym", 2, ctx.teleportGym)
	travelButton("My plot", 3, ctx.teleportPlot)
	self.travel = travel

	------------------------------------------------ cravings (top right, optional details)
	local cravings = UI.surface(root, UDim2.fromOffset(260, 0), UDim2.new(1, -12, 0, 8), C.Ivory)
	cravings.AnchorPoint = Vector2.new(1, 0)
	cravings.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(cravings, 8, 12, 10, 12)
	UI.list(cravings, 6)
	local cravingsHeader = UI.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 0, Parent = cravings })
	self.cravingsTitle = UI.text(cravingsHeader, "Cravings", UDim2.new(1, -28, 1, 0), nil, { size = T.Body })
	self.cravingsArrow = UI.text(cravingsHeader, "▾", UDim2.fromOffset(24, 32), UDim2.new(1, -24, 0, 0), { size = T.Body, align = Enum.TextXAlignment.Center })
	cravingsHeader.Activated:Connect(function()
		self:setCravingsOpen(not self.cravingsOpen)
	end)
	self.cravingRows = {}
	for i, zone in BiomeConfig.allCravingZones() do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.Paper, LayoutOrder = i, Visible = false, Parent = cravings })
		UI.corner(row, UI.Radius.s)
		UI.text(row, BiomeConfig.zoneName(zone), UDim2.new(0.56, -8, 1, 0), UDim2.fromOffset(8, 0), { size = T.Caption, font = UI.FontMedium, wrap = false })
		local crave = UI.text(row, "?", UDim2.new(0.44, -8, 1, 0), UDim2.new(0.56, 0, 0, 0), { size = T.Caption, align = Enum.TextXAlignment.Right, wrap = false })
		self.cravingRows[zone] = { row = row, label = crave }
	end
	self.cravingsNote = UI.text(cravings, "Land where they crave your snack to grow a combo (up to 10x mutation odds).", UDim2.new(1, 0, 0, 0), nil, { size = T.Caption, color = C.Muted, font = UI.FontMedium, auto = Enum.AutomaticSize.Y, order = 99 })
	self.cravingsNote.Visible = false
	self.cravings = cravings

	------------------------------------------------ bottom action cluster
	local bottom = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(640, 200), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), Parent = root })
	self.bottom = bottom

	-- One context line, never a stack of prompts.
	local context = UI.surface(bottom, UDim2.fromOffset(0, 32), UDim2.new(0.5, 0, 0, 0), C.Paper, UI.Radius.pill)
	context.AnchorPoint = Vector2.new(0.5, 0)
	context.AutomaticSize = Enum.AutomaticSize.X
	UI.padding(context, 0, 14, 0, 14)
	self.contextText = UI.text(context, "", UDim2.fromOffset(0, 32), nil, { size = T.Body, auto = Enum.AutomaticSize.X, wrap = false })
	self.context = context

	-- Charge meter with a labelled sweet zone (text + tick marks, not colour alone).
	local meter = UI.new("Frame", { Size = UDim2.fromOffset(440, 22), Position = UDim2.new(0.5, -220, 0, 58), BackgroundColor3 = C.Paper, BorderSizePixel = 0, Parent = bottom })
	UI.corner(meter, UI.Radius.pill)
	self.meterStroke = UI.stroke(meter, C.Line, 2)
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Amber, BorderSizePixel = 0, Parent = meter })
	UI.corner(fill, UI.Radius.pill)
	self.meterFill = fill
	local sweet = UI.new("Frame", {
		Size = UDim2.new(1 - GameConfig.SweetSpotMin, 0, 1, 0),
		Position = UDim2.new(GameConfig.SweetSpotMin, 0, 0, 0),
		BackgroundColor3 = C.Leaf,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = meter,
	})
	UI.corner(sweet, UI.Radius.pill)
	for _, x in { 0, 1 } do
		UI.new("Frame", { Size = UDim2.new(0, 2, 1, 8), Position = UDim2.new(x, -1, 0, -4), BackgroundColor3 = C.LeafDark, BorderSizePixel = 0, ZIndex = 3, Parent = sweet })
	end
	self.sweetZone = sweet
	self.sweetLabel = UI.text(meter, "Sweet", UDim2.new(1 - GameConfig.SweetSpotMin, 24, 0, 18), UDim2.new(GameConfig.SweetSpotMin, -12, 0, -20), { size = T.Caption, color = C.LeafDark, align = Enum.TextXAlignment.Center, font = UI.FontHeavy })
	UI.textOutline(self.sweetLabel, 1)
	self.sweetLabel.TextColor3 = C.Paper
	self.meter = meter
	self.meterCaption = UI.text(bottom, "", UDim2.fromOffset(440, 22), UDim2.new(0.5, -220, 0, 84), { size = T.Small, align = Enum.TextXAlignment.Center, color = C.Paper })
	UI.textOutline(self.meterCaption)

	-- Secondary: Train.
	local trainBtn = UI.button(bottom, "Train", "secondary", UDim2.fromOffset(150, 66), UDim2.new(0.5, -280, 1, -70))
	self.trainSub = UI.text(trainBtn:FindFirstChild("Face") :: any, "", UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 1, -22), { size = T.Caption, color = C.Muted, align = Enum.TextXAlignment.Center })
	local trainLabel = UI.buttonLabel(trainBtn)
	if trainLabel then
		trainLabel.Size = UDim2.new(1, -16, 1, -18)
	end
	if not UserInputService.TouchEnabled then
		UI.keycap(trainBtn:FindFirstChild("Face") :: any, "Q", UDim2.fromOffset(6, 6))
	end
	trainBtn.InputBegan:Connect(function(input)
		if isPress(input) then
			ctx.onTrainDown(input)
		end
	end)
	self.trainBtn = trainBtn

	-- Primary: Throw (or "Go to Throw Line" when away).
	local throwBtn = UI.button(bottom, "Throw", "primary", UDim2.fromOffset(220, 82), UDim2.new(0.5, -110, 1, -86), T.Title)
	local throwLabel = UI.buttonLabel(throwBtn)
	if throwLabel then
		throwLabel.Font = UI.Display
	end
	if not UserInputService.TouchEnabled then
		self.throwKey = UI.keycap(throwBtn:FindFirstChild("Face") :: any, "E", UDim2.fromOffset(8, 8))
	end
	throwBtn.InputBegan:Connect(function(input)
		if isPress(input) then
			if self.awayFromLine then
				ctx.teleportThrowLine()
			else
				ctx.onThrowDown(input)
			end
		end
	end)
	self.throwBtn = throwBtn

	-- Secondary: equipped snack (opens the shop).
	local foodChip = UI.button(bottom, "", "secondary", UDim2.fromOffset(170, 66), UDim2.new(0.5, 130, 1, -70))
	local foodFace = foodChip:FindFirstChild("Face") :: any
	local foodLabel = UI.buttonLabel(foodChip)
	if foodLabel then
		foodLabel.Visible = false
	end
	self.foodDot = UI.new("Frame", { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(10, 17), BackgroundColor3 = C.Terracotta, Parent = foodFace })
	UI.corner(self.foodDot, 14)
	self.foodName = UI.text(foodFace, "Berry Bite", UDim2.new(1, -50, 0, 24), UDim2.fromOffset(44, 8), { size = T.Small, wrap = false })
	self.foodInfo = UI.text(foodFace, "Change snack", UDim2.new(1, -50, 0, 20), UDim2.fromOffset(44, 32), { size = T.Caption, color = C.Muted, font = UI.FontMedium, wrap = false })
	foodChip.Activated:Connect(function()
		self.panels:toggle("Shop")
	end)

	-- Status chips (only when relevant).
	self.comboChip = UI.tag(bottom, "", C.AmberSoft, C.Charcoal, UDim2.new(0.5, -280, 1, -100))
	self.comboChip.Visible = false
	self.autoChip = UI.tag(bottom, "Auto-throw on", C.LeafSoft, C.LeafDark, UDim2.new(0.5, 130, 1, -100))
	self.autoChip.Visible = false
	self.boostChip = UI.tag(root, "", C.AmberSoft, C.Charcoal, UDim2.new(0.5, 0, 0, 94))
	self.boostChip.AnchorPoint = Vector2.new(0.5, 0)
	self.boostChip.Visible = false

	self.saveWarning = UI.text(root, "", UDim2.fromOffset(360, 20), UDim2.new(1, -372, 1, -24), { size = T.Caption, color = C.Paper, align = Enum.TextXAlignment.Right })
	UI.textOutline(self.saveWarning)

	------------------------------------------------ toasts
	local toastHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(520, 200), Position = UDim2.new(0.5, -260, 0, 126), Parent = popups })
	UI.list(toastHolder, 6, false, Enum.HorizontalAlignment.Center)
	self.toastHolder = toastHolder

	------------------------------------------------ catch card (right)
	local card = UI.surface(root, UDim2.fromOffset(320, 0), UDim2.new(1, 340, 0.5, -60), C.Ivory)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Visible = false
	UI.padding(card, 12)
	self.card = card
	local viewHolder = UI.new("Frame", { BackgroundColor3 = C.Paper, Size = UDim2.fromOffset(96, 96), Parent = card })
	UI.corner(viewHolder, UI.Radius.m)
	self.cardViewHolder = viewHolder
	self.cardNew = UI.tag(viewHolder, "New", C.Amber, C.Charcoal, UDim2.fromOffset(-6, -8))
	self.cardNew.ZIndex = 4
	local info = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -108, 0, 0), Position = UDim2.fromOffset(108, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card })
	UI.list(info, 2)
	self.cardRarity = UI.tag(info, "Common", C.Sand, C.Charcoal, nil, 1)
	self.cardTitle = UI.text(info, "", UDim2.new(1, 0, 0, 0), nil, { size = T.Label, font = UI.FontHeavy, auto = Enum.AutomaticSize.Y, order = 2 })
	self.cardInfo = UI.text(info, "", UDim2.new(1, 0, 0, 20), nil, { size = T.Caption, color = C.Muted, font = UI.FontMedium, order = 3 })
	self.cardIncome = UI.text(info, "", UDim2.new(1, 0, 0, 22), nil, { size = T.Small, color = C.AmberDark, order = 4 })
	self.cardFooter = UI.text(card, "", UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 104), { size = T.Small, font = UI.FontMedium, auto = Enum.AutomaticSize.Y })

	------------------------------------------------ reward banner (quests, zones, purchases)
	local reward = UI.surface(popups, UDim2.fromOffset(380, 0), UDim2.new(0.5, -190, 0, 170), C.Ivory)
	reward.AutomaticSize = Enum.AutomaticSize.Y
	reward.Visible = false
	reward.ZIndex = 31
	UI.padding(reward, 12, 16, 14, 16)
	UI.list(reward, 4, false, Enum.HorizontalAlignment.Center)
	self.rewardTitle = UI.tag(reward, "", C.Amber, C.Charcoal, nil, 1)
	self.rewardTitle.ZIndex = 32
	self.rewardText = UI.text(reward, "", UDim2.new(1, 0, 0, 30), nil, { size = T.Title, font = UI.Display, align = Enum.TextXAlignment.Center, order = 2, z = 32 })
	self.rewardCoins = UI.text(reward, "", UDim2.new(1, 0, 0, 24), nil, { size = T.Body, color = C.AmberDark, align = Enum.TextXAlignment.Center, order = 3, z = 32 })
	self.reward = reward

	------------------------------------------------ hatch / purchase reveal
	local hatch = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.Scrim, BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 34, Parent = popups })
	local hatchCard = UI.surface(hatch, UDim2.fromOffset(400, 430), UDim2.new(0.5, -200, 0.5, -215), C.Ivory)
	hatchCard.ZIndex = 35
	self.hatchHeader = UI.text(hatchCard, "", UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 12), { size = T.Small, color = C.Muted, align = Enum.TextXAlignment.Center, z = 36 })
	self.hatchView = UI.new("Frame", { BackgroundColor3 = C.Paper, Size = UDim2.fromOffset(220, 196), Position = UDim2.new(0.5, -110, 0, 40), ZIndex = 36, Parent = hatchCard })
	UI.corner(self.hatchView, UI.Radius.l)
	self.hatchEgg = UI.new("Frame", { BackgroundColor3 = C.Paper, Size = UDim2.fromOffset(110, 140), Position = UDim2.new(0.5, -55, 0.5, -70), ZIndex = 37, Parent = self.hatchView })
	UI.corner(self.hatchEgg, 55)
	UI.stroke(self.hatchEgg, C.Line, 2)
	self.hatchRarity = UI.tag(hatchCard, "", C.Sand, C.Charcoal, UDim2.new(0.5, 0, 0, 246))
	self.hatchRarity.AnchorPoint = Vector2.new(0.5, 0)
	self.hatchRarity.ZIndex = 36
	self.hatchName = UI.text(hatchCard, "", UDim2.new(1, -24, 0, 34), UDim2.fromOffset(12, 276), { size = T.Title, font = UI.Display, align = Enum.TextXAlignment.Center, z = 36 })
	self.hatchInfo = UI.text(hatchCard, "", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 312), { size = T.Small, color = C.Muted, align = Enum.TextXAlignment.Center, z = 36 })
	local function raise(b: GuiObject)
		b.ZIndex = 36
		for _, d in b:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 37
			end
		end
	end
	local hatchOk = UI.button(hatchCard, "Done", "secondary", UDim2.fromOffset(170, 50), UDim2.new(0.5, -178, 1, -66))
	raise(hatchOk)
	-- "Hatch again" only appears after an egg hatch the player can afford to repeat.
	local hatchAgain = UI.button(hatchCard, "Hatch again", "primary", UDim2.fromOffset(170, 50), UDim2.new(0.5, 8, 1, -66))
	raise(hatchAgain)
	self.hatchOk = hatchOk
	self.hatchAgain = hatchAgain
	local function closeHatch()
		if self.hatchRevealing then
			self.hatchSkip = true -- first tap skips the wobble, second closes
			return
		end
		hatch.Visible = false
	end
	hatchOk.Activated:Connect(closeHatch)
	hatch.Activated:Connect(closeHatch)
	hatchAgain.Activated:Connect(function()
		local eggId = self.hatchEggId
		if self.hatchRevealing or not eggId then
			return
		end
		local ok, msg = ctx.invoke("HatchEgg", eggId)
		if not ok then
			self:toast(msg, C.Terracotta)
		end
	end)
	self.hatch = hatch

	------------------------------------------------ cutscene letterbox + skip
	local overlay = UI.new("Frame", { Name = "Cutscene", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	UI.new("Frame", { BackgroundColor3 = C.Scrim, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.1, 0), ZIndex = 20, Parent = overlay })
	UI.new("Frame", { BackgroundColor3 = C.Scrim, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.1, 0), Position = UDim2.fromScale(0, 0.9), ZIndex = 20, Parent = overlay })
	self.cutsceneTitle = UI.text(overlay, "", UDim2.new(0.8, 0, 0, 48), UDim2.fromScale(0.1, 0.13), { size = 44, font = UI.Display, color = C.Paper, align = Enum.TextXAlignment.Center, z = 21 })
	UI.textOutline(self.cutsceneTitle, 2)
	self.cutsceneSub = UI.text(overlay, "", UDim2.new(0.6, 0, 0, 28), UDim2.new(0.2, 0, 0.13, 52), { size = T.Title, color = C.Paper, align = Enum.TextXAlignment.Center, z = 21 })
	UI.textOutline(self.cutsceneSub)
	self.overlay = overlay
	local skip = UI.button(gui, "Skip", "secondary", UDim2.fromOffset(150, 50), UDim2.new(1, -166, 1, -66))
	skip.ZIndex = 25
	for _, d in skip:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 26
		end
	end
	if not UserInputService.TouchEnabled then
		UI.keycap(skip:FindFirstChild("Face") :: any, "␣", UDim2.fromOffset(8, 10), 27)
	end
	skip.Visible = false
	skip.Activated:Connect(ctx.onSkip)
	self.skipButton = skip

	------------------------------------------------ panels
	self.panels = Panels.new(root, ctx, self)

	------------------------------------------------ welcome (first session)
	local welcome = UI.new("Frame", { BackgroundColor3 = C.Scrim, BackgroundTransparency = 0.5, Size = UDim2.fromScale(1, 1), Visible = false, Active = true, ZIndex = 33, Parent = root })
	local wcard = UI.surface(welcome, UDim2.fromOffset(520, 0), UDim2.new(0.5, -260, 0.5, -180), C.Ivory)
	wcard.AutomaticSize = Enum.AutomaticSize.Y
	wcard.ZIndex = 34
	UI.padding(wcard, 20, 24, 20, 24)
	UI.list(wcard, 12)
	UI.text(wcard, "Welcome to Snack Force", UDim2.new(1, 0, 0, 40), nil, { size = T.Display, font = UI.Display, order = 1, z = 35 })
	UI.text(wcard, "Toss snacks, meet hungry pets, build your park.", UDim2.new(1, 0, 0, 24), nil, { size = T.Body, color = C.Muted, font = UI.FontMedium, order = 2, z = 35 })
	local steps = {
		{ n = "1", title = "Train", text = "Hold Q or Train to get stronger. The Gym doubles it." },
		{ n = "2", title = "Throw", text = "At the Throw Line, hold to charge and release in the Sweet zone." },
		{ n = "3", title = "Collect", text = "A pet catches your snack and earns coins on your plot." },
	}
	for i, step in steps do
		local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 2 + i, ZIndex = 35, Parent = wcard })
		local badge = UI.new("TextLabel", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = C.Leaf, Text = step.n, Font = UI.FontHeavy, TextSize = T.Label, TextColor3 = C.OnColor, ZIndex = 35, Parent = row })
		UI.corner(badge, 20)
		UI.text(row, step.title, UDim2.new(1, -56, 0, 24), UDim2.fromOffset(56, 2), { size = T.Label, font = UI.FontHeavy, z = 35 })
		UI.text(row, step.text, UDim2.new(1, -56, 0, 26), UDim2.fromOffset(56, 26), { size = T.Small, color = C.Muted, font = UI.FontMedium, z = 35 })
	end
	local go = UI.button(wcard, "Let's go", "primary", UDim2.new(1, 0, 0, 52))
	go.LayoutOrder = 10
	for _, d in go:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 36
		end
	end
	go.ZIndex = 35
	go.Activated:Connect(function()
		welcome.Visible = false
	end)
	self.welcome = welcome

	------------------------------------------------ responsive scaling
	local function rescale()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local inset = GuiService:GetGuiInset()
		local v = camera.ViewportSize - Vector2.new(0, inset.Y)
		if v.X <= 1 or v.Y <= 1 then
			return
		end
		local s = math.min(v.X / 1280, v.Y / 720)
		if UserInputService.TouchEnabled then
			-- Keep touch targets usable on phones while still fitting the layout.
			s = math.max(s, math.min(0.8, v.X / 1100, v.Y / 600))
		end
		s = math.clamp(s, 0.5, 1.6)
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		popupScale.Scale = s
		popups.Size = UDim2.fromScale(1 / s, 1 / s)
		local logical = v / s
		self:setCompact(logical.X < 1180 or logical.Y < 640)
	end
	self.rescale = rescale
	local function hookCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			table.insert(self.connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
		end
		rescale()
	end
	hookCamera()
	table.insert(self.connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera))
	self:setCravingsOpen(false)
	return self
end

-- Small screens: shorter quest card, nav icons only in one tight column, cravings closed.
function Hud:setCompact(compact: boolean)
	if compact == self.compact then
		return
	end
	self.compact = compact
	self.questHint.Visible = not compact and not self.questCollapsed
	self.quest.Size = UDim2.fromOffset(if compact then 250 else 300, 0)
	local grid = self.nav:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = if compact then UDim2.fromOffset(64, 56) else UDim2.fromOffset(74, 64)
	end
	self.nav.Position = UDim2.fromOffset(12, if compact then 132 else 178)
	if compact then
		self:setCravingsOpen(false)
	end
end

function Hud:onNav(key: string)
	if key == "Travel" then
		self.travel.Visible = not self.travel.Visible
		return
	end
	self.travel.Visible = false
	self.panels:toggle(key)
end

function Hud:setCravingsOpen(open: boolean)
	self.cravingsOpen = open
	for _, row in self.cravingRows do
		row.row.Visible = open
	end
	self.cravingsNote.Visible = open
	self.cravingsArrow.Text = if open then "▴" else "▾"
	self:refreshCravings()
end

function Hud:update(state: any)
	UI.setReduceMotion(state.settings ~= nil and state.settings.ReduceMotion == true)
	self.coinsLabel.Text = GameMath.formatNumber(state.coins or 0)
	local mult = state.incomeMult or 1
	self.incomeLabel.Text = string.format("+%s/s%s", GameMath.formatNumber(state.income or 0), if mult > 1 then string.format(" (x%d)", mult) else "")
	self.gemsLabel.Text = GameMath.formatNumber(state.gems or 0)
	self.tokensLabel.Text = GameMath.formatNumber(state.pawTokens or 0)
	self.trainSub.Text = "Strength " .. GameMath.formatNumber(state.strength or 0)
	self.bestDistance = state.bestDistance or 0

	local streak = state.streak or 0
	self.comboChip.Visible = streak > 0
	self.comboChip.Text = string.format("Combo x%s · streak %d", tostring(state.comboMult or 1), streak)

	local food = FoodConfig.get(state.equippedFood) or FoodConfig.Foods[1]
	self.foodName.Text = food.name
	self.foodInfo.Text = string.format("%s %s · Change", FoodConfig.CravingIcons[food.craving] or "", food.craving)
	self.foodDot.BackgroundColor3 = food.color
	self.equippedCraving = food.craving
	local settings = state.settings
	self.autoChip.Visible = settings ~= nil and settings.AutoThrow == true and state.autoThrowUnlocked == true
	self.saveWarning.Text = if state.canSave == false then "Progress isn't being saved this session" else ""
	self.coinRushEndsAt = state.coinRushEndsAt or 0
	self:refreshCravings()
	self:refreshQuest(state.quest, state.loaded == true)
	self:refreshBadges(state)
	self.panels:refresh(state, state.full == true)
end

-- Amber dots on the rail: something useful is waiting there.
function Hud:refreshBadges(state: any)
	local coins = state.coins or 0
	local owned = state.ownedFoods or {}
	local snack = false
	for _, f in FoodConfig.Foods do
		if not owned[f.id] then
			snack = coins >= f.price
			break
		end
	end
	local egg = false
	for _, e in EggConfig.Eggs do
		if (state.pawTokens or 0) >= e.cost then
			egg = true
		end
	end
	self.navButtons.Shop.Badge.Visible = snack
	self.navButtons.Eggs.Badge.Visible = egg
end

function Hud:refreshQuest(q: any, loaded: boolean)
	if not loaded then
		self.questHeader.Text = "Quest"
		self.questTitle.Text = "Loading your save"
		self.questHint.Text = ""
		self.questReward.Visible = false
		UI.setProgress(self.questFill, 0)
		self.questBarText.Text = ""
		return
	end
	if type(q) ~= "table" then
		self.questHeader.Text = "All quests complete"
		self.questTitle.Text = "Snack Force legend"
		self.questHint.Text = "Chase Rainbow and Infinite pets on the Moon."
		self.questReward.Visible = false
		UI.setProgress(self.questFill, 1)
		self.questBarText.Text = "Done"
		self.questFocus = nil
		return
	end
	self.questHeader.Text = string.format("Quest %d of %d", q.index or 1, q.total or 1)
	self.questReward.Visible = true
	self.questReward.Text = string.format("🪙 %s  🐾 %d", GameMath.formatNumber(q.reward or 0), EggConfig.TokenRewards.Quest)
	self.questTitle.Text = q.title or ""
	self.questHint.Text = q.hint or ""
	local target = math.max(q.target or 1, 1)
	UI.setProgress(self.questFill, (q.progress or 0) / target)
	self.questBarText.Text = string.format("%s / %s", GameMath.formatNumber(q.progress or 0), GameMath.formatNumber(target))
	if self.questId ~= q.id then
		self.questId = q.id
		self.questFocus = q.focus
		UI.pop(self.quest, 0.04)
	end
end

function Hud:setCravings(cravings: { [string]: string }?)
	self.cravingMap = cravings
	self:refreshCravings()
end

function Hud:refreshCravings()
	local cravings = self.cravingMap or {}
	local matches = 0
	for zone, row in self.cravingRows do
		local c = cravings[zone]
		local match = c ~= nil and c == self.equippedCraving
		if match then
			matches += 1
		end
		row.label.Text = if c then string.format("%s %s%s", FoodConfig.CravingIcons[c] or "", c, if match then "  ✓" else "") else "?"
		row.row.BackgroundColor3 = if match then C.LeafSoft else C.Paper
	end
	local snack = self.equippedCraving or "your snack"
	self.cravingsTitle.Text = if matches > 0 then string.format("Cravings · %d want %s", matches, snack) else "Cravings · none want " .. snack
end

function Hud:setWeather(w: any)
	self.weather = w
	self:setCravings(w and w.cravings)
	if w and w.active then
		local def = GameConfig.getWeather(w.id)
		self.weatherDot.BackgroundColor3 = if def then def.color else C.Plum
		UI.pop(self.weatherChip, 0.06)
	else
		self.weatherDot.BackgroundColor3 = C.Muted
	end
end

-- The one context line above the meter. Empty text hides it.
function Hud:setContext(text: string?)
	local t = text or ""
	self.contextText.Text = t
	self.context.Visible = t ~= ""
end

-- When away from the Throw Line the primary button becomes "Go to Throw Line".
function Hud:setAway(away: boolean)
	if away == self.awayFromLine then
		return
	end
	self.awayFromLine = away
	local label = UI.buttonLabel(self.throwBtn)
	if label then
		label.Text = if away then "Go to Throw Line" else "Throw"
		label.TextSize = if away then UI.Type.Label else UI.Type.Title
	end
	if self.throwKey then
		self.throwKey.Visible = not away
	end
	self.meter.Visible = not away
	self.meterCaption.Visible = not away
end

function Hud:setGym(inGym: boolean)
	if inGym == self.inGym then
		return
	end
	self.inGym = inGym
	UI.setButton(self.trainBtn, if inGym then "Train 2x" else "Train", if inGym then "reward" else "secondary")
end

-- Called every frame for countdowns and the charge meter.
function Hud:tick(charge: number?, preview: string?)
	local w = self.weather
	local now = Workspace:GetServerTimeNow()
	if w then
		if w.active then
			self.weatherText.Text = string.format("%s · %s · %s", w.name or "Weather", w.description or "", clock((w.endsAt or now) - now))
		else
			self.weatherText.Text = "Next weather in " .. clock((w.nextAt or now) - now)
		end
	end
	local rushLeft = (self.coinRushEndsAt or 0) - os.time()
	self.boostChip.Visible = rushLeft > 0
	if rushLeft > 0 then
		self.boostChip.Text = "Coin Rush 2x · " .. (if rushLeft >= 3600 then string.format("%dh %02dm", rushLeft // 3600, (rushLeft % 3600) // 60) else clock(rushLeft))
	end
	local label = UI.buttonLabel(self.throwBtn)
	if charge then
		self.meterFill.Size = UDim2.new(charge, 0, 1, 0)
		local sweet = GameMath.isSweetSpot(charge)
		self.meterFill.BackgroundColor3 = if sweet then C.Leaf else C.Amber
		self.meterStroke.Color = if sweet then C.LeafDark else C.Line
		self.sweetZone.BackgroundTransparency = if sweet then 0.1 else 0.45
		self.sweetLabel.Text = if sweet then "Sweet ✓" else "Sweet"
		self.meterCaption.Text = preview or ""
		if label and not self.awayFromLine then
			label.Text = "Release"
		end
	else
		self.meterFill.Size = UDim2.new(0, 0, 1, 0)
		self.meterStroke.Color = C.Line
		self.sweetZone.BackgroundTransparency = 0.45
		self.sweetLabel.Text = "Sweet"
		self.meterCaption.Text = if (self.bestDistance or 0) > 0 then "Best " .. GameMath.formatNumber(self.bestDistance) .. " m" else ""
		if label and not self.awayFromLine then
			label.Text = "Throw"
		end
	end
end

-- Draws attention to a rail button (quest focus).
function Hud:pulse(key: string)
	local b = self.navButtons[key]
	if b then
		UI.pop(b, 0.12)
	end
end

local TOAST_ICONS: { [string]: string } = { good = "✓", bad = "!", info = "•" }

function Hud:toast(text: string, color: Color3?)
	if text == "" then
		return
	end
	for _, existing in self.toasts do
		if existing:GetAttribute("Text") == text then
			UI.pop(existing, 0.05)
			return
		end
	end
	local accent = color or C.Teal
	local t = UI.surface(self.toastHolder, UDim2.fromOffset(0, 40), nil, C.Ivory, UI.Radius.pill)
	t.AutomaticSize = Enum.AutomaticSize.X
	t:SetAttribute("Text", text)
	UI.padding(t, 0, 16, 0, 8)
	UI.list(t, 8, true)
	local kind = if accent == C.Terracotta then "bad" elseif accent == C.Leaf then "good" else "info"
	local dot = UI.new("TextLabel", { Size = UDim2.fromOffset(26, 26), BackgroundColor3 = accent, Text = TOAST_ICONS[kind], Font = UI.FontHeavy, TextSize = T.Small, TextColor3 = UI.onColor(accent), LayoutOrder = 1, Parent = t })
	UI.corner(dot, 13)
	UI.text(t, text, UDim2.fromOffset(0, 40), nil, { size = T.Body, auto = Enum.AutomaticSize.X, wrap = false, order = 2 })
	UI.pop(t, 0.05)
	table.insert(self.toasts, t)
	while #self.toasts > 3 do
		local old = table.remove(self.toasts, 1)
		if old then
			old:Destroy()
		end
	end
	task.delay(2.6, function()
		local idx = table.find(self.toasts, t)
		if idx then
			table.remove(self.toasts, idx)
		end
		if t.Parent then
			t:Destroy()
		end
	end)
end

-- Floating "+123" under the wallet.
function Hud:coinPopup(amount: number, color: Color3?)
	if amount <= 0 then
		return
	end
	local l = UI.text(self.popupHolder, "+" .. GameMath.formatNumber(amount) .. " 🪙", UDim2.fromOffset(220, 28), UDim2.fromOffset(0, 0), { size = T.Label, font = UI.FontHeavy, color = color or C.Amber, align = Enum.TextXAlignment.Center })
	UI.textOutline(l)
	if UI.reducedMotion() then
		task.delay(1.2, function()
			l:Destroy()
		end)
	else
		UI.tween(l, 1.3, { Position = UDim2.fromOffset(0, 50), TextTransparency = 1 })
		task.delay(1.35, function()
			l:Destroy()
		end)
	end
	UI.pop(self.wallet, 0.04)
end

function Hud:showReward(payload: any)
	table.insert(self.rewardQueue, payload)
	if self.rewardBusy then
		return
	end
	self.rewardBusy = true
	task.spawn(function()
		while #self.rewardQueue > 0 do
			local p = table.remove(self.rewardQueue, 1)
			local accent = if p.color == "Green" then C.Leaf elseif p.color == "Blue" then C.Teal elseif p.color == "Purple" then C.Plum else C.Amber
			self.rewardTitle.Text = p.title or "Reward"
			self.rewardTitle.BackgroundColor3 = accent
			self.rewardTitle.TextColor3 = UI.onColor(accent)
			self.rewardText.Text = p.text or ""
			local parts = {}
			if (p.coins or 0) > 0 then
				table.insert(parts, "+" .. GameMath.formatNumber(p.coins) .. " coins")
			end
			if (p.tokens or 0) > 0 then
				table.insert(parts, string.format("+%d Paw Token%s", p.tokens, if p.tokens == 1 then "" else "s"))
			end
			self.rewardCoins.Text = table.concat(parts, "  ·  ")
			self.rewardCoins.Visible = #parts > 0
			self.reward.Visible = true
			UI.pop(self.reward, if p.milestone then 0.15 else 0.06)
			if p.milestone then
				UI.flash(self.gui, accent, 0.25)
			end
			self:coinPopup(p.coins or 0)
			task.wait(if p.milestone then 2.4 else 1.8)
			self.reward.Visible = false
			task.wait(0.12)
		end
		self.rewardBusy = false
	end)
end

function Hud:showWelcome()
	self.welcome.Visible = true
	UI.pop(self.welcome, 0.05)
end

-- Egg hatch / Gem offer reveal: the egg wobbles and cracks, then the pet appears.
function Hud:showHatch(payload: any)
	local rec = payload.pet or {}
	local pet = PetConfig.get(rec.species)
	local egg = EggConfig.get(payload.eggId)
	for _, child in self.hatchView:GetChildren() do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end
	local rc = rarityColor(payload.rarity)
	local source = payload.source
	self.hatchHeader.Text = if source == "fuse"
		then (if (payload.fusions or 1) > 1 then string.format("Fused %d times · best result", payload.fusions) else "Fusion complete")
		elseif source == "offer" then "Added to your pets"
		else (if egg then egg.name .. " hatched" else "Hatched")
	self.hatchEggId = if source == "egg" and egg then egg.id else nil
	local st = self.ctx.getState()
	local canAgain = egg ~= nil and source == "egg" and (st.pawTokens or 0) >= egg.cost
	self.hatchAgain.Visible = canAgain
	if canAgain and egg then
		UI.setButton(self.hatchAgain, string.format("Again · %d 🐾", egg.cost), "primary")
	end
	self.hatchOk.Position = if canAgain then UDim2.new(0.5, -178, 1, -66) else UDim2.new(0.5, -85, 1, -66)
	self.hatchRarity.Text = payload.rarity or "Common"
	self.hatchRarity.BackgroundColor3 = rc
	self.hatchRarity.TextColor3 = UI.onColor(rc)
	self.hatchName.Text = mutationText(rec) .. (if pet then pet.name else "Pet")
	self.hatchInfo.Text = string.format("+%s coins/sec%s", GameMath.formatNumber(payload.income or 0), if payload.newSpecies then " · New species" else "")
	self.hatchEgg.BackgroundColor3 = if egg then egg.shell else C.Paper
	self.hatchEgg.Visible = payload.source == "egg"
	self.hatchEgg.Rotation = 0
	self.hatchName.Visible = false
	self.hatchInfo.Visible = false
	self.hatchRarity.Visible = false
	self.hatch.Visible = true
	local reduced = UI.reducedMotion()
	local eggArt = self.hatchEgg :: Frame
	local view = self.hatchView :: Frame
	self.hatchRevealing = true
	self.hatchSkip = false
	task.spawn(function()
		if payload.source == "egg" and not reduced then
			-- Anticipation: three wobbles that grow, each skippable with a tap.
			for i = 1, 3 do
				if self.hatchSkip then
					break
				end
				UI.tween(eggArt, 0.12, { Rotation = (6 + i * 4) * (if i % 2 == 0 then -1 else 1) })
				task.wait(0.14)
				UI.tween(eggArt, 0.12, { Rotation = 0 })
				task.wait(0.22)
			end
		end
		self.hatchRevealing = false
		eggArt.Visible = false
		if pet and self.hatch.Visible then
			UI.petViewport(view, rec, UDim2.fromScale(1, 1), UDim2.new())
		end
		self.hatchName.Visible = true
		self.hatchInfo.Visible = true
		self.hatchRarity.Visible = true
		UI.pop(view, 0.15)
		if (payload.rarityIndex or 1) >= GameConfig.rarityIndex("Epic") then
			UI.flash(self.gui, rc, 0.3)
		end
	end)
end

function Hud:showCatch(payload: any)
	table.insert(self.cardQueue, payload)
	if #self.cardQueue > 5 then
		table.remove(self.cardQueue, 1)
	end
	if self.cardBusy then
		return
	end
	self.cardBusy = true
	task.spawn(function()
		while #self.cardQueue > 0 do
			local p = table.remove(self.cardQueue, 1)
			self:renderCard(p)
			local card = self.card :: Frame
			card.Position = UDim2.new(1, 340, 0.5, -60)
			card.Visible = true
			UI.tween(card, 0.3, { Position = UDim2.new(1, -332, 0.5, -60) }, Enum.EasingStyle.Quart)
			task.wait(if #self.cardQueue > 0 then 1.4 else 2.6)
			UI.tween(card, 0.22, { Position = UDim2.new(1, 340, 0.5, -60) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.24)
			card.Visible = false
		end
		self.cardBusy = false
	end)
end

function Hud:renderCard(p: any)
	local rec = p.pet or {}
	local pet = PetConfig.get(rec.species)
	local rc = rarityColor(p.rarity)
	self.cardTitle.Text = mutationText(rec) .. (if pet then pet.name else "Pet")
	self.cardRarity.Text = p.rarity or "Common"
	self.cardRarity.BackgroundColor3 = rc
	self.cardRarity.TextColor3 = UI.onColor(rc)
	for _, child in self.cardViewHolder:GetChildren() do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end
	if pet then
		UI.petViewport(self.cardViewHolder :: any, rec, UDim2.fromScale(1, 1), UDim2.new())
	end
	self.cardNew.Visible = p.newSpecies == true
	self.cardInfo.Text = string.format("%s m · %s%s", GameMath.formatNumber(p.distance or 0), p.zoneName or BiomeConfig.zoneName(p.zone), if p.sweetSpot then " · Sweet" else "")
	self.cardIncome.Text = "+" .. GameMath.formatNumber(p.income or 0) .. " coins/sec"
	local extras = {}
	if (p.bonusCoins or 0) > 0 then
		table.insert(extras, "craving +" .. GameMath.formatNumber(p.bonusCoins))
	end
	if (p.discoveryReward or 0) > 0 then
		table.insert(extras, "new species +" .. GameMath.formatNumber(p.discoveryReward))
	end
	if (p.tokens or 0) > 0 then
		table.insert(extras, string.format("+%d 🐾", p.tokens))
	end
	local status
	if p.outcome == "sold" then
		status = "Auto-sold for " .. GameMath.formatNumber(p.soldFor or 0)
		self.cardFooter.TextColor3 = C.AmberDark
	elseif p.outcome == "full" then
		status = "Backpack full · sold for " .. GameMath.formatNumber(p.soldFor or 0)
		self.cardFooter.TextColor3 = C.Terracotta
	elseif rec.equipped then
		status = "On your plot"
		self.cardFooter.TextColor3 = C.LeafDark
	else
		status = "In your backpack · try Equip best"
		self.cardFooter.TextColor3 = C.Muted
	end
	self.cardFooter.Text = status .. (if #extras > 0 then "\n" .. table.concat(extras, " · ") else "")
end

function Hud:setCutscene(active: boolean, title: string?, sub: string?)
	self.overlay.Visible = active
	self.skipButton.Visible = active
	self.root.Visible = not active
	self.cutsceneTitle.Text = title or ""
	self.cutsceneSub.Text = sub or ""
	if active and title then
		UI.pop(self.cutsceneTitle :: any, 0.1)
	end
end

function Hud:setSkipOnly(active: boolean)
	self.skipButton.Visible = active
end

function Hud:flash(color: Color3, strength: number?)
	UI.flash(self.gui, color, strength)
end

function Hud:destroy()
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	self.gui:Destroy()
end

return Hud
