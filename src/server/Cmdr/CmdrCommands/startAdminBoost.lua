return {
	Name = "startAdminBoost",
	Aliases = { "startadminboost", "startboost" },
	Description = "Start a timed admin boost (Yen, Mana, Process, Drop, SpawnTier, Capsule).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "adminBoostType", Name = "boostType", Description = "Boost type" },
		{ Type = "number", Name = "multiplier", Description = "Multiplier or bonus amount (e.g. 2)" },
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
