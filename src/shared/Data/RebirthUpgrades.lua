local RebirthUpgrades = {}

RebirthUpgrades.UnitSpawnTier = {
	MaxLevel = 4,
	Costs = { 1, 3, 6, 10 },
}

RebirthUpgrades.MoreMana = {
	MaxLevel = 5,
	MultiplierPerLevel = 0.2,
	Costs = { 2, 4, 8, 16, 32 },
}

function RebirthUpgrades.getUnitSpawnTier(level: number): number
	return math.clamp(math.floor(level or 0) + 1, 1, RebirthUpgrades.UnitSpawnTier.MaxLevel + 1)
end

function RebirthUpgrades.getManaMultiplier(level: number): number
	level = math.clamp(math.floor(level or 0), 0, RebirthUpgrades.MoreMana.MaxLevel)
	return 1 + level * RebirthUpgrades.MoreMana.MultiplierPerLevel
end

function RebirthUpgrades.getCost(upgradeKey: string, level: number): number?
	local config = RebirthUpgrades[upgradeKey]
	if type(config) ~= "table" or type(config.Costs) ~= "table" then
		return nil
	end

	level = math.max(math.floor(level or 0), 0)
	return config.Costs[level + 1]
end

function RebirthUpgrades.isMaxed(upgradeKey: string, level: number): boolean
	local config = RebirthUpgrades[upgradeKey]
	if type(config) ~= "table" then
		return true
	end

	return math.floor(level or 0) >= (config.MaxLevel or 0)
end

return RebirthUpgrades
