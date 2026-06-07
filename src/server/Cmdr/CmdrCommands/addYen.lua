return {
	Name = "addYen",
	Aliases = { "addyen" },
	Description = "Add Yen to a player.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "integer", Name = "amount", Description = "Yen to add" },
	},
}
