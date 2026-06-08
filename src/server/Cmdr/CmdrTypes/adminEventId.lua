local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminRuntime = require(ReplicatedStorage.Shared.Features.Admin.AdminRuntime)
local TypeUtil = require(ReplicatedStorage.Shared.Features.Cmdr.TypeUtil)

local eventIds = AdminRuntime.getEventIds()
table.sort(eventIds)

return function(registry)
	registry:RegisterType("adminEventId", {
		Transform = function(text)
			return text
		end,
		Validate = function(value)
			return AdminRuntime.findEventDefinition(value) ~= nil
		end,
		Autocomplete = function(text)
			return TypeUtil.filterAutocomplete(eventIds, text)
		end,
		Parse = function(value)
			return value
		end,
	})
end
