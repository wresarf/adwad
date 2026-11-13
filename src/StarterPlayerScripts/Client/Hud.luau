--!strict
-- Main HUD: stats, weather banner, cravings board, charge meter, throw/train buttons,
-- toasts, catch cards, cutscene overlay and the menu that opens the panels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	onThrowDown: () -> (),
	onThrowUp: () -> (),
	onTrain: () -> (),
	teleportThrowLine: () -> (),
	teleportPlot: () -> (),
	onSkip: () -> (),
}

local Hud = {}
Hud.__index = Hud

local function pill(parent: Instance, icon: string, color: Color3, x: number): TextLabel
	local f = UI.panel(parent, UDim2.fromOffset(176, 44), UDim2.new(0.5, x, 0, 8), C.Panel)
	f.AnchorPoint = Vector2.new(0.5, 0)
	UI.gradient(f, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 220))
	local badge = UI.new("Frame", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = color, Parent = f })
	UI.corner(badge, 18)
	UI.label(badge, icon, UDim2.fromScale(1, 1), UDim2.new(), C.Text)
	return UI.label(f, "0", UDim2.new(1, -50, 1, -10), UDim2.fromOffset(46, 5), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
end

function Hud.new(playerGui: PlayerGui, ctx: Ctx)
	local self = setmetatable({}, Hud) :: any
	self.ctx = ctx
	self.toasts = {}
	self.cardQueue = {}
	self.cardBusy = false
	self.connections = {}

	local gui = UI.new("ScreenGui", {
		Name = "SnackHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		Parent = playerGui,
	})
	self.gui = gui

	-- Logical 1280x720 canvas scaled to the viewport.
	local root = UI.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local uiScale = UI.new("UIScale", { Parent = root })
	self.root = root
	local function rescale()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local v = camera.ViewportSize
		local s = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.5, 1.5)
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	rescale()
	local function hookCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			table.insert(self.connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
		end
		rescale()
	end
	hookCamera()
	table.insert(self.connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera))

	------------------------------------------------ stats
	self.coinsLabel = pill(root, "💰", C.Gold, -282)
	self.incomeLabel = pill(root, "⚡", C.Green, -94)
	self.strengthLabel = pill(root, "💪", C.Red, 94)
	self.bestLabel = pill(root, "📏", C.Blue, 282)

	------------------------------------------------ weather banner
	local banner = UI.panel(root, UDim2.fromOffset(460, 62), UDim2.new(0.5, 0, 0, 60), C.Purple)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Visible = false
	self.bannerGradient = UI.gradient(banner, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 200))
	self.bannerTitle = UI.label(banner, "", UDim2.new(1, -20, 0.55, 0), UDim2.fromOffset(10, 4))
	self.bannerSub = UI.label(banner, "", UDim2.new(1, -20, 0.38, 0), UDim2.new(0, 10, 0.58, 0), C.Text)
	self.banner = banner
	self.nextWeather = UI.label(root, "", UDim2.fromOffset(300, 22), UDim2.new(0.5, -150, 0, 60), C.Muted)

	------------------------------------------------ cravings board (right)
	local board = UI.panel(root, UDim2.fromOffset(236, 270), UDim2.new(1, -248, 0, 70), C.Panel)
	board.BackgroundTransparency = 0.15
	UI.label(board, "BIOME CRAVINGS", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 6), C.Gold)
	self.cravingRows = {}
	local zones = BiomeConfig.allCravingZones()
	for i, zone in zones do
		local biome = BiomeConfig.get(zone)
		local name = if biome then biome.name else ((BiomeConfig.Celestial :: any)[zone].name)
		local row = UI.new("Frame", { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 30 + (i - 1) * 29), BackgroundColor3 = C.PanelLight, Parent = board })
		UI.corner(row, 8)
		UI.label(row, name, UDim2.new(0.62, -6, 1, -4), UDim2.fromOffset(6, 2), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
		local crave = UI.label(row, "?", UDim2.new(0.38, -6, 1, -4), UDim2.new(0.62, 0, 0, 2), C.Text, { TextXAlignment = Enum.TextXAlignment.Right })
		self.cravingRows[zone] = { row = row, label = crave }
	end
	self.cravingHint = UI.label(root, "Match a biome's craving to build a combo (up to 10x mutation odds)!", UDim2.fromOffset(236, 30), UDim2.new(1, -248, 0, 344), C.Muted, { TextWrapped = true })

	------------------------------------------------ left menu
	local menu = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(130, 320), Position = UDim2.new(0, 12, 0.5, -170), Parent = root })
	UI.new("UIListLayout", { Padding = UDim.new(0, 8), Parent = menu })
	local function menuButton(text: string, color: Color3): TextButton
		return UI.button(menu, text, color, UDim2.fromOffset(130, 54), UDim2.new())
	end
	local shopBtn = menuButton("Food Shop", C.Orange)
	local petsBtn = menuButton("Pets & Fuse", C.Pink)
	local settingsBtn = menuButton("Settings", C.Blue)
	local throwTp = menuButton("Throw Line", C.Red)
	local plotTp = menuButton("My Plot", C.Green)
	throwTp.Activated:Connect(ctx.teleportThrowLine)
	plotTp.Activated:Connect(ctx.teleportPlot)

	------------------------------------------------ bottom controls
	local bottom = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(640, 190), Position = UDim2.new(0.5, -320, 1, -200), Parent = root })
	self.bottom = bottom

	local combo = UI.panel(bottom, UDim2.fromOffset(250, 34), UDim2.fromOffset(195, 0), C.Orange)
	UI.gradient(combo, Color3.new(1, 1, 1), Color3.fromRGB(200, 160, 120))
	self.comboLabel = UI.label(combo, "Combo x1", UDim2.new(1, -12, 1, -6), UDim2.fromOffset(6, 3))
	self.combo = combo

	local meter = UI.panel(bottom, UDim2.fromOffset(440, 36), UDim2.fromOffset(100, 44), Color3.fromRGB(20, 20, 35))
	local sweet = UI.new("Frame", {
		Size = UDim2.new(1 - GameConfig.SweetSpotMin, 0, 1, 0),
		Position = UDim2.new(GameConfig.SweetSpotMin, 0, 0, 0),
		BackgroundColor3 = C.Green,
		BorderSizePixel = 0,
		Parent = meter,
	})
	UI.corner(sweet, 10)
	local fill = UI.new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.Gold, BorderSizePixel = 0, Parent = meter })
	UI.corner(fill, 10)
	UI.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 60)), Parent = fill })
	self.meterText = UI.label(meter, "Hold THROW (E) - release in the green zone!", UDim2.new(1, -10, 1, -8), UDim2.fromOffset(5, 4), C.Text, { ZIndex = 3 })
	UI.label(sweet, "SWEET", UDim2.new(1, 0, 0.5, 0), UDim2.fromScale(0, -0.55), C.Green)
	self.meterFill = fill
	self.meter = meter

	local throwBtn = UI.button(bottom, "THROW", C.Red, UDim2.fromOffset(200, 84), UDim2.fromOffset(220, 96))
	self.throwBtn = throwBtn
	throwBtn.MouseButton1Down:Connect(ctx.onThrowDown)
	throwBtn.MouseButton1Up:Connect(ctx.onThrowUp)
	local trainBtn = UI.button(bottom, "TRAIN (Q)", C.Purple, UDim2.fromOffset(150, 64), UDim2.fromOffset(50, 106))
	trainBtn.Activated:Connect(ctx.onTrain)
	self.trainBtn = trainBtn

	local foodChip = UI.panel(bottom, UDim2.fromOffset(170, 64), UDim2.fromOffset(440, 106), C.PanelLight)
	self.foodName = UI.label(foodChip, "Berry Bite", UDim2.new(1, -12, 0.5, -4), UDim2.fromOffset(6, 4))
	self.foodInfo = UI.label(foodChip, "", UDim2.new(1, -12, 0.4, -2), UDim2.new(0, 6, 0.55, 0), C.Muted)
	self.autoBadge = UI.label(root, "AUTO-THROW ON", UDim2.fromOffset(220, 28), UDim2.new(0.5, -110, 1, -230), C.Green)
	self.autoBadge.Visible = false

	self.saveWarning = UI.label(root, "", UDim2.fromOffset(500, 20), UDim2.new(0.5, -250, 1, -22), C.Red)

	------------------------------------------------ overlays
	local toastHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(520, 300), Position = UDim2.new(0.5, -260, 0, 130), Parent = root })
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = toastHolder })
	self.toastHolder = toastHolder

	local card = UI.panel(root, UDim2.fromOffset(310, 168), UDim2.new(1, 20, 0.5, 30), C.Panel)
	card.Visible = false
	self.card = card
	self.cardStroke = card:FindFirstChildOfClass("UIStroke")
	self.cardTitle = UI.label(card, "", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 8))
	self.cardRarity = UI.label(card, "", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 44))
	self.cardInfo = UI.label(card, "", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 72), C.Muted)
	self.cardIncome = UI.label(card, "", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 98), C.Gold)
	self.cardFooter = UI.label(card, "", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 132), C.Green)

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
	shopBtn.Activated:Connect(function()
		self.panels:toggle("Shop")
	end)
	petsBtn.Activated:Connect(function()
		self.panels:toggle("Pets")
	end)
	settingsBtn.Activated:Connect(function()
		self.panels:toggle("Settings")
	end)

	return self
