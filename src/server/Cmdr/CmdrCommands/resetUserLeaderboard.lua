return {
	Name = "resetUserLeaderboard",
	Aliases = { "resetuserleaderboard", "resetuserlb", "resetlb", "resetleaderboard" },
	Description = "Reset a user's leaderboard stats to 0 by UserId and republish them on all boards (not hidden). Works offline.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "userId", Description = "Roblox UserId" },
	},
}
