local AnimeDroppers = require(script.Parent.Parent.Parent.Data.AnimeDroppers)
local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)
local FormatUtil = require(script.Parent.FormatUtil)

local Pricing = {}
local RATE_GAIN_BASE = 2
local RATE_GAIN_STEP_SIZE = 2
local RATE_GAIN_STEP_POWER = 1.53
local RATE_PRICE_BASE = 5
local RATE_PRICE_LINEAR = 5
local RATE_PRICE_GROWTH = 1.22
local RATE_PRICE_GAIN_VALUE = 19
local MAX_UNIT_BUY_AMOUNT = 1e100
local MAX_RATE_BUY_AMOUNT = 10000
local UNIT_INCREMENT_SCALE_INTERVAL = 1_000_000_000

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

local function getSpawnTierPriceMultiplier(spawnTier: number?): number
	spawnTier = math.max(math.floor(tonumber(spawnTier) or 1), 1)
	local tierData = AnimeDroppers.Tiers[spawnTier]
	return math.max(math.floor(tonumber(tierData and tierData.RequiredTier1) or 1), 1)
end

function Pricing.getUnitPriceIncrement(unitScaleCount: number, spawnTier: number?): number
	local tierMultiplier = getSpawnTierPriceMultiplier(spawnTier)
	local scalingBonus = math.max(math.floor((tonumber(unitScaleCount) or 0) / UNIT_INCREMENT_SCALE_INTERVAL), 0)
	return TycoonConfig.UnitPriceIncrement * tierMultiplier + scalingBonus
end

function Pricing.getUnitPrice(purchaseCount: number, spawnTier: number?, unitScaleCount: number?): number
	local scaleCount = if unitScaleCount ~= nil then unitScaleCount else purchaseCount
	return TycoonConfig.UnitPriceBase + purchaseCount * Pricing.getUnitPriceIncrement(scaleCount, spawnTier)
end

local function getUnitBulkDiscount(amount: number, useMaxDiscount: boolean?): number
	return if useMaxDiscount then UNIT_BULK_DISCOUNTS.Max or 0 else UNIT_BULK_DISCOUNTS[amount] or 0
end

function Pricing.getUnitBulkPrice(
	purchaseCount: number,
	amount: number,
	useMaxDiscount: boolean?,
	spawnTier: number?,
	unitScaleCount: number?
): number
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return 0
	end

	local scaleCount = if unitScaleCount ~= nil then unitScaleCount else purchaseCount
	local increment = Pricing.getUnitPriceIncrement(scaleCount, spawnTier)
	local firstPrice = Pricing.getUnitPrice(purchaseCount, spawnTier, scaleCount)
	local totalPrice = amount * firstPrice + increment * amount * (amount - 1) / 2
	local discount = getUnitBulkDiscount(amount, useMaxDiscount)
	return math.max(math.floor(totalPrice * (1 - discount)), 0)
end

function Pricing.getMaxBaseUnitCapacity(): number
	return math.huge
end

function Pricing.getMaxAffordableUnitPurchase(
	purchaseCount: number,
	yen: number,
	maxAmount: number?,
	spawnTier: number?,
	unitScaleCount: number?
): (number, number)
	yen = math.max(yen or 0, 0)
	maxAmount = math.max(math.floor(tonumber(maxAmount) or MAX_UNIT_BUY_AMOUNT), 0)
	if yen <= 0 or maxAmount <= 0 then
		return 0, 0
	end

	local low = 0
	local high = 1
	while high < maxAmount do
		local price = Pricing.getUnitBulkPrice(purchaseCount, high, true, spawnTier, unitScaleCount)
		if price > yen or price == math.huge then
			break
		end

		low = high
		high = math.min(high * 2, maxAmount)
	end

	local iterations = 0
	while low < high and iterations < 512 do
		iterations += 1
		local mid = math.ceil((low + high + 1) / 2)
		if mid <= low then
			break
		end

		local price = Pricing.getUnitBulkPrice(purchaseCount, mid, true, spawnTier, unitScaleCount)
		if price <= yen then
			low = mid
		else
			high = mid - 1
		end
	end

	return low, Pricing.getUnitBulkPrice(purchaseCount, low, true, spawnTier, unitScaleCount)
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

function Pricing.getMaxAffordableRateUpgrade(
	rateLevel: number,
	yen: number,
	maxAmount: number?
): (number, number, number)
	yen = math.max(yen or 0, 0)
	maxAmount = math.max(math.floor(tonumber(maxAmount) or MAX_RATE_BUY_AMOUNT), 0)
	if maxAmount <= 0 then
		return 0, 0, 0
	end

	local nextPrice = Pricing.getRateUpgradePrice(rateLevel, 1, true)
	if nextPrice > yen then
		return 0, 0, 0
	end

	local low = 1
	local high = 1
	while high < maxAmount and Pricing.getRateUpgradePrice(rateLevel, high, true) <= yen do
		low = high
		high = math.min(high * 2, maxAmount)
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
