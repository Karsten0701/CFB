local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local FormatUtil = require(script.Parent.Parent.Tycoon.FormatUtil)

local RobuxPriceUtil = {}

RobuxPriceUtil.ROBUX_ICON = ""
RobuxPriceUtil.OWNED_LABEL = "Owned"

local PRICE_CACHE_TTL = 120
local priceCache: { [string]: { Price: number, ExpiresAt: number } } = {}

local function getCacheKey(infoType: Enum.InfoType, assetId: number): string
	return `{infoType.Name}:{assetId}`
end

local function resolvePriceFromInfo(productInfo: any, hasPlus: boolean): number?
	local basePrice = tonumber(productInfo.PriceInRobux)
	if not basePrice then
		return nil
	end

	if hasPlus and type(productInfo.Discounts) == "table" then
		for _, discount in productInfo.Discounts do
			if discount.Type == "RobloxPlusSubscription" then
				local discounted = tonumber(discount.AmountInRobux)
				if discounted and discounted > 0 then
					return math.floor(discounted)
				end
			end
		end
	end

	return math.floor(basePrice)
end

function RobuxPriceUtil.formatPrice(robux: number?): string
	return RobuxPriceUtil.ROBUX_ICON .. FormatUtil.formatNumber(math.max(math.floor(tonumber(robux) or 0), 0))
end

function RobuxPriceUtil.formatOwnedLabel(): string
	return RobuxPriceUtil.OWNED_LABEL
end

function RobuxPriceUtil.getLocalHasPlus(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player.HasRobloxSubscription == true
end

function RobuxPriceUtil.getProductPriceAsync(productId: number, hasPlus: boolean?): number?
	local usePlus = if hasPlus ~= nil then hasPlus else RobuxPriceUtil.getLocalHasPlus()
	local cacheKey = getCacheKey(Enum.InfoType.Product, productId)
	local cached = priceCache[cacheKey]
	local now = os.clock()
	if cached and cached.ExpiresAt > now then
		return cached.Price
	end

	local ok, productInfo = pcall(function()
		return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
	end)
	if not ok or type(productInfo) ~= "table" then
		return nil
	end

	local price = resolvePriceFromInfo(productInfo, usePlus)
	if price then
		priceCache[cacheKey] = {
			Price = price,
			ExpiresAt = now + PRICE_CACHE_TTL,
		}
	end

	return price
end

function RobuxPriceUtil.getGamePassPriceAsync(passId: number, hasPlus: boolean?): number?
	local usePlus = if hasPlus ~= nil then hasPlus else RobuxPriceUtil.getLocalHasPlus()
	local cacheKey = getCacheKey(Enum.InfoType.GamePass, passId)
	local cached = priceCache[cacheKey]
	local now = os.clock()
	if cached and cached.ExpiresAt > now then
		return cached.Price
	end

	local ok, productInfo = pcall(function()
		return MarketplaceService:GetProductInfoAsync(passId, Enum.InfoType.GamePass)
	end)
	if not ok or type(productInfo) ~= "table" then
		return nil
	end

	local price = resolvePriceFromInfo(productInfo, usePlus)
	if price then
		priceCache[cacheKey] = {
			Price = price,
			ExpiresAt = now + PRICE_CACHE_TTL,
		}
	end

	return price
end

function RobuxPriceUtil.invalidateCache()
	table.clear(priceCache)
end

return RobuxPriceUtil