end

function Hud:update(state: any)
	self.coinsLabel.Text = GameMath.formatNumber(state.coins or 0)
	self.incomeLabel.Text = GameMath.formatNumber(state.income or 0) .. "/s"
	self.strengthLabel.Text = GameMath.formatNumber(state.strength or 0)
	self.bestLabel.Text = GameMath.formatNumber(state.bestDistance or 0) .. "m"
	local mult = state.comboMult or 1
	local streak = state.streak or 0
	self.comboLabel.Text = if streak > 0 then string.format("COMBO x%s  (streak %d)", tostring(mult), streak) else "Combo x1 - match a craving!"
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
	if state.full then
		self.panels:refresh(state)
	end
end

function Hud:setCravings(cravings: { [string]: string }?)
	self.cravings = cravings
	self:refreshCravings()
end

function Hud:refreshCravings()
	local cravings = self.cravings or {}
	for zone, row in self.cravingRows do
		local c = cravings[zone]
		row.label.Text = if c then (FoodConfig.CravingIcons[c] or "") .. " " .. c else "?"
		row.label.TextColor3 = if c then (FoodConfig.CravingColors[c] or C.Text):Lerp(Color3.new(1, 1, 1), 0.3) else C.Muted
		local match = c ~= nil and c == self.equippedCraving
		row.row.BackgroundColor3 = if match then Color3.fromRGB(40, 120, 70) else C.PanelLight
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

