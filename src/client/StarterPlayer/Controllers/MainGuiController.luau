local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local Icon = require(ReplicatedStorage.Packages.topbarplus)
local Knit = require(ReplicatedStorage.Packages.knit)

local MainGuiController = Knit.CreateController({
	Name = "MainGuiController",
})

local localPlayer = Players.LocalPlayer
local COUNTER_ANIMATION_TIME = 0.5
local COUNTER_ANIMATION_STEPS = 50
local MESSAGE_LIFETIME = 3
local DOUBLE_YEN_PRODUCT = Monetization.DeveloperProducts.DoubleYen

local displayedValues = {
	ManaBag = 0,
	YenShow = 0,
}

local doubleYenClickConnection: RBXScriptConnection? = nil
local doubleYenPromptOpen = false
local settingsIcon = nil
local homeIcon = nil
local boundSettingsFrame: GuiObject? = nil
local lastHomeTeleportAt = 0
local activeMessages = {}
local nextMessageLayoutOrder = 0
local shopConnections: { RBXScriptConnection } = {}
local gamePassPromptOpen = false

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

local animationTokens = {
	ManaBag = 0,
	YenShow = 0,
}

local function setMessageTransparency(instance: Instance, transparency: number)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			descendant.TextTransparency = transparency
			descendant.TextStrokeTransparency = math.clamp(transparency, 0, 1)
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			descendant.ImageTransparency = transparency
		elseif descendant:IsA("UIStroke") then
			descendant.Transparency = transparency
		end
	end

	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		instance.TextTransparency = transparency
		instance.TextStrokeTransparency = math.clamp(transparency, 0, 1)
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		instance.ImageTransparency = transparency
	end
end

local function setRichText(instance: Instance, enabled: boolean)
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		instance.RichText = enabled
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			descendant.RichText = enabled
		end
	end
end

local function setFirstMessageText(instance: Instance, text: string)
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		instance.Text = text
		return
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			descendant.Text = text
			return
		end
	end
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

function MainGuiController:getAmountLabel(containerName: string): TextLabel?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local container = mainGui:FindFirstChild(containerName)
	if not container then
		return nil
	end

	local amount = container:FindFirstChild("Amount")
	return if amount and amount:IsA("TextLabel") then amount else nil
end

function MainGuiController:getMainGui(): Instance?
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	return playerGui:FindFirstChild("MainGui")
end

function MainGuiController:getSettingsFrame(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local settingsFrame = mainGui:FindFirstChild("SettingsFrame")
	return if settingsFrame and settingsFrame:IsA("GuiObject") then settingsFrame else nil
end

function MainGuiController:getShopFrame(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local shopFrame = mainGui:FindFirstChild("ShopFrame")
	return if shopFrame and shopFrame:IsA("GuiObject") then shopFrame else nil
end

function MainGuiController:getMessageHolder(): Instance?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	return mainGui:FindFirstChild("MessageHolder")
end

function MainGuiController:getMessageTemplate(): GuiObject?
	local messageHolder = self:getMessageHolder()
	if not messageHolder then
		return nil
	end

	local template = messageHolder:FindFirstChild("Template")
	if template and template:IsA("GuiObject") then
		template.Visible = false
		return template
	end

	return nil
end

function MainGuiController:getMessageText(baseText: string, count: number): string
	if count <= 1 then
		return baseText
	end

	return baseText .. ' <font color="#FFFFFF">x' .. count .. "</font>"
end

function MainGuiController:pulseMessage(messageGui: GuiObject)
	local scale = messageGui:FindFirstChild("MessageScale")
	if not scale or not scale:IsA("UIScale") then
		scale = Instance.new("UIScale")
		scale.Name = "MessageScale"
		scale.Parent = messageGui
	end

	scale.Scale = 1.08
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

function MainGuiController:fadeOutMessage(key: string, token: number)
	local entry = activeMessages[key]
	if not entry or entry.Token ~= token then
		return
	end

	local messageGui = entry.Gui
	activeMessages[key] = nil
	if not messageGui or not messageGui.Parent then
		return
	end

	local fadeProgress = Instance.new("NumberValue")
	fadeProgress.Value = 0
	local connection = fadeProgress.Changed:Connect(function(value)
		setMessageTransparency(messageGui, value)
	end)

	TweenService:Create(fadeProgress, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = 1,
	}):Play()

	task.delay(0.28, function()
		connection:Disconnect()
		fadeProgress:Destroy()
		if messageGui.Parent then
			messageGui:Destroy()
		end
	end)
end

function MainGuiController:showMessage(key: string, richText: string)
	local existing = activeMessages[key]
	if existing and existing.Gui and existing.Gui.Parent then
		existing.Count += 1
		existing.Token += 1
		setFirstMessageText(existing.Gui, self:getMessageText(existing.BaseText, existing.Count))
		self:pulseMessage(existing.Gui)

		local token = existing.Token
		task.delay(MESSAGE_LIFETIME, function()
			self:fadeOutMessage(key, token)
		end)
		return
	end

	local template = self:getMessageTemplate()
	local messageHolder = self:getMessageHolder()
	if not template or not messageHolder then
		return
	end

	nextMessageLayoutOrder -= 1
	local messageGui = template:Clone()
	messageGui.Name = "Message"
	messageGui.Visible = true
	messageGui.LayoutOrder = nextMessageLayoutOrder
	setRichText(messageGui, true)
	setFirstMessageText(messageGui, richText)
	setMessageTransparency(messageGui, 1)

	local scale = Instance.new("UIScale")
	scale.Name = "MessageScale"
	scale.Scale = 0.82
	scale.Parent = messageGui

	messageGui.Parent = messageHolder
	activeMessages[key] = {
		Gui = messageGui,
		BaseText = richText,
		Count = 1,
		Token = 1,
	}

	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	local fadeProgress = Instance.new("NumberValue")
	fadeProgress.Value = 1
	local connection = fadeProgress.Changed:Connect(function(value)
		setMessageTransparency(messageGui, value)
	end)

	TweenService:Create(fadeProgress, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = 0,
	}):Play()

	task.delay(0.2, function()
		connection:Disconnect()
		fadeProgress:Destroy()
	end)

	local token = activeMessages[key].Token
	task.delay(MESSAGE_LIFETIME, function()
		self:fadeOutMessage(key, token)
	end)
