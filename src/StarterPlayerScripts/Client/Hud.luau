--!strict
-- Main HUD: stats, quest tracker, weather banner, cravings board, charge meter with a
-- distance preview, throw/train buttons, toasts, catch cards, reward popups, cutscene
-- overlay, welcome screen and the menu that opens the panels.
-- Layout is authored on a logical 1280x720 canvas and scaled to the viewport (with a
-- larger minimum on touch devices and a compact mode for small screens).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local GameMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameMath"))

local UI = require(script.Parent:WaitForChild("UI"))
local Panels = require(script.Parent:WaitForChild("Panels"))

local C = UI.Colors

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

local function pill(parent: Instance, icon: string, color: Color3, order: number): TextLabel
	local f = UI.panel(parent, UDim2.fromOffset(140, 40), UDim2.new(), C.Panel)
	f.LayoutOrder = order
	UI.gradient(f, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 220))
	local badge = UI.new("Frame", { Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = color, Parent = f })
	UI.corner(badge, 16)
	UI.label(badge, icon, UDim2.fromScale(1, 1), UDim2.new(), C.Text)
	return UI.label(f, "0", UDim2.new(1, -46, 1, -10), UDim2.fromOffset(42, 5), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
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

function Hud.new(playerGui: PlayerGui, ctx: Ctx)
	local self = setmetatable({}, Hud) :: any
	self.ctx = ctx
	self.toasts = {}
	self.cardQueue = {}
	self.cardBusy = false
	self.rewardQueue = {}
	self.rewardBusy = false
	self.connections = {}
	self.cravingsCollapsed = false
	self.compact = false
	self.menuButtons = {}
	self.lastCoins = nil

	local gui = UI.new("ScreenGui", {
		Name = "SnackHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		Parent = playerGui,
	})
	self.gui = gui

	local root = UI.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local uiScale = UI.new("UIScale", { Parent = root })
	self.root = root
	self.uiScale = uiScale
	-- Toasts, rewards and coin popups live on their own layer: above panels and still
	-- visible while a cutscene hides the main HUD.
	local popups = UI.new("Frame", { Name = "Popups", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = gui })
	local popupScale = UI.new("UIScale", { Parent = popups })
	self.popups = popups

	------------------------------------------------ stats (top centre)
	local stats = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(600, 44), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0), Parent = root })
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = stats })
	self.coinsLabel = pill(stats, "💰", C.Gold, 1)
	self.incomeLabel = pill(stats, "⚡", C.Green, 2)
	self.strengthLabel = pill(stats, "💪", C.Red, 3)
	self.bestLabel = pill(stats, "📏", C.Blue, 4)
	self.popupHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 120), Position = UDim2.new(0.5, -300, 0, 46), Parent = popups })

	------------------------------------------------ weather banner
	local banner = UI.panel(root, UDim2.fromOffset(440, 64), UDim2.new(0.5, 0, 0, 56), C.Purple)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Visible = false
	UI.gradient(banner, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 200))
	self.bannerTitle = UI.label(banner, "", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 3))
	self.bannerSub = UI.label(banner, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 28), C.Text)
	local _, bannerFill = UI.progressBar(banner, UDim2.new(1, -20, 0, 10), UDim2.fromOffset(10, 49), C.Text)
	self.bannerFill = bannerFill
	self.banner = banner
	self.nextWeather = UI.label(root, "", UDim2.fromOffset(300, 20), UDim2.new(0.5, -150, 0, 56), C.Muted)

	------------------------------------------------ quest tracker (top left)
	local quest = UI.panel(root, UDim2.fromOffset(280, 100), UDim2.fromOffset(12, 8), C.Panel)
	quest.BackgroundTransparency = 0.1
	self.questHeader = UI.label(quest, "QUEST", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 5), C.Gold, { TextXAlignment = Enum.TextXAlignment.Left })
	self.questTitle = UI.label(quest, "", UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 23), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
	self.questHint = UI.label(quest, "", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 46), C.Muted, { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
	local _, questFill, questBarText = UI.progressBar(quest, UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 77), C.Green)
	self.questFill = questFill
	self.questBarText = questBarText
	self.quest = quest

	------------------------------------------------ cravings board (top right, collapsible)
	local board = UI.panel(root, UDim2.fromOffset(236, 268), UDim2.new(1, -248, 0, 8), C.Panel)
	board.BackgroundTransparency = 0.15
	board.ClipsDescendants = true
	local boardHeader = UI.new("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Text = "", Parent = board })
	self.boardTitle = UI.label(boardHeader, "BIOME CRAVINGS  ▾", UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 5), C.Gold)
	boardHeader.Activated:Connect(function()
		self:setCravingsCollapsed(not self.cravingsCollapsed)
	end)
	self.board = board
	self.cravingRows = {}
	local zones = BiomeConfig.allCravingZones()
	for i, zone in zones do
		local row = UI.new("Frame", { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 32 + (i - 1) * 29), BackgroundColor3 = C.PanelLight, Parent = board })
		UI.corner(row, 8)
		UI.label(row, BiomeConfig.zoneName(zone), UDim2.new(0.6, -6, 1, -4), UDim2.fromOffset(6, 2), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
		local crave = UI.label(row, "?", UDim2.new(0.4, -6, 1, -4), UDim2.new(0.6, 0, 0, 2), C.Text, { TextXAlignment = Enum.TextXAlignment.Right })
		self.cravingRows[zone] = { row = row, label = crave }
	end
	self.cravingHint = UI.label(root, "Green rows crave your snack: land there to build a combo (up to 10x mutation odds)!", UDim2.fromOffset(236, 34), UDim2.new(1, -248, 0, 280), C.Muted, { TextWrapped = true })

	------------------------------------------------ left menu
	local menu = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 420), Position = UDim2.fromOffset(12, 118), Parent = root })
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu })
	self.menu = menu
	local function menuButton(key: string, text: string, color: Color3, order: number, height: number?): TextButton
		local b = UI.button(menu, text, color, UDim2.fromOffset(150, height or 44), UDim2.new())
		b.LayoutOrder = order
		self.menuButtons[key] = b
		return b
	end
	local shopBtn = menuButton("Shop", "Food Shop [F]", C.Orange, 1)
	local petsBtn = menuButton("Pets", "Pets & Fuse [G]", C.Pink, 2)
	local indexBtn = menuButton("Index", "Pet Index [N]", C.Blue, 3)
	local settingsBtn = menuButton("Settings", "Settings", Color3.fromRGB(110, 110, 160), 4)
	local helpBtn = menuButton("Help", "How to Play [H]", C.Purple, 5)
	local tpRow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 70), LayoutOrder = 6, Parent = menu })
	UI.label(tpRow, "TELEPORT", UDim2.new(1, 0, 0, 16), UDim2.new(), C.Muted)
	local function tp(key: string, text: string, color: Color3, x: number, w: number, fn: () -> ())
		local b = UI.button(tpRow, text, color, UDim2.fromOffset(w, 46), UDim2.fromOffset(x, 20))
		b.Activated:Connect(fn)
		self.menuButtons[key] = b
	end
	tp("ThrowLine", "Throw", C.Red, 0, 48, ctx.teleportThrowLine)
	tp("Gym", "Gym", C.Purple, 51, 48, ctx.teleportGym)
	tp("Plot", "Plot", C.Green, 102, 48, ctx.teleportPlot)

	------------------------------------------------ bottom controls
	local bottom = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(660, 214), Position = UDim2.new(0.5, -330, 1, -220), Parent = root })
	self.bottom = bottom

	self.contextHint = UI.label(bottom, "", UDim2.fromOffset(520, 22), UDim2.fromOffset(70, 0), C.Gold)
	local combo = UI.panel(bottom, UDim2.fromOffset(260, 32), UDim2.fromOffset(200, 26), C.Orange)
	UI.gradient(combo, Color3.new(1, 1, 1), Color3.fromRGB(200, 160, 120))
	self.comboLabel = UI.label(combo, "Combo x1", UDim2.new(1, -12, 1, -6), UDim2.fromOffset(6, 3))
	self.combo = combo

	local meter = UI.panel(bottom, UDim2.fromOffset(460, 34), UDim2.fromOffset(100, 66), Color3.fromRGB(20, 20, 35))
	local sweet = UI.new("Frame", {
		Size = UDim2.new(1 - GameConfig.SweetSpotMin, 0, 1, 0),
		Position = UDim2.new(GameConfig.SweetSpotMin, 0, 0, 0),
		BackgroundColor3 = C.Green,
		BorderSizePixel = 0,
		Parent = meter,
	})
	UI.corner(sweet, 10)
	self.sweetZone = sweet
	sweet.ZIndex = 2
	sweet.BackgroundTransparency = 0.25 -- drawn over the fill so it can light up
	local fill = UI.new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.Gold, BorderSizePixel = 0, Parent = meter })
	UI.corner(fill, 10)
	UI.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 60)), Parent = fill })
	self.meterText = UI.label(meter, "", UDim2.new(1, -10, 1, -8), UDim2.fromOffset(5, 4), C.Text, { ZIndex = 3 })
	UI.label(sweet, "SWEET", UDim2.new(1, 0, 0.5, 0), UDim2.fromScale(0, -0.55), C.Green)
	self.meterFill = fill
	self.meter = meter
	self.meterStroke = meter:FindFirstChildOfClass("UIStroke")

	local throwBtn = UI.button(bottom, "THROW (E)", C.Red, UDim2.fromOffset(200, 84), UDim2.fromOffset(230, 116))
	self.throwBtn = throwBtn
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	throwBtn.InputBegan:Connect(function(input)
		if isPress(input) then
			ctx.onThrowDown(input)
		end
	end)
	local trainBtn = UI.button(bottom, "TRAIN (Q)", C.Purple, UDim2.fromOffset(160, 64), UDim2.fromOffset(56, 126))
	trainBtn.InputBegan:Connect(function(input)
		if isPress(input) then
			ctx.onTrainDown(input)
		end
	end)
	self.trainBtn = trainBtn

	local foodChip = UI.panel(bottom, UDim2.fromOffset(170, 64), UDim2.fromOffset(446, 126), C.PanelLight)
	self.foodName = UI.label(foodChip, "Berry Bite", UDim2.new(1, -12, 0.5, -4), UDim2.fromOffset(6, 4))
	self.foodInfo = UI.label(foodChip, "", UDim2.new(1, -12, 0.4, -2), UDim2.new(0, 6, 0.55, 0), C.Muted)
	local foodButton = UI.new("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", Parent = foodChip })
	foodButton.Activated:Connect(function()
		self.panels:toggle("Shop")
	end)

	self.autoBadge = UI.label(bottom, "AUTO-THROW ON", UDim2.fromOffset(170, 20), UDim2.fromOffset(446, 104), C.Green)
	self.autoBadge.Visible = false
	self.gymBadge = UI.label(bottom, "GYM: 2x TRAINING!", UDim2.fromOffset(170, 20), UDim2.fromOffset(46, 104), C.Pink)
	self.gymBadge.Visible = false

	self.saveWarning = UI.label(root, "", UDim2.fromOffset(500, 18), UDim2.new(0.5, -250, 1, -20), C.Red)

	------------------------------------------------ overlays
	local toastHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(520, 220), Position = UDim2.new(0.5, -260, 0, 128), Parent = popups })
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = toastHolder })
	self.toastHolder = toastHolder

	local card = UI.panel(root, UDim2.fromOffset(330, 176), UDim2.new(1, 20, 0.5, -40), C.Panel)
	card.Visible = false
	self.card = card
	self.cardStroke = card:FindFirstChildOfClass("UIStroke")
	self.cardViewHolder = UI.new("Frame", { BackgroundColor3 = C.PanelLight, Size = UDim2.fromOffset(96, 96), Position = UDim2.fromOffset(10, 10), Parent = card })
	UI.corner(self.cardViewHolder, 12)
	self.cardNew = UI.label(self.cardViewHolder, "NEW!", UDim2.fromOffset(56, 22), UDim2.fromOffset(-6, -8), C.Gold, { Rotation = -12, ZIndex = 4 })
	self.cardTitle = UI.label(card, "", UDim2.new(1, -126, 0, 30), UDim2.fromOffset(116, 10), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
	self.cardRarity = UI.label(card, "", UDim2.new(1, -126, 0, 22), UDim2.fromOffset(116, 42), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
	self.cardInfo = UI.label(card, "", UDim2.new(1, -126, 0, 20), UDim2.fromOffset(116, 66), C.Muted, { TextXAlignment = Enum.TextXAlignment.Left })
	self.cardIncome = UI.label(card, "", UDim2.new(1, -126, 0, 22), UDim2.fromOffset(116, 88), C.Gold, { TextXAlignment = Enum.TextXAlignment.Left })
	self.cardExtra = UI.label(card, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 114), C.Orange)
	self.cardFooter = UI.label(card, "", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 140), C.Green)

	-- Reward popup (quests, zones, welcome back).
	local reward = UI.panel(popups, UDim2.fromOffset(420, 128), UDim2.new(0.5, -210, 0.5, -150), C.Panel)
	reward.Visible = false
	reward.ZIndex = 30
	self.rewardStroke = reward:FindFirstChildOfClass("UIStroke")
	if self.rewardStroke then
		self.rewardStroke.Thickness = 4
	end
	UI.gradient(reward, Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 210))
	self.rewardTitle = UI.label(reward, "", UDim2.new(1, -20, 0, 40), UDim2.fromOffset(10, 8), C.Gold, { ZIndex = 31 })
	self.rewardText = UI.label(reward, "", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 52), C.Text, { ZIndex = 31 })
	self.rewardCoins = UI.label(reward, "", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 84), C.Gold, { ZIndex = 31 })
	self.reward = reward

	-- Cutscene letterbox + skip.
	local overlay = UI.new("Frame", { Name = "Cutscene", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.11, 0), ZIndex = 20, Parent = overlay })
	UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.11, 0), Position = UDim2.fromScale(0, 0.89), ZIndex = 20, Parent = overlay })
	self.cutsceneTitle = UI.label(overlay, "", UDim2.new(0.8, 0, 0.1, 0), UDim2.fromScale(0.1, 0.14), C.Gold, { ZIndex = 21 })
	self.cutsceneSub = UI.label(overlay, "", UDim2.new(0.6, 0, 0.06, 0), UDim2.fromScale(0.2, 0.25), C.Text, { ZIndex = 21 })
	self.overlay = overlay
	local skip = UI.button(gui, "SKIP  >>  (Space)", C.PanelLight, UDim2.fromOffset(220, 50), UDim2.new(1, -240, 1, -70))
	skip.ZIndex = 25
	skip.Visible = false
	skip.Activated:Connect(ctx.onSkip)
	self.skipButton = skip

	------------------------------------------------ panels
	self.panels = Panels.new(root, ctx, self)
	local function bindPanel(button: TextButton, name: string)
		button.Activated:Connect(function()
			self.panels:toggle(name)
		end)
	end
	bindPanel(shopBtn, "Shop")
	bindPanel(petsBtn, "Pets")
	bindPanel(indexBtn, "Index")
	bindPanel(settingsBtn, "Settings")
	bindPanel(helpBtn, "Help")
	quest.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.panels:toggle("Help")
		end
	end)

	------------------------------------------------ welcome screen (first session)
	local welcome = UI.panel(root, UDim2.fromOffset(560, 330), UDim2.new(0.5, -280, 0.5, -175), C.Panel)
	welcome.Visible = false
	welcome.ZIndex = 35
	UI.gradient(welcome, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 220))
	UI.label(welcome, "WELCOME TO SNACK FORCE!", UDim2.new(1, -30, 0, 40), UDim2.fromOffset(15, 12), C.Gold, { ZIndex = 36 })
	local steps = {
		{ n = "1", title = "TRAIN", text = "Hold Q or TRAIN to get stronger. The Gym doubles it!", color = C.Purple },
		{ n = "2", title = "THROW", text = "At the Throw Line, hold E or THROW and let go in the green SWEET zone.", color = C.Red },
		{ n = "3", title = "CATCH", text = "A pet catches your snack and earns coins on your plot.", color = C.Green },
		{ n = "4", title = "COMBO", text = "Land in biomes that crave your snack for up to 10x mutation odds.", color = C.Orange },
	}
	for i, step in steps do
		local y = 58 + (i - 1) * 54
		local badge = UI.new("Frame", { BackgroundColor3 = step.color, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(18, y), ZIndex = 36, Parent = welcome })
		UI.corner(badge, 22)
		UI.stroke(badge)
		UI.label(badge, step.n, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15), C.Text, { ZIndex = 37 })
		UI.label(welcome, step.title, UDim2.fromOffset(90, 22), UDim2.fromOffset(72, y + 2), step.color, { TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 36 })
		UI.label(welcome, step.text, UDim2.new(1, -96, 0, 20), UDim2.fromOffset(72, y + 24), C.Text, { TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 36 })
	end
	local go = UI.button(welcome, "LET'S GO!", C.Green, UDim2.fromOffset(200, 46), UDim2.new(0.5, -100, 1, -58))
	go.ZIndex = 36
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
			-- Keep touch targets usable on phones while still fitting a 1180-wide layout.
			s = math.max(s, math.min(0.72, v.X / 1180, v.Y / 560))
		end
		s = math.clamp(s, 0.45, 1.5)
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		popupScale.Scale = s
		popups.Size = UDim2.fromScale(1 / s, 1 / s)
		local logical = v / s
		local compact = logical.Y < 650 or logical.X < 1220
		if compact ~= self.compact then
			self.compact = compact
			self:setCravingsCollapsed(compact)
		end
		self.cravingHint.Visible = not compact and not self.cravingsCollapsed
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

	return self
