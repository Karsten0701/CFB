local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local QuestConfig = require(ReplicatedStorage.Shared.Data.QuestConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)

local QuestUtil = {}

local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400

local function getStableHash(value: string): number
	local hash = 2166136261
	for index = 1, #value do
		hash = bit32.bxor(hash, string.byte(value, index))
		hash = (hash * 16777619) % 4294967296
	end

	return hash
end

local function isLeapYear(year: number): boolean
	return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function getDaysInMonth(year: number, month: number): number
	local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	if month == 2 and isLeapYear(year) then
		return 29
	end

	return days[month] or 30
end

local function getLastSundayDay(year: number, month: number): number
	local daysInMonth = getDaysInMonth(year, month)
	local weekday =
		os.date("!*t", os.time({ year = year, month = month, day = daysInMonth, hour = 12, min = 0, sec = 0 })).wday
	local daysBack = (weekday - 1) % 7
	return daysInMonth - daysBack
end

function QuestUtil.getNetherlandsOffsetSeconds(now: number?): number
	now = math.floor(tonumber(now) or os.time())
	local utc = os.date("!*t", now)
	local year = utc.year

	local marchLastSunday = getLastSundayDay(year, 3)
	local octoberLastSunday = getLastSundayDay(year, 10)
	local dstStart = os.time({ year = year, month = 3, day = marchLastSunday, hour = 1, min = 0, sec = 0 })
	local dstEnd = os.time({ year = year, month = 10, day = octoberLastSunday, hour = 1, min = 0, sec = 0 })

	if now >= dstStart and now < dstEnd then
		return 7200
	end

	return 3600
end

function QuestUtil.getPeriodEnd(category: string, now: number?): number
	now = math.floor(tonumber(now) or os.time())
	local offset = QuestUtil.getNetherlandsOffsetSeconds(now)
	local localNow = now + offset
	local components = os.date("!*t", localNow)
	local secondsIntoDay = components.hour * SECONDS_PER_HOUR + components.min * SECONDS_PER_MINUTE + components.sec
	local midnightLocal = localNow - secondsIntoDay
	local resetHour = QuestConfig.Reset.DailyHour or 5

	if category == "Hourly" then
		local secondsIntoHour = components.min * SECONDS_PER_MINUTE + components.sec
		return now - secondsIntoHour + SECONDS_PER_HOUR
	end

	if category == "Daily" then
		local todayResetLocal = midnightLocal + resetHour * SECONDS_PER_HOUR
		local periodEndLocal = if localNow >= todayResetLocal
			then todayResetLocal + SECONDS_PER_DAY
			else todayResetLocal
		return periodEndLocal - offset
	end

	if category == "Weekly" then
		local weeklyDay = QuestConfig.Reset.WeeklyDay or 7
		local daysUntil = (weeklyDay - components.wday) % 7
		local targetDayStartLocal = midnightLocal + daysUntil * SECONDS_PER_DAY
		local targetResetLocal = targetDayStartLocal + resetHour * SECONDS_PER_HOUR

		if daysUntil == 0 and localNow >= targetResetLocal then
			targetResetLocal += 7 * SECONDS_PER_DAY
		end

		return targetResetLocal - offset
	end

	return now + SECONDS_PER_HOUR
end

function QuestUtil.getPeriodStart(category: string, now: number?): number
	now = math.floor(tonumber(now) or os.time())
	local periodEnd = QuestUtil.getPeriodEnd(category, now)

	if category == "Hourly" then
		return periodEnd - SECONDS_PER_HOUR
	end

	if category == "Daily" then
		return periodEnd - SECONDS_PER_DAY
	end

	if category == "Weekly" then
		return periodEnd - 7 * SECONDS_PER_DAY
	end

	return now or 0
end

