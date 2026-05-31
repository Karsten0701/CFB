local Culling = {}

local OTHER_TYCOON_LOAD_DISTANCE = 75
local OTHER_TYCOON_UNLOAD_DISTANCE = 90

function Culling.shouldRenderAtDistance(distance: number, isOwn: boolean): boolean
	if isOwn then
		return true
	end

	return distance <= OTHER_TYCOON_LOAD_DISTANCE
end

function Culling.shouldKeepRenderedAtDistance(distance: number, isOwn: boolean): boolean
	if isOwn then
		return true
	end

	return distance <= OTHER_TYCOON_UNLOAD_DISTANCE
end

function Culling.getOtherTycoonLoadDistance(): number
	return OTHER_TYCOON_LOAD_DISTANCE
end

function Culling.getOtherTycoonUnloadDistance(): number
	return OTHER_TYCOON_UNLOAD_DISTANCE
end

return Culling
