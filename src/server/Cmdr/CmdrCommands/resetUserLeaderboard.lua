return {
	Name = "resetUserLeaderboard",
	Aliases = { "resetuserleaderboard", "resetuserlb", "resetlb" },
	Description = "Reset a user's leaderboard stats by UserId, apply a rebirth-style progress reset, and remove them from all boards (works offline).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "userId", Description = "Roblox UserId" },
	},
}
