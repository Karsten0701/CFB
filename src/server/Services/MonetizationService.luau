local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local Knit = require(ReplicatedStorage.Packages.knit)

local MonetizationService = Knit.CreateService({
	Name = "MonetizationService",
	Client = {},
})

local gamePassCache: { [Player]: { [string]: boolean } } = {}
local GAMEPASS_BACKED_SETTINGS = {
	AutoCollect = true,
	AutoDeposit = true,
}

local function setCachedProductEntitlement(player: Player, entitlementKey: string)
	gamePassCache[player] = gamePassCache[player] or {}
	gamePassCache[player][entitlementKey] = true
	gamePassCache[player][entitlementKey .. "Product"] = true
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

function MonetizationService:GetEntitlements(player: Player): { [string]: boolean }
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
	local entitlements = self:GetEntitlements(player)
	return entitlements[gamePassKey] == true
end

function MonetizationService:OwnsGamePassOnly(player: Player, gamePassKey: string): boolean
	local entitlements = self:GetEntitlements(player)
	return entitlements[gamePassKey .. "GamePass"] == true
end

function MonetizationService:OwnsProductEntitlement(player: Player, entitlementKey: string): boolean
	local entitlements = self:GetEntitlements(player)
	return entitlements[entitlementKey .. "Product"] == true
end

function MonetizationService:InvalidateEntitlementCache(player: Player)
	gamePassCache[player] = nil
end

function MonetizationService:AdminGrantGamePass(player: Player, gamePassKey: string): boolean
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

	if product.Kind == "StarterPack" then
		if PlayerDataService:Get(player, { "PurchasedProducts", product.Key }) == true then
			return true, nil
		end
	end

	local TycoonService = Knit.GetService("TycoonService")
	if product.Kind == "Units" then
		if not TycoonService:GrantUnits(player, product.Amount) then
			return false, "grant_units_failed"
		end
	elseif product.Kind == "SellAll" then
		TycoonService:SellAllProcessor(player)
	elseif product.Kind == "OpenCapsule" then
		if not TycoonService:OpenPendingCapsulePurchase(player) then
			return false, "open_capsule_failed"
		end
	elseif product.Kind == "StarterPack" then
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
					self:AdminGrantGamePass(player, gamePassKey)
				end
			end
		end

		PlayerDataService:Set(player, { "PurchasedProducts", product.Key }, true)
	else
		return false, "unsupported_product_kind"
	end

	if product.Kind ~= "OneTimeEntitlement" and product.Key then
		PlayerDataService:Set(player, { "PurchasedProducts", product.Key }, true)
	end

	self:InvalidateEntitlementCache(player)
	return true, nil
end

function MonetizationService:KnitStart()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
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

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		gamePassCache[player] = nil
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = game:GetService("Players"):GetPlayerByUserId(receiptInfo.PlayerId)
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

		local TycoonService = Knit.GetService("TycoonService")
		local success = false

		if product.Kind == "Units" then
			success = TycoonService:GrantUnits(player, product.Amount)
		elseif product.Kind == "SellAll" then
			TycoonService:SellAllProcessor(player)
			success = true
		elseif product.Kind == "OneTimeEntitlement" and product.EntitlementKey then
			PlayerDataService:Set(player, { "PurchasedProducts", product.EntitlementKey }, true)
			setCachedProductEntitlement(player, product.EntitlementKey)
			success = true
		elseif product.Kind == "OpenCapsule" then
			success = TycoonService:OpenPendingCapsulePurchase(player)
		elseif product.Kind == "StarterPack" then
			if PlayerDataService:Get(player, { "PurchasedProducts", product.Key }) == true then
				success = true
			else
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
						if type(gamePassKey) ~= "string" then
							continue
						end

						PlayerDataService:Set(player, { "GrantedGamePasses", gamePassKey }, true)
						setCachedGamePassEntitlement(player, gamePassKey)
						enablePurchasedGamePassSetting(player, gamePassKey)
					end
				end

				PlayerDataService:Set(player, { "PurchasedProducts", product.Key }, true)
				success = true
			end
		end

		if not success then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		PlayerDataService:Set(player, receiptPath, true)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

function MonetizationService.Client:GetEntitlements(player: Player)
	return self.Server:GetEntitlements(player)
end

return MonetizationService
