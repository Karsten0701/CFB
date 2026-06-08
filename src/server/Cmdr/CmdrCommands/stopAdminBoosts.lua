return {
	Name = "stopAdminBoosts",
	Aliases = { "stopadminboosts", "stopboosts" },
	Description = "Stop all active admin boosts.",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "adminScope",
			Name = "scope",
			Description = "global or server",
			Optional = true,
			Default = "global",
		},
	},
}
