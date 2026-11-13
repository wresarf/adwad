--!strict
-- Assigns the six plot pads to players and renders their equipped pets on pedestals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local GameMath = require(Shared:WaitForChild("GameMath"))
local PetModelBuilder = require(Shared:WaitForChild("PetModelBuilder"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))

local PlotService = {}
PlotService.__index = PlotService

type PlotInfo = WorldBuilder.PlotInfo
export type PlotService = typeof(setmetatable({} :: { plots: { PlotInfo }, owners: { [Player]: PlotInfo } }, PlotService))

function PlotService.new(plots: { PlotInfo }): PlotService
	return setmetatable({ plots = plots, owners = {} }, PlotService)
end

function PlotService.get(self: PlotService, player: Player): PlotInfo?
	return self.owners[player]
end

function PlotService.claim(self: PlotService, player: Player): PlotInfo?
	local existing = self.owners[player]
	if existing then
		return existing
	end
	local taken: { [PlotInfo]: boolean } = {}
	for _, p in self.owners do
		taken[p] = true
	end
	for _, plot in self.plots do
		if not taken[plot] then
			self.owners[player] = plot
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			plot.ownerLabel.Text = player.DisplayName .. "'s Pets"
			plot.incomeLabel.Text = "+0 / sec"
			return plot
		end
	end
	return nil
end

function PlotService.release(self: PlotService, player: Player)
	local plot = self.owners[player]
	if not plot then
		return
	end
	self.owners[player] = nil
	plot.petsFolder:ClearAllChildren()
	plot.model:SetAttribute("OwnerUserId", nil)
	plot.ownerLabel.Text = "Free Plot"
	plot.incomeLabel.Text = "+0 / sec"
end

local function petLabel(adornee: BasePart, rec: any, height: number)
	local pet = PetConfig.get(rec.species)
	if not pet then
		return
	end
	local rarity = GameMath.overallRarity(rec)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PetLabel"
	gui.Size = UDim2.fromOffset(170, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.5, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = adornee
	local function line(text: string, y: number, h: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, h, 0)
		l.Position = UDim2.new(0, 0, y, 0)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.Text = text
		l.Parent = gui
	end
	local mut = ""
	if rec.size ~= "Normal" then
		mut ..= rec.size .. " "
	end
	if rec.material ~= "Normal" then
		mut ..= rec.material .. " "
	end
	line(mut .. pet.name, 0, 0.4, (GameConfig.RarityColors :: any)[rarity] or Color3.new(1, 1, 1))
	line(rarity, 0.4, 0.28, Color3.fromRGB(230, 230, 240))
	line("+" .. GameMath.formatNumber(GameMath.petIncome(rec)) .. "/s", 0.68, 0.32, Color3.fromRGB(255, 230, 90))
end

function PlotService.render(self: PlotService, player: Player, data: any, income: number)
	local plot = self.owners[player]
	if not plot then
		return
	end
	plot.petsFolder:ClearAllChildren()
	plot.incomeLabel.Text = "+" .. GameMath.formatNumber(income) .. " / sec"
	local equipped = {}
	for _, p in data.pets do
		if p.equipped then
			table.insert(equipped, p)
		end
	end
	table.sort(equipped, function(a, b)
		return GameMath.petIncome(a) > GameMath.petIncome(b)
	end)
	local rotation = plot.pad.CFrame.Rotation
	for i, rec in equipped do
		local ped = plot.pedestals[i]
		if not ped then
			break
		end
		local top = ped.CFrame.Position + Vector3.new(0, ped.Size.X / 2, 0)
		local model, height = PetModelBuilder.build(rec.species, rec.material, rec.size, CFrame.new(top) * rotation)
		model:AddTag("PlotPet")
		model:SetAttribute("Uid", rec.uid)
		local primary = model.PrimaryPart
		if primary then
			petLabel(primary, rec, height - primary.CFrame.Position.Y + top.Y)
		end
		model.Parent = plot.petsFolder
	end
end

function PlotService.setIncome(self: PlotService, player: Player, income: number)
	local plot = self.owners[player]
	if plot then
		plot.incomeLabel.Text = "+" .. GameMath.formatNumber(income) .. " / sec"
	end
end

return PlotService
