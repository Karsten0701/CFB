local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local RobuxPriceUtil = require(ReplicatedStorage.Shared.Features.Monetization.RobuxPriceUtil)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local SidePurchases = {}

local localPlayer = Players.LocalPlayer

local ROTATE_INTERVAL = 30

local PULSE_MIN_SCALE = 0.95
local PULSE_MAX_SCALE = 1.02
local PULSE_HALF_DURATION = 1.25

local ICON_WIGGLE_INTERVAL = 5
local ICON_WIGGLE_DEGREES = 10
local ICON_WIGGLE_STEP_DURATION = 0.1

local ICON_COLLECT_DEPOSIT = "rbxassetid://111292353080235"
local ICON_DOUBLE_MANA = "rbxassetid://137496054365193"
local ICON_DOUBLE_YEN = "rbxassetid://96573285096968"
local ICON_UNITS = "rbxassetid://130087907961701"
local ICON_STARTER_PACK = "rbxassetid://127289191186032"

local COLLECT_DEPOSIT_KEYS = { "AutoCollect", "AutoDeposit" }
local MANA_YEN_KEYS = { "DoubleMana", "DoubleYen" }
local UNIT_PRODUCT_KEYS = { "Unit25", "Unit100", "Unit999", "Unit9999" }

local GAMEPASS_DISPLAY = {
	AutoCollect = { Name = "AUTO COLLECT", Icon = ICON_COLLECT_DEPOSIT },
	AutoDeposit = { Name = "AUTO DEPOSIT", Icon = ICON_COLLECT_DEPOSIT },
	DoubleMana = { Name = "2X MANA", Icon = ICON_DOUBLE_MANA },
	DoubleYen = { Name = "2X YEN", Icon = ICON_DOUBLE_YEN },
}

local clickConnections: { RBXScriptConnection } = {}
local purchaseFinishedConnections: { RBXScriptConnection } = {}
local sidePurchasePromptOpen = false
local rotateIndices = {
	CollectDeposit = 1,
	ManaYen = 1,
	Units = 1,
}
local pulseStates: { [GuiObject]: { token: number, running: boolean, tween: Tween? } } = {}
local iconWiggleStates: { [ImageLabel]: { token: number, running: boolean } } = {}
local priceUpdateTokens: { [GuiObject]: number } = {}
local rotateLoopRunning = false
local tutorialPollRunning = false
local purchaseHandlersConnected = false
local sidePurchasesInitialized = false

local ATTR_PURCHASE_KEY = "SidePurchaseKey"
local ATTR_PURCHASE_KIND = "SidePurchaseKind"

local function clearClickConnections()
	for _, connection in clickConnections do
		connection:Disconnect()
	end
	table.clear(clickConnections)
end

local function ensurePopupInputPassthrough(popup: GuiObject)
	popup.Active = true
	for _, descendant in popup:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.Active = false
		end
	end
end

local function setPopupOffer(popup: GuiObject, key: string, kind: "GamePass" | "Product")
	popup:SetAttribute(ATTR_PURCHASE_KEY, key)
	popup:SetAttribute(ATTR_PURCHASE_KIND, kind)
end

local function clearPopupOffer(popup: GuiObject)
	popup:SetAttribute(ATTR_PURCHASE_KEY, nil)
	popup:SetAttribute(ATTR_PURCHASE_KIND, nil)
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

local function findPriceLabel(popup: GuiObject): TextLabel?
	local price = popup:FindFirstChild("Price")
	return if price and price:IsA("TextLabel") then price else nil
end

local function findNameLabel(popup: GuiObject): TextLabel?
	local nameLabel = popup:FindFirstChild("Name")
	return if nameLabel and nameLabel:IsA("TextLabel") then nameLabel else nil
end

local function findIconLabel(popup: GuiObject): ImageLabel?
	local icon = popup:FindFirstChild("Icon")
	return if icon and icon:IsA("ImageLabel") then icon else nil
end

local function formatUnitDisplayName(amount: number): string
	return `+{amount} UNITS`
end

