return {
	Name = "resetDataUser",
	Aliases = { "resetdatauser", "wipedatauser", "fullresetuser" },
	Description = "Fully reset a user's saved data by UserId (works offline). Online players are kicked to rejoin.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "userId", Description = "Roblox UserId" },
	},
}
