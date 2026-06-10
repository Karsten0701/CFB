local AdminConfig = require(script.Parent.AdminConfig)

local PotionConfig = {}

PotionConfig.DurationSeconds = 15 * 60
PotionConfig.DefaultMultiplier = 2

PotionConfig.Types = {
	Yen = {
		EffectKey = "YenMultiplier",
		Name = "2x Yen",
		Description = "Earn 2x Yen while this potion is active.",
		Icon = AdminConfig.BoostTypes.Yen.Icon,
		Multiplier = 2,
	},
	Mana = {
		EffectKey = "ManaMultiplier",
		Name = "2x Mana",
		Description = "Earn 2x Mana while this potion is active.",
		Icon = AdminConfig.BoostTypes.Mana.Icon,
		Multiplier = 2,
	},
	Deposit = {
		EffectKey = "ProcessSpeedMultiplier",
		Name = "2x Deposit",
		Description = "Deposit Mana 2x faster while this potion is active.",
		Icon = AdminConfig.BoostTypes.Process.Icon,
		Multiplier = 2,
	},
}

PotionConfig.ProductKeyByType = {
	Yen = "PotionYen",
	Mana = "PotionMana",
	Deposit = "PotionDeposit",
}

PotionConfig.TypeByProductKind = {
	PotionYen = "Yen",
	PotionMana = "Mana",
	PotionDeposit = "Deposit",
}

function PotionConfig.getTypeConfig(potionType: string)
	return PotionConfig.Types[potionType]
end

function PotionConfig.getTypeFromProductKind(kind: string): string?
	return PotionConfig.TypeByProductKind[kind]
end

return PotionConfig
