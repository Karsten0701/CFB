local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TypeUtil = require(ReplicatedStorage.Shared.Features.Cmdr.TypeUtil)

local potionTypes = { "Yen", "Mana", "Deposit", "Bundle" }

return function(registry)
	registry:RegisterType("potionType", {
		Transform = function(text)
			local lower = string.lower(text or "")
			for _, potionType in potionTypes do
				if string.lower(potionType) == lower then
					return potionType
				end
			end

			return text
		end,
		Validate = function(value)
			for _, potionType in potionTypes do
				if potionType == value then
					return true
				end
			end

			return false
		end,
		Autocomplete = function(text)
			return TypeUtil.filterAutocomplete(potionTypes, text)
		end,
		Parse = function(value)
			return value
		end,
	})
end
