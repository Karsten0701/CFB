local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local PotionConfig = require(ReplicatedStorage.Shared.Data.PotionConfig)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local RobuxPriceUtil = require(ReplicatedStorage.Shared.Features.Monetization.RobuxPriceUtil)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local Knit = require(ReplicatedStorage.Packages.knit)
local GiftFeature = require(script.Parent.Gift)

local Shop = {}

local localPlayer = Players.LocalPlayer
local DOUBLE_YEN_PRODUCT = Monetization.DeveloperProducts.DoubleYen
local STARTER_PACK_PRODUCT = Monetization.DeveloperProducts.StarterPack
local POTION_BUNDLE_PRODUCT = Monetization.DeveloperProducts.PotionBundle
local GAMEPASS_BUNDLE_PRODUCT = Monetization.DeveloperProducts.GamepassBundle

local doubleYenClickConnection: RBXScriptConnection? = nil
local doubleYenPromptOpen = false
local doubleYenOfferCache: GuiObject? = nil
local doubleYenOfferScannedGui: Instance? = nil
local shopConnections: { RBXScriptConnection } = {}
local gamePassPromptOpen = false
local shopProductPromptOpen = false

local SHOP_GAMEPASS_ALIASES = {
	AutoCollect = "AutoCollect",
	AutoDeposit = "AutoDeposit",
	DoubleCoins = "DoubleYen",
	DoubleYen = "DoubleYen",
	DoubleDepoSpeed = "DoubleDeposit",
	DoubleDeposit = "DoubleDeposit",
	DoubleDropSpeed = "DoubleDropSpeed",
	DoubleMana = "DoubleMana",
}

local BOOST_UI_TO_POTION_TYPE = {
	Yen = "Yen",
	Mana = "Mana",
	Deposit = "Deposit",
}

local SHOP_PRODUCT_KEYS = {
	StarterPack = { Key = "StarterPack", ShowOwned = true },
	PotionBundle = { Key = "PotionBundle", ShowOwned = false },
	GamepassBundle = { Key = "GamepassBundle", ShowOwned = true },
}

local function getGamePassKeyFromId(gamePassId: number): string?
	for key, gamePass in Monetization.GamePasses do
		if gamePass.PassId == gamePassId then
			return key
		end
	end

	return nil
end

local function isLocalProductPromptFinished(firstArg: any): boolean
	if firstArg == localPlayer then
		return true
	end

	if type(firstArg) == "number" then
		return firstArg == localPlayer.UserId
	end

	return false
end

local function findRobuxPriceLabel(root: Instance): TextLabel?
	local label = root:FindFirstChild("RobuxPrice", true)
	if label and label:IsA("TextLabel") then
		return label
	end

	local buyButton = root:FindFirstChild("BuyButton", true)
	if buyButton then
		label = buyButton:FindFirstChild("RobuxPrice", true)
		if label and label:IsA("TextLabel") then
			return label
		end
	end

	return nil
end

local function findBuyButton(root: GuiObject): GuiObject?
	local buyButton = root:FindFirstChild("BuyButton", true)
	if buyButton and buyButton:IsA("GuiObject") then
		return buyButton
	end

	return root
end

local function setBuyButtonOwnedState(buyButton: GuiObject?, owned: boolean)
	if not buyButton then
		return
	end

	if buyButton:IsA("GuiButton") then
		buyButton.Active = not owned
		buyButton.AutoButtonColor = not owned
	end
end

local function updateRobuxPriceLabel(label: TextLabel, text: string)
	label.Text = text
end

