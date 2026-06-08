return {
	Name = "resetData",
	Aliases = { "resetdata", "wipedata", "fullreset" },
	Description = "Fully reset a player's saved data to defaults. Online players are kicked to rejoin.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
	},
}
