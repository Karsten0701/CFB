return {
	Name = "clearLeaderboard",
	Aliases = { "clearleaderboard", "lbremove" },
	Description = "Remove a user's leaderboard data by UserId.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "userId", Description = "Roblox UserId" },
		{ Type = "leaderboardBoard", Name = "board", Description = "Board name or all" },
	},
}
