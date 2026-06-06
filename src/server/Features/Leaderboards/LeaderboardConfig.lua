local LeaderboardConfig = {}

LeaderboardConfig.UpdateInterval = 120
LeaderboardConfig.TopTierRigRefreshInterval = 15
LeaderboardConfig.MaxEntries = 100
LeaderboardConfig.DataStorePrefix = "CFB_GlobalLeaderboard_v1_"

LeaderboardConfig.Boards = {
	Rebirth = {
		DataStoreName = "Rebirth",
		DataPath = "Rebirths",
		AmountSuffix = "Rebirths",
	},
	Yen = {
		DataStoreName = "Yen",
		DataPath = "LifetimeYen",
		AmountSuffix = "Yen",
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
