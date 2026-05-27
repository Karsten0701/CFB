local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.knit)

Knit.AddControllersDeep(script.Parent.Parent.StarterPlayer)

Knit.Start():catch(function(err)
	warn("Client bootstrap failed:", err)
end)
