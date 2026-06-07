local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TypeUtil = require(ReplicatedStorage.Shared.Features.Cmdr.TypeUtil)

local UPGRADE_KEYS = { "BetterMaxButton", "MoreMana", "UnitSpawnTier" }

return function(registry)
	registry:RegisterType("rebirthUpgradeKey", {
		Transform = function(text)
			return text
		end,
		Validate = function(value)
			for _, key in UPGRADE_KEYS do
				if key == value then
					return true
				end
			end
			return false
		end,
		Autocomplete = function(text)
			return TypeUtil.filterAutocomplete(UPGRADE_KEYS, text)
		end,
		Parse = function(value)
			return value
		end,
	})
end
