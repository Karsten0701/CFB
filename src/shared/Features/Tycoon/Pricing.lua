local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)
local FormatUtil = require(script.Parent.FormatUtil)

local Pricing = {}

function Pricing.getUnitPrice(totalPurchased: number): number
	return TycoonConfig.UnitPriceBase + totalPurchased * TycoonConfig.UnitPriceIncrement
end

function Pricing.getUnitBulkPrice(totalPurchased: number, amount: number): number
	return amount * Pricing.getUnitPrice(totalPurchased)
end

local function getRateStepGain(rateLevel: number): number
	return math.floor(rateLevel / 5) + 1
end

local function getSingleRateUpgradePrice(rateLevel: number): number
	local level = rateLevel + 1
	return math.floor(TycoonConfig.RateUpgradeBasePrice * (level ^ 1.12) * (1.025 ^ rateLevel))
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

	return totalPrice
end

function Pricing.formatYen(amount: number): string
	return "¥" .. FormatUtil.formatNumber(amount)
end

return Pricing
