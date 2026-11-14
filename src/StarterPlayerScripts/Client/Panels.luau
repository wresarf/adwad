--!strict
-- Modal panels: Snacks (earned upgrades), Eggs (earn-only Paw Tokens, odds shown), Pets,
-- Pet Index, Store (Robux passes, Gem packs and fixed Gem offers), Settings and Help.
-- Only one is open at a time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))
local EggConfig = require(Config:WaitForChild("EggConfig"))
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local UpgradeConfig = require(Config:WaitForChild("UpgradeConfig"))
local GameMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameMath"))
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))

local UI = require(script.Parent:WaitForChild("UI"))
local C = UI.Colors
local T = UI.Type

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

local function rarityColor(name: string?): Color3
	return (GameConfig.RarityColors :: any)[name or "Common"] or C.Muted
end

local function rarityTag(parent: Instance, rarity: string, pos: UDim2?, order: number?): TextLabel
	local rc = rarityColor(rarity)
	return UI.tag(parent, rarity, rc, UI.onColor(rc), pos, order)
end

local function percent(p: number): string
	if p == math.floor(p) then
		return string.format("%d%%", p)
	end
	return string.format("%.2f%%", p)
end

type Shell = { frame: Frame, body: ScrollingFrame, toolbar: Frame, subtitle: TextLabel, balance: TextLabel }

local PANEL_W, PANEL_H = 780, 540
local PETS_W = 920 -- the Pets panel is wider to fit the selected-pet sheet
local SHEET_W = 260

local function shell(root: Instance, title: string, subtitle: string, onClose: () -> (), width: number?): Shell
	local w = width or PANEL_W
	local frame = UI.surface(root, UDim2.fromOffset(w, PANEL_H), UDim2.new(0.5, -w / 2, 0.5, -PANEL_H / 2 + 8), C.Ivory, UI.Radius.l)
	frame.Visible = false
	frame.Active = true -- taps on the panel must not reach the Throw / Train buttons below
	frame.ZIndex = 10
	frame.Name = title
	UI.text(frame, title, UDim2.new(1, -200, 0, 40), UDim2.fromOffset(24, 14), { size = T.Display, font = UI.Display })
	local sub = UI.text(frame, subtitle, UDim2.new(1, -200, 0, 22), UDim2.fromOffset(24, 54), { size = T.Small, color = C.Muted, font = UI.FontMedium })
	local balance = UI.tag(frame, "", C.Paper, C.Charcoal, UDim2.new(1, -76, 0, 24))
	balance.AnchorPoint = Vector2.new(1, 0)
	balance.Size = UDim2.fromOffset(0, 32)
	balance.TextSize = T.Body
	balance.Visible = false
	local close = UI.button(frame, "✕", "ghost", UDim2.fromOffset(48, 48), UDim2.new(1, -64, 0, 16))
	close.Activated:Connect(onClose)
	local toolbar = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -48, 0, 52), Position = UDim2.fromOffset(24, 86), Parent = frame })
	local body = UI.new("ScrollingFrame", {
		Size = UDim2.new(1, -36, 1, -152),
		Position = UDim2.fromOffset(24, 142),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Muted,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = frame,
	})
	UI.padding(body, 2, 12, 12, 2)
	return { frame = frame, body = body, toolbar = toolbar, subtitle = sub, balance = balance }
end

