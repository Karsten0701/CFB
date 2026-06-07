return {
	Name = "removeUnit",
	Aliases = { "removeunit" },
	Description = "Remove units of a specific tier from a player.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "integer", Name = "tier", Description = "Unit tier" },
		{ Type = "integer", Name = "amount", Description = "How many units to remove" },
	},
}
