local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage.Packages.dataservice).client
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Knit = require(ReplicatedStorage.Packages.knit)

type Path = string | { string | number }

local PlayerDataController = Knit.CreateController({
	Name = "PlayerDataController",
})

function PlayerDataController:KnitInit()
	DataService:init()
end

function PlayerDataController:Get(path: Path?)
	return DataService:get(path)
end

function PlayerDataController:Observe(path: Path, callback: (any, any?) -> (), janitor: any?)
	callback(DataService:get(path))

	local connection = DataService:getChangedSignal(path):Connect(callback)
	if janitor then
		janitor:Add(connection)
	end

	return connection
end

function PlayerDataController:ObserveIndex(path: Path, callback: (string | number, any, any?) -> (), janitor: any?)
	local connection = DataService:getIndexChangedSignal(path):Connect(callback)
	if janitor then
		janitor:Add(connection)
	end

	return connection
end

function PlayerDataController:ObserveInventoryAdded(callback: (number, any) -> (), janitor: any?)
	local connection = DataService:getArrayInsertedSignal("inventory"):Connect(callback)
	if janitor then
		janitor:Add(connection)
	end

	return connection
end

function PlayerDataController:ObserveInventoryRemoved(callback: (number, any) -> (), janitor: any?)
	local connection = DataService:getArrayRemovedSignal("inventory"):Connect(callback)
	if janitor then
		janitor:Add(connection)
	end

	return connection
end

function PlayerDataController:NewJanitor()
	return Janitor.new()
end

function PlayerDataController:SetMusicVolume(volume: number)
	return Knit.GetService("PlayerDataService"):SetMusicVolume(volume)
end

function PlayerDataController:SetSfxVolume(volume: number)
	return Knit.GetService("PlayerDataService"):SetSfxVolume(volume)
end

return PlayerDataController