local function clearList(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function row(parent: Instance, height: number, order: number): Frame
	local r = UI.surface(parent, UDim2.new(1, 0, 0, height), nil, C.Paper, UI.Radius.m)
	r.LayoutOrder = order
	return r
end

local function sectionTitle(parent: Instance, text: string, order: number): TextLabel
	return UI.text(parent, text, UDim2.new(1, 0, 0, 32), nil, { size = T.Label, font = UI.FontHeavy, order = order, alignY = Enum.TextYAlignment.Bottom })
end

function Panels.new(root: Instance, ctx: any, hud: any)
	local self = setmetatable({}, Panels) :: any
	self.ctx = ctx
	self.hud = hud
	self.frames = {}
	self.shells = {}
	self.open = nil
	self.state = nil
	self.sort = "Income"
	self.storeDirty = true

	local function close()
		self:toggle(nil)
	end

	-- Runs a remote; toasts failures always and successes unless `quiet`.
	local function run(name: string, ...: any): boolean
		local ok, msg = ctx.invoke(name, ...)
		hud:toast(msg, if ok then C.Leaf else C.Terracotta)
		return ok
	end
	local function runQuiet(name: string, ...: any): boolean
		local ok, msg = ctx.invoke(name, ...)
		if not ok then
			hud:toast(msg, C.Terracotta)
		end
		return ok
	end
	self.run = run

	local function add(key: string, sh: Shell)
		self.frames[key] = sh.frame
		self.shells[key] = sh
	end

	------------------------------------------------ snacks (earned upgrades)
	local shop = shell(root, "Snack Shop", "Better snacks fly further and add a little luck.", close)
	UI.list(shop.body, 8)
	-- Two tabs over one list: snacks and permanent coin upgrades.
	self.shopTab = "Snacks"
	self.shopTabs = {}
	self.upgradeRowsList = {}
	local function shopTab(name: string, x: number)
		local b = UI.button(shop.toolbar, name, "secondary", UDim2.fromOffset(140, 44), UDim2.fromOffset(x, 0), T.Body)
		b.Activated:Connect(function()
			self:setShopTab(name)
		end)
		self.shopTabs[name] = b
	end
	shopTab("Snacks", 0)
	shopTab("Upgrades", 148)
	self.shopHint = UI.text(shop.toolbar, "", UDim2.new(1, -310, 1, 0), UDim2.fromOffset(306, 0), { size = T.Small, color = C.Muted, font = UI.FontMedium })
	self.shopRows = {}
	self.snackRowsList = {}
	for i, food in FoodConfig.Foods do
		local r = row(shop.body, 84, i)
		table.insert(self.snackRowsList, r)
		local swatch = UI.new("Frame", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(14, 14), BackgroundColor3 = food.color, Parent = r })
		UI.corner(swatch, if food.shape == "Block" then 12 else 28)
		UI.text(swatch, FoodConfig.CravingIcons[food.craving] or "", UDim2.fromScale(1, 1), nil, { size = T.Title, align = Enum.TextXAlignment.Center })
		UI.text(r, food.name, UDim2.new(1, -330, 0, 26), UDim2.fromOffset(84, 10), { size = T.Label, font = UI.FontHeavy })
		UI.text(r, string.format("Craves %s · Power x%.2f · Luck x%.2f", food.craving, food.power, food.luck), UDim2.new(1, -330, 0, 20), UDim2.fromOffset(84, 36), { size = T.Small, color = C.Muted, font = UI.FontMedium })
		UI.text(r, food.description, UDim2.new(1, -330, 0, 20), UDim2.fromOffset(84, 56), { size = T.Caption, color = C.Muted, font = UI.FontMedium })
		local buy = UI.button(r, "", "primary", UDim2.fromOffset(200, 48), UDim2.new(1, -214, 0, 10))
		buy.Activated:Connect(function()
			run("BuyFood", food.id)
		end)
		local bar, fill, barText = UI.progressBar(r, UDim2.fromOffset(200, 14), UDim2.new(1, -214, 0, 62), C.Amber)
		barText.Visible = false
		self.shopRows[food.id] = { button = buy, fill = fill, bar = bar, barText = barText, row = r }
	end
	self.upgradeRows = {}
	for i, upgrade in UpgradeConfig.Upgrades do
		local r = row(shop.body, 84, 100 + i)
		r.Visible = false
		table.insert(self.upgradeRowsList, r)
		local badge = UI.new("TextLabel", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(14, 14), BackgroundColor3 = C.LeafSoft, Text = upgrade.icon, Font = UI.FontHeavy, TextSize = T.Title, TextColor3 = C.Charcoal, Parent = r })
		UI.corner(badge, UI.Radius.m)
		UI.text(r, upgrade.name, UDim2.new(1, -330, 0, 26), UDim2.fromOffset(84, 10), { size = T.Label, font = UI.FontHeavy })
		local levelText = UI.text(r, "", UDim2.new(1, -330, 0, 20), UDim2.fromOffset(84, 36), { size = T.Small, color = C.Muted, font = UI.FontMedium })
		UI.text(r, upgrade.effect .. " level", UDim2.new(1, -330, 0, 20), UDim2.fromOffset(84, 56), { size = T.Caption, color = C.Muted, font = UI.FontMedium })
		local buy = UI.button(r, "", "primary", UDim2.fromOffset(200, 48), UDim2.new(1, -214, 0, 10))
		buy.Activated:Connect(function()
			run("BuyUpgrade", upgrade.id)
		end)
		local pips = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 14), Position = UDim2.new(1, -214, 0, 62), Parent = r })
		UI.list(pips, 6, true, Enum.HorizontalAlignment.Center)
		local pipList = {}
		for lvl = 1, UpgradeConfig.maxLevel(upgrade) do
			local pip = UI.new("Frame", { Size = UDim2.fromOffset(28, 10), BackgroundColor3 = C.Sand, BorderSizePixel = 0, LayoutOrder = lvl, Parent = pips })
			UI.corner(pip, 5)
			pipList[lvl] = pip
		end
		self.upgradeRows[upgrade.id] = { button = buy, level = levelText, pips = pipList }
	end
	add("Shop", shop)

	------------------------------------------------ eggs (earn-only)
	local eggs = shell(root, "Safari Eggs", "Exclusive pets you can't catch by throwing.", close)
	UI.list(eggs.body, 12)
	UI.text(eggs.toolbar, string.format("Paw Tokens are earned by playing: +%d per quest, +%d per new zone, +%d per new species, +%d every %d catches. They can't be bought.", EggConfig.TokenRewards.Quest, EggConfig.TokenRewards.ZoneFirst, EggConfig.TokenRewards.NewSpecies, EggConfig.TokenRewards.CatchMilestone, EggConfig.CatchMilestoneEvery), UDim2.fromScale(1, 1), nil, { size = T.Small, color = C.Muted, font = UI.FontMedium })
	self.eggRows = {}
	for i, egg in EggConfig.Eggs do
		local card = UI.surface(eggs.body, UDim2.new(1, 0, 0, 0), nil, C.Paper, UI.Radius.m)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.LayoutOrder = i
		UI.padding(card, 14)
		UI.list(card, 8)
		local top = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 1, Parent = card })
		local shellArt = UI.new("Frame", { Size = UDim2.fromOffset(66, 84), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = egg.shell, Parent = top })
		UI.corner(shellArt, 33)
		UI.stroke(shellArt, C.Line, 2)
		for s, spot in { { 0.3, 0.3, 12 }, { 0.62, 0.48, 9 }, { 0.38, 0.66, 10 }, { 0.68, 0.22, 7 } } do
			local d = UI.new("Frame", { Size = UDim2.fromOffset(spot[3], spot[3]), Position = UDim2.fromScale(spot[1], spot[2]), BackgroundColor3 = egg.spots, Name = "Spot" .. s, Parent = shellArt })
			UI.corner(d, 99)
		end
		UI.text(top, egg.name, UDim2.new(1, -330, 0, 30), UDim2.fromOffset(88, 6), { size = T.Title, font = UI.Display })
		UI.text(top, egg.description, UDim2.new(1, -330, 0, 22), UDim2.fromOffset(88, 38), { size = T.Small, color = C.Muted, font = UI.FontMedium })
		UI.text(top, string.format("Costs %d Paw Tokens", egg.cost), UDim2.new(1, -330, 0, 22), UDim2.fromOffset(88, 62), { size = T.Small })
		local hatch = UI.button(top, "Hatch", "primary", UDim2.fromOffset(200, 50), UDim2.new(1, -204, 0, 4))
		hatch.Activated:Connect(function()
			runQuiet("HatchEgg", egg.id)
		end)
		local oddsToggle = UI.button(top, "Hide odds", "ghost", UDim2.fromOffset(200, 34), UDim2.new(1, -204, 0, 58), T.Small)
		local odds = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = card })
		UI.list(odds, 4)
		UI.text(odds, "Odds per hatch (fixed: luck, weather and combos never change them)", UDim2.new(1, 0, 0, 22), nil, { size = T.Caption, color = C.Muted, order = 0 })
		local ownedLabels = {}
		for j, entry in egg.entries do
			local pet = PetConfig.get(entry.species)
			local line = UI.new("Frame", { BackgroundColor3 = C.Ivory, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = j, Parent = odds })
			UI.corner(line, UI.Radius.s)
			if pet then
				-- A small 3D preview of exactly what can hatch.
				UI.petViewport(line, { species = entry.species }, UDim2.fromOffset(40, 40), UDim2.fromOffset(4, 2))
			end
			UI.text(line, if pet then pet.name else entry.species, UDim2.new(0.45, -52, 1, 0), UDim2.fromOffset(50, 0), { size = T.Small })
			if pet then
				rarityTag(line, pet.rarity, UDim2.new(0.45, 0, 0, 10))
				UI.text(line, "+" .. GameMath.formatNumber(pet.baseIncome) .. "/s", UDim2.new(0.18, 0, 1, 0), UDim2.new(0.62, 0, 0, 0), { size = T.Caption, color = C.Muted })
			end
			ownedLabels[entry.species] = UI.text(line, "", UDim2.new(0.12, 0, 1, 0), UDim2.new(0.74, 0, 0, 0), { size = T.Caption, color = C.LeafDark })
			UI.text(line, percent(entry.chance), UDim2.new(0.14, -12, 1, 0), UDim2.new(0.86, 0, 0, 0), { size = T.Small, font = UI.FontHeavy, align = Enum.TextXAlignment.Right })
		end
		oddsToggle.Activated:Connect(function()
			odds.Visible = not odds.Visible
			UI.setButton(oddsToggle, if odds.Visible then "Hide odds" else "View odds")
		end)
		self.eggRows[egg.id] = { button = hatch, owned = ownedLabels }
	end
	add("Eggs", eggs)

	------------------------------------------------ pets
	local pets = shell(root, "Your Pets", "", close, PETS_W)
	pets.body.Size = UDim2.new(1, -(36 + SHEET_W + 12), 1, -152)
	local function barButton(text: string, style: string, x: number, w: number, fn: () -> ()): TextButton
		local b = UI.button(pets.toolbar, text, style, UDim2.fromOffset(w, 46), UDim2.fromOffset(x, 0), T.Small)
		b.Activated:Connect(fn)
		return b
	end
	barButton("Equip best", "primary", 0, 130, function()
		run("EquipBest")
	end)
	barButton("Fuse all", "secondary", 138, 106, function()
		run("FusePets", "ALL")
	end)
	self.autoSellButton = barButton("Auto-sell: Off", "secondary", 252, 168, function()
		local st = self.state
		local current = if st and st.settings then st.settings.AutoSellRarity else "Off"
		run("AutoSell", cycle(AUTO_SELL_OPTIONS, current), false)
	end)
	barButton("Sell matching", "secondary", 428, 140, function()
		local st = self.state
		local current = if st and st.settings then st.settings.AutoSellRarity else "Off"
		if current == "Off" then
			hud:toast("Pick an auto-sell rarity first", C.Terracotta)
			return
		end
		run("AutoSell", current, true)
	end)
	self.sortButton = barButton("Sort: Income", "ghost", 576, 150, function()
		self.sort = cycle(SORTS, self.sort)
		if self.state then
			self:refreshPets(self.state)
		end
	end)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 196), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pets.body })
	self.petList = pets.body
	self.petCountLabel = pets.subtitle
	self.petCards = {}
	self.selectedKey = nil
	self.sellArmed = nil

	-- Selected-pet sheet (right column): details and the actions for one group.
	local sheet = UI.surface(pets.frame, UDim2.fromOffset(SHEET_W, PANEL_H - 158), UDim2.new(1, -(SHEET_W + 20), 0, 142), C.Paper, UI.Radius.m)
	UI.padding(sheet, 12)
	self.sheet = sheet
	self.sheetEmpty = UI.text(sheet, "Select a pet to see its details, place it on your plot, lock or sell it.", UDim2.fromScale(1, 1), nil, { size = T.Body, color = C.Muted, font = UI.FontMedium, align = Enum.TextXAlignment.Center })
	local sheetBody = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = sheet })
	self.sheetBody = sheetBody
	self.sheetView = UI.new("Frame", { BackgroundColor3 = C.Ivory, Size = UDim2.new(1, 0, 0, 110), Parent = sheetBody })
	UI.corner(self.sheetView, UI.Radius.s)
	self.sheetName = UI.text(sheetBody, "", UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 116), { size = T.Label, font = UI.FontHeavy, wrap = false })
	self.sheetTags = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 144), Parent = sheetBody })
	UI.list(self.sheetTags, 6, true)
	self.sheetInfo = UI.text(sheetBody, "", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 172), { size = T.Small, color = C.Muted, font = UI.FontMedium, alignY = Enum.TextYAlignment.Top })
	local function sheetButton(y: number, style: string, fn: () -> ()): TextButton
		local b = UI.button(sheetBody, "", style, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, y), T.Body)
		b.Activated:Connect(fn)
		return b
	end
	local function act(action: string)
		local key = self.selectedKey
		if key then
			run("ManagePet", action, key)
		end
	end
	self.sheetPlace = sheetButton(214, "primary", function()
		local g = self.selectedGroup
		if g then
			act(if g.equipped > 0 and g.equipped == g.count then "Unequip" else "Equip")
		end
	end)
	self.sheetFuse = sheetButton(260, "reward", function()
		local g = self.selectedGroup
		if g and g.count >= 3 and not g.locked and MutationConfig.nextMaterial(g.rec.material) then
			self.run("FusePets", g.key)
		end
	end)
	self.sheetLock = UI.button(sheetBody, "", "secondary", UDim2.new(0.5, -4, 0, 40), UDim2.fromOffset(0, 306), T.Small)
	self.sheetLock.Activated:Connect(function()
		local g = self.selectedGroup
		if g then
			act(if g.locked then "Unlock" else "Lock")
		end
	end)
	-- Selling asks twice: the first tap arms it, the second within 3 s sells one copy.
	self.sheetSell = UI.button(sheetBody, "", "secondary", UDim2.new(0.5, -4, 0, 40), UDim2.new(0.5, 4, 0, 306), T.Small)
	self.sheetSell.Activated:Connect(function()
		local g = self.selectedGroup
		if not g or g.locked then
			return
		end
		if self.sellArmed == g.key and os.clock() - (self.sellArmedAt or 0) < 3 then
			self.sellArmed = nil
			act("Sell")
		else
			self.sellArmed = g.key
			self.sellArmedAt = os.clock()
			self:renderSheet()
		end
	end)
	add("Pets", pets)

	------------------------------------------------ index
	local index = shell(root, "Pet Index", "", close)
	UI.list(index.body, 6)
	UI.text(index.toolbar, "Your first catch of each species pays a coin bonus and a Paw Token.", UDim2.fromScale(1, 1), nil, { size = T.Small, color = C.Muted, font = UI.FontMedium })
	self.indexList = index.body
	self.indexHint = index.subtitle
	add("Index", index)

	------------------------------------------------ store (Robux + Gems)
	local store = shell(root, "Store", "Optional extras. The whole game is playable without them.", close)
	UI.list(store.body, 8)
	UI.text(store.toolbar, "Gems only buy the exact items shown. They can't buy eggs, coins, tokens or luck.", UDim2.fromScale(1, 1), nil, { size = T.Small, color = C.Muted, font = UI.FontMedium })
	self.storeList = store.body
	add("Store", store)

	------------------------------------------------ settings
	local settings = shell(root, "Settings", "Saved with your progress.", close)
	UI.list(settings.body, 8)
	UI.text(settings.toolbar, "Cutscenes can always be skipped with Skip, Space or Enter.", UDim2.fromScale(1, 1), nil, { size = T.Small, color = C.Muted, font = UI.FontMedium })
	self.settingButtons = {}
	local function settingRow(order: number, key: string, title: string, desc: string, onClick: () -> ())
		local r = row(settings.body, 72, order)
		UI.text(r, title, UDim2.new(1, -230, 0, 26), UDim2.fromOffset(16, 10), { size = T.Label, font = UI.FontHeavy })
		UI.text(r, desc, UDim2.new(1, -230, 0, 22), UDim2.fromOffset(16, 38), { size = T.Small, color = C.Muted, font = UI.FontMedium })
		local b = UI.button(r, "", "secondary", UDim2.fromOffset(180, 48), UDim2.new(1, -196, 0, 10), T.Body)
		b.Activated:Connect(onClick)
		self.settingButtons[key] = b
	end
	local function current(key: string): any
		local st = self.state
		return if st and st.settings then st.settings[key] else nil
	end
	settingRow(1, "ReduceMotion", "Reduce motion", "Calmer camera, no shake or flashes, fewer particles.", function()
		run("ToggleSetting", "ReduceMotion", current("ReduceMotion") ~= true)
	end)
	settingRow(2, "AutoThrow", "Auto-throw", "Throws for you every few seconds (no Sweet bonus).", function()
		run("ToggleSetting", "AutoThrow", not current("AutoThrow"))
	end)
	settingRow(3, "ShowCutscenes", "Follow camera and cutscenes", "Watch your snack fly and the Space and Moon scenes.", function()
		run("ToggleSetting", "ShowCutscenes", not current("ShowCutscenes"))
	end)
	settingRow(4, "AutoSkipRarity", "Skip cutscenes below", "Space and Moon scenes for lower rarities are skipped.", function()
		run("ToggleSetting", "AutoSkipRarity", cycle(AUTO_SKIP_OPTIONS, current("AutoSkipRarity") or "Off"))
	end)
	settingRow(5, "KeepMutated", "Never auto-sell mutations", "Protects Gold+ materials and Huge+ sizes.", function()
		run("ToggleSetting", "KeepMutated", not current("KeepMutated"))
	end)
	settingRow(6, "ShowGuide", "Quest guide", "A marker that points to your current quest.", function()
		run("ToggleSetting", "ShowGuide", current("ShowGuide") == false)
	end)
	add("Settings", settings)

	------------------------------------------------ help
	local help = shell(root, "How to Play", "Everything in one place.", close)
	UI.list(help.body, 8)
	UI.text(help.toolbar, "Keys: E throw · Q train · F snacks · B eggs · G pets · N index · T travel · H help · R use stall", UDim2.fromScale(1, 1), nil, { size = T.Small, color = C.Muted, font = UI.FontMedium })
	local sections = {
		{ "Throw", "Stand at the Throw Line, hold to charge, release in the Sweet zone. The meter shows where the snack will land." },
		{ "Sweet zone", string.format("Releasing in the Sweet zone gives x%.2f distance and x%.2f mutation luck. Auto-throw never hits it.", GameConfig.SweetSpotDistanceMult, GameConfig.SweetSpotLuckMult) },
		{ "Biomes", "Sunny Meadow, Sizzle Dunes, Frostbite Peaks, Magma Fields, Toxic Swamp, Nuclear Wasteland. Wind and gravity stretch or shrink throws. Past 2,500 m is Space, past 3,600 m the Moon." },
		{ "Cravings and combos", "Each biome craves Berry, Meat, Spicy or Cosmic. Landing a match grows your streak: x1.5, x2, x3 and up to x10 mutation odds. A miss resets it." },
		{ "Mutations", "Materials: Normal, Gold, Diamond, Emerald, Ruby, Rainbow. Sizes: Normal, Huge, Colossal, Monstrous, Titanic, Cosmic, Infinite." },
		{ "Fusion and auto-sell", "Three identical pets fuse into the next material. Auto-sell turns low-rarity catches into coins. Mutations are protected by default." },
		{ "Weather", string.format("Every %d s a %d s event starts: Titan Storm (3x size luck), Feast Frenzy (2x craving bonus), Prism Aurora (4x material luck). Cravings change each time.", GameConfig.WeatherInterval, GameConfig.WeatherDuration) },
		{ "Safari Eggs", "Spend earned Paw Tokens at the Hatchery for pets you can't catch. Every egg lists its exact odds." },
		{ "Progress", string.format("Quests guide you and pay coins plus a Paw Token. Your plot keeps earning %d%% while you're away (up to %d h). Auto-throw unlocks at %d m.", math.floor(GameConfig.OfflineRate * 100), GameConfig.OfflineMaxSeconds // 3600, GameConfig.AutoThrowUnlockDistance) },
	}
	for i, sec in sections do
		local r = UI.surface(help.body, UDim2.new(1, 0, 0, 0), nil, C.Paper, UI.Radius.m)
		r.AutomaticSize = Enum.AutomaticSize.Y
		r.LayoutOrder = i
		UI.padding(r, 10, 16, 12, 16)
		UI.list(r, 2)
		UI.text(r, sec[1], UDim2.new(1, 0, 0, 26), nil, { size = T.Label, font = UI.FontHeavy, order = 1 })
		UI.text(r, sec[2], UDim2.new(1, 0, 0, 0), nil, { size = T.Body, font = UI.FontMedium, color = C.Muted, auto = Enum.AutomaticSize.Y, order = 2 })
	end
	add("Help", help)

	return self
end

function Panels:toggle(name: string?)
	if self.open == name then
		name = nil
	end
	if name and not self.frames[name] then
		return
	end
	if name == "Pets" and self.petsDirty and self.state then
		self:refreshPets(self.state)
	end
	if name == "Index" and self.state then
		self:refreshIndex(self.state)
	end
	if name == "Store" and self.state then
		self:refreshStore(self.state)
	end
	for key, frame in self.frames do
		frame.Visible = key == name
		if key == name then
			UI.pop(frame, 0.04)
		end
	end
	self.open = name
end

function Panels:isOpen(): boolean
	return self.open ~= nil
end

function Panels:setShopTab(name: string)
	self.shopTab = name
	for key, b in self.shopTabs do
		UI.setButton(b, nil, if key == name then "primary" else "secondary")
	end
	for _, r in self.snackRowsList do
		r.Visible = name == "Snacks"
	end
	for _, r in self.upgradeRowsList do
		r.Visible = name == "Upgrades"
	end
	self.shopHint.Text = if name == "Snacks"
		then "Match a biome's craving to grow your combo. Snacks are yours to keep."
		else "Permanent upgrades, paid with coins you earn."
	local body = self.shells.Shop.body
	body.CanvasPosition = Vector2.new()
end

function Panels:refresh(state: any, full: boolean?)
	self.state = state
	local coins = state.coins or 0
	self.shells.Shop.balance.Visible = true
	self.shells.Shop.balance.Text = "🪙 " .. GameMath.formatNumber(coins)
	self.shells.Eggs.balance.Visible = true
	self.shells.Eggs.balance.Text = "🐾 " .. GameMath.formatNumber(state.pawTokens or 0)
	self.shells.Store.balance.Visible = true
	self.shells.Store.balance.Text = "💎 " .. GameMath.formatNumber(state.gems or 0)

	-- Snacks: owned / equip / price, with progress toward the next one.
	local owned = state.ownedFoods or {}
	local nextFood: string? = nil
	for _, food in FoodConfig.Foods do
		if not owned[food.id] then
			nextFood = food.id
			break
		end
	end
	for id, r in self.shopRows do
		local food = FoodConfig.get(id)
		if food then
			local showBar = false
			if state.equippedFood == id then
				UI.setButton(r.button, "Equipped ✓", "ghost")
			elseif owned[id] then
				UI.setButton(r.button, "Equip", "secondary")
			else
				local affordable = coins >= food.price
				UI.setButton(r.button, (if affordable then "Buy · " else "🔒 ") .. GameMath.formatNumber(food.price), if affordable then "primary" else "disabled")
				r.button.Active = true -- still tappable: the server explains what's missing
				showBar = id == nextFood and not affordable
				if showBar then
					UI.setProgress(r.fill, coins / math.max(food.price, 1))
				end
			end
			r.bar.Visible = showBar
		end
	end
	if not self.shopTab or self.shopHint.Text == "" then
		self:setShopTab(self.shopTab or "Snacks")
	end
	local levels = state.upgrades or {}
	for id, r in self.upgradeRows do
		local upgrade = UpgradeConfig.get(id)
		if upgrade then
			local level = levels[id] or 0
			local maxLevel = UpgradeConfig.maxLevel(upgrade)
			r.level.Text = string.format("Level %d of %d", level, maxLevel)
			for i, pip in r.pips do
				pip.BackgroundColor3 = if i <= level then C.Leaf else C.Sand
			end
			local price = UpgradeConfig.nextPrice(upgrade, level)
			if not price then
				UI.setButton(r.button, "Maxed ✓", "ghost")
			elseif coins >= price then
				UI.setButton(r.button, "Buy · " .. GameMath.formatNumber(price), "primary")
			else
				UI.setButton(r.button, "Need " .. GameMath.formatNumber(price - coins) .. " more", "disabled")
			end
			r.button.Active = true
		end
	end

	-- Eggs
	local discovered = state.discovered or {}
	for eggId, r in self.eggRows do
		local egg = EggConfig.get(eggId)
		if egg then
			local can = (state.pawTokens or 0) >= egg.cost
			UI.setButton(r.button, if can then "Hatch · " .. egg.cost .. " 🐾" else string.format("Need %d 🐾", egg.cost - (state.pawTokens or 0)), if can then "primary" else "disabled")
			r.button.Active = true
			for species, label in r.owned do
				label.Text = if discovered[species] then "Owned ✓" else ""
			end
		end
	end

	-- Settings
	local s = state.settings or {}
	local function onOff(key: string, v: boolean)
		local b = self.settingButtons[key]
		if b then
			UI.setButton(b, if v then "On" else "Off", if v then "primary" else "secondary")
		end
	end
	if state.autoThrowUnlocked then
		onOff("AutoThrow", s.AutoThrow == true)
	else
		UI.setButton(self.settingButtons.AutoThrow, string.format("🔒 %d m", GameConfig.AutoThrowUnlockDistance), "disabled")
		self.settingButtons.AutoThrow.Active = true
	end
	onOff("ReduceMotion", s.ReduceMotion == true)
	onOff("ShowCutscenes", s.ShowCutscenes ~= false)
	onOff("KeepMutated", s.KeepMutated ~= false)
	onOff("ShowGuide", s.ShowGuide ~= false)
	UI.setButton(self.settingButtons.AutoSkipRarity, s.AutoSkipRarity or "Off", "secondary")
	UI.setButton(self.autoSellButton, "Auto-sell: " .. (s.AutoSellRarity or "Off"))

	-- Grids are the expensive parts: only rebuild on full syncs, and only while visible.
	if full == false then
		if self.open == "Store" and (self.storeGems ~= state.gems or self.storePending ~= (state.receiptPending == true)) then
			self:refreshStore(state)
		end
		return
	end
	self.storeDirty = true
	if self.open == "Pets" then
		self:refreshPets(state)
	else
		self.petsDirty = true
	end
	if self.open == "Index" then
		self:refreshIndex(state)
	end
	if self.open == "Store" then
		self:refreshStore(state)
	end
end

------------------------------------------------------------------ pets

-- Pets grouped by species + material + size (the fusion key).
function Panels:refreshPets(state: any)
	self.petsDirty = false
	UI.setButton(self.sortButton, "Sort: " .. self.sort)
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
	for _, g in order do
		local all = true
		for _, p in state.pets or {} do
			if GameMath.fuseKey(p) == g.key and not p.locked then
				all = false
				break
			end
		end
		g.locked = all
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
	self.petCountLabel.Text = string.format("%d / %d in backpack · %d / %d on your plot", #(state.pets or {}), state.maxPets or GameConfig.MaxPets, equippedCount, state.slots or GameConfig.PlotPedestals)

	self.petCards = {}
	self.groups = groups
	local selected: string? = self.selectedKey
	if selected and not groups[selected] then
		selected = nil
		self.selectedKey = nil
	end
	self.selectedGroup = if selected then groups[selected] else nil
	self:renderSheet()

	if #order == 0 then
		local empty = UI.text(self.petList, "No pets yet. Throw a snack at the Throw Line to meet your first one.", UDim2.fromOffset(520, 60), nil, { size = T.Body, color = C.Muted })
		empty.LayoutOrder = 1
		return
	end

	for i, g in order do
		local rec = g.rec
		local pet = PetConfig.get(rec.species)
		local rarity = GameMath.overallRarity(rec)
		local card = UI.surface(self.petList, UDim2.new(), nil, C.Paper, UI.Radius.m)
		card.LayoutOrder = i
		self.petCards[g.key] = card
		local mat = MutationConfig.getMaterial(rec.material)
		local art = UI.new("Frame", { Size = UDim2.new(1, -16, 0, 76), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = if mat and mat.color then C.Ivory:Lerp(mat.color, 0.25) else C.Ivory, Parent = card })
		UI.corner(art, UI.Radius.s)
		if i <= MAX_VIEWPORTS and pet then
			UI.petViewport(art, rec, UDim2.fromScale(1, 1), UDim2.new())
		else
			local sw = UI.new("Frame", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, -23, 0, 15), BackgroundColor3 = if pet then pet.bodyColor else C.Muted, Parent = art })
			UI.corner(sw, 23)
		end
		UI.tag(art, "x" .. g.count, C.Paper, C.Charcoal, UDim2.new(1, -4, 0, 4)).AnchorPoint = Vector2.new(1, 0)
		if g.equipped > 0 then
			UI.tag(art, if g.equipped < g.count then string.format("%d on plot", g.equipped) else "On plot", C.LeafSoft, C.LeafDark, UDim2.fromOffset(4, 4))
		end
		if g.locked then
			UI.tag(art, "🔒", C.Paper, C.Charcoal, UDim2.new(1, -4, 1, -4)).AnchorPoint = Vector2.new(1, 1)
		end
		-- Tapping the card selects it (the fuse button below keeps its own action).
		local pick = UI.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, -44), ZIndex = 4, Parent = card })
		pick.Activated:Connect(function()
			self:select(g.key)
		end)
		local mut = {}
		if rec.size ~= "Normal" then
			table.insert(mut, rec.size)
		end
		if rec.material ~= "Normal" then
			table.insert(mut, rec.material)
		end
		UI.text(card, if pet then pet.name else rec.species, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 88), { size = T.Small, font = UI.FontHeavy, wrap = false })
		rarityTag(card, rarity, UDim2.fromOffset(8, 112))
		UI.text(card, if #mut > 0 then table.concat(mut, " ") else "", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 136), { size = T.Caption, color = C.Muted })
		UI.text(card, "+" .. GameMath.formatNumber(g.income) .. "/s", UDim2.new(0.5, -8, 0, 24), UDim2.new(0.5, 0, 0, 110), { size = T.Small, color = C.AmberDark, align = Enum.TextXAlignment.Right })
		local nextMat = MutationConfig.nextMaterial(rec.material)
		if nextMat then
			local can = g.count >= 3 and not g.locked
			local fuse = UI.button(card, if g.locked then "Locked" elseif can then "Fuse → " .. nextMat.id else string.format("%d / 3 to fuse", g.count), if can then "reward" else "disabled", UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 1, -40), T.Caption)
			fuse.Activated:Connect(function()
				if can then
					self.run("FusePets", g.key)
				end
			end)
		else
			UI.text(card, "Top material", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 1, -38), { size = T.Caption, color = C.Muted, align = Enum.TextXAlignment.Center })
		end
	end
	self:highlightSelection()
