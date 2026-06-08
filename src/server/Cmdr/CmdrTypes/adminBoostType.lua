local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminRuntime = require(ReplicatedStorage.Shared.Features.Admin.AdminRuntime)
local TypeUtil = require(ReplicatedStorage.Shared.Features.Cmdr.TypeUtil)

local boostTypes = AdminRuntime.getBoostTypeKeys()

return function(registry)
	registry:RegisterType("adminBoostType", {
		Transform = function(text)
			return text
		end,
		Validate = function(value)
			return AdminRuntime.getBoostType(value) ~= nil
		end,
		Autocomplete = function(text)
			return TypeUtil.filterAutocomplete(boostTypes, text)
		end,
		Parse = function(value)
			return value
		end,
	})
end
