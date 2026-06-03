local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local Icon = require(ReplicatedStorage.Packages.topbarplus)
local Knit = require(ReplicatedStorage.Packages.knit)

local Settings = {}

local settingsIcon = nil
local boundSettingsFrame: GuiObject? = nil
local settingsConnections: { RBXScriptConnection } = {}
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

local SETTING_GAMEPASS_REQUIREMENTS = {
	AutoCollect = "AutoCollect",
	AutoDeposit = "AutoDeposit",
}

local SETTING_TOGGLE_COOLDOWNS = {
	ShowOtherTycoons = 3,
}

function Settings.Install(MainGuiController)

function MainGuiController:getSettingsEntitlements(): { [string]: boolean }
	return settingsEntitlements
end

function MainGuiController:setSettingsEntitlements(entitlements: { [string]: boolean })
	settingsEntitlements = entitlements or {}
	settingsEntitlementsLoaded = true
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
			self:updateUpgradesFrame()
			self:updateDoubleYenOffer()
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


function MainGuiController:setupSettingsFeature()
	self:setupSettingsIcon()
	self:setupSettingsFrame()
end

function MainGuiController:refreshSettingsFeature()
	self:refreshSettingsEntitlements()
	self:refreshGamePassSettings()
end

end

return Settings