end

function Hud:setCravingsCollapsed(collapsed: boolean)
	self.cravingsCollapsed = collapsed
	self.board.Size = UDim2.fromOffset(236, if collapsed then 36 else 268)
	self.boardTitle.Text = if collapsed then "BIOME CRAVINGS  ▸" else "BIOME CRAVINGS  ▾"
	self.cravingHint.Visible = not collapsed and not self.compact
end

function Hud:update(state: any)
	local coins = state.coins or 0
	self.coinsLabel.Text = GameMath.formatNumber(coins)
	self.incomeLabel.Text = GameMath.formatNumber(state.income or 0) .. "/s"
	self.strengthLabel.Text = GameMath.formatNumber(state.strength or 0)
	self.bestLabel.Text = GameMath.formatNumber(state.bestDistance or 0) .. "m"
	local mult = state.comboMult or 1
	local streak = state.streak or 0
	self.comboLabel.Text = if streak > 0 then string.format("COMBO x%s  (streak %d)", tostring(mult), streak) else "Combo x1: match a craving!"
	self.combo.BackgroundColor3 = if mult >= 10 then C.Pink elseif mult >= 4 then C.Purple elseif streak > 0 then C.Orange else C.PanelLight
	local food = FoodConfig.get(state.equippedFood) or FoodConfig.Foods[1]
	self.foodName.Text = food.name
	self.foodInfo.Text = string.format("%s %s  x%.2f power", FoodConfig.CravingIcons[food.craving] or "", food.craving, food.power)
	self.foodName.TextColor3 = food.color:Lerp(Color3.new(1, 1, 1), 0.35)
	self.equippedCraving = food.craving
	local settings = state.settings
	self.autoBadge.Visible = settings ~= nil and settings.AutoThrow == true and state.autoThrowUnlocked == true
	self.saveWarning.Text = if state.canSave == false then "Progress is not being saved this session" else ""
	self:refreshCravings()
	self:refreshQuest(state.quest, state.loaded == true)
	-- Shop/settings refresh on every sync (coins tick up); grids only on full syncs.
	self.panels:refresh(state, state.full == true)
	self.lastCoins = coins
