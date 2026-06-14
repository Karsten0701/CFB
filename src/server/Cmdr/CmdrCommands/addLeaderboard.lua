return {
	Name = "addLeaderboard",
	Aliases = { "addleaderboard", "restoreleaderboard", "unbanlb" },
	Description = "Remove a user from the leaderboard blacklist and allow them to show again (addLeaderboard / unbanlb).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "userId", Description = "Roblox UserId" },
	},
}
