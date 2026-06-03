local AnimeDroppers = require(script.Parent.Parent.Parent.Data.AnimeDroppers)
local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)
local FormatUtil = require(script.Parent.FormatUtil)

local Pricing = {}
local RATE_GAIN_BASE = 1
local RATE_GAIN_LINEAR = 0.9
local RATE_GAIN_POWER_SCALE = 0.24
local RATE_GAIN_EXPONENT = 1.95
local RATE_PRICE_BASE = 5
local RATE_PRICE_LINEAR = 4
local RATE_PRICE_POWER_SCALE = 1.9
local RATE_PRICE_EXPONENT = 2.35
local MAX_RATE_BUY_AMOUNT = 100_000_000

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

local function getPowerRangeSum(fromLevel: number, count: number, exponent: number): number
	if count <= 0 then
		return 0
	end

	if count == 1 then
		return (fromLevel + 1) ^ exponent
	end

	local first = fromLevel + 1
	local last = fromLevel + count
	local integral = (last ^ (exponent + 1) - first ^ (exponent + 1)) / (exponent + 1)
	local edgeAverage = (first ^ exponent + last ^ exponent) / 2
	return math.max(integral + edgeAverage, 0)
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

local function getRateSequentialPrice(rateLevel: number, amount: number): number
	if amount <= 0 then
		return 0
	end

	local firstLinear = rateLevel * RATE_PRICE_LINEAR
	local lastLinear = (rateLevel + amount - 1) * RATE_PRICE_LINEAR
	local linearTotal = getArithmeticSum(firstLinear, lastLinear, amount)
	local powerTotal = getPowerRangeSum(rateLevel, amount, RATE_PRICE_EXPONENT) * RATE_PRICE_POWER_SCALE
	return RATE_PRICE_BASE * amount + linearTotal + powerTotal
end

function Pricing.getRateGain(amount: number, rateLevel: number): number
	if amount <= 0 then
		return 0
	end

	amount = math.floor(amount)
	local firstLinear = rateLevel * RATE_GAIN_LINEAR
	local lastLinear = (rateLevel + amount - 1) * RATE_GAIN_LINEAR
	local linearTotal = getArithmeticSum(firstLinear, lastLinear, amount)
	local powerTotal = getPowerRangeSum(rateLevel, amount, RATE_GAIN_EXPONENT) * RATE_GAIN_POWER_SCALE
	local totalGain = RATE_GAIN_BASE * amount + linearTotal + powerTotal
	return math.max(math.floor(totalGain + 0.5), amount)
end

local function getRateBulkDiscount(amount: number, useMaxDiscount: boolean?): number
	return if useMaxDiscount then RATE_BULK_DISCOUNTS.Max or 0 else RATE_BULK_DISCOUNTS[amount] or 0
end

function Pricing.getRateUpgradePrice(rateLevel: number, amount: number?, useMaxDiscount: boolean?): number
	amount = amount or 1
	amount = math.max(math.floor(amount or 0), 0)
	if amount <= 0 then
		return 0
	end

	local totalPrice = getRateSequentialPrice(rateLevel, amount or 0)

	local discount = getRateBulkDiscount(amount or 0, useMaxDiscount)
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