end

function MainGuiController:ShowDepositMessage(amount: number)
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return
	end

	self:showMessage(
		"DepositMana:" .. amount,
		'You deposited <font color="#42B6FF">' .. FormatUtil.formatMana(amount) .. "</font>"
	)
end

function MainGuiController:ShowBoughtUnitsMessage(amount: number)
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return
	end

	self:showMessage(
		"BoughtUnits:" .. amount,
		'You bought <font color="#47FF6A">' .. FormatUtil.formatNumber(amount) .. " Anime Units</font>"
	)
end

function MainGuiController:ShowMergedUnitsMessage(amount: number)
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return
	end

	self:showMessage(
		"MergedUnits:" .. amount,
		'You merged <font color="#FFCC33">' .. FormatUtil.formatNumber(amount) .. " Anime Units</font>"
	)
end

function MainGuiController:ShowRobuxUnitsMessage(amount: number)
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return
	end

	self:showMessage(
		"RobuxUnits:" .. amount,
		'You bought <font color="#47FF6A">+'
			.. FormatUtil.formatNumber(amount)
			.. ' Anime Drops</font>, <font color="#FFD86B">Thank you for your support!</font>'
	)
end

function MainGuiController:setupSettingsIcon()
	if not settingsIcon then
		settingsIcon = Icon.new()
			:setName("Settings")
			:setImage("rbxassetid://77679977863044")
			:setImageScale(0.72)
			:setCaption("Settings")
			:align("Left")
	end

	local settingsFrame = self:getSettingsFrame()
	if not settingsFrame or boundSettingsFrame == settingsFrame then
		return
	end

	settingsFrame.Visible = false
	if boundSettingsFrame then
		settingsIcon:unbindToggleItem(boundSettingsFrame)
	end

	boundSettingsFrame = settingsFrame
	settingsIcon:bindToggleItem(settingsFrame)
end

function MainGuiController:setupHomeIcon()
	if homeIcon then
		return
	end

	homeIcon = Icon.new()
		:setName("TeleportHome")
		:setImage("rbxassetid://122963480555617")
		:setImageScale(0.72)
		:setCaption("Teleport to plot")
		:align("Left")
		:oneClick(true)

	homeIcon.selected:Connect(function()
		local now = os.clock()
		if now - lastHomeTeleportAt < 1 then
			return
		end

		lastHomeTeleportAt = now
		local TycoonService = Knit.GetService("TycoonService")
		TycoonService:TeleportHome():andThen(function(success, err)
			if not success and err then
				warn("[MainGuiController] Teleport home failed:", err)
			end
		end)
	end)
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

	local normalizedName = string.lower(string.gsub(instance.Name, "%s+", ""))
	if normalizedName == "doubleyen" or normalizedName == "2xyen" or normalizedName == "yen2x" then
		return true
	end

	if instance.Name == "Amount" and instance:IsA("TextLabel") then
		local normalizedText = string.lower(string.gsub(instance.Text, "%s+", ""))
		return string.find(normalizedText, "2xyen", 1, true) ~= nil
	end

	return false
end

function MainGuiController:getDoubleYenOffer(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	for _, descendant in mainGui:GetDescendants() do
		if self:isDoubleYenCandidate(descendant) then
			local root = self:getDoubleYenOfferRootFromDescendant(mainGui, descendant)
			if root then
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
					return root
				end
			end
		end
	end

	return nil
end

function MainGuiController:getClickableGui(root: GuiObject): GuiObject
	if root:IsA("TextButton") or root:IsA("ImageButton") then
		return root
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
			return descendant
		end
	end

	return root
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
		warn("[MainGuiController] Missing gamepass for shop button:", buttonRoot.Name, gamePassKey)
		return
	end

	local clickable = self:getClickableGui(buttonRoot)
	local function prompt()
		if gamePassPromptOpen then
			return
		end

		gamePassPromptOpen = true
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(localPlayer, gamePass.PassId)
		end)

		if not ok then
			gamePassPromptOpen = false
			warn("[MainGuiController] Gamepass prompt failed:", err)
		end
	end

	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		table.insert(shopConnections, clickable.Activated:Connect(prompt))
	else
		table.insert(shopConnections, clickable.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt()
			end
		end))
	end
