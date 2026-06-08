return {
	Name = "clearLeaderboard",
	Aliases = { "clearleaderboard", "lbremove" },
	Description = "Remove a user from the leaderboard DataStore by UserId without changing their saved progress.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "userId", Description = "Roblox UserId" },
		{ Type = "leaderboardBoard", Name = "board", Description = "Board name or all" },
	},
}
