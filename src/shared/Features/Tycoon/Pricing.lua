local AnimeDroppers = require(script.Parent.Parent.Parent.Data.AnimeDroppers)
local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)
local FormatUtil = require(script.Parent.FormatUtil)

local Pricing = {}
local RATE_EARLY_LEVELS = 5
local RATE_EARLY_BASE_PRICE = 10
local RATE_EARLY_INCREMENT = 5
local RATE_STEP_SIZE = 5
local RATE_GAIN_EXPONENT = 1.75
local RATE_PRICE_LINEAR_INCREMENT = 15
local RATE_PRICE_GAIN_MULTIPLIER = 11
local RATE_PRICE_STEP_MULTIPLIER = 12.5
local RATE_PRICE_STEP_EXPONENT = 2.25
local MAX_RATE_BUY_AMOUNT = 100_000

local UNIT_BULK_DISCOUNTS = {
	[5] = 0.075,
	[10] = 0.2,
	[25] = 0.2,
	[100] = 0.33,
	["Max"] = 0,
}

local RATE_BULK_DISCOUNTS = {
	[10] = 0.2,
	["Max"] = 0,
}

function Pricing.getBaseUnitCount(units: { { Tier: number } }): number
	local total = 0

	for _, unit in units do
		if type(unit) ~= "table" then
			continue
		end

		local tierData = AnimeDroppers.Tiers[unit.Tier or 1]
		total += tierData and tierData.RequiredTier1 or 1
	end

	return total
end

function Pricing.getUnitPrice(baseUnitCount: number): number
	return TycoonConfig.UnitPriceBase + baseUnitCount * TycoonConfig.UnitPriceIncrement
end

local function getArithmeticSum(first: number, last: number, count: number): number
	return (first + last) * count / 2
end

local function getUnitBulkDiscount(amount: number, useMaxDiscount: boolean?): number
	return if useMaxDiscount then UNIT_BULK_DISCOUNTS.Max or 0 else UNIT_BULK_DISCOUNTS[amount] or 0
end

function Pricing.getUnitBulkPrice(baseUnitCount: number, amount: number, useMaxDiscount: boolean?): number
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return 0
	end

	local firstPrice = Pricing.getUnitPrice(baseUnitCount)
	local totalPrice = amount * firstPrice + TycoonConfig.UnitPriceIncrement * amount * (amount - 1) / 2
	local discount = getUnitBulkDiscount(amount, useMaxDiscount)
	return math.max(math.floor(totalPrice * (1 - discount)), 0)
end

function Pricing.getMaxBaseUnitCapacity(): number
	return TycoonConfig.MaxUnits * (TycoonConfig.MergeRatio ^ (AnimeDroppers.MaxTier - 1))
end

function Pricing.getMaxAffordableUnitPurchase(baseUnitCount: number, yen: number): (number, number)
	yen = math.max(yen or 0, 0)
	local capacity = math.max(math.floor(Pricing.getMaxBaseUnitCapacity() - baseUnitCount), 0)
	if capacity <= 0 then
		return 0, 0
	end

	local low = 0
	local high = capacity
	local iterations = 0
	while low < high and iterations < 128 do
		iterations += 1
		local mid = math.ceil((low + high + 1) / 2)
		if mid <= low then
			break
		end

		local price = Pricing.getUnitBulkPrice(baseUnitCount, mid, true)
		if price <= yen then
			low = mid
		else
			high = mid - 1
		end
	end

	return low, Pricing.getUnitBulkPrice(baseUnitCount, low, true)
end

local function getRateStepGain(rateLevel: number): number
	local step = math.floor(rateLevel / RATE_STEP_SIZE) + 1
	return math.max(math.floor(step ^ RATE_GAIN_EXPONENT + 0.5), 1)
end

local function getSingleRateUpgradePrice(rateLevel: number): number
	if rateLevel < RATE_EARLY_LEVELS then
		return RATE_EARLY_BASE_PRICE + rateLevel * RATE_EARLY_INCREMENT
	end

	local step = math.floor(rateLevel / RATE_STEP_SIZE) + 1
	local gain = getRateStepGain(rateLevel)
	return math.floor(
		TycoonConfig.RateUpgradeBasePrice
			+ rateLevel * RATE_PRICE_LINEAR_INCREMENT
			+ gain * RATE_PRICE_GAIN_MULTIPLIER
			+ (step ^ RATE_PRICE_STEP_EXPONENT) * RATE_PRICE_STEP_MULTIPLIER
	)
