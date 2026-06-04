local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Knit = require(ReplicatedStorage.Packages.knit)

local MonetizationService = Knit.CreateService({
	Name = "MonetizationService",
	Client = {},
})

local gamePassCache: { [Player]: { [string]: boolean } } = {}

local function setCachedProductEntitlement(player: Player, entitlementKey: string)
	gamePassCache[player] = gamePassCache[player] or {}
	gamePassCache[player][entitlementKey] = true
	gamePassCache[player][entitlementKey .. "Product"] = true
end

function MonetizationService:GetEntitlements(player: Player): { [string]: boolean }
	local cached = gamePassCache[player]
	if cached then
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

		entitlements[key .. "GamePass"] = owns
		entitlements[key] = owns
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

function MonetizationService:KnitStart()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end

		for key, gamePass in Monetization.GamePasses do
			if gamePass.PassId == passId then
				gamePassCache[player] = gamePassCache[player] or {}
				gamePassCache[player][key] = true
				gamePassCache[player][key .. "GamePass"] = true
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
						if type(unit) ~= "table" or #nextUnits >= TycoonConfig.MaxUnits then
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
					for _, entitlementKey in product.Gamepasses do
						if type(entitlementKey) ~= "string" then
							continue
						end

						PlayerDataService:Set(player, { "PurchasedProducts", entitlementKey }, true)
						setCachedProductEntitlement(player, entitlementKey)
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
