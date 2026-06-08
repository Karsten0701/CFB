local TypeUtil = require(game:GetService("ReplicatedStorage").Shared.Features.Cmdr.TypeUtil)

local scopes = { "global", "server" }

return function(registry)
	registry:RegisterType("adminScope", {
		Transform = function(text)
			return string.lower(text)
		end,
		Validate = function(value)
			return value == "global" or value == "server"
		end,
		Autocomplete = function(text)
			return TypeUtil.filterAutocomplete(scopes, text)
		end,
		Parse = function(value)
			return value
		end,
	})
end
