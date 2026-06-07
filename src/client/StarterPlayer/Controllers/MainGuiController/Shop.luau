local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local Shop = {}

local localPlayer = Players.LocalPlayer
local DOUBLE_YEN_PRODUCT = Monetization.DeveloperProducts.DoubleYen
local STARTER_PACK_PRODUCT = Monetization.DeveloperProducts.StarterPack

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

local function isLocalProductPromptFinished(firstArg: any): boolean
	if firstArg == localPlayer then
		return true
	end

	if type(firstArg) == "number" then
		return firstArg == localPlayer.UserId
	end

	return false
end

function Shop.Install(MainGuiController)

local function getEntitlements(controller): { [string]: boolean }
	return controller:getSettingsEntitlements()
end

local function ownsShopGamePass(controller, gamePassKey: string): boolean
	return getEntitlements(controller)[gamePassKey .. "GamePass"] == true
end

local function ownsDoubleYenProduct(): boolean
	local PlayerDataController = Knit.GetController("PlayerDataController")
	return PlayerDataController:Get({ "PurchasedProducts", "DoubleYen" }) == true
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

	local clickable = self:getClickableGui(buttonRoot)
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

function MainGuiController:connectStarterPackButton(buttonRoot: GuiObject)
	if not STARTER_PACK_PRODUCT or type(STARTER_PACK_PRODUCT.ProductId) ~= "number" then
		warn("[MainGuiController] Missing StarterPack developer product")
		return
	end

	self:connectGuiActivated(buttonRoot, function()
		if shopProductPromptOpen then
			return
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		if PlayerDataController:Get({ "PurchasedProducts", "StarterPack" }) == true then
			self:ShowAlreadyPurchasedStarterPackMessage()
			return
		end

		shopProductPromptOpen = true
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, STARTER_PACK_PRODUCT.ProductId)
		end)

		if not ok then
			shopProductPromptOpen = false
			warn("[MainGuiController] StarterPack prompt failed:", err)
		end
	end)
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

	local starterPackButton = scrollingFrame:FindFirstChild("StarterPack")
	if starterPackButton and starterPackButton:IsA("GuiObject") then
		self:connectStarterPackButton(starterPackButton)
	end
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
	self:updateDoubleYenOffer()
end

function MainGuiController:refreshShopFeature()
	self:setupShopFrame()
	self:updateDoubleYenOffer()
end

function MainGuiController:clearShopRuntimeCache()
	doubleYenOfferCache = nil
	doubleYenOfferScannedGui = nil
end

function MainGuiController:onShopProductPromptFinished(firstArg: any, productId: number, wasPurchased: boolean)
	if not isLocalProductPromptFinished(firstArg) then
		return
	end

	if productId == DOUBLE_YEN_PRODUCT.ProductId and wasPurchased == true then
		SoundUtil.Robux()
	elseif STARTER_PACK_PRODUCT and productId == STARTER_PACK_PRODUCT.ProductId and wasPurchased == true then
		SoundUtil.Robux()
	end

	doubleYenPromptOpen = false
	shopProductPromptOpen = false
	self:refreshSettingsFeature()
	self:refreshShopFeature()
end

function MainGuiController:onShopGamePassPromptFinished(player: Player, wasPurchased: boolean)
	if player ~= localPlayer then
		return
	end

	if wasPurchased == true then
		SoundUtil.Robux()
		self:refreshSettingsFeature()
	end

	gamePassPromptOpen = false
end

end

return Shop
