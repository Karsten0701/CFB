local AnalyticsService = game:GetService("AnalyticsService")

local TierUnlockAnalytics = {}

local FIRST_JOIN_FUNNEL_NAME = "FirstJoin"
local TIER_UNLOCK_FUNNEL_NAME = "TierUnlocks"
local TUTORIAL_COMPLETE_FUNNEL_NAME = "TutorialComplete"

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
	if tier < 1 or tier > 100 then
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

function TierUnlockAnalytics.logTutorialCompleted(player: Player): boolean
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, TUTORIAL_COMPLETE_FUNNEL_NAME, nil, 1, "Completed Tutorial")
	end)

	if not ok then
		warn("[TierUnlockAnalytics] Failed to log tutorial complete funnel step:", err)
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

return TierUnlockAnalytics
