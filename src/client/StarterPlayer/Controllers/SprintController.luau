local _Players = game:GetService("Players")
local player = _Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local _Janitor = require(ReplicatedStorage.Packages.janitor)
local Knit = require(ReplicatedStorage.Packages.knit)

local SprintController = Knit.CreateController({
	Name = "SprintController",
})

local sprinting = false
local NormalWalkSpeed = 16
local SprintWalkSpeed = 24

function SprintController:KnitStart()
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprinting = true
			local Humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			Humanoid.WalkSpeed = SprintWalkSpeed
		end
	end)
	UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprinting = false
			local Humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			Humanoid.WalkSpeed = NormalWalkSpeed
		end
	end)
end

function SprintController:IsSprinting()
	return sprinting
end

function SprintController:SetSprinting(sprinting: boolean)
	sprinting = sprinting
end

function SprintController:GetSprinting()
	return sprinting
end

return SprintController
