local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local GuildConfig = require(ReplicatedStorage.Shared.Data.GuildConfig)
local GuildUtil = require(ReplicatedStorage.Shared.Features.Guilds.GuildUtil)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local Guilds = {}

local guildConnections: { RBXScriptConnection } = {}
local guildUpdatedConnection: RBXScriptConnection? = nil
local guildInvitesUpdatedConnection: RBXScriptConnection? = nil
local guildRequestOpen = false
local activeTab = "Top"
local listMode = "Top"
local selectedGuildId: string? = nil
local loadedGuilds: { { [string]: any } } = {}
local browsePage = 1
local browseHasMore = false
local browseSearchQuery = ""
local browseSearchDebounceThread: thread? = nil
local lastRenderedListMode: string? = nil
local createIsPublic = true
local myGuildShowingSettings = false
local myGuildViewGuildId: string? = nil
local myGuildIsPublic = true
local myGuildListConnections: { RBXScriptConnection } = {}
local memberListFrame: Frame? = nil
local listConnections: { RBXScriptConnection } = {}
local inviteListConnections: { RBXScriptConnection } = {}
local loadedInvites: { { Summary: { [string]: any }, InvitedAt: number } } = {}
local pendingConfirmationAction: (() -> ())? = nil
local pendingJoinConfirmationAction: (() -> ())? = nil
local pendingLeaveConfirmationAction: (() -> ())? = nil

local GUILDS_BUTTON_NAME = "GuildsButton"
local LEAVE_CONFIRMATION_MESSAGE = "Are you sure you want to LEAVE your guild?"
local DISBAND_CONFIRMATION_MESSAGE = "Disband your guild? All members will be removed."
local SWAP_GUILD_CONFIRMATION_MESSAGE = "Leave your current guild to join a new one."
local SWAP_GUILD_JOIN_CONFIRMATION_MESSAGE = "Leave your current guild to join this one?"
local JOIN_CONFIRMATION_MESSAGE = "Are you sure you want to JOIN this guild?"
local PRIVACY_SELECTED_STROKE = 3
local PRIVACY_UNSELECTED_STROKE = 0
local TAB_ACTIVE_SCALE = 1.2
local TAB_INACTIVE_SCALE = 1.0
local BROWSE_SEARCH_MIN_LENGTH = 2
local BROWSE_SEARCH_DEBOUNCE_SECONDS = 0.35

local TAB_BUTTON_SPECS = {
	{ tab = "Top", names = { "TopGuilds" } },
	{ tab = "Browse", names = { "BrowseGuilds" } },
	{ tab = "Create", names = { "CreateGuild" } },
	{ tab = "Invites", names = { "Invites", "GuildInvites" } },
	{ tab = "MyGuild", names = { "MyGuild" } },
}

local function clearInviteListConnections()
	for _, connection in inviteListConnections do
		connection:Disconnect()
	end
	table.clear(inviteListConnections)
end

local function clearListConnections()
	for _, connection in listConnections do
		connection:Disconnect()
	end
	table.clear(listConnections)
end

local function clearConnections()
	for _, connection in guildConnections do
		connection:Disconnect()
	end
	table.clear(guildConnections)

	if guildUpdatedConnection then
		guildUpdatedConnection:Disconnect()
		guildUpdatedConnection = nil
	end

	if guildInvitesUpdatedConnection then
		guildInvitesUpdatedConnection:Disconnect()
		guildInvitesUpdatedConnection = nil
	end
end

local function connectInviteGui(guiObject: GuiObject, callback: () -> ())
	if guiObject:IsA("TextButton") or guiObject:IsA("ImageButton") then
		table.insert(inviteListConnections, guiObject.Activated:Connect(callback))
	else
		table.insert(
			inviteListConnections,
			guiObject.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					callback()
				end
			end)
		)
	end
end

local function connectGui(guiObject: GuiObject, callback: () -> ())
	local clickable = guiObject
	if not (clickable:IsA("TextButton") or clickable:IsA("ImageButton")) then
		table.insert(
			guildConnections,
			clickable.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					callback()
				end
			end)
		)
		return
	end

	table.insert(guildConnections, clickable.Activated:Connect(callback))
end

local function findTextLabel(parent: Instance?, names: { string }): TextLabel?
	if not parent then
		return nil
	end

	for _, name in names do
		local label = parent:FindFirstChild(name, true)
		if label and label:IsA("TextLabel") then
			return label
		end
	end

	return nil
end

local function findImageLabel(parent: Instance?, names: { string }): ImageLabel?
	if not parent then
		return nil
	end

	for _, name in names do
		local image = parent:FindFirstChild(name, true)
		if image and image:IsA("ImageLabel") then
			return image
		end
	end

	return nil
end

local function stringContains(haystack: string, needle: string): boolean
	return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

local function isLogoTextBox(textBox: TextBox): boolean
	local lowerName = string.lower(textBox.Name)
	if stringContains(lowerName, "logo") or stringContains(lowerName, "icon") then
		return true
	end

	local placeholder = string.lower(textBox.PlaceholderText or "")
	if stringContains(placeholder, "rbxassetid") or placeholder == "rbxassetid://" then
		return true
	end

	local parent = textBox.Parent
	while parent and parent:IsA("GuiObject") do
		local lowerParent = string.lower(parent.Name)
		if stringContains(lowerParent, "logo") or stringContains(lowerParent, "icon") then
			return true
		end
		parent = parent.Parent
	end

	return false
end

local function findTextBoxNearLabel(createFrame: GuiObject, labelText: string): TextBox?
	for _, desc in createFrame:GetDescendants() do
		if desc:IsA("TextLabel") and stringContains(desc.Text, labelText) then
			local parent = desc.Parent
			if parent then
				for _, child in parent:GetChildren() do
					if child:IsA("TextBox") then
						return child
					end
				end

				local nested = parent:FindFirstChildWhichIsA("TextBox", true)
				if nested then
					return nested
				end
			end
		end
	end

	return nil
end

local function findCreateGuildNameTextBox(createFrame: GuiObject): TextBox?
	local preferredNames = { "GuildNameInput", "GuildName", "NameInput", "Name", "Guild Name" }
	for _, name in preferredNames do
		local found = createFrame:FindFirstChild(name, true)
		if found and found:IsA("TextBox") then
			return found
		end
		if found then
			local nested = found:FindFirstChildWhichIsA("TextBox")
			if nested then
				return nested
			end
		end
	end

	local nearLabel = findTextBoxNearLabel(createFrame, "Guild Name")
	if nearLabel then
		return nearLabel
	end

	for _, desc in createFrame:GetDescendants() do
		if desc:IsA("TextBox") and not isLogoTextBox(desc) then
			return desc
		end
	end

	return nil
end

local function findCreateGuildLogoTextBox(createFrame: GuiObject): TextBox?
	local preferredNames = { "GuildLogoInput", "GuildLogo", "LogoInput", "Logo", "Guild Logo" }
	for _, name in preferredNames do
		local found = createFrame:FindFirstChild(name, true)
		if found and found:IsA("TextBox") then
			return found
		end
		if found then
			local nested = found:FindFirstChildWhichIsA("TextBox")
			if nested then
				return nested
			end
		end
	end

	local nearLabel = findTextBoxNearLabel(createFrame, "Guild Logo")
	if nearLabel then
		return nearLabel
	end

	for _, desc in createFrame:GetDescendants() do
		if desc:IsA("TextBox") and isLogoTextBox(desc) then
			return desc
		end
	end

	local textBoxes = {}
	for _, desc in createFrame:GetDescendants() do
		if desc:IsA("TextBox") then
			table.insert(textBoxes, desc)
		end
	end

	if #textBoxes >= 2 then
		return textBoxes[2]
	end

	return nil
end

local function setTextOnDescendants(parent: Instance?, names: { string }, text: string)
	for _, name in names do
		local found = parent and parent:FindFirstChild(name, true)
		if not found then
			continue
		end

		if found:IsA("TextLabel") or found:IsA("TextButton") then
			found.Text = text
		else
			local label = found:FindFirstChildWhichIsA("TextLabel", true)
				or found:FindFirstChildWhichIsA("TextButton", true)
			if label then
				label.Text = text
			end
		end
	end
end

local CONFIRMATION_BUTTON_NAMES = {
	YesButton = true,
	NoButton = true,
}

local function setConfirmationMessage(frame: Instance?, message: string)
	if not frame then
		return
	end

	local function isUnderConfirmationButton(inst: Instance): boolean
		local parent = inst.Parent
		while parent and parent ~= frame do
			if CONFIRMATION_BUTTON_NAMES[parent.Name] then
				return true
			end
			parent = parent.Parent
		end
		return false
	end

	for _, name in { "maintext", "Message", "Title" } do
		for _, desc in frame:GetDescendants() do
			if desc.Name == name and desc:IsA("TextLabel") and not isUnderConfirmationButton(desc) then
				desc.Text = message
				break
			end
		end
	end
end

local function setImageOnDescendants(parent: Instance?, names: { string }, image: string)
	local imageLabel = findImageLabel(parent, names)
	if imageLabel then
		imageLabel.Image = image
	end
end

local function getMemberCountText(summary: { [string]: any }): string
	local memberCount = math.max(math.floor(tonumber(summary.MemberCount) or 0), 0)
	local maxMembers = math.max(math.floor(tonumber(summary.MaxMembers) or GuildConfig.MaxMembers), 1)
	return `{memberCount}/{maxMembers}`
end

local function clearMyGuildListConnections()
	for _, connection in myGuildListConnections do
		connection:Disconnect()
	end
	table.clear(myGuildListConnections)