end

function Hud:refreshQuest(q: any, loaded: boolean)
	if not loaded then
		self.questHeader.Text = "QUEST"
		self.questTitle.Text = "Loading your save..."
		self.questHint.Text = ""
		UI.setProgress(self.questFill, 0)
		self.questBarText.Text = ""
		return
	end
	if type(q) ~= "table" then
		self.questHeader.Text = "ALL QUESTS COMPLETE"
		self.questTitle.Text = "Snack Force Legend!"
		self.questHint.Text = "Chase Rainbow and Infinite pets on the Moon."
		UI.setProgress(self.questFill, 1)
		self.questBarText.Text = "DONE"
		self.questFocus = nil
		return
	end
	self.questHeader.Text = string.format("QUEST %d/%d   +%s 💰", q.index or 1, q.total or 1, GameMath.formatNumber(q.reward or 0))
	self.questTitle.Text = q.title or ""
	self.questHint.Text = q.hint or ""
	local target = math.max(q.target or 1, 1)
	UI.setProgress(self.questFill, (q.progress or 0) / target)
	self.questBarText.Text = string.format("%s / %s", GameMath.formatNumber(q.progress or 0), GameMath.formatNumber(target))
	if self.questFocus ~= q.focus or self.questId ~= q.id then
		self.questId = q.id
		self.questFocus = q.focus
		UI.pop(self.quest)
	end
