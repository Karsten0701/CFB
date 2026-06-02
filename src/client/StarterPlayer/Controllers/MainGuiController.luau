local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local TycoonUtil = require(ReplicatedStorage.Shared.Features.Tycoon.TycoonUtil)
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
local doubleYenOfferCache: GuiObject? = nil
local doubleYenOfferScannedGui: Instance? = nil
local settingsIcon = nil
local homeIcon = nil
local boundSettingsFrame: GuiObject? = nil
local lastHomeTeleportAt = 0
local activeMessages = {}
local nextMessageLayoutOrder = 0
local shopConnections: { RBXScriptConnection } = {}
local rebirthConnections: { RBXScriptConnection } = {}
local offlineRewardConnections: { RBXScriptConnection } = {}
local settingsConnections: { RBXScriptConnection } = {}
local indexConnections: { RBXScriptConnection } = {}
local settingsRowCache: { [string]: GuiObject } = {}
local settingsSliderCache: { [string]: { Frame: GuiObject?, Slider: GuiObject?, Label: TextLabel? } } = {}
local settingsToggleTextCache: { [GuiObject]: { TextLabel | TextButton } } = {}
local musicSoundCache: { Sound } = {}
local lastMusicScanAt = -math.huge
local musicEnabledCache = true
local settingsEntitlements: { [string]: boolean } = {}
local settingsEntitlementsLoaded = false
local lastShowOtherTycoonToggleAt = -math.huge
local lastAppliedMusicVolume: number? = nil
local lastAppliedMusicEnabled: boolean? = nil
local lastAppliedSfxVolume: number? = nil
local lastAppliedSoundEnabled: boolean? = nil
local gamePassPromptOpen = false
local rebirthRequestOpen = false
local offlineRewardRequestOpen = false
local offlineRewardClaimed = false
local indexTouchLoopConnection: RBXScriptConnection? = nil
local indexTouchPart: BasePart? = nil
local indexTouchPartConnections: { RBXScriptConnection } = {}
local indexTouchedParts: { [BasePart]: boolean } = {}
local indexTouching = false
local indexClosedByButton = false
local indexWarnedMissingGui = false
local indexWarnedMissingFrame = false
local indexWarnedMissingTouchPart = false

local INDEX_UNLOCKED_COLOR = Color3.fromRGB(255, 255, 255)
local INDEX_LOCKED_COLOR = Color3.fromRGB(0, 0, 0)
local INDEX_TOUCH_DISCOVERY_INTERVAL = 0.5

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

local SETTING_GAMEPASS_REQUIREMENTS = {
	AutoCollect = "AutoCollect",
	AutoDeposit = "AutoDeposit",
}

