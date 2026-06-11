local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local PotionConfig = require(ReplicatedStorage.Shared.Data.PotionConfig)
local Knit = require(ReplicatedStorage.Packages.knit)

local MonetizationService = Knit.CreateService({
	Name = "MonetizationService",
	Client = {},
})

local gamePassCache: { [Player]: { [string]: boolean } } = {}
local pendingGifts: { [Player]: { RecipientUserId: number, GiftProductKey: string }? } = {}

local GAMEPASS_BACKED_SETTINGS = {
	AutoCollect = true,
	AutoDeposit = true,
}

local GIFT_KIND_TO_GAMEPASS = {
	GiftAutoCollect = "AutoCollect",
	GiftAutoDeposit = "AutoDeposit",
	GiftDoubleYen = "DoubleYen",
	GiftDoubleDropSpeed = "DoubleDropSpeed",
	GiftDoubleMana = "DoubleMana",
	GiftDoubleDeposit = "DoubleDeposit",
}

local function setCachedProductEntitlement(player: Player, entitlementKey: string)
	gamePassCache[player] = gamePassCache[player] or {}
	gamePassCache[player][entitlementKey] = true
	gamePassCache[player][entitlementKey .. "Product"] = true
end

local function isMonetizationEnabled(): boolean
	return Monetization.isEnabled()
end

local function setCachedGamePassEntitlement(player: Player, gamePassKey: string)
	gamePassCache[player] = gamePassCache[player] or {}
	gamePassCache[player][gamePassKey] = true
	gamePassCache[player][gamePassKey .. "GamePass"] = true
end

local function enablePurchasedGamePassSetting(player: Player, gamePassKey: string)
	if not GAMEPASS_BACKED_SETTINGS[gamePassKey] then
		return
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	PlayerDataService:Set(player, { "Settings", "GamePassSettingDisabled", gamePassKey }, false)
	PlayerDataService:Set(player, { "Settings", gamePassKey }, true)
end

local function enableOwnedGamePassSettingIfAllowed(player: Player, gamePassKey: string)
	if not GAMEPASS_BACKED_SETTINGS[gamePassKey] then
		return
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	if PlayerDataService:Get(player, { "Settings", "GamePassSettingDisabled", gamePassKey }) == true then
		return
	end

	if PlayerDataService:Get(player, { "Settings", gamePassKey }) ~= true then
		PlayerDataService:Set(player, { "Settings", gamePassKey }, true)
	end
end

local function grantStarterPackToPlayer(service: any, player: Player, product): boolean
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if PlayerDataService:Get(player, { "PurchasedProducts", product.Key }) == true then
		return true
	end

	local currentUnits = PlayerDataService:GetUnits(player)
	local nextUnits = table.clone(currentUnits)
	if type(product.Units) == "table" then
		for _, unit in product.Units do
			if type(unit) ~= "table" then
				continue
			end

			table.insert(nextUnits, {
				Tier = unit.Tier or 1,
			})
		end
	end

	if #nextUnits ~= #currentUnits then
		PlayerDataService:SetUnits(player, nextUnits)
	end

	if type(product.Yen) == "number" and product.Yen > 0 then
		PlayerDataService:AddYen(player, product.Yen)
	end

	if type(product.Gamepasses) == "table" then
		for _, gamePassKey in product.Gamepasses do
			if type(gamePassKey) == "string" then
				service:AdminGrantGamePass(player, gamePassKey)
			end
		end
	end

	PlayerDataService:Set(player, { "PurchasedProducts", product.Key }, true)
	return true
end

local function grantAllGamePasses(service: any, player: Player): boolean
	for gamePassKey in Monetization.GamePasses do
		service:AdminGrantGamePass(player, gamePassKey)
	end
	return true
end

local function grantPotionProduct(player: Player, product): boolean
	local PotionService = Knit.GetService("PotionService")

	if product.Kind == "PotionBundle" then
		return PotionService:AddPotionsFromBundle(player, product.Amount or 10)
	end

	local potionType = product.PotionType or PotionConfig.getTypeFromProductKind(product.Kind)
	if not potionType then
		return false
	end

	return PotionService:AddPotions(player, potionType, product.Amount or 1)
