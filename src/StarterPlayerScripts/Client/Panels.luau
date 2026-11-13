--!strict
-- Modal panels: Food Shop, Pets & Fuse, Settings. Only one is open at a time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local FoodConfig = require(Config:WaitForChild("FoodConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local MutationConfig = require(Config:WaitForChild("MutationConfig"))
local GameMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameMath"))

local UI = require(script.Parent:WaitForChild("UI"))
local C = UI.Colors

local Panels = {}
Panels.__index = Panels

local AUTO_SELL_OPTIONS = { "Off", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local AUTO_SKIP_OPTIONS = { "Off", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

local function cycle(list: { string }, current: string): string
	local i = table.find(list, current) or 0
	return list[(i % #list) + 1]
end

local function shell(root: Instance, title: string, color: Color3, onClose: () -> ()): (Frame, ScrollingFrame, Frame)
	local frame = UI.panel(root, UDim2.fromOffset(680, 470), UDim2.new(0.5, -340, 0.5, -225), C.Panel)
	frame.Visible = false
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
		Parent = frame,
	})
	return frame, list, toolbar
end

function Panels.new(root: Instance, ctx: any, hud: any)
	local self = setmetatable({}, Panels) :: any
	self.ctx = ctx
	self.hud = hud
	self.frames = {}
	self.open = nil
	self.state = nil

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
	UI.label(shopBar, "Better food flies further. Match biome cravings for combos!", UDim2.fromScale(1, 1), UDim2.new(), C.Muted)
	UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = shopList })
	self.shopRows = {}
	for i, food in FoodConfig.Foods do
		local row = UI.panel(shopList, UDim2.new(1, -12, 0, 70), UDim2.new(), C.PanelLight)
		row.LayoutOrder = i
		local swatch = UI.new("Frame", { Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = food.color, Parent = row })
		UI.corner(swatch, if food.shape == "Block" then 10 else 27)
		UI.stroke(swatch)
		UI.label(swatch, FoodConfig.CravingIcons[food.craving] or "", UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15))
		UI.label(row, food.name, UDim2.new(0, 260, 0, 28), UDim2.fromOffset(72, 6), food.color:Lerp(Color3.new(1, 1, 1), 0.4), { TextXAlignment = Enum.TextXAlignment.Left })
		UI.label(row, string.format("%s craving  -  x%.2f power  -  x%.2f luck", food.craving, food.power, food.luck), UDim2.new(0, 330, 0, 20), UDim2.fromOffset(72, 38), C.Muted, { TextXAlignment = Enum.TextXAlignment.Left })
		local buy = UI.button(row, "", C.Green, UDim2.fromOffset(170, 50), UDim2.new(1, -180, 0, 10))
		buy.Activated:Connect(function()
			run("BuyFood", food.id)
		end)
		self.shopRows[food.id] = buy
	end
	self.frames.Shop = shop

	------------------------------------------------ pets
	local pets, petList, petBar = shell(root, "PETS & FUSE", C.Pink, close)
	local equipBest = UI.button(petBar, "Equip Best", C.Green, UDim2.fromOffset(130, 42), UDim2.new())
	equipBest.Activated:Connect(function()
		run("EquipBest")
	end)
	local fuseAll = UI.button(petBar, "Fuse All", C.Purple, UDim2.fromOffset(120, 42), UDim2.fromOffset(138, 0))
	fuseAll.Activated:Connect(function()
		run("FusePets", "ALL")
	end)
	local autoSell = UI.button(petBar, "Auto-Sell: Off", C.Orange, UDim2.fromOffset(190, 42), UDim2.fromOffset(266, 0))
	autoSell.Activated:Connect(function()
		local st = self.state
		local current = if st and st.settings then st.settings.AutoSellRarity else "Off"
		run("AutoSell", cycle(AUTO_SELL_OPTIONS, current), false)
	end)
	local sellNow = UI.button(petBar, "Sell Matching", C.Red, UDim2.fromOffset(150, 42), UDim2.fromOffset(464, 0))
	sellNow.Activated:Connect(function()
		local st = self.state
		local current = if st and st.settings then st.settings.AutoSellRarity else "Off"
		if current == "Off" then
			hud:toast("Pick an Auto-Sell rarity first", C.Red)
			return
		end
		run("AutoSell", current, true)
	end)
	self.autoSellButton = autoSell
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(200, 132), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = petList })
	self.petList = petList
	self.petCountLabel = UI.label(pets, "", UDim2.fromOffset(300, 22), UDim2.new(0, 330, 0, 16), C.Text, { ZIndex = 12 })
	self.frames.Pets = pets

	------------------------------------------------ settings
	local settings, setList, setBar = shell(root, "SETTINGS", C.Blue, close)
	UI.label(setBar, "Cutscenes are always skippable with SKIP or Space.", UDim2.fromScale(1, 1), UDim2.new(), C.Muted)
	UI.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = setList })
	self.settingButtons = {}
	local function settingRow(order: number, key: string, title: string, desc: string, onClick: () -> ())
		local row = UI.panel(setList, UDim2.new(1, -12, 0, 66), UDim2.new(), C.PanelLight)
		row.LayoutOrder = order
		UI.label(row, title, UDim2.new(0, 400, 0, 28), UDim2.fromOffset(12, 6), C.Text, { TextXAlignment = Enum.TextXAlignment.Left })
		UI.label(row, desc, UDim2.new(0, 420, 0, 20), UDim2.fromOffset(12, 38), C.Muted, { TextXAlignment = Enum.TextXAlignment.Left })
		local b = UI.button(row, "", C.Blue, UDim2.fromOffset(170, 48), UDim2.new(1, -180, 0, 9))
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
	settingRow(2, "ShowCutscenes", "Camera Effects & Cutscenes", "Follow your food and watch space / moon cutscenes.", function()
		run("ToggleSetting", "ShowCutscenes", not current("ShowCutscenes"))
	end)
	settingRow(3, "AutoSkipRarity", "Auto-Skip Cutscenes Below", "Space/moon cutscenes for catches below this rarity are skipped.", function()
		run("ToggleSetting", "AutoSkipRarity", cycle(AUTO_SKIP_OPTIONS, current("AutoSkipRarity") or "Off"))
	end)
	settingRow(4, "KeepMutated", "Never Auto-Sell Mutations", "Protects Gold+ materials and Huge+ sizes from auto-sell.", function()
		run("ToggleSetting", "KeepMutated", not current("KeepMutated"))
	end)
	self.frames.Settings = settings

	return self
