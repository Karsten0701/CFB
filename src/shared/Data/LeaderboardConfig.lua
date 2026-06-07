local LeaderboardConfig = {}

LeaderboardConfig.UpdateInterval = 300
LeaderboardConfig.InitialUpdateDelay = 60
LeaderboardConfig.PublishPlayerDelay = 2
LeaderboardConfig.PublishDebounceSeconds = 90
LeaderboardConfig.MinPublishIntervalSeconds = 180
LeaderboardConfig.WriteBudgetWaitTimeout = 25
LeaderboardConfig.WriteSpacing = 0.6
LeaderboardConfig.LowBudgetWarnCooldown = 300
LeaderboardConfig.TopTierRigRefreshInterval = 15
LeaderboardConfig.MaxEntries = 100
LeaderboardConfig.DataStorePrefix = "CFB_GlobalLeaderboard_v3_"

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
	},
	Playtime = {
		DataStoreName = "Playtime",
		DataPath = "PlaytimeSeconds",
		AmountSuffix = "Playtime",
	},
}

return LeaderboardConfig