end

local function grantGiftProduct(service: any, buyer: Player, product): boolean
	local pending = pendingGifts[buyer]
	if not pending then
		return false
	end

	if pending.GiftProductKey ~= product.Key then
		return false
	end

	local recipient = Players:GetPlayerByUserId(pending.RecipientUserId)
	if not recipient then
		return false
	end

	local success = false
	local gamePassKey = GIFT_KIND_TO_GAMEPASS[product.Kind]
	if gamePassKey then
		success = service:AdminGrantGamePass(recipient, gamePassKey)
	elseif product.Kind == "GiftStarterPack" then
		local starterPack = Monetization.DeveloperProducts.StarterPack
		success = starterPack ~= nil and grantStarterPackToPlayer(service, recipient, starterPack)
	elseif product.Kind == "GiftPotionBundle" then
		local PotionService = Knit.GetService("PotionService")
		success = PotionService:AddPotionsFromBundle(recipient, product.Amount or 10)
	elseif product.Kind == "GiftGamepassBundle" then
		success = grantAllGamePasses(service, recipient)
	end

	if success then
		pendingGifts[buyer] = nil
		service:InvalidateEntitlementCache(recipient)
	end

	return success
end

local function playerOwnsGiftTarget(service: any, player: Player, giftProductKey: string): boolean
	local target = Monetization.GiftTargets[giftProductKey]
	if not target then
		return true
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if target.Type == "GamePass" and type(target.Key) == "string" then
		return service:OwnsGamePass(player, target.Key)
	end

	if target.Type == "Product" and type(target.Key) == "string" then
		return PlayerDataService:Get(player, { "PurchasedProducts", target.Key }) == true
	end

	if target.Type == "GamepassBundle" then
		if PlayerDataService:Get(player, { "PurchasedProducts", "GamepassBundle" }) == true then
			return true
		end

		for gamePassKey in Monetization.GamePasses do
			if not service:OwnsGamePass(player, gamePassKey) then
				return false
			end
		end

		return true
	end

	if target.Type == "PotionBundle" then
		return false
	end

	return false
end

local function processStandardProduct(service: any, player: Player, product): boolean
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local TycoonService = Knit.GetService("TycoonService")

	if product.Kind == "Units" then
		return TycoonService:GrantUnits(player, product.Amount)
	end

	if product.Kind == "SellAll" then
		TycoonService:SellAllProcessor(player)
		return true
	end

	if product.Kind == "OneTimeEntitlement" and product.EntitlementKey then
		PlayerDataService:Set(player, { "PurchasedProducts", product.EntitlementKey }, true)
		setCachedProductEntitlement(player, product.EntitlementKey)
		return true
	end

	if product.Kind == "OpenCapsule" then
		return TycoonService:OpenPendingCapsulePurchase(player)
	end

	if product.Kind == "Offline5xReward" then
		local granted, reward = TycoonService:ClaimOffline5xReward(player)
		return granted and (reward or 0) > 0
	end

	if product.Kind == "StarterPack" then
		return grantStarterPackToPlayer(service, player, product)
	end

	if product.Kind == "GamepassBundle" then
		if PlayerDataService:Get(player, { "PurchasedProducts", product.Key }) == true then
			return true
		end

		if not grantAllGamePasses(service, player) then
			return false
		end

		PlayerDataService:Set(player, { "PurchasedProducts", product.Key }, true)
		return true
	end

	if
		product.Kind == "PotionYen"
		or product.Kind == "PotionMana"
		or product.Kind == "PotionDeposit"
		or product.Kind == "PotionBundle"
	then
		return grantPotionProduct(player, product)
	end

	if string.sub(product.Kind, 1, 4) == "Gift" then
		return grantGiftProduct(service, player, product)
	end

	return false
end

