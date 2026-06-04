local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)

local CapsuleUtil = {}

local function getCapsuleConfig()
	return TycoonConfig.Capsules or {}
end

function CapsuleUtil.getHighestUnitTier(units: { { Tier: number } }?): number
	local highest = 1
	if type(units) ~= "table" then
		return highest
	end

	for _, unit in units do
		if type(unit) == "table" then
			local tier = math.clamp(math.floor(tonumber(unit.Tier) or 1), 1, AnimeDroppers.MaxTier)
			if tier > highest then
				highest = tier
			end
		end
	end

	return highest
end

function CapsuleUtil.getPreviewTiers(highestTier: number): { number }
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local config = getCapsuleConfig()
	local weights = config.TierWeights
	if type(weights) ~= "table" or #weights <= 0 then
		return {
			math.max(highestTier - 1, 1),
			highestTier,
			math.min(highestTier + 1, AnimeDroppers.MaxTier),
		}
	end

	local previewTiers = table.create(#weights)
	for index, entry in weights do
		local offset = if type(entry) == "table" then math.floor(tonumber(entry.Offset) or 0) else 0
		previewTiers[index] = math.clamp(highestTier + offset, 1, AnimeDroppers.MaxTier)
	end

	return previewTiers
end

function CapsuleUtil.rollRewardTier(highestTier: number): number?
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local config = getCapsuleConfig()
	local weights = config.TierWeights
	if type(weights) ~= "table" or #weights <= 0 then
		return highestTier
	end

	local roll = math.random()
	local cumulative = 0
	for _, entry in weights do
		if type(entry) ~= "table" then
			continue
		end

		local chance = tonumber(entry.Chance) or 0
		cumulative += chance
		if roll <= cumulative then
			local offset = math.floor(tonumber(entry.Offset) or 0)
			return math.clamp(highestTier + offset, 1, AnimeDroppers.MaxTier)
		end
	end

	local lastEntry = weights[#weights]
	if type(lastEntry) == "table" then
		local offset = math.floor(tonumber(lastEntry.Offset) or 0)
		return math.clamp(highestTier + offset, 1, AnimeDroppers.MaxTier)
	end

	return highestTier
end

function CapsuleUtil.getOpenPrice(highestTier: number): number
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local config = getCapsuleConfig()
	local tierData = AnimeDroppers.Tiers[highestTier]
	local dropValue = if tierData then tonumber(tierData.DropValue) or 1 else 1
	local multiplier = tonumber(config.OpenPriceMultiplier) or 50
	local minPrice = tonumber(config.MinOpenPrice) or 100
	return math.max(math.floor(dropValue * multiplier), minPrice)
end

function CapsuleUtil.getPreviewDisplayEntries(highestTier: number): { { Tier: number, DisplayName: string, Chance: number } }
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local previewTiers = CapsuleUtil.getPreviewTiers(highestTier)
	local config = getCapsuleConfig()
	local weights = config.TierWeights or {}
	local entries = table.create(#previewTiers)

	for index, tier in previewTiers do
		local tierData = AnimeDroppers.Tiers[tier]
		local weightEntry = weights[index]
		local chance = if type(weightEntry) == "table" then tonumber(weightEntry.Chance) or 0 else 0
		table.insert(entries, {
			Tier = tier,
			DisplayName = if tierData then tierData.DisplayName else `Tier {tier}`,
			Chance = chance,
		})
	end

	return entries
end

function CapsuleUtil.formatChancePercent(chance: number): string
	chance = math.clamp(chance or 0, 0, 1)
	return string.format("%.0f%%", chance * 100)
end

function CapsuleUtil.getSlotNames(): { string }
	local config = getCapsuleConfig()
	if type(config.SlotNames) == "table" and #config.SlotNames > 0 then
		return config.SlotNames
	end

	return { "unit1", "unit2", "unit3" }
end

return CapsuleUtil
