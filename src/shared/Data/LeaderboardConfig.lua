local LeaderboardConfig = {}

LeaderboardConfig.UpdateInterval = 300
LeaderboardConfig.InitialUpdateDelay = 20
LeaderboardConfig.PublishPlayerDelay = 2
LeaderboardConfig.PublishDebounceSeconds = 90
LeaderboardConfig.MinPublishIntervalSeconds = 180
LeaderboardConfig.WriteBudgetWaitTimeout = 25
LeaderboardConfig.WriteSpacing = 0.6
LeaderboardConfig.LowBudgetWarnCooldown = 300
LeaderboardConfig.TopTierRigRefreshInterval = 15
LeaderboardConfig.MaxEntries = 100
LeaderboardConfig.DataStorePrefix = "CFB_GlobalLeaderboard_v3_"
LeaderboardConfig.LegacyTieBreakModulus = 1_000_000
-- Values above these are auto-reset to 0 on the leaderboard (not removed/hidden).
LeaderboardConfig.SanityMax = {
	Rebirths = 50,
	PlaytimeSeconds = 10 * 365 * 24 * 60 * 60,
}
LeaderboardConfig.ReadRetryCount = 3
LeaderboardConfig.ReadRetryDelaySeconds = 2
LeaderboardConfig.DisplayReadSpacing = 0.6
LeaderboardConfig.DisplayEnrichMaxEntries = 25

LeaderboardConfig.Boards = {
	Rebirth = {
		DataStoreName = "Rebirth",
		DataPath = "Rebirths",
		AmountSuffix = "Rebirths",
	},
	Yen = {
		DataStoreName = "Yen_v2",
		DataPath = "LifetimeYen",
		AmountSuffix = "Yen",
		SortMode = "Logarithmic",
	},
	Units = {
		DataStoreName = "Units",
		DataPath = "TotalUnitsBought",
		AmountSuffix = "Units",
		SortMode = "Logarithmic",
	},
	Playtime = {
		DataStoreName = "Playtime",
		DataPath = "PlaytimeSeconds",
		AmountSuffix = "Playtime",
	},
}

return LeaderboardConfig
