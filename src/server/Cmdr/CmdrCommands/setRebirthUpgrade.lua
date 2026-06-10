return {
	Name = "setRebirthUpgrade",
	Aliases = { "rebirthupgrade", "setrebirthupgrade" },
	Description = "Set a player's rebirth upgrade level (UnitSpawnTier, MoreMana).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "rebirthUpgradeKey", Name = "upgrade", Description = "Rebirth upgrade key" },
		{ Type = "integer", Name = "level", Description = "Upgrade level (0 = none)" },
	},
}