end

function Hud:setCravings(cravings: { [string]: string }?)
	self.cravings = cravings
	self:refreshCravings()
end

function Hud:refreshCravings()
	local cravings = self.cravings or {}
	local matches = 0
	for zone, row in self.cravingRows do
		local c = cravings[zone]
		row.label.Text = if c then (FoodConfig.CravingIcons[c] or "") .. " " .. c else "?"
		row.label.TextColor3 = if c then (FoodConfig.CravingColors[c] or C.Text):Lerp(Color3.new(1, 1, 1), 0.3) else C.Muted
		local match = c ~= nil and c == self.equippedCraving
		if match then
			matches += 1
		end
		row.row.BackgroundColor3 = if match then Color3.fromRGB(40, 120, 70) else C.PanelLight
	end
	if self.cravingsCollapsed then
		self.boardTitle.Text = string.format("CRAVINGS: %d match  ▸", matches)
	end
end

function Hud:setWeather(w: any)
	self.weather = w
	self:setCravings(w and w.cravings)
	if w and w.active then
		local def = GameConfig.getWeather(w.id)
		self.banner.BackgroundColor3 = if def then def.color else C.Purple
		self.bannerTitle.Text = string.upper(w.name or "Weather")
		self.banner.Visible = true
		self.nextWeather.Visible = false
		UI.pop(self.banner)
	else
		self.banner.Visible = false
		self.nextWeather.Visible = true
	end