local SETTING_TOGGLE_COOLDOWNS = {
	ShowOtherTycoons = 3,
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

function MainGuiController:getShopFrame(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local shopFrame = mainGui:FindFirstChild("ShopFrame")
	return if shopFrame and shopFrame:IsA("GuiObject") then shopFrame else nil
end

function MainGuiController:getOfflineEarningFrame(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local frame = mainGui:FindFirstChild("OfflineEarning")
	return if frame and frame:IsA("GuiObject") then frame else nil
end

function MainGuiController:getIndexFrame(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local frame = mainGui:FindFirstChild("IndexFrame")
	if frame and frame:IsA("GuiObject") then
		return frame
	end

	if not indexWarnedMissingFrame then
		indexWarnedMissingFrame = true
		warn("[MainGuiController] MainGui.IndexFrame not found; Index touch cannot open the UI.")
	end

	return nil
end

function MainGuiController:getIndexTemplate(): GuiObject?
	local frame = self:getIndexFrame()
	local scrollingFrame = frame and frame:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return nil
	end

	local template = scrollingFrame:FindFirstChild("Template")
	if template and template:IsA("GuiObject") then
		template.Visible = false
		return template
	end

	return nil
end

function MainGuiController:getConfiguredUnitIcon(tierData: any): string
	local iconId = tierData and (tierData.IconId or tierData.IconID or tierData.IconAssetId)
	if type(iconId) == "number" and iconId > 0 then
		return "rbxassetid://" .. tostring(iconId)
	elseif type(iconId) == "string" and iconId ~= "" and iconId ~= "rbxassetid://0" then
		if tonumber(iconId) then
			return "rbxassetid://" .. iconId
		end

		return iconId
	end

	local current: Instance = ReplicatedStorage
	for _, childName in TycoonConfig.AssetsPath do
		local nextChild = current:FindFirstChild(childName)
		if not nextChild then
			return ""
		end
		current = nextChild
	end

	local model = current:FindFirstChild(tierData.ModelName)
	if not model then
		return ""
	end

	for _, attributeName in { "IconId", "IconID", "IconAssetId" } do
		local attributeIcon = model:GetAttribute(attributeName)
		if type(attributeIcon) == "number" and attributeIcon > 0 then
			return "rbxassetid://" .. tostring(attributeIcon)
		elseif type(attributeIcon) == "string" and attributeIcon ~= "" then
			return if tonumber(attributeIcon) then "rbxassetid://" .. attributeIcon else attributeIcon
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Decal") or descendant:IsA("Texture") then
			if descendant.Texture ~= "" then
				return descendant.Texture
			end
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			if descendant.Image ~= "" then
				return descendant.Image
			end
		end
	end

	return ""
end

function MainGuiController:isAnimeDropperUnlocked(unlockedDroppers: any, tier: number): boolean
	if type(unlockedDroppers) ~= "table" then
		return tier == 1
	end

	return unlockedDroppers[tier] == true or unlockedDroppers[tostring(tier)] == true
end

function MainGuiController:clearIndexConnections()
	for _, connection in indexConnections do
		connection:Disconnect()
	end

	table.clear(indexConnections)
end

function MainGuiController:connectIndexGuiActivated(guiObject: GuiObject, callback: () -> ())
	local clickable = self:getClickableGui(guiObject)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		table.insert(indexConnections, clickable.Activated:Connect(callback))
	else
		table.insert(
			indexConnections,
			clickable.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					callback()
				end
			end)
		)
	end
end

function MainGuiController:refreshIndexFrame()
	local frame = self:getIndexFrame()
	if not frame then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local unlockedDroppers = PlayerDataController:Get("UnlockedAnimeDroppers")

	for _, child in frame:GetDescendants() do
		if not child:IsA("GuiObject") or child:GetAttribute("IndexUnitClone") ~= true then
			continue
		end

		local tier = math.floor(tonumber(child:GetAttribute("Tier")) or 0)
		local unlocked = self:isAnimeDropperUnlocked(unlockedDroppers, tier)
		local tierData = AnimeDroppers.Tiers[tier]
		local nameLabel = child:FindFirstChild("Name", true)
		if nameLabel and (nameLabel:IsA("TextLabel") or nameLabel:IsA("TextButton")) then
			nameLabel.Text = if unlocked and tierData
				then tierData.DisplayName or tierData.ModelName or ("Unit " .. tostring(tier))
				else "???"
		end

		local icon = child:FindFirstChild("Icon", true)
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			icon.ImageColor3 = if unlocked then INDEX_UNLOCKED_COLOR else INDEX_LOCKED_COLOR
		end
	end
end

function MainGuiController:buildIndexFrame()
	local frame = self:getIndexFrame()
	local template = self:getIndexTemplate()
	if not frame or not template then
		return
	end

	local scrollingFrame = template.Parent
	if not scrollingFrame then
		return
	end

	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("IndexUnitClone") == true then
			child:Destroy()
		end
	end

	for tier = 1, AnimeDroppers.MaxTier do
		local tierData = AnimeDroppers.Tiers[tier]
		if not tierData then
			continue
		end

		local item = template:Clone()
		item.Name = "Unit" .. tostring(tier)
		item.LayoutOrder = tier
		item.Visible = true
		item:SetAttribute("IndexUnitClone", true)
		item:SetAttribute("Tier", tier)

		local nameLabel = item:FindFirstChild("Name", true)
		if nameLabel and (nameLabel:IsA("TextLabel") or nameLabel:IsA("TextButton")) then
			nameLabel.Text = tierData.DisplayName or tierData.ModelName or ("Unit " .. tostring(tier))
		end

		local icon = item:FindFirstChild("Icon", true)
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			local configuredIcon = self:getConfiguredUnitIcon(tierData)
			if configuredIcon ~= "" then
				icon.Image = configuredIcon
			end
		end

		item.Parent = scrollingFrame
	end

	self:refreshIndexFrame()
end

function MainGuiController:setIndexFrameOpen(open: boolean)
	local frame = self:getIndexFrame()
	if not frame then
		return
	end

	OpenFrame.SetupFrame(frame)
	OpenFrame.Toggle(frame, open)
end

function MainGuiController:getOwnIndexTouchPart(): BasePart?
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local tycoonName = PlayerDataController:Get("TycoonName")

	local tycoon = if tycoonName and tycoonName ~= "" then TycoonUtil.getTycoonByName(tycoonName) else nil
	if not tycoon then
		local tycoonsFolder = TycoonUtil.getTycoonsFolder()
		if tycoonsFolder then
			for _, candidate in tycoonsFolder:GetChildren() do
				if candidate:GetAttribute("Owner") == localPlayer.UserId then
					tycoon = candidate
					break
				end
			end
		end
	end

	if not tycoon then
		return nil
	end

	local indexModel = tycoon:FindFirstChild("Index", true)
	local touchPart = indexModel and indexModel:FindFirstChild("TouchPart", true)
	if touchPart and touchPart:IsA("BasePart") then
		return touchPart
	end

	local fallbackTouchPart = tycoon:FindFirstChild("TouchPart", true)
	if fallbackTouchPart and fallbackTouchPart:IsA("BasePart") and fallbackTouchPart:FindFirstAncestor("Index") then
		return fallbackTouchPart
	end

	if not indexWarnedMissingTouchPart then
		indexWarnedMissingTouchPart = true
		warn("[MainGuiController] Own tycoon Index.TouchPart not found yet.")
	end

	return nil
end

function MainGuiController:isLocalCharacterPart(part: BasePart): boolean
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then
		return false
	end

	return Players:GetPlayerFromCharacter(character) == localPlayer
end

function MainGuiController:updateIndexTouchState(touching: boolean)
	if touching == indexTouching then
		local frame = self:getIndexFrame()
		if touching and not indexClosedByButton and frame and not frame.Visible then
			self:refreshIndexFrame()
			self:setIndexFrameOpen(true)
		end

		return
	end

	indexTouching = touching
	if touching then
		if not indexClosedByButton then
			self:refreshIndexFrame()
			self:setIndexFrameOpen(true)
		end
	else
		indexClosedByButton = false
		self:setIndexFrameOpen(false)
	end
end

function MainGuiController:hasCurrentIndexTouch(): boolean
	for part in indexTouchedParts do
		if part.Parent and self:isLocalCharacterPart(part) then
			return true
		end

		indexTouchedParts[part] = nil
	end

	local touchPart = indexTouchPart
	if not touchPart or not touchPart.Parent then
		return false
	end

	for _, part in touchPart:GetTouchingParts() do
		if part:IsA("BasePart") and self:isLocalCharacterPart(part) then
			indexTouchedParts[part] = true
			return true
		end
	end

	return false
end

function MainGuiController:clearIndexTouchPartConnections()
	for _, connection in indexTouchPartConnections do
		connection:Disconnect()
	end

	table.clear(indexTouchPartConnections)
	table.clear(indexTouchedParts)
	indexTouchPart = nil
	self:updateIndexTouchState(false)
end

function MainGuiController:bindIndexTouchPart(touchPart: BasePart)
	if indexTouchPart == touchPart then
		return
	end

	self:clearIndexTouchPartConnections()
	indexTouchPart = touchPart
	indexWarnedMissingTouchPart = false

	pcall(function()
		touchPart.CanTouch = true
	end)

	table.insert(
		indexTouchPartConnections,
		touchPart.Touched:Connect(function(hit)
			if not hit:IsA("BasePart") or not self:isLocalCharacterPart(hit) then
				return
			end

			indexTouchedParts[hit] = true
			self:updateIndexTouchState(true)
		end)
	)

	table.insert(
		indexTouchPartConnections,
		touchPart.TouchEnded:Connect(function(hit)
			if hit:IsA("BasePart") then
				indexTouchedParts[hit] = nil
			end

			task.defer(function()
				self:updateIndexTouchState(self:hasCurrentIndexTouch())
			end)
		end)
	)

	table.insert(
		indexTouchPartConnections,
		touchPart.Destroying:Connect(function()
			self:clearIndexTouchPartConnections()
		end)
	)

	self:updateIndexTouchState(self:hasCurrentIndexTouch())
end

function MainGuiController:startIndexTouchLoop()
	if indexTouchLoopConnection then
		return
	end

	local elapsed = 0
	indexTouchLoopConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < INDEX_TOUCH_DISCOVERY_INTERVAL then
			return
		end
		elapsed = 0

		local touchPart = self:getOwnIndexTouchPart()
		if touchPart then
			self:bindIndexTouchPart(touchPart)
		elseif indexTouchPart then
			self:clearIndexTouchPartConnections()
		end
	end)
end

function MainGuiController:setupIndexFrame()
	self:clearIndexConnections()

	local frame = self:getIndexFrame()
	if not frame then
		return
	end

	frame.Visible = false
	OpenFrame.SetupFrame(frame)
	self:buildIndexFrame()

	local topBar = frame:FindFirstChild("TopBar")
	local closeButton = topBar and topBar:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiObject") then
		self:connectIndexGuiActivated(closeButton, function()
			if indexTouching then
				indexClosedByButton = true
			end

			self:setIndexFrameOpen(false)
		end)
	end

	self:startIndexTouchLoop()
	if indexTouching and not indexClosedByButton then
		self:setIndexFrameOpen(true)
	end
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

function MainGuiController:ShowRateUpgradeMessage(gain: number)
	gain = math.max(math.floor(gain), 0)
	if gain <= 0 then
		return
	end

	self:showMessage(
		"RateUpgrade:" .. gain,
		'You bought <font color="#47FF6A">+' .. FormatUtil.formatNumber(gain) .. " Rate</font>"
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

function MainGuiController:clearSettingsConnections()
	for _, connection in settingsConnections do
		connection:Disconnect()
	end

	table.clear(settingsConnections)
	table.clear(settingsRowCache)
	table.clear(settingsSliderCache)
	table.clear(settingsToggleTextCache)
end

function MainGuiController:getSettingsRow(rowName: string): GuiObject?
	local cached = settingsRowCache[rowName]
	if cached and cached.Parent then
		return cached
	end

	local frame = self:getSettingsFrame()
	local row = frame and frame:FindFirstChild(rowName, true)
	if row and row:IsA("GuiObject") then
		settingsRowCache[rowName] = row
		return row
	end

	return nil
end

function MainGuiController:getSettingsValue(settingName: string, fallback: any): any
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local value = PlayerDataController:Get({ "Settings", settingName })
	return if value == nil then fallback else value
end

function MainGuiController:setSetting(settingName: string, value: any)
	local PlayerDataController = Knit.GetController("PlayerDataController")
	PlayerDataController:SetSetting(settingName, value)
end

function MainGuiController:ownsSettingGamePass(settingName: string): boolean
	local gamePassKey = SETTING_GAMEPASS_REQUIREMENTS[settingName]
	if not gamePassKey then
		return true
	end

	return settingsEntitlements[gamePassKey] == true
end

function MainGuiController:refreshGamePassSettings()
	if not settingsEntitlementsLoaded then
		return
	end

	for settingName in SETTING_GAMEPASS_REQUIREMENTS do
		local row = self:getSettingsRow(settingName)
		local ownsGamePass = self:ownsSettingGamePass(settingName)
		if not ownsGamePass and self:getSettingsValue(settingName, false) == true then
			self:setSetting(settingName, false)
		end

		if row then
			local enabled = ownsGamePass and self:getSettingsValue(settingName, false) == true
			self:setToggleVisual(row, enabled)
		end
	end
end

function MainGuiController:refreshSettingsToggleVisuals(settings: any)
	if type(settings) ~= "table" then
		return
	end

	local toggleRows = {
		AutoCollect = { Setting = "AutoCollect", Fallback = false },
		AutoDeposit = { Setting = "AutoDeposit", Fallback = false },
		ShowOtherTycoon = { Setting = "ShowOtherTycoons", Fallback = true },
	}

	for rowName, info in toggleRows do
		local row = settingsRowCache[rowName]
		if not row or not row.Parent then
			continue
		end

		local enabled = if settings[info.Setting] == nil then info.Fallback else settings[info.Setting] == true
		if SETTING_GAMEPASS_REQUIREMENTS[info.Setting] and settingsEntitlementsLoaded then
			enabled = enabled and self:ownsSettingGamePass(info.Setting)
		end

		self:setToggleVisual(row, enabled)
	end
end

function MainGuiController:refreshSettingsEntitlements()
	local MonetizationService = Knit.GetService("MonetizationService")
	MonetizationService:GetEntitlements()
		:andThen(function(entitlements)
			settingsEntitlements = entitlements or {}
			settingsEntitlementsLoaded = true
			self:refreshGamePassSettings()
		end)
		:catch(function(err)
			warn("[MainGuiController] Failed to refresh settings gamepasses:", err)
		end)
end

function MainGuiController:setToggleVisual(row: GuiObject, enabled: boolean)
	row:SetAttribute("Enabled", enabled)
	row.BackgroundTransparency = if enabled then 0.05 else 0.25
	row.BackgroundColor3 = if enabled then Color3.fromRGB(32, 210, 95) else Color3.fromRGB(45, 45, 45)

	local textTargets = settingsToggleTextCache[row]
	if not textTargets then
		textTargets = {}
		settingsToggleTextCache[row] = textTargets

		for _, descendant in row:GetDescendants() do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				local lowerName = string.lower(descendant.Name)
				if lowerName == "value" or lowerName == "status" or lowerName == "toggle" then
					table.insert(textTargets, descendant)
				end
			end
		end
	end

	for index = #textTargets, 1, -1 do
		local descendant = textTargets[index]
		if not descendant.Parent then
			table.remove(textTargets, index)
			continue
		end

		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			descendant.Text = if enabled then "ON" else "OFF"
		end
	end
end

function MainGuiController:connectSettingsActivated(guiObject: GuiObject, callback: () -> ())
	local clickable = self:getClickableGui(guiObject)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		table.insert(settingsConnections, clickable.Activated:Connect(callback))
	else
		table.insert(
			settingsConnections,
			clickable.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					callback()
				end
			end)
		)
	end
end

function MainGuiController:setupSettingsToggle(rowName: string, settingName: string, fallback: boolean)
	local row = self:getSettingsRow(rowName)
	if not row then
		return
	end

	local function refresh()
		local enabled = self:getSettingsValue(settingName, fallback) == true
		if SETTING_GAMEPASS_REQUIREMENTS[settingName] and settingsEntitlementsLoaded then
			enabled = enabled and self:ownsSettingGamePass(settingName)
		end

		self:setToggleVisual(row, enabled)
	end

	refresh()
	self:connectSettingsActivated(row, function()
		local toggleCooldown = SETTING_TOGGLE_COOLDOWNS[settingName]
		if toggleCooldown then
			local now = os.clock()
			local lastToggleAt = if settingName == "ShowOtherTycoons" then lastShowOtherTycoonToggleAt else -math.huge
			local remaining = toggleCooldown - (now - lastToggleAt)
			if remaining > 0 then
				self:ShowSettingCooldownMessage(remaining)
				refresh()
				return
			end

			if settingName == "ShowOtherTycoons" then
				lastShowOtherTycoonToggleAt = now
			end
		end

		local nextValue = self:getSettingsValue(settingName, fallback) ~= true
		if nextValue and SETTING_GAMEPASS_REQUIREMENTS[settingName] and not self:ownsSettingGamePass(settingName) then
			self:ShowMissingGamePassMessage()
			self:setToggleVisual(row, false)
			self:refreshSettingsEntitlements()
			return
		end

		self:setSetting(settingName, nextValue)
		self:setToggleVisual(row, nextValue)
		if settingName == "Sound" then
			SoundUtil.SetSoundEnabled(nextValue)
		elseif settingName == "Music" then
			musicEnabledCache = nextValue
			self:applyMusicVolume(math.clamp(tonumber(self:getSettingsValue("musicVolume", 1)) or 1, 0, 1))
		end
	end)
end

function MainGuiController:setupAutoMergeSetting()
	local row = self:getSettingsRow("AutoMerge")
	if not row then
		return
	end

	local textBox = row:FindFirstChildWhichIsA("TextBox", true)
	if not textBox then
		return
	end

	local currentValue = math.clamp(math.floor(tonumber(self:getSettingsValue("AutoMergeAt", 100)) or 100), 0, 100)
	textBox.Text = tostring(currentValue)

	table.insert(
		settingsConnections,
		textBox.FocusLost:Connect(function()
			local nextValue = math.clamp(math.floor(tonumber(textBox.Text) or currentValue), 0, 100)
			currentValue = nextValue
			textBox.Text = tostring(nextValue)
			self:setSetting("AutoMergeAt", nextValue)
		end)
	)
end

function MainGuiController:findSliderParts(rowName: string): (GuiObject?, GuiObject?, TextLabel?)
	local cached = settingsSliderCache[rowName]
	if cached and cached.Frame and cached.Frame.Parent then
		return cached.Frame, cached.Slider, cached.Label
	end

	local row = self:getSettingsRow(rowName)
	local sliderFrame = row and row:FindFirstChild("SliderFrame", true)
	if not sliderFrame or not sliderFrame:IsA("GuiObject") then
		return nil, nil, nil
	end

	local slider = sliderFrame:FindFirstChild("Slider", true)
	local label = row:FindFirstChild("TextLabel", true)
	local sliderObject = if slider and slider:IsA("GuiObject") then slider else nil
	local labelObject = if label and label:IsA("TextLabel") then label else nil
	settingsSliderCache[rowName] = {
		Frame = sliderFrame,
		Slider = sliderObject,
		Label = labelObject,
	}

	return sliderFrame, sliderObject, labelObject
end

function MainGuiController:applyMusicVolume(volume: number)
	local targetVolume = if musicEnabledCache then volume else 0
	local now = os.clock()

	if now - lastMusicScanAt > 3 then
		lastMusicScanAt = now
		table.clear(musicSoundCache)

		for _, root in { SoundService, workspace } do
			for _, descendant in root:GetDescendants() do
				if not descendant:IsA("Sound") then
					continue
				end

				local lowerName = string.lower(descendant.Name)
				if
					not (
						string.find(lowerName, "music")
						or string.find(lowerName, "song")
						or string.find(lowerName, "theme")
						or string.find(lowerName, "bgm")
					)
				then
					continue
				end

				table.insert(musicSoundCache, descendant)
			end
		end
	end

	for index = #musicSoundCache, 1, -1 do
		local sound = musicSoundCache[index]
		if not sound.Parent then
			table.remove(musicSoundCache, index)
			continue
		end

		local originalVolume = sound:GetAttribute("OriginalVolume")
		if type(originalVolume) ~= "number" then
			originalVolume = sound.Volume
			sound:SetAttribute("OriginalVolume", originalVolume)
		end

		sound.Volume = originalVolume * targetVolume
	end
end

function MainGuiController:applySettingsEffects(settings: any)
	if type(settings) ~= "table" then
		return
	end

	local soundEnabled = settings.Sound ~= false
	local sfxVolume = math.clamp(tonumber(settings.sfxVolume) or 1, 0, 1)
	if soundEnabled ~= lastAppliedSoundEnabled or sfxVolume ~= lastAppliedSfxVolume then
		lastAppliedSoundEnabled = soundEnabled
		lastAppliedSfxVolume = sfxVolume
		SoundUtil.ConfigureFromSettings(settings)
	end

	local musicEnabled = settings.Music ~= false
	local musicVolume = math.clamp(tonumber(settings.musicVolume) or 1, 0, 1)
	if musicEnabled ~= lastAppliedMusicEnabled or musicVolume ~= lastAppliedMusicVolume then
		lastAppliedMusicEnabled = musicEnabled
		lastAppliedMusicVolume = musicVolume
		musicEnabledCache = musicEnabled
		self:applyMusicVolume(musicVolume)
	end
end

function MainGuiController:setupVolumeSlider(rowName: string, settingName: string, setterName: string)
	local sliderFrame, slider, label = self:findSliderParts(rowName)
	if not sliderFrame or not slider then
		return
	end

	local dragging = false
	local currentVolume = math.clamp(tonumber(self:getSettingsValue(settingName, 1)) or 1, 0, 1)
	local function saveVolume(volume: number, force: boolean?)
		if not force then
			return
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		PlayerDataController[setterName](PlayerDataController, volume)
	end

	local function setVisual(volume: number)
		volume = math.clamp(volume, 0, 1)
		slider.Position = UDim2.new(volume, 0, slider.Position.Y.Scale, slider.Position.Y.Offset)
		if label then
			label.Text = tostring(math.floor(volume * 100 + 0.5)) .. "%"
		end
	end

	local function setFromPosition(screenX: number, shouldSave: boolean)
		local x = sliderFrame.AbsolutePosition.X
		local width = math.max(sliderFrame.AbsoluteSize.X, 1)
		local volume = math.clamp((screenX - x) / width, 0, 1)
		currentVolume = volume
		setVisual(volume)

		if settingName == "musicVolume" then
			self:applyMusicVolume(volume)
		elseif settingName == "sfxVolume" then
			SoundUtil.SetLocalSfxVolume(volume)
		end

		if shouldSave then
			saveVolume(volume)
		end
	end

	setVisual(currentVolume)
	if settingName == "musicVolume" then
		musicEnabledCache = self:getSettingsValue("Music", true) == true
		self:applyMusicVolume(currentVolume)
	elseif settingName == "sfxVolume" then
		SoundUtil.SetLocalSfxVolume(currentVolume)
	end

	local function beginDrag(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		dragging = true
		setFromPosition(input.Position.X, true)
	end

	table.insert(settingsConnections, sliderFrame.InputBegan:Connect(beginDrag))
	table.insert(settingsConnections, slider.InputBegan:Connect(beginDrag))
	table.insert(
		settingsConnections,
		UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end

			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				setFromPosition(input.Position.X, true)
			end
		end)
	)
	table.insert(
		settingsConnections,
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = false
				saveVolume(currentVolume, true)
			end
		end)
	)
end

function MainGuiController:setupSettingsFrame()
	self:clearSettingsConnections()

	local frame = self:getSettingsFrame()
	if not frame then
		return
	end

	local topBar = frame:FindFirstChild("TopBar")
	local closeButton = topBar and topBar:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiObject") then
		self:connectSettingsActivated(closeButton, function()
			OpenFrame.Toggle(frame, false)
			if settingsIcon then
				settingsIcon:deselect("CloseButton", settingsIcon)
			end
		end)
	end

	self:setupSettingsToggle("AutoCollect", "AutoCollect", false)
	self:setupSettingsToggle("AutoDeposit", "AutoDeposit", false)
	self:setupSettingsToggle("ShowOtherTycoon", "ShowOtherTycoons", true)
	self:setupAutoMergeSetting()
	self:setupVolumeSlider("Music", "musicVolume", "SetMusicVolume")
	self:setupVolumeSlider("SoundsFX", "sfxVolume", "SetSfxVolume")
	self:refreshGamePassSettings()
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

function MainGuiController:connectRebirthGuiActivated(guiObject: GuiObject, callback: () -> ())
	local clickable = self:getClickableGui(guiObject)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		table.insert(rebirthConnections, clickable.Activated:Connect(callback))
	else
		table.insert(
			rebirthConnections,
			clickable.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					callback()
				end
			end)
		)
	end
