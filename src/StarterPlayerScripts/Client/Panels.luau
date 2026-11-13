--!strict
-- Modal panels: Food Shop, Pets & Fuse, Pet Index, Settings and How to Play.
-- Only one is open at a time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))
local GameMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameMath"))
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))

local UI = require(script.Parent:WaitForChild("UI"))
local C = UI.Colors

local Panels = {}
Panels.__index = Panels

local AUTO_SELL_OPTIONS = { "Off", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local AUTO_SKIP_OPTIONS = { "Off", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local SORTS = { "Income", "Rarity", "Count" }
local MAX_VIEWPORTS = 30 -- pet cards beyond this show a colour swatch instead of a 3D preview

local function cycle(list: { string }, current: string): string
	local i = table.find(list, current) or 0
	return list[(i % #list) + 1]
end

local function shell(root: Instance, title: string, color: Color3, onClose: () -> ()): (Frame, ScrollingFrame, Frame)
	local frame = UI.panel(root, UDim2.fromOffset(700, 480), UDim2.new(0.5, -350, 0.5, -235), C.Panel)
	frame.Visible = false
	frame.Active = true -- taps on the panel must not reach the THROW / TRAIN buttons below
	frame.ZIndex = 10
	local header = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = color, BorderSizePixel = 0, Parent = frame })
	UI.corner(header, 14)
	UI.gradient(header, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 200))
	UI.label(header, title, UDim2.new(1, -80, 1, -12), UDim2.fromOffset(16, 6), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
	local close = UI.button(header, "X", C.Red, UDim2.fromOffset(44, 44), UDim2.new(1, -50, 0, 5))
	close.Activated:Connect(onClose)
	local toolbar = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 44), Position = UDim2.fromOffset(12, 62), Parent = frame })
	local list = UI.new("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -122),
		Position = UDim2.fromOffset(12, 112),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = frame,
	})
	UI.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = list })
	return frame, list, toolbar
end

