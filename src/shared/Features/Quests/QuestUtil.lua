local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local QuestConfig = require(ReplicatedStorage.Shared.Data.QuestConfig)

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
	local weekday = os.date("!*t", os.time({ year = year, month = month, day = daysInMonth, hour = 12, min = 0, sec = 0 })).wday
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
	local secondsIntoDay = components.hour * SECONDS_PER_HOUR
		+ components.min * SECONDS_PER_MINUTE
		+ components.sec
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

	return now
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
	return math.max(QuestUtil.getPeriodEnd(category, now) - now, 0)
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

function QuestUtil.getTierEconomyScale(tier: number): number
	tier = math.clamp(math.floor(tonumber(tier) or 1), 1, AnimeDroppers.MaxTier)
	local tierData = AnimeDroppers.Tiers[tier]
	if not tierData then
		return 100
	end

	local dropValue = math.max(tonumber(tierData.DropValue) or 1, 1)
	local estimatedCost = math.max(tonumber(tierData.EstimatedTier1Cost) or 1, 1)
	return math.max(dropValue * estimatedCost, 100)
end

local function getQuestProgressionMultipliers(
	scaling: { [string]: any },
	highestTier: number,
	unitCount: number,
	requiredTier1: number
): (number, number)
	local tierStep = math.max(tonumber(scaling.TierMultiplierPerStep) or 0.12, 0)
	local unitStrength = math.max(tonumber(scaling.UnitScaleStrength) or 0.22, 0)
	local tierMult = 1 + math.max(highestTier - 1, 0) * tierStep
	local unitRatio = math.max(unitCount, 1) / math.max(requiredTier1, 1)
	local unitMult = 1 + math.log10(unitRatio + 1) * unitStrength

	return tierMult, unitMult
end

function QuestUtil.computeQuestTarget(
	questType: string,
	category: string,
	highestTier: number,
	unitCount: number?,
	seed: string?
): number
	highestTier = math.clamp(math.floor(tonumber(highestTier) or 1), 1, AnimeDroppers.MaxTier)
	unitCount = math.max(math.floor(tonumber(unitCount) or 0), 0)
	local scaling = QuestConfig.Scaling or {}
	local tierData = AnimeDroppers.Tiers[highestTier]
	local requiredTier1 = math.max(tonumber(tierData and tierData.RequiredTier1) or 1, 1)
	local tierMult, unitMult = getQuestProgressionMultipliers(scaling, highestTier, unitCount, requiredTier1)
	local progressionMult = tierMult * unitMult

	if questType == "EarnYen" then
		local tierScale = QuestUtil.getTierEconomyScale(highestTier)
		local percent = (scaling.EarnYenTierPercent or {})[category] or 0.1
		local minimums = scaling.EarnYenMinimum or {}
		local minimum = math.max(math.floor(tonumber(minimums[category]) or 100), 100)
		return math.max(math.floor(tierScale * percent * progressionMult), minimum)
	end

	if questType == "CollectMana" then
		local percent = (scaling.CollectManaTierPercent or {})[category] or 0.1
		local minimums = scaling.CollectManaMinimum or {}
		local minimum = math.max(math.floor(tonumber(minimums[category]) or 50), 50)
		local dropValue = math.max(tonumber(tierData and tierData.DropValue) or 1, 1)
		return math.max(math.floor(dropValue * requiredTier1 * percent * 10 * progressionMult), minimum)
	end

	if questType == "BuyUnits" then
		local minimums = scaling.BuyUnitsMinimum or {}
		local minimum = math.max(math.floor(tonumber(minimums[category]) or 1), 1)
		return math.max(math.floor(minimum * progressionMult), 1)
	end

	if questType == "Playtime" then
		local playtime = scaling.PlaytimeSeconds or {}
		if category == "Hourly" then
			local minSec = math.max(math.floor(tonumber(playtime.HourlyMin) or 600), 60)
			local maxSec = math.max(math.floor(tonumber(playtime.HourlyMax) or 900), minSec)
			if type(seed) == "string" then
				local roll = getStableHash(seed .. ":playtime")
				return minSec + (roll % (maxSec - minSec + 1))
			end

			return minSec
		end

		if category == "Daily" then
			return math.max(math.floor(tonumber(playtime.Daily) or 10800), 60)
		end

		if category == "Weekly" then
			return math.max(math.floor(tonumber(playtime.Weekly) or 43200), 60)
		end
	end

	if questType == "ReachTier" then
		local offset = (scaling.ReachTierOffset or {})[category] or 0
		return math.clamp(highestTier + offset, 2, AnimeDroppers.MaxTier)
	end

	return 1
end

