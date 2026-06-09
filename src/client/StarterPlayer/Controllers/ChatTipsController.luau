local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChatTips = require(ReplicatedStorage.Shared.Data.ChatTips)
local Knit = require(ReplicatedStorage.Packages.knit)

local ChatTipsController = Knit.CreateController({
	Name = "ChatTipsController",
})

local generalChannel: TextChannel? = nil

local function isTextChatEnabled(): boolean
	return TextChatService.ChatVersion == Enum.ChatVersion.TextChatService
end

local function resolveGeneralChannel(): TextChannel?
	if generalChannel and generalChannel.Parent then
		return generalChannel
	end

	if not isTextChatEnabled() then
		return nil
	end

	local textChannels = TextChatService:FindFirstChild("TextChannels")
	if not textChannels then
		local ok, result = pcall(function()
			return TextChatService:WaitForChild("TextChannels", 20)
		end)
		if not ok then
			return nil
		end
		textChannels = result
	end

	local channel = textChannels:FindFirstChild("RBXGeneral")
	if not channel then
		local ok, result = pcall(function()
			return textChannels:WaitForChild("RBXGeneral", 20)
		end)
		if ok then
			channel = result
		end
	end

	if channel and channel:IsA("TextChannel") then
		generalChannel = channel
		return channel
	end

	return nil
end

local function displayLegacyTip(message: string)
	local formattedMessage = ChatTips.formatMessage(message)
	local plainText = string.gsub(formattedMessage, "<.->", "")

	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = plainText,
			Color = Color3.fromRGB(255, 217, 102),
			Font = Enum.Font.GothamBold,
			FontSize = Enum.FontSize.Size18,
		})
	end)
end

local function displayTextChatTip(message: string)
	local channel = resolveGeneralChannel()
	if not channel then
		displayLegacyTip(message)
		return
	end

	local formattedMessage = ChatTips.formatMessage(message)
	local ok = pcall(function()
		channel:DisplaySystemMessage(formattedMessage)
	end)
	if not ok then
		displayLegacyTip(message)
	end
end

function ChatTipsController:displayTip(message: string)
	if type(message) ~= "string" or message == "" then
		return
	end

	if isTextChatEnabled() then
		displayTextChatTip(message)
	else
		displayLegacyTip(message)
	end
end

function ChatTipsController:KnitStart()
	local ChatTipsService = Knit.GetService("ChatTipsService")

	ChatTipsService.TipReceived:Connect(function(message: string)
		self:displayTip(message)
	end)

	task.spawn(function()
		resolveGeneralChannel()
	end)
end

return ChatTipsController