end

local function setPlayerThumbnail(imageLabel: ImageLabel, userId: number)
	if userId <= 0 then
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)

		if ok and imageLabel.Parent then
			imageLabel.Image = content
		end
	end)
end

local function formatGuildRole(role: string): string
	if role == GuildUtil.RoleOwner then
		return "Leader"
	end
	return role
end

local function getGuildScoreText(summary: { [string]: any }): string
	local score = math.max(math.floor(tonumber(summary.GuildScore) or 0), 0)
	return FormatUtil.formatNumber(score)
end

local function isMyGuildReadOnlyView(): boolean
	return myGuildViewGuildId ~= nil
end

local function getRankText(rank: number): string
	if rank > 0 then
		return `Rank #{rank}`
	end
	return "Rank --"
end

function Guilds.Install(MainGuiController)
	function MainGuiController:clearGuildConnections()
		clearConnections()
	end

	function MainGuiController:getGuildsFrame(): GuiObject?
		local mainGui = self:getMainGui()
		local frame = mainGui and mainGui:FindFirstChild("GuildsFrame")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getCreateGuildFrame(): GuiObject?
		local guildsFrame = self:getGuildsFrame()
		local frame = guildsFrame and guildsFrame:FindFirstChild("CreateGuildFrame")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getTopGuildsFrame(): GuiObject?
		local guildsFrame = self:getGuildsFrame()
		local frame = guildsFrame and guildsFrame:FindFirstChild("TopGuildsFrame")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getBrowseGuildsFrame(): GuiObject?
		local guildsFrame = self:getGuildsFrame()
		local frame = guildsFrame and guildsFrame:FindFirstChild("BrowseGuildsFrame")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getBrowseSearchInput(): TextBox?
		local browseFrame = self:getBrowseGuildsFrame()
		local searchInput = browseFrame and browseFrame:FindFirstChild("SearchInput", true)
		return if searchInput and searchInput:IsA("TextBox") then searchInput else nil
	end

	function MainGuiController:getBrowseRefreshButton(): GuiObject?
		local browseFrame = self:getBrowseGuildsFrame()
		local refreshButton = browseFrame and browseFrame:FindFirstChild("RefreshButton", true)
		return if refreshButton and refreshButton:IsA("GuiObject") then refreshButton else nil
	end

	function MainGuiController:getGuildInvitesFrame(): GuiObject?
		local guildsFrame = self:getGuildsFrame()
		local frame = guildsFrame and guildsFrame:FindFirstChild("GuildInvites")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getGuildConfirmationFrame(): GuiObject?
		local guildsFrame = self:getGuildsFrame()
		local frame = guildsFrame and guildsFrame:FindFirstChild("ConfirmationFrame")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getGuildLeaveConfirmationFrame(): GuiObject?
		local guildsFrame = self:getGuildsFrame()
		local leaveFrame = guildsFrame and guildsFrame:FindFirstChild("ConfirmationFrameLeave")
		if leaveFrame and leaveFrame:IsA("GuiObject") then
			return leaveFrame
		end
		return self:getGuildConfirmationFrame()
	end

	function MainGuiController:getGuildJoinConfirmationFrame(): GuiObject?
		local guildsFrame = self:getGuildsFrame()
		local frame = guildsFrame and guildsFrame:FindFirstChild("ConfirmationFrameJoin")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getGuildInviteScrollingFrame(): ScrollingFrame?
		local invitesFrame = self:getGuildInvitesFrame()
		local scrollingFrame = invitesFrame and invitesFrame:FindFirstChild("ScrollingFrame", true)
		return if scrollingFrame and scrollingFrame:IsA("ScrollingFrame") then scrollingFrame else nil
	end

	function MainGuiController:getGuildInviteTemplate(): GuiObject?
		local scrollingFrame = self:getGuildInviteScrollingFrame()
		local template = scrollingFrame and scrollingFrame:FindFirstChild("TemplateHolder", true)
		if not template then
			template = scrollingFrame and scrollingFrame:FindFirstChild("GuildTemplate", true)
		end
		return if template and template:IsA("GuiObject") then template else nil
	end

	function MainGuiController:getGuildScrollingFrame(): ScrollingFrame?
		if listMode == "Browse" then
			local browseFrame = self:getBrowseGuildsFrame()
			local scrollContainer = browseFrame and browseFrame:FindFirstChild("BrowseGuildsScroll", true)
			local scrollingFrame = scrollContainer and scrollContainer:FindFirstChild("ScrollingFrame", true)
			if scrollingFrame and scrollingFrame:IsA("ScrollingFrame") then
				return scrollingFrame
			end
		end

		local topGuildsFrame = self:getTopGuildsFrame()
		local scrollContainer = topGuildsFrame and topGuildsFrame:FindFirstChild("TopGuildsScroll", true)
		local scrollingFrame = scrollContainer and scrollContainer:FindFirstChild("ScrollingFrame", true)
		return if scrollingFrame and scrollingFrame:IsA("ScrollingFrame") then scrollingFrame else nil
	end

	function MainGuiController:getGuildTemplate(): GuiObject?
		local scrollingFrame = self:getGuildScrollingFrame()
		local template = scrollingFrame and scrollingFrame:FindFirstChild("GuildTemplate", true)
		return if template and template:IsA("GuiObject") then template else nil
	end

	function MainGuiController:getPreviewGuildFrame(): GuiObject?
		if listMode == "Browse" then
			local browseFrame = self:getBrowseGuildsFrame()
			local preview = browseFrame and browseFrame:FindFirstChild("PreviewGuild", true)
			if preview and preview:IsA("GuiObject") then
				return preview
			end
		end

		local topGuildsFrame = self:getTopGuildsFrame()
		local preview = topGuildsFrame and topGuildsFrame:FindFirstChild("PreviewGuild", true)
		return if preview and preview:IsA("GuiObject") then preview else nil
	end

	function MainGuiController:getMyGuildFrame(): GuiObject?
		local guildsFrame = self:getGuildsFrame()
		local frame = guildsFrame and guildsFrame:FindFirstChild("MyGuildFrame")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getMyGuildPreviewFrame(): GuiObject?
		local myGuildFrame = self:getMyGuildFrame()
		local preview = myGuildFrame
			and (myGuildFrame:FindFirstChild("previewGuild", true) or myGuildFrame:FindFirstChild("PreviewGuild", true))
		return if preview and preview:IsA("GuiObject") then preview else nil
	end

	function MainGuiController:getMyGuildSettingsFrame(): GuiObject?
		local myGuildFrame = self:getMyGuildFrame()
		local settings = myGuildFrame and myGuildFrame:FindFirstChild("GuildSettings", true)
		return if settings and settings:IsA("GuiObject") then settings else nil
	end

	function MainGuiController:getMyGuildMemberScrollFrame(): GuiObject?
		local myGuildFrame = self:getMyGuildFrame()
		local scroll = myGuildFrame and myGuildFrame:FindFirstChild("MemberScroll")
		return if scroll and scroll:IsA("GuiObject") then scroll else nil
	end

	function MainGuiController:getMyGuildMemberScrollingFrame(): ScrollingFrame?
		local memberScrollFrame = self:getMyGuildMemberScrollFrame()
		local scroll = memberScrollFrame and memberScrollFrame:FindFirstChildWhichIsA("ScrollingFrame")
		return if scroll and scroll:IsA("ScrollingFrame") then scroll else nil
	end

	function MainGuiController:getMyGuildMemberTemplate(): GuiObject?
		local scrollingFrame = self:getMyGuildMemberScrollingFrame()
		local template = scrollingFrame and scrollingFrame:FindFirstChild("MemberTemplate", true)
		return if template and template:IsA("GuiObject") then template else nil
	end

	function MainGuiController:getMyGuildInviteInput(): TextBox?
		local settings = self:getMyGuildSettingsFrame()
		local input = settings and settings:FindFirstChild("InviteInput", true)
		return if input and input:IsA("TextBox") then input else nil
	end

	function MainGuiController:isInGuild(): boolean
		return self:getPlayerGuildData().GuildId ~= ""
	end

	function MainGuiController:isGuildOwner(): boolean
		local guildData = self:getPlayerGuildData()
		return guildData.GuildId ~= "" and guildData.Role == GuildUtil.RoleOwner
	end

	function MainGuiController:getPlayerGuildData(): { GuildId: string, Role: string, OwnedGuildId: string }
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local guild = PlayerDataController:Get("Guild")
		if type(guild) ~= "table" then
			return { GuildId = "", Role = "", OwnedGuildId = "" }
		end

		return {
			GuildId = if type(guild.GuildId) == "string" then guild.GuildId else "",
			Role = if type(guild.Role) == "string" then guild.Role else "",
			OwnedGuildId = if type(guild.OwnedGuildId) == "string" then guild.OwnedGuildId else "",
		}
	end

	function MainGuiController:isViewingOwnGuildInMyGuildTab(): boolean
		if not self:isInGuild() then
			return false
		end
		if myGuildViewGuildId == nil then
			return true
		end
		return self:getPlayerGuildData().GuildId == myGuildViewGuildId
	end

	function MainGuiController:viewGuildInMyGuildTab(guildId: string)
		if guildId == "" then
			return
		end

		myGuildViewGuildId = guildId
		myGuildShowingSettings = false
		self:setGuildTab("MyGuild")
	end

	function MainGuiController:openMyGuildTab()
		myGuildViewGuildId = nil
		myGuildShowingSettings = false
		self:setGuildTab("MyGuild")
	end

	function MainGuiController:canCreateGuild(): boolean
		local guildData = self:getPlayerGuildData()
		return guildData.GuildId == "" and guildData.OwnedGuildId == ""
	end

	function MainGuiController:setGuildTab(tabName: string)
		activeTab = tabName

		local createFrame = self:getCreateGuildFrame()
		local topFrame = self:getTopGuildsFrame()
		local browseFrame = self:getBrowseGuildsFrame()
		local invitesFrame = self:getGuildInvitesFrame()
		local myGuildFrame = self:getMyGuildFrame()
		if createFrame then
			createFrame.Visible = tabName == "Create"
		end
		if topFrame then
			topFrame.Visible = tabName == "Top"
		end
		if browseFrame then
			browseFrame.Visible = tabName == "Browse"
		end
		if invitesFrame then
			invitesFrame.Visible = tabName == "Invites"
		end
		if myGuildFrame then
			myGuildFrame.Visible = tabName == "MyGuild"
		end

		self:updateGuildTabScales(tabName)
		self:hideGuildConfirmation()
		self:hideGuildJoinConfirmation()

		if tabName == "Top" then
			listMode = "Top"
			self:refreshGuildList()
		elseif tabName == "Browse" then
			listMode = "Browse"
			browsePage = 1
			self:refreshBrowseRandomGuilds()
		elseif tabName == "Invites" then
			self:refreshGuildInvites()
		elseif tabName == "MyGuild" then
			myGuildShowingSettings = false
			self:updateMyGuildViewMode()
			self:refreshMyGuildDisplay()
		end

		self:updateGuildHeaderPower()
	end

	function MainGuiController:updateGuildTabScales(activeTabName: string)
		local guildsFrame = self:getGuildsFrame()
		local sideButtons = guildsFrame and guildsFrame:FindFirstChild("SideButtons", true)
		if not sideButtons then
			return
		end

		for _, spec in TAB_BUTTON_SPECS do
			for _, buttonName in spec.names do
				local button = sideButtons:FindFirstChild(buttonName, true)
				if button and button:IsA("GuiObject") then
					local uiScale = button:FindFirstChildOfClass("UIScale")
					if not uiScale then
						uiScale = Instance.new("UIScale")
						uiScale.Parent = button
					end
					uiScale.Scale = if activeTabName == spec.tab then TAB_ACTIVE_SCALE else TAB_INACTIVE_SCALE
				end
			end
		end
	end

	function MainGuiController:updateGuildHeaderPower()
		local guildsFrame = self:getGuildsFrame()
		if not guildsFrame then
			return
		end

		local function applyPowerText(powerText: string)
			local topFrame = guildsFrame:FindFirstChild("TopFrame", true)
			if topFrame then
				setTextOnDescendants(topFrame, { "Power", "GuildPower", "PointsCount" }, powerText)
				local pointsCountFrame = topFrame:FindFirstChild("PointsCount", true)
				if pointsCountFrame then
					setTextOnDescendants(pointsCountFrame, { "Amount" }, powerText)
				end
			end
		end

		if not self:isInGuild() then
			applyPowerText("0")
			return
		end

		local GuildService = Knit.GetService("GuildService")
		GuildService:GetMyGuild()
			:andThen(function(summary)
				if summary then
					applyPowerText(getGuildScoreText(summary))
				else
					applyPowerText("0")
				end
			end)
			:catch(function()
				applyPowerText("0")
			end)
	end

	function MainGuiController:hideGuildJoinConfirmation()
		pendingJoinConfirmationAction = nil
		local confirmationFrame = self:getGuildJoinConfirmationFrame()
		if confirmationFrame then
			confirmationFrame.Visible = false
		end
	end

	function MainGuiController:showGuildJoinConfirmation(onConfirm: () -> (), message: string?)
		self:hideGuildConfirmation()
		self:hideGuildLeaveConfirmation()

		local confirmationFrame = self:getGuildJoinConfirmationFrame()
		if not confirmationFrame then
			onConfirm()
			return
		end

		pendingJoinConfirmationAction = onConfirm
		setConfirmationMessage(confirmationFrame, message or JOIN_CONFIRMATION_MESSAGE)
		confirmationFrame.Visible = true
	end

	function MainGuiController:promptGuildInviteJoin(guildId: string, message: string?)
		self:showGuildJoinConfirmation(function()
			self:hideGuildJoinConfirmation()
			self:acceptGuildInvite(guildId)
		end, message)
	end

	function MainGuiController:hideGuildLeaveConfirmation()
		pendingLeaveConfirmationAction = nil
		local confirmationFrame = self:getGuildLeaveConfirmationFrame()
		if confirmationFrame then
			confirmationFrame.Visible = false
		end
		if self:getGuildLeaveConfirmationFrame() == self:getGuildConfirmationFrame() then
			pendingConfirmationAction = nil
		end
	end

	function MainGuiController:showGuildLeaveConfirmation(onConfirm: () -> (), message: string?)
		self:hideGuildConfirmation()
		self:hideGuildJoinConfirmation()

		local confirmationFrame = self:getGuildLeaveConfirmationFrame()
		if not confirmationFrame then
			onConfirm()
			return
		end

		if confirmationFrame == self:getGuildConfirmationFrame() then
			pendingLeaveConfirmationAction = nil
			pendingConfirmationAction = onConfirm
		else
			pendingConfirmationAction = nil
			pendingLeaveConfirmationAction = onConfirm
		end

		setConfirmationMessage(confirmationFrame, message or LEAVE_CONFIRMATION_MESSAGE)
		confirmationFrame.Visible = true
	end

	function MainGuiController:promptLeaveGuild(onSuccess: (() -> ())?, message: string?)
		self:showGuildLeaveConfirmation(function()
			self:hideGuildLeaveConfirmation()
			self:executeLeaveGuild(function()
				myGuildViewGuildId = nil
				myGuildShowingSettings = false
				if onSuccess then
					onSuccess()
				end
			end)
		end, message)
	end

	function MainGuiController:hideGuildConfirmation()
		pendingConfirmationAction = nil
		local confirmationFrame = self:getGuildConfirmationFrame()
		if confirmationFrame then
			confirmationFrame.Visible = false
		end
	end

	function MainGuiController:showGuildConfirmation(message: string, onConfirm: () -> ())
		self:hideGuildJoinConfirmation()
		self:hideGuildLeaveConfirmation()

		local confirmationFrame = self:getGuildConfirmationFrame()
		if not confirmationFrame then
			onConfirm()
			return
		end

		pendingConfirmationAction = onConfirm
		setConfirmationMessage(confirmationFrame, message)
		confirmationFrame.Visible = true
	end

	function MainGuiController:executeLeaveGuild(onSuccess: (() -> ())?)
		if guildRequestOpen then
			return
		end

		local guildData = self:getPlayerGuildData()
		if guildData.GuildId == "" then
			if onSuccess then
				onSuccess()
			end
			return
		end

		guildRequestOpen = true
		local GuildService = Knit.GetService("GuildService")
		GuildService:LeaveGuild()
			:andThen(function(success, err)
				guildRequestOpen = false
				if success then
					SoundUtil.TutorialProgress()
					self:updateCreateGuildAccess()
					self:updateGuildHeaderPower()
					if activeTab == "Top" or activeTab == "Browse" then
						self:refreshGuildList()
					end
					self:refreshGuildInvites()
					if onSuccess then
						onSuccess()
					end
				elseif err then
					warn("[MainGuiController] Leave guild failed:", err)
				end
			end)
			:catch(function(err)
				guildRequestOpen = false
				warn("[MainGuiController] Leave guild failed:", err)
			end)
	end

	function MainGuiController:acceptGuildInvite(guildId: string)
		if guildRequestOpen or guildId == "" then
			return
		end

		guildRequestOpen = true
		local GuildService = Knit.GetService("GuildService")
		GuildService:AcceptGuildInvite(guildId)
			:andThen(function(success, err)
				guildRequestOpen = false
				if success then
					SoundUtil.TutorialProgress()
					self:refreshGuildInvites()
					self:updateCreateGuildAccess()
					self:updateGuildHeaderPower()
					self:openMyGuildTab()
				elseif err then
					warn("[MainGuiController] Accept invite failed:", err)
				end
			end)
			:catch(function(err)
				guildRequestOpen = false
				warn("[MainGuiController] Accept invite failed:", err)
			end)
	end

	function MainGuiController:handleInviteAccept(summary: { [string]: any })
		if guildRequestOpen or not summary then
			return
		end

		local guildData = self:getPlayerGuildData()
		if guildData.GuildId == summary.Id then
			return
		end

		if guildData.GuildId ~= "" then
			self:showGuildJoinConfirmation(function()
				self:hideGuildJoinConfirmation()
				self:acceptGuildInvite(summary.Id)
			end, SWAP_GUILD_JOIN_CONFIRMATION_MESSAGE)
			return
		end

		self:promptGuildInviteJoin(summary.Id)
	end

	function MainGuiController:handleInviteDecline(guildId: string)
		if guildRequestOpen or guildId == "" then
			return
		end

		guildRequestOpen = true
		local GuildService = Knit.GetService("GuildService")
		GuildService:DeclineGuildInvite(guildId)
			:andThen(function(success, err)
				guildRequestOpen = false
				if success then
					self:refreshGuildInvites()
				elseif err then
					warn("[MainGuiController] Decline invite failed:", err)
				end
			end)
			:catch(function(err)
				guildRequestOpen = false
				warn("[MainGuiController] Decline invite failed:", err)
			end)
	end

	function MainGuiController:clearGuildInviteItems()
		local scrollingFrame = self:getGuildInviteScrollingFrame()
		local template = self:getGuildInviteTemplate()
		if not scrollingFrame or not template then
			return
		end

		for _, child in scrollingFrame:GetChildren() do
			if child:IsA("GuiObject") and child ~= template and child.Name ~= "UIListLayout" then
				if child.Name ~= "Top" and child.Name ~= "Bottom" then
					child:Destroy()
				end
			end
		end
	end

	function MainGuiController:renderGuildInvites(invites: { { Summary: { [string]: any }, InvitedAt: number } })
		local scrollingFrame = self:getGuildInviteScrollingFrame()
		local template = self:getGuildInviteTemplate()
		if not scrollingFrame or not template then
			return
		end

		clearInviteListConnections()
		self:clearGuildInviteItems()
		template.Visible = false
		loadedInvites = invites

		for _, invite in invites do
			local summary = invite.Summary
			if type(summary) ~= "table" then
				continue
			end

			local item = template:Clone()
			item.Name = "InviteItem_" .. tostring(summary.Id)
			item.Visible = true
			item.Parent = scrollingFrame

			local guildTemplate = item:FindFirstChild("GuildTemplate", true) or item
			self:populateGuildListItem(guildTemplate, summary, summary.Rank)

			local joinButton = item:FindFirstChild("JoinButton", true)
			if joinButton and joinButton:IsA("GuiObject") then
				connectInviteGui(joinButton, function()
					self:handleInviteAccept(summary)
				end)
			end

			local declineButton = item:FindFirstChild("DeclineButton", true)
			if declineButton and declineButton:IsA("GuiObject") then
				connectInviteGui(declineButton, function()
					self:handleInviteDecline(summary.Id)
				end)
			end

			local viewButton = item:FindFirstChild("ViewButton", true)
			if viewButton and viewButton:IsA("GuiObject") then
				connectInviteGui(viewButton, function()
					self:viewGuildInMyGuildTab(summary.Id)
				end)
			end
		end
	end

	function MainGuiController:refreshGuildInvites()
		local GuildService = Knit.GetService("GuildService")
		GuildService:GetGuildInvites()
			:andThen(function(result)
				local invites = if type(result) == "table" and type(result.invites) == "table" then result.invites else {}
				self:renderGuildInvites(invites)
			end)
			:catch(function(err)
				warn("[MainGuiController] Guild invites failed:", err)
			end)
	end

	function MainGuiController:populateGuildListItem(item: GuiObject, summary: { [string]: any }, rank: number?)
		setTextOnDescendants(item, { "GuildName" }, tostring(summary.Name or ""))
		setTextOnDescendants(item, { "Ranking" }, getRankText(rank or summary.Rank or 0))
		setTextOnDescendants(item, { "MemberCount" }, getMemberCountText(summary))
		setTextOnDescendants(item, { "GuildScore", "Score", "Points" }, getGuildScoreText(summary))
		setImageOnDescendants(item, { "Icon", "ImageLabel" }, GuildUtil.formatIconImage(summary.IconId))

		local pointsCountFrame = item:FindFirstChild("PointsCount", true)
		if pointsCountFrame then
			setTextOnDescendants(pointsCountFrame, { "Amount" }, getGuildScoreText(summary))
		end
	end

	function MainGuiController:populateMyGuildPreview(item: GuiObject, summary: { [string]: any })
		setTextOnDescendants(item, { "GuildName" }, tostring(summary.Name or ""))
		setTextOnDescendants(item, { "Ranking" }, getRankText(summary.Rank or 0))
		setImageOnDescendants(item, { "Icon" }, GuildUtil.formatIconImage(summary.IconId))

		local memberCountFrame = item:FindFirstChild("MemberCount", true)
		if memberCountFrame then
			setTextOnDescendants(memberCountFrame, { "Amount" }, getMemberCountText(summary))
		else
			setTextOnDescendants(item, { "MemberCount" }, getMemberCountText(summary))
		end

		local pointsCountFrame = item:FindFirstChild("PointsCount", true)
		if pointsCountFrame then
			setTextOnDescendants(pointsCountFrame, { "Amount" }, getGuildScoreText(summary))
		else
			setTextOnDescendants(item, { "GuildScore", "Score", "Points", "PointsCount" }, getGuildScoreText(summary))
		end
	end

	function MainGuiController:updateMyGuildViewMode()
		local settingsFrame = self:getMyGuildSettingsFrame()
		local memberScrollFrame = self:getMyGuildMemberScrollFrame()
		local readOnly = isMyGuildReadOnlyView()
		local showSettings = not readOnly and myGuildShowingSettings and self:isGuildOwner()

		if settingsFrame then
			settingsFrame.Visible = showSettings
		end
		if memberScrollFrame then
			memberScrollFrame.Visible = not showSettings
		end
	end

	function MainGuiController:toggleMyGuildSettingsView()
		if isMyGuildReadOnlyView() or not self:isViewingOwnGuildInMyGuildTab() or not self:isGuildOwner() then
			return
		end

		myGuildShowingSettings = not myGuildShowingSettings
		self:updateMyGuildViewMode()
	end

	function MainGuiController:updateMyGuildActionButtons()
		local preview = self:getMyGuildPreviewFrame()
		if not preview then
			return
		end

		local readOnly = isMyGuildReadOnlyView()
		local viewingOwn = self:isViewingOwnGuildInMyGuildTab()

		local settingButton = preview:FindFirstChild("SettingButton", true)
			or preview:FindFirstChild("SETTING", true)
			or preview:FindFirstChild("Setting", true)
		if settingButton and settingButton:IsA("GuiObject") then
			settingButton.Visible = not readOnly and viewingOwn and self:isGuildOwner()
		end

		local leaveButton = preview:FindFirstChild("LeaveButton", true)
			or preview:FindFirstChild("LEAVE", true)
			or preview:FindFirstChild("Leave", true)
		if leaveButton and leaveButton:IsA("GuiObject") then
			leaveButton.Visible = not readOnly and viewingOwn and self:isInGuild()
			local textButton = if leaveButton:IsA("TextButton")
				then leaveButton
				else leaveButton:FindFirstChildWhichIsA("TextButton", true)
			if textButton then
				textButton.Text = if self:isGuildOwner() then "DISBAND" else "LEAVE"
			end
		end
	end

	function MainGuiController:updateMyGuildVisibilityLabel(isPublic: boolean)
		local settingsFrame = self:getMyGuildSettingsFrame()
		if not settingsFrame then
			return
		end

		local currentlyLabel = settingsFrame:FindFirstChild("Currently", true)
		if currentlyLabel and currentlyLabel:IsA("TextLabel") then
			currentlyLabel.Text = if isPublic then "Currently PUBLIC" else "Currently PRIVATE"
		end
	end

	function MainGuiController:updateMyGuildSettingsAccess()
		self:updateMyGuildActionButtons()
	end

	function MainGuiController:clearMyGuildMemberItems()
		local scrollingFrame = self:getMyGuildMemberScrollingFrame()
		local template = self:getMyGuildMemberTemplate()
		if not scrollingFrame or not template then
			return
		end

		for _, child in scrollingFrame:GetChildren() do
			if child:IsA("GuiObject") and child ~= template and child.Name ~= "UIListLayout" then
				if child.Name ~= "Top" and child.Name ~= "Bottom" then
					child:Destroy()
				end
			end
		end
	end

	function MainGuiController:populateMyGuildMemberItem(item: GuiObject, member: { [string]: any })
		local username = tostring(member.DisplayName or "Player")
		setTextOnDescendants(item, { "Username" }, `@{username}`)
		setTextOnDescendants(item, { "Role" }, formatGuildRole(tostring(member.Role or "")))

		local points = math.max(math.floor(tonumber(member.Points) or 0), 0)
		local pointsText = FormatUtil.formatNumber(points)
		local pointsFrame = item:FindFirstChild("Points", true)
		if pointsFrame then
			setTextOnDescendants(pointsFrame, { "Count", "Amount" }, pointsText)
		else
			setTextOnDescendants(item, { "Count", "Amount" }, pointsText)
		end

		local icon = findImageLabel(item, { "MemberIcon", "Icon" })
		if icon then
			setPlayerThumbnail(icon, member.UserId)
		end
	end

	function MainGuiController:renderMyGuildMembers(members: { { [string]: any } })
		local scrollingFrame = self:getMyGuildMemberScrollingFrame()
		local template = self:getMyGuildMemberTemplate()
		if not scrollingFrame or not template then
			return
		end

		template.Visible = false

		local existingItems: { [number]: GuiObject } = {}
		for _, child in scrollingFrame:GetChildren() do
			if child:IsA("GuiObject") and string.sub(child.Name, 1, 7) == "Member_" then
				local userId = tonumber(string.sub(child.Name, 8))
				if userId then
					existingItems[userId] = child
				end
			end
		end

		local newUserIds: { [number]: boolean } = {}
		for index, member in members do
			local userId = member.UserId
			if type(userId) ~= "number" then
				continue
			end

			newUserIds[userId] = true
			local item = existingItems[userId]
			if not item then
				item = template:Clone()
				item.Name = "Member_" .. tostring(userId)
				item.Parent = scrollingFrame
			end
			item.Visible = true
			item.LayoutOrder = index
			self:populateMyGuildMemberItem(item, member)
		end

		for userId, item in existingItems do
			if not newUserIds[userId] then
				item:Destroy()
			end
		end

		local layout = scrollingFrame:FindFirstChildWhichIsA("UIListLayout")
		if layout then
			scrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
			if not layout:GetAttribute("MyGuildCanvasBound") then
				layout:SetAttribute("MyGuildCanvasBound", true)
				clearMyGuildListConnections()
				table.insert(
					myGuildListConnections,
					layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
						scrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
					end)
				)
			end
		end
	end

	function MainGuiController:updateMyGuildPreview(summary: { [string]: any }?)
		local preview = self:getMyGuildPreviewFrame()
		if not preview then
			return
		end

		if not summary then
			setTextOnDescendants(preview, { "GuildName" }, "No Guild")
			setTextOnDescendants(preview, { "Ranking" }, "Rank --")
			local memberCountFrame = preview:FindFirstChild("MemberCount", true)
			if memberCountFrame then
				setTextOnDescendants(memberCountFrame, { "Amount" }, `0/{GuildConfig.MaxMembers}`)
			end
			local pointsCountFrame = preview:FindFirstChild("PointsCount", true)
			if pointsCountFrame then
				setTextOnDescendants(pointsCountFrame, { "Amount" }, "0")
			end
			setImageOnDescendants(preview, { "Icon" }, "")
			self:updateMyGuildActionButtons()
			return
		end

		self:populateMyGuildPreview(preview, summary)
		self:updateMyGuildActionButtons()
	end

	function MainGuiController:applyMyGuildDisplayData(summary: { [string]: any }, members: { { [string]: any } }?)
		myGuildIsPublic = summary.IsPublic == true
		self:updateMyGuildPreview(summary)
		self:updateGuildHeaderPower()
		self:updateMyGuildVisibilityLabel(myGuildIsPublic)
		if not isMyGuildReadOnlyView() and self:isGuildOwner() then
			self:setPrivacySelection(self:getMyGuildSettingsFrame() or self:getMyGuildFrame() :: GuiObject, myGuildIsPublic)
		end
		self:updateMyGuildViewMode()
		self:updateMyGuildSettingsAccess()
		self:renderMyGuildMembers(if type(members) == "table" then members else {})
	end

	function MainGuiController:refreshMyGuildDisplay()
		local GuildService = Knit.GetService("GuildService")

		if myGuildViewGuildId ~= nil then
			GuildService:GetGuildDetails(myGuildViewGuildId)
				:andThen(function(summary, members)
					if not summary then
						self:updateMyGuildPreview(nil)
						self:clearMyGuildMemberItems()
						return
					end

					self:applyMyGuildDisplayData(summary, members)
				end)
				:catch(function(err)
					warn("[MainGuiController] Guild view failed:", err)
				end)
			return
		end

		if not self:isInGuild() then
			self:updateMyGuildPreview(nil)
			self:clearMyGuildMemberItems()
			return
		end

		GuildService:GetMyGuild()
			:andThen(function(summary, members)
				if not summary then
					self:updateMyGuildPreview(nil)
					self:clearMyGuildMemberItems()
					return
				end

				self:applyMyGuildDisplayData(summary, members)
			end)
			:catch(function(err)
				warn("[MainGuiController] My guild failed:", err)
			end)
	end

	function MainGuiController:refreshMyGuild()
		self:refreshMyGuildDisplay()
	end

	function MainGuiController:submitMyGuildInvite()
		if guildRequestOpen or not self:isGuildOwner() then
			return
		end

		local inviteInput = self:getMyGuildInviteInput()
		local username = if inviteInput then inviteInput.Text else ""
		local trimmed = string.gsub(username, "^%s+", "")
		trimmed = string.gsub(trimmed, "%s+$", "")
		if trimmed == "" then
			warn("[MainGuiController] Invite failed: Username required")
			return
		end

		guildRequestOpen = true
		local GuildService = Knit.GetService("GuildService")
		GuildService:InvitePlayerByUsername(trimmed)
			:andThen(function(success, err)
				guildRequestOpen = false
				if success then
					SoundUtil.TutorialProgress()
					if inviteInput then
						inviteInput.Text = ""
					end
				elseif err then
					warn("[MainGuiController] Invite failed:", err)
				end
			end)
			:catch(function(err)
				guildRequestOpen = false
				warn("[MainGuiController] Invite failed:", err)
			end)
	end

	function MainGuiController:submitMyGuildVisibility(isPublic: boolean)
		if guildRequestOpen or not self:isGuildOwner() or myGuildIsPublic == isPublic then
			if myGuildIsPublic ~= isPublic then
				self:setPrivacySelection(self:getMyGuildSettingsFrame() or self:getMyGuildFrame() :: GuiObject, myGuildIsPublic)
			end
			return
		end

		guildRequestOpen = true
		local GuildService = Knit.GetService("GuildService")
		GuildService:SetGuildVisibility(isPublic)
			:andThen(function(success, err)
				guildRequestOpen = false
				if success then
					SoundUtil.TutorialProgress()
					myGuildIsPublic = isPublic
					self:updateMyGuildVisibilityLabel(isPublic)
					self:setPrivacySelection(self:getMyGuildSettingsFrame() or self:getMyGuildFrame() :: GuiObject, isPublic)
					self:refreshMyGuild()
					self:refreshGuildList()
				elseif err then
					warn("[MainGuiController] Visibility update failed:", err)
					self:setPrivacySelection(
						self:getMyGuildSettingsFrame() or self:getMyGuildFrame() :: GuiObject,
						myGuildIsPublic
					)
				end
			end)
			:catch(function(err)
				guildRequestOpen = false
				warn("[MainGuiController] Visibility update failed:", err)
			end)
	end

	function MainGuiController:clearGuildListItems()
		local scrollingFrame = self:getGuildScrollingFrame()
		local template = self:getGuildTemplate()
		if not scrollingFrame or not template then
			return
		end

		for _, child in scrollingFrame:GetChildren() do
			if child:IsA("GuiObject") and child ~= template and child.Name ~= "UIListLayout" then
				if child.Name ~= "Top" and child.Name ~= "Bottom" then
					child:Destroy()
				end
			end
		end
	end

	function MainGuiController:connectGuildListItem(item: GuiObject, summary: { [string]: any })
		local function onSelect()
			selectedGuildId = summary.Id
			self:updateGuildPreview(summary)
		end

		if item:IsA("TextButton") or item:IsA("ImageButton") then
			table.insert(listConnections, item.Activated:Connect(onSelect))
		else
			table.insert(
				listConnections,
				item.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						onSelect()
					end
				end)
			)
		end
	end

	function MainGuiController:updateGuildListItemInPlace(summary: { [string]: any })
		local scrollingFrame = self:getGuildScrollingFrame()
		if not scrollingFrame then
			return
		end

		for index, guild in loadedGuilds do
			if guild.Id == summary.Id then
				loadedGuilds[index] = summary
				break
			end
		end

		local item = scrollingFrame:FindFirstChild("GuildItem_" .. tostring(summary.Id))
		if item and item:IsA("GuiObject") then
			local listIndex = 0
			for index, guild in loadedGuilds do
				if guild.Id == summary.Id then
					listIndex = index
					break
				end
			end
			local rank = if listMode == "Top" then listIndex else summary.Rank
			self:populateGuildListItem(item, summary, rank)
		end

		if selectedGuildId == summary.Id then
			self:updateGuildPreview(summary)
		end
	end

	function MainGuiController:renderGuildList(guilds: { { [string]: any } })
		local scrollingFrame = self:getGuildScrollingFrame()
		local template = self:getGuildTemplate()
		if not scrollingFrame or not template then
			return
		end

		local forceRebuild = lastRenderedListMode ~= listMode
		lastRenderedListMode = listMode
		loadedGuilds = guilds

		if forceRebuild then
			clearListConnections()
			self:clearGuildListItems()
		end

		template.Visible = false

		local existingItems: { [string]: GuiObject } = {}
		for _, child in scrollingFrame:GetChildren() do
			if child:IsA("GuiObject") and string.sub(child.Name, 1, 10) == "GuildItem_" then
				existingItems[string.sub(child.Name, 11)] = child
			end
		end

		local newIds: { [string]: boolean } = {}
		for index, summary in guilds do
			newIds[summary.Id] = true
			local item = existingItems[summary.Id]
			if not item then
				item = template:Clone()
				item.Name = "GuildItem_" .. tostring(summary.Id)
				item.Parent = scrollingFrame
				self:connectGuildListItem(item, summary)
			end
			item.Visible = true
			item.LayoutOrder = index
			self:populateGuildListItem(
				item,
				summary,
				if listMode == "Top" then index else summary.Rank
			)
		end

		for guildId, item in existingItems do
			if not newIds[guildId] then
				item:Destroy()
			end
		end

		if #guilds > 0 then
			local stillSelected = false
			if selectedGuildId then
				for _, summary in guilds do
					if summary.Id == selectedGuildId then
						stillSelected = true
						self:updateGuildPreview(summary)
						break
					end
				end
			end
			if not stillSelected then
				local firstGuild = guilds[1]
				selectedGuildId = firstGuild.Id
				self:updateGuildPreview(firstGuild)
			end
		else
			selectedGuildId = nil
			self:updateGuildPreview(nil)
		end

		local layout = scrollingFrame:FindFirstChildWhichIsA("UIListLayout")
		if layout then
			scrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
			if not layout:GetAttribute("GuildListCanvasBound") then
				layout:SetAttribute("GuildListCanvasBound", true)
				table.insert(
					listConnections,
					layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
						scrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
					end)
				)
			end
		end
	end

	function MainGuiController:updateGuildPreview(summary: { [string]: any }?)
		local preview = self:getPreviewGuildFrame()
		if not preview then
			return
		end

		if not summary then
			setTextOnDescendants(preview, { "GuildName" }, "No Guilds")
			setTextOnDescendants(preview, { "Ranking" }, "Rank --")
			setTextOnDescendants(preview, { "MemberCount" }, `0/{GuildConfig.MaxMembers}`)
			setImageOnDescendants(preview, { "Icon" }, "")
			self:updateGuildActionButtons(nil)
			return
		end

		self:populateGuildListItem(preview, summary, summary.Rank)
		self:updateGuildActionButtons(summary)
	end

	function MainGuiController:updateGuildActionButtons(summary: { [string]: any }?)
		local preview = self:getPreviewGuildFrame()
		if not preview then
			return
		end

		local joinButton = preview:FindFirstChild("JoinButton", true)
		if not (joinButton and joinButton:IsA("GuiObject")) then
			return
		end

		local guildData = self:getPlayerGuildData()
		local textButton = if joinButton:IsA("TextButton") then joinButton else joinButton:FindFirstChildWhichIsA("TextButton", true)

		if not summary then
			joinButton.Visible = false
			return
		end

		joinButton.Visible = true
		local active = true

		if guildData.GuildId == summary.Id then
			if guildData.Role == GuildUtil.RoleOwner then
				if textButton then
					textButton.Text = "OWNER"
				end
				active = false
			else
				if textButton then
					textButton.Text = "LEAVE"
				end
				active = true
			end
		elseif guildData.GuildId ~= "" then
			if textButton then
				textButton.Text = "JOIN"
			end
			active = summary.IsPublic == true
		elseif summary.IsPublic == true then
			if textButton then
				textButton.Text = "JOIN"
			end
			active = true
		else
			if textButton then
				textButton.Text = "PRIVATE"
			end
			active = false
		end

		if joinButton:IsA("GuiButton") then
			joinButton.Active = active
			joinButton.AutoButtonColor = active
		end
	end

	function MainGuiController:refreshBrowseRandomGuilds()
		if browseSearchDebounceThread then
			task.cancel(browseSearchDebounceThread)
			browseSearchDebounceThread = nil
		end

		browseSearchQuery = ""
		local searchInput = self:getBrowseSearchInput()
		if searchInput then
			searchInput.Text = ""
		end
		self:refreshGuildList()
	end

	function MainGuiController:submitBrowseSearch()
		local searchInput = self:getBrowseSearchInput()
		local query = if searchInput then GuildUtil.normalizeGuildName(searchInput.Text) else ""

		if query == "" then
			browseSearchQuery = ""
			self:refreshGuildList()
			return
		end

		if #query < BROWSE_SEARCH_MIN_LENGTH then
			return
		end

		browseSearchQuery = query
		self:refreshGuildList()
	end

	function MainGuiController:scheduleBrowseSearch()
		if browseSearchDebounceThread then
			task.cancel(browseSearchDebounceThread)
			browseSearchDebounceThread = nil
		end

		browseSearchDebounceThread = task.delay(BROWSE_SEARCH_DEBOUNCE_SECONDS, function()
			browseSearchDebounceThread = nil
			if activeTab ~= "Browse" then
				return
			end
			self:submitBrowseSearch()
		end)
	end

	function MainGuiController:refreshGuildList()
		local GuildService = Knit.GetService("GuildService")
		if listMode == "Browse" then
			GuildService:BrowseGuilds(browseSearchQuery)
				:andThen(function(result, hasMore)
					browseHasMore = hasMore == true
					local guilds = if type(result) == "table" and type(result.guilds) == "table" then result.guilds else {}
					self:renderGuildList(guilds)
				end)
				:catch(function(err)
					warn("[MainGuiController] Browse guilds failed:", err)
				end)
			return
		end

		GuildService:GetTopGuilds()
			:andThen(function(result)
				local guilds = if type(result) == "table" and type(result.guilds) == "table" then result.guilds else {}
				self:renderGuildList(guilds)
			end)
			:catch(function(err)
				warn("[MainGuiController] Top guilds failed:", err)
			end)
	end

	function MainGuiController:updateCreateGuildAccess()
		local sideButtons = self:getGuildsFrame() and self:getGuildsFrame():FindFirstChild("SideButtons", true)
		if not sideButtons then
			return
		end

		local createButton = sideButtons:FindFirstChild("CreateGuild", true)
		if createButton and createButton:IsA("GuiObject") then
			createButton.Visible = self:canCreateGuild()
		end

		local myGuildButton = sideButtons:FindFirstChild("MyGuild", true)
		if myGuildButton and myGuildButton:IsA("GuiObject") then
			myGuildButton.Visible = self:isInGuild()
		end

		if activeTab == "Create" and not self:canCreateGuild() then
			if self:isInGuild() then
				self:openMyGuildTab()
			else
				self:setGuildTab("Top")
			end
		elseif activeTab == "MyGuild" and not self:isInGuild() and myGuildViewGuildId == nil then
			self:setGuildTab("Top")
		end
	end

	function MainGuiController:setPrivacySelection(createFrame: GuiObject, isPublic: boolean)
		local publicButton = createFrame:FindFirstChild("PUBLIC", true)
			or createFrame:FindFirstChild("Public", true)
		local privateButton = createFrame:FindFirstChild("PRIVATE", true)
			or createFrame:FindFirstChild("Private", true)

		local function setStroke(button: Instance?, selected: boolean)
			if not button or not button:IsA("GuiObject") then
				return
			end
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if not stroke then
				stroke = Instance.new("UIStroke")
				stroke.Parent = button
			end
			stroke.Thickness = if selected then PRIVACY_SELECTED_STROKE else PRIVACY_UNSELECTED_STROKE
			stroke.Color = Color3.fromRGB(255, 255, 255)
		end

		setStroke(publicButton, isPublic)
		setStroke(privateButton, not isPublic)
	end

	function MainGuiController:updateCreateGuildPreview(createFrame: GuiObject)
		local iconPreview = findImageLabel(createFrame, { "GuildIcon", "Icon" })
		local textBox = findCreateGuildLogoTextBox(createFrame)

		if not iconPreview then
			return
		end

		if not textBox then
			iconPreview.Image = ""
			return
		end

		local iconId = GuildUtil.parseIconIdOptional(textBox.Text)
		iconPreview.Image = GuildUtil.formatIconImage(iconId)
	end

	function MainGuiController:hideGuildMemberList()
		if memberListFrame then
			memberListFrame.Visible = false
		end
	end

	function MainGuiController:showGuildMemberList(guildId: string)
		local topGuildsFrame = self:getTopGuildsFrame()
		if not topGuildsFrame then
			return
		end

		if not memberListFrame then
			memberListFrame = Instance.new("Frame")
			memberListFrame.Name = "MemberListFrame"
			memberListFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
			memberListFrame.BackgroundTransparency = 0.1
			memberListFrame.BorderSizePixel = 0
			memberListFrame.Size = UDim2.fromScale(0.45, 0.55)
			memberListFrame.Position = UDim2.fromScale(0.5, 0.5)
			memberListFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			memberListFrame.ZIndex = 20
			memberListFrame.Parent = topGuildsFrame

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 12)
			corner.Parent = memberListFrame

			local title = Instance.new("TextLabel")
			title.Name = "Title"
			title.BackgroundTransparency = 1
			title.Size = UDim2.new(1, -20, 0, 36)
			title.Position = UDim2.fromOffset(10, 8)
			title.Font = Enum.Font.GothamBold
			title.TextSize = 20
			title.TextColor3 = Color3.fromRGB(255, 255, 255)
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Text = "Members"
			title.Parent = memberListFrame

			local closeButton = Instance.new("TextButton")
			closeButton.Name = "CloseButton"
			closeButton.Size = UDim2.fromOffset(28, 28)
			closeButton.Position = UDim2.new(1, -36, 0, 8)
			closeButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
			closeButton.Text = "X"
			closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
			closeButton.Font = Enum.Font.GothamBold
			closeButton.TextSize = 16
			closeButton.Parent = memberListFrame

			local closeCorner = Instance.new("UICorner")
			closeCorner.CornerRadius = UDim.new(0, 6)
			closeCorner.Parent = closeButton

			connectGui(closeButton, function()
				self:hideGuildMemberList()
			end)

			local list = Instance.new("ScrollingFrame")
			list.Name = "List"
			list.BackgroundTransparency = 1
			list.BorderSizePixel = 0
			list.Size = UDim2.new(1, -20, 1, -56)
			list.Position = UDim2.fromOffset(10, 48)
			list.ScrollBarThickness = 6
			list.CanvasSize = UDim2.new()
			list.Parent = memberListFrame

			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 6)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = list
		end

		memberListFrame.Visible = true
		local list = memberListFrame:FindFirstChild("List")
		if not list or not list:IsA("ScrollingFrame") then
			return
		end

		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") and not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end

		local GuildService = Knit.GetService("GuildService")
		GuildService:GetGuildDetails(guildId)
			:andThen(function(summary, members)
				if not memberListFrame or not memberListFrame.Visible then
					return
				end

				local title = memberListFrame:FindFirstChild("Title")
				if title and title:IsA("TextLabel") and type(summary) == "table" then
					title.Text = `Members - {summary.Name}`
				end

				local guildData = self:getPlayerGuildData()
				local canKick = guildData.GuildId == guildId and guildData.Role == GuildUtil.RoleOwner

				if type(members) ~= "table" then
					return
				end

				for index, member in members do
					local row = Instance.new("Frame")
					row.Name = "Member_" .. tostring(member.UserId)
					row.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
					row.BorderSizePixel = 0
					row.Size = UDim2.new(1, 0, 0, 34)
					row.LayoutOrder = index
					row.Parent = list

					local rowCorner = Instance.new("UICorner")
					rowCorner.CornerRadius = UDim.new(0, 8)
					rowCorner.Parent = row

					local nameLabel = Instance.new("TextLabel")
					nameLabel.BackgroundTransparency = 1
					nameLabel.Size = UDim2.new(1, -90, 1, 0)
					nameLabel.Position = UDim2.fromOffset(10, 0)
					nameLabel.Font = Enum.Font.Gotham
					nameLabel.TextSize = 16
					nameLabel.TextXAlignment = Enum.TextXAlignment.Left
					nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					nameLabel.Text = `{member.DisplayName} ({member.Role})`
					nameLabel.Parent = row

					if canKick and member.Role ~= GuildUtil.RoleOwner then
						local kickButton = Instance.new("TextButton")
						kickButton.Name = "KickButton"
						kickButton.Size = UDim2.fromOffset(70, 24)
						kickButton.Position = UDim2.new(1, -78, 0.5, -12)
						kickButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
						kickButton.Text = "KICK"
						kickButton.TextColor3 = Color3.fromRGB(255, 255, 255)
						kickButton.Font = Enum.Font.GothamBold
						kickButton.TextSize = 14
						kickButton.Parent = row

						local kickCorner = Instance.new("UICorner")
						kickCorner.CornerRadius = UDim.new(0, 6)
						kickCorner.Parent = kickButton

						kickButton.Activated:Connect(function()
							if guildRequestOpen then
								return
							end
							guildRequestOpen = true
							GuildService:KickMember(member.UserId)
								:andThen(function(success, err)
									guildRequestOpen = false
									if success then
										SoundUtil.TutorialProgress()
										self:showGuildMemberList(guildId)
										self:refreshGuildList()
									elseif err then
										warn("[MainGuiController] Kick failed:", err)
									end
								end)
								:catch(function(err)
									guildRequestOpen = false
									warn("[MainGuiController] Kick failed:", err)
								end)
						end)
					end
				end

				local layout = list:FindFirstChildOfClass("UIListLayout")
				if layout then
					list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
				end
			end)
			:catch(function(err)
				warn("[MainGuiController] Guild details failed:", err)
			end)
	end

	function MainGuiController:submitCreateGuild(createFrame: GuiObject, isPublic: boolean)
		if guildRequestOpen or not self:canCreateGuild() then
			return
		end

		local nameTextBox = findCreateGuildNameTextBox(createFrame)
		local logoTextBox = findCreateGuildLogoTextBox(createFrame)
		local nameText = if nameTextBox then nameTextBox.Text else ""
		local logoText = if logoTextBox then logoTextBox.Text else ""

		local validName, nameErr = GuildUtil.isValidGuildName(nameText)
		if not validName then
			warn("[MainGuiController] Create guild failed:", nameErr or "Invalid guild name")
			return
		end

		local _, iconErr = GuildUtil.parseIconIdOptional(logoText)
		if iconErr then
			warn("[MainGuiController] Create guild failed:", iconErr)
			return
		end

		guildRequestOpen = true
		local GuildService = Knit.GetService("GuildService")
		GuildService:CreateGuild(nameText, logoText, isPublic)
			:andThen(function(success, err)
				guildRequestOpen = false
				if success then
					SoundUtil.TutorialProgress()
					self:updateCreateGuildAccess()
					self:openMyGuildTab()
					self:refreshGuildList()
				elseif err then
					warn("[MainGuiController] Create guild failed:", err)
				end
			end)
			:catch(function(err)
				guildRequestOpen = false
				warn("[MainGuiController] Create guild failed:", err)
			end)
	end

	function MainGuiController:handleGuildJoinAction(summary: { [string]: any })
		if guildRequestOpen or not summary then
			return
		end

		local guildData = self:getPlayerGuildData()
		local GuildService = Knit.GetService("GuildService")

		if guildData.GuildId == summary.Id then
			if guildData.Role == GuildUtil.RoleOwner then
				return
			end

			self:promptLeaveGuild(function()
				self:refreshGuildList()
			end)
			return
		end

		if summary.IsPublic ~= true then
			return
		end

		local function performJoin()
			guildRequestOpen = true
			GuildService:JoinGuild(summary.Id)
				:andThen(function(success, err)
					guildRequestOpen = false
					if success then
						SoundUtil.TutorialProgress()
						self:updateCreateGuildAccess()
						self:updateGuildHeaderPower()
						self:openMyGuildTab()
						self:refreshGuildList()
					elseif err then
						warn("[MainGuiController] Join guild failed:", err)
					end
				end)
				:catch(function(err)
					guildRequestOpen = false
					warn("[MainGuiController] Join guild failed:", err)
				end)
		end

		local confirmationMessage = if guildData.GuildId ~= ""
			then SWAP_GUILD_JOIN_CONFIRMATION_MESSAGE
			else JOIN_CONFIRMATION_MESSAGE
		self:showGuildJoinConfirmation(function()
			self:hideGuildJoinConfirmation()
			performJoin()
		end, confirmationMessage)
	end

	function MainGuiController:setupGuildsFrame()
		self:clearGuildConnections()
		self:hideGuildMemberList()
		self:hideGuildConfirmation()
		self:hideGuildJoinConfirmation()
		self:hideGuildLeaveConfirmation()

		local frame = self:getGuildsFrame()
		if not frame then
			return
		end

		frame.Visible = false
		OpenFrame.SetupFrame(frame)
		self:updateCreateGuildAccess()

		local topFrameHeader = frame:FindFirstChild("TopFrame", true)
		local closeButton = topFrameHeader and topFrameHeader:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiObject") then
			connectGui(closeButton, function()
				OpenFrame.Toggle(frame, false)
				self:hideGuildMemberList()
				self:hideGuildConfirmation()
				self:hideGuildJoinConfirmation()
				self:hideGuildLeaveConfirmation()
			end)
		end

		local confirmationFrame = self:getGuildConfirmationFrame()
		if confirmationFrame then
			confirmationFrame.Visible = false
			local yesButton = confirmationFrame:FindFirstChild("YesButton", true)
			local noButton = confirmationFrame:FindFirstChild("NoButton", true)
			if yesButton and yesButton:IsA("GuiObject") then
				connectGui(yesButton, function()
					local leaveAction = pendingLeaveConfirmationAction
					if leaveAction then
						pendingLeaveConfirmationAction = nil
						leaveAction()
						return
					end

					local action = pendingConfirmationAction
					pendingConfirmationAction = nil
					if action then
						action()
					end
				end)
			end
			if noButton and noButton:IsA("GuiObject") then
				connectGui(noButton, function()
					self:hideGuildConfirmation()
					self:hideGuildLeaveConfirmation()
				end)
			end
		end

		local joinConfirmationFrame = self:getGuildJoinConfirmationFrame()
		if joinConfirmationFrame then
			joinConfirmationFrame.Visible = false
			local joinYesButton = joinConfirmationFrame:FindFirstChild("YesButton", true)
			local joinNoButton = joinConfirmationFrame:FindFirstChild("NoButton", true)
			if joinYesButton and joinYesButton:IsA("GuiObject") then
				connectGui(joinYesButton, function()
					local action = pendingJoinConfirmationAction
					pendingJoinConfirmationAction = nil
					if action then
						action()
					end
				end)
			end
			if joinNoButton and joinNoButton:IsA("GuiObject") then
				connectGui(joinNoButton, function()
					self:hideGuildJoinConfirmation()
				end)
			end
		end

		local leaveConfirmationFrame = self:getGuildLeaveConfirmationFrame()
		if leaveConfirmationFrame and leaveConfirmationFrame ~= confirmationFrame then
			leaveConfirmationFrame.Visible = false
			local leaveYesButton = leaveConfirmationFrame:FindFirstChild("YesButton", true)
			local leaveNoButton = leaveConfirmationFrame:FindFirstChild("NoButton", true)
			if leaveYesButton and leaveYesButton:IsA("GuiObject") then
				connectGui(leaveYesButton, function()
					local action = pendingLeaveConfirmationAction
					pendingLeaveConfirmationAction = nil
					if action then
						action()
					end
				end)
			end
			if leaveNoButton and leaveNoButton:IsA("GuiObject") then
				connectGui(leaveNoButton, function()
					self:hideGuildLeaveConfirmation()
				end)
			end
		end

		local sideButtons = frame:FindFirstChild("SideButtons", true)
		if sideButtons then
			local topButton = sideButtons:FindFirstChild("TopGuilds", true)
			local createButton = sideButtons:FindFirstChild("CreateGuild", true)
			local browseButton = sideButtons:FindFirstChild("BrowseGuilds", true)
			local invitesButton = sideButtons:FindFirstChild("Invites", true)
				or sideButtons:FindFirstChild("GuildInvites", true)
			local myGuildButton = sideButtons:FindFirstChild("MyGuild", true)

			if topButton and topButton:IsA("GuiObject") then
				connectGui(topButton, function()
					self:setGuildTab("Top")
				end)
			end
			if createButton and createButton:IsA("GuiObject") then
				connectGui(createButton, function()
					if not self:canCreateGuild() then
						return
					end
					self:setGuildTab("Create")
				end)
			end
			if browseButton and browseButton:IsA("GuiObject") then
				connectGui(browseButton, function()
					self:setGuildTab("Browse")
				end)
			end
			if invitesButton and invitesButton:IsA("GuiObject") then
				connectGui(invitesButton, function()
					self:setGuildTab("Invites")
				end)
			end
			if myGuildButton and myGuildButton:IsA("GuiObject") then
				connectGui(myGuildButton, function()
					if not self:isInGuild() then
						return
					end
					self:openMyGuildTab()
				end)
			end
		end

		local myGuildFrame = self:getMyGuildFrame()
		if myGuildFrame then
			myGuildShowingSettings = false

			local settingsFrame = self:getMyGuildSettingsFrame()
			local memberScrollFrame = self:getMyGuildMemberScrollFrame()
			if settingsFrame then
				settingsFrame.Visible = false
			end
			if memberScrollFrame then
				memberScrollFrame.Visible = true
			end
			self:updateMyGuildViewMode()

			local preview = self:getMyGuildPreviewFrame()
			local settingButton = if preview
				then preview:FindFirstChild("SettingButton", true)
					or preview:FindFirstChild("SETTING", true)
					or preview:FindFirstChild("Setting", true)
				else myGuildFrame:FindFirstChild("SettingButton", true)
					or myGuildFrame:FindFirstChild("SETTING", true)
			if settingButton and settingButton:IsA("GuiObject") then
				connectGui(settingButton, function()
					self:toggleMyGuildSettingsView()
				end)
			end

			if preview then
				local leaveButton = preview:FindFirstChild("LeaveButton", true)
					or preview:FindFirstChild("LEAVE", true)
					or preview:FindFirstChild("Leave", true)
				if leaveButton and leaveButton:IsA("GuiObject") then
					connectGui(leaveButton, function()
						if self:isGuildOwner() then
							self:showGuildLeaveConfirmation(function()
								self:hideGuildLeaveConfirmation()
								self:executeLeaveGuild(function()
									myGuildViewGuildId = nil
									myGuildShowingSettings = false
									self:setGuildTab("Browse")
								end)
							end, DISBAND_CONFIRMATION_MESSAGE)
							return
						end

						self:promptLeaveGuild(function()
							self:setGuildTab("Top")
						end)
					end)
				end
			end

			local settingsFrameForButtons = self:getMyGuildSettingsFrame()
			if settingsFrameForButtons then
				local publicButton = settingsFrameForButtons:FindFirstChild("MakePublic", true)
					or settingsFrameForButtons:FindFirstChild("PUBLIC", true)
					or settingsFrameForButtons:FindFirstChild("Public", true)
				local privateButton = settingsFrameForButtons:FindFirstChild("MakePrivate", true)
					or settingsFrameForButtons:FindFirstChild("PRIVATE", true)
					or settingsFrameForButtons:FindFirstChild("Private", true)

				if publicButton and publicButton:IsA("GuiObject") then
					connectGui(publicButton, function()
						self:submitMyGuildVisibility(true)
					end)
				end
				if privateButton and privateButton:IsA("GuiObject") then
					connectGui(privateButton, function()
						self:submitMyGuildVisibility(false)
					end)
				end

				local inviteButton = settingsFrameForButtons:FindFirstChild("InviteButton", true)
				if inviteButton and inviteButton:IsA("GuiObject") then
					connectGui(inviteButton, function()
						self:submitMyGuildInvite()
					end)
				end
			end
		end

		local preview = self:getPreviewGuildFrame()
		if preview then
			local joinButton = preview:FindFirstChild("JoinButton", true)
			if joinButton and joinButton:IsA("GuiObject") then
				connectGui(joinButton, function()
					local summary = nil
					for _, guild in loadedGuilds do
						if guild.Id == selectedGuildId then
							summary = guild
							break
						end
					end
					if summary then
						self:handleGuildJoinAction(summary)
					end
				end)
			end

			local viewButton = preview:FindFirstChild("ViewButton", true)
			if viewButton and viewButton:IsA("GuiObject") then
				connectGui(viewButton, function()
					if selectedGuildId then
						self:viewGuildInMyGuildTab(selectedGuildId)
					end
				end)
			end
		end

		local browseFrame = self:getBrowseGuildsFrame()
		if browseFrame then
			local browsePreview = browseFrame:FindFirstChild("PreviewGuild", true)
			if browsePreview and browsePreview:IsA("GuiObject") then
				local joinButton = browsePreview:FindFirstChild("JoinButton", true)
				if joinButton and joinButton:IsA("GuiObject") then
					connectGui(joinButton, function()
						local summary = nil
						for _, guild in loadedGuilds do
							if guild.Id == selectedGuildId then
								summary = guild
								break
							end
						end
						if summary then
							self:handleGuildJoinAction(summary)
						end
					end)
				end

				local viewButton = browsePreview:FindFirstChild("ViewButton", true)
				if viewButton and viewButton:IsA("GuiObject") then
					connectGui(viewButton, function()
						if selectedGuildId then
							self:viewGuildInMyGuildTab(selectedGuildId)
						end
					end)
				end
			end

			local searchInput = self:getBrowseSearchInput()
			if searchInput then
				table.insert(
					guildConnections,
					searchInput:GetPropertyChangedSignal("Text"):Connect(function()
						if activeTab ~= "Browse" then
							return
						end

						local query = GuildUtil.normalizeGuildName(searchInput.Text)
						if query == "" then
							if browseSearchQuery ~= "" then
								browseSearchQuery = ""
								self:refreshGuildList()
							end
							return
						end

						self:scheduleBrowseSearch()
					end)
				)

				table.insert(guildConnections, searchInput.FocusLost:Connect(function(enterPressed)
					if activeTab ~= "Browse" then
						return
					end

					if enterPressed then
						if browseSearchDebounceThread then
							task.cancel(browseSearchDebounceThread)
							browseSearchDebounceThread = nil
						end
						self:submitBrowseSearch()
					end
				end))
			end

			local refreshButton = self:getBrowseRefreshButton()
			if refreshButton then
				connectGui(refreshButton, function()
					if activeTab ~= "Browse" then
						return
					end

					self:refreshBrowseRandomGuilds()
				end)
			end
		end

		local createFrame = self:getCreateGuildFrame()
		if createFrame then
			createIsPublic = true
			self:setPrivacySelection(createFrame, createIsPublic)

			local publicButton = createFrame:FindFirstChild("PUBLIC", true)
				or createFrame:FindFirstChild("Public", true)
			local privateButton = createFrame:FindFirstChild("PRIVATE", true)
				or createFrame:FindFirstChild("Private", true)

			if publicButton and publicButton:IsA("GuiObject") then
				connectGui(publicButton, function()
					createIsPublic = true
					self:setPrivacySelection(createFrame, createIsPublic)
				end)
			end
			if privateButton and privateButton:IsA("GuiObject") then
				connectGui(privateButton, function()
					createIsPublic = false
					self:setPrivacySelection(createFrame, createIsPublic)
				end)
			end

			local logoTextBox = findCreateGuildLogoTextBox(createFrame)
			if logoTextBox then
				table.insert(guildConnections, logoTextBox:GetPropertyChangedSignal("Text"):Connect(function()
					self:updateCreateGuildPreview(createFrame)
				end))
			end

			local costLabel = createFrame:FindFirstChild("Cost", true)
			if costLabel and costLabel:IsA("TextLabel") then
				costLabel.Text = FormatUtil.formatNumber(GuildConfig.CreateCost)
			end

			local createGuildButton = createFrame:FindFirstChild("CreateGuildButton", true)
				or createFrame:FindFirstChild("CREATE GUILD", true)
			if createGuildButton and createGuildButton:IsA("GuiObject") then
				connectGui(createGuildButton, function()
					self:submitCreateGuild(createFrame, createIsPublic)
				end)
			end
		end

		self:setGuildTab("Top")

		local guildsButton = self:getRightSideButton(GUILDS_BUTTON_NAME)
		if guildsButton then
			connectGui(guildsButton, function()
				OpenFrame.Toggle(frame)
				if frame.Visible then
					self:updateCreateGuildAccess()
					self:updateGuildHeaderPower()
					self:refreshGuildList()
					self:refreshGuildInvites()
					if self:isInGuild() then
						if activeTab ~= "MyGuild" then
							myGuildShowingSettings = false
						end
						if activeTab == "MyGuild" then
							myGuildShowingSettings = false
							self:updateMyGuildViewMode()
							self:refreshMyGuild()
						end
					end
				else
					self:hideGuildMemberList()
					self:hideGuildConfirmation()
					self:hideGuildJoinConfirmation()
				end
			end)
		end

		local GuildService = Knit.GetService("GuildService")
		if not guildUpdatedConnection then
			guildUpdatedConnection = GuildService.GuildUpdated:Connect(function(updatedGuildId: string)
				self:updateCreateGuildAccess()

				if type(updatedGuildId) ~= "string" or updatedGuildId == "" then
					return
				end

				if self:getPlayerGuildData().GuildId == updatedGuildId then
					self:refreshMyGuildDisplay()
					self:updateGuildHeaderPower()
				end

				if activeTab == "Top" or activeTab == "Browse" then
					for _, guild in loadedGuilds do
						if guild.Id == updatedGuildId then
							GuildService:GetGuildDetails(updatedGuildId)
								:andThen(function(summary)
									if summary then
										self:updateGuildListItemInPlace(summary)
									end
								end)
							break
						end
					end
				end
			end)
		end

		if not guildInvitesUpdatedConnection then
			guildInvitesUpdatedConnection = GuildService.GuildInvitesUpdated:Connect(function()
				self:refreshGuildInvites()
			end)
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		PlayerDataController:Observe("Guild", function()
			self:updateCreateGuildAccess()
			for _, guild in loadedGuilds do
				if guild.Id == selectedGuildId then
					self:updateGuildPreview(guild)
					break
				end
			end
			if activeTab == "MyGuild" then
				self:refreshMyGuild()
			end
		end)

		PlayerDataController:Observe("GuildInvites", function()
			self:refreshGuildInvites()
		end)
	end
end

return Guilds
