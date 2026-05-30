local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage.Packages.dataservice).server
local Knit = require(ReplicatedStorage.Packages.knit)
local DataTemplate = require(script.Parent.DataTemplate)

type Path = string | { string | number }

local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {},
})

local leaderstatValues: { [Player]: { Yen: IntValue, Units: IntValue } } = {}

local function ensureNumberField(player: Player, path: string, defaultValue: number)
	local value = PlayerDataService:Get(player, path)
	if type(value) ~= "number" then
		PlayerDataService:Set(player, path, defaultValue)
	end
end

local function migrateNumberField(player: Player, oldPath: string, newPath: string)
	local newValue = PlayerDataService:Get(player, newPath)
	if type(newValue) == "number" then
		return
	end

	local oldValue = PlayerDataService:Get(player, oldPath)
	PlayerDataService:Set(player, newPath, if type(oldValue) == "number" then oldValue else 0)
end

local function ensureManaPowerData(player: Player)
	migrateNumberField(player, "Money", "Yen")
	ensureNumberField(player, "Yen", 100)
	migrateNumberField(player, "MagicPowerInBag", "ManaPowerInBag")
	migrateNumberField(player, "MagicPowerInDeposit", "ManaPowerInDeposit")
	ensureNumberField(player, "ManaPowerInBag", 0)
	ensureNumberField(player, "ManaPowerInDeposit", 0)

	if type(PlayerDataService:Get(player, "ProcessedReceipts")) ~= "table" then
		PlayerDataService:Set(player, "ProcessedReceipts", {})
	end
end

local function syncLeaderstats(player: Player)
	local values = leaderstatValues[player]
	if not values then
		return
	end

	local yen = PlayerDataService:Get(player, "Yen") or 0
	local units = PlayerDataService:GetUnits(player)

	values.Yen.Value = math.floor(yen)
	values.Units.Value = #units
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
	function DataService:onPlayerInit(player: Player, _data: any)
		ensureManaPowerData(player)
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
		profileStoreIndex = "CFB_PlayerData",
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

function PlayerDataService:AddManaPowerToBag(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	self:Update(player, "ManaPowerInBag", function(current: number)
		return current + amount
	end)
end

function PlayerDataService:DepositManaPower(player: Player): number
	local bagAmount = self:Get(player, "ManaPowerInBag") or 0
	if bagAmount <= 0 then
		return 0
	end

	local depositAmount = self:Get(player, "ManaPowerInDeposit") or 0
	self:Set(player, "ManaPowerInBag", 0)
	self:Set(player, "ManaPowerInDeposit", depositAmount + bagAmount)

	return bagAmount
end

function PlayerDataService:GetUnits(player: Player): { { Tier: number } }
	return self:Get(player, "Units") or {}
end

function PlayerDataService:SetUnits(player: Player, units: { { Tier: number } })
	self:Set(player, "Units", units)
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
