return {
	Name = "stopAdminEvent",
	Aliases = { "stopadminevent", "stopevent" },
	Description = "Stop the active admin event (all servers by default).",
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
