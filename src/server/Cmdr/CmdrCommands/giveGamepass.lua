return {
	Name = "giveGamepass",
	Aliases = { "givegamepass", "grantgamepass" },
	Description = "Grant a gamepass entitlement to a player.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "gamePassKey", Name = "gamePassKey", Description = "Gamepass key from Monetization config" },
	},
}