end

function Hud:setContext(text: string?)
	self.contextHint.Text = text or ""
end

function Hud:setGym(inGym: boolean)
	self.gymBadge.Visible = inGym
	self.trainBtn.BackgroundColor3 = if inGym then C.Pink else C.Purple
end

-- Called every frame for countdowns and the charge meter.
function Hud:tick(charge: number?, preview: string?)
	local w = self.weather
	if w then
		local now = Workspace:GetServerTimeNow()
		if w.active then
			local left = math.max(0, (w.endsAt or now) - now)
			self.bannerSub.Text = string.format("%s  -  %ds left", w.description or "", math.ceil(left))
			UI.setProgress(self.bannerFill, left / GameConfig.WeatherDuration)
		else
			local left = math.max(0, math.ceil((w.nextAt or now) - now))
			self.nextWeather.Text = string.format("Next weather event in %d:%02d", left // 60, left % 60)
		end
	end
	if charge then
		self.meterFill.Size = UDim2.new(charge, 0, 1, 0)
		local sweet = GameMath.isSweetSpot(charge)
		self.meterText.Text = if sweet then "SWEET SPOT! LET GO!  " .. (preview or "") else string.format("%d%%  %s", math.floor(charge * 100), preview or "")
		self.meterText.TextColor3 = if sweet then C.Green else C.Text
		if self.meterStroke then
			self.meterStroke.Color = if sweet then C.Green else C.Stroke
		end
		self.sweetZone.BackgroundColor3 = if sweet then Color3.fromRGB(150, 255, 170) else C.Green
	else
		self.meterFill.Size = UDim2.new(0, 0, 1, 0)
		self.meterText.Text = "Hold E / THROW, let go in the green zone"
		self.meterText.TextColor3 = C.Text
		if self.meterStroke then
			self.meterStroke.Color = C.Stroke
		end
		self.sweetZone.BackgroundColor3 = C.Green
	end
end

-- Pulses a HUD button to draw attention (quest focus).
function Hud:pulse(key: string)
	local b = self.menuButtons[key]
	if b then
		UI.pop(b)
	end
end

function Hud:toast(text: string, color: Color3?)
	-- Collapse identical toasts instead of stacking duplicates.
	for _, existing in self.toasts do
		if existing:GetAttribute("Text") == text then
			UI.pop(existing)
			return
		end
	end
	local t = UI.panel(self.toastHolder, UDim2.fromOffset(480, 38), UDim2.new(), color or C.PanelLight)
	t:SetAttribute("Text", text)
	UI.gradient(t, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 210))
	UI.label(t, text, UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4))
	UI.pop(t)
	table.insert(self.toasts, t)
	while #self.toasts > 4 do
		local old = table.remove(self.toasts, 1)
		if old then
			old:Destroy()
		end
	end
	task.delay(2.8, function()
		local idx = table.find(self.toasts, t)
		if idx then
			table.remove(self.toasts, idx)
		end
		if t.Parent then
			t:Destroy()
		end
	end)