end

function Panels:select(key: string?)
	if self.selectedKey ~= key then
		self.sellArmed = nil
	end
	self.selectedKey = key
	self.selectedGroup = if key and self.groups then self.groups[key] else nil
	self:highlightSelection()
	self:renderSheet()
end

-- Selected card: thicker leaf-green edge plus the sheet on the right (not colour alone:
-- the sheet names the pet).
function Panels:highlightSelection()
	for key, card in self.petCards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			local selected = key == self.selectedKey
			stroke.Color = if selected then C.Leaf else C.Line
			stroke.Thickness = if selected then 3 else 1
			stroke.Transparency = if selected then 0 else 0.2
		end
	end
end

function Panels:renderSheet()
	local g: any = self.selectedGroup
	self.sheetEmpty.Visible = g == nil
	self.sheetBody.Visible = g ~= nil
	if not g then
		return
	end
	local rec: any = g.rec
	local pet = PetConfig.get(rec.species)
	if self.sheetViewKey ~= g.key then
		self.sheetViewKey = g.key
		for _, child in self.sheetView:GetChildren() do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end
		if pet then
			UI.petViewport(self.sheetView, rec, UDim2.fromScale(1, 1), UDim2.new())
		end
	end
	local mut = {}
	if rec.size ~= "Normal" then
		table.insert(mut, rec.size)
	end
	if rec.material ~= "Normal" then
		table.insert(mut, rec.material)
	end
	self.sheetName.Text = (if #mut > 0 then table.concat(mut, " ") .. " " else "") .. (if pet then pet.name else rec.species)
	clearList(self.sheetTags)
	rarityTag(self.sheetTags, (GameMath.overallRarity(rec)), nil, 1)
	UI.tag(self.sheetTags, "x" .. g.count, C.Ivory, C.Charcoal, nil, 2)
	if g.locked then
		UI.tag(self.sheetTags, "🔒 Locked", C.Ivory, C.Charcoal, nil, 3)
	end
	self.sheetInfo.Text = string.format("+%s/s each · %d on plot\nSells for %s", GameMath.formatNumber(g.income), g.equipped, GameMath.formatNumber(GameMath.sellValue(rec)))
	local allOut = g.equipped > 0 and g.equipped == g.count
	UI.setButton(self.sheetPlace, if allOut then "Back to backpack" else "Place on plot", if allOut then "secondary" else "primary")
	local nextMat = MutationConfig.nextMaterial(rec.material)
	if not nextMat then
		UI.setButton(self.sheetFuse, "Top material", "disabled")
	elseif g.locked then
		UI.setButton(self.sheetFuse, "Unlock to fuse", "disabled")
	elseif g.count >= 3 then
		UI.setButton(self.sheetFuse, "Fuse 3 → " .. nextMat.id, "reward")
	else
		UI.setButton(self.sheetFuse, string.format("Fuse: %d / 3", g.count), "disabled")
	end
	UI.setButton(self.sheetLock, if g.locked then "Unlock" else "🔒 Lock", "secondary")
	if g.locked then
		UI.setButton(self.sheetSell, "Locked", "disabled")
	elseif self.sellArmed == g.key then
		UI.setButton(self.sheetSell, "Tap to confirm", "danger")
	else
		UI.setButton(self.sheetSell, "Sell 1", "secondary")
	end
end

------------------------------------------------------------------ index

-- Every species grouped by zone; undiscovered ones show a silhouette.
function Panels:refreshIndex(state: any)
	clearList(self.indexList)
	local discovered = state.discovered or {}
	local found = 0
	for _ in discovered do
		found += 1
	end
	self.indexHint.Text = string.format("%d of %d species discovered", found, #PetConfig.Pets)
	local zones = BiomeConfig.allCravingZones()
	table.insert(zones, PetConfig.EggZone)
	local order = 0
	for _, zone in zones do
		local list = PetConfig.forZone(zone)
		local zoneFound = 0
		for _, pet in list do
			if discovered[pet.id] then
				zoneFound += 1
			end
		end
		local isEgg = zone == PetConfig.EggZone
		local reached = isEgg or (state.zonesReached and state.zonesReached[zone])
		order += 1
		sectionTitle(self.indexList, string.format("%s  %d / %d%s", if isEgg then "Safari Eggs" else BiomeConfig.zoneName(zone), zoneFound, #list, if reached then "" else "  · not reached yet"), order)
		order += 1
		local strip = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = self.indexList })
		UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(132, 150), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = strip })
		for i, pet in list do
			local known = discovered[pet.id] == true
			local card = UI.surface(strip, UDim2.new(), nil, if known then C.Paper else C.Sand, UI.Radius.m)
			card.LayoutOrder = i
			UI.petViewport(card, { species = pet.id }, UDim2.new(1, -16, 0, 70), UDim2.fromOffset(8, 6), not known)
			UI.text(card, if known then pet.name else "???", UDim2.new(1, -12, 0, 20), UDim2.fromOffset(6, 78), { size = T.Small, font = UI.FontHeavy, align = Enum.TextXAlignment.Center, color = if known then C.Charcoal else C.Muted, wrap = false })
			local tag = rarityTag(card, pet.rarity, UDim2.new(0.5, 0, 0, 100))
			tag.AnchorPoint = Vector2.new(0.5, 0)
			local foot = if known then (FoodConfig.CravingIcons[pet.craving] or "") .. " likes " .. pet.craving elseif isEgg then "From an egg" else "+" .. GameMath.formatNumber(Progression.discoveryReward(pet.id)) .. " on first catch"
			UI.text(card, foot, UDim2.new(1, -12, 0, 18), UDim2.fromOffset(6, 126), { size = T.Caption, color = C.Muted, align = Enum.TextXAlignment.Center, wrap = false })
		end
	end