local function getAvailableKeys(keys: { string }, isOwned: (string) -> boolean): { string }
	local available: { string } = {}
	for _, key in keys do
		if not isOwned(key) then
			table.insert(available, key)
		end
	end
	return available
end

local function beginPriceUpdate(popup: GuiObject): number
	local token = (priceUpdateTokens[popup] or 0) + 1
	priceUpdateTokens[popup] = token
	return token
end

local function isPriceUpdateCurrent(popup: GuiObject, token: number): boolean
	return priceUpdateTokens[popup] == token
end

local function getOrCreateUIScale(popup: GuiObject): UIScale
	local existing = popup:FindFirstChild("SidePurchasePulse")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "SidePurchasePulse"
	uiScale.Scale = 1
	uiScale.Parent = popup
	return uiScale
end

local function resetPopupPulse(popup: GuiObject, state: { tween: Tween? }?)
	if state and state.tween then
		state.tween:Cancel()
		state.tween = nil
	end

	local uiScale = popup:FindFirstChild("SidePurchasePulse")
	if uiScale and uiScale:IsA("UIScale") then
		uiScale.Scale = 1
	end
end

local function stopPopupPulse(popup: GuiObject)
	local state = pulseStates[popup]
	if not state then
		resetPopupPulse(popup, nil)
		return
	end

	state.token += 1
	state.running = false
	resetPopupPulse(popup, state)
end

local function startPopupPulse(popup: GuiObject)
	if not pulseStates[popup] then
		pulseStates[popup] = {
			token = 0,
			running = false,
			tween = nil,
		}
	end

	local state = pulseStates[popup]
	if state.running then
		return
	end

	state.running = true
	state.token += 1
	local pulseToken = state.token
	local uiScale = getOrCreateUIScale(popup)

	if state.tween then
		state.tween:Cancel()
		state.tween = nil
	end

	uiScale.Scale = PULSE_MIN_SCALE

	local pulseTween = TweenService:Create(
		uiScale,
		TweenInfo.new(PULSE_HALF_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = PULSE_MAX_SCALE }
	)
	state.tween = pulseTween

	task.spawn(function()
		if pulseToken ~= state.token or not popup.Parent or not popup.Visible then
			state.running = false
			return
		end

		pulseTween:Play()

		while pulseToken == state.token and popup.Parent and popup.Visible do
			task.wait(0.25)
		end

		if pulseToken == state.token then
			resetPopupPulse(popup, state)
		end

		state.running = false
	end)
end

local function tweenGui(
	guiObject: GuiObject,
	properties: { [string]: any },
	duration: number,
	easingStyle: Enum.EasingStyle?
)
	local tween = TweenService:Create(
		guiObject,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		properties
	)
	tween:Play()
	tween.Completed:Wait()
end

local function resetIconWiggle(icon: ImageLabel)
	icon.Rotation = 0
end

local function stopIconWiggle(icon: ImageLabel?)
	if not icon then
		return
	end

	local state = iconWiggleStates[icon]
	if not state then
		resetIconWiggle(icon)
		return
	end

	state.token += 1
	state.running = false
	resetIconWiggle(icon)
end

local function playIconWiggleStep(icon: ImageLabel, flipPositive: boolean)
	local offset = if flipPositive then ICON_WIGGLE_DEGREES else -ICON_WIGGLE_DEGREES
	tweenGui(icon, { Rotation = offset }, ICON_WIGGLE_STEP_DURATION, Enum.EasingStyle.Quad)
	tweenGui(icon, { Rotation = -offset }, ICON_WIGGLE_STEP_DURATION * 2, Enum.EasingStyle.Quad)
	tweenGui(icon, { Rotation = 0 }, ICON_WIGGLE_STEP_DURATION, Enum.EasingStyle.Quad)
end

