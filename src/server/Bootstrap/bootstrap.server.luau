local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameShutdown = require(script.Parent.Parent.Modules.GameShutdown)
local Knit = require(ReplicatedStorage.Packages.knit)

GameShutdown.init()

Knit.AddServicesDeep(script.Parent.Parent)

Knit.Start():catch(function(err)
	warn("Server bootstrap failed:", err)
end)
