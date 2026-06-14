return {
	Name = "usePotion",
	Aliases = { "usepotion", "activatepotion", "spawnpotion" },
	Description = "Activate a potion boost for a player without consuming inventory.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "potionType", Name = "potionType", Description = "Yen, Mana, or Deposit" },
		{
			Type = "integer",
			Name = "durationMinutes",
			Description = "Boost duration in minutes (0 = default 15 min)",
			Default = 0,
		},
	},
}
