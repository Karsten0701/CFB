return {
	Name = "givePotion",
	Aliases = { "givepotion", "grantpotion", "addpotion" },
	Description = "Give inventory potions to a player (Yen, Mana, Deposit, or Bundle for all types).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "potionType", Name = "potionType", Description = "Yen, Mana, Deposit, or Bundle" },
		{
			Type = "integer",
			Name = "amount",
			Description = "Amount to grant (Bundle = amount per type)",
			Default = 1,
		},
	},
}