end

function MainGuiController:connectGuiActivated(guiObject: GuiObject, callback: () -> ())
	local clickable = self:getClickableGui(guiObject)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		table.insert(shopConnections, clickable.Activated:Connect(callback))
	else
		table.insert(shopConnections, clickable.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				callback()
			end
		end))
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
end

function MainGuiController:updateDoubleYenOffer()
	local offer = self:getDoubleYenOffer()
	if not offer then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local purchased = PlayerDataController:Get({ "PurchasedProducts", "DoubleYen" }) == true
	if purchased then
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

	local clickable = self:getClickableGui(offer)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		doubleYenClickConnection = clickable.Activated:Connect(function()
			if doubleYenPromptOpen then
				return
			end

			doubleYenPromptOpen = true
			MarketplaceService:PromptProductPurchase(localPlayer, DOUBLE_YEN_PRODUCT.ProductId)
		end)
	else
		doubleYenClickConnection = clickable.InputBegan:Connect(function(input)
			if doubleYenPromptOpen or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			doubleYenPromptOpen = true
			MarketplaceService:PromptProductPurchase(localPlayer, DOUBLE_YEN_PRODUCT.ProductId)
		end)
	end
end

function MainGuiController:formatCounter(counterName: string, value: number): string
	if counterName == "ManaBag" then
		return FormatUtil.formatNumber(value) .. " Mana"
	elseif counterName == "YenShow" then
		return Pricing.formatYen(value)
	end

	return FormatUtil.formatNumber(value)
end

function MainGuiController:setCounterText(counterName: string, value: number)
	local label = self:getAmountLabel(counterName)
	if label then
		label.Text = self:formatCounter(counterName, value)
	end
end

function MainGuiController:animateCounter(counterName: string, targetValue: number)
	targetValue = math.max(math.floor(targetValue), 0)

	local startValue = displayedValues[counterName] or 0
	if startValue == targetValue then
		self:setCounterText(counterName, targetValue)
		return
	end

	animationTokens[counterName] = (animationTokens[counterName] or 0) + 1
	local token = animationTokens[counterName]
	local stepDuration = COUNTER_ANIMATION_TIME / COUNTER_ANIMATION_STEPS

	task.spawn(function()
		for step = 1, COUNTER_ANIMATION_STEPS do
			if animationTokens[counterName] ~= token then
				return
			end

			local alpha = step / COUNTER_ANIMATION_STEPS
			local easedAlpha = 1 - (1 - alpha) ^ 3
			local value = math.floor(startValue + (targetValue - startValue) * easedAlpha + 0.5)

			displayedValues[counterName] = value
			self:setCounterText(counterName, value)

			if step < COUNTER_ANIMATION_STEPS then
				task.wait(stepDuration)
			end
		end

		if animationTokens[counterName] == token then
			displayedValues[counterName] = targetValue
			self:setCounterText(counterName, targetValue)
		end
	end)
end

function MainGuiController:updateManaBag()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:animateCounter("ManaBag", PlayerDataController:Get("ManaInBag") or 0)
end

function MainGuiController:updateYenShow()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:animateCounter("YenShow", PlayerDataController:Get("Yen") or 0)
end

function MainGuiController:updateAll(instant: boolean?)
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local mana = math.max(math.floor(PlayerDataController:Get("ManaInBag") or 0), 0)
	local yen = math.max(math.floor(PlayerDataController:Get("Yen") or 0), 0)
	self:setupSettingsIcon()
	self:setupHomeIcon()
	self:setupShopFrame()

	if instant then
		animationTokens.ManaBag += 1
		animationTokens.YenShow += 1
		displayedValues.ManaBag = mana
		displayedValues.YenShow = yen
		self:setCounterText("ManaBag", mana)
		self:setCounterText("YenShow", yen)
		self:updateDoubleYenOffer()
		return
	end

	self:animateCounter("ManaBag", mana)
	self:animateCounter("YenShow", yen)
	self:updateDoubleYenOffer()
end

function MainGuiController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:setupSettingsIcon()
	self:setupHomeIcon()
	self:setupShopFrame()

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(firstArg)
		if isLocalProductPromptFinished(firstArg) then
			doubleYenPromptOpen = false
			self:updateDoubleYenOffer()
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player)
		if player == localPlayer then
			gamePassPromptOpen = false
		end
	end)

	task.spawn(function()
		PlayerDataController:WaitForData()
		self:updateAll()

		PlayerDataController:Observe("ManaInBag", function()
			self:updateManaBag()
		end)

		PlayerDataController:Observe("Yen", function()
			self:updateYenShow()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "DoubleYen" }, function()
			self:updateDoubleYenOffer()
		end)
	end)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "MainGui" then
			task.defer(function()
				self:updateAll(true)
				self:setupSettingsIcon()
				self:setupShopFrame()
			end)
		end
	end)
end

return MainGuiController
