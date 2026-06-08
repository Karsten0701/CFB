local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AdminMessageFormat = require(ReplicatedStorage.Shared.Features.Admin.AdminMessageFormat)

local AdminMessagesFeature = {}

local activeAdminBanners = {}
local nextAdminBannerLayoutOrder = 0
local ADMIN_MESSAGE_LIFETIME = 4
local ADMIN_EVENT_LIFETIME = 6

local function isTextGui(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton")
end

local function setRichText(instance: Instance, enabled: boolean)
	if isTextGui(instance) then
		instance.RichText = enabled
	end

	for _, descendant in instance:GetDescendants() do
		if isTextGui(descendant) then
			descendant.RichText = enabled
		end
	end
end

local function setBannerText(root: Instance, text: string)
	local messageLabel = root:FindFirstChild("Message", true)
	if messageLabel and isTextGui(messageLabel) then
		messageLabel.RichText = true
		messageLabel.Text = text
		return
	end

	for _, descendant in root:GetDescendants() do
		if isTextGui(descendant) then
			descendant.RichText = true
			descendant.Text = text
			return
		end
	end
end

local function setBannerIcon(root: Instance, image: string?)
	if image == nil or image == "" then
		return
	end

	local icon = root:FindFirstChild("icon", true)
	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		icon.Image = image
	end
end

local function setBannerTransparency(instance: Instance, transparency: number)
	for _, descendant in instance:GetDescendants() do
		if isTextGui(descendant) then
			descendant.TextTransparency = transparency
			descendant.TextStrokeTransparency = math.clamp(transparency, 0, 1)
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			descendant.ImageTransparency = transparency
		elseif descendant:IsA("UIStroke") then
			descendant.Transparency = transparency
		end
	end

	if isTextGui(instance) then
		instance.TextTransparency = transparency
		instance.TextStrokeTransparency = math.clamp(transparency, 0, 1)
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		instance.ImageTransparency = transparency
	end
end

function AdminMessagesFeature.Install(MainGuiController)
	function MainGuiController:getAdminMessageHolder(): Instance?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		return mainGui:FindFirstChild("AdminMessageHolder", true)
	end

	function MainGuiController:getAdminBannerTemplate(templateKind: string): GuiObject?
		local holder = self:getAdminMessageHolder()
		if not holder then
			return nil
		end

		local templateName = if templateKind == "event" then "EventTemplate" else "Template"
		local template = holder:FindFirstChild(templateName)
		if template and template:IsA("GuiObject") then
			template.Visible = false
			return template
		end

		return nil
	end

	function MainGuiController:pulseAdminBanner(messageGui: GuiObject)
		local scale = messageGui:FindFirstChild("AdminBannerScale")
		if not scale or not scale:IsA("UIScale") then
			scale = Instance.new("UIScale")
			scale.Name = "AdminBannerScale"
			scale.Parent = messageGui
		end

		scale.Scale = 1.08
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	function MainGuiController:fadeOutAdminBanner(key: string, token: number)
		local entry = activeAdminBanners[key]
		if not entry or entry.Token ~= token then
			return
		end

		local messageGui = entry.Gui
		activeAdminBanners[key] = nil
		if not messageGui or not messageGui.Parent then
			return
		end

		local fadeProgress = Instance.new("NumberValue")
		fadeProgress.Value = 0
		local connection = fadeProgress.Changed:Connect(function(value)
			setBannerTransparency(messageGui, value)
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

	function MainGuiController:showAdminBanner(
		key: string,
		templateKind: string,
		richText: string,
		iconImage: string?,
		lifetime: number?
	)
		local existing = activeAdminBanners[key]
		if existing and existing.Gui and existing.Gui.Parent then
			existing.Token += 1
			setBannerText(existing.Gui, richText)
			if iconImage then
				setBannerIcon(existing.Gui, iconImage)
			end
			self:pulseAdminBanner(existing.Gui)

			local token = existing.Token
			task.delay(lifetime or ADMIN_MESSAGE_LIFETIME, function()
				self:fadeOutAdminBanner(key, token)
			end)
			return
		end

		local template = self:getAdminBannerTemplate(templateKind)
		local holder = self:getAdminMessageHolder()
		if not template or not holder then
			return
		end

		nextAdminBannerLayoutOrder -= 1
		local messageGui = template:Clone()
		messageGui.Name = "AdminBanner"
		messageGui.Visible = true
		messageGui.LayoutOrder = nextAdminBannerLayoutOrder
		setRichText(messageGui, true)
		setBannerText(messageGui, richText)
		setBannerIcon(messageGui, iconImage)
		setBannerTransparency(messageGui, 1)

		local scale = Instance.new("UIScale")
		scale.Name = "AdminBannerScale"
		scale.Scale = 0.82
		scale.Parent = messageGui

		messageGui.Parent = holder
		activeAdminBanners[key] = {
			Gui = messageGui,
			Token = 1,
		}

		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()

		local fadeProgress = Instance.new("NumberValue")
		fadeProgress.Value = 1
		local connection = fadeProgress.Changed:Connect(function(value)
			setBannerTransparency(messageGui, value)
		end)

		TweenService:Create(fadeProgress, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Value = 0,
		}):Play()

		task.delay(0.2, function()
			connection:Disconnect()
			fadeProgress:Destroy()
		end)

		local token = activeAdminBanners[key].Token
		task.delay(lifetime or ADMIN_MESSAGE_LIFETIME, function()
			self:fadeOutAdminBanner(key, token)
		end)
	end

	function MainGuiController:ShowAdminBanner(kind: string, senderName: string, data: any)
		senderName = tostring(senderName or "Admin")
		data = if type(data) == "table" then data else {}

		local richText = ""
		local templateKind = "message"
		local iconImage: string? = nil
		local key = kind .. ":" .. senderName
		local lifetime = ADMIN_MESSAGE_LIFETIME

		if kind == "admin_message" then
			local message = tostring(data.message or "")
			if message == "" then
				return
			end
			richText = AdminMessageFormat.formatAdminMessage(senderName, message)
			key = `AdminMsg:{senderName}:{message}`
		elseif kind == "event_started" then
			local adminEvent = data.adminEvent
			if type(adminEvent) ~= "table" then
				return
			end
			richText = AdminMessageFormat.formatEventStarted(senderName, adminEvent)
			templateKind = "event"
			iconImage = adminEvent.Icon
			key = `EventStart:{adminEvent.Id}`
			lifetime = ADMIN_EVENT_LIFETIME
		elseif kind == "boost_started" then
			local boost = data.boost
			if type(boost) ~= "table" then
				return
			end
			richText = AdminMessageFormat.formatBoostStarted(senderName, boost)
			templateKind = "event"
			key = `BoostStart:{boost.Id}`
			lifetime = ADMIN_EVENT_LIFETIME
		elseif kind == "system" then
			local message = tostring(data.message or "")
			if message == "" then
				return
			end
			richText = AdminMessageFormat.formatSystemMessage(senderName, message)
			key = `System:{senderName}:{message}`
		else
			return
		end

		self:showAdminBanner(key, templateKind, richText, iconImage, lifetime)
	end

	function MainGuiController:ShowAnnouncementMessage(senderName: string, message: string)
		self:ShowAdminBanner("admin_message", senderName, { message = message })
	end
end

return AdminMessagesFeature
