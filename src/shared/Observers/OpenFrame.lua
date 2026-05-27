-- UIFrameAnimatorModule
-- ModuleScript in ReplicatedStorage.Modules

local UIFrameAnimator = {}

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

UIFrameAnimator.TagName = "AnimatedFrame"

UIFrameAnimator.Settings = {
	OpenScale = 1,
	ClosedScale = 0.5,

	OpenTweenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	CloseTweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),

	AutoHideWhenClosed = true,
}

local activeFrames = {}
local currentFrame = nil
local started = false
local internalVisibleChange = {}

local function getUIScale(frame)
	local uiScale = frame:FindFirstChildOfClass("UIScale")

	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Scale = 1
		uiScale.Parent = frame
	end

	return uiScale
end

local function setVisible(frame, visible)
	internalVisibleChange[frame] = true
	frame.Visible = visible
	internalVisibleChange[frame] = nil
end

local function cancelTween(data)
	if data.Tween then
		data.Tween:Cancel()
		data.Tween = nil
	end
end

function UIFrameAnimator.SetupFrame(frame)
	if activeFrames[frame] then return end
	if not frame:IsA("GuiObject") then return end

	local uiScale = getUIScale(frame)

	local data = {
		UIScale = uiScale,
		IsOpen = frame.Visible,
		Tween = nil,
		Connections = {},
	}

	activeFrames[frame] = data

	if frame.Visible then
		uiScale.Scale = UIFrameAnimator.Settings.OpenScale
		currentFrame = frame
	else
		uiScale.Scale = UIFrameAnimator.Settings.ClosedScale
	end

	data.Connections[#data.Connections + 1] = frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if internalVisibleChange[frame] then return end

		UIFrameAnimator.Toggle(frame, frame.Visible)
	end)

	data.Connections[#data.Connections + 1] = frame.Destroying:Connect(function()
		UIFrameAnimator.RemoveFrame(frame)
	end)
end

local function openFrame(frame)
	local data = activeFrames[frame]
	if not data then return end

	cancelTween(data)

	if currentFrame and currentFrame ~= frame and activeFrames[currentFrame] then
		UIFrameAnimator.Toggle(currentFrame, false)
	end

	currentFrame = frame
	data.IsOpen = true

	setVisible(frame, true)

	data.UIScale.Scale = UIFrameAnimator.Settings.ClosedScale

	data.Tween = TweenService:Create(
		data.UIScale,
		UIFrameAnimator.Settings.OpenTweenInfo,
		{ Scale = UIFrameAnimator.Settings.OpenScale }
	)

	data.Tween:Play()
end

local function closeFrame(frame)
	local data = activeFrames[frame]
	if not data then return end

	cancelTween(data)

	data.IsOpen = false

	if currentFrame == frame then
		currentFrame = nil
	end

	data.Tween = TweenService:Create(
		data.UIScale,
		UIFrameAnimator.Settings.CloseTweenInfo,
		{ Scale = UIFrameAnimator.Settings.ClosedScale }
	)

	data.Tween:Play()

	data.Tween.Completed:Once(function()
		if not activeFrames[frame] then return end
		if data.IsOpen then return end

		if UIFrameAnimator.Settings.AutoHideWhenClosed then
			setVisible(frame, false)
		end
	end)
end

-- Enige functie die je gebruikt:
-- Toggle(frame) = open/dicht
-- Toggle(frame, true) = force open
-- Toggle(frame, false) = force close
function UIFrameAnimator.Toggle(frame, forceState)
	if not activeFrames[frame] then
		UIFrameAnimator.SetupFrame(frame)
	end

	local data = activeFrames[frame]
	if not data then return end

	local shouldOpen

	if forceState ~= nil then
		shouldOpen = forceState
	else
		shouldOpen = not data.IsOpen
	end

	if shouldOpen then
		openFrame(frame)
	else
		closeFrame(frame)
	end
end

function UIFrameAnimator.RemoveFrame(frame)
	local data = activeFrames[frame]
	if not data then return end

	cancelTween(data)

	for _, connection in data.Connections do
		connection:Disconnect()
	end

	if currentFrame == frame then
		currentFrame = nil
	end

	activeFrames[frame] = nil
	internalVisibleChange[frame] = nil
end

function UIFrameAnimator.Start()
	if started then return end
	started = true

	for _, object in CollectionService:GetTagged(UIFrameAnimator.TagName) do
		UIFrameAnimator.SetupFrame(object)
	end

	CollectionService:GetInstanceAddedSignal(UIFrameAnimator.TagName):Connect(function(object)
		UIFrameAnimator.SetupFrame(object)
	end)

	CollectionService:GetInstanceRemovedSignal(UIFrameAnimator.TagName):Connect(function(object)
		UIFrameAnimator.RemoveFrame(object)
	end)
end

return UIFrameAnimator