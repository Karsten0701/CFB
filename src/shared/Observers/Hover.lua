-- HoverEffectsModule
-- ModuleScript in ReplicatedStorage.Modules

local HoverEffects = {}

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)

HoverEffects.TagName = "Hover"

HoverEffects.Settings = {
	HoverScale = 1.06,
	ClickScale = 0.88,

	HoverTweenInfo = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	LeaveTweenInfo = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	ClickTweenInfo = TweenInfo.new(0.045, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	ReleaseTweenInfo = TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}
local activeButtons = {}
local started = false
local mouseDown = false

local function scaleUDim2(size, multiplier)
	return UDim2.new(
		size.X.Scale * multiplier,
		size.X.Offset * multiplier,
		size.Y.Scale * multiplier,
		size.Y.Offset * multiplier
	)
end

local function playTween(button, data, tweenInfo, targetSize)
	if data.CurrentTarget == targetSize then
		return
	end

	data.CurrentTarget = targetSize

	if data.Tween then
		data.Tween:Cancel()
	end

	data.Tween = TweenService:Create(button, tweenInfo, {
		Size = targetSize,
	})

	data.Tween:Play()
end

local function refreshButton(button)
	local data = activeButtons[button]
	if not data then
		return
	end

	if data.Hovering and mouseDown then
		playTween(button, data, HoverEffects.Settings.ClickTweenInfo, data.ClickSize)
	elseif data.Hovering then
		playTween(button, data, HoverEffects.Settings.ReleaseTweenInfo, data.HoverSize)
	else
		playTween(button, data, HoverEffects.Settings.LeaveTweenInfo, data.OriginalSize)
	end
end

local function refreshAllHovering()
	for button, data in activeButtons do
		if data.Hovering then
			refreshButton(button)
		end
	end
end

function HoverEffects.SetupButton(button)
	if activeButtons[button] then
		return
	end
	if not button:IsA("GuiButton") then
		return
	end

	button.AnchorPoint = button.AnchorPoint

	local originalSize = button.Size

	local data = {
		OriginalSize = originalSize,
		HoverSize = scaleUDim2(originalSize, HoverEffects.Settings.HoverScale),
		ClickSize = scaleUDim2(originalSize, HoverEffects.Settings.ClickScale),

		Hovering = false,
		Tween = nil,
		CurrentTarget = nil,
		Connections = {},
	}

	activeButtons[button] = data

	data.Connections[#data.Connections + 1] = button.MouseEnter:Connect(function()
		data.Hovering = true
		SoundUtil.Hover()
		refreshButton(button)
	end)

	data.Connections[#data.Connections + 1] = button.MouseLeave:Connect(function()
		data.Hovering = false
		refreshButton(button)
	end)

	data.Connections[#data.Connections + 1] = button.MouseButton1Down:Connect(function()
		mouseDown = true
		SoundUtil.Click()
		refreshButton(button)
	end)

	data.Connections[#data.Connections + 1] = button.Activated:Connect(function()
		if data.Hovering then
			playTween(button, data, HoverEffects.Settings.ClickTweenInfo, data.ClickSize)

			task.delay(HoverEffects.Settings.ClickTweenInfo.Time, function()
				if activeButtons[button] then
					refreshButton(button)
				end
			end)
		end
	end)

	data.Connections[#data.Connections + 1] = button:GetPropertyChangedSignal("Size"):Connect(function()
		if data.Tween then
			return
		end

		data.OriginalSize = button.Size
		data.HoverSize = scaleUDim2(data.OriginalSize, HoverEffects.Settings.HoverScale)
		data.ClickSize = scaleUDim2(data.OriginalSize, HoverEffects.Settings.ClickScale)
	end)

	data.Connections[#data.Connections + 1] = button.Destroying:Connect(function()
		HoverEffects.RemoveButton(button)
	end)
end

function HoverEffects.RemoveButton(button)
	local data = activeButtons[button]
	if not data then
		return
	end

	if data.Tween then
		data.Tween:Cancel()
	end

	for _, connection in data.Connections do
		connection:Disconnect()
	end

	activeButtons[button] = nil
end

function HoverEffects.Start()
	if started then
		return
	end
	started = true

	for _, object in CollectionService:GetTagged(HoverEffects.TagName) do
		HoverEffects.SetupButton(object)
	end

	CollectionService:GetInstanceAddedSignal(HoverEffects.TagName):Connect(function(object)
		HoverEffects.SetupButton(object)
	end)

	CollectionService:GetInstanceRemovedSignal(HoverEffects.TagName):Connect(function(object)
		HoverEffects.RemoveButton(object)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		mouseDown = false
		refreshAllHovering()
	end)
end

return HoverEffects