-- Called every frame for countdowns and the charge meter.
function Hud:tick(charge: number?)
	local w = self.weather
	if w then
		local now = Workspace:GetServerTimeNow()
		if w.active then
			local left = math.max(0, math.ceil((w.endsAt or now) - now))
			self.bannerSub.Text = string.format("%s  -  %ds left", w.description or "", left)
		else
			local left = math.max(0, math.ceil((w.nextAt or now) - now))
			self.nextWeather.Text = string.format("Next weather event in %d:%02d", left // 60, left % 60)
		end
	end
	if charge then
		self.meterFill.Size = UDim2.new(charge, 0, 1, 0)
		local sweet = GameMath.isSweetSpot(charge)
		self.meterText.Text = if sweet then "SWEET SPOT! RELEASE!" else string.format("%d%%", math.floor(charge * 100))
		self.meterText.TextColor3 = if sweet then C.Green else C.Text
	else
		self.meterFill.Size = UDim2.new(0, 0, 1, 0)
		self.meterText.Text = "Hold THROW (E) - release in the green zone!"
		self.meterText.TextColor3 = C.Text
	end
end

function Hud:toast(text: string, color: Color3?)
	local t = UI.panel(self.toastHolder, UDim2.fromOffset(480, 40), UDim2.new(), color or C.PanelLight)
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
			card.Position = UDim2.new(1, 20, 0.5, 30)
			card.Visible = true
			UI.tween(card, 0.35, { Position = UDim2.new(1, -330, 0.5, 30) }, Enum.EasingStyle.Back)
			task.wait(2.4)
			UI.tween(card, 0.25, { Position = UDim2.new(1, 20, 0.5, 30) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
	local mut = {}
	if rec.size and rec.size ~= "Normal" then
		table.insert(mut, rec.size)
	end
	if rec.material and rec.material ~= "Normal" then
		table.insert(mut, rec.material)
	end
	self.cardTitle.Text = (if #mut > 0 then table.concat(mut, " ") .. " " else "") .. (if pet then pet.name else "Pet")
	self.cardTitle.TextColor3 = rarityColor
	self.cardRarity.Text = string.upper(p.rarity or "Common")
	self.cardRarity.TextColor3 = rarityColor
	if self.cardStroke then
		self.cardStroke.Color = rarityColor
	end
	local zoneBiome = BiomeConfig.get(p.zone)
	local zoneName = if zoneBiome then zoneBiome.name else ((BiomeConfig.Celestial :: any)[p.zone] or { name = p.zone }).name
	self.cardInfo.Text = string.format("%sm  -  %s%s", GameMath.formatNumber(p.distance or 0), zoneName or "?", if p.sweetSpot then "  -  SWEET!" else "")
	self.cardIncome.Text = "+" .. GameMath.formatNumber(p.income or 0) .. " coins/sec"
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
		self.cardFooter.Text = "Added to your pets"
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

function Hud:destroy()
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	self.gui:Destroy()
end

return Hud
