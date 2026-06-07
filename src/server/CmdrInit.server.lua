--[[
	Bootstrap Cmdr after Knit. Package must live at ServerScriptService.cmdr (Studio).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.knit)
local StudioHostAllowlist = require(script.Parent.Modules.Security.StudioHostAllowlist)

local CMDR_ADMIN_ATTR = "BananaBombCmdrAdmin"

local CUSTOM_COMMAND_NAMES = {
	"addYen",
	"removeYen",
	"addUnit",
	"removeUnit",
	"removeAllUnits",
	"setRebirths",
	"addRebirthTokens",
	"setRebirthTokens",
	"setRebirthUpgrade",
	"giveGamepass",
	"revokeGamepass",
	"giveProduct",
	"sellAll",
	"clearLeaderboard",
	"resetUserLeaderboard",
	"viewData",
}

local function syncCmdrAdminAttr(player: Player)
	player:SetAttribute(CMDR_ADMIN_ATTR, StudioHostAllowlist.isAdminPlayer(player))
end

local function requireCmdr(cmdrRoot: Instance): any
	local ok, mod = pcall(require, cmdrRoot)
	if ok then
		return mod
	end
	local cmdrModule = cmdrRoot:FindFirstChild("Cmdr")
	if cmdrModule and cmdrModule:IsA("ModuleScript") then
		return require(cmdrModule)
	end
	local initModule = cmdrRoot:FindFirstChild("Initialize")
	if initModule and initModule:IsA("ModuleScript") then
		return require(initModule)
	end
	error(`[CmdrInit] Could not require Cmdr from {cmdrRoot:GetFullName()}: {mod}`)
end

local function registerCustomCommands(Cmdr: any, commandsFolder: Folder)
	local registry = Cmdr.Registry or Cmdr
	if not registry or typeof(registry.RegisterCommand) ~= "function" then
		warn("[CmdrInit] Cmdr.Registry.RegisterCommand missing — falling back to RegisterCommandsIn.")
		Cmdr:RegisterCommandsIn(commandsFolder)
		return
	end

	for _, name in ipairs(CUSTOM_COMMAND_NAMES) do
		local defScript = commandsFolder:FindFirstChild(name)
		local serverScript = commandsFolder:FindFirstChild(name .. "Server")
		if defScript and defScript:IsA("ModuleScript") and serverScript and serverScript:IsA("ModuleScript") then
			registry:RegisterCommand(defScript, serverScript)
		else
			warn(`[CmdrInit] Missing command pair: {name} + {name}Server`)
		end
	end
end

local function replaceAutoCompleteModule()
	local cmdrClient = ReplicatedStorage:FindFirstChild("CmdrClient")
	local cmdrInterface = cmdrClient and cmdrClient:FindFirstChild("CmdrInterface")
	local existing = cmdrInterface and cmdrInterface:FindFirstChild("AutoComplete")
	local fixed = script.Parent.Cmdr:FindFirstChild("AutoCompleteFixed")
	if not existing or not fixed or not fixed:IsA("ModuleScript") then
		return
	end

	local replacement = fixed:Clone()
	replacement.Name = "AutoComplete"
	replacement.Parent = cmdrInterface
	existing:Destroy()
end

local function initCmdr()
	local cmdrRoot = ServerScriptService:WaitForChild("cmdr", 15)
	if not cmdrRoot then
		warn("[CmdrInit] ServerScriptService.cmdr not found — add the Cmdr package in Studio.")
		return
	end

	local Cmdr = requireCmdr(cmdrRoot)
	local cmdrFolder = script.Parent.Cmdr
	local commandsFolder = cmdrFolder:FindFirstChild("CmdrCommands") :: Folder
	local typesFolder = cmdrFolder:FindFirstChild("CmdrTypes")
	local hooksFolder = cmdrFolder:FindFirstChild("CmdrHooks")

	local typesOk, typesErr = pcall(function()
		if typesFolder then
			Cmdr:RegisterTypesIn(typesFolder)
		end
	end)
	if not typesOk then
		warn("[CmdrInit] RegisterTypesIn failed:", typesErr)
	end

	local hooksOk, hooksErr = pcall(function()
		if hooksFolder then
			Cmdr:RegisterHooksIn(hooksFolder)
		end
	end)
	if not hooksOk then
		warn("[CmdrInit] RegisterHooksIn failed:", hooksErr)
	end

	Cmdr:RegisterDefaultCommands()
	if commandsFolder then
		registerCustomCommands(Cmdr, commandsFolder)
	end

	Players.PlayerAdded:Connect(syncCmdrAdminAttr)
	for _, player in Players:GetPlayers() do
		syncCmdrAdminAttr(player)
	end

	replaceAutoCompleteModule()
end

local function waitForKnitReady()
	while true do
		local ok = pcall(function()
			return Knit.GetService("PlayerDataService")
		end)
		if ok then
			return
		end
		task.wait(0.1)
	end
end

task.defer(function()
	waitForKnitReady()
	local ok, err = pcall(initCmdr)
	if not ok then
		warn("[CmdrInit]", err)
	end
end)
