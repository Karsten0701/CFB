local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ChatTips = require(ReplicatedStorage.Shared.Data.ChatTips)
local GameShutdown = require(script.Parent.Parent.Modules.GameShutdown)
local Knit = require(ReplicatedStorage.Packages.knit)

local ChatTipsService = Knit.CreateService({
	Name = "ChatTipsService",
	Client = {
		TipReceived = Knit.CreateSignal(),
	},
})

local function ensureDefaultTextChannels()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end

	pcall(function()
		if TextChatService.CreateDefaultTextChannels ~= true then
			TextChatService.CreateDefaultTextChannels = true
		end
	end)
end

function ChatTipsService:broadcastTip(message: string): boolean
	if GameShutdown.isShuttingDown() or type(message) ~= "string" or message == "" then
		return false
	end

	self.Client.TipReceived:FireAll(message)
	return true
end

function ChatTipsService:KnitInit()
	ensureDefaultTextChannels()
end

function ChatTipsService:KnitStart()
	local tips = ChatTips.Tips
	if type(tips) ~= "table" or #tips <= 0 then
		warn("[ChatTipsService] No chat tips configured.")
		return
	end

	local interval = math.max(tonumber(ChatTips.IntervalSeconds) or 180, 30)
	local initialDelay = math.max(tonumber(ChatTips.InitialDelaySeconds) or 60, 0)
	local tipIndex = 1

	task.spawn(function()
		if initialDelay > 0 then
			task.wait(initialDelay)
		end

		while not GameShutdown.isShuttingDown() do
			local tip = tips[tipIndex]
			if type(tip) == "string" and tip ~= "" then
				self:broadcastTip(tip)
			end

			tipIndex += 1
			if tipIndex > #tips then
				tipIndex = 1
			end

			task.wait(interval)
		end
	end)
end

return ChatTipsService