function MonetizationService:GetEntitlements(player: Player): { [string]: boolean }
	if not isMonetizationEnabled() then
		return {}
	end

	local cached = gamePassCache[player]
	if cached then
		for gamePassKey in GAMEPASS_BACKED_SETTINGS do
			if cached[gamePassKey] == true then
				enableOwnedGamePassSettingIfAllowed(player, gamePassKey)
			end
		end

		return cached
	end

	local entitlements = {}
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	for key, gamePass in Monetization.GamePasses do
		local owns = false
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePass.PassId)
		end)

		if ok then
			owns = result == true
		else
			warn("[MonetizationService] Gamepass ownership check failed:", key, result)
		end

		owns = owns or PlayerDataService:Get(player, { "GrantedGamePasses", key }) == true
		entitlements[key .. "GamePass"] = owns
		entitlements[key] = owns
		if owns then
			enableOwnedGamePassSettingIfAllowed(player, key)
		end
	end

	for _, product in Monetization.DeveloperProducts do
		if product.Kind == "OneTimeEntitlement" and product.EntitlementKey then
			local ownsProduct = PlayerDataService:Get(player, { "PurchasedProducts", product.EntitlementKey }) == true
			entitlements[product.EntitlementKey .. "Product"] = ownsProduct
			entitlements[product.EntitlementKey] = entitlements[product.EntitlementKey] == true or ownsProduct
		end
	end

	gamePassCache[player] = entitlements
	return entitlements
end

function MonetizationService:OwnsGamePass(player: Player, gamePassKey: string): boolean
	if not isMonetizationEnabled() then
		return false
	end

	local entitlements = self:GetEntitlements(player)
	return entitlements[gamePassKey] == true
end

function MonetizationService:OwnsGamePassOnly(player: Player, gamePassKey: string): boolean
	if not isMonetizationEnabled() then
		return false
	end

	local entitlements = self:GetEntitlements(player)
	return entitlements[gamePassKey .. "GamePass"] == true
end

function MonetizationService:OwnsProductEntitlement(player: Player, entitlementKey: string): boolean
	if not isMonetizationEnabled() then
		return false
	end

	local entitlements = self:GetEntitlements(player)
	return entitlements[entitlementKey .. "Product"] == true
end

function MonetizationService:InvalidateEntitlementCache(player: Player)
	gamePassCache[player] = nil
end

function MonetizationService:PrepareGift(
	buyer: Player,
	recipientUserId: number,
	giftProductKey: string
): (boolean, string?)
	if not isMonetizationEnabled() then
		return false, "monetization_disabled"
	end

	recipientUserId = math.floor(tonumber(recipientUserId) or 0)
	if recipientUserId <= 0 or recipientUserId == buyer.UserId then
		return false, "invalid_recipient"
	end

	local giftProduct = Monetization.DeveloperProducts[giftProductKey]
	if not giftProduct or string.sub(giftProductKey, 1, 4) ~= "Gift" then
		return false, "invalid_gift_product"
	end

	local recipient = Players:GetPlayerByUserId(recipientUserId)
	if not recipient then
		return false, "recipient_not_in_server"
	end

	if playerOwnsGiftTarget(self, recipient, giftProductKey) then
		return false, "recipient_already_owns"
	end

	pendingGifts[buyer] = {
		RecipientUserId = recipientUserId,
		GiftProductKey = giftProductKey,
	}
	return true, nil
end

function MonetizationService:CancelGift(buyer: Player)
	pendingGifts[buyer] = nil
end

function MonetizationService:GetGiftEligiblePlayers(buyer: Player, giftProductKey: string): { { UserId: number, Name: string, DisplayName: string } }
	local results = {}
	if not isMonetizationEnabled() then
		return results
	end

	local giftProduct = Monetization.DeveloperProducts[giftProductKey]
	if not giftProduct then
		return results
	end

	for _, player in Players:GetPlayers() do
		if player == buyer then
			continue
		end

		if playerOwnsGiftTarget(self, player, giftProductKey) then
			continue
		end

		table.insert(results, {
			UserId = player.UserId,
			Name = player.Name,
			DisplayName = player.DisplayName,
		})
	end

	table.sort(results, function(a, b)
		return a.DisplayName < b.DisplayName
	end)

	return results
end

