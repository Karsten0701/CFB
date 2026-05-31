local AnimeDroppers = require(script.Parent.Parent.Parent.Data.AnimeDroppers)
local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)

local Merge = {}

local function countByTier(units: { { Tier: number } }): { [number]: number }
	local counts = {}
	for _, unit in units do
		local tier = unit.Tier or 1
		if AnimeDroppers.Tiers[tier] then
			counts[tier] = (counts[tier] or 0) + 1
		end
	end
	return counts
end

local function rebuildUnits(counts: { [number]: number }): { { Tier: number } }
	local units = {}
	for tier = AnimeDroppers.MaxTier, 1, -1 do
		local count = counts[tier] or 0
		for _ = 1, count do
			table.insert(units, { Tier = tier })
		end
	end
	return units
end

function Merge.sortUnits(units: { { Tier: number } }): { { Tier: number } }
	local sortedUnits = table.clone(units)
	table.sort(sortedUnits, function(left, right)
		return (left.Tier or 1) > (right.Tier or 1)
	end)

	return sortedUnits
end

function Merge.runOnce(units: { { Tier: number } }): ({ { Tier: number } }, boolean, number)
	local counts = countByTier(units)
	local changed = false
	local mergedUnitCount = 0

	for tier = 1, AnimeDroppers.MaxTier do
		local tierData = AnimeDroppers.Tiers[tier]
		local targetTier = tierData and tierData.MergeInto
		if not targetTier or not AnimeDroppers.Tiers[targetTier] then
			continue
		end

		local count = counts[tier] or 0
		local mergeCount = math.floor(count / TycoonConfig.MergeRatio)
		if mergeCount > 0 then
			counts[tier] = count - mergeCount * TycoonConfig.MergeRatio
			counts[targetTier] = (counts[targetTier] or 0) + mergeCount
			mergedUnitCount += mergeCount * TycoonConfig.MergeRatio
			changed = true
		end
	end

	return rebuildUnits(counts), changed, mergedUnitCount
end

function Merge.autoMerge(units: { { Tier: number } }): { { Tier: number } }
	local mergedUnits = table.clone(units)
	local changed = true

	while changed do
		mergedUnits, changed = Merge.runOnce(mergedUnits)
	end

	return mergedUnits
end

function Merge.makeRoom(units: { { Tier: number } }, amountToAdd: number): { { Tier: number } }
	local mergedUnits = Merge.autoMerge(units)
	local safety = 0

	while #mergedUnits + amountToAdd > TycoonConfig.MaxUnits and safety < 32 do
		local beforeCount = #mergedUnits
		mergedUnits = Merge.autoMerge(mergedUnits)
		if #mergedUnits == beforeCount then
			break
		end
		safety += 1
	end

	return mergedUnits
end

return Merge
