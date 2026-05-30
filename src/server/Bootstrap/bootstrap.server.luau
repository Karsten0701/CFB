local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.knit)

Knit.AddServicesDeep(script.Parent.Parent)

Knit.Start():catch(function(err)
	warn("Server bootstrap failed:", err)
end)
