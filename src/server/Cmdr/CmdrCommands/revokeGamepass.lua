return {
	Name = "revokeGamepass",
	Aliases = { "revokegamepass" },
	Description = "Revoke an admin-granted gamepass entitlement from a player.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "gamePassKey", Name = "gamePassKey", Description = "Gamepass key from Monetization config" },
	},
}