function QuestUtil.computeYenRewardAmount(highestTier: number, category: string): number
	highestTier = math.clamp(math.floor(tonumber(highestTier) or 1), 1, AnimeDroppers.MaxTier)
	local scaling = QuestConfig.Scaling or {}
	local percent = (scaling.EarnYenReward or {})[category] or 0.1
	local tierScale = QuestUtil.getTierEconomyScale(highestTier)
	local amount = math.max(math.floor(tierScale * percent), 100)
	if category == "Hourly" then
		amount = math.max(math.floor(amount / 5), 100)
	end
	return amount
end

local function formatPotionRewardText(amount: number, potionType: string): string
	amount = math.max(math.floor(tonumber(amount) or 1), 1)
	potionType = potionType or "Yen"
	return tostring(amount) .. "x " .. potionType .. " Potion"
end

local function rollRewardKind(rewardWeights: { [string]: number }, seed: string): string
	local candidates = {}
	local totalWeight = 0

	for kind, weight in rewardWeights do
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

function QuestUtil.buildReward(kind: string, category: string, highestTier: number, seed: string)
	highestTier = math.clamp(math.floor(tonumber(highestTier) or 1), 1, AnimeDroppers.MaxTier)

	if kind == "Yen" then
		return {
			Kind = "Yen",
			Amount = QuestUtil.computeYenRewardAmount(highestTier, category),
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
		Amount = QuestUtil.computeYenRewardAmount(highestTier, category),
		RewardTier = highestTier,
	}
end

local function rollReward(rewardWeights: { [string]: number }, category: string, highestTier: number, seed: string)
	local kind = rollRewardKind(rewardWeights or { Yen = 1 }, seed)
	return QuestUtil.buildReward(kind, category, highestTier, seed)
end

function QuestUtil.rollQuestSlots(userId: number, category: string, periodId: string, highestTier: number, unitCount: number?)
	local usedIds = {}
	local slots = {}

	for slotIndex = 1, QuestConfig.QuestCount do
		local seed = tostring(userId) .. ":" .. periodId .. ":" .. category .. ":" .. tostring(slotIndex)
		local questEntry = rollFromWeightedPool(QuestConfig.Pool, seed, usedIds)
		if not questEntry then
			questEntry = QuestConfig.Pool[1]
		end

		if questEntry and questEntry.id then
			usedIds[questEntry.id] = true
		end

		local target = QuestUtil.computeQuestTarget(questEntry.type, category, highestTier, unitCount, seed)
		local reward = rollReward(questEntry.rewardWeights or { Yen = 1 }, category, highestTier, seed)

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

function QuestUtil.computeProgress(questType: string, target: number, stats: { [string]: any }, baselines: { [string]: any }): number
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

function QuestUtil.resolveRewardAmount(reward: { [string]: any }, highestTier: number, category: string): { [string]: any }
	if type(reward) ~= "table" then
		return { Kind = "Yen", Amount = 0 }
	end

	if reward.Kind == "Yen" then
		return {
			Kind = "Yen",
			Amount = QuestUtil.computeYenRewardAmount(highestTier, category),
		}
	end

	if reward.Kind == "Potion" then
		return {
			Kind = "Potion",
			PotionType = reward.PotionType,
			Amount = math.max(math.floor(tonumber(reward.Amount) or 1), 1),
		}
	end

	if reward.Kind == "UnitTier" then
		return {
			Kind = "UnitTier",
			Tier = QuestUtil.resolveUnitRewardTier(highestTier, reward),
			Amount = math.max(math.floor(tonumber(reward.Amount) or 1), 1),
		}
	end

	return reward
end

function QuestUtil.formatRewardText(reward: { [string]: any }, highestTier: number, category: string): string
	if type(reward) ~= "table" then
		return "Reward: ?"
	end

	highestTier = math.clamp(math.floor(tonumber(highestTier) or 1), 1, AnimeDroppers.MaxTier)

	if reward.Kind == "Yen" then
		local amount = QuestUtil.computeYenRewardAmount(highestTier, category)
		return "¥" .. FormatUtil.formatNumber(amount)
	end

	if reward.Kind == "Potion" then
		return formatPotionRewardText(reward.Amount, reward.PotionType)
	end

	if reward.Kind == "UnitTier" then
		local tier = QuestUtil.resolveUnitRewardTier(highestTier, reward)
		local tierData = AnimeDroppers.Tiers[tier]
		local displayName = if tierData and tierData.DisplayName then tierData.DisplayName else "Tier " .. tostring(tier)
		return "1x " .. displayName .. " (T" .. tostring(tier) .. ")"
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
		local displayName = if tierData and tierData.DisplayName then tierData.DisplayName else "Tier " .. tostring(tier)
		return "1x " .. displayName .. " (T" .. tostring(tier) .. ")"
	end

	return "your reward"
end

return QuestUtil
