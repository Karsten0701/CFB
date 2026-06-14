return {
	Name = "clearLeaderboard",
	Aliases = { "clearleaderboard", "lbremove" },
	Description = "Remove a user from leaderboards and add them to the persistent blacklist (saved across servers).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "userId", Description = "Roblox UserId" },
		{ Type = "leaderboardBoard", Name = "board", Description = "Board name or all" },
	},
}
