local AdminConfig = {}

AdminConfig.MessagingTopic = "CFB_Admin_v1"

AdminConfig.BoostTypes = {
	Yen = {
		EffectKey = "YenMultiplier",
		Label = "Yen",
		DefaultMultiplier = 2,
		Icon = "rbxassetid://96573285096968",
		Description = "Earn more Yen while this boost is active.",
	},
	Mana = {
		EffectKey = "ManaMultiplier",
		Label = "Mana",
		DefaultMultiplier = 2,
		Icon = "rbxassetid://121705665379355",
		Description = "Earn more Mana while this boost is active.",
	},
	Process = {
		EffectKey = "ProcessSpeedMultiplier",
		Label = "Process Speed",
		DefaultMultiplier = 1.5,
		Icon = "rbxassetid://133030186915996",
		Description = "Process Mana faster while this boost is active.",
	},
	Drop = {
		EffectKey = "DropSpeedMultiplier",
		Label = "Drop Speed",
		DefaultMultiplier = 1.5,
		Icon = "rbxassetid://115755999549909",
		Description = "Anime units drop faster while this boost is active.",
	},
	SpawnTier = {
		EffectKey = "UnitSpawnTierBonus",
		Label = "Spawn Tier",
		DefaultMultiplier = 1,
		IsBonus = true,
		Icon = "rbxassetid://133962178231664",
		Description = "Spawn higher tier units while this boost is active.",
	},
	Capsule = {
		EffectKey = "CapsuleSpawnChanceMultiplier",
		Label = "Capsule Spawn",
		DefaultMultiplier = 2,
		Icon = "rbxassetid://126078239150428",
		Description = "Capsules spawn more often while this boost is active.",
	},
}

return AdminConfig
