return {
	Name = "addLeaderboard",
	Aliases = { "addleaderboard", "restoreleaderboard", "unbanlb" },
	Description = "Allow a user to show on leaderboards again after clearLeaderboard (by UserId).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "userId", Description = "Roblox UserId" },
	},
}
