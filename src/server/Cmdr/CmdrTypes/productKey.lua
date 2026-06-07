local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local TypeUtil = require(ReplicatedStorage.Shared.Features.Cmdr.TypeUtil)

local keys: { string } = {}
for key in Monetization.DeveloperProducts do
	table.insert(keys, key)
end
table.sort(keys)

return function(registry)
	registry:RegisterType("productKey", {
		Transform = function(text)
			return text
		end,
		Validate = function(value)
			return Monetization.DeveloperProducts[value] ~= nil
		end,
		Autocomplete = function(text)
			return TypeUtil.filterAutocomplete(keys, text)
		end,
		Parse = function(value)
			return value
		end,
	})
end
