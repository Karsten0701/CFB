local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")
local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Icon = require(ReplicatedStorage.Packages.topbarplus)
local Knit = require(ReplicatedStorage.Packages.knit)
local IndexFeature = require(script.Index)
local OfflineFeature = require(script.Offline)
local RebirthFeature = require(script.Rebirth)
local SettingsFeature = require(script.Settings)
local ShopFeature = require(script.Shop)
local CapsuleFeature = require(script.Capsule)
local TeleportFeature = require(script.Teleport)
local EventFeature = require(script.Event)

local MainGuiController = Knit.CreateController({
	Name = "MainGuiController",
})

local localPlayer = Players.LocalPlayer
local COUNTER_ANIMATION_TIME = 0.5
local COUNTER_ANIMATION_STEPS = 50
local MESSAGE_LIFETIME = 3
local LOADING_BATCH_SIZE = 100
local LOADING_FAKE_DURATION = 3
local LOADING_MAX_WAIT = 5
local LOADING_FORCED_FINISH_DURATION = 0.45
local NEW_UNIT_POPUP_HOLD_TIME = 2.4
local YEN_ICON_IMAGE = "rbxassetid://96573285096968"
local REBIRTH_TOKEN_ICON_IMAGE = "rbxassetid://107689343391713"

local displayedValues = {
	ManaBag = 0,
	YenShow = 0,
}

local homeIcon = nil
local lastHomeTeleportAt = 0
local feedbackIcon = nil
local feedbackPromptOpen = false
local lastFeedbackPromptAt = 0
local activeMessages = {}
local nextMessageLayoutOrder = 0
local indexWarnedMissingGui = false
local loadingScreenFinished = false
local loadingScreenRunning = false
local unlockedDropperCache: { [number]: boolean }? = nil
local newUnitPopupQueue: { number } = {}
local newUnitPopupRunning = false
local currencyDisplayMode: "Yen" | "RebirthTokens" = "Yen"

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

local function getTextLabel(root: Instance?, name: string): TextLabel?
	local label = root and root:FindFirstChild(name, true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function getImageGui(root: Instance?, name: string): (ImageLabel | ImageButton)?
	local image = root and root:FindFirstChild(name, true)
	return if image and (image:IsA("ImageLabel") or image:IsA("ImageButton")) then image else nil
end

local function getGuiObject(root: Instance?, name: string): GuiObject?
	local object = root and root:FindFirstChild(name, true)
	return if object and object:IsA("GuiObject") then object else nil
end

local function setGuiObjectTransparency(root: Instance, transparency: number, minimumFrameTransparency: number?)
	local frameTransparency = if minimumFrameTransparency ~= nil
		then math.max(transparency, minimumFrameTransparency)
		else transparency

	if root:IsA("Frame") or root:IsA("ScrollingFrame") then
		root.BackgroundTransparency = frameTransparency
	elseif root:IsA("ImageLabel") or root:IsA("ImageButton") then
		root.ImageTransparency = transparency
	elseif isTextGui(root) then
		root.TextTransparency = transparency
		root.TextStrokeTransparency = math.clamp(transparency, 0, 1)
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Frame") or descendant:IsA("ScrollingFrame") then
			descendant.BackgroundTransparency = frameTransparency
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			descendant.ImageTransparency = transparency
		elseif isTextGui(descendant) then
			descendant.TextTransparency = transparency
			descendant.TextStrokeTransparency = math.clamp(transparency, 0, 1)
		elseif descendant:IsA("UIStroke") then
			descendant.Transparency = transparency
		end
	end
end

local function shouldPreloadInstance(instance: Instance): boolean
	return instance:IsA("ImageLabel")
		or instance:IsA("ImageButton")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("MeshPart")
		or instance:IsA("SpecialMesh")
		or instance:IsA("Sound")
		or instance:IsA("Animation")
		or instance:IsA("VideoFrame")
end

local function getPreloadTargets(mainGui: Instance?): { Instance }
	local targets = {}
	local seen: { [Instance]: boolean } = {}

	local function add(instance: Instance?)
		if instance and shouldPreloadInstance(instance) and not seen[instance] then
			seen[instance] = true
			table.insert(targets, instance)
		end
	end

	local function addTree(instance: Instance?)
		if not instance then
			return
		end

		add(instance)
		for _, descendant in instance:GetDescendants() do
			add(descendant)
		end
	end

	addTree(mainGui)
	addTree(ReplicatedStorage:FindFirstChild("Assets"))

	return targets
end

IndexFeature.Install(MainGuiController)
OfflineFeature.Install(MainGuiController)
RebirthFeature.Install(MainGuiController)
SettingsFeature.Install(MainGuiController)
ShopFeature.Install(MainGuiController)
CapsuleFeature.Install(MainGuiController)
TeleportFeature.Install(MainGuiController)
EventFeature.Install(MainGuiController)

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

function MainGuiController:getCounterContainer(containerName: string): Instance?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	return mainGui:FindFirstChild(containerName)
end

function MainGuiController:getCurrencyIcon(containerName: string): (ImageLabel | ImageButton)?
	local container = self:getCounterContainer(containerName)
	if not container then
		return nil
	end

	local coinIcon = container:FindFirstChild("coinicon", true) or container:FindFirstChild("CoinIcon", true)
	if coinIcon and (coinIcon:IsA("ImageLabel") or coinIcon:IsA("ImageButton")) then
		return coinIcon
	end

	for _, name in { "Icon", "ImageLabel" } do
		local icon = container:FindFirstChild(name, true)
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			return icon
		end
	end

	return nil
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

function MainGuiController:getLoadingScreen(): GuiObject?
	local mainGui = self:getMainGui()
	return getGuiObject(mainGui, "LoadingScreen")
end

function MainGuiController:getNewUnitPopup(): GuiObject?
	local mainGui = self:getMainGui()
	return getGuiObject(mainGui, "NewUnitPopup")
end

function MainGuiController:setLoadingProgress(progress: number)
	local loadingScreen = self:getLoadingScreen()
	if not loadingScreen then
		return
	end

	progress = math.clamp(progress, 0, 1)
	local filler = getGuiObject(loadingScreen, "Filler")
	if filler then
		filler.AnchorPoint = Vector2.new(0, filler.AnchorPoint.Y)
		filler.Position = UDim2.new(0, 0, filler.Position.Y.Scale, filler.Position.Y.Offset)
		TweenService:Create(filler, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(progress, 0, filler.Size.Y.Scale, filler.Size.Y.Offset),
		}):Play()
	end

	local percentageLabel = getTextLabel(loadingScreen, "LoadingPercentage")
	if percentageLabel then
		percentageLabel.Text = tostring(math.floor(progress * 100 + 0.5)) .. "%"
	end
