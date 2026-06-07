return {
	Name = "removeYen",
	Aliases = { "removeyen" },
	Description = "Remove Yen from a player.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "integer", Name = "amount", Description = "Yen to remove" },
	},
}
