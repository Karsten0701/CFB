local RebirthUpgrades = {}

RebirthUpgrades.UnitSpawnTier = {
	MaxLevel = 4,
	kind = "RebirthTokens",
	Costs = { 1, 4, 8, 20 },
}

RebirthUpgrades.MoreMana = {
	MaxLevel = 5,
	kind = "RebirthTokens",
	MultiplierPerLevel = 0.2,
	Costs = { 2, 3, 8, 13, 21 },
}

RebirthUpgrades.BetterMaxButton = {
	MaxLevel = 5,
	kind = "Yen",
	Costs = { 1e9, 5e11, 5e12, 1e14, 2.5e16 },
	Levels = {
		[1] = {
			MaxButtonCount = 1000,
		},
		[2] = {
			MaxButtonCount = 5000,
		},
		[3] = {
			MaxButtonCount = 25000,
		},
		[4] = {
			MaxButtonCount = 100000,
		},
		[5] = {
			MaxButtonCount = 1000000,
		},
	},
}

function RebirthUpgrades.getUnitSpawnTier(level: number): number
	return math.clamp(math.floor(level or 0) + 1, 1, RebirthUpgrades.UnitSpawnTier.MaxLevel + 1)
end

function RebirthUpgrades.upgradeUnitsForSpawnTier(
	units: { { Tier: number, Slot: number? } },
	previousLevel: number,
	nextLevel: number
): ({ { Tier: number, Slot: number? } }, boolean)
	local previousSpawnTier = RebirthUpgrades.getUnitSpawnTier(previousLevel)
	local newSpawnTier = RebirthUpgrades.getUnitSpawnTier(nextLevel)
	if newSpawnTier <= previousSpawnTier then
		return units, false
	end

	local changed = false
	local nextUnits = table.create(#units)

	for _, unit in units do
		if type(unit) ~= "table" then
			continue
		end

		local tier = math.clamp(math.floor(tonumber(unit.Tier) or 1), 1, newSpawnTier)
		if tier == previousSpawnTier and tier < newSpawnTier then
			tier = newSpawnTier
			changed = true
		end

		table.insert(nextUnits, {
			Tier = tier,
			Slot = unit.Slot,
		})
	end

	return nextUnits, changed
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

function RebirthUpgrades.getMaxButtonCount(level: number): number
	local config = RebirthUpgrades.BetterMaxButton
	local clampedLevel = math.clamp(math.floor(level or 0), 0, config.MaxLevel)
	local levelData = config.Levels[clampedLevel]
	return if type(levelData) == "table" then levelData.MaxButtonCount or 0 else 0
end

function RebirthUpgrades.getNextMaxButtonCount(level: number): number
	local config = RebirthUpgrades.BetterMaxButton
	local nextLevel = math.clamp(math.floor(level or 0) + 1, 0, config.MaxLevel)
	return RebirthUpgrades.getMaxButtonCount(nextLevel)
end

return RebirthUpgrades