end

-- Floating "+123" next to the coin counter.
function Hud:coinPopup(amount: number, color: Color3?)
	if amount <= 0 then
		return
	end
	local l = UI.label(self.popupHolder, "+" .. GameMath.formatNumber(amount) .. " 💰", UDim2.fromOffset(180, 30), UDim2.fromOffset(math.random(0, 20), 0), color or C.Gold)
	UI.pop(l)
	UI.tween(l, 1.4, { Position = l.Position + UDim2.fromOffset(0, 70), TextTransparency = 1 })
	task.delay(1.45, function()
		l:Destroy()
	end)
	UI.pop(self.coinsLabel.Parent :: any)
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
			local color = (C :: any)[p.color or "Gold"] or C.Gold
			self.rewardTitle.Text = p.title or "REWARD!"
			self.rewardTitle.TextColor3 = color
			self.rewardText.Text = p.text or ""
			self.rewardCoins.Text = if (p.coins or 0) > 0 then "+" .. GameMath.formatNumber(p.coins) .. " coins" else ""
			if self.rewardStroke then
				self.rewardStroke.Color = color
			end
			self.reward.Visible = true
			UI.pop(self.reward)
			self:coinPopup(p.coins or 0, color)
			task.wait(2.2)
			self.reward.Visible = false
			task.wait(0.15)
		end
		self.rewardBusy = false
	end)
