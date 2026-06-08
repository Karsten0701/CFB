local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.knit)

local AdminGuiController = Knit.CreateController({
	Name = "AdminGuiController",
})

local CMDR_ADMIN_ATTR = "BananaBombCmdrAdmin"
local localPlayer = Players.LocalPlayer

local adminGui: ScreenGui? = nil
local adminPanel: GuiObject? = nil
local announcementsFrame: GuiObject? = nil
local messageBox: TextBox? = nil
local guiConnections: { RBXScriptConnection } = {}

local function disconnectGuiConnections()
	for _, connection in guiConnections do
		connection:Disconnect()
	end
	table.clear(guiConnections)
end

local function connectPressed(root: Instance, callback: () -> ())
	if root:IsA("GuiButton") then
		table.insert(guiConnections, root.Activated:Connect(callback))
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") then
			table.insert(guiConnections, descendant.Activated:Connect(callback))
		end
	end
end

local function findTextBox(root: Instance): TextBox?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextBox") then
			return descendant
		end
	end
	return nil
end

local function findButton(root: Instance, names: { string }): GuiObject?
	for _, name in names do
		local button = root:FindFirstChild(name, true)
		if button and button:IsA("GuiObject") then
			return button
		end
	end
	return nil
end

local function findAdminPanel(root: ScreenGui): GuiObject?
	for _, name in { "AdminPanel", "Panel", "Main", "MainFrame", "Announcements" } do
		local frame = root:FindFirstChild(name, true)
		if frame and frame:IsA("GuiObject") and frame.Name ~= "OpenAdmin" then
			return frame
		end
	end

	for _, child in root:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "OpenAdmin" and not child:IsA("ScreenGui") then
			return child
		end
	end

	return nil
end

local function setAdminGuiVisible(visible: boolean)
	if not adminGui then
		return
	end

	adminGui.Enabled = visible
	if adminPanel then
		adminPanel.Visible = false
	end
	if announcementsFrame and announcementsFrame ~= adminPanel then
		announcementsFrame.Visible = false
	end
end

local function toggleAdminPanel()
	local panel = adminPanel or announcementsFrame
	if not panel then
		warn("[AdminGuiController] No admin panel frame found in AdminGui")
		return
	end

	panel.Visible = not panel.Visible
end

local function getMessageText(): string
	if not messageBox then
		return ""
	end

	return string.gsub(messageBox.Text or "", "^%s+", ""):gsub("%s+$", "")
end

local function parseNumber(text: string?): number?
	local value = tonumber(text)
	if value == nil or value ~= value then
		return nil
	end
	return value
end

local function wireAdminActions(root: Instance, AdminService: any)
	local function bindAction(buttonNames: { string }, callback: () -> ())
		local button = findButton(root, buttonNames)
		if button then
			connectPressed(button, callback)
		end
	end

	bindAction({ "StartEvent", "StartEventGlobal" }, function()
		local eventIdBox = findTextBox(root:FindFirstChild("Events", true) or root)
		local multiplierBox = root:FindFirstChild("EventMultiplier", true)
		local durationBox = root:FindFirstChild("EventDuration", true)
		local eventId = if eventIdBox then eventIdBox.Text else ""
		local multiplier = if multiplierBox and multiplierBox:IsA("TextBox")
			then parseNumber(multiplierBox.Text)
			else nil
		local duration = if durationBox and durationBox:IsA("TextBox") then parseNumber(durationBox.Text) else nil
		if eventId == "" or not duration then
			return
		end

		AdminService:StartAdminEvent(eventId, multiplier, duration, true):catch(warn)
	end)

	bindAction({ "StartEventServer" }, function()
		local eventsFrame = root:FindFirstChild("Events", true) or root
		local eventIdBox = findTextBox(eventsFrame)
		local multiplierBox = eventsFrame:FindFirstChild("EventMultiplier", true)
		local durationBox = eventsFrame:FindFirstChild("EventDuration", true)
		local eventId = if eventIdBox then eventIdBox.Text else ""
		local multiplier = if multiplierBox and multiplierBox:IsA("TextBox")
			then parseNumber(multiplierBox.Text)
			else nil
		local duration = if durationBox and durationBox:IsA("TextBox") then parseNumber(durationBox.Text) else nil
		if eventId == "" or not duration then
			return
		end

		AdminService:StartAdminEvent(eventId, multiplier, duration, false):catch(warn)
	end)

	bindAction({ "StopEvent", "StopEventGlobal" }, function()
		AdminService:StopAdminEvent(true):catch(warn)
	end)

	bindAction({ "StopEventServer" }, function()
		AdminService:StopAdminEvent(false):catch(warn)
	end)

	bindAction({ "StartBoost", "StartBoostGlobal" }, function()
		local boostsFrame = root:FindFirstChild("Boosts", true) or root
		local boostTypeBox = findTextBox(boostsFrame)
		local multiplierBox = boostsFrame:FindFirstChild("BoostMultiplier", true)
			or root:FindFirstChild("BoostMultiplier", true)
		local durationBox = boostsFrame:FindFirstChild("BoostDuration", true)
			or root:FindFirstChild("BoostDuration", true)
		local boostType = if boostTypeBox then boostTypeBox.Text else ""
		local multiplier = if multiplierBox and multiplierBox:IsA("TextBox")
			then parseNumber(multiplierBox.Text)
			else nil
		local duration = if durationBox and durationBox:IsA("TextBox") then parseNumber(durationBox.Text) else nil
		if boostType == "" or not duration then
			return
		end

		AdminService:StartAdminBoost(boostType, multiplier, duration, true):catch(warn)
	end)

	bindAction({ "StartBoostServer" }, function()
		local boostsFrame = root:FindFirstChild("Boosts", true) or root
		local boostTypeBox = findTextBox(boostsFrame)
		local multiplierBox = boostsFrame:FindFirstChild("BoostMultiplier", true)
		local durationBox = boostsFrame:FindFirstChild("BoostDuration", true)
		local boostType = if boostTypeBox then boostTypeBox.Text else ""
		local multiplier = if multiplierBox and multiplierBox:IsA("TextBox")
			then parseNumber(multiplierBox.Text)
			else nil
		local duration = if durationBox and durationBox:IsA("TextBox") then parseNumber(durationBox.Text) else nil
		if boostType == "" or not duration then
			return
		end

		AdminService:StartAdminBoost(boostType, multiplier, duration, false):catch(warn)
	end)

	bindAction({ "StopBoosts", "StopBoostsGlobal" }, function()
		AdminService:StopAdminBoosts(true):catch(warn)
	end)

	bindAction({ "StopBoostsServer" }, function()
		AdminService:StopAdminBoosts(false):catch(warn)
	end)