local function startIconWiggle(popup: GuiObject)
	local icon = findIconLabel(popup)
	if not icon then
		return
	end

	if not iconWiggleStates[icon] then
		iconWiggleStates[icon] = {
			token = 0,
			running = false,
		}
	end

	local state = iconWiggleStates[icon]
	if state.running then
		return
	end

	state.running = true
	state.token += 1
	local wiggleToken = state.token
	icon.Rotation = 0

	task.spawn(function()
		task.wait(ICON_WIGGLE_INTERVAL)

		local flipPositive = false
		while wiggleToken == state.token and popup.Parent and popup.Visible and icon.Parent do
			flipPositive = not flipPositive
			playIconWiggleStep(icon, flipPositive)

			if wiggleToken ~= state.token or not popup.Parent or not popup.Visible or not icon.Parent then
				break
			end

			task.wait(ICON_WIGGLE_INTERVAL)
		end

		state.running = false
		if wiggleToken == state.token and icon.Parent then
			resetIconWiggle(icon)
		end
	end)
end

local function syncPopupAnimations(popup: GuiObject?, visible: boolean)
	if not popup then
		return
	end

	if visible then
		startPopupPulse(popup)
		startIconWiggle(popup)
	else
		stopPopupPulse(popup)
		stopIconWiggle(findIconLabel(popup))
	end
end

