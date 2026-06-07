return {
	Name = "setRebirths",
	Aliases = { "rebirths", "removerebirth" },
	Description = "Set a player's rebirth count (use 0 to remove rebirths).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "integer", Name = "amount", Description = "Rebirth count" },
	},
}