local function clearList(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Panels.new(root: Instance, ctx: any, hud: any)
	local self = setmetatable({}, Panels) :: any
	self.ctx = ctx
	self.hud = hud
	self.frames = {}
	self.open = nil
	self.state = nil
	self.sort = "Income"
	self.fusableOnly = false

	local function close()
		self:toggle(nil)
	end

	local function run(name: string, ...: any)
		local ok, msg = ctx.invoke(name, ...)
		hud:toast(msg, if ok then C.Green else C.Red)
		return ok
	end
	self.run = run

	------------------------------------------------ shop
	local shop, shopList, shopBar = shell(root, "FOOD SHOP", C.Orange, close)
	self.shopHint = UI.label(shopBar, "Better snacks fly further and add luck. Match biome cravings for combos!", UDim2.fromScale(1, 1), UDim2.new(), C.Muted)
	UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = shopList })
	self.shopRows = {}
	for i, food in FoodConfig.Foods do
		local row = UI.panel(shopList, UDim2.new(1, -14, 0, 78), UDim2.new(), C.PanelLight)
		row.LayoutOrder = i
		local swatch = UI.new("Frame", { Size = UDim2.fromOffset(58, 58), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = food.color, Parent = row })
		UI.corner(swatch, if food.shape == "Block" then 10 else 29)
		UI.stroke(swatch)
		UI.gradient(swatch, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
		UI.label(swatch, FoodConfig.CravingIcons[food.craving] or "", UDim2.fromScale(0.66, 0.66), UDim2.fromScale(0.17, 0.17))
		UI.label(row, food.name, UDim2.new(0, 280, 0, 26), UDim2.fromOffset(80, 6), food.color:Lerp(Color3.new(1, 1, 1), 0.4), { TextXAlignment = Enum.TextXAlignment.Left })
		UI.label(row, string.format("%s %s craving  -  x%.2f power  -  x%.2f luck", FoodConfig.CravingIcons[food.craving] or "", food.craving, food.power, food.luck), UDim2.new(0, 330, 0, 18), UDim2.fromOffset(80, 33), C.Muted, { TextXAlignment = Enum.TextXAlignment.Left })
		UI.label(row, food.description, UDim2.new(0, 330, 0, 16), UDim2.fromOffset(80, 53), C.Muted, { TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 0.25 })
		local buy = UI.button(row, "", C.Green, UDim2.fromOffset(180, 46), UDim2.new(1, -192, 0, 8))
		buy.Activated:Connect(function()
			run("BuyFood", food.id)
		end)
		local _, fill, barText = UI.progressBar(row, UDim2.fromOffset(180, 14), UDim2.new(1, -192, 0, 58), C.Gold)
		self.shopRows[food.id] = { button = buy, fill = fill, barText = barText, bar = fill.Parent, row = row }
	end
	self.frames.Shop = shop

	------------------------------------------------ pets
	local pets, petList, petBar = shell(root, "PETS & FUSE", C.Pink, close)
	local function barButton(text: string, color: Color3, x: number, w: number, fn: () -> ()): TextButton
		local b = UI.button(petBar, text, color, UDim2.fromOffset(w, 42), UDim2.fromOffset(x, 0))
		b.Activated:Connect(fn)
		return b
	end
	barButton("Equip Best", C.Green, 0, 112, function()
		run("EquipBest")
	end)
	barButton("Fuse All", C.Purple, 118, 98, function()
		run("FusePets", "ALL")
	end)
	self.autoSellButton = barButton("Auto-Sell: Off", C.Orange, 222, 162, function()
		local st = self.state
		local current = if st and st.settings then st.settings.AutoSellRarity else "Off"
		run("AutoSell", cycle(AUTO_SELL_OPTIONS, current), false)
	end)
	barButton("Sell Matching", C.Red, 390, 128, function()
		local st = self.state
		local current = if st and st.settings then st.settings.AutoSellRarity else "Off"
		if current == "Off" then
			hud:toast("Pick an Auto-Sell rarity first", C.Red)
			return
		end
		run("AutoSell", current, true)
	end)
	self.sortButton = barButton("Sort: Income", C.Blue, 524, 128, function()
		self.sort = cycle(SORTS, self.sort)
		if self.state then
			self:refreshPets(self.state)
		end
	end)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(160, 176), CellPadding = UDim2.fromOffset(9, 9), SortOrder = Enum.SortOrder.LayoutOrder, Parent = petList })
	self.petList = petList
	self.petCountLabel = UI.label(pets, "", UDim2.fromOffset(330, 22), UDim2.new(0, 300, 0, 16), C.Text, { ZIndex = 12 })
	self.frames.Pets = pets

	------------------------------------------------ index
	local index, indexList, indexBar = shell(root, "PET INDEX", C.Blue, close)
	self.indexHint = UI.label(indexBar, "", UDim2.fromScale(1, 1), UDim2.new(), C.Muted)
	UI.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = indexList })
	self.indexList = indexList
	self.frames.Index = index

	------------------------------------------------ settings
	local settings, setList, setBar = shell(root, "SETTINGS", Color3.fromRGB(110, 110, 160), close)
	UI.label(setBar, "Cutscenes can always be skipped with SKIP, Space or Enter.", UDim2.fromScale(1, 1), UDim2.new(), C.Muted)
	UI.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = setList })
	self.settingButtons = {}
	local function settingRow(order: number, key: string, title: string, desc: string, onClick: () -> ())
		local row = UI.panel(setList, UDim2.new(1, -14, 0, 66), UDim2.new(), C.PanelLight)
		row.LayoutOrder = order
		UI.label(row, title, UDim2.new(0, 420, 0, 28), UDim2.fromOffset(12, 6), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
		UI.label(row, desc, UDim2.new(0, 440, 0, 20), UDim2.fromOffset(12, 38), C.Muted, { TextXAlignment = Enum.TextXAlignment.Left })
		local b = UI.button(row, "", C.Blue, UDim2.fromOffset(170, 48), UDim2.new(1, -182, 0, 9))
		b.Activated:Connect(onClick)
		self.settingButtons[key] = b
	end
	local function current(key: string): any
		local st = self.state
		return if st and st.settings then st.settings[key] else nil
	end
	settingRow(1, "AutoThrow", "Auto-Throw", "Late game: throws for you every few seconds (no sweet spot bonus).", function()
		run("ToggleSetting", "AutoThrow", not current("AutoThrow"))
	end)
	settingRow(2, "ShowCutscenes", "Camera Effects & Cutscenes", "Follow your snack and watch the Space / Moon cutscenes.", function()
		run("ToggleSetting", "ShowCutscenes", not current("ShowCutscenes"))
	end)
	settingRow(3, "AutoSkipRarity", "Auto-Skip Cutscenes Below", "Space/Moon cutscenes for catches below this rarity are skipped.", function()
		run("ToggleSetting", "AutoSkipRarity", cycle(AUTO_SKIP_OPTIONS, current("AutoSkipRarity") or "Off"))
	end)
	settingRow(4, "KeepMutated", "Never Auto-Sell Mutations", "Protects Gold+ materials and Huge+ sizes from auto-sell.", function()
		run("ToggleSetting", "KeepMutated", not current("KeepMutated"))
	end)
	settingRow(5, "ShowGuide", "Quest Guide Beam", "Shows a glowing path to where your current quest happens.", function()
		run("ToggleSetting", "ShowGuide", current("ShowGuide") == false)
	end)
	self.frames.Settings = settings

	------------------------------------------------ help
	local help, helpList, helpBar = shell(root, "HOW TO PLAY", C.Purple, close)
	UI.label(helpBar, "Everything you need to become a Snack Force legend.", UDim2.fromScale(1, 1), UDim2.new(), C.Muted)
	UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = helpList })
	local sections = {
		{ title = "Controls", color = C.Blue, text = "Throw: hold E / THROW button / R2, let go in the green zone.\nTrain: hold Q / TRAIN / X.   Skip: Space, Enter or SKIP.\nPanels: F Food Shop, G Pets, N Index, H Help.   Interact with stalls: R." },
		{ title = "Sweet Spot", color = C.Green, text = string.format("Letting go in the green zone gives x%.2f distance and x%.2f mutation luck. Auto-Throw never hits it.", GameConfig.SweetSpotDistanceMult, GameConfig.SweetSpotLuckMult) },
		{ title = "Biomes", color = C.Orange, text = "Sunny Meadow > Sizzle Dunes > Frostbite Peaks > Magma Fields > Toxic Swamp > Nuclear Wasteland. Wind and gravity in each one stretch or shrink your throw. Past 2,500m is Space, past 3,600m the Moon." },
		{ title = "Cravings & Combos", color = C.Pink, text = "Each biome craves Berry, Meat, Spicy or Cosmic snacks. Landing a match builds a streak: x1.5 > x2 > x3 ... up to x10 mutation odds. A miss resets it." },
		{ title = "Mutations", color = C.Gold, text = "Materials: Normal, Gold, Diamond, Emerald, Ruby, Rainbow.\nSizes: Normal, Huge, Colossal, Monstrous, Titanic, Cosmic, Infinite." },
		{ title = "Fusion & Auto-Sell", color = C.Purple, text = "Three identical pets (same species, material and size) fuse into the next material. Auto-Sell sells low-rarity catches for coins. Mutations are protected by default." },
		{ title = "Weather", color = C.Blue, text = string.format("Every %ds a %ds event starts: Titan Storm (3x size luck), Feast Frenzy (2x craving bonus), Prism Aurora (4x material luck). Cravings re-roll each time.", GameConfig.WeatherInterval, GameConfig.WeatherDuration) },
		{ title = "Progress", color = C.Green, text = string.format("Quests pay coins and guide you. First landings in a zone and new species give bonus coins. Your plot keeps earning %d%% while you're offline (up to %dh). Auto-Throw unlocks at %dm.", math.floor(GameConfig.OfflineRate * 100), GameConfig.OfflineMaxSeconds // 3600, GameConfig.AutoThrowUnlockDistance) },
	}
	for i, sec in sections do
		local row = UI.panel(helpList, UDim2.new(1, -14, 0, 0), UDim2.new(), C.PanelLight)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = i
		UI.new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = row })
		UI.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
		UI.label(row, sec.title, UDim2.new(1, 0, 0, 24), UDim2.new(), sec.color, { TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 })
		UI.label(row, sec.text, UDim2.new(1, 0, 0, 0), UDim2.new(), C.Text, {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			TextScaled = false,
			TextSize = 17,
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
		})
	end
	self.frames.Help = help

	return self
