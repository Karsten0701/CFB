--[[
	Runs on server and client (Cmdr copies hooks to ReplicatedStorage).
	Server verifies StudioHostAllowlist; client only checks the server-set admin attribute.
]]

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DENY_MSG = "You don't have permission to run commands."

return function(registry)
	registry:RegisterHook("BeforeRun", function(context)
		local executor = context.Executor
		if not executor or not executor:IsA("Player") then
			return DENY_MSG
		end

		if RunService:IsServer() then
			local serverRoot = ServerScriptService:FindFirstChild("Server")
			local allowlistModule = serverRoot
				and serverRoot:FindFirstChild("Modules")
				and serverRoot.Modules:FindFirstChild("Security")
				and serverRoot.Modules.Security:FindFirstChild("StudioHostAllowlist")

			if allowlistModule and allowlistModule:IsA("ModuleScript") then
				local StudioHostAllowlist = require(allowlistModule)
				if not StudioHostAllowlist.isAdminPlayer(executor) then
					return DENY_MSG
				end
				return nil
			end
		end

		if executor:GetAttribute("BananaBombCmdrAdmin") ~= true then
			return DENY_MSG
		end
	end)
end
