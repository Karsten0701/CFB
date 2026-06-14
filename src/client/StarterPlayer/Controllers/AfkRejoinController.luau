local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.knit)

local AfkRejoinController = Knit.CreateController({
	Name = "AfkRejoinController",
})

local localPlayer = Players.LocalPlayer
local REJOIN_PLACE_ID = 140269809669116
local AFK_REJOIN_SECONDS = 17 * 60
local TELEPORT_RETRY_SECONDS = 10

local lastActivityAt = os.clock()
local teleporting = false
local nextTeleportAttemptAt = 0

local function markActivity()
	if teleporting then
		return
	end

	lastActivityAt = os.clock()
end

local function tryTeleport()
	local now = os.clock()
	if now < nextTeleportAttemptAt then
		return
	end

	teleporting = true
	nextTeleportAttemptAt = now + TELEPORT_RETRY_SECONDS

	local ok, err = pcall(function()
		TeleportService:Teleport(REJOIN_PLACE_ID, localPlayer)
	end)

	if not ok then
		warn("[AfkRejoinController] AFK rejoin teleport failed:", err)
		teleporting = false
	end
end

function AfkRejoinController:KnitStart()
	UserInputService.InputBegan:Connect(markActivity)
	UserInputService.InputChanged:Connect(markActivity)
	UserInputService.InputEnded:Connect(markActivity)
	UserInputService.TouchStarted:Connect(markActivity)
	UserInputService.TouchMoved:Connect(markActivity)
	UserInputService.TouchEnded:Connect(markActivity)
	UserInputService.WindowFocused:Connect(markActivity)

	TeleportService.TeleportInitFailed:Connect(function(player, _result, errorMessage)
		if player ~= localPlayer then
			return
		end

		teleporting = false
		markActivity()
		warn("[AfkRejoinController] AFK rejoin teleport init failed:", errorMessage)
	end)

	task.spawn(function()
		while true do
			task.wait(1)

			if RunService:IsStudio() then
				continue
			end

			if os.clock() - lastActivityAt >= AFK_REJOIN_SECONDS then
				tryTeleport()
			end
		end
	end)
end

return AfkRejoinController