end

function Panels:toggle(name: string?)
	if self.open == name then
		name = nil
	end
	if name == "Pets" and self.petsDirty and self.state then
		self:refreshPets(self.state)
	end
	if name == "Index" and self.state then
		self:refreshIndex(self.state)
	end
	for key, frame in self.frames do
		frame.Visible = key == name
		if key == name then
			UI.pop(frame)
		end
	end
	self.open = name
end

function Panels:isOpen(): boolean
	return self.open ~= nil
end

function Panels:refresh(state: any, full: boolean?)
	self.state = state
	-- Shop: owned / equip / price with progress toward the next purchase.
	local owned = state.ownedFoods or {}
	local coins = state.coins or 0
	local recommended: string? = nil
	for _, food in FoodConfig.Foods do
		if not owned[food.id] then
			recommended = food.id
			break
		end
	end
	for id, row in self.shopRows do
		local food = FoodConfig.get(id)
		if food then
			local button = row.button
			local showBar = false
			if state.equippedFood == id then
				button.Text = "EQUIPPED"
				button.BackgroundColor3 = C.PanelLight
			elseif owned[id] then
				button.Text = "Equip"
				button.BackgroundColor3 = C.Blue
			else
				button.Text = GameMath.formatNumber(food.price) .. " coins"
				local affordable = coins >= food.price
				button.BackgroundColor3 = if affordable then C.Green else C.Locked
				showBar = id == recommended
				if showBar then
					UI.setProgress(row.fill, coins / math.max(food.price, 1))
					row.barText.Text = if affordable then "Ready to buy!" else "NEXT: " .. math.floor(coins / food.price * 100) .. "%"
				end
			end
			row.bar.Visible = showBar
			local stroke = row.row:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if state.equippedFood == id then C.Gold elseif showBar then C.Green else C.Stroke
			end
		end
	end

	-- Settings
	local s = state.settings or {}
	local function onOff(key: string, v: boolean)
		local b = self.settingButtons[key]
		if b then
			b.Text = if v then "ON" else "OFF"
			b.BackgroundColor3 = if v then C.Green else C.Red
		end
	end
	if state.autoThrowUnlocked then
		onOff("AutoThrow", s.AutoThrow == true)
	else
		local b = self.settingButtons.AutoThrow
		b.Text = "Locked (" .. GameConfig.AutoThrowUnlockDistance .. "m)"
		b.BackgroundColor3 = C.Locked
	end
	onOff("ShowCutscenes", s.ShowCutscenes ~= false)
	onOff("KeepMutated", s.KeepMutated ~= false)
	onOff("ShowGuide", s.ShowGuide ~= false)
	local skipBtn = self.settingButtons.AutoSkipRarity
	skipBtn.Text = s.AutoSkipRarity or "Off"
	skipBtn.BackgroundColor3 = (GameConfig.RarityColors :: any)[s.AutoSkipRarity] or C.PanelLight
	self.autoSellButton.Text = "Auto-Sell: " .. (s.AutoSellRarity or "Off")

	-- The pet grid and index are the expensive parts: only rebuild them on full syncs
	-- (inventory changes), and only while visible.
	if full == false then
		return
	end
	if self.open == "Pets" then
		self:refreshPets(state)
	else
		self.petsDirty = true
	end
	if self.open == "Index" then
		self:refreshIndex(state)
	end
