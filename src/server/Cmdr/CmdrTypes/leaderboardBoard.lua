local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardConfig = require(ReplicatedStorage.Shared.Data.LeaderboardConfig)
local TypeUtil = require(ReplicatedStorage.Shared.Features.Cmdr.TypeUtil)

local boards: { string } = { "all" }
for boardName in LeaderboardConfig.Boards do
	table.insert(boards, boardName)
end
table.sort(boards)

return function(registry)
	registry:RegisterType("leaderboardBoard", {
		Transform = function(text)
			return text
		end,
		Validate = function(value)
			return value == "all" or LeaderboardConfig.Boards[value] ~= nil
		end,
		Autocomplete = function(text)
			return TypeUtil.filterAutocomplete(boards, text)
		end,
		Parse = function(value)
			return value
		end,
	})
end