function QuestUtil.getPeriodId(category: string, now: number?): string
	now = math.floor(tonumber(now) or os.time())
	local offset = QuestUtil.getNetherlandsOffsetSeconds(now)
	local periodStart = QuestUtil.getPeriodStart(category, now)
	local components = os.date("!*t", periodStart + offset)

	if category == "Hourly" then
		return string.format("%04d-%02d-%02dT%02d", components.year, components.month, components.day, components.hour)
	end

	if category == "Daily" then
		return string.format("%04d-%02d-%02d", components.year, components.month, components.day)
	end

	if category == "Weekly" then
		return string.format("%04d-W%02d-%02d", components.year, components.month, components.day)
	end

	return tostring(periodStart)
end

function QuestUtil.getTimeUntilReset(category: string, now: number?): number
	now = math.floor(tonumber(now) or os.time())
	return math.max(QuestUtil.getPeriodEnd(category, now or 0) - (now or 0), 0)
end

function QuestUtil.formatTimeUntilReset(category: string, now: number?): string
	local remaining = QuestUtil.getTimeUntilReset(category, now)

	if category == "Hourly" then
		local minutes = math.floor(remaining / SECONDS_PER_MINUTE)
		local seconds = remaining % SECONDS_PER_MINUTE
		return string.format("-- Resets in %dm %ds --", minutes, seconds)
	end

	if category == "Daily" then
		local hours = math.floor(remaining / SECONDS_PER_HOUR)
		local minutes = math.floor((remaining % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
		local seconds = remaining % SECONDS_PER_MINUTE
		return string.format("-- Resets in %dh %dm %ds --", hours, minutes, seconds)
	end

	local days = math.floor(remaining / SECONDS_PER_DAY)
	local hours = math.floor((remaining % SECONDS_PER_DAY) / SECONDS_PER_HOUR)
	local minutes = math.floor((remaining % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
	return string.format("-- Resets in %dd %dh %dm --", days, hours, minutes)
end

local function rollFromWeightedPool(entries: { any }, seed: string, usedIds: { [string]: boolean }?): any
	local candidates = {}
	local totalWeight = 0

	for _, entry in entries do
		if type(entry) ~= "table" then
			continue
		end

		if usedIds and entry.id and usedIds[entry.id] then
			continue
		end

		local weight = math.max(math.floor(tonumber(entry.weight) or 0), 0)
		if weight <= 0 then
			continue
		end

		totalWeight += weight
		table.insert(candidates, { Entry = entry, Weight = weight })
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = (getStableHash(seed) % totalWeight) + 1
	local current = 0
	for _, candidate in candidates do
		current += candidate.Weight
		if roll <= current then
			return candidate.Entry
		end
	end

	return candidates[#candidates].Entry
end

local function getDropIntervalSeconds(scaling: { [string]: any }): number
	return math.max(math.floor(tonumber(scaling.DropIntervalSeconds) or 60), 1)
end

function QuestUtil.getManaPerSecond(units: { { Tier: number } }?, dropIntervalSeconds: number?): number
	if type(units) ~= "table" then
		return 0
	end

	local scaling = QuestConfig.Scaling or {}
	local dropInterval = math.max(math.floor(tonumber(dropIntervalSeconds) or getDropIntervalSeconds(scaling)), 1)
	local total = 0

	for _, unit in units do
		if type(unit) ~= "table" then
			continue
		end

		local tierData = AnimeDroppers.Tiers[unit.Tier or 1]
		if tierData then
			total += math.max(tonumber(tierData.DropValue) or 1, 1) / dropInterval
		end
	end

	return math.max(total, 0)
end

function QuestUtil.getGroupRewardAmount(units: { { Tier: number } }?): number
	local groupRewardConfig = TycoonConfig.GroupReward or {}
	local baseYen = tonumber(groupRewardConfig.BaseYen) or 500
	local yenPerBaseUnit = tonumber(groupRewardConfig.YenPerBaseUnit) or 50
	local baseUnitCount = Pricing.getBaseUnitCount(units or {})
	local growthMultiplier = tonumber(groupRewardConfig.GrowthMultiplier) or 1
	local growthUnitsPerStep = math.max(tonumber(groupRewardConfig.GrowthUnitsPerStep) or 1, 1)
	local maxGrowthMultiplier = math.max(tonumber(groupRewardConfig.MaxGrowthMultiplier) or math.huge, 1)
	local reward = baseYen + baseUnitCount * yenPerBaseUnit
	local growth = math.min(growthMultiplier ^ (baseUnitCount / growthUnitsPerStep), maxGrowthMultiplier)
	return math.max(math.floor(reward * growth), 0)
end

function QuestUtil.getIncomeProfile(units: { { Tier: number } }?, yenMultiplier: number?)
	units = if type(units) == "table" then units else {}
	yenMultiplier = math.max(tonumber(yenMultiplier) or 1, 1)
	local manaPerSecond = QuestUtil.getManaPerSecond(units)

	return {
		manaPerSecond = manaPerSecond,
		yenPerSecond = manaPerSecond * yenMultiplier,
		yenMultiplier = yenMultiplier,
		baseUnitCount = Pricing.getBaseUnitCount(units or {}),
		unitCount = #(units or {}),
	}
end

function QuestUtil.getRewardIncomeProfile(units: { { Tier: number } }?, yenMultiplier: number?)
	units = if type(units) == "table" then units else {}
	yenMultiplier = math.max(tonumber(yenMultiplier) or 1, 1)
	local scaling = QuestConfig.Scaling or {}
	local rewardConfig = scaling.YenReward or {}
	local dropInterval = math.max(math.floor(tonumber(rewardConfig.DropIntervalSeconds) or 6), 1)
	local manaPerSecond = QuestUtil.getManaPerSecond(units, dropInterval)

	return {
		manaPerSecond = manaPerSecond,
		yenPerSecond = manaPerSecond * yenMultiplier,
		yenMultiplier = yenMultiplier,
		baseUnitCount = Pricing.getBaseUnitCount(units or {}),
		unitCount = #(units or {}),
	}
end

local function getIncomeSeconds(category: string, seed: string?): number
	local scaling = QuestConfig.Scaling or {}
	local incomeSeconds = scaling.IncomeSeconds or {}

	if category == "Hourly" then
		local hourly = incomeSeconds.Hourly or { Min = 600, Max = 900 }
		local minSec = math.max(math.floor(tonumber(hourly.Min) or 600), 60)
		local maxSec = math.max(math.floor(tonumber(hourly.Max) or 900), minSec)
		if type(seed) == "string" then
			local roll = getStableHash(seed .. ":income")
			return minSec + (roll % (maxSec - minSec + 1))
		end

		return minSec
	end

	return math.max(math.floor(tonumber(incomeSeconds[category]) or 600), 60)
end

local function getIncomeEfficiency(category: string): number
	local scaling = QuestConfig.Scaling or {}
	local efficiency = (scaling.IncomeEfficiency or {})[category]
	return math.clamp(tonumber(efficiency) or 0.4, 0.05, 1)
end

function QuestUtil.getCategoryDifficulty(category: string): number
	local scaling = QuestConfig.Scaling or {}
	return math.max(tonumber((scaling.CategoryDifficulty or {})[category]) or 1, 1)
end

function QuestUtil.getRewardDifficulty(category: string): number
	local scaling = QuestConfig.Scaling or {}
	return math.max(tonumber((scaling.RewardDifficulty or {})[category]) or 1, 1)
end

local function scaleRequirement(category: string, amount: number): number
	return math.max(math.floor(amount * QuestUtil.getCategoryDifficulty(category)), 1)
end

local function scaleReward(category: string, amount: number): number
	return math.max(math.floor(amount * QuestUtil.getRewardDifficulty(category)), 1)
end

local function getBuyUnitsProgressionMultiplier(
	scaling: { [string]: any },
	highestTier: number,
	baseUnitCount: number
): number
	local tierStep = math.max(tonumber(scaling.BuyUnitsTierStep) or 0.04, 0)
	local unitStrength = math.max(tonumber(scaling.BuyUnitsUnitStrength) or 0.06, 0)
	local tierMult = 1 + math.max(highestTier - 1, 0) * tierStep
	local unitMult = 1 + math.log10(math.max(baseUnitCount, 1) + 1) * unitStrength
	return tierMult * unitMult
end

function QuestUtil.computeQuestTarget(
	questType: string,
	category: string,
	income: { [string]: any },
	highestTier: number,
	seed: string?
): number
	highestTier = math.clamp(math.floor(tonumber(highestTier) or 1), 1, AnimeDroppers.MaxTier)
	income = income or QuestUtil.getIncomeProfile(nil, 1)
	local scaling = QuestConfig.Scaling or {}
	local manaPerSecond = math.max(tonumber(income.manaPerSecond) or 0, 0)
	local yenPerSecond = math.max(tonumber(income.yenPerSecond) or 0, 0)
	local baseUnitCount = math.max(math.floor(tonumber(income.baseUnitCount) or 0), 0)

	if questType == "EarnYen" then
		local seconds = getIncomeSeconds(category, seed)
		local efficiency = getIncomeEfficiency(category)
		local minimums = scaling.EarnYenMinimum or {}
		local minimum = math.max(math.floor(tonumber(minimums[category]) or 100), 1)
		local target = math.max(math.floor(yenPerSecond * seconds * efficiency), minimum)
		return scaleRequirement(category, target)
	end

	if questType == "CollectMana" then
		local seconds = getIncomeSeconds(category, seed)
		local efficiency = getIncomeEfficiency(category)
		local minimums = scaling.CollectManaMinimum or {}
		local minimum = math.max(math.floor(tonumber(minimums[category]) or 100), 1)
		local target = math.max(math.floor(manaPerSecond * seconds * efficiency), minimum)
		return scaleRequirement(category, target)
	end

	if questType == "BuyUnits" then
		local minimums = scaling.BuyUnitsMinimum or {}
		local minimum = math.max(math.floor(tonumber(minimums[category]) or 1), 1)
		local progressionMult = getBuyUnitsProgressionMultiplier(scaling, highestTier, baseUnitCount)
		local target = math.max(math.floor(minimum * progressionMult), 1)
		return scaleRequirement(category, target)
	end

	if questType == "Playtime" then
		local playtime = scaling.PlaytimeSeconds or {}
		local seconds = 60

		if category == "Hourly" then
			local minSec = math.max(math.floor(tonumber(playtime.HourlyMin) or 600), 60)
			local maxSec = math.max(math.floor(tonumber(playtime.HourlyMax) or 900), minSec)
			if type(seed) == "string" then
				local roll = getStableHash(seed .. ":playtime")
				seconds = minSec + (roll % (maxSec - minSec + 1))
			else
				seconds = minSec
			end
		elseif category == "Daily" then
			seconds = math.max(math.floor(tonumber(playtime.Daily) or 10800), 60)
		elseif category == "Weekly" then
			seconds = math.max(math.floor(tonumber(playtime.Weekly) or 43200), 60)
		end

		return scaleRequirement(category, seconds)
	end

	if questType == "ReachTier" then
		local offset = (scaling.ReachTierOffset or {})[category] or 0
		return math.clamp(highestTier + offset, 2, AnimeDroppers.MaxTier)
	end

	return 1
end

function QuestUtil.estimateYenMultiplier(rebirths: number?): number
	rebirths = math.max(math.floor(tonumber(rebirths) or 0), 0)
	local rebirthConfig = TycoonConfig.Rebirth or {}
	return math.max((rebirthConfig.BaseYenMultiplier or 1) + rebirths * (rebirthConfig.YenMultiplierPerRebirth or 0), 1)
end

function QuestUtil.getRewardContext(
	units: { { Tier: number } }?,
	yenMultiplier: number?
): {
	units: { { Tier: number } },
	yenMultiplier: number,
	highestTier: number,
	income: { [string]: any },
}
	units = if type(units) == "table" then units else {}
	yenMultiplier = math.max(tonumber(yenMultiplier) or 1, 1)
	local income = QuestUtil.getIncomeProfile(units, yenMultiplier)

	return {
		units = units,
		yenMultiplier = yenMultiplier,
		highestTier = CapsuleUtil.getHighestUnitTier(units),
		income = income,
	}
end

function QuestUtil.computeYenRewardAmount(
	income: { [string]: any },
	category: string,
	units: { { Tier: number } }?
): number
	local yenMultiplier = 1
	if type(income) == "table" then
		yenMultiplier = math.max(tonumber(income.yenMultiplier) or 1, 1)
		if yenMultiplier <= 1 then
			local manaPerSecond = math.max(tonumber(income.manaPerSecond) or 0, 0)
			local yenPerSecond = math.max(tonumber(income.yenPerSecond) or 0, 0)
			if manaPerSecond > 0 then
				yenMultiplier = yenPerSecond / manaPerSecond
			end
		end
	end

	local rewardIncome = QuestUtil.getRewardIncomeProfile(units, yenMultiplier)
	local scaling = QuestConfig.Scaling or {}
	local rewardConfig = scaling.YenReward or {}
	local seconds = math.max(math.floor(tonumber((rewardConfig.Seconds or {})[category]) or 180), 1)
	local multiplier = math.clamp(tonumber(rewardConfig.Multiplier) or 0.16, 0.01, 1)
	local minimum = math.max(math.floor(tonumber((rewardConfig.Minimum or {})[category]) or 100), 1)
	local groupCapRatio = math.clamp(tonumber(rewardConfig.GroupRewardCap) or 0.5, 0.1, 1)
	local yenPerSecond = math.max(tonumber(rewardIncome.yenPerSecond) or 0, 0)
	local offlineStyle = math.floor(yenPerSecond * seconds * multiplier)
	local groupReward = QuestUtil.getGroupRewardAmount(units)
	local groupCap = math.max(math.floor(groupReward * groupCapRatio), minimum)
	local amount = math.max(math.min(offlineStyle, groupCap), minimum)
	return scaleReward(category, amount)
end

local function getPotionRewardAmount(_reward: { [string]: any }, category: string): number
	return math.max(math.floor(tonumber((QuestConfig.PotionAmounts or {})[category]) or 1), 1)
end

local function formatPotionRewardText(amount: number, potionType: string): string
	amount = math.max(math.floor(tonumber(amount) or 1), 1)
	potionType = potionType or "Yen"
	return tostring(amount) .. "x " .. potionType .. " Potion"
end

local function mergeCategoryRewardWeights(
	entryWeights: { [string]: number },
	category: string
): { [string]: number }
	local categoryWeights = (QuestConfig.CategoryRewardWeights or {})[category] or {}
	local merged = {}

	for kind, weight in entryWeights do
		local entryWeight = math.max(math.floor(tonumber(weight) or 0), 0)
		if entryWeight <= 0 then
			continue
		end

		local categoryWeight = math.max(tonumber(categoryWeights[kind]) or 1, 0)
		if categoryWeight <= 0 then
			continue
		end

		merged[kind] = entryWeight * categoryWeight
	end

	if next(merged) == nil then
		return { Yen = 1 }
	end

	return merged
end

local function rollRewardKind(
	rewardWeights: { [string]: number },
	seed: string,
	potionRewardsRolled: number?
): string
	local maxPotions = math.max(math.floor(tonumber(QuestConfig.MaxPotionRewardsPerPeriod) or 1), 0)
	potionRewardsRolled = math.max(math.floor(tonumber(potionRewardsRolled) or 0), 0)

	local candidates = {}
	local totalWeight = 0

	for kind, weight in rewardWeights do
		if kind == "Potion" and potionRewardsRolled >= maxPotions then
			continue
		end

		local normalizedWeight = math.max(math.floor(tonumber(weight) or 0), 0)
		if normalizedWeight > 0 then
			totalWeight += normalizedWeight
			table.insert(candidates, { Kind = kind, Weight = normalizedWeight })
		end
	end

	if totalWeight <= 0 then
		return "Yen"
	end

	local roll = (getStableHash(seed .. ":rewardKind") % totalWeight) + 1
	local current = 0
	for _, candidate in candidates do
		current += candidate.Weight
		if roll <= current then
			return candidate.Kind
		end
	end

	return candidates[#candidates].Kind
end

function QuestUtil.buildReward(
	kind: string,
	category: string,
	income: { [string]: any },
	highestTier: number,
	seed: string,
	units: { { Tier: number } }?
)
	highestTier = math.clamp(math.floor(tonumber(highestTier) or 1), 1, AnimeDroppers.MaxTier)

	if kind == "Yen" then
		return {
			Kind = "Yen",
			Amount = QuestUtil.computeYenRewardAmount(income, category, units),
			RewardTier = highestTier,
		}
	end

	if kind == "Potion" then
		local potionTypes = QuestConfig.PotionTypes
		local typeIndex = (getStableHash(seed .. ":potionType") % #potionTypes) + 1
		return {
			Kind = "Potion",
			PotionType = potionTypes[typeIndex],
			Amount = math.max(math.floor(tonumber((QuestConfig.PotionAmounts or {})[category]) or 1), 1),
		}
	end

	if kind == "UnitTier" then
		return {
			Kind = "UnitTier",
			Offset = (QuestConfig.UnitTierOffsets or {})[category] or 0,
			MinTier = math.max(math.floor(tonumber((QuestConfig.UnitMinTier or {})[category]) or 3), 1),
			Amount = 1,
			RewardTier = highestTier,
		}
	end

	return {
		Kind = "Yen",
		Amount = QuestUtil.computeYenRewardAmount(income, category, units),
		RewardTier = highestTier,
	}
end

local function rollReward(
	rewardWeights: { [string]: number },
	category: string,
	income: { [string]: any },
	highestTier: number,
	seed: string,
	units: { { Tier: number } }?,
	potionRewardsRolled: number?
)
	local mergedWeights = mergeCategoryRewardWeights(rewardWeights or { Yen = 1 }, category)
	local kind = rollRewardKind(mergedWeights, seed, potionRewardsRolled)
	return QuestUtil.buildReward(kind, category, income, highestTier, seed, units)
end

function QuestUtil.rollQuestSlots(
	userId: number,
	category: string,
	periodId: string,
	units: { { Tier: number } }?,
	yenMultiplier: number?
)
	local usedIds = {}
	local potionRewardsRolled = 0
	local slots = {}
	units = if type(units) == "table" then units else {}
	local income = QuestUtil.getIncomeProfile(units, yenMultiplier)
	local highestTier = CapsuleUtil.getHighestUnitTier(units)

	for slotIndex = 1, QuestConfig.QuestCount do
		local seed = tostring(userId) .. ":" .. periodId .. ":" .. category .. ":" .. tostring(slotIndex)
		local questEntry = rollFromWeightedPool(QuestConfig.Pool, seed, usedIds)
		if not questEntry then
			questEntry = QuestConfig.Pool[1]
		end

		if questEntry and questEntry.id then
			usedIds[questEntry.id] = true
		end

		local target = QuestUtil.computeQuestTarget(questEntry.type, category, income, highestTier, seed)
		local reward = rollReward(
			questEntry.rewardWeights or { Yen = 1 },
			category,
			income,
			highestTier,
			seed,
			units,
			potionRewardsRolled
		)

		if type(reward) == "table" and reward.Kind == "Potion" then
			potionRewardsRolled += 1
		end

		table.insert(slots, {
			QuestId = questEntry.id,
			Type = questEntry.type,
			Target = target,
			Reward = reward,
			Progress = 0,
			Claimed = false,
		})
	end

	return slots
end

function QuestUtil.createBaselines(stats: { [string]: any })
	return {
		PlaytimeSeconds = math.max(math.floor(tonumber(stats.PlaytimeSeconds) or 0), 0),
	}
end

function QuestUtil.createPeriodStats()
	return {
		YenEarned = 0,
		UnitsBought = 0,
		ManaCollected = 0,
	}
end

function QuestUtil.computeProgress(
	questType: string,
	target: number,
	stats: { [string]: any },
	baselines: { [string]: any }
): number
	target = math.max(math.floor(tonumber(target) or 1), 1)
	baselines = baselines or {}
	stats = stats or {}

	if questType == "BuyUnits" then
		return math.max(math.floor(tonumber(stats.UnitsBought) or 0), 0)
	end

	if questType == "EarnYen" then
		return math.max(math.floor(tonumber(stats.YenEarned) or 0), 0)
	end

	if questType == "CollectMana" then
		return math.max(math.floor(tonumber(stats.ManaCollected) or 0), 0)
	end

	if questType == "Playtime" then
		local current = math.max(math.floor(tonumber(stats.PlaytimeSeconds) or 0), 0)
		local baseline = math.max(math.floor(tonumber(baselines.PlaytimeSeconds) or 0), 0)
		return math.max(current - baseline, 0)
	end

	if questType == "ReachTier" then
		return math.max(math.floor(tonumber(stats.HighestTier) or 1), 1)
	end

	return 0
end

function QuestUtil.isQuestComplete(questType: string, target: number, progress: number): boolean
	target = math.max(math.floor(tonumber(target) or 1), 1)
	progress = math.max(math.floor(tonumber(progress) or 0), 0)

	if questType == "ReachTier" then
		return progress >= target
	end

	return progress >= target
end

local function formatPlaytimeTarget(seconds: number): string
	seconds = math.max(math.floor(tonumber(seconds) or 0), 0)
	if seconds >= SECONDS_PER_HOUR and seconds % SECONDS_PER_HOUR == 0 then
		local hours = seconds / SECONDS_PER_HOUR
		return tostring(hours) .. (hours == 1 and " hour" or " hours")
	end

	local minutes = math.max(math.ceil(seconds / SECONDS_PER_MINUTE), 1)
	return tostring(minutes) .. (minutes == 1 and " min" or " min")
end

function QuestUtil.formatProgressValue(questType: string, value: number): string
	value = math.max(math.floor(tonumber(value) or 0), 0)

	if questType == "EarnYen" or questType == "CollectMana" then
		return FormatUtil.formatNumber(value)
	end

	if questType == "Playtime" then
		return formatPlaytimeTarget(value)
	end

	if questType == "ReachTier" then
		return "T" .. tostring(value)
	end

	return FormatUtil.formatNumber(value)
end

function QuestUtil.formatQuestDescription(questType: string, target: number, progress: number): string
	local labelTemplate = QuestConfig.TypeLabels[questType] or "Complete %s"
	local targetText = QuestUtil.formatProgressValue(questType, target)
	local description = string.format(labelTemplate, targetText)

	if questType == "ReachTier" then
		local currentTier = math.max(math.floor(tonumber(progress) or 1), 1)
		return description .. string.format(" (%s/%s)", "T" .. tostring(currentTier), "T" .. tostring(target))
	end

	local progressText = QuestUtil.formatProgressValue(questType, progress)
	local targetDisplay = QuestUtil.formatProgressValue(questType, target)
	return description .. string.format(" (%s/%s)", progressText, targetDisplay)
end

function QuestUtil.resolveUnitRewardTier(highestTier: number, reward: { [string]: any }): number
	highestTier = math.max(math.floor(tonumber(highestTier) or 1), 1)
	local offset = math.floor(tonumber(reward.Offset) or 0)
	local minTier = math.max(math.floor(tonumber(reward.MinTier) or 3), 1)
	return math.clamp(math.max(minTier, highestTier + offset), 1, AnimeDroppers.MaxTier)
end

function QuestUtil.syncSlotReward(
	slot: { [string]: any },
	context: { [string]: any },
	category: string
): { [string]: any }
	if type(slot) ~= "table" or type(slot.Reward) ~= "table" then
		return slot
	end

	local resolved = QuestUtil.resolveRewardAmount(slot.Reward, context, category)
	local nextSlot = table.clone(slot)
	local nextReward = table.clone(slot.Reward)

	if resolved.Kind == "Yen" then
		nextReward.Amount = resolved.Amount
	elseif resolved.Kind == "UnitTier" then
		nextReward.RewardTier = resolved.Tier
	end

	nextSlot.Reward = nextReward
	return nextSlot
end

function QuestUtil.resolveRewardAmount(
	reward: { [string]: any },
	context: { [string]: any },
	category: string
): { [string]: any }
	if type(reward) ~= "table" then
		return { Kind = "Yen", Amount = 0 }
	end

	context = QuestUtil.getRewardContext(context.units, context.yenMultiplier)

	if reward.Kind == "Yen" then
		local rewardIncome = QuestUtil.getRewardIncomeProfile(context.units, context.yenMultiplier)
		return {
			Kind = "Yen",
			Amount = QuestUtil.computeYenRewardAmount(rewardIncome, category, context.units),
		}
	end

	if reward.Kind == "Potion" then
		return {
			Kind = "Potion",
			PotionType = reward.PotionType,
			Amount = getPotionRewardAmount(reward, category),
		}
	end

	if reward.Kind == "UnitTier" then
		return {
			Kind = "UnitTier",
			Tier = QuestUtil.resolveUnitRewardTier(context.highestTier, reward),
			Amount = 1,
		}
	end

	return reward
end

function QuestUtil.formatRewardText(reward: { [string]: any }, context: { [string]: any }, category: string): string
	if type(reward) ~= "table" then
		return "Reward: ?"
	end

	context = QuestUtil.getRewardContext(context.units, context.yenMultiplier)

	if reward.Kind == "Potion" then
		return formatPotionRewardText(getPotionRewardAmount(reward, category), reward.PotionType)
	end

	local resolved = QuestUtil.resolveRewardAmount(reward, context, category)

	if resolved.Kind == "Yen" then
		return "¥" .. FormatUtil.formatNumber(resolved.Amount)
	end

	if resolved.Kind == "UnitTier" then
		local tier = math.max(math.floor(tonumber(resolved.Tier) or 1), 1)
		local amount = 1
		local tierData = AnimeDroppers.Tiers[tier]
		local displayName = if tierData and tierData.DisplayName
			then tierData.DisplayName
			else "Tier " .. tostring(tier)
		return tostring(amount) .. "x " .. displayName .. " (T" .. tostring(tier) .. ")"
	end

	return "Reward"
end

function QuestUtil.formatGrantedRewardText(resolved: { [string]: any }): string
	if type(resolved) ~= "table" then
		return "your reward"
	end

	if resolved.Kind == "Yen" then
		local amount = math.max(math.floor(tonumber(resolved.Amount) or 0), 0)
		return "¥" .. FormatUtil.formatNumber(amount)
	end

	if resolved.Kind == "Potion" then
		return formatPotionRewardText(resolved.Amount, resolved.PotionType)
	end

	if resolved.Kind == "UnitTier" then
		local tier = math.max(math.floor(tonumber(resolved.Tier) or 1), 1)
		local tierData = AnimeDroppers.Tiers[tier]
		local displayName = if tierData and tierData.DisplayName
			then tierData.DisplayName
			else "Tier " .. tostring(tier)
		return "1x " .. displayName .. " (T" .. tostring(tier) .. ")"
	end

	return "your reward"
end

return QuestUtil