end

function MainGuiController:finishLoadingScreen()
	local loadingScreen = self:getLoadingScreen()
	if not loadingScreen or loadingScreenFinished then
		return
	end

	loadingScreenFinished = true
	self:setLoadingProgress(1)

	local startPosition = loadingScreen.Position
	local targetPosition = startPosition - UDim2.fromScale(0, 1.25)
	local tween = TweenService:Create(
		loadingScreen,
		TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut),
		{ Position = targetPosition }
	)
	tween:Play()
	tween.Completed:Connect(function()
		if loadingScreen.Parent then
			loadingScreen.Visible = false
			loadingScreen.Position = startPosition
		end
	end)
end

function MainGuiController:startLoadingScreen()
	if loadingScreenRunning or loadingScreenFinished then
		return
	end

	loadingScreenRunning = true
	task.spawn(function()
		local mainGui = self:getMainGui()
		local loadingScreen = self:getLoadingScreen()
		local deadline = os.clock() + 10
		while (not mainGui or not loadingScreen) and os.clock() < deadline do
			task.wait(0.1)
			mainGui = self:getMainGui()
			loadingScreen = self:getLoadingScreen()
		end
		if not loadingScreen then
			loadingScreenRunning = false
			return
		end

		loadingScreen.Visible = true
		self:setLoadingProgress(0)

		local targets = getPreloadTargets(mainGui)
		local total = math.max(#targets, 1)
		local loaded = 0
		local preloadDone = false
		local startedAt = os.clock()

		task.spawn(function()
			for index = 1, #targets, LOADING_BATCH_SIZE do
				local batch = {}
				for batchIndex = index, math.min(index + LOADING_BATCH_SIZE - 1, #targets) do
					table.insert(batch, targets[batchIndex])
				end

				pcall(function()
					ContentProvider:PreloadAsync(batch)
				end)

				loaded = math.min(index + #batch - 1, total)
				task.wait()
			end

			preloadDone = true
		end)

		while not preloadDone and os.clock() - startedAt < LOADING_MAX_WAIT do
			local elapsed = os.clock() - startedAt
			local fakeProgress = math.clamp(elapsed / LOADING_FAKE_DURATION, 0, 0.92)
			local assetProgress = math.clamp(loaded / total, 0, 1)
			self:setLoadingProgress(math.max(fakeProgress, assetProgress * 0.95))

			if elapsed >= LOADING_FAKE_DURATION or assetProgress >= 0.95 then
				break
			end

			task.wait(0.05)
		end

		if not preloadDone and os.clock() - startedAt >= LOADING_MAX_WAIT then
			local forceStartedAt = os.clock()
			while os.clock() - forceStartedAt < LOADING_FORCED_FINISH_DURATION do
				local alpha = math.clamp((os.clock() - forceStartedAt) / LOADING_FORCED_FINISH_DURATION, 0, 1)
				self:setLoadingProgress(0.92 + alpha * 0.08)
				task.wait(0.05)
			end
		else
			local finishStartedAt = os.clock()
			while os.clock() - finishStartedAt < 0.45 do
				local alpha = math.clamp((os.clock() - finishStartedAt) / 0.45, 0, 1)
				self:setLoadingProgress(0.92 + alpha * 0.08)
				task.wait(0.03)
			end
		end

		self:finishLoadingScreen()
		loadingScreenRunning = false
	end)
end

function MainGuiController:setNewUnitPopupContent(tier: number)
	local popup = self:getNewUnitPopup()
	if not popup then
		return
	end

	local tierData = AnimeDroppers.Tiers[tier]
	local displayName = if tierData
		then tierData.DisplayName or tierData.ModelName or ("Tier " .. tier)
		else ("Tier " .. tier)
	local charName = getTextLabel(popup, "CharName")
	if charName then
		charName.Text = string.upper(displayName)
	end

	local altLabel = getTextLabel(popup, "alt")
	if altLabel then
		altLabel.Text = "NEW CHARACTER UNLOCKED!"
	end

	local shadowLabel = getTextLabel(popup, "shadow")
	if shadowLabel then
		shadowLabel.Text = string.upper(displayName)
	end

	local icon = getImageGui(popup, "CharIcon")
	if icon and tierData then
		local image = self:getConfiguredUnitIcon(tierData)
		if image ~= "" then
			icon.Image = image
		end
	end
end

function MainGuiController:playNewUnitPopup(tier: number)
	local popup = self:getNewUnitPopup()
	if not popup then
		return
	end

	self:setNewUnitPopupContent(tier)

	local originalPosition = popup.Position
	local hiddenPosition = originalPosition - UDim2.fromScale(0, 1.25)
	popup.Position = hiddenPosition
	popup.Visible = true
	setGuiObjectTransparency(popup, 1, 0.2)

	local popTargets = {}
	for _, name in { "alt", "CharName", "shadow", "CharIcon" } do
		local object = popup:FindFirstChild(name, true)
		if object and object:IsA("GuiObject") then
			local scale = object:FindFirstChild("UnlockPopScale")
			if not scale or not scale:IsA("UIScale") then
				scale = Instance.new("UIScale")
				scale.Name = "UnlockPopScale"
				scale.Parent = object
			end
			scale.Scale = 0.15
			table.insert(popTargets, scale)
		end
	end

	TweenService:Create(popup, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = originalPosition,
	}):Play()

	local fadeProgress = Instance.new("NumberValue")
	fadeProgress.Value = 1
	local fadeConnection = fadeProgress.Changed:Connect(function(value)
		setGuiObjectTransparency(popup, value, 0.2)
	end)
	TweenService:Create(fadeProgress, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = 0,
	}):Play()

	task.delay(0.2, function()
		for _, scale in popTargets do
			if scale.Parent then
				TweenService:Create(scale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end
		end
	end)

	task.delay(NEW_UNIT_POPUP_HOLD_TIME, function()
		if not popup.Parent then
			return
		end

		local outTween = TweenService:Create(
			popup,
			TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Position = hiddenPosition }
		)
		local fadeOut = Instance.new("NumberValue")
		fadeOut.Value = 0
		local fadeOutConnection = fadeOut.Changed:Connect(function(value)
			setGuiObjectTransparency(popup, value, 0.2)
		end)
		TweenService:Create(fadeOut, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Value = 1,
		}):Play()
		outTween:Play()
		outTween.Completed:Connect(function()
			fadeConnection:Disconnect()
			fadeProgress:Destroy()
			fadeOutConnection:Disconnect()
			fadeOut:Destroy()
			if popup.Parent then
				popup.Visible = false
				popup.Position = originalPosition
				setGuiObjectTransparency(popup, 0, 0.2)
			end
		end)
	end)