function MonetizationService:AdminGrantGamePass(player: Player, gamePassKey: string): boolean
	if not isMonetizationEnabled() then
		return false
	end

	if not Monetization.GamePasses[gamePassKey] then
		return false
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	PlayerDataService:Set(player, { "GrantedGamePasses", gamePassKey }, true)
	setCachedGamePassEntitlement(player, gamePassKey)
	enablePurchasedGamePassSetting(player, gamePassKey)
	return true
end

function MonetizationService:AdminRevokeGamePass(player: Player, gamePassKey: string): boolean
	if not Monetization.GamePasses[gamePassKey] then
		return false
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	PlayerDataService:Set(player, { "GrantedGamePasses", gamePassKey }, false)
	self:InvalidateEntitlementCache(player)
	return true
end

function MonetizationService:AdminGrantProduct(player: Player, productKey: string): (boolean, string?)
	if not isMonetizationEnabled() then
		return false, "monetization_disabled"
	end

	local product = Monetization.DeveloperProducts[productKey]
	if not product then
		return false, "unknown_product"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if product.Kind == "OneTimeEntitlement" and product.EntitlementKey then
		if PlayerDataService:Get(player, { "PurchasedProducts", product.EntitlementKey }) == true then
			return true, nil
		end

		PlayerDataService:Set(player, { "PurchasedProducts", product.EntitlementKey }, true)
		setCachedProductEntitlement(player, product.EntitlementKey)
		return true, nil
	end

	local success = processStandardProduct(self, player, product)
	if not success then
		return false, "unsupported_product_kind"
	end

	if product.Kind ~= "OneTimeEntitlement" and product.Key then
		if
			product.Kind ~= "StarterPack"
			and product.Kind ~= "PotionYen"
			and product.Kind ~= "PotionMana"
			and product.Kind ~= "PotionDeposit"
			and product.Kind ~= "PotionBundle"
			and product.Kind ~= "GamepassBundle"
		then
			PlayerDataService:Set(player, { "PurchasedProducts", product.Key }, true)
		end
	end

	self:InvalidateEntitlementCache(player)
	return true, nil
end

function MonetizationService:KnitStart()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not isMonetizationEnabled() then
			return
		end

		if not wasPurchased then
			return
		end

		for key, gamePass in Monetization.GamePasses do
			if gamePass.PassId == passId then
				setCachedGamePassEntitlement(player, key)
				enablePurchasedGamePassSetting(player, key)
				break
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		gamePassCache[player] = nil
		pendingGifts[player] = nil
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		if not isMonetizationEnabled() then
			warn("[MonetizationService] Product receipt ignored because monetization is disabled:", receiptInfo.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local product = Monetization.ProductsById[receiptInfo.ProductId]
		if not product then
			warn("[MonetizationService] Unknown product receipt:", receiptInfo.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local PlayerDataService = Knit.GetService("PlayerDataService")
		PlayerDataService:WaitForData(player)

		local receiptPath = { "ProcessedReceipts", tostring(receiptInfo.PurchaseId) }
		if PlayerDataService:Get(player, receiptPath) == true then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local success = processStandardProduct(self, player, product)
		if not success then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if product.Kind ~= "OneTimeEntitlement" and product.Key then
			if
				product.Kind ~= "StarterPack"
				and product.Kind ~= "PotionYen"
				and product.Kind ~= "PotionMana"
				and product.Kind ~= "PotionDeposit"
				and product.Kind ~= "PotionBundle"
				and product.Kind ~= "GamepassBundle"
				and string.sub(product.Kind, 1, 4) ~= "Gift"
			then
				PlayerDataService:Set(player, { "PurchasedProducts", product.Key }, true)
			end
		end

		PlayerDataService:Set(player, receiptPath, true)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

function MonetizationService.Client:GetEntitlements(player: Player)
	return self.Server:GetEntitlements(player)
end

function MonetizationService.Client:PrepareGift(player: Player, recipientUserId: number, giftProductKey: string)
	return self.Server:PrepareGift(player, recipientUserId, giftProductKey)
end

function MonetizationService.Client:CancelGift(player: Player)
	self.Server:CancelGift(player)
end

function MonetizationService.Client:GetGiftEligiblePlayers(player: Player, giftProductKey: string)
	return self.Server:GetGiftEligiblePlayers(player, giftProductKey)
end

return MonetizationService
