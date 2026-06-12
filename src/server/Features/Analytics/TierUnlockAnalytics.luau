local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)

local TierUnlockAnalytics = {}

local FIRST_JOIN_FUNNEL_NAME = "FirstJoin"
local TIER_UNLOCK_FUNNEL_NAME = "TierUnlocks"
local TUTORIAL_COMPLETE_FUNNEL_NAME = "TutorialComplete"
local SESSION_TIME_FUNNEL_NAME = "SessionTime"
local PLAYTIME_FUNNEL_NAME = "Playtime"
local REBIRTH_FUNNEL_NAME = "Rebirths"
local QUEST_FUNNEL_NAME = "Quests"

local function getStepName(tier: number): string
	return "Unlocked Tier " .. tostring(tier)
end

function TierUnlockAnalytics.logFirstJoin(player: Player): boolean
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, FIRST_JOIN_FUNNEL_NAME, nil, 1, "Joined Game")
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log first join funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logTierUnlocked(player: Player, tier: number): boolean
	tier = math.floor(tonumber(tier) or 0)
	if not AnimeDroppers.Tiers[tier] then
		return false
	end

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, TIER_UNLOCK_FUNNEL_NAME, nil, tier, getStepName(tier))
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log tier unlock funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.getTierUnlockSteps(): { number }
	local tiers = {}
	for tier in AnimeDroppers.Tiers do
		local normalizedTier = math.floor(tonumber(tier) or 0)
		if normalizedTier >= 1 then
			table.insert(tiers, normalizedTier)
		end
	end

	table.sort(tiers)
	return tiers
end

function TierUnlockAnalytics.logTutorialCompleted(player: Player): boolean
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, TUTORIAL_COMPLETE_FUNNEL_NAME, nil, 1, "Completed Tutorial")
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log tutorial complete funnel step:", err)
	end

	return ok
end

local function getMinuteLabel(minutes: number): string
	local suffix = if minutes == 1 then "Minute" else "Minutes"
	return "Played " .. tostring(minutes) .. " " .. suffix
end

function TierUnlockAnalytics.getSessionTimeMilestones(): { number }
	local milestones = {}

	for minute = 1, 10 do
		table.insert(milestones, minute)
	end

	for minute = 15, 60, 5 do
		table.insert(milestones, minute)
	end

	for minute = 75, 12 * 60, 15 do
		table.insert(milestones, minute)
	end

	return milestones
end

function TierUnlockAnalytics.getPlaytimeMilestones(): { number }
	local milestones = TierUnlockAnalytics.getSessionTimeMilestones()

	for minute = 24 * 60, 7 * 24 * 60, 12 * 60 do
		table.insert(milestones, minute)
	end

	return milestones
end

function TierUnlockAnalytics.logSessionTimeReached(player: Player, minutes: number, step: number?): boolean
	minutes = math.floor(tonumber(minutes) or 0)
	if minutes <= 0 then
		return false
	end
	step = math.max(math.floor(tonumber(step) or minutes), 1)

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, SESSION_TIME_FUNNEL_NAME, nil, step, getMinuteLabel(minutes))
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log session time funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logPlaytimeReached(player: Player, minutes: number, step: number?): boolean
	minutes = math.floor(tonumber(minutes) or 0)
	if minutes <= 0 then
		return false
	end
	step = math.max(math.floor(tonumber(step) or minutes), 1)

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, PLAYTIME_FUNNEL_NAME, nil, step, getMinuteLabel(minutes))
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log playtime funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logRebirthReached(player: Player, rebirths: number): boolean
	rebirths = math.floor(tonumber(rebirths) or 0)
	if rebirths <= 0 then
		return false
	end

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			REBIRTH_FUNNEL_NAME,
			nil,
			rebirths,
			"Reached Rebirth " .. tostring(rebirths)
		)
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log rebirth funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logQuestUnlocked(player: Player): boolean
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, QUEST_FUNNEL_NAME, nil, 1, "Unlocked Quests")
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log quest unlock funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logQuestOpened(player: Player): boolean
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, QUEST_FUNNEL_NAME, nil, 2, "Opened Quests")
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log quest open funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logQuestClaimed(player: Player): boolean
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, QUEST_FUNNEL_NAME, nil, 3, "Claimed Quest")
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log quest claim funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.getNewUnlockTiers(previousUnlocked: any, nextUnlocked: any, loggedTiers: any): { number }
	if type(nextUnlocked) ~= "table" then
		return {}
	end

	local newTiers = {}
	for tier, unlocked in nextUnlocked do
		local normalizedTier = math.floor(tonumber(tier) or 0)
		local wasUnlocked = type(previousUnlocked) == "table"
			and (previousUnlocked[normalizedTier] == true or previousUnlocked[tostring(normalizedTier)] == true)
		local wasLogged = type(loggedTiers) == "table"
			and (loggedTiers[normalizedTier] == true or loggedTiers[tostring(normalizedTier)] == true)

		if unlocked == true and not wasUnlocked and not wasLogged then
			table.insert(newTiers, normalizedTier)
		end
	end

	table.sort(newTiers)
	return newTiers
end

function TierUnlockAnalytics.getUnlockedTiersToLog(unlockedDroppers: any, loggedTiers: any): { number }
	if type(unlockedDroppers) ~= "table" then
		return {}
	end

	local tiersToLog = {}
	for _, tier in TierUnlockAnalytics.getTierUnlockSteps() do
		local isUnlocked = unlockedDroppers[tier] == true or unlockedDroppers[tostring(tier)] == true
		local wasLogged = type(loggedTiers) == "table"
			and (loggedTiers[tier] == true or loggedTiers[tostring(tier)] == true)

		if isUnlocked and not wasLogged then
			table.insert(tiersToLog, tier)
		end
	end

	return tiersToLog
end

return TierUnlockAnalytics
