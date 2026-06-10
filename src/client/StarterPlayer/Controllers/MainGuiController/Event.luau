local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AdminRuntime = require(ReplicatedStorage.Shared.Features.Admin.AdminRuntime)
local EventConfig = require(ReplicatedStorage.Shared.Data.Events)
local EventUtil = require(ReplicatedStorage.Shared.Features.Events.EventUtil)
local PotionConfig = require(ReplicatedStorage.Shared.Data.PotionConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Knit = require(ReplicatedStorage.Packages.knit)

local EventFeature = {}

export type EventDisplayEntry = {
	Key: string,
	Icon: string?,
	Name: string,
	Description: string,
	EndsAt: number,
}

local updateConnection: RBXScriptConnection? = nil
local entryHoverConnections: { [Instance]: { RBXScriptConnection } } = {}
local hoverActive = false
local hoverEntryKey: string? = nil
local eventLoopRunning = false
local currentDisplayEntries: { EventDisplayEntry } = {}

local function disconnectEntryHover(icon: Instance)
	local connections = entryHoverConnections[icon]
	if not connections then
		return
	end

	for _, connection in connections do
		connection:Disconnect()
	end
	entryHoverConnections[icon] = nil
	icon:SetAttribute("EventHoverBound", nil)
end

local function getTextLabel(root: Instance?, name: string): TextLabel?
	local label = root and root:FindFirstChild(name, true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function setIconImage(root: GuiObject, image: string?)
	if image == nil or image == "" then
		return
	end

	if root:IsA("ImageButton") or root:IsA("ImageLabel") then
		root.Image = image
	end

	local childIcon = root:FindFirstChild("icon", true) or root:FindFirstChild("Icon", true)
	if childIcon and (childIcon:IsA("ImageLabel") or childIcon:IsA("ImageButton")) then
		childIcon.Image = image
	end
end

local function sanitizeEntryName(key: string): string
	return "Entry_" .. key:gsub("[^%w_]", "_")
end

local function findEntryIcon(eventFrame: GuiObject, entryKey: string, cloneName: string): GuiObject?
	local icon = eventFrame:FindFirstChild(cloneName)
	if icon and icon:IsA("GuiObject") then
		return icon
	end

	for _, child in eventFrame:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("EventEntryKey") == entryKey then
			return child
		end
	end

	return nil
end

local HOVER_ZINDEX = 50

local function setHoverPosition(hoverInfo: GuiObject)
	local mouseLocation = UserInputService:GetMouseLocation()
	local parent = hoverInfo.Parent
	local parentPosition = if parent and parent:IsA("GuiObject") then parent.AbsolutePosition else Vector2.zero

	hoverInfo.Position =
		UDim2.fromOffset(mouseLocation.X - parentPosition.X + 14, mouseLocation.Y - parentPosition.Y + 14)
end

local function getHoverTextLabels(hoverInfo: GuiObject): (TextLabel?, TextLabel?)
	local nameLabel = getTextLabel(hoverInfo, "Name")
	local descLabel = getTextLabel(hoverInfo, "Desc")
	if nameLabel and descLabel then
		return nameLabel, descLabel
	end

	local labels = {}
	for _, descendant in hoverInfo:GetDescendants() do
		if descendant:IsA("TextLabel") then
			table.insert(labels, descendant)
		end
	end

	table.sort(labels, function(a, b)
		return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
	end)

	return nameLabel or labels[1], descLabel or labels[2]
end

local function setHoverText(hoverInfo: GuiObject, name: string, description: string)
	local nameLabel, descLabel = getHoverTextLabels(hoverInfo)
	if nameLabel then
		nameLabel.Text = name
		nameLabel.Visible = true
	end
	if descLabel then
		descLabel.Text = description
		descLabel.Visible = true
	end
end

local function showHoverInfo(hoverInfo: GuiObject, mainGui: Instance?)
	if mainGui and hoverInfo.Parent ~= mainGui then
		hoverInfo.Parent = mainGui
	end

	hoverInfo.Visible = true
	hoverInfo.ZIndex = HOVER_ZINDEX
	hoverInfo.Active = false
	if hoverInfo:IsA("Frame") then
		hoverInfo.BackgroundTransparency = math.min(hoverInfo.BackgroundTransparency, 0.35)
	end

	for _, descendant in hoverInfo:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = HOVER_ZINDEX + 1
			descendant.Visible = true
		end
	end
end

local function hideHoverInfo(hoverInfo: GuiObject)
	hoverInfo.Visible = false
end

local function makeIconInteractive(icon: GuiObject)
	icon.Active = true
	for _, descendant in icon:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.Active = false
		end
	end
end


local function getPotionDisplayEntries(now: number): { EventDisplayEntry }
	local entries: { EventDisplayEntry } = {}
	local ok, activeBoosts = pcall(function()
		local PlayerDataController = Knit.GetController("PlayerDataController")
		return PlayerDataController:Get("ActivePotionBoosts")
	end)

	if not ok or type(activeBoosts) ~= "table" then
		return entries
	end

	for potionType, typeConfig in PotionConfig.Types do
		local boost = activeBoosts[potionType]
		if type(boost) ~= "table" then
			continue
		end

		local remaining = math.max(math.floor(tonumber(boost.RemainingSeconds) or 0), 0)
		if remaining <= 0 then
			continue
		end

		local multiplier = math.max(tonumber(boost.Multiplier) or typeConfig.Multiplier or 2, 1)
		table.insert(entries, {
			Key = "potion:" .. potionType,
			Icon = typeConfig.Icon,
			Name = typeConfig.Name,
			Description = `{multiplier}x {typeConfig.Name:gsub("^%d+x%s*", "")} for {AdminRuntime.formatDuration(remaining)}.`,
			EndsAt = now + remaining,
		})
	end

	return entries
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
	local durationSeconds = math.max(boostEndsAt - os.time(), 0)
	local multiplier = math.max(tonumber(tutorialConfig.RewardMultiplier) or 2, 1)
	return {
		EndsAt = boostEndsAt,
		Name = tutorialConfig.BoostName or "2x Yen Boost",
		Description = tutorialConfig.BoostDescription
			or `{multiplier}x Yen for {AdminRuntime.formatDuration(durationSeconds)}.`,
		Icon = tutorialConfig.BoostIcon,
	}
end

local function buildBoostDescription(boost: AdminRuntime.AdminBoostState): string
	local durationSeconds = math.max(math.floor(boost.EndsAt - boost.StartedAt), 0)
	return `{AdminRuntime.describeEffects(boost.Effects)} for {AdminRuntime.formatDuration(durationSeconds)}.`
end

local function buildAdminEventDescription(adminEvent: AdminRuntime.AdminEventState): string
	local durationSeconds = math.max(
		math.floor(adminEvent.DurationSeconds or (adminEvent.EndsAt - adminEvent.StartedAt)),
		1
	)
	if adminEvent.Description and adminEvent.Description ~= adminEvent.Name then
		return adminEvent.Description
	end

	return `{AdminRuntime.describeEffects(adminEvent.Effects)} for {AdminRuntime.formatDuration(durationSeconds)}.`
end

local function collectDisplayEntries(now: number): { EventDisplayEntry }
	local entries: { EventDisplayEntry } = {}
	local adminEvent = AdminRuntime.getActiveAdminEvent(now)

	if adminEvent then
		table.insert(entries, {
			Key = "admin_event:" .. adminEvent.Id,
			Icon = adminEvent.Icon,
			Name = adminEvent.Name,
			Description = buildAdminEventDescription(adminEvent),
			EndsAt = adminEvent.EndsAt,
		})
	else
		local activeEvent = EventUtil.getActiveEvent(now)
		if activeEvent and activeEvent.EndsAt > now then
			table.insert(entries, {
				Key = "world_event:" .. activeEvent.Id,
				Icon = activeEvent.Icon,
				Name = activeEvent.Name,
				Description = activeEvent.Description,
				EndsAt = activeEvent.EndsAt,
			})
		else
			local remaining = math.max(EventUtil.getNextEventStartsAt(now) - now, 0)
			table.insert(entries, {
				Key = "next_event",
				Icon = EventConfig.NextWindowIcon,
				Name = (EventConfig.NextWindowName or "Next event") .. " in " .. EventUtil.formatTime(remaining),
				Description = EventConfig.NextWindowDescription or "???",
				EndsAt = now + remaining,
			})
		end
	end

	for _, boost in AdminRuntime.getActiveBoosts(now) do
		table.insert(entries, {
			Key = "boost:" .. boost.Id,
			Icon = boost.Icon or EventConfig.NextWindowIcon,
			Name = boost.Name,
			Description = buildBoostDescription(boost),
			EndsAt = boost.EndsAt,
		})
	end

	local tutorialBoost = getTutorialBoost()
	if tutorialBoost then
		table.insert(entries, {
			Key = "tutorial_boost",
			Icon = tutorialBoost.Icon,
			Name = tutorialBoost.Name,
			Description = tutorialBoost.Description,
			EndsAt = tutorialBoost.EndsAt,
		})
	end

	for _, potionEntry in getPotionDisplayEntries(now) do
		table.insert(entries, potionEntry)
	end

	return entries
end

function EventFeature.Install(MainGuiController)
	function MainGuiController:getEventFrame(): GuiObject?
		local mainGui = self:getMainGui()
		local frame = mainGui and mainGui:FindFirstChild("EventFrame", true)
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getEventHoverInfo(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local hoverInfoFrame = mainGui:FindFirstChild("EventHoverInfo")
		if not hoverInfoFrame then
			hoverInfoFrame = mainGui:FindFirstChild("EventHoverInfo", true)
		end

		return if hoverInfoFrame and hoverInfoFrame:IsA("GuiObject") then hoverInfoFrame else nil
	end

	function MainGuiController:getEventIconTemplate(): GuiObject?
		local eventFrame = self:getEventFrame()
		if not eventFrame then
			return nil
		end

		local template = eventFrame:FindFirstChild("EventIcon")
		if template and template:IsA("GuiObject") and template:GetAttribute("EventEntryKey") == nil then
			template:SetAttribute("IsEventIconTemplate", true)
			template.Visible = false
			return template
		end

		for _, child in eventFrame:GetChildren() do
			if child:IsA("GuiObject") and child:GetAttribute("IsEventIconTemplate") == true then
				child.Visible = false
				return child
			end
		end

		return nil
	end

	function MainGuiController:updateEventHover(entries: { EventDisplayEntry }?)
		local hoverInfo = self:getEventHoverInfo()
		if not hoverInfo or not hoverActive or not hoverEntryKey then
			return
		end

		local resolvedEntries = entries or currentDisplayEntries
		for _, entry in resolvedEntries do
			if entry.Key == hoverEntryKey then
				setHoverText(hoverInfo, entry.Name, entry.Description)
				return
			end
		end
	end

	function MainGuiController:bindEventEntryHover(icon: GuiObject, entryKey: string)
		disconnectEntryHover(icon)
		makeIconInteractive(icon)

		local connections = {}

		local function onEnter()
			local mainGui = self:getMainGui()
			local hoverInfo = self:getEventHoverInfo()
			if not hoverInfo then
				return
			end

			hoverActive = true
			hoverEntryKey = entryKey
			showHoverInfo(hoverInfo, mainGui)
			setHoverPosition(hoverInfo)
			self:updateEventHover()
		end

		local function onLeave()
			local hoverInfo = self:getEventHoverInfo()
			hoverActive = false
			hoverEntryKey = nil
			if hoverInfo then
				hideHoverInfo(hoverInfo)
			end
		end

		table.insert(connections, icon.MouseEnter:Connect(onEnter))
		table.insert(connections, icon.MouseLeave:Connect(onLeave))

		entryHoverConnections[icon] = connections
		icon:SetAttribute("EventHoverBound", true)
	end

	function MainGuiController:ensureEventEntryHover(icon: GuiObject, entryKey: string)
		makeIconInteractive(icon)
		if entryHoverConnections[icon] and icon:GetAttribute("EventHoverBound") == true then
			return
		end

		self:bindEventEntryHover(icon, entryKey)
	end

	function MainGuiController:syncEventIcons(entries: { EventDisplayEntry })
		local eventFrame = self:getEventFrame()
		local templateIcon = self:getEventIconTemplate()
		if not eventFrame or not templateIcon then
			return
		end

		templateIcon.Visible = false
		eventFrame.Visible = #entries > 0
		currentDisplayEntries = entries

		local now = EventUtil.getNow()
		local nextKeys: { [string]: boolean } = {}
		for index, entry in entries do
			nextKeys[entry.Key] = true
			local cloneName = sanitizeEntryName(entry.Key)
			local icon = findEntryIcon(eventFrame, entry.Key, cloneName)
			if not icon or not icon:IsA("GuiObject") then
				icon = templateIcon:Clone()
				icon.Name = cloneName
				icon:SetAttribute("EventEntryKey", entry.Key)
				icon:SetAttribute("IsEventIconTemplate", nil)
				icon.Parent = eventFrame
			end

			if icon.Name ~= cloneName then
				icon.Name = cloneName
			end
			icon:SetAttribute("EventEntryKey", entry.Key)
			local isBoostEntry = string.sub(entry.Key, 1, 7) == "potion:"
				or string.sub(entry.Key, 1, 6) == "boost:"
				or entry.Key == "tutorial_boost"
			icon:SetAttribute("EntryKind", if isBoostEntry then "Boost" else "Event")
			icon:SetAttribute("IsBoost", isBoostEntry)
			icon.Visible = true
			icon.LayoutOrder = index
			setIconImage(icon, entry.Icon)
			self:ensureEventEntryHover(icon, entry.Key)

			local remaining = math.max(math.floor(entry.EndsAt - now), 0)
			local timerLabel = getTextLabel(icon, "Timer")
			if timerLabel then
				timerLabel.Text = EventUtil.formatTime(remaining)
			end
		end

		for _, child in eventFrame:GetChildren() do
			if child:IsA("GuiObject") and child:GetAttribute("IsEventIconTemplate") ~= true then
				local entryKey = child:GetAttribute("EventEntryKey")
				if type(entryKey) == "string" and not nextKeys[entryKey] then
					disconnectEntryHover(child)
					child:Destroy()
				end
			end
		end

		if hoverActive then
			self:updateEventHover(entries)
		end
	end

	function MainGuiController:updateEventDisplay()
		local eventFrame = self:getEventFrame()
		local hoverInfo = self:getEventHoverInfo()
		if not eventFrame then
			return
		end

		local now = EventUtil.getNow()
		local entries = collectDisplayEntries(now)
		self:syncEventIcons(entries)

		if hoverInfo then
			if hoverActive and hoverEntryKey ~= nil then
				showHoverInfo(hoverInfo, self:getMainGui())
				setHoverPosition(hoverInfo)
				self:updateEventHover()
			elseif not hoverActive then
				hideHoverInfo(hoverInfo)
			end
		end
	end

	function MainGuiController:setupEventFrame()
		local hoverInfo = self:getEventHoverInfo()
		if hoverInfo then
			hideHoverInfo(hoverInfo)
		end

		hoverActive = false
		hoverEntryKey = nil

		if updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
		end

		updateConnection = RunService.RenderStepped:Connect(function()
			if hoverActive then
				local currentHoverInfo = self:getEventHoverInfo()
				if currentHoverInfo then
					setHoverPosition(currentHoverInfo)
					self:updateEventHover()
				end
			end
		end)

		self:updateEventDisplay()
	end

	function MainGuiController:refreshEventFeature()
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