end

-- Pets grouped by species + material + size (the fusion key).
function Panels:refreshPets(state: any)
	self.petsDirty = false
	self.sortButton.Text = "Sort: " .. self.sort
	clearList(self.petList)
	local groups: { [string]: any } = {}
	local order = {}
	local equippedCount = 0
	for _, p in state.pets or {} do
		local key = GameMath.fuseKey(p)
		local g = groups[key]
		if not g then
			local _, rIdx = GameMath.overallRarity(p)
			g = { key = key, rec = p, count = 0, equipped = 0, income = GameMath.petIncome(p), rarityIndex = rIdx }
			groups[key] = g
			table.insert(order, g)
		end
		g.count += 1
		if p.equipped then
			g.equipped += 1
			equippedCount += 1
		end
	end
	local sort = self.sort
	table.sort(order, function(a, b)
		if sort == "Rarity" and a.rarityIndex ~= b.rarityIndex then
			return a.rarityIndex > b.rarityIndex
		elseif sort == "Count" and a.count ~= b.count then
			return a.count > b.count
		end
		if a.income ~= b.income then
			return a.income > b.income
		end
		return a.key < b.key
	end)
	local discovered = 0
	for _ in state.discovered or {} do
		discovered += 1
	end
	self.petCountLabel.Text = string.format("%d/%d pets  -  %d/%d on plot  -  Index %d/%d", #(state.pets or {}), state.maxPets or GameConfig.MaxPets, equippedCount, state.slots or GameConfig.PlotPedestals, discovered, #PetConfig.Pets)

	if #order == 0 then
		local empty = UI.label(self.petList, "No pets yet! Throw snacks at the Throw Line to catch some.", UDim2.fromOffset(600, 40), UDim2.new(), C.Muted)
		empty.LayoutOrder = 1
		return
	end

	for i, g in order do
		local rec = g.rec
		local pet = PetConfig.get(rec.species)
		local rarity = GameMath.overallRarity(rec)
		local rc = (GameConfig.RarityColors :: any)[rarity] or C.Text
		local cardColor = C.PanelLight
		local mat = MutationConfig.getMaterial(rec.material)
		if mat and mat.color then
			cardColor = C.PanelLight:Lerp(mat.color, 0.35)
		end
		local card = UI.panel(self.petList, UDim2.new(), UDim2.new(), cardColor)
		card.LayoutOrder = i
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = rc
		end
		if i <= MAX_VIEWPORTS and pet then
			UI.petViewport(card, rec, UDim2.fromOffset(70, 62), UDim2.new(0.5, -35, 0, 2))
		else
			local sw = UI.new("Frame", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, -23, 0, 10), BackgroundColor3 = if pet then pet.bodyColor else C.Muted, Parent = card })
			UI.corner(sw, 23)
		end
		if g.equipped > 0 then
			UI.label(card, "ON PLOT", UDim2.fromOffset(56, 16), UDim2.fromOffset(4, 4), C.Green)
		end
		UI.label(card, "x" .. g.count, UDim2.fromOffset(40, 20), UDim2.new(1, -44, 0, 4), C.Text)
		local mut = {}
		if rec.size ~= "Normal" then
			table.insert(mut, rec.size)
		end
		if rec.material ~= "Normal" then
			table.insert(mut, rec.material)
		end
		UI.label(card, if pet then pet.name else rec.species, UDim2.new(1, -10, 0, 20), UDim2.fromOffset(5, 64), rc)
		UI.label(card, if #mut > 0 then table.concat(mut, " ") else "Normal", UDim2.new(1, -10, 0, 16), UDim2.fromOffset(5, 85), C.Text)
		UI.label(card, rarity, UDim2.new(1, -10, 0, 15), UDim2.fromOffset(5, 102), C.Muted)
		UI.label(card, "+" .. GameMath.formatNumber(g.income) .. "/s each", UDim2.new(1, -10, 0, 16), UDim2.fromOffset(5, 118), C.Gold)
		local nextMat = MutationConfig.nextMaterial(rec.material)
		if nextMat then
			local can = g.count >= 3
			local fuse = UI.button(card, if can then "FUSE > " .. nextMat.id else string.format("%d/3 to fuse", g.count), if can then C.Purple else Color3.fromRGB(90, 80, 110), UDim2.new(1, -10, 0, 30), UDim2.fromOffset(5, 139))
			fuse.Activated:Connect(function()
				if can then
					self.run("FusePets", g.key)
				end
			end)
		else
			UI.label(card, "MAX MATERIAL", UDim2.new(1, -10, 0, 22), UDim2.fromOffset(5, 143), C.Pink)
		end
	end
end

-- Every species grouped by zone; undiscovered ones show a silhouette.
function Panels:refreshIndex(state: any)
	clearList(self.indexList)
	local discovered = state.discovered or {}
	local found = 0
	for _ in discovered do
		found += 1
	end
	self.indexHint.Text = string.format("Discovered %d / %d species. Each new species pays a coin bonus on its first catch!", found, #PetConfig.Pets)
	for order, zone in BiomeConfig.allCravingZones() do
		local list = PetConfig.forZone(zone)
		local section = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -14, 0, 150), LayoutOrder = order, Parent = self.indexList })
		local zoneFound = 0
		for _, pet in list do
			if discovered[pet.id] then
				zoneFound += 1
			end
		end
		local reached = state.zonesReached and state.zonesReached[zone]
		UI.label(section, string.format("%s  (%d/%d)%s", BiomeConfig.zoneName(zone), zoneFound, #list, if reached then "" else "  - not reached yet"), UDim2.new(1, 0, 0, 22), UDim2.new(), if reached then C.Gold else C.Muted, { TextXAlignment = Enum.TextXAlignment.Left })
		for i, pet in list do
			local known = discovered[pet.id] == true
			local rc = (GameConfig.RarityColors :: any)[pet.rarity] or C.Text
			local card = UI.panel(section, UDim2.fromOffset(122, 120), UDim2.fromOffset((i - 1) * 130, 26), if known then C.PanelLight else C.Dark)
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if known then rc else C.Stroke
			end
			UI.petViewport(card, { species = pet.id }, UDim2.fromOffset(80, 66), UDim2.new(0.5, -40, 0, 2), not known)
			UI.label(card, if known then pet.name else "???", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(4, 68), if known then C.Text else C.Muted)
			UI.label(card, pet.rarity, UDim2.new(1, -8, 0, 14), UDim2.fromOffset(4, 86), rc)
			UI.label(card, if known then (FoodConfig.CravingIcons[pet.craving] or "") .. " likes " .. pet.craving else "+" .. GameMath.formatNumber(Progression.discoveryReward(pet.id)) .. " on find", UDim2.new(1, -8, 0, 14), UDim2.fromOffset(4, 102), C.Muted)
		end
	end
end

return Panels
