local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Icon = require(ReplicatedStorage.Packages.topbarplus)
local Knit = require(ReplicatedStorage.Packages.knit)
local IndexFeature = require(script.Index)
local OfflineFeature = require(script.Offline)
local RebirthFeature = require(script.Rebirth)
local SettingsFeature = require(script.Settings)
local ShopFeature = require(script.Shop)

local MainGuiController = Knit.CreateController({
	Name = "MainGuiController",
})

local localPlayer = Players.LocalPlayer
local COUNTER_ANIMATION_TIME = 0.5
local COUNTER_ANIMATION_STEPS = 50
local MESSAGE_LIFETIME = 3

local displayedValues = {
	ManaBag = 0,
	YenShow = 0,
}

local homeIcon = nil
local lastHomeTeleportAt = 0
local activeMessages = {}
local nextMessageLayoutOrder = 0
local indexWarnedMissingGui = false

local animationTokens = {
	ManaBag = 0,
	YenShow = 0,
}

local function isTextGui(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton")
end

local function applyTextGuiState(instance: any, text: string?, richText: boolean?)
	if text ~= nil then
		instance.Text = text
		instance:SetAttribute("Text", text)
	end

	if richText ~= nil then
		instance.RichText = richText
		instance:SetAttribute("RichText", richText)
	end
end

local function setMessageTransparency(instance: Instance, transparency: number)
	for _, descendant in instance:GetDescendants() do
		if isTextGui(descendant) then
			descendant.TextTransparency = transparency
			descendant.TextStrokeTransparency = math.clamp(transparency, 0, 1)
			descendant:SetAttribute("TextTransparency", transparency)
			descendant:SetAttribute("TextStrokeTransparency", math.clamp(transparency, 0, 1))
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			descendant.ImageTransparency = transparency
			descendant:SetAttribute("ImageTransparency", transparency)
		elseif descendant:IsA("UIStroke") then
			descendant.Transparency = transparency
		end
	end

	if isTextGui(instance) then
		instance.TextTransparency = transparency
		instance.TextStrokeTransparency = math.clamp(transparency, 0, 1)
		instance:SetAttribute("TextTransparency", transparency)
		instance:SetAttribute("TextStrokeTransparency", math.clamp(transparency, 0, 1))
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		instance:SetAttribute("ImageTransparency", transparency)
		instance.ImageTransparency = transparency
	end
end

local function setRichText(instance: Instance, enabled: boolean)
	if isTextGui(instance) then
		applyTextGuiState(instance, nil, enabled)
	end

	for _, descendant in instance:GetDescendants() do
		if isTextGui(descendant) then
			applyTextGuiState(descendant, nil, enabled)
		end
	end
end

local function setFirstMessageText(instance: Instance, text: string)
	if isTextGui(instance) then
		applyTextGuiState(instance, text, true)
		return
	end

	for _, descendant in instance:GetDescendants() do
		if isTextGui(descendant) then
			applyTextGuiState(descendant, text, true)
			return
		end
	end
end

IndexFeature.Install(MainGuiController)
OfflineFeature.Install(MainGuiController)
RebirthFeature.Install(MainGuiController)
SettingsFeature.Install(MainGuiController)
ShopFeature.Install(MainGuiController)

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
		if not indexWarnedMissingGui then
			indexWarnedMissingGui = true
			warn("[MainGuiController] PlayerGui not found yet; IndexFrame cannot open.")
		end
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

function MainGuiController:getOfflineEarningFrame(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local frame = mainGui:FindFirstChild("OfflineEarning")
	return if frame and frame:IsA("GuiObject") then frame else nil
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

function MainGuiController:ShowRateUpgradeMessage(gain: number, upgradeAmount: number?)
	gain = math.max(math.floor(gain), 0)
	if gain <= 0 then
		return
	end

	upgradeAmount = math.max(math.floor(upgradeAmount or 0), 0)
	local pluralSuffix = if upgradeAmount == 1 then "" else "s"
	local upgradeText = if upgradeAmount > 0
		then tostring(upgradeAmount) .. " Rate upgrade" .. pluralSuffix
		else "+" .. FormatUtil.formatNumber(gain) .. " Rate"
	local gainText = if upgradeAmount > 0
		then ' <font color="#47FF6A">(+' .. FormatUtil.formatNumber(gain) .. " Rate)</font>"
		else ""

	self:showMessage(
		"RateUpgrade:" .. tostring(gain) .. ":" .. tostring(upgradeAmount),
		"You bought " .. upgradeText .. gainText
	)
end

function MainGuiController:ShowGroupRewardMessage(amount: number)
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return
	end

	self:showMessage(
		"GroupReward:" .. amount,
		'You claimed <font color="#FFD86B">' .. Pricing.formatYen(amount) .. "</font>"
	)
end

function MainGuiController:ShowOfflineRewardMessage(amount: number)
	amount = math.max(math.floor(amount), 0)
	if amount <= 0 then
		return
	end

	self:showMessage(
		"OfflineReward:" .. amount,
		'You claimed <font color="#FFD86B">' .. Pricing.formatYen(amount) .. "</font> offline earnings"
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

function MainGuiController:ShowMissingGamePassMessage()
	self:showMessage("MissingGamePass", "You don't own this gamepass!")
end

function MainGuiController:ShowAlreadyOwnGamePassMessage()
	self:showMessage("AlreadyOwnGamePass", "You already own this gamepass!")
end

function MainGuiController:ShowAlreadyPurchasedStarterPackMessage()
	self:showMessage("AlreadyStarterPack", "You already purchased the Starter Pack!")
end

function MainGuiController:ShowSettingCooldownMessage(seconds: number)
	self:showMessage("SettingCooldown", "Please wait " .. tostring(math.ceil(seconds)) .. "s before switching again.")
end

function MainGuiController:ShowMissingRebirthTierMessage()
	self:showMessage("RebirthMissingTier", "You dont have the Required Tier neccesary to rebirth.")
end

function MainGuiController:ShowRebirthMessage(rebirths: number, tokenReward: number?)
	tokenReward = math.max(math.floor(tokenReward or 0), 0)
	local tokenText = ""
	if tokenReward > 0 then
		tokenText = ' <font color="#47FF6A">+' .. FormatUtil.formatNumber(tokenReward or 0) .. " Rebirth Tokens.</font>"
	end

	self:showMessage(
		"Rebirth:" .. tostring(rebirths),
		'Rebirth complete! <font color="#FFD86B">Yen Boost upgraded.</font>' .. tokenText
	)
end

function MainGuiController:ShowRebirthUpgradeMessage(upgradeName: string)
	self:showMessage("RebirthUpgrade:" .. upgradeName, '<font color="#47FF6A">' .. upgradeName .. " upgraded!</font>")
end

function MainGuiController:ShowNotEnoughRebirthTokensMessage()
	self:showMessage("NotEnoughTokens", "Not enough Rebirth Tokens!")
end

function MainGuiController:ShowRebirthUpgradeMaxedMessage()
	self:showMessage("UpgradeMaxed", "This upgrade is already MAX!")
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

function MainGuiController:setupFavoritePrompt()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local promptConfig = TycoonConfig.FavoritePrompt or {}
	local itemId = tonumber(promptConfig.ItemId) or 0
	if itemId <= 0 or PlayerDataController:Get("FavoritePromptShown") == true then
		return
	end

	task.delay(tonumber(promptConfig.Delay) or 60, function()
		if PlayerDataController:Get("FavoritePromptShown") == true then
			return
		end

		local ok, err = pcall(function()
			AvatarEditorService:PromptSetFavorite(itemId, Enum.AvatarItemType.Asset, true)
		end)
		if not ok then
			warn("[MainGuiController] Favorite prompt failed:", err)
			return
		end

		PlayerDataController:MarkFavoritePromptShown()
	end)
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
	self:setupSettingsFeature()
	self:setupHomeIcon()
	self:setupShopFeature()
	self:setupRebirthFrame()
	self:setupUpgradesFrame()
	self:setupOfflineEarningFrame()
	self:setupIndexFrame()

	if instant then
		animationTokens.ManaBag += 1
		animationTokens.YenShow += 1
		displayedValues.ManaBag = mana
		displayedValues.YenShow = yen
		self:setCounterText("ManaBag", mana)
		self:setCounterText("YenShow", yen)
		self:refreshShopFeature()
		return
	end

	self:animateCounter("ManaBag", mana)
	self:animateCounter("YenShow", yen)
	self:refreshShopFeature()
end

function MainGuiController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:setupSettingsFeature()
	self:setupHomeIcon()
	self:setupShopFeature()
	self:setupRebirthFrame()
	self:setupUpgradesFrame()
	self:setupOfflineEarningFrame()
	self:setupIndexFrame()

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(firstArg, productId, wasPurchased)
		self:onShopProductPromptFinished(firstArg, productId, wasPurchased)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _gamePassId, wasPurchased)
		self:onShopGamePassPromptFinished(player, wasPurchased)
	end)

	task.spawn(function()
		PlayerDataController:WaitForData()
		self:updateAll()
		self:refreshSettingsFeature()
		self:setupFavoritePrompt()
		self:showOfflineEarningAfterDelay()

		PlayerDataController:Observe("ManaInBag", function()
			self:updateManaBag()
		end)

		PlayerDataController:Observe("Yen", function()
			self:updateYenShow()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "DoubleYen" }, function()
			self:refreshSettingsFeature()
			self:refreshShopFeature()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "DoubleMana" }, function()
			self:refreshSettingsFeature()
			self:updateUpgradesFrame()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "StarterPack" }, function()
			self:refreshShopFeature()
		end)

		PlayerDataController:Observe("Rebirths", function()
			self:updateRebirthFrame()
		end)

		PlayerDataController:Observe("RebirthTokens", function()
			self:updateUpgradesFrame()
		end)

		PlayerDataController:Observe("RebirthUpgrades", function()
			self:updateUpgradesFrame()
		end)

		PlayerDataController:Observe({ "RebirthUpgrades", "UnitSpawnTier" }, function()
			self:updateUpgradesFrame()
		end)

		PlayerDataController:Observe({ "RebirthUpgrades", "MoreMana" }, function()
			self:updateUpgradesFrame()
		end)

		PlayerDataController:Observe("UnlockedAnimeDroppers", function()
			self:refreshIndexFrame()
		end)

		PlayerDataController:Observe("Settings", function(settings)
			self:applySettingsEffects(settings)
			self:refreshSettingsToggleVisuals(settings)
		end)
	end)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "MainGui" then
			task.defer(function()
				self:clearShopRuntimeCache()
				self:updateAll(true)
				self:setupSettingsFeature()
				self:setupShopFeature()
				self:setupRebirthFrame()
				self:setupUpgradesFrame()
				self:setupOfflineEarningFrame()
				self:setupIndexFrame()
			end)
		end
	end)
end

return MainGuiController