end

------------------------------------------------------------------ store

-- Button text + style for a Robux listing. States: owned, priced, loading, pending
-- (a Gem purchase is being saved), off sale, error, unset.
local function priceText(listing: any, owned: boolean?, pending: boolean?): (string, string)
	if owned then
		return "Owned ✓", "ghost"
	end
	if listing.status == "ok" and type(listing.price) == "number" then
		if pending then
			return "Finishing…", "disabled"
		end
		return "R$ " .. GameMath.formatNumber(listing.price), "reward"
	elseif listing.status == "loading" then
		return "Checking price…", "disabled"
	elseif listing.status == "offsale" then
		return "Not on sale", "disabled"
	elseif listing.status == "error" then
		return "Try again later", "disabled"
	end
	return "Not available yet", "disabled"
end
Panels._priceText = priceText -- exposed for the test-suite

function Panels:refreshStore(state: any)
	self.storeDirty = false
	self.storeGems = state.gems
	self.storePending = state.receiptPending == true
	local list = self.storeList
	clearList(list)
	local catalog = state.store or { passes = {}, products = {} }
	local passes = state.passes or {}
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function item(title: string, desc: string, icon: string, button: string, style: string, onClick: (() -> ())?)
		local r = row(list, 76, nextOrder())
		local badge = UI.new("TextLabel", { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(12, 12), BackgroundColor3 = C.AmberSoft, Text = icon, Font = UI.FontHeavy, TextSize = T.Title, TextColor3 = C.Charcoal, Parent = r })
		UI.corner(badge, UI.Radius.m)
		UI.text(r, title, UDim2.new(1, -300, 0, 26), UDim2.fromOffset(78, 10), { size = T.Label, font = UI.FontHeavy })
		UI.text(r, desc, UDim2.new(1, -300, 0, 22), UDim2.fromOffset(78, 38), { size = T.Small, color = C.Muted, font = UI.FontMedium })
		local b = UI.button(r, button, style, UDim2.fromOffset(196, 48), UDim2.new(1, -210, 0, 12), T.Body)
		if onClick and style ~= "disabled" and style ~= "ghost" then
			b.Activated:Connect(onClick)
		else
			b.Active = false
		end
	end

	sectionTitle(list, "Passes", nextOrder())
	for _, listing in catalog.passes or {} do
		local text, style = priceText(listing, passes[listing.key])
		item(listing.name, listing.description, listing.icon or "★", text, style, function()
			self.run("StorePurchase", "Pass", listing.key)
		end)
	end

	sectionTitle(list, "Gems", nextOrder())
	for _, listing in catalog.products or {} do
		local text, style = priceText(listing, false, state.receiptPending == true)
		item(listing.name, listing.description, "💎", text, style, function()
			self.run("StorePurchase", "Product", listing.key)
		end)
	end

	sectionTitle(list, "Spend Gems", nextOrder())
	local gems = state.gems or 0
	for _, offer in MonetizationConfig.GemOffers do
		local can = gems >= offer.gems and state.receiptPending ~= true
		local label = if can then string.format("Buy · 💎 %d", offer.gems) elseif gems < offer.gems then string.format("Need %d more 💎", offer.gems - gems) else "Finishing…"
		item(offer.name, offer.description, if offer.grant.kind == "pet" then "🐾" else "⏱", label, if can then "primary" else "disabled", function()
			self.run("StorePurchase", "Offer", offer.key)
		end)
	end
	local note = UI.text(list, "Robux prices come from Roblox. Offers that aren't set up yet stay unavailable and never open a purchase.", UDim2.new(1, 0, 0, 0), nil, { size = T.Caption, color = C.Muted, font = UI.FontMedium, auto = Enum.AutomaticSize.Y })
	note.LayoutOrder = nextOrder()
end

return Panels
