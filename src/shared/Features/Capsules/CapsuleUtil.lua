local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
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

local function getExpectedRewardBaseUnits(highestTier: number): number
	local config = getCapsuleConfig()
	local weights = config.TierWeights
	local previewTiers = CapsuleUtil.getPreviewTiers(highestTier)
	if type(weights) ~= "table" or #weights <= 0 then
		return getTierRequiredBaseUnits(highestTier)
	end

	local expectedValue = 0
	local totalChance = 0
	for index, tier in previewTiers do
		local entry = weights[index]
		local chance = if type(entry) == "table" then math.max(tonumber(entry.Chance) or 0, 0) else 0
		expectedValue += getTierRequiredBaseUnits(tier) * chance
		totalChance += chance
	end

	if totalChance <= 0 then
		return getTierRequiredBaseUnits(highestTier)
	end

	return expectedValue / totalChance
end

local function getEstimatedUnitBuyCost(baseUnitValue: number, spawnTier: number, purchasedUnitCount: number): number
	local spawnBaseValue = getTierRequiredBaseUnits(spawnTier)
	local equivalentUnits = math.max((baseUnitValue or 1) / spawnBaseValue, 0.05)
	local lowerAmount = math.floor(equivalentUnits)
	local upperAmount = math.max(lowerAmount + 1, 1)
	local alpha = equivalentUnits - lowerAmount

	if lowerAmount <= 0 then
		return Pricing.getUnitBulkPrice(purchasedUnitCount, 1, true) * equivalentUnits
	end

	local lowerPrice = Pricing.getUnitBulkPrice(purchasedUnitCount, lowerAmount, true)
	local upperPrice = Pricing.getUnitBulkPrice(purchasedUnitCount, upperAmount, true)
	return lowerPrice + (upperPrice - lowerPrice) * alpha
end

function CapsuleUtil.getOpenPrice(
	highestTier: number,
	units: { { Tier: number } }?,
	purchasedUnitCount: number?,
	spawnTier: number?
): number
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local config = getCapsuleConfig()
	local minPrice = tonumber(config.MinOpenPrice) or 100
	local discount = math.clamp(tonumber(config.OpenPriceUnitCostDiscount) or 0.45, 0.01, 1)
	local dropMultiplier = math.max(tonumber(config.OpenPriceMultiplier) or 50, 1)
	local ownedCostPercent = math.clamp(tonumber(config.OpenPriceOwnedUnitCostPercent) or 0.18, 0.01, 1)
	local ownedCostFloorPercent = math.clamp(tonumber(config.OpenPriceOwnedUnitCostFloorPercent) or 0.04, 0, ownedCostPercent)
	local unitBuyDiscount = math.clamp(tonumber(config.OpenPriceUnitBuyDiscount) or 0.62, 0.05, 1)
	local spawnTierDiscountPower = math.clamp(tonumber(config.OpenPriceSpawnTierDiscountPower) or 1, 0, 2)
	local ownedBaseUnitPercent = math.clamp(tonumber(config.OpenPriceOwnedBaseUnitPercent) or 0.025, 0, 1)
	local globalMultiplier = math.max(tonumber(config.OpenPriceGlobalMultiplier) or 1.5, 0.1)
	local ownedScalingPercent = math.max(tonumber(config.OpenPriceOwnedScalingPercent) or 0.02, 0)
	local ownedScalingPower = math.clamp(tonumber(config.OpenPriceOwnedScalingPower) or 0.5, 0, 1.5)
	local ownedScalingMax = math.max(tonumber(config.OpenPriceOwnedScalingMax) or 2.25, 1)
	local currentUnitCountPercent = math.max(tonumber(config.OpenPriceCurrentUnitCountPercent) or 0.015, 0)
	local currentUnitCountPower = math.clamp(tonumber(config.OpenPriceCurrentUnitCountPower) or 0.65, 0, 1.5)
	local currentUnitCountMax = math.max(tonumber(config.OpenPriceCurrentUnitCountMax) or 1.8, 1)
	purchasedUnitCount = math.max(math.floor(tonumber(purchasedUnitCount) or 0), 0)
	spawnTier = math.clamp(math.floor(tonumber(spawnTier) or highestTier), 1, AnimeDroppers.MaxTier)
	local spawnBaseValue = getTierRequiredBaseUnits(spawnTier)
	local floorTier = highestTier

	for _, tier in CapsuleUtil.getPreviewTiers(highestTier) do
		floorTier = math.min(floorTier, tier)
	end

	local tierData = AnimeDroppers.Tiers[floorTier]
	local requiredTierOneUnits = math.max(math.floor(tonumber(tierData and tierData.RequiredTier1) or 1), 1)
	local estimatedUnitCost = tonumber(tierData and tierData.EstimatedTier1Cost)
		or Pricing.getUnitBulkPrice(0, requiredTierOneUnits, true)
	local dropValue = math.max(tonumber(tierData and tierData.DropValue) or 1, 1)
	local legacyTierPrice = math.max(estimatedUnitCost * discount, dropValue * dropMultiplier)
	local expectedBaseUnits = getExpectedRewardBaseUnits(highestTier)
	local valueBasedPrice = getEstimatedUnitBuyCost(expectedBaseUnits, spawnTier, purchasedUnitCount) * unitBuyDiscount
	local spawnTierDiscount = 1 / (spawnBaseValue ^ spawnTierDiscountPower)
	local tierBasedPrice = math.min(legacyTierPrice, valueBasedPrice) * spawnTierDiscount
	local ownedUnitCost = 0
	local ownedBaseUnits = 0
	local currentUnitCount = 0
	if type(units) == "table" then
		for _, unit in units do
			if type(unit) ~= "table" then
				continue
			end

			currentUnitCount += 1
			local ownedTierData = AnimeDroppers.Tiers[unit.Tier or 1]
			ownedUnitCost += tonumber(ownedTierData and ownedTierData.EstimatedTier1Cost) or 0
			ownedBaseUnits += getTierRequiredBaseUnits(unit.Tier or 1)
		end
	end

	local price = tierBasedPrice
	local ownedProgressMultiplier = 1
	if ownedUnitCost > 0 then
		price = math.min(price, ownedUnitCost * ownedCostPercent)
		price = math.max(price, ownedUnitCost * ownedCostFloorPercent)
	end
	if ownedBaseUnits > 0 and ownedBaseUnitPercent > 0 then
		local ownedEquivalentUnits = math.max(ownedBaseUnits / spawnBaseValue, 1)
		ownedProgressMultiplier = math.min(1 + ownedScalingPercent * (ownedEquivalentUnits ^ ownedScalingPower), ownedScalingMax)
		local ownedProgressPrice = Pricing.getUnitBulkPrice(purchasedUnitCount, math.max(math.floor(ownedBaseUnits / spawnBaseValue), 1), true)
			* ownedBaseUnitPercent
			* spawnTierDiscount
		price = math.min(price, ownedProgressPrice)
	end

	local currentUnitCountMultiplier = math.min(
		1 + currentUnitCountPercent * (currentUnitCount ^ currentUnitCountPower),
		currentUnitCountMax
	)

	price *= globalMultiplier * ownedProgressMultiplier * currentUnitCountMultiplier
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
