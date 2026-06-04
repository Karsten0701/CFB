local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local EventConfig = require(ReplicatedStorage.Shared.Data.Events)
local EventUtil = require(ReplicatedStorage.Shared.Features.Events.EventUtil)

local EventFeature = {}

local updateConnection: RBXScriptConnection? = nil
local hoverConnections: { RBXScriptConnection } = {}
local hoverActive = false
local lastDisplayId: string? = nil
local eventLoopRunning = false

local function disconnectHoverConnections()
	for _, connection in hoverConnections do
		connection:Disconnect()
	end

	table.clear(hoverConnections)
end

local function getTextLabel(root: Instance?, name: string): TextLabel?
	local label = root and root:FindFirstChild(name, true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function setIconImage(icon: GuiObject, image: string?)
	if image == nil or image == "" then
		return
	end

	if icon:IsA("ImageButton") or icon:IsA("ImageLabel") then
		icon.Image = image
	end
end

local function setHoverPosition(hoverInfo: GuiObject)
	local mouseLocation = UserInputService:GetMouseLocation()
	local parent = hoverInfo.Parent
	local parentPosition = if parent and parent:IsA("GuiObject") then parent.AbsolutePosition else Vector2.zero
	local offset = Vector2.new(0, 0)

	hoverInfo.Position =
		UDim2.fromOffset(mouseLocation.X - parentPosition.X + offset.X, mouseLocation.Y - parentPosition.Y + offset.Y)
end

function EventFeature.Install(MainGuiController)
	function MainGuiController:getEventFrame(): GuiObject?
		local mainGui = self:getMainGui()
		local frame = mainGui and mainGui:FindFirstChild("EventFrame", true)
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getEventHoverInfo(): GuiObject?
		local mainGui = self:getMainGui()
		local hoverInfoFrame = mainGui and mainGui:FindFirstChild("EventHoverInfo", true)
		return if hoverInfoFrame and hoverInfoFrame:IsA("GuiObject")
			then hoverInfoFrame
			else warn("No hover info frame")
	end

	function MainGuiController:getEventIcon(): GuiObject?
		local eventFrame = self:getEventFrame()
		local icon = eventFrame and eventFrame:FindFirstChild("EventIcon", true)
		return if icon and icon:IsA("GuiObject") then icon else nil
	end

	function MainGuiController:updateEventDisplay()
		local eventFrame = self:getEventFrame()
		local icon = self:getEventIcon()
		local hoverInfo = self:getEventHoverInfo()
		if not eventFrame or not icon or not hoverInfo then
			warn("No event frame, icon, or hover info")
			return
		end

		local activeEvent = EventUtil.getActiveEvent()
		local now = os.time()
		local timerLabel = getTextLabel(icon, "Timer")

		eventFrame.Visible = true
		if hoverInfo then
			hoverInfo.Visible = hoverActive
		else
			print("No hover info")
		end

		if activeEvent then
			local remaining = math.max(activeEvent.EndsAt - now, 0)
			if timerLabel then
				timerLabel.Text = EventUtil.formatTime(remaining)
			end

			if activeEvent.Id ~= lastDisplayId then
				lastDisplayId = activeEvent.Id
				setIconImage(icon, activeEvent.Icon)

				local nameLabel = getTextLabel(hoverInfo, "Name")
				local descLabel = getTextLabel(hoverInfo, "Desc")
				if nameLabel then
					nameLabel.Text = activeEvent.Name
					print("Name: " .. nameLabel.Text)
				end
				if descLabel then
					descLabel.Text = activeEvent.Description
					print("Description: " .. descLabel.Text)
				end
			end
		else
			local remaining = math.max(EventUtil.getNextEventStartsAt(now) - now, 0)
			local nextEvent = EventUtil.getNextEvent(now)
			if timerLabel then
				timerLabel.Text = EventUtil.formatTime(remaining)
			end

			local nextDisplayId = if nextEvent then "next:" .. (nextEvent.Id or nextEvent.Name or "") else nil
			if lastDisplayId ~= nextDisplayId then
				lastDisplayId = nextDisplayId
				if nextEvent then
					setIconImage(icon, nextEvent.Icon)
				end
			end

			local nameLabel = getTextLabel(hoverInfo, "Name")
			local descLabel = getTextLabel(hoverInfo, "Desc")
			if nameLabel then
				if nextEvent then
					nameLabel.Text = "Next: " .. (nextEvent.Name or "Anime Event")
				else
					nameLabel.Text = EventConfig.EmptyWindowName or "Preparing next event"
				end
			end
			if descLabel then
				if nextEvent and nextEvent.Description then
					descLabel.Text = nextEvent.Description
				else
					descLabel.Text = "Next event starts soon."
				end
			end
		end
	end

	function MainGuiController:setupEventFrame()
		disconnectHoverConnections()

		local icon = self:getEventIcon()
		local hoverInfo = self:getEventHoverInfo()
		if hoverInfo then
			hoverInfo.Visible = false
		end

		if icon and hoverInfo then
			table.insert(
				hoverConnections,
				icon.MouseEnter:Connect(function()
					hoverActive = true
					hoverInfo.Visible = true
					setHoverPosition(hoverInfo)
				end)
			)

			table.insert(
				hoverConnections,
				icon.MouseLeave:Connect(function()
					hoverActive = false
					hoverInfo.Visible = false
				end)
			)
		end

		if updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
		end

		updateConnection = RunService.RenderStepped:Connect(function()
			if hoverActive then
				local currentHoverInfo = self:getEventHoverInfo()
				if currentHoverInfo then
					setHoverPosition(currentHoverInfo)
				end
			end
		end)

		self:updateEventDisplay()
	end

	function MainGuiController:setupEventFeature()
		self:setupEventFrame()
		if eventLoopRunning then
			return
		end

		eventLoopRunning = true
		task.spawn(function()
			while true do
				self:updateEventDisplay()
				task.wait(1)
			end
		end)
	end
end

return EventFeature
