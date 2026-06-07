return {
	Name = "sellAll",
	Aliases = { "sellall", "sellprocessor" },
	Description = "Sell all processor mana for a player (same as SellAll dev product).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
	},
}
