return {
	Name = "resetDeposit",
	Aliases = { "resetdeposit", "resetrate", "clearmana" },
	Description = "Reset a player's deposit mana, bag mana, rate, and rate upgrade level.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
	},
}