end

function MainGuiController:queueNewUnitPopup(tier: number)
	table.insert(newUnitPopupQueue, tier)
	if newUnitPopupRunning then
		return
	end

	newUnitPopupRunning = true
	task.spawn(function()
		while #newUnitPopupQueue > 0 do
			local nextTier = table.remove(newUnitPopupQueue, 1)
			SoundUtil.TierUnlock()
			self:playNewUnitPopup(nextTier)
			task.wait(NEW_UNIT_POPUP_HOLD_TIME + 0.7)
		end
		newUnitPopupRunning = false
	end)
end

function MainGuiController:onUnlockedAnimeDroppersChanged(unlockedDroppers: any)
	self:refreshIndexFrame()
	if type(unlockedDroppers) ~= "table" then
		return
	end

	if unlockedDropperCache == nil then
		unlockedDropperCache = {}
		for tier = 1, AnimeDroppers.MaxTier do
			if self:isAnimeDropperUnlocked(unlockedDroppers, tier) then
				unlockedDropperCache[tier] = true
			end
		end
		return
	end

	for tier = 1, AnimeDroppers.MaxTier do
		local unlocked = self:isAnimeDropperUnlocked(unlockedDroppers, tier)
		if unlocked and not unlockedDropperCache[tier] then
			unlockedDropperCache[tier] = true
			self:queueNewUnitPopup(tier)
		end
	end
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

