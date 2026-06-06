local AnimeDroppers = require(script.Parent.Parent.Parent.Data.AnimeDroppers)
local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)
local FormatUtil = require(script.Parent.FormatUtil)

local Pricing = {}
local RATE_GAIN_BASE = 2
local RATE_GAIN_STEP_SIZE = 2
local RATE_GAIN_STEP_POWER = 1.55
local RATE_PRICE_BASE = 5
local RATE_PRICE_LINEAR = 5
local RATE_PRICE_GROWTH = 1.2
local RATE_PRICE_GAIN_VALUE = 19
local MAX_UNIT_BUY_AMOUNT = 1e100
local MAX_RATE_BUY_AMOUNT = 10000

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
	return math.huge
end

function Pricing.getMaxAffordableUnitPurchase(baseUnitCount: number, yen: number): (number, number)
	yen = math.max(yen or 0, 0)
	if yen <= 0 then
		return 0, 0
	end

	local low = 0
	local high = 1
	while high < MAX_UNIT_BUY_AMOUNT do
		local price = Pricing.getUnitBulkPrice(baseUnitCount, high, true)
		if price > yen or price == math.huge then
			break
		end

		low = high
		high = math.min(high * 2, MAX_UNIT_BUY_AMOUNT)
	end

	local iterations = 0
	while low < high and iterations < 512 do
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

	local total = 0
	for offset = 1, amount do
		local nextLevel = rateLevel + offset
		if nextLevel == 1 then
			total += RATE_PRICE_BASE
			continue
		end

		local levelIndex = math.max(nextLevel - 1, 0)
		local gainStepIndex = math.floor(levelIndex / RATE_GAIN_STEP_SIZE)
		local gainAtLevel = math.max(math.floor(RATE_GAIN_BASE * (RATE_GAIN_STEP_POWER ^ gainStepIndex) + 0.5), 2)
		local stepPrice = RATE_PRICE_BASE + levelIndex * RATE_PRICE_LINEAR
		stepPrice = stepPrice * (RATE_PRICE_GROWTH ^ levelIndex) + gainAtLevel * RATE_PRICE_GAIN_VALUE
		total += math.ceil(stepPrice)
	end

	return total
end

function Pricing.getRateGain(amount: number, rateLevel: number): number
	if amount <= 0 then
		return 0
	end

	amount = math.floor(amount)
	local totalGain = 0
	for offset = 1, amount do
		local nextLevel = rateLevel + offset
		local stepIndex = math.floor((nextLevel - 1) / RATE_GAIN_STEP_SIZE)
		totalGain += math.max(math.floor(RATE_GAIN_BASE * (RATE_GAIN_STEP_POWER ^ stepIndex) + 0.5), 2)
	end

	return totalGain
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
