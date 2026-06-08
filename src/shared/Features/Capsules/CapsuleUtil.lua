local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local RebirthUpgrades = require(ReplicatedStorage.Shared.Data.RebirthUpgrades)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)

local CapsuleUtil = {}

local function getCapsuleConfig()
	return TycoonConfig.Capsules or {}
end

local function getTierRequiredBaseUnits(tier: number): number
	local tierData = AnimeDroppers.Tiers[math.clamp(math.floor(tier or 1), 1, AnimeDroppers.MaxTier)]
	return math.max(tonumber(tierData and tierData.RequiredTier1) or 1, 1)
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

local function getOpenPriceConfig(): { [string]: any }
	local config = getCapsuleConfig()
	local openPrice = config.OpenPrice
	if type(openPrice) == "table" then
		return openPrice
	end

	return {
		Min = config.MinOpenPrice,
		Discount = config.OpenPriceUnitBuyDiscount,
		MinValueRatio = 1,
		ReferenceSpawnTierCap = RebirthUpgrades.UnitSpawnTier.MaxLevel + 1,
		EconomyScaleExponent = 0.5,
		LateGameUnitThreshold = 50_000_000,
		MinMarginalMultiplier = 400,
	}
end

local function getPricingSpawnTier(actualSpawnTier: number): number
	local openPrice = getOpenPriceConfig()
	local configuredCap = math.floor(tonumber(openPrice.ReferenceSpawnTierCap) or 0)
	local defaultCap = RebirthUpgrades.UnitSpawnTier.MaxLevel + 1
	local cap = if configuredCap > 0 then configuredCap else defaultCap
	return math.clamp(math.min(actualSpawnTier, cap), 1, AnimeDroppers.MaxTier)
end

local function getMarginalUnitPrice(
	purchasedUnitCount: number,
	spawnTier: number,
	unitScaleCount: number
): number
	return Pricing.getUnitBulkPrice(purchasedUnitCount, 1, true, spawnTier, unitScaleCount)
end

function CapsuleUtil.getExpectedRewardBaseUnits(highestTier: number): number
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local previewTiers = CapsuleUtil.getPreviewTiers(highestTier)
	local config = getCapsuleConfig()
	local weights = config.TierWeights
	if type(weights) ~= "table" or #weights <= 0 then
		return getTierRequiredBaseUnits(highestTier)
	end

	local expectedBaseUnits = 0
	for index, tier in previewTiers do
		local weightEntry = weights[index]
		local chance = if type(weightEntry) == "table" then tonumber(weightEntry.Chance) or 0 else 0
		expectedBaseUnits += chance * getTierRequiredBaseUnits(tier)
	end

	return math.max(expectedBaseUnits, 0)
end

--[[
	Open price = (+1 buy price) × (expected reward RequiredTier1 / rebirth spawn RequiredTier1)
	× economy scale × discount. Spawn tier from events is capped for the ratio so late-game
	capsules stay in the trillions instead of collapsing to billions.
]]
function CapsuleUtil.getOpenPrice(
	highestTier: number,
	_units: { { Tier: number } }?,
	purchasedUnitCount: number?,
	spawnTier: number?,
	unitScaleCount: number?
): number
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local openPrice = getOpenPriceConfig()
	local minPrice = math.max(math.floor(tonumber(openPrice.Min) or 100), 0)
	local discount = math.clamp(tonumber(openPrice.Discount) or 0.85, 0.05, 1)
	local minValueRatio = math.max(tonumber(openPrice.MinValueRatio) or 1, 1)
	local economyScaleExponent = math.clamp(tonumber(openPrice.EconomyScaleExponent) or 0.5, 0, 2)
	local lateGameUnitThreshold = math.max(tonumber(openPrice.LateGameUnitThreshold) or 50_000_000, 0)
	local minMarginalMultiplier = math.max(tonumber(openPrice.MinMarginalMultiplier) or 350, 1)

	local resolvedPurchasedCount = math.max(math.floor(tonumber(purchasedUnitCount) or 0), 0)
	local resolvedUnitScaleCount =
		math.max(math.floor(tonumber(unitScaleCount) or resolvedPurchasedCount), resolvedPurchasedCount)
	local resolvedSpawnTier = math.clamp(math.floor(tonumber(spawnTier) or highestTier), 1, AnimeDroppers.MaxTier)
	local pricingSpawnTier = getPricingSpawnTier(resolvedSpawnTier)
	local pricingSpawnBase = math.max(getTierRequiredBaseUnits(pricingSpawnTier), 1)
	local highestBaseUnits = math.max(getTierRequiredBaseUnits(highestTier), 1)

	local marginalUnitPrice =
		getMarginalUnitPrice(resolvedPurchasedCount, resolvedSpawnTier, resolvedUnitScaleCount)
	if marginalUnitPrice <= 0 then
		return minPrice
	end

	local expectedRewardBaseUnits = CapsuleUtil.getExpectedRewardBaseUnits(highestTier)
	if expectedRewardBaseUnits <= 0 then
		return minPrice
	end

	local valueRatio = math.max(expectedRewardBaseUnits / pricingSpawnBase, minValueRatio)
	local economyScale = math.max(resolvedUnitScaleCount / highestBaseUnits, 1) ^ economyScaleExponent
	local price = marginalUnitPrice * valueRatio * economyScale * discount

	if resolvedUnitScaleCount >= lateGameUnitThreshold then
		price = math.max(price, marginalUnitPrice * minMarginalMultiplier * discount)
	end

	return math.max(math.floor(price), minPrice)
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
