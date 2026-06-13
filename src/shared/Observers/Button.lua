local ButtonPress = {}

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)

ButtonPress.TagName = "Button"
ButtonPress.Settings = {
	PressOffset = 0.5,
	PressTweenInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	ReleaseTweenInfo = TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	RepeatCooldown = 1,
	PulseInterval = 1.12,
	StandingCheckInterval = 0.1,
}

local activeButtons: { [BasePart]: any } = {}
local started = false

local function getButtonHead(object: Instance): BasePart?
	if object:IsA("BasePart") then
		return object
	end

	if object:IsA("Model") then
		local head = object:FindFirstChild("Head", true)
		return if head and head:IsA("BasePart") then head else nil
	end

	return nil
end

local function isLocalCharacterPart(part: BasePart): boolean
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then
		return false
	end

	local player = Players:GetPlayerFromCharacter(character)
	return player == Players.LocalPlayer and part.Name == "HumanoidRootPart"
end

local function getLocalRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isRootStandingOn(root: BasePart?, head: BasePart): boolean
	if not root then
		return false
	end

	local rootPosition = root.Position
	local headPosition = head.Position
	local offsetX = rootPosition.X - headPosition.X
	local offsetZ = rootPosition.Z - headPosition.Z
	local radius = math.max(head.Size.X, head.Size.Y, head.Size.Z) * 0.5
	local allowedRadius = radius + 0.6
	local verticalOffset = rootPosition.Y - headPosition.Y

	return offsetX * offsetX + offsetZ * offsetZ <= allowedRadius * allowedRadius and verticalOffset >= 0 and verticalOffset <= 6
end

function ButtonPress.GetLocalRoot(): BasePart?
	return getLocalRoot()
end

function ButtonPress.IsRootStandingOn(root: BasePart?, head: BasePart): boolean
	return isRootStandingOn(root, head)
end

function ButtonPress.IsStandingOn(head: BasePart): boolean
	return isRootStandingOn(getLocalRoot(), head)
end

local function tweenHead(head: BasePart, data, targetPosition: Vector3, tweenInfo: TweenInfo)
	if data.Tween then
		data.Tween:Cancel()
		data.Tween = nil
	end

	data.Tween = TweenService:Create(head, tweenInfo, {
		Position = targetPosition,
	})
	data.Tween:Play()
end

local function playPulseLoop(head: BasePart, data)
	while activeButtons[head] == data and data.Held do
		tweenHead(
			head,
			data,
			data.OriginalPosition - Vector3.new(0, ButtonPress.Settings.PressOffset, 0),
			ButtonPress.Settings.PressTweenInfo
		)
		task.wait(0.12)

		if activeButtons[head] ~= data then
			return
		end

		tweenHead(head, data, data.OriginalPosition, ButtonPress.Settings.ReleaseTweenInfo)
		task.wait(math.max(ButtonPress.Settings.PulseInterval - 0.12, 0.05))
		SoundUtil.Click()
	end

	if activeButtons[head] == data then
		tweenHead(head, data, data.OriginalPosition, ButtonPress.Settings.ReleaseTweenInfo)
		data.LoopThread = nil
	end
end

function ButtonPress.SetPressed(head: BasePart, pressed: boolean)
	local data = activeButtons[head]
	if not data or data.Held == pressed then
		return
	end

	data.Held = pressed

	if pressed then
		SoundUtil.Click()
		if not data.LoopThread then
			data.LoopThread = task.spawn(playPulseLoop, head, data)
		end
	else
		tweenHead(head, data, data.OriginalPosition, ButtonPress.Settings.ReleaseTweenInfo)
		SoundUtil.Click()
	end
end

local function playPressPulse(head: BasePart, data)
	if data.Pulsing then
		return
	end

	data.Pulsing = true
	tweenHead(
		head,
		data,
		data.OriginalPosition - Vector3.new(0, ButtonPress.Settings.PressOffset, 0),
		ButtonPress.Settings.PressTweenInfo
	)
	task.wait(0.12)

	if activeButtons[head] and not ButtonPress.IsStandingOn(head) then
		tweenHead(head, data, data.OriginalPosition, ButtonPress.Settings.ReleaseTweenInfo)
		SoundUtil.Click()
	end

	data.Pulsing = false
end

function ButtonPress.TriggerPress(head: BasePart)
	local data = activeButtons[head]
	if not data then
		return
	end

	local now = os.clock()
	if now - (data.LastPress or 0) < ButtonPress.Settings.RepeatCooldown then
		return
	end

	data.LastPress = now
	SoundUtil.Click()
	task.spawn(playPressPulse, head, data)
end

function ButtonPress.SetupButton(buttonModel: Instance)
	local head = getButtonHead(buttonModel)
	if not head then
		return
	end

	if activeButtons[head] then
		return
	end

	head.Anchored = true

	local data = {
		OriginalPosition = head.Position,
		Held = false,
		Pulsing = false,
		LoopThread = nil,
		Tween = nil,
		LastPress = 0,
		Connections = {},
	}

	activeButtons[head] = data

	data.Connections[#data.Connections + 1] = head.Destroying:Connect(function()
		ButtonPress.RemoveButton(buttonModel)
	end)
end

function ButtonPress.RemoveButton(buttonModel: Instance)
	local head = getButtonHead(buttonModel)
	if not head then
		return
	end

	local data = activeButtons[head]
	if not data then
		return
	end

	if data.Tween then
		data.Tween:Cancel()
	end

	if data.LoopThread then
		task.cancel(data.LoopThread)
	end

	head.Position = data.OriginalPosition

	for _, connection in data.Connections do
		connection:Disconnect()
	end

	activeButtons[head] = nil
end

function ButtonPress.Start()
	if started then
		return
	end
	started = true

	for _, object in CollectionService:GetTagged(ButtonPress.TagName) do
		ButtonPress.SetupButton(object)
	end

	CollectionService:GetInstanceAddedSignal(ButtonPress.TagName):Connect(function(object)
		ButtonPress.SetupButton(object)
	end)

	CollectionService:GetInstanceRemovedSignal(ButtonPress.TagName):Connect(function(object)
		ButtonPress.RemoveButton(object)
	end)

	local accumulatedTime = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		accumulatedTime += deltaTime
		if accumulatedTime < ButtonPress.Settings.StandingCheckInterval then
			return
		end

		accumulatedTime = 0
		local root = getLocalRoot()
		for head in activeButtons do
			ButtonPress.SetPressed(head, isRootStandingOn(root, head))
		end
	end)
end

return ButtonPress
