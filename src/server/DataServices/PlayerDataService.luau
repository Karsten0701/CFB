local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage.Packages.dataservice).server
local Knit = require(ReplicatedStorage.Packages.knit)
local DataTemplate = require(script.Parent.DataTemplate)

type Path = string | { string | number }

local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {},
})

function PlayerDataService:KnitInit()
	DataService:init({
		template = DataTemplate,
		profileStoreIndex = "CFB_PlayerData",
	})
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

function PlayerDataService:AddCurrency(player: Player, amount: number)
	assert(amount >= 0, "Currency reward amount cannot be negative")

	return self:Update(player, "currency", function(currentCurrency: number)
		return currentCurrency + amount
	end)
end

function PlayerDataService:AddInventoryItem(player: Player, item: { [string]: any })
	self:WaitForData(player)
	DataService:arrayInsert(player, "inventory", item)
end

function PlayerDataService:RemoveInventoryItem(player: Player, index: number)
	self:WaitForData(player)
	return DataService:arrayRemove(player, "inventory", index)
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

	self.Server:Set(player, { "settings", "musicVolume" }, volume)
	return true
end

function PlayerDataService.Client:SetSfxVolume(player: Player, volume: number): boolean
	if not isValidVolume(volume) then
		return false
	end

	self.Server:Set(player, { "settings", "sfxVolume" }, volume)
	return true
end

return PlayerDataService