end

local function getRateSequentialPrice(rateLevel: number, amount: number): number
	local currentLevel = rateLevel
	local remaining = amount
	local totalPrice = 0

	if currentLevel < RATE_EARLY_LEVELS then
		local earlyCount = math.min(remaining, RATE_EARLY_LEVELS - currentLevel)
		local firstPrice = RATE_EARLY_BASE_PRICE + currentLevel * RATE_EARLY_INCREMENT
		local lastPrice = RATE_EARLY_BASE_PRICE + (currentLevel + earlyCount - 1) * RATE_EARLY_INCREMENT
		totalPrice += getArithmeticSum(firstPrice, lastPrice, earlyCount)
		currentLevel += earlyCount
		remaining -= earlyCount
	end

	while remaining > 0 do
		local step = math.floor(currentLevel / RATE_STEP_SIZE) + 1
		local nextStepLevel = step * RATE_STEP_SIZE
		local chunk = math.min(remaining, math.max(nextStepLevel - currentLevel, 1))
		local gain = getRateStepGain(currentLevel)
		local firstLinear = currentLevel * RATE_PRICE_LINEAR_INCREMENT
		local lastLinear = (currentLevel + chunk - 1) * RATE_PRICE_LINEAR_INCREMENT
		local perLevelConstant = TycoonConfig.RateUpgradeBasePrice
			+ gain * RATE_PRICE_GAIN_MULTIPLIER
			+ (step ^ RATE_PRICE_STEP_EXPONENT) * RATE_PRICE_STEP_MULTIPLIER

		totalPrice += perLevelConstant * chunk + getArithmeticSum(firstLinear, lastLinear, chunk)
		currentLevel += chunk
		remaining -= chunk
	end

	return totalPrice
end

function Pricing.getRateGain(amount: number, rateLevel: number): number
	if amount <= 0 then
		return 0
	end

	amount = math.floor(amount)
	local totalGain = 0
	local currentLevel = rateLevel
	local remaining = amount
	while remaining > 0 do
		local nextStepLevel = (math.floor(currentLevel / RATE_STEP_SIZE) + 1) * RATE_STEP_SIZE
		local chunk = math.min(remaining, math.max(nextStepLevel - currentLevel, 1))
		totalGain += getRateStepGain(currentLevel) * chunk
		currentLevel += chunk
		remaining -= chunk
	end

	return totalGain
end

local function getRateBulkDiscount(amount: number, useMaxDiscount: boolean?): number
	return if useMaxDiscount then RATE_BULK_DISCOUNTS.Max or 0 else RATE_BULK_DISCOUNTS[amount] or 0
end

function Pricing.getRateUpgradePrice(rateLevel: number, amount: number?, useMaxDiscount: boolean?): number
	amount = amount or 1
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return 0
	end

	local totalPrice = getRateSequentialPrice(rateLevel, amount)

	local discount = getRateBulkDiscount(amount, useMaxDiscount)
	return math.max(math.floor(totalPrice * (1 - discount)), 0)
end

function Pricing.getMaxAffordableRateUpgrade(rateLevel: number, yen: number): (number, number, number)
	yen = math.max(yen or 0, 0)
	local nextPrice = Pricing.getRateUpgradePrice(rateLevel, 1, true)
	if nextPrice > yen then
		return 0, 0, 0
	end

	local low = 1
	local high = 1
	while high < MAX_RATE_BUY_AMOUNT and Pricing.getRateUpgradePrice(rateLevel, high, true) <= yen do
		low = high
		high = math.min(high * 2, MAX_RATE_BUY_AMOUNT)
		if high == low then
			break
		end
	end

	while low < high do
		local mid = math.ceil((low + high + 1) / 2)
		local price = Pricing.getRateUpgradePrice(rateLevel, mid, true)
		if price <= yen then
			low = mid
		else
			high = mid - 1
		end
	end

	local amount = low
	return amount, Pricing.getRateUpgradePrice(rateLevel, amount, true), Pricing.getRateGain(amount, rateLevel)
end

function Pricing.formatYen(amount: number): string
	return "¥" .. FormatUtil.formatNumber(amount)
end

return Pricing
