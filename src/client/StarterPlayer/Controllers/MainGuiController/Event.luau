local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local EventConfig = require(ReplicatedStorage.Shared.Data.Events)
local EventUtil = require(ReplicatedStorage.Shared.Features.Events.EventUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Knit = require(ReplicatedStorage.Packages.knit)

local EventFeature = {}

local updateConnection: RBXScriptConnection? = nil
local hoverConnections: { RBXScriptConnection } = {}
local hoverActive = false
local hoverMode: "event" | "tutorial"? = nil
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

local function setHoverText(hoverInfo: GuiObject, name: string, description: string)
	local nameLabel = getTextLabel(hoverInfo, "Name")
	local descLabel = getTextLabel(hoverInfo, "Desc")
	if nameLabel then
		nameLabel.Text = name
	end
	if descLabel then
		descLabel.Text = description
	end
end

local function getTutorialBoost(): { EndsAt: number, Name: string, Description: string, Icon: string? }?
	local ok, boostEndsAt = pcall(function()
		local PlayerDataController = Knit.GetController("PlayerDataController")
		return PlayerDataController:Get("TutorialBoostEndsAt")
	end)
	if not ok or type(boostEndsAt) ~= "number" or boostEndsAt <= os.time() then
		return nil
	end

	local tutorialConfig = TycoonConfig.Tutorial or {}
	return {
		EndsAt = boostEndsAt,
		Name = tutorialConfig.BoostName or "2x Yen Boost",
		Description = tutorialConfig.BoostDescription or "Tutorial reward",
		Icon = tutorialConfig.BoostIcon,
	}
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

	function MainGuiController:getTutorialBoostIcon(templateIcon: GuiObject?): GuiObject?
		local eventFrame = self:getEventFrame()
		local iconParent = templateIcon and templateIcon.Parent
		if not eventFrame or not templateIcon or not iconParent then
			return nil
		end

		local existing = eventFrame:FindFirstChild("TutorialBoostIcon", true)
		if existing and existing:IsA("GuiObject") then
			return existing
		end

		local clone = templateIcon:Clone()
		clone.Name = "TutorialBoostIcon"
		clone.LayoutOrder = templateIcon.LayoutOrder + 1
		clone.Position = templateIcon.Position + UDim2.fromOffset(templateIcon.AbsoluteSize.X + 8, 0)
		clone.Visible = false
		clone.Parent = iconParent
		return clone
	end

	function MainGuiController:updateTutorialBoostIcon(templateIcon: GuiObject, hoverInfo: GuiObject)
		local boostIcon = self:getTutorialBoostIcon(templateIcon)
		local tutorialBoost = getTutorialBoost()
		if not boostIcon then
			return
		end

		if not tutorialBoost then
			boostIcon.Visible = false
			if hoverMode == "tutorial" then
				hoverActive = false
				hoverMode = nil
				hoverInfo.Visible = false
			end
			return
		end

		boostIcon.Visible = true
		setIconImage(boostIcon, tutorialBoost.Icon)

		local timerLabel = getTextLabel(boostIcon, "Timer")
		if timerLabel then
			timerLabel.Text = EventUtil.formatTime(math.max(tutorialBoost.EndsAt - os.time(), 0))
		end

		if hoverMode == "tutorial" then
			setHoverText(hoverInfo, tutorialBoost.Name, tutorialBoost.Description)
		end
	end

	function MainGuiController:updateEventDisplay()
		local eventFrame = self:getEventFrame()
		local icon = self:getEventIcon()
		local hoverInfo = self:getEventHoverInfo()
		if not eventFrame or not icon or not hoverInfo then
			warn("No event frame, icon, or hover info")
			return
		end

		local now = EventUtil.getNow()
		local activeEvent = EventUtil.getActiveEvent(now)
		local timerLabel = getTextLabel(icon, "Timer")

		eventFrame.Visible = true
		self:updateTutorialBoostIcon(icon, hoverInfo)
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

				if hoverMode ~= "tutorial" then
					setHoverText(hoverInfo, activeEvent.Name, activeEvent.Description)
				end
			end
		else
			local remaining = math.max(EventUtil.getNextEventStartsAt(now) - now, 0)
			if timerLabel then
				timerLabel.Text = EventUtil.formatTime(remaining)
			end

			local nextDisplayId = "next"
			if lastDisplayId ~= nextDisplayId then
				lastDisplayId = nextDisplayId
				setIconImage(icon, EventConfig.NextWindowIcon)
			end

			if hoverMode ~= "tutorial" then
				setHoverText(
					hoverInfo,
					(EventConfig.NextWindowName or "Next event")
					.. " in "
						.. EventUtil.formatTime(remaining),
					EventConfig.NextWindowDescription or "???"
				)
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
					hoverMode = "event"
					hoverInfo.Visible = true
					setHoverPosition(hoverInfo)
					lastDisplayId = nil
					self:updateEventDisplay()
				end)
			)

			table.insert(
				hoverConnections,
				icon.MouseLeave:Connect(function()
					hoverActive = false
					hoverMode = nil
					hoverInfo.Visible = false
				end)
			)

			local boostIcon = self:getTutorialBoostIcon(icon)
			if boostIcon then
				table.insert(
					hoverConnections,
					boostIcon.MouseEnter:Connect(function()
						hoverActive = true
						hoverMode = "tutorial"
						hoverInfo.Visible = true
						setHoverPosition(hoverInfo)
						self:updateEventDisplay()
					end)
				)

				table.insert(
					hoverConnections,
					boostIcon.MouseLeave:Connect(function()
						hoverActive = false
						hoverMode = nil
						hoverInfo.Visible = false
					end)
				)
			end
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