end

function Hud:showWelcome()
	self.welcome.Visible = true
	UI.pop(self.welcome)
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
			card.Position = UDim2.new(1, 20, 0.5, -40)
			card.Visible = true
			UI.tween(card, 0.35, { Position = UDim2.new(1, -350, 0.5, -40) }, Enum.EasingStyle.Back)
			task.wait(if #self.cardQueue > 0 then 1.6 else 2.6)
			UI.tween(card, 0.25, { Position = UDim2.new(1, 20, 0.5, -40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.27)
			card.Visible = false
		end
		self.cardBusy = false
	end)
end

function Hud:renderCard(p: any)
	local rec = p.pet or {}
	local pet = PetConfig.get(rec.species)
	local rarityColor = (GameConfig.RarityColors :: any)[p.rarity] or C.Text
	self.cardTitle.Text = mutationText(rec) .. (if pet then pet.name else "Pet")
	self.cardTitle.TextColor3 = rarityColor
	self.cardRarity.Text = string.upper(p.rarity or "Common")
	self.cardRarity.TextColor3 = rarityColor
	if self.cardStroke then
		self.cardStroke.Color = rarityColor
	end
	self.cardViewHolder.BackgroundColor3 = C.PanelLight:Lerp(rarityColor, 0.25)
	for _, child in self.cardViewHolder:GetChildren() do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end
	if pet then
		UI.petViewport(self.cardViewHolder :: any, rec, UDim2.fromScale(1, 1), UDim2.new())
	end
	self.cardNew.Visible = p.newSpecies == true
	self.cardInfo.Text = string.format("%sm  -  %s%s", GameMath.formatNumber(p.distance or 0), p.zoneName or BiomeConfig.zoneName(p.zone), if p.sweetSpot then "  -  SWEET!" else "")
	self.cardIncome.Text = "+" .. GameMath.formatNumber(p.income or 0) .. " coins/sec"
	local extras = {}
	if (p.bonusCoins or 0) > 0 then
		table.insert(extras, "Craving +" .. GameMath.formatNumber(p.bonusCoins))
	end
	if (p.discoveryReward or 0) > 0 then
		table.insert(extras, "New species +" .. GameMath.formatNumber(p.discoveryReward))
	end
	self.cardExtra.Text = table.concat(extras, "   ")
	if p.outcome == "sold" then
		self.cardFooter.Text = "Auto-sold for " .. GameMath.formatNumber(p.soldFor or 0)
		self.cardFooter.TextColor3 = C.Gold
	elseif p.outcome == "full" then
		self.cardFooter.Text = "Inventory full! Sold for " .. GameMath.formatNumber(p.soldFor or 0)
		self.cardFooter.TextColor3 = C.Red
	elseif rec.equipped then
		self.cardFooter.Text = "Placed on your plot!"
		self.cardFooter.TextColor3 = C.Green
	else
		self.cardFooter.Text = "Added to your pets (plot full: try Equip Best)"
		self.cardFooter.TextColor3 = C.Muted
	end
end

function Hud:setCutscene(active: boolean, title: string?, sub: string?)
	self.overlay.Visible = active
	self.skipButton.Visible = active
	self.root.Visible = not active
	self.cutsceneTitle.Text = title or ""
	self.cutsceneSub.Text = sub or ""
	if active and title then
		UI.pop(self.cutsceneTitle :: any)
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
