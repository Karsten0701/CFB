local ShowOther = {}

function ShowOther.shouldRenderOthers(settings: { ShowOthers: boolean? }?): boolean
	if not settings then
		return true
	end

	return settings.ShowOthers ~= false
end

return ShowOther
