return {
	Name = "spawnMutationBalls",
	Aliases = { "spawnmutationballs", "mutationballs", "spawnballs" },
	Description = "Spawn gold mutation balls for everyone (all servers by default).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "integer", Name = "count", Description = "How many balls to spawn per player" },
		{
			Type = "adminScope",
			Name = "scope",
			Description = "global or server",
			Optional = true,
			Default = "global",
		},
	},
}
