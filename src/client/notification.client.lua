-- StarterPlayerScripts/EventFollowPrompt.client.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local remote = ReplicatedStorage:WaitForChild("EventFollowPrompt")

remote.OnClientEvent:Connect(function(eventId)
	local success, result = pcall(function()
		return SocialService:PromptRsvpToEventAsync(tostring(eventId))
	end)

	if not success then
		warn("Event RSVP prompt failed:", result)
	else
		print("RSVP status:", result)
	end
end)
