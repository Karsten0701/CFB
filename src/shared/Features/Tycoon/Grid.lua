local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)

local Grid = {}

function Grid.getFloorAndSpot(unitIndex: number): (number, number)
	local floorIndex = math.ceil(unitIndex / TycoonConfig.SpotsPerFloor)
	local spotIndex = (unitIndex - 1) % TycoonConfig.SpotsPerFloor + 1
	return floorIndex, spotIndex
end

function Grid.requiredFloors(unitCount: number): number
	if unitCount <= 0 then
		return 1
	end

	return math.min(math.ceil(unitCount / TycoonConfig.SpotsPerFloor), TycoonConfig.MaxFloors)
end

return Grid
