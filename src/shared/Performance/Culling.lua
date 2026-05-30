local Culling = {}

local DEFAULT_DISTANCE = 250

function Culling.shouldRenderAtDistance(distance: number, isOwn: boolean): boolean
	if isOwn then
		return true
	end

	return distance <= DEFAULT_DISTANCE
end

return Culling
