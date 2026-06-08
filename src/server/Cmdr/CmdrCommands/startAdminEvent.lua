return {
	Name = "startAdminEvent",
	Aliases = { "startadminevent", "startevent" },
	Description = "Start a global admin event from Events.lua (all servers by default).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "adminEventId", Name = "eventId", Description = "Event id from Events.lua" },
		{
			Type = "number",
			Name = "multiplier",
			Description = "Effect strength (e.g. 2 for 2x drop speed). Use 0 for event default.",
		},
		{ Type = "number", Name = "durationMinutes", Description = "Duration in minutes" },
		{
			Type = "adminScope",
			Name = "scope",
			Description = "global or server",
			Optional = true,
			Default = "global",
		},
	},
}