end

function MainGuiController:clearRebirthConnections()
	for _, connection in rebirthConnections do
		connection:Disconnect()
	end

	table.clear(rebirthConnections)
end

function MainGuiController:clearOfflineRewardConnections()
	for _, connection in offlineRewardConnections do
		connection:Disconnect()
	end

	table.clear(offlineRewardConnections)
end

function MainGuiController:connectOfflineRewardGuiActivated(guiObject: GuiObject, callback: () -> ())
	local clickable = self:getClickableGui(guiObject)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		table.insert(offlineRewardConnections, clickable.Activated:Connect(callback))
	else
		table.insert(
			offlineRewardConnections,
			clickable.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					callback()
				end
			end)
		)
	end
end

function MainGuiController:getRebirthFrame(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local rebirthFrame = mainGui:FindFirstChild("RebirthFrame")
	return if rebirthFrame and rebirthFrame:IsA("GuiObject") then rebirthFrame else nil
end

function MainGuiController:getRebirthRequiredTier(rebirths: number): number
	local rebirthConfig = TycoonConfig.Rebirth
	return math.max(
		math.floor((rebirthConfig.FirstRequiredTier or 15) + rebirths * (rebirthConfig.RequiredTierStep or 5)),
		1
	)
end

function MainGuiController:getRebirthYenMultiplier(rebirths: number): number
	local rebirthConfig = TycoonConfig.Rebirth
	return (rebirthConfig.BaseYenMultiplier or 1) + rebirths * (rebirthConfig.YenMultiplierPerRebirth or 0)
end

function MainGuiController:formatRebirthMultiplier(multiplier: number): string
	if multiplier % 1 == 0 then
		return tostring(math.floor(multiplier))
	end

	return string.format("%.1f", multiplier)
end

function MainGuiController:setNamedText(root: Instance, name: string, text: string)
	local target = root:FindFirstChild(name, true)
	if target and (target:IsA("TextLabel") or target:IsA("TextButton")) then
		target.Text = text
	end
end

function MainGuiController:getRightSideButton(buttonName: string): GuiObject?
	local mainGui = self:getMainGui()
	local rightSide = mainGui and mainGui:FindFirstChild("RightSide")
	if not rightSide then
		return nil
	end

	local button = rightSide:FindFirstChild(buttonName, true)
	return if button and button:IsA("GuiObject") then button else nil
end

function MainGuiController:updateRebirthFrame(rebirthOverride: number?)
	local frame = self:getRebirthFrame()
	if not frame then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local rebirths = math.max(math.floor(rebirthOverride or PlayerDataController:Get("Rebirths") or 0), 0)
	local nextRebirths = rebirths + 1
	local requiredTier = self:getRebirthRequiredTier(rebirths)
	local nextMultiplier = self:getRebirthYenMultiplier(nextRebirths)

	self:setNamedText(frame, "TierReq", "Reach Tier " .. requiredTier)
	self:setNamedText(frame, "Boost", self:formatRebirthMultiplier(nextMultiplier) .. "x YEN Boost")
end

function MainGuiController:setupRebirthFrame()
	self:clearRebirthConnections()

	local frame = self:getRebirthFrame()
	if not frame then
		return
	end

	OpenFrame.SetupFrame(frame)
	self:updateRebirthFrame()

	local topBar = frame:FindFirstChild("TopBar")
	local closeButton = topBar and topBar:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiObject") then
		self:connectRebirthGuiActivated(closeButton, function()
			OpenFrame.Toggle(frame)
		end)
	end

	local acceptButton = frame:FindFirstChild("AcceptButton", true)
	if acceptButton and acceptButton:IsA("GuiObject") then
		self:connectRebirthGuiActivated(acceptButton, function()
			if rebirthRequestOpen then
				return
			end

			rebirthRequestOpen = true
			local TycoonService = Knit.GetService("TycoonService")
			TycoonService:Rebirth()
				:andThen(function(success, err, rebirths, tokenReward)
					rebirthRequestOpen = false
					if success then
						local TycoonController = Knit.GetController("TycoonController")
						TycoonController:ClearOwnDrops()
						self:ShowRebirthMessage(rebirths or 0, tokenReward or 0)
						self:updateRebirthFrame(rebirths)
						OpenFrame.Toggle(frame, false)
					elseif err == "Required tier missing" then
						self:ShowMissingRebirthTierMessage()
					elseif err then
						warn("[MainGuiController] Rebirth failed:", err)
					end
				end)
				:catch(function(err)
					rebirthRequestOpen = false
					warn("[MainGuiController] Rebirth failed:", err)
				end)
		end)
	end

	local rebirthButton = self:getRightSideButton("RebirthButton")
	if rebirthButton then
		self:connectRebirthGuiActivated(rebirthButton, function()
			self:updateRebirthFrame()
			OpenFrame.Toggle(frame)
		end)
	end
end

function MainGuiController:formatOfflineDuration(seconds: number): string
	seconds = math.max(math.floor(seconds or 0), 0)
	local totalMinutes = math.floor(seconds / 60 + 0.5)
	local hours = math.floor(totalMinutes / 60)
	local minutes = totalMinutes % 60

	if hours <= 0 then
		local minuteLabel = if minutes == 1 then " minute" else " minutes"
		return tostring(minutes) .. minuteLabel
	end

	if minutes <= 0 then
		local hourLabel = if hours == 1 then " hour" else " hours"
		return tostring(hours) .. hourLabel
	end

	local hourLabel = if hours == 1 then " hour and " else " hours and "
	local minuteLabel = if minutes == 1 then " minute" else " minutes"
	return tostring(hours) .. hourLabel .. tostring(minutes) .. minuteLabel
end

function MainGuiController:updateOfflineEarningFrame(payload: any)
	local frame = self:getOfflineEarningFrame()
	if not frame or type(payload) ~= "table" then
		return
	end

	local offlineSeconds = math.max(math.floor(payload.OfflineSeconds or 0), 0)
	local reward = math.max(math.floor(payload.Reward or 0), 0)
	self:setNamedText(frame, "OfflineTime", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflineTimer", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflienTime", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflineReward", Pricing.formatYen(reward))
end

function MainGuiController:claimOfflineReward(frame: GuiObject?)
	if offlineRewardClaimed or offlineRewardRequestOpen then
		if frame then
			OpenFrame.Toggle(frame, false)
		end
		return
	end

	offlineRewardRequestOpen = true
	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:ClaimOfflineReward()
		:andThen(function(success, err, reward)
			offlineRewardRequestOpen = false
			offlineRewardClaimed = true
			if frame then
				OpenFrame.Toggle(frame, false)
			end

			if success then
				self:ShowOfflineRewardMessage(reward or 0)
			elseif err and err ~= "No reward" then
				warn("[MainGuiController] Offline reward failed:", err)
			end
		end)
		:catch(function(err)
			offlineRewardRequestOpen = false
			if frame then
				OpenFrame.Toggle(frame, false)
			end
			warn("[MainGuiController] Offline reward failed:", err)
		end)
end

function MainGuiController:setupOfflineEarningFrame()
	self:clearOfflineRewardConnections()

	local frame = self:getOfflineEarningFrame()
	if not frame then
		return
	end

	frame.Visible = false
	OpenFrame.SetupFrame(frame)

	local topBar = frame:FindFirstChild("TopBar")
	local closeButton = topBar and topBar:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiObject") then
		self:connectOfflineRewardGuiActivated(closeButton, function()
			self:claimOfflineReward(frame)
		end)
	end

	local claimButton = frame:FindFirstChild("Claim", true)
	if claimButton and claimButton:IsA("GuiObject") then
		self:connectOfflineRewardGuiActivated(claimButton, function()
			self:claimOfflineReward(frame)
		end)
	end
end

function MainGuiController:showOfflineEarningAfterDelay()
	if offlineRewardClaimed then
		return
	end

	local offlineConfig = TycoonConfig.OfflineReward or {}
	task.delay(tonumber(offlineConfig.ClaimPopupDelay) or 20, function()
		if offlineRewardClaimed then
			return
		end

		local frame = self:getOfflineEarningFrame()
		if not frame then
			return
		end

		local TycoonService = Knit.GetService("TycoonService")
		TycoonService:GetOfflineReward()
			:andThen(function(success, payload)
				if not success or type(payload) ~= "table" or payload.Eligible ~= true then
					return
				end

				self:updateOfflineEarningFrame(payload)
				OpenFrame.Toggle(frame, true)
			end)
			:catch(function(err)
				warn("[MainGuiController] Failed to get offline reward:", err)
			end)
	end)
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
	self:setupSettingsIcon()
	self:setupSettingsFrame()
	self:setupHomeIcon()
	self:setupShopFrame()
	self:setupRebirthFrame()
	self:setupOfflineEarningFrame()
	self:setupIndexFrame()

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
	self:setupSettingsFrame()
	self:setupHomeIcon()
	self:setupShopFrame()
	self:setupRebirthFrame()
	self:setupOfflineEarningFrame()
	self:setupIndexFrame()

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(firstArg, productId, wasPurchased)
		if isLocalProductPromptFinished(firstArg) then
			if productId == DOUBLE_YEN_PRODUCT.ProductId and wasPurchased == true then
				SoundUtil.Robux()
			end

			doubleYenPromptOpen = false
			self:updateDoubleYenOffer()
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _gamePassId, wasPurchased)
		if player == localPlayer then
			if wasPurchased == true then
				SoundUtil.Robux()
				self:refreshSettingsEntitlements()
			end

			gamePassPromptOpen = false
		end
	end)

	task.spawn(function()
		PlayerDataController:WaitForData()
		self:updateAll()
		self:refreshSettingsEntitlements()
		self:setupFavoritePrompt()
		self:showOfflineEarningAfterDelay()

		PlayerDataController:Observe("ManaInBag", function()
			self:updateManaBag()
		end)

		PlayerDataController:Observe("Yen", function()
			self:updateYenShow()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "DoubleYen" }, function()
			self:updateDoubleYenOffer()
		end)

		PlayerDataController:Observe("Rebirths", function()
			self:updateRebirthFrame()
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
				doubleYenOfferCache = nil
				doubleYenOfferScannedGui = nil
				self:updateAll(true)
				self:setupSettingsIcon()
				self:setupSettingsFrame()
				self:setupShopFrame()
				self:setupRebirthFrame()
				self:setupOfflineEarningFrame()
				self:setupIndexFrame()
			end)
		end
	end)
end

return MainGuiController
