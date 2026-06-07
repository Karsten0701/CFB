return {
	Name = "addRebirthTokens",
	Aliases = { "addrebirthtokens" },
	Description = "Add rebirth tokens to a player.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "integer", Name = "amount", Description = "Tokens to add" },
	},
}