function SidePurchases.Install(MainGuiController)
	local function getEntitlements(): { [string]: boolean }
		return MainGuiController:getSettingsEntitlements()
	end

	local function ownsGamePass(gamePassKey: string): boolean
		if getEntitlements()[gamePassKey .. "GamePass"] == true then
			return true
		end

		if getEntitlements()[gamePassKey] == true then
			return true
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		if PlayerDataController:Get({ "GrantedGamePasses", gamePassKey }) == true then
			return true
		end

		if gamePassKey == "DoubleMana" then
			return PlayerDataController:Get({ "PurchasedProducts", "DoubleMana" }) == true
		end

		return false
	end

	local function ownsStarterPack(): boolean
		local PlayerDataController = Knit.GetController("PlayerDataController")
		return PlayerDataController:Get({ "PurchasedProducts", "StarterPack" }) == true
	end

	local function shouldHideForTutorial(): boolean
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local tutorial = PlayerDataController:Get("Tutorial")
		if type(tutorial) == "table" then
			if tutorial.Cancelled == true or tutorial.Completed == true then
				return false
			end
		end

		local TutorialController = Knit.GetController("TutorialController")
		return TutorialController:shouldTrack()
	end

	function MainGuiController:getSidePurchasesFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local frame = mainGui:FindFirstChild("SidePurchases")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	local function updateGamePassPopup(popup: GuiObject, gamePassKey: string)
		local display = GAMEPASS_DISPLAY[gamePassKey]
		if not display then
			return
		end

		local priceToken = beginPriceUpdate(popup)

		local nameLabel = findNameLabel(popup)
		if nameLabel then
			nameLabel.Text = display.Name
		end

		local iconLabel = findIconLabel(popup)
		if iconLabel then
			iconLabel.Image = display.Icon
		end

		local gamePass = Monetization.GamePasses[gamePassKey]
		local priceLabel = findPriceLabel(popup)
		if not gamePass or not priceLabel then
			return
		end

		if ownsGamePass(gamePassKey) then
			priceLabel.Text = RobuxPriceUtil.formatOwnedLabel()
			return
		end

		priceLabel.Text = RobuxPriceUtil.formatPrice(gamePass.Price)

		task.spawn(function()
			local price = RobuxPriceUtil.getGamePassPriceAsync(gamePass.PassId)
			if not priceLabel.Parent or not isPriceUpdateCurrent(popup, priceToken) then
				return
			end

			if ownsGamePass(gamePassKey) then
				priceLabel.Text = RobuxPriceUtil.formatOwnedLabel()
				return
			end

			priceLabel.Text = RobuxPriceUtil.formatPrice(price or gamePass.Price)
		end)
	end

	local function updateProductPopup(popup: GuiObject, productKey: string, displayName: string?, icon: string?)
		local product = Monetization.DeveloperProducts[productKey]
		if not product then
			return
		end

		local priceToken = beginPriceUpdate(popup)

		local nameLabel = findNameLabel(popup)
		if nameLabel then
			if displayName then
				nameLabel.Text = displayName
			elseif product.Kind == "Units" then
				nameLabel.Text = formatUnitDisplayName(product.Amount or 0)
			end
		end

		local iconLabel = findIconLabel(popup)
		if iconLabel and icon then
			iconLabel.Image = icon
		end

		local priceLabel = findPriceLabel(popup)
		if not priceLabel then
			return
		end

		if productKey == "StarterPack" and ownsStarterPack() then
			priceLabel.Text = RobuxPriceUtil.formatOwnedLabel()
			return
		end

		priceLabel.Text = RobuxPriceUtil.formatPrice(product.Price)

		task.spawn(function()
			local price = RobuxPriceUtil.getProductPriceAsync(product.ProductId)
			if not priceLabel.Parent or not isPriceUpdateCurrent(popup, priceToken) then
				return
			end

			if productKey == "StarterPack" and ownsStarterPack() then
				priceLabel.Text = RobuxPriceUtil.formatOwnedLabel()
				return
			end

			priceLabel.Text = RobuxPriceUtil.formatPrice(price or product.Price)
		end)
	end

	local function getRotatingKey(groupName: "CollectDeposit" | "ManaYen" | "Units", availableKeys: { string }): string?
		if #availableKeys == 0 then
			return nil
		end

		if #availableKeys == 1 then
			return availableKeys[1]
		end

		local index = rotateIndices[groupName] or 1
		while index > #availableKeys do
			index -= 1
		end
		if index < 1 then
			index = 1
		end

		rotateIndices[groupName] = index
		return availableKeys[index]
	end

	local function advanceRotatingIndices()
		for groupName, availableKeys in
			{
				CollectDeposit = getAvailableKeys(COLLECT_DEPOSIT_KEYS, ownsGamePass),
				ManaYen = getAvailableKeys(MANA_YEN_KEYS, ownsGamePass),
				Units = UNIT_PRODUCT_KEYS,
			}
		do
			if #availableKeys > 1 then
				local currentIndex = rotateIndices[groupName] or 1
				rotateIndices[groupName] = (currentIndex % #availableKeys) + 1
			end
		end
	end

	function MainGuiController:refreshSidePurchases()
		if not Monetization.isEnabled() then
			local frame = self:getSidePurchasesFrame()
			if frame then
				frame.Visible = false
			end
			return
		end

		local frame = self:getSidePurchasesFrame()
		if not frame then
			return
		end

		local hideForTutorial = shouldHideForTutorial()
		local anyPopupVisible = false

		local collectDepositPopup = frame:FindFirstChild("CollectDepositPopup")
		if collectDepositPopup and collectDepositPopup:IsA("GuiObject") then
			local available = getAvailableKeys(COLLECT_DEPOSIT_KEYS, ownsGamePass)
			local key = getRotatingKey("CollectDeposit", available)
			local visible = key ~= nil and not hideForTutorial
			collectDepositPopup.Visible = visible
			if visible and key then
				updateGamePassPopup(collectDepositPopup, key)
				setPopupOffer(collectDepositPopup, key, "GamePass")
			else
				clearPopupOffer(collectDepositPopup)
			end
			syncPopupAnimations(collectDepositPopup, visible)
			anyPopupVisible = anyPopupVisible or visible
		end

		local manaYenPopup = frame:FindFirstChild("ManaYenPopup")
		if manaYenPopup and manaYenPopup:IsA("GuiObject") then
			local available = getAvailableKeys(MANA_YEN_KEYS, ownsGamePass)
			local key = getRotatingKey("ManaYen", available)
			local visible = key ~= nil and not hideForTutorial
			manaYenPopup.Visible = visible
			if visible and key then
				updateGamePassPopup(manaYenPopup, key)
				setPopupOffer(manaYenPopup, key, "GamePass")
			else
				clearPopupOffer(manaYenPopup)
			end
			syncPopupAnimations(manaYenPopup, visible)
			anyPopupVisible = anyPopupVisible or visible
		end

		local starterPackPopup = frame:FindFirstChild("StarterPackPopup")
		if starterPackPopup and starterPackPopup:IsA("GuiObject") then
			local visible = not ownsStarterPack() and not hideForTutorial
			starterPackPopup.Visible = visible
			if visible then
				updateProductPopup(starterPackPopup, "StarterPack", "STARTER PACK", ICON_STARTER_PACK)
				setPopupOffer(starterPackPopup, "StarterPack", "Product")
			else
				clearPopupOffer(starterPackPopup)
			end
			syncPopupAnimations(starterPackPopup, visible)
			anyPopupVisible = anyPopupVisible or visible
		end

		local unitPurchasePopup = frame:FindFirstChild("UnitPurchasePopup")
		if unitPurchasePopup and unitPurchasePopup:IsA("GuiObject") then
			local key = getRotatingKey("Units", UNIT_PRODUCT_KEYS)
			local visible = key ~= nil and not hideForTutorial
			unitPurchasePopup.Visible = visible
			if visible and key then
				updateProductPopup(unitPurchasePopup, key, nil, ICON_UNITS)
				setPopupOffer(unitPurchasePopup, key, "Product")
			else
				clearPopupOffer(unitPurchasePopup)
			end
			syncPopupAnimations(unitPurchasePopup, visible)
			anyPopupVisible = anyPopupVisible or visible
		end

		frame.Visible = anyPopupVisible
	end

	local function promptGamePass(gamePassKey: string)
		if sidePurchasePromptOpen then
			return
		end

		if ownsGamePass(gamePassKey) then
			MainGuiController:ShowAlreadyOwnGamePassMessage()
			return
		end

		local gamePass = Monetization.GamePasses[gamePassKey]
		if not gamePass or type(gamePass.PassId) ~= "number" or gamePass.PassId <= 0 then
			return
		end

		sidePurchasePromptOpen = true
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetEntitlements()
			:andThen(function(entitlements)
				MainGuiController:mergeSettingsEntitlements(entitlements or {})

				if ownsGamePass(gamePassKey) then
					sidePurchasePromptOpen = false
					MainGuiController:ShowAlreadyOwnGamePassMessage()
					MainGuiController:refreshSidePurchases()
					return
				end

				local ok, err = pcall(function()
					MarketplaceService:PromptGamePassPurchase(localPlayer, gamePass.PassId)
				end)

				if not ok then
					sidePurchasePromptOpen = false
					warn("[SidePurchases] Gamepass prompt failed:", err)
				end
			end)
			:catch(function(err)
				sidePurchasePromptOpen = false
				warn("[SidePurchases] Failed to check gamepass ownership:", err)
			end)
	end

	local function promptProduct(productKey: string)
		if sidePurchasePromptOpen then
			return
		end

		if productKey == "StarterPack" and ownsStarterPack() then
			MainGuiController:ShowAlreadyPurchasedStarterPackMessage()
			return
		end

		local product = Monetization.DeveloperProducts[productKey]
		if not product or type(product.ProductId) ~= "number" then
			return
		end

		sidePurchasePromptOpen = true
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, product.ProductId)
		end)

		if not ok then
			sidePurchasePromptOpen = false
			warn("[SidePurchases] Product prompt failed:", productKey, err)
		end
	end

	local function connectPopupClick(popup: GuiObject)
		ensurePopupInputPassthrough(popup)

		local clickable: GuiObject = popup
		if not popup:IsA("ImageButton") and not popup:IsA("TextButton") then
			clickable = MainGuiController:getClickableGui(popup)
		end

		if clickable:IsA("ImageButton") or clickable:IsA("TextButton") then
			table.insert(
				clickConnections,
				clickable.Activated:Connect(function()
					local key = popup:GetAttribute(ATTR_PURCHASE_KEY)
					local kind = popup:GetAttribute(ATTR_PURCHASE_KIND)
					if type(key) ~= "string" or key == "" or type(kind) ~= "string" then
						return
					end

					if kind == "GamePass" then
						promptGamePass(key)
					elseif kind == "Product" then
						promptProduct(key)
					end
				end)
			)
			return
		end

		table.insert(
			clickConnections,
			clickable.InputBegan:Connect(function(input)
				if
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end

				local key = popup:GetAttribute(ATTR_PURCHASE_KEY)
				local kind = popup:GetAttribute(ATTR_PURCHASE_KIND)
				if type(key) ~= "string" or key == "" or type(kind) ~= "string" then
					return
				end

				if kind == "GamePass" then
					promptGamePass(key)
				elseif kind == "Product" then
					promptProduct(key)
				end
			end)
		)
	end

	local function connectPurchaseFinishedHandlers()
		if purchaseHandlersConnected then
			return
		end

		purchaseHandlersConnected = true

		table.insert(
			purchaseFinishedConnections,
			MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
				if player ~= localPlayer then
					return
				end

				sidePurchasePromptOpen = false
				if wasPurchased == true then
					SoundUtil.Robux()
					for key, gamePass in Monetization.GamePasses do
						if gamePass.PassId == gamePassId then
							MainGuiController:markShopGamePassOwned(key)
							break
						end
					end
				end

				MainGuiController:refreshSidePurchases()
			end)
		)

		table.insert(
			purchaseFinishedConnections,
			MarketplaceService.PromptProductPurchaseFinished:Connect(function(firstArg, productId, wasPurchased)
				if not isLocalProductPromptFinished(firstArg) then
					return
				end

				sidePurchasePromptOpen = false
				if wasPurchased == true then
					local product = Monetization.ProductsById[productId]
					if product and (product.Kind == "Units" or product.Key == "StarterPack") then
						SoundUtil.Robux()
					end
				end

				MainGuiController:refreshSidePurchases()
			end)
		)
	end

	local function startSidePurchaseLoops()
		if not rotateLoopRunning then
			rotateLoopRunning = true
			task.spawn(function()
				while true do
					task.wait(ROTATE_INTERVAL)
					advanceRotatingIndices()
					MainGuiController:refreshSidePurchases()
				end
			end)
		end

		if not tutorialPollRunning then
			tutorialPollRunning = true
			task.spawn(function()
				while shouldHideForTutorial() do
					MainGuiController:refreshSidePurchases()
					task.wait(0.25)
				end
				MainGuiController:refreshSidePurchases()
				tutorialPollRunning = false
			end)
		end
	end

	function MainGuiController:setupSidePurchases()
		connectPurchaseFinishedHandlers()

		local frame = self:getSidePurchasesFrame()
		if not frame then
			return false
		end

		clearClickConnections()

		for _, popupName in { "CollectDepositPopup", "StarterPackPopup", "ManaYenPopup", "UnitPurchasePopup" } do
			local popup = frame:FindFirstChild(popupName)
			if popup and popup:IsA("GuiObject") then
				connectPopupClick(popup)
			end
		end

		startSidePurchaseLoops()
		sidePurchasesInitialized = true
		self:refreshSidePurchases()
		return true
	end

	function MainGuiController:bindSidePurchasesObservers(PlayerDataController)
		if not sidePurchasesInitialized then
			self:setupSidePurchases()
		end

		PlayerDataController:Observe("Tutorial", function()
			self:refreshSidePurchases()
		end)

		PlayerDataController:ObserveIndex("Tutorial", function()
			self:refreshSidePurchases()
		end)

		PlayerDataController:Observe("TutorialBoostEndsAt", function()
			self:refreshSidePurchases()
		end)

		PlayerDataController:Observe("GrantedGamePasses", function()
			self:refreshSidePurchases()
		end)

		PlayerDataController:ObserveIndex("GrantedGamePasses", function()
			self:refreshSidePurchases()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "StarterPack" }, function()
			self:refreshSidePurchases()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "DoubleMana" }, function()
			self:refreshSidePurchases()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "DoubleYen" }, function()
			self:refreshSidePurchases()
		end)

		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetEntitlements()
			:andThen(function(entitlements)
				self:mergeSettingsEntitlements(entitlements or {})
				self:refreshSidePurchases()
			end)
			:catch(function(err)
				warn("[SidePurchases] Failed to refresh entitlements:", err)
			end)
	end
end

return SidePurchases
