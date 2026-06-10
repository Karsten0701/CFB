local YenUpgrades = {}

YenUpgrades.BetterMaxButton = {
	MaxLevel = 5,
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

YenUpgrades.BetterGoldenDrops = {
	MaxLevel = 4,
	Costs = { 1000, 100000, 50e6, 1e9 },
	BaseMultiplier = 2,
	UnlockMultipliers = { 5, 10, 25, 100 },
}

YenUpgrades.Pickuprange = {
	MaxLevel = 4,
	Costs = { 100000, 1e6, 500e6, 25e9 },
	Multipliers = { 1, 1.25, 1.5, 1.75, 2 },
}

function YenUpgrades.getCost(upgradeKey: string, level: number): number?
	local config = YenUpgrades[upgradeKey]
	if type(config) ~= "table" or type(config.Costs) ~= "table" then
		return nil
	end

	level = math.max(math.floor(level or 0), 0)
	return config.Costs[level + 1]
end

function YenUpgrades.isMaxed(upgradeKey: string, level: number): boolean
	local config = YenUpgrades[upgradeKey]
	if type(config) ~= "table" then
		return true
	end

	return math.floor(level or 0) >= (config.MaxLevel or 0)
end

function YenUpgrades.getMaxButtonCount(level: number): number
	local config = YenUpgrades.BetterMaxButton
	local clampedLevel = math.clamp(math.floor(level or 0), 0, config.MaxLevel)
	local levelData = config.Levels[clampedLevel]
	return if type(levelData) == "table" then levelData.MaxButtonCount or 0 else 0
end

function YenUpgrades.getNextMaxButtonCount(level: number): number
	local config = YenUpgrades.BetterMaxButton
	local nextLevel = math.clamp(math.floor(level or 0) + 1, 0, config.MaxLevel)
	return YenUpgrades.getMaxButtonCount(nextLevel)
end

function YenUpgrades.getUnlockedGoldMultipliers(level: number): { number }
	local config = YenUpgrades.BetterGoldenDrops
	level = math.clamp(math.floor(level or 0), 0, config.MaxLevel)
	local multipliers = { config.BaseMultiplier or 2 }

	for index = 1, level do
		local unlocked = config.UnlockMultipliers[index]
		if type(unlocked) == "number" then
			table.insert(multipliers, unlocked)
		end
	end

	return multipliers
end

function YenUpgrades.getMaxGoldMultiplier(level: number): number
	local multipliers = YenUpgrades.getUnlockedGoldMultipliers(level)
	local maxMultiplier = 1

	for _, multiplier in multipliers do
		maxMultiplier = math.max(maxMultiplier, multiplier)
	end

	return maxMultiplier
end

function YenUpgrades.getCurrentGoldMultiplier(level: number): number
	local config = YenUpgrades.BetterGoldenDrops
	level = math.clamp(math.floor(level or 0), 0, config.MaxLevel)
	if level <= 0 then
		return config.BaseMultiplier or 2
	end

	return config.UnlockMultipliers[level] or config.BaseMultiplier or 2
end

function YenUpgrades.getNextGoldMultiplier(level: number): number
	local config = YenUpgrades.BetterGoldenDrops
	level = math.clamp(math.floor(level or 0), 0, config.MaxLevel)
	if level >= config.MaxLevel then
		return config.UnlockMultipliers[config.MaxLevel] or config.BaseMultiplier or 2
	end

	return config.UnlockMultipliers[level + 1] or config.BaseMultiplier or 2
end

function YenUpgrades.getPickupRangeMultiplier(level: number): number
	local config = YenUpgrades.Pickuprange
	level = math.clamp(math.floor(level or 0), 0, config.MaxLevel)
	return config.Multipliers[level + 1] or 1
end

function YenUpgrades.getNextPickupRangeMultiplier(level: number): number
	local config = YenUpgrades.Pickuprange
	local nextLevel = math.clamp(math.floor(level or 0) + 1, 0, config.MaxLevel)
	return config.Multipliers[nextLevel + 1] or config.Multipliers[#config.Multipliers] or 1
end

return YenUpgrades
