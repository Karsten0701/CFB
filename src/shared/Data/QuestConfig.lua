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
	Daily = 2,
	Weekly = 4,
}

QuestConfig.UnitTierOffsets = {
	Hourly = -2,
	Daily = -1,
	Weekly = 1,
}

QuestConfig.UnitMinTier = {
	Hourly = 3,
	Daily = 3,
	Weekly = 4,
}

QuestConfig.Scaling = {
	-- Progression multipliers applied on top of category bases (tier + owned units).
	TierMultiplierPerStep = 0.12,
	UnitScaleStrength = 0.22,

	PlaytimeSeconds = {
		HourlyMin = 600, -- 10 min
		HourlyMax = 900, -- 15 min
		Daily = 10800, -- 3h
		Weekly = 43200, -- 12h
	},

	BuyUnitsMinimum = {
		Hourly = 750,
		Daily = 25000,
		Weekly = 175000,
	},

	EarnYenTierPercent = {
		Hourly = 0.06,
		Daily = 0.28,
		Weekly = 1.10,
	},
	EarnYenMinimum = {
		Hourly = 500,
		Daily = 50000,
		Weekly = 500000,
	},

	CollectManaTierPercent = {
		Hourly = 0.04,
		Daily = 0.18,
		Weekly = 0.85,
	},
	CollectManaMinimum = {
		Hourly = 500,
		Daily = 100000,
		Weekly = 800000,
	},

	EarnYenReward = {
		Hourly = 0.10,
		Daily = 0.38,
		Weekly = 1.40,
	},

	ReachTierOffset = {
		Hourly = 0,
		Daily = 1,
		Weekly = 5,
	},
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
