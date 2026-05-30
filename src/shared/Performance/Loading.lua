local Loading = {}

function Loading.shouldLoadTycoon(_tycoon: Instance, _isOwn: boolean): boolean
	return true
end

function Loading.onTycoonLoaded(_tycoon: Instance)
end

return Loading
