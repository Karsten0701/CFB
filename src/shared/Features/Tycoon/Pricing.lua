local AnimeDroppers = require(script.Parent.Parent.Parent.Data.AnimeDroppers)
local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)
local FormatUtil = require(script.Parent.FormatUtil)

local Pricing = {}
local RATE_EARLY_LEVELS = 5
local RATE_EARLY_BASE_PRICE = 10
local RATE_EARLY_INCREMENT = 10
local RATE_LEVEL_BASE = 42
local RATE_LEVEL_LINEAR_INCREMENT = 10
local RATE_LEVEL_MULTIPLIER = 3.25
local RATE_LEVEL_EXPONENT = 1.38
local RATE_GAIN_MULTIPLIER = 5
local RATE_GAIN_EXPONENT = 1.42
local RATE_STEP_SIZE = 5

local UNIT_BULK_DISCOUNTS = {
	[10] = 0.1,
	[25] = 0.2,
	[100] = 0.5,
}

local RATE_BULK_DISCOUNTS = {
	[10] = 0.1,
	[25] = 0.2,
	[100] = 0.5,
}

function Pricing.getBaseUnitCount(units: { { Tier: number } }): number
	local total = 0

	for _, unit in units or {} do
		local tierData = AnimeDroppers.Tiers[unit.Tier or 1]
		total += tierData and tierData.RequiredTier1 or 1
	end

	return total
end

function Pricing.getUnitPrice(baseUnitCount: number): number
	return TycoonConfig.UnitPriceBase + baseUnitCount * TycoonConfig.UnitPriceIncrement
end

function Pricing.getUnitBulkPrice(baseUnitCount: number, amount: number): number
	local totalPrice = 0
	for offset = 0, amount - 1 do
		totalPrice += Pricing.getUnitPrice(baseUnitCount + offset)
	end

	local discount = UNIT_BULK_DISCOUNTS[amount] or 0
	return math.max(math.floor(totalPrice * (1 - discount)), 0)
end

local function getRateStepGain(rateLevel: number): number
	local step = math.floor(rateLevel / RATE_STEP_SIZE)
	return math.max(math.floor((step + 1) ^ RATE_GAIN_EXPONENT + 0.15), 1)
end

local function getSingleRateUpgradePrice(rateLevel: number): number
	if rateLevel < RATE_EARLY_LEVELS then
		return RATE_EARLY_BASE_PRICE + rateLevel * RATE_EARLY_INCREMENT
	end

	local gain = getRateStepGain(rateLevel)
	local lateLevel = rateLevel - RATE_EARLY_LEVELS + 1
	return math.floor(
		RATE_LEVEL_BASE
			+ lateLevel * RATE_LEVEL_LINEAR_INCREMENT
			+ (lateLevel ^ RATE_LEVEL_EXPONENT) * RATE_LEVEL_MULTIPLIER
			+ gain * RATE_GAIN_MULTIPLIER
	)
end

function Pricing.getRateGain(amount: number, rateLevel: number): number
	if amount <= 0 then
		return 0
	end

	local totalGain = 0
	for offset = 0, amount - 1 do
		totalGain += getRateStepGain(rateLevel + offset)
	end

	return totalGain
end

function Pricing.getRateUpgradePrice(rateLevel: number, amount: number?): number
	amount = amount or 1
	local totalPrice = 0

	for offset = 0, amount - 1 do
		totalPrice += getSingleRateUpgradePrice(rateLevel + offset)
	end

	local discount = RATE_BULK_DISCOUNTS[amount] or 0
	return math.max(math.floor(totalPrice * (1 - discount)), 0)
end

function Pricing.formatYen(amount: number): string
	return "¥" .. FormatUtil.formatNumber(amount)
end

return Pricing
