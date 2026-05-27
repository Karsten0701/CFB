local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.knit)

Knit.AddServices(script.Parent.Parent.DataServices)

Knit.Start():catch(function(err)
	warn("Server bootstrap failed:", err)
end)
