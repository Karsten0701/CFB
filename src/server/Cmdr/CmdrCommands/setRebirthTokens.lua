return {
	Name = "setRebirthTokens",
	Aliases = { "rebirthtokens" },
	Description = "Set a player's rebirth token balance.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "integer", Name = "amount", Description = "Token balance" },
	},
}
