--[[
	Cmdr client: only enabled for players with server-set BananaBombCmdrAdmin attribute.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CMDR_ADMIN_ATTR = "BananaBombCmdrAdmin"
local localPlayer = Players.LocalPlayer

local function applyCmdrEnabled(interface: any, enabled: boolean)
	if interface.SetEnabled then
		interface:SetEnabled(enabled)
	end
	if enabled and interface.SetActivationKeys then
		interface:SetActivationKeys({ Enum.KeyCode.F2 })
	end
end

local function tryRegisterClientCommands(cmdrClientFolder: Instance, interface: any)
	local commands = cmdrClientFolder:FindFirstChild("Commands")
	if not commands or typeof(interface.RegisterCommandsIn) ~= "function" then
		return
	end
	pcall(function()
		interface:RegisterCommandsIn(commands)
	end)
end

local function bindCmdrInterface(interface: any, cmdrClientFolder: Instance)
	tryRegisterClientCommands(cmdrClientFolder, interface)

	applyCmdrEnabled(interface, localPlayer:GetAttribute(CMDR_ADMIN_ATTR) == true)

	localPlayer:GetAttributeChangedSignal(CMDR_ADMIN_ATTR):Connect(function()
		applyCmdrEnabled(interface, localPlayer:GetAttribute(CMDR_ADMIN_ATTR) == true)
	end)

	if interface.HandleEvent then
		interface:HandleEvent("Message", function(_text, _player) end)
		interface:HandleEvent("Notification", function(_message, _type) end)
	end
end

local cmdrClientFolder = ReplicatedStorage:WaitForChild("CmdrClient", 30)
if not cmdrClientFolder then
	warn("[CmdrClient] CmdrClient not found in ReplicatedStorage — is the server Cmdr package loaded?")
	return
end

local success, interface = pcall(require, cmdrClientFolder)
if success and interface then
	bindCmdrInterface(interface, cmdrClientFolder)
else
	warn("[CmdrClient] Failed to require CmdrClient:", interface)
end