function MainGuiController:ShowCapsuleRewardMessage(rewardTier: number?)
	local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
	local tier = math.max(math.floor(rewardTier or 1), 1)
	local tierData = AnimeDroppers.Tiers[tier]
	local displayName = if tierData then tierData.DisplayName else ("Tier " .. tier)
	local tierDisplayName = "[T" .. tostring(tier) .. "] " .. displayName

	self:showMessage(
		"CapsuleReward:" .. tier,
		'Capsule opened! You received <font color="#FF8BE7">' .. tierDisplayName .. "</font>"
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
		then FormatUtil.formatNumber(upgradeAmount or 0) .. " Rate upgrade" .. pluralSuffix
		else "+" .. FormatUtil.formatNumber(gain) .. " Rate"
	local gainText = if upgradeAmount > 0
		then ' <font color="#47FF6A">(+' .. FormatUtil.formatNumber(gain) .. " Rate)</font>"
		else ""

	self:showMessage(
		"RateUpgrade:" .. FormatUtil.formatNumber(gain or 0) .. ":" .. FormatUtil.formatNumber(upgradeAmount or 0),
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

function MainGuiController:ShowGroupRewardReadyMessage()
	self:showMessage("GroupRewardReady", '<font color="#47FF6A">Group reward is ready to claim!</font>')
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

function MainGuiController:ShowRebirthReadyMessage()
	self:showMessage("RebirthReady", '<font color="#47FF6A">You can rebirth now!</font>')
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

function MainGuiController:ShowNotEnoughYenMessage()
	self:showMessage("NotEnoughYen", "Not enough Yen!")
end

function MainGuiController:ShowRebirthUpgradeMaxedMessage()
	self:showMessage("UpgradeMaxed", "This upgrade is already MAX!")
end

function MainGuiController:ShowMaxButtonLockedMessage()
	self:showMessage("MaxButtonLocked", "Unlock this button in the Rebirth Upgrades.")
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

function MainGuiController:setupFeedbackIcon()
	if feedbackIcon then
		return
	end

	feedbackIcon = Icon.new()
		:setName("Feedback")
		:setLabel("Feedback")
		:setCaption("Send feedback")
		:setOrder(9999)
		:align("Right")
		:oneClick(true)

	feedbackIcon:modifyTheme({
		{ "Widget", "MinimumWidth", 118 },
		{ "Widget", "DesiredWidth", 132 },
		{ "IconLabel", "TextSize", 17 },
	})

	feedbackIcon.selected:Connect(function()
		local now = os.clock()
		if feedbackPromptOpen or now - lastFeedbackPromptAt < 2 then
			return
		end

		feedbackPromptOpen = true
		lastFeedbackPromptAt = now
		task.spawn(function()
			local success, err = pcall(function()
				SocialService:PromptFeedbackSubmissionAsync()
			end)

			feedbackPromptOpen = false
			if not success then
				warn("[MainGuiController] Feedback prompt failed:", err)
				self:showMessage("FeedbackUnavailable", "Feedback is unavailable right now.")
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
		if currencyDisplayMode == "RebirthTokens" then
			return FormatUtil.formatNumber(value) .. " Rebirth Tokens"
		end

		return Pricing.formatYen(value)
	end

	return FormatUtil.formatNumber(value)
end

function MainGuiController:setCurrencyDisplayMode(mode: "Yen" | "RebirthTokens")
	local changed = currencyDisplayMode ~= mode
	currencyDisplayMode = mode
	local icon = self:getCurrencyIcon("YenShow")
	if icon then
		icon.Image = if mode == "RebirthTokens" then REBIRTH_TOKEN_ICON_IMAGE else YEN_ICON_IMAGE
	end

	if changed then
		animationTokens.YenShow += 1
	end
	self:updateYenShow()
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
	local value = if currencyDisplayMode == "RebirthTokens"
		then PlayerDataController:Get("RebirthTokens") or 0
		else PlayerDataController:Get("Yen") or 0
	self:animateCounter("YenShow", value)
end

function MainGuiController:updateAll(instant: boolean?)
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local mana = math.max(math.floor(PlayerDataController:Get("ManaInBag") or 0), 0)
	local yen = math.max(math.floor(PlayerDataController:Get("Yen") or 0), 0)
	local yenShowValue = if currencyDisplayMode == "RebirthTokens"
		then math.max(math.floor(PlayerDataController:Get("RebirthTokens") or 0), 0)
		else yen
	self:setupSettingsFeature()
	self:setupHomeIcon()
	self:setupFeedbackIcon()
	self:setupShopFeature()
	self:setupRebirthFrame()
	self:setupUpgradesFrame()
	self:setupOfflineEarningFrame()
	self:setupIndexFrame()
	self:setupEventFrame()
	local newUnitPopup = self:getNewUnitPopup()
	if newUnitPopup and not newUnitPopupRunning then
		newUnitPopup.Visible = false
	end

	if instant then
		animationTokens.ManaBag += 1
		animationTokens.YenShow += 1
		displayedValues.ManaBag = mana
		displayedValues.YenShow = yenShowValue
		self:setCounterText("ManaBag", mana)
		self:setCounterText("YenShow", yenShowValue)
		self:refreshShopFeature()
		return
	end

	self:animateCounter("ManaBag", mana)
	self:animateCounter("YenShow", yenShowValue)
	self:refreshShopFeature()
end

function MainGuiController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:startLoadingScreen()
	self:setupSettingsFeature()
	self:setupHomeIcon()
	self:setupFeedbackIcon()
	self:setupShopFeature()
	self:setupRebirthFrame()
	self:setupUpgradesFrame()
	self:setupOfflineEarningFrame()
	self:setupIndexFrame()
	self:setupOpenCapsuleFrame()
	self:setupTeleportFrame()
	self:setupEventFeature()
	local newUnitPopup = self:getNewUnitPopup()
	if newUnitPopup then
		newUnitPopup.Visible = false
	end

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(firstArg, productId, wasPurchased)
		self:onShopProductPromptFinished(firstArg, productId, wasPurchased)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _gamePassId, wasPurchased)
		self:onShopGamePassPromptFinished(player, wasPurchased)
	end)

	task.spawn(function()
		PlayerDataController:WaitForData()
		self:updateAll()
		self:onUnlockedAnimeDroppersChanged(PlayerDataController:Get("UnlockedAnimeDroppers"))
		self:syncRebirthReadyState(false)
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
			self:syncRebirthReadyState(false)
		end)

		PlayerDataController:Observe("RebirthTokens", function()
			self:updateUpgradesFrame()
			if currencyDisplayMode == "RebirthTokens" then
				self:updateYenShow()
			end
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

		PlayerDataController:Observe({ "RebirthUpgrades", "BetterMaxButton" }, function()
			self:updateUpgradesFrame()
		end)

		PlayerDataController:Observe("UnlockedAnimeDroppers", function()
			self:onUnlockedAnimeDroppersChanged(PlayerDataController:Get("UnlockedAnimeDroppers"))
		end)

		PlayerDataController:Observe("Units", function()
			self:updateRebirthFrame()
			self:syncRebirthReadyState(true)
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
				self:setupOpenCapsuleFrame()
				self:setupTeleportFrame()
				self:setupEventFrame()
				local refreshedNewUnitPopup = self:getNewUnitPopup()
				if refreshedNewUnitPopup and not newUnitPopupRunning then
					refreshedNewUnitPopup.Visible = false
				end
			end)
		end
	end)
end

return MainGuiController
