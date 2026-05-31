local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local DataService = require(ReplicatedStorage.Packages.dataservice).server
local Knit = require(ReplicatedStorage.Packages.knit)
local DataTemplate = require(script.Parent.DataTemplate)

type Path = string | { string | number }

local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {},
})

local leaderstatValues: { [Player]: { Yen: IntValue, Units: IntValue } } = {}

local function migrateNumberFieldInData(data: { [string]: any }, oldPath: string, newPath: string, defaultValue: number)
	if type(data[newPath]) == "number" then
		return
	end

	data[newPath] = if type(data[oldPath]) == "number" then data[oldPath] else defaultValue
end

local function normalizeUnits(units: any): { { Tier: number, Slot: number } }
	local normalizedUnits = {}
	if type(units) ~= "table" then
		return normalizedUnits
	end

	for _, unit in units do
		if type(unit) ~= "table" then
			continue
		end

		local tier = math.clamp(math.floor(tonumber(unit.Tier) or 1), 1, AnimeDroppers.MaxTier)
		if AnimeDroppers.Tiers[tier] then
			table.insert(normalizedUnits, {
				Tier = tier,
				Slot = tonumber(unit.Slot) or math.huge,
			})
		end
	end

	table.sort(normalizedUnits, function(left, right)
		if left.Tier == right.Tier then
			return left.Slot < right.Slot
		end

		return left.Tier > right.Tier
	end)

	for slot, unit in normalizedUnits do
		unit.Slot = slot
	end

	return normalizedUnits
end

local function ensureManaData(data: { [string]: any })
	migrateNumberFieldInData(data, "Money", "Yen", 100)
	migrateNumberFieldInData(data, "MagicPowerInBag", "ManaInBag", 0)
	migrateNumberFieldInData(data, "MagicPowerInDeposit", "ManaInDeposit", 0)
	migrateNumberFieldInData(data, "ManaPowerInBag", "ManaInBag", 0)
	migrateNumberFieldInData(data, "ManaPowerInDeposit", "ManaInDeposit", 0)

	if type(data.Yen) ~= "number" then
		data.Yen = 100
	end

	if type(data.ManaInBag) ~= "number" then
		data.ManaInBag = 0
	end

	if type(data.ManaInDeposit) ~= "number" then
		data.ManaInDeposit = 0
	end

	if type(data.ProcessedReceipts) ~= "table" then
		data.ProcessedReceipts = {}
	end

	if type(data.PurchasedProducts) ~= "table" then
		data.PurchasedProducts = {}
	end

	if type(data.Settings) ~= "table" then
		data.Settings = {}
	end

	if type(data.Settings.ShowOthers) ~= "boolean" then
		data.Settings.ShowOthers = true
	end

	if type(data.Settings.ShowOtherTycoons) ~= "boolean" then
		data.Settings.ShowOtherTycoons = true
	end

	local autoMergeAt = tonumber(data.Settings.AutoMergeAt) or 100
	data.Settings.AutoMergeAt = math.clamp(math.floor(autoMergeAt), 1, 100)

	if type(data.Settings.AutoCollect) ~= "boolean" then
		data.Settings.AutoCollect = true
	end

	if type(data.Settings.AutoDeposit) ~= "boolean" then
		data.Settings.AutoDeposit = true
	end

	data.Units = normalizeUnits(data.Units)
end

local function syncLeaderstats(player: Player)
	local values = leaderstatValues[player]
	if not values then
		return
	end

	local yen = PlayerDataService:Get(player, "Yen") or 0
	local units = PlayerDataService:GetUnits(player)

	values.Yen.Value = math.floor(yen)
	values.Units.Value = Pricing.getBaseUnitCount(units)
end

local function setupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local yenValue = Instance.new("IntValue")
	yenValue.Name = "Yen"
	yenValue.Parent = leaderstats

	local unitsValue = Instance.new("IntValue")
	unitsValue.Name = "Units"
	unitsValue.Parent = leaderstats

	leaderstats.Parent = player
	leaderstatValues[player] = {
		Yen = yenValue,
		Units = unitsValue,
	}

	syncLeaderstats(player)
end

function PlayerDataService:KnitInit()
	function DataService:onPlayerInit(player: Player, data: any)
		ensureManaData(data)
		setupLeaderstats(player)

		PlayerDataService:Observe(player, "Yen", function()
			syncLeaderstats(player)
		end)

		PlayerDataService:Observe(player, "Units", function()
			syncLeaderstats(player)
		end)
	end

	DataService:init({
		template = DataTemplate,
		profileStoreIndex = "CFB_PlayerData.5",
	})
end

function PlayerDataService:KnitStart()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		leaderstatValues[player] = nil
	end)
end

function PlayerDataService:WaitForData(player: Player)
	return DataService:waitForData(player)
end

function PlayerDataService:Get(player: Player, path: Path?)
	self:WaitForData(player)
	return DataService:get(player, path)
end

function PlayerDataService:Set(player: Player, path: Path, value: any)
	self:WaitForData(player)
	DataService:set(player, path, value)
end

function PlayerDataService:Update(player: Player, path: Path, callback: (any) -> any)
	self:WaitForData(player)
	return DataService:update(player, path, callback)
end

function PlayerDataService:AddYen(player: Player, amount: number)
	assert(amount >= 0, "Yen reward amount cannot be negative")

	return self:Update(player, "Yen", function(currentYen: number)
		return currentYen + amount
	end)
end

function PlayerDataService:TrySpendYen(player: Player, amount: number): boolean
	if amount < 0 then
		return false
	end

	local currentYen = self:Get(player, "Yen")
	if currentYen < amount then
		return false
	end

	self:Set(player, "Yen", currentYen - amount)
	return true
end

function PlayerDataService:AddManaToBag(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	self:Update(player, "ManaInBag", function(current: number)
		return current + amount
	end)
end

function PlayerDataService:DepositMana(player: Player): number
	local bagAmount = self:Get(player, "ManaInBag") or 0
	if bagAmount <= 0 then
		return 0
	end

	local depositAmount = self:Get(player, "ManaInDeposit") or 0
	self:Set(player, "ManaInBag", 0)
	self:Set(player, "ManaInDeposit", depositAmount + bagAmount)

	return bagAmount
end

function PlayerDataService:GetUnits(player: Player): { { Tier: number, Slot: number } }
	return self:Get(player, "Units") or {}
end

function PlayerDataService:SetUnits(player: Player, units: { { Tier: number } })
	self:Set(player, "Units", normalizeUnits(units))
end

function PlayerDataService:Observe(player: Player, path: Path, callback: (any, any?) -> ())
	self:WaitForData(player)
	return DataService:getChangedSignal(player, path):Connect(callback)
end

local function isValidVolume(volume: any): boolean
	return type(volume) == "number" and volume == volume and volume >= 0 and volume <= 1
end

function PlayerDataService.Client:SetMusicVolume(player: Player, volume: number): boolean
	if not isValidVolume(volume) then
		return false
	end

	self.Server:Set(player, { "Settings", "musicVolume" }, volume)
	return true
end

function PlayerDataService.Client:SetSfxVolume(player: Player, volume: number): boolean
	if not isValidVolume(volume) then
		return false
	end

	self.Server:Set(player, { "Settings", "sfxVolume" }, volume)
	return true
end

return PlayerDataService