end

function Panels:toggle(name: string?)
	if self.open == name then
		name = nil
	end
	if name == "Pets" and self.petsDirty and self.state then
		self:refreshPets(self.state)
	end
	for key, frame in self.frames do
		frame.Visible = key == name
		if key == name then
			UI.pop(frame)
		end
	end
	self.open = name
end

function Panels:refresh(state: any)
	self.state = state
	-- Shop
	local owned = state.ownedFoods or {}
	for id, button in self.shopRows do
		local food = FoodConfig.get(id)
		if food then
			if state.equippedFood == id then
				button.Text = "EQUIPPED"
				button.BackgroundColor3 = C.PanelLight
			elseif owned[id] then
				button.Text = "Equip"
				button.BackgroundColor3 = C.Blue
			else
				button.Text = GameMath.formatNumber(food.price) .. " coins"
				button.BackgroundColor3 = if (state.coins or 0) >= food.price then C.Green else Color3.fromRGB(110, 90, 100)
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
		b.BackgroundColor3 = Color3.fromRGB(110, 90, 100)
	end
	onOff("ShowCutscenes", s.ShowCutscenes ~= false)
	onOff("KeepMutated", s.KeepMutated ~= false)
	local skipBtn = self.settingButtons.AutoSkipRarity
	skipBtn.Text = s.AutoSkipRarity or "Off"
	skipBtn.BackgroundColor3 = (GameConfig.RarityColors :: any)[s.AutoSkipRarity] or C.PanelLight
	self.autoSellButton.Text = "Auto-Sell: " .. (s.AutoSellRarity or "Off")

	-- The pet grid is the expensive part: only rebuild it while visible.
	if self.open == "Pets" then
		self:refreshPets(state)
	else
		self.petsDirty = true
	end
end

-- Pets grouped by species + material + size (the fusion key).
function Panels:refreshPets(state: any)
	self.petsDirty = false
	for _, child in self.petList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local groups: { [string]: any } = {}
	local order = {}
	local equippedCount = 0
	for _, p in state.pets or {} do
		local key = GameMath.fuseKey(p)
		local g = groups[key]
		if not g then
			g = { key = key, rec = p, count = 0, equipped = 0 }
			groups[key] = g
			table.insert(order, g)
		end
		g.count += 1
		if p.equipped then
			g.equipped += 1
			equippedCount += 1
		end
	end
	table.sort(order, function(a, b)
		return GameMath.petIncome(a.rec) > GameMath.petIncome(b.rec)
	end)
	local discovered = 0
	for _ in state.discovered or {} do
		discovered += 1
	end
	self.petCountLabel.Text = string.format("%d/%d pets  -  %d/%d equipped  -  Index %d/%d", #(state.pets or {}), state.maxPets or GameConfig.MaxPets, equippedCount, state.slots or GameConfig.PlotPedestals, discovered, #PetConfig.Pets)

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
		local mut = {}
		if rec.size ~= "Normal" then
			table.insert(mut, rec.size)
		end
		if rec.material ~= "Normal" then
			table.insert(mut, rec.material)
		end
		UI.label(card, if pet then pet.name else rec.species, UDim2.new(1, -12, 0, 24), UDim2.fromOffset(6, 4), rc)
		UI.label(card, if #mut > 0 then table.concat(mut, " ") else "Normal", UDim2.new(1, -12, 0, 18), UDim2.fromOffset(6, 28), C.Text)
		UI.label(card, string.format("%s  -  x%d%s", rarity, g.count, if g.equipped > 0 then string.format(" (%d on plot)", g.equipped) else ""), UDim2.new(1, -12, 0, 18), UDim2.fromOffset(6, 48), C.Muted)
		UI.label(card, "+" .. GameMath.formatNumber(GameMath.petIncome(rec)) .. "/s each", UDim2.new(1, -12, 0, 18), UDim2.fromOffset(6, 68), C.Gold)
		local nextMat = MutationConfig.nextMaterial(rec.material)
		if nextMat then
			local can = g.count >= 3
			local fuse = UI.button(card, if can then "FUSE -> " .. nextMat.id else string.format("%d/3 to fuse", g.count), if can then C.Purple else Color3.fromRGB(90, 80, 110), UDim2.new(1, -12, 0, 32), UDim2.fromOffset(6, 92))
			fuse.Activated:Connect(function()
				if can then
					self.run("FusePets", g.key)
				end
			end)
		else
			UI.label(card, "MAX MATERIAL", UDim2.new(1, -12, 0, 24), UDim2.fromOffset(6, 96), C.Pink)
		end
	end
end

return Panels
