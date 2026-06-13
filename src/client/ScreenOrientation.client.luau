local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Forceren naar Landscape bij start
playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

-- Check of speler in verkeerde oriëntatie zit
local function checkOrientation()
	local current = playerGui.CurrentScreenOrientation
end

-- Eerste check
checkOrientation()

-- Hercheck telkens wanneer de oriëntatie verandert
playerGui:GetPropertyChangedSignal("CurrentScreenOrientation"):Connect(checkOrientation)