end

function AdminGuiController:setupGui()
	disconnectGuiConnections()

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	adminGui = playerGui:FindFirstChild("AdminGui") :: ScreenGui?
	if not adminGui or not adminGui:IsA("ScreenGui") then
		return
	end

	local isAdmin = localPlayer:GetAttribute(CMDR_ADMIN_ATTR) == true
	setAdminGuiVisible(isAdmin)
	if not isAdmin then
		return
	end

	adminPanel = findAdminPanel(adminGui)
	announcementsFrame = adminGui:FindFirstChild("Announcements", true) :: GuiObject?
	messageBox = if announcementsFrame then findTextBox(announcementsFrame) else nil

	if adminPanel then
		adminPanel.Visible = false
	end

	local openButton = adminGui:FindFirstChild("OpenAdmin", true)
	if openButton then
		connectPressed(openButton, toggleAdminPanel)
	end

	local AdminService = Knit.GetService("AdminService")
	wireAdminActions(adminGui, AdminService)

	local serverButton = if announcementsFrame
		then findButton(announcementsFrame, { "Server", "SendServer" })
		else findButton(adminGui, { "Server", "SendServer" })
	local globalButton = if announcementsFrame
		then findButton(announcementsFrame, { "Global", "SendGlobal" })
		else findButton(adminGui, { "Global", "SendGlobal" })

	local function sendServer()
		local message = getMessageText()
		if message == "" then
			return
		end

		AdminService:SendServerAnnouncement(message):andThen(function(success: boolean, err: string?)
			if success and messageBox then
				messageBox.Text = ""
			elseif err then
				warn("[AdminGuiController] Server announce failed:", err)
			end
		end)
	end

	local function sendGlobal()
		local message = getMessageText()
		if message == "" then
			return
		end

		AdminService:SendGlobalAnnouncement(message):andThen(function(success: boolean, err: string?)
			if success and messageBox then
				messageBox.Text = ""
			elseif err then
				warn("[AdminGuiController] Global announce failed:", err)
			end
		end)
	end

	if serverButton then
		connectPressed(serverButton, sendServer)
	end
	if globalButton then
		connectPressed(globalButton, sendGlobal)
	end

	localPlayer:GetAttributeChangedSignal(CMDR_ADMIN_ATTR):Connect(function()
		local nowAdmin = localPlayer:GetAttribute(CMDR_ADMIN_ATTR) == true
		setAdminGuiVisible(nowAdmin)
		if nowAdmin then
			self:setupGui()
		else
			disconnectGuiConnections()
		end
	end)
end

function AdminGuiController:KnitStart()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "AdminGui" then
			task.defer(function()
				self:setupGui()
			end)
		end
	end)

	task.defer(function()
		self:setupGui()
	end)
end

return AdminGuiController