function Shop.Install(MainGuiController)
	GiftFeature.Install(MainGuiController)

	local function getEntitlements(controller): { [string]: boolean }
		return controller:getSettingsEntitlements()
	end

	local function ownsShopGamePass(controller, gamePassKey: string): boolean
		if getEntitlements(controller)[gamePassKey .. "GamePass"] == true then
			return true
		end

		if getEntitlements(controller)[gamePassKey] == true then
			return true
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		if PlayerDataController:Get({ "GrantedGamePasses", gamePassKey }) == true then
			return true
		end

		return false
	end

	local function ownsDoubleYenProduct(): boolean
		local PlayerDataController = Knit.GetController("PlayerDataController")
		return PlayerDataController:Get({ "PurchasedProducts", "DoubleYen" }) == true
	end

	local function ownsOneTimeProduct(productKey: string): boolean
		local PlayerDataController = Knit.GetController("PlayerDataController")
		return PlayerDataController:Get({ "PurchasedProducts", productKey }) == true
	end

	local function refreshGamePassPrice(controller, itemRoot: GuiObject, gamePassKey: string)
		local gamePass = Monetization.GamePasses[gamePassKey]
		if not gamePass then
			return
		end

		local priceLabel = findRobuxPriceLabel(itemRoot)
		local buyButton = findBuyButton(itemRoot)
		local owned = ownsShopGamePass(controller, gamePassKey)

		if owned then
			if priceLabel then
				updateRobuxPriceLabel(priceLabel, RobuxPriceUtil.formatOwnedLabel())
			end
			setBuyButtonOwnedState(buyButton, true)
			return
		end

		setBuyButtonOwnedState(buyButton, false)
		task.spawn(function()
			local price = RobuxPriceUtil.getGamePassPriceAsync(gamePass.PassId)
			if not priceLabel or not priceLabel.Parent then
				return
			end

			if ownsShopGamePass(controller, gamePassKey) then
				updateRobuxPriceLabel(priceLabel, RobuxPriceUtil.formatOwnedLabel())
				setBuyButtonOwnedState(buyButton, true)
				return
			end

			updateRobuxPriceLabel(priceLabel, RobuxPriceUtil.formatPrice(price or gamePass.Price))
		end)
	end

	local function refreshDevProductPrice(itemRoot: GuiObject, productKey: string, showOwned: boolean)
		local product = Monetization.DeveloperProducts[productKey]
		if not product then
			return
		end

		local priceLabel = findRobuxPriceLabel(itemRoot)
		local buyButton = findBuyButton(itemRoot)
		local owned = showOwned and ownsOneTimeProduct(productKey)

		if owned then
			if priceLabel then
				updateRobuxPriceLabel(priceLabel, RobuxPriceUtil.formatOwnedLabel())
			end
			setBuyButtonOwnedState(buyButton, true)
			return
		end

		setBuyButtonOwnedState(buyButton, false)
		task.spawn(function()
			local price = RobuxPriceUtil.getProductPriceAsync(product.ProductId)
			if not priceLabel or not priceLabel.Parent then
				return
			end

			if showOwned and ownsOneTimeProduct(productKey) then
				updateRobuxPriceLabel(priceLabel, RobuxPriceUtil.formatOwnedLabel())
				setBuyButtonOwnedState(buyButton, true)
				return
			end

			updateRobuxPriceLabel(priceLabel, RobuxPriceUtil.formatPrice(price or product.Price))
		end)
	end

	local function refreshPotionBoostUi(itemRoot: GuiObject, potionType: string)
		local ownedAmount = itemRoot:FindFirstChild("OwnedAmount", true)
		if not ownedAmount or not ownedAmount:IsA("TextLabel") then
			return
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		local amount = math.max(math.floor(PlayerDataController:Get({ "Potions", potionType }) or 0), 0)
		ownedAmount.Text = `You own: {amount}`

		local productKey = PotionConfig.ProductKeyByType[potionType]
		if productKey then
			refreshDevProductPrice(itemRoot, productKey, false)
		end
	end

	function MainGuiController:getShopFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local shopFrame = mainGui:FindFirstChild("ShopFrame")
		return if shopFrame and shopFrame:IsA("GuiObject") then shopFrame else nil
	end

	function MainGuiController:getDoubleYenOfferRootFromDescendant(mainGui: Instance, descendant: Instance): GuiObject?
		local current = descendant
		while current and current.Parent and current.Parent ~= mainGui do
			if current.Parent.Name == "RightSide" and current:IsA("GuiObject") then
				return current
			end

			current = current.Parent
		end

		return if current and current:IsA("GuiObject") and current ~= mainGui then current else nil
	end

	function MainGuiController:isDoubleYenCandidate(instance: Instance): boolean
		if
			instance:GetAttribute("ProductId") == DOUBLE_YEN_PRODUCT.ProductId
			or instance:GetAttribute("DevProductId") == DOUBLE_YEN_PRODUCT.ProductId
		then
			return true
		end

		local normalizedName = string.lower(string.gsub(instance.Name, "%s+", "") or "")
		if normalizedName == "doubleyen" or normalizedName == "2xyen" or normalizedName == "yen2x" then
			return true
		end

		if instance.Name == "Amount" and instance:IsA("TextLabel") then
			local normalizedText = string.lower(string.gsub(instance.Text, "%s+", "") or "")
			return string.find(normalizedText, "2xyen", 1, true) ~= nil
		end

		return false
	end

	function MainGuiController:getDoubleYenOffer(): GuiObject?
		if doubleYenOfferCache and doubleYenOfferCache.Parent then
			return doubleYenOfferCache
		end

		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end
		if doubleYenOfferScannedGui == mainGui then
			return nil
		end

		for _, descendant in mainGui:GetDescendants() do
			if self:isDoubleYenCandidate(descendant) then
				local root = self:getDoubleYenOfferRootFromDescendant(mainGui, descendant)
				if root then
					doubleYenOfferCache = root
					return root
				end
			end
		end

		local rightSide = mainGui:FindFirstChild("RightSide")
		if rightSide then
			for _, descendant in rightSide:GetDescendants() do
				if descendant.Name == "Amount" and descendant:IsA("TextLabel") then
					local root = self:getDoubleYenOfferRootFromDescendant(mainGui, descendant)
					if root then
						doubleYenOfferCache = root
						return root
					end
				end
			end
		end

		doubleYenOfferScannedGui = mainGui
		return nil
	end

	function MainGuiController:clearShopConnections()
		for _, connection in shopConnections do
			connection:Disconnect()
		end

		table.clear(shopConnections)
	end

	function MainGuiController:connectShopButton(buttonRoot: GuiObject, gamePassKey: string)
		local gamePass = Monetization.GamePasses[gamePassKey]
		if not gamePass or type(gamePass.PassId) ~= "number" or gamePass.PassId <= 0 then
			return
		end

		refreshGamePassPrice(self, buttonRoot, gamePassKey)

		local clickable = self:getClickableGui(findBuyButton(buttonRoot))
		local function prompt()
			if gamePassPromptOpen then
				return
			end

			if ownsShopGamePass(self, gamePassKey) then
				self:ShowAlreadyOwnGamePassMessage()
				return
			end

			gamePassPromptOpen = true
			local MonetizationService = Knit.GetService("MonetizationService")
			MonetizationService:GetEntitlements()
				:andThen(function(entitlements)
					self:setSettingsEntitlements(entitlements or {})
					self:refreshGamePassSettings()

					if ownsShopGamePass(self, gamePassKey) then
						gamePassPromptOpen = false
						self:ShowAlreadyOwnGamePassMessage()
						refreshGamePassPrice(self, buttonRoot, gamePassKey)
						return
					end

					local ok, err = pcall(function()
						MarketplaceService:PromptGamePassPurchase(localPlayer, gamePass.PassId)
					end)

					if not ok then
						gamePassPromptOpen = false
						warn("[MainGuiController] Gamepass prompt failed:", err)
					end
				end)
				:catch(function(err)
					gamePassPromptOpen = false
					warn("[MainGuiController] Failed to check gamepass ownership:", err)
				end)
		end

		if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
			table.insert(shopConnections, clickable.Activated:Connect(prompt))
		else
			table.insert(
				shopConnections,
				clickable.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						prompt()
					end
				end)
			)
		end
	end

	function MainGuiController:connectDevProductButton(buttonRoot: GuiObject, productKey: string, showOwned: boolean)
		local product = Monetization.DeveloperProducts[productKey]
		if not product or type(product.ProductId) ~= "number" then
			return
		end

		refreshDevProductPrice(buttonRoot, productKey, showOwned)

		self:connectGuiActivated(findBuyButton(buttonRoot), function()
			if shopProductPromptOpen then
				return
			end

			if showOwned and ownsOneTimeProduct(productKey) then
				if productKey == "StarterPack" then
					self:ShowAlreadyPurchasedStarterPackMessage()
				elseif productKey == "GamepassBundle" then
					self:ShowAlreadyOwnGamePassMessage()
				end
				return
			end

			shopProductPromptOpen = true
			local ok, err = pcall(function()
				MarketplaceService:PromptProductPurchase(localPlayer, product.ProductId)
			end)

			if not ok then
				shopProductPromptOpen = false
				warn("[MainGuiController] Product prompt failed:", productKey, err)
			end
		end)
	end

	function MainGuiController:connectPotionBoostButton(buttonRoot: GuiObject, potionType: string)
		local productKey = PotionConfig.ProductKeyByType[potionType]
		if not productKey then
			return
		end

		refreshPotionBoostUi(buttonRoot, potionType)

		local buyButton = buttonRoot:FindFirstChild("BuyButton", true)
		if buyButton and buyButton:IsA("GuiObject") then
			self:connectDevProductButton(buttonRoot, productKey, false)
		end

		local useButton = buttonRoot:FindFirstChild("UseButton", true)
		if useButton and useButton:IsA("GuiObject") then
			self:connectGuiActivated(useButton, function()
				local PotionService = Knit.GetService("PotionService")
				PotionService:UsePotion(potionType)
					:andThen(function(success: boolean, err: string?)
						if success then
							refreshPotionBoostUi(buttonRoot, potionType)
							self:refreshEventFeature()
							return
						end
					end)
					:catch(function(err)
						warn("[MainGuiController] UsePotion error:", err)
					end)
			end)
		end
	end

	function MainGuiController:connectGuiActivated(guiObject: GuiObject, callback: () -> ())
		local clickable = self:getClickableGui(guiObject)
		if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
			table.insert(shopConnections, clickable.Activated:Connect(callback))
		else
			table.insert(
				shopConnections,
				clickable.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						callback()
					end
				end)
			)
		end
	end

	function MainGuiController:refreshShopPrices()
		local shopFrame = self:getShopFrame()
		local scrollingFrame = shopFrame and shopFrame:FindFirstChild("ScrollingFrame")
		if not scrollingFrame then
			return
		end

		for buttonName, gamePassKey in SHOP_GAMEPASS_ALIASES do
			local buttonRoot = scrollingFrame:FindFirstChild(buttonName)
			if buttonRoot and buttonRoot:IsA("GuiObject") then
				refreshGamePassPrice(self, buttonRoot, gamePassKey)
			end
		end

		for itemName, productInfo in SHOP_PRODUCT_KEYS do
			local buttonRoot = scrollingFrame:FindFirstChild(itemName)
			if buttonRoot and buttonRoot:IsA("GuiObject") then
				refreshDevProductPrice(buttonRoot, productInfo.Key, productInfo.ShowOwned)
			end
		end

		local boostsFolder = scrollingFrame:FindFirstChild("Boosts")
		if boostsFolder then
			for uiName, potionType in BOOST_UI_TO_POTION_TYPE do
				local boostRoot = boostsFolder:FindFirstChild(uiName)
				if boostRoot and boostRoot:IsA("GuiObject") then
					refreshPotionBoostUi(boostRoot, potionType)
				end
			end
		end
	end

	function MainGuiController:markShopGamePassOwned(gamePassKey: string)
		if gamePassKey == "" then
			return
		end

		self:mergeSettingsEntitlements({
			[gamePassKey] = true,
			[gamePassKey .. "GamePass"] = true,
		})
		self:refreshShopPrices()
		self:refreshGamePassSettings()
	end

	function MainGuiController:setupShopFrame()
		self:clearShopConnections()

		local shopFrame = self:getShopFrame()
		if not shopFrame then
			return
		end

		OpenFrame.SetupFrame(shopFrame)

		local topBar = shopFrame:FindFirstChild("TopBar")
		local closeButton = topBar and topBar:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiObject") then
			self:connectGuiActivated(closeButton, function()
				OpenFrame.Toggle(shopFrame)
			end)
		end

		local mainGui = self:getMainGui()
		local rightSide = mainGui and mainGui:FindFirstChild("RightSide")
		local shopButton = rightSide and rightSide:FindFirstChild("ShopButton", true)
		if shopButton and shopButton:IsA("GuiObject") then
			self:connectGuiActivated(shopButton, function()
				OpenFrame.Toggle(shopFrame)
			end)
		end

		local scrollingFrame = shopFrame:FindFirstChild("ScrollingFrame")
		if not scrollingFrame then
			return
		end

		for buttonName, gamePassKey in SHOP_GAMEPASS_ALIASES do
			local buttonRoot = scrollingFrame:FindFirstChild(buttonName)
			if buttonRoot and buttonRoot:IsA("GuiObject") then
				self:connectShopButton(buttonRoot, gamePassKey)
			end
		end

		for itemName, productInfo in SHOP_PRODUCT_KEYS do
			local buttonRoot = scrollingFrame:FindFirstChild(itemName)
			if buttonRoot and buttonRoot:IsA("GuiObject") then
				self:connectDevProductButton(buttonRoot, productInfo.Key, productInfo.ShowOwned)
			end
		end

		local boostsFolder = scrollingFrame:FindFirstChild("Boosts")
		if boostsFolder then
			for uiName, potionType in BOOST_UI_TO_POTION_TYPE do
				local boostRoot = boostsFolder:FindFirstChild(uiName)
				if boostRoot and boostRoot:IsA("GuiObject") then
					self:connectPotionBoostButton(boostRoot, potionType)
				end
			end
		end

		self:setupGiftFeature()
		self:refreshShopPrices()
	end

	function MainGuiController:updateDoubleYenOffer()
		local offer = self:getDoubleYenOffer()
		if not offer then
			return
		end

		if ownsDoubleYenProduct() then
			offer.Visible = false
			if doubleYenClickConnection then
				doubleYenClickConnection:Disconnect()
				doubleYenClickConnection = nil
			end
			return
		end

		offer.Visible = true
		local amount = offer:FindFirstChild("Amount", true)
		if amount and amount:IsA("TextLabel") then
			amount.Text = "2x Yen"
		end

		if doubleYenClickConnection then
			return
		end

		local function promptDoubleYenProduct()
			if doubleYenPromptOpen then
				return
			end

			if ownsDoubleYenProduct() then
				self:ShowAlreadyOwnGamePassMessage()
				self:updateDoubleYenOffer()
				return
			end

			doubleYenPromptOpen = true
			local MonetizationService = Knit.GetService("MonetizationService")
			MonetizationService:GetEntitlements()
				:andThen(function(entitlements)
					self:setSettingsEntitlements(entitlements or {})
					self:refreshGamePassSettings()

					if ownsDoubleYenProduct() or entitlements.DoubleYenProduct == true then
						doubleYenPromptOpen = false
						self:ShowAlreadyOwnGamePassMessage()
						self:updateDoubleYenOffer()
						return
					end

					local ok, err = pcall(function()
						MarketplaceService:PromptProductPurchase(localPlayer, DOUBLE_YEN_PRODUCT.ProductId)
					end)

					if not ok then
						doubleYenPromptOpen = false
						warn("[MainGuiController] DoubleYen product prompt failed:", err)
					end
				end)
				:catch(function(err)
					doubleYenPromptOpen = false
					warn("[MainGuiController] Failed to check DoubleYen ownership:", err)
				end)
		end

		local clickable = self:getClickableGui(offer)
		if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
			doubleYenClickConnection = clickable.Activated:Connect(promptDoubleYenProduct)
		else
			doubleYenClickConnection = clickable.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end

				promptDoubleYenProduct()
			end)
		end
	end

	function MainGuiController:setupShopFeature()
		self:setupShopFrame()
		self:refreshShopPrices()
		self:updateDoubleYenOffer()
		self:refreshSettingsEntitlements()
	end

	function MainGuiController:refreshShopFeature()
		self:refreshShopPrices()
		self:updateDoubleYenOffer()
	end

	function MainGuiController:clearShopRuntimeCache()
		doubleYenOfferCache = nil
		doubleYenOfferScannedGui = nil
		self:clearGiftRuntimeCache()
	end

	local function isShopRelatedProduct(productId: number): boolean
		if DOUBLE_YEN_PRODUCT and productId == DOUBLE_YEN_PRODUCT.ProductId then
			return true
		end
		if STARTER_PACK_PRODUCT and productId == STARTER_PACK_PRODUCT.ProductId then
			return true
		end
		if POTION_BUNDLE_PRODUCT and productId == POTION_BUNDLE_PRODUCT.ProductId then
			return true
		end
		if GAMEPASS_BUNDLE_PRODUCT and productId == GAMEPASS_BUNDLE_PRODUCT.ProductId then
			return true
		end

		local product = Monetization.ProductsById[productId]
		if not product then
			return false
		end

		return product.Kind == "PotionYen"
			or product.Kind == "PotionMana"
			or product.Kind == "PotionDeposit"
			or string.sub(product.Kind, 1, 4) == "Gift"
	end

	function MainGuiController:onShopProductPromptFinished(firstArg: any, productId: number, wasPurchased: boolean)
		if not isLocalProductPromptFinished(firstArg) then
			return
		end

		if wasPurchased == true and isShopRelatedProduct(productId) then
			SoundUtil.Robux()
		end

		doubleYenPromptOpen = false
		shopProductPromptOpen = false

		local product = Monetization.ProductsById[productId]
		if product and string.sub(product.Kind, 1, 4) == "Gift" then
			self:onGiftProductPromptFinished()
		end

		self:refreshSettingsFeature()
		self:refreshShopFeature()
		self:refreshEventFeature()
	end

	function MainGuiController:onShopGamePassPromptFinished(player: Player, gamePassId: number, wasPurchased: boolean)
		if player ~= localPlayer then
			return
		end

		if wasPurchased == true then
			SoundUtil.Robux()
			local gamePassKey = getGamePassKeyFromId(gamePassId)
			if gamePassKey then
				self:markShopGamePassOwned(gamePassKey)
			end
			self:refreshSettingsFeature()
		end

		gamePassPromptOpen = false
		self:refreshShopFeature()
	end
end

return Shop
