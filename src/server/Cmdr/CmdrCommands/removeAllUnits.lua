return {
	Name = "removeAllUnits",
	Aliases = { "removeallunits", "clearunits" },
	Description = "Reset a player's units to the starter loadout.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
	},
}
