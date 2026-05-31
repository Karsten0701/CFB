local ShowOther = {}

function ShowOther.shouldRenderOthers(settings: { [string]: any }?): boolean
	if type(settings) ~= "table" then
		return true
	end

	local showOthers = settings.ShowOthers
	local showOtherTycoons = settings.ShowOtherTycoons

	return showOthers ~= false and showOtherTycoons ~= false
end

return ShowOther
