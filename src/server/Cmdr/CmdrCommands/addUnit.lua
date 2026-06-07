return {
	Name = "addUnit",
	Aliases = { "addunit" },
	Description = "Add units of a specific tier to a player.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "integer", Name = "tier", Description = "Unit tier" },
		{ Type = "integer", Name = "amount", Description = "How many units to add" },
	},
}
