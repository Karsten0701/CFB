local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)

local TierUnlockAnalytics = {}

local FIRST_JOIN_FUNNEL_NAME = "FirstJoin"
local TIER_UNLOCK_FUNNEL_NAME = "TierUnlocks"
local TUTORIAL_FUNNEL_NAME = "Tutorial"
local SESSION_TIME_FUNNEL_NAME = "SessionTime"
local PLAYTIME_FUNNEL_NAME = "Playtime"
local REBIRTH_FUNNEL_NAME = "Rebirths"
local QUEST_FUNNEL_NAME = "Quests"

local tierUnlockSteps: { number }? = nil
local tierUnlockStepByTier: { [number]: number } = {}

local function rebuildTierUnlockStepMap()
	tierUnlockSteps = {}
	table.clear(tierUnlockStepByTier)

	for tier in AnimeDroppers.Tiers do
		local normalizedTier = math.floor(tonumber(tier) or 0)
		if normalizedTier >= 1 then
			table.insert(tierUnlockSteps, normalizedTier)
		end
	end

	table.sort(tierUnlockSteps)

	for step, tier in tierUnlockSteps do
		tierUnlockStepByTier[tier] = step
	end
end

rebuildTierUnlockStepMap()

local function getStepName(tier: number): string
	return "Unlocked Tier " .. tostring(tier)
end

local function getMinuteLabel(minutes: number): string
	minutes = math.max(math.floor(tonumber(minutes) or 0), 0)
	if minutes == 0 then
		return "0 Minutes"
	end

	local suffix = if minutes == 1 then "Minute" else "Minutes"
	return "Played " .. tostring(minutes) .. " " .. suffix
end

local function getMilestoneStep(milestones: { number }, milestone: number): number
	for step, value in milestones do
		if value == milestone then
			return step
		end
	end

	return math.max(math.floor(tonumber(milestone) or 0) + 1, 1)
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

	local step = tierUnlockStepByTier[tier]
	if not step then
		return false
	end

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, TIER_UNLOCK_FUNNEL_NAME, nil, step, getStepName(tier))
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log tier unlock funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.getTierUnlockSteps(): { number }
	if not tierUnlockSteps then
		rebuildTierUnlockStepMap()
	end

	return tierUnlockSteps
end

function TierUnlockAnalytics.logTutorialInProgress(player: Player): boolean
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, TUTORIAL_FUNNEL_NAME, nil, 1, "Tutorial Not Completed")
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log tutorial in-progress funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logTutorialCompleted(player: Player): boolean
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, TUTORIAL_FUNNEL_NAME, nil, 2, "Tutorial Completed")
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log tutorial complete funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.getSessionTimeMilestones(): { number }
	local milestones = { 0 }

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
	if minutes < 0 then
		return false
	end

	local milestones = TierUnlockAnalytics.getSessionTimeMilestones()
	local resolvedStep = math.max(math.floor(tonumber(step) or getMilestoneStep(milestones, minutes)), 1)

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			SESSION_TIME_FUNNEL_NAME,
			nil,
			resolvedStep,
			getMinuteLabel(minutes)
		)
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log session time funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logPlaytimeReached(player: Player, minutes: number, step: number?): boolean
	minutes = math.floor(tonumber(minutes) or 0)
	if minutes < 0 then
		return false
	end

	local milestones = TierUnlockAnalytics.getPlaytimeMilestones()
	local resolvedStep = math.max(math.floor(tonumber(step) or getMilestoneStep(milestones, minutes)), 1)

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			PLAYTIME_FUNNEL_NAME,
			nil,
			resolvedStep,
			getMinuteLabel(minutes)
		)
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log playtime funnel step:", err)
	end

	return ok
end

function TierUnlockAnalytics.logRebirthReached(player: Player, rebirths: number): boolean
	rebirths = math.floor(tonumber(rebirths) or 0)
	if rebirths < 0 then
		return false
	end

	local step = rebirths + 1
	local label = if rebirths == 0 then "0 Rebirths" else "Reached Rebirth " .. tostring(rebirths)

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, REBIRTH_FUNNEL_NAME, nil, step, label)
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

function TierUnlockAnalytics.logQuestClaimed(player: Player, claimCount: number): boolean
	claimCount = math.max(math.floor(tonumber(claimCount) or 0), 1)
	local step = claimCount + 2
	local suffix = if claimCount == 1 then "" else "s"
	local label = "Claimed " .. tostring(claimCount) .. " Quest" .. suffix

	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, QUEST_FUNNEL_NAME, nil, step, label)
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
