local QuestConfig = {}

QuestConfig.QuestCount = 3

QuestConfig.Categories = { "Hourly", "Daily", "Weekly" }

QuestConfig.Reset = {
	DailyHour = 5,
	WeeklyDay = 7,
}

QuestConfig.TypeLabels = {
	BuyUnits = "Buy %s Units",
	EarnYen = "Earn %s Yen",
	CollectMana = "Collect %s Mana",
	Playtime = "Play for %s",
	ReachTier = "Reach Tier %s",
}

QuestConfig.PotionTypes = { "Yen", "Mana", "Deposit" }

QuestConfig.PotionAmounts = {
	Hourly = 1,
	Daily = 5,
	Weekly = 10,
}

-- One quest reward per category is guaranteed to be a potion; remaining rewards roll normally.
QuestConfig.GuaranteedPotionRewardsPerPeriod = 1

-- Biases reward rolls per category (multiplied with each quest entry's rewardWeights).
QuestConfig.CategoryRewardWeights = {
	Hourly = { Yen = 5, Potion = 5, UnitTier = 5 },
	Daily = { Yen = 10, Potion = 10, UnitTier = 5 },
	Weekly = { Yen = 9, Potion = 9, UnitTier = 5 },
}

QuestConfig.UnitTierOffsets = {
	Hourly = -2,
	Daily = -1,
	Weekly = 0,
}

QuestConfig.UnitMinTier = {
	Hourly = 3,
	Daily = 3,
	Weekly = 4,
}

QuestConfig.Scaling = {
	-- Requirement difficulty (locked at quest roll / reset).
	CategoryDifficulty = {
		Hourly = 3,
		Daily = 5,
		Weekly = 20,
	},
	-- Reward difficulty (recomputed live with current units).
	RewardDifficulty = {
		Hourly = 3,
		Daily = 5,
		Weekly = 20,
	},

	-- Matches server drop cadence (TycoonService DROP_INTERVAL).
	DropIntervalSeconds = 60,

	-- Active farming time used for mana/yen quest targets (offline-style income estimate).
	IncomeSeconds = {
		Hourly = { Min = 600, Max = 900 },
		Daily = 10800,
		Weekly = 43200,
	},
	IncomeEfficiency = {
		Hourly = 0.5,
		Daily = 0.4,
		Weekly = 0.35,
	},

	PlaytimeSeconds = {
		HourlyMin = 5 * 60,
		HourlyMax = 20 * 60,
		DailyMin = 45 * 60,
		DailyMax = 6 * 60 * 60,
		WeeklyMin = 4 * 60 * 60,
		WeeklyMax = 16 * 60 * 60,
	},

	BuyUnitsMinimum = {
		Hourly = 750,
		Daily = 25000,
		Weekly = 175000,
	},
	BuyUnitsTierStep = 0.04,
	BuyUnitsUnitStrength = 0.06,

	EarnYenMinimum = {
		Hourly = 100,
		Daily = 5000,
		Weekly = 50000,
	},
	CollectManaMinimum = {
		Hourly = 100,
		Daily = 5000,
		Weekly = 50000,
	},

	-- Yen rewards: live income at visual drop cadence (6s), offline-style seconds × multiplier.
	YenReward = {
		DropIntervalSeconds = 6,
		Seconds = {
			Hourly = 300,
			Daily = 1200,
			Weekly = 5400,
		},
		Multiplier = 0.16,
		GroupRewardCap = 0.5,
		Minimum = {
			Hourly = 100,
			Daily = 1000,
			Weekly = 10000,
		},
	},

	ReachTierOffset = {
		Hourly = 1,
		Daily = 2,
		Weekly = 5,
	},
	ReachTierMaxOffsetHighestTier = 20,
}

QuestConfig.Pool = {
	{
		id = "buy_units",
		type = "BuyUnits",
		weight = 12,
		rewardWeights = { Yen = 5, Potion = 4, UnitTier = 2 },
	},
	{
		id = "earn_yen",
		type = "EarnYen",
		weight = 12,
		rewardWeights = { Yen = 7, Potion = 4 },
	},
	{
		id = "collect_mana",
		type = "CollectMana",
		weight = 10,
		rewardWeights = { Yen = 4, Potion = 6 },
	},
	{
		id = "playtime",
		type = "Playtime",
		weight = 10,
		rewardWeights = { Yen = 3, Potion = 7 },
	},
	{
		id = "reach_tier",
		type = "ReachTier",
		weight = 8,
		rewardWeights = { Yen = 4, UnitTier = 5 },
	},
}

return QuestConfig
