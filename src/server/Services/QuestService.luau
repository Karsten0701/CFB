local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
local EventUtil = require(ReplicatedStorage.Shared.Features.Events.EventUtil)
local QuestConfig = require(ReplicatedStorage.Shared.Data.QuestConfig)
local QuestUtil = require(ReplicatedStorage.Shared.Features.Quests.QuestUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Knit = require(ReplicatedStorage.Packages.knit)
local TierUnlockAnalytics = require(script.Parent.Parent.Features.Analytics.TierUnlockAnalytics)

local QuestService = Knit.CreateService({
	Name = "QuestService",
	Client = {},
})

local QUEST_STAT_FLUSH_DELAY = 1
local pendingQuestStats: { [Player]: { [string]: number } } = {}
local questStatFlushScheduled: { [Player]: boolean } = {}

local function areQuestsUnlocked(PlayerDataService, player: Player): boolean
	return math.max(math.floor(tonumber(PlayerDataService:Get(player, "Rebirths")) or 0), 0) >= 1
end

local function getCategoryStats(categoryData: any): { [string]: any }
	if type(categoryData) ~= "table" or type(categoryData.Stats) ~= "table" then
		return QuestUtil.createPeriodStats()
	end

	return {
		YenEarned = math.max(math.floor(tonumber(categoryData.Stats.YenEarned) or 0), 0),
		UnitsBought = math.max(math.floor(tonumber(categoryData.Stats.UnitsBought) or 0), 0),
		ManaCollected = math.max(math.floor(tonumber(categoryData.Stats.ManaCollected) or 0), 0),
	}
end

local function getQuestYenMultiplier(player: Player): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local multiplier = 1

	pcall(function()
		local MonetizationService = Knit.GetService("MonetizationService")
		if MonetizationService:OwnsGamePassOnly(player, "DoubleYen") then
			multiplier *= 2
		end
		if MonetizationService:OwnsProductEntitlement(player, "DoubleYen") then
			multiplier *= 2
		end
	end)

	local rebirths = math.max(math.floor(PlayerDataService:Get(player, "Rebirths") or 0), 0)
	local rebirthConfig = TycoonConfig.Rebirth or {}
	multiplier *= (rebirthConfig.BaseYenMultiplier or 1) + rebirths * (rebirthConfig.YenMultiplierPerRebirth or 0)
	multiplier *= EventUtil.getEffectMultiplier("YenMultiplier", 1)

	local tutorialBoostEndsAt = math.max(math.floor(PlayerDataService:Get(player, "TutorialBoostEndsAt") or 0), 0)
	if tutorialBoostEndsAt > os.time() then
		local tutorialConfig = TycoonConfig.Tutorial or {}
		multiplier *= math.max(tonumber(tutorialConfig.RewardMultiplier) or 2, 1)
	end

	pcall(function()
		local PotionService = Knit.GetService("PotionService")
		multiplier *= PotionService:GetPotionMultiplier(player, "YenMultiplier")
	end)

	return math.max(multiplier, 1)
end

local function getLiveStats(PlayerDataService, player: Player, playtimeSeconds: number?)
	local units = PlayerDataService:GetUnits(player)
	return {
		PlaytimeSeconds = playtimeSeconds or PlayerDataService:GetPlaytimeSeconds(player),
		HighestTier = CapsuleUtil.getHighestUnitTier(units),
	}
end

local function getProgressStats(PlayerDataService, player: Player, category: string, playtimeSeconds: number?)
	local quests = PlayerDataService:Get(player, "Quests")
	local categoryData = if type(quests) == "table" then quests[category] else nil
	local periodStats = getCategoryStats(categoryData)
	local liveStats = getLiveStats(PlayerDataService, player, playtimeSeconds)

	return {
		YenEarned = periodStats.YenEarned,
		UnitsBought = periodStats.UnitsBought,
		ManaCollected = periodStats.ManaCollected,
		PlaytimeSeconds = liveStats.PlaytimeSeconds,
		HighestTier = liveStats.HighestTier,
	}
end

local function migrateLegacyPeriodStats(PlayerDataService, player: Player, category: string)
	local quests = PlayerDataService:Get(player, "Quests")
	if type(quests) ~= "table" then
		return
	end

	local categoryData = quests[category]
	if type(categoryData) ~= "table" then
		return
	end

	local baselines = categoryData.Baselines
	if type(baselines) ~= "table" then
		return
	end

	local hasLegacyBaselines = baselines.LifetimeYen ~= nil
		or baselines.TotalUnitsPurchased ~= nil
		or baselines.ManaCollected ~= nil
	if not hasLegacyBaselines then
		return
	end

	local stats = getCategoryStats(categoryData)
	if stats.YenEarned > 0 or stats.UnitsBought > 0 or stats.ManaCollected > 0 then
		return
	end

	local lifetimeYen = math.max(math.floor(tonumber(PlayerDataService:Get(player, "LifetimeYen")) or 0), 0)
	local totalUnits = math.max(math.floor(tonumber(PlayerDataService:Get(player, "TotalUnitsPurchased")) or 0), 0)
	local totalMana = math.max(math.floor(tonumber(quests.TotalManaCollected) or 0), 0)

	local yenEarned = math.max(lifetimeYen - math.max(math.floor(tonumber(baselines.LifetimeYen) or 0), 0), 0)
	local unitsBought = math.max(totalUnits - math.max(math.floor(tonumber(baselines.TotalUnitsPurchased) or 0), 0), 0)
	local manaCollected = math.max(totalMana - math.max(math.floor(tonumber(baselines.ManaCollected) or 0), 0), 0)

	if yenEarned == 0 and unitsBought == 0 and manaCollected == 0 then
		return
	end

	PlayerDataService:Set(player, { "Quests", category, "Stats" }, {
		YenEarned = yenEarned,
		UnitsBought = unitsBought,
		ManaCollected = manaCollected,
	})
end

local function refreshCategoryProgress(PlayerDataService, player: Player, category: string, playtimeSeconds: number?)
	local quests = PlayerDataService:Get(player, "Quests")
	if type(quests) ~= "table" then
		return
	end

	local categoryData = quests[category]
	if type(categoryData) ~= "table" or type(categoryData.Slots) ~= "table" then
		return
	end

	local stats = getProgressStats(PlayerDataService, player, category, playtimeSeconds)
	local baselines = categoryData.Baselines or {}
	local units = PlayerDataService:GetUnits(player)
	local rewardContext = {
		units = units,
		yenMultiplier = getQuestYenMultiplier(player),
	}
	local nextSlots = {}
	local changed = false

	for slotIndex, slot in categoryData.Slots do
		if type(slot) ~= "table" then
			continue
		end

		local progress = QuestUtil.computeProgress(slot.Type, slot.Target, stats, baselines)
		local nextSlot = QuestUtil.syncSlotReward(table.clone(slot), rewardContext, category)
		nextSlot.Progress = progress
		nextSlots[slotIndex] = nextSlot

		if slot.Progress ~= progress then
			changed = true
		end

		local oldReward = if type(slot.Reward) == "table" then slot.Reward else {}
		local newReward = if type(nextSlot.Reward) == "table" then nextSlot.Reward else {}
		if oldReward.Amount ~= newReward.Amount or oldReward.RewardTier ~= newReward.RewardTier then
			changed = true
		end
	end

	if changed then
		PlayerDataService:Set(player, { "Quests", category, "Slots" }, nextSlots)
	end
end

local function ensurePlaytimeBaseline(PlayerDataService, player: Player, category: string)
	local baselines = PlayerDataService:Get(player, { "Quests", category, "Baselines" })
	if type(baselines) == "table" and baselines.PlaytimeSeconds ~= nil then
		return
	end

	local liveStats = getLiveStats(PlayerDataService, player, PlayerDataService:GetPlaytimeSeconds(player))
	PlayerDataService:Set(
		player,
		{ "Quests", category, "Baselines", "PlaytimeSeconds" },
		QuestUtil.createBaselines(liveStats).PlaytimeSeconds
	)
end

function QuestService:RefreshPlaytimeProgress(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	if not areQuestsUnlocked(PlayerDataService, player) then
		return
	end

	local playtimeSeconds = PlayerDataService:GetPlaytimeSeconds(player)
	for _, category in QuestConfig.Categories do
		ensurePlaytimeBaseline(PlayerDataService, player, category)
		refreshCategoryProgress(PlayerDataService, player, category, playtimeSeconds)
	end
end

local function incrementCategoryStatNow(player: Player, statKey: string, amount: number)
	if amount <= 0 then
		return
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	if not areQuestsUnlocked(PlayerDataService, player) then
		return
	end

	for _, category in QuestConfig.Categories do
		PlayerDataService:Update(player, { "Quests", category, "Stats", statKey }, function(current: number)
			return math.max(math.floor(tonumber(current) or 0), 0) + amount
		end)
		refreshCategoryProgress(PlayerDataService, player, category)
	end
end

function QuestService:FlushPendingStats(player: Player)
	questStatFlushScheduled[player] = nil
	local pending = pendingQuestStats[player]
	if not pending then
		return
	end

	pendingQuestStats[player] = nil
	for statKey, amount in pending do
		incrementCategoryStatNow(player, statKey, amount)
	end
end

function QuestService:QueueStat(player: Player, statKey: string, amount: number)
	amount = math.max(math.floor(tonumber(amount) or 0), 0)
	if amount <= 0 then
		return
	end

	pendingQuestStats[player] = pendingQuestStats[player] or {}
	pendingQuestStats[player][statKey] = (pendingQuestStats[player][statKey] or 0) + amount

	if questStatFlushScheduled[player] then
		return
	end

	questStatFlushScheduled[player] = true
	task.delay(QUEST_STAT_FLUSH_DELAY, function()
		if player.Parent then
			self:FlushPendingStats(player)
		else
			pendingQuestStats[player] = nil
			questStatFlushScheduled[player] = nil
		end
	end)
end

function QuestService:TrackYenEarned(player: Player, amount: number)
	self:QueueStat(player, "YenEarned", amount)
end

function QuestService:TrackUnitsBought(player: Player, amount: number)
	self:QueueStat(player, "UnitsBought", amount)
end

function QuestService:TrackManaCollected(player: Player, amount: number)
	self:QueueStat(player, "ManaCollected", amount)
end

local function rollCategoryQuests(PlayerDataService, player: Player, category: string, now: number)
	local periodId = QuestUtil.getPeriodId(category, now)
	local periodEnd = QuestUtil.getPeriodEnd(category, now)
	local liveStats = getLiveStats(PlayerDataService, player, PlayerDataService:GetPlaytimeSeconds(player))
	local units = PlayerDataService:GetUnits(player)
	local yenMultiplier = getQuestYenMultiplier(player)
	local slots = QuestUtil.rollQuestSlots(player.UserId, category, periodId, units, yenMultiplier)
	local periodStats = QuestUtil.createPeriodStats()
	local baselines = QuestUtil.createBaselines(liveStats)

	for _, slot in slots do
		slot.Progress = QuestUtil.computeProgress(slot.Type, slot.Target, periodStats, baselines)
	end

	PlayerDataService:Set(player, { "Quests", category }, {
		PeriodId = periodId,
		PeriodEnd = periodEnd,
		Baselines = baselines,
		Stats = periodStats,
		Slots = slots,
	})
end

function QuestService:EnsureQuestsFresh(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	if not areQuestsUnlocked(PlayerDataService, player) then
		return
	end

	local now = os.time()
	local quests = PlayerDataService:Get(player, "Quests")
	if type(quests) ~= "table" then
		PlayerDataService:Set(player, "Quests", {
			TotalManaCollected = 0,
			Hourly = { PeriodId = "", PeriodEnd = 0, Baselines = {}, Stats = QuestUtil.createPeriodStats(), Slots = {} },
			Daily = { PeriodId = "", PeriodEnd = 0, Baselines = {}, Stats = QuestUtil.createPeriodStats(), Slots = {} },
			Weekly = { PeriodId = "", PeriodEnd = 0, Baselines = {}, Stats = QuestUtil.createPeriodStats(), Slots = {} },
		})
		quests = PlayerDataService:Get(player, "Quests")
	end

	for _, category in QuestConfig.Categories do
		local categoryData = if type(quests) == "table" then quests[category] else nil
		local periodId = QuestUtil.getPeriodId(category, now)
		local periodEnd = QuestUtil.getPeriodEnd(category, now)
		local firstSlot = if type(categoryData) == "table" and type(categoryData.Slots) == "table"
			then categoryData.Slots[1]
			else nil
		local needsRoll = type(categoryData) ~= "table"
			or categoryData.PeriodId ~= periodId
			or type(firstSlot) ~= "table"
			or firstSlot.QuestId == ""
			or type(categoryData.Stats) ~= "table"

		if needsRoll then
			rollCategoryQuests(PlayerDataService, player, category, now)
		else
			if (tonumber(categoryData.PeriodEnd) or 0) ~= periodEnd then
				PlayerDataService:Set(player, { "Quests", category, "PeriodEnd" }, periodEnd)
			end
			migrateLegacyPeriodStats(PlayerDataService, player, category)
			ensurePlaytimeBaseline(PlayerDataService, player, category)
			refreshCategoryProgress(PlayerDataService, player, category)
		end
	end
end

function QuestService:GetProgress(player: Player, category: string, slotIndex: number): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if not areQuestsUnlocked(PlayerDataService, player) then
		return 0
	end
	self:EnsureQuestsFresh(player)

	local slot = PlayerDataService:Get(player, { "Quests", category, "Slots", slotIndex })
	if type(slot) ~= "table" then
		return 0
	end

	return math.max(math.floor(tonumber(slot.Progress) or 0), 0)
end

function QuestService:IsComplete(player: Player, category: string, slotIndex: number): boolean
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if not areQuestsUnlocked(PlayerDataService, player) then
		return false
	end
	self:EnsureQuestsFresh(player)
	refreshCategoryProgress(PlayerDataService, player, category)

	local slot = PlayerDataService:Get(player, { "Quests", category, "Slots", slotIndex })
	if type(slot) ~= "table" then
		return false
	end

	local progress = math.max(math.floor(tonumber(slot.Progress) or 0), 0)
	return QuestUtil.isQuestComplete(slot.Type, slot.Target, progress)
end

local function grantReward(player: Player, reward: { [string]: any }, category: string): (boolean, string?, { [string]: any }?)
	if type(reward) ~= "table" then
		return false, "Invalid reward", nil
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local units = PlayerDataService:GetUnits(player)
	local resolved = QuestUtil.resolveRewardAmount(reward, {
		units = units,
		yenMultiplier = getQuestYenMultiplier(player),
	}, category)
	local kind = resolved.Kind

	if kind == "Yen" then
		local amount = math.max(math.floor(tonumber(resolved.Amount) or 0), 0)
		if amount <= 0 then
			return false, "Invalid yen reward", nil
		end

		PlayerDataService:AddYen(player, amount)
		return true, nil, resolved
	end

	if kind == "Potion" then
		local PotionService = Knit.GetService("PotionService")
		local potionType = resolved.PotionType
		local amount = math.max(math.floor(tonumber(resolved.Amount) or 0), 0)
		if not potionType or amount <= 0 then
			return false, "Invalid potion reward", nil
		end

		if not PotionService:AddPotions(player, potionType, amount) then
			return false, "Failed to grant potion", nil
		end

		return true, nil, resolved
	end

	if kind == "UnitTier" then
		local TycoonService = Knit.GetService("TycoonService")
		local tier = math.max(math.floor(tonumber(resolved.Tier) or 1), 1)
		local amount = math.max(math.floor(tonumber(resolved.Amount) or 1), 1)

		if not TycoonService:GrantUnitAtTier(player, tier, amount) then
			return false, "Failed to grant unit", nil
		end

		return true, nil, resolved
	end

	return false, "Unknown reward", nil
end

function QuestService.Client:ClaimQuest(player: Player, category: string, slotIndex: number): (boolean, string?, string?)
	if category ~= "Hourly" and category ~= "Daily" and category ~= "Weekly" then
		return false, "Invalid category", nil
	end

	slotIndex = math.floor(tonumber(slotIndex) or 0)
	if slotIndex < 1 or slotIndex > QuestConfig.QuestCount then
		return false, "Invalid slot", nil
	end

	local QuestServiceServer = Knit.GetService("QuestService")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if not areQuestsUnlocked(PlayerDataService, player) then
		return false, "Locked", nil
	end
	QuestServiceServer:EnsureQuestsFresh(player)
	refreshCategoryProgress(PlayerDataService, player, category)

	local slot = PlayerDataService:Get(player, { "Quests", category, "Slots", slotIndex })
	if type(slot) ~= "table" then
		return false, "Missing quest", nil
	end

	if slot.Claimed == true then
		return false, "Already claimed", nil
	end

	local stats = getProgressStats(PlayerDataService, player, category)
	local baselines = PlayerDataService:Get(player, { "Quests", category, "Baselines" }) or {}
	local progress = QuestUtil.computeProgress(slot.Type, slot.Target, stats, baselines)
	if not QuestUtil.isQuestComplete(slot.Type, slot.Target, progress) then
		return false, "Not complete", nil
	end

	local granted, grantErr, resolvedReward = grantReward(player, slot.Reward, category)
	if not granted then
		return false, grantErr or "Grant failed", nil
	end

	PlayerDataService:Set(player, { "Quests", category, "Slots", slotIndex, "Claimed" }, true)
	PlayerDataService:Set(player, { "Quests", category, "Slots", slotIndex, "Progress" }, progress)
	local claimCount = math.max(math.floor(PlayerDataService:Get(player, { "Analytics", "QuestClaimsFunnelLogged" }) or 0), 0) + 1
	if TierUnlockAnalytics.logQuestClaimed(player, claimCount) then
		PlayerDataService:Set(player, { "Analytics", "QuestClaimsFunnelLogged" }, claimCount)
	end
	return true, nil, QuestUtil.formatGrantedRewardText(resolvedReward)
end

function QuestService.Client:LogQuestOpened(player: Player): boolean
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	if not areQuestsUnlocked(PlayerDataService, player) then
		return false
	end
	if PlayerDataService:Get(player, { "Analytics", "QuestOpenedFunnelLogged" }) == true then
		return true
	end

	if TierUnlockAnalytics.logQuestOpened(player) then
		PlayerDataService:Set(player, { "Analytics", "QuestOpenedFunnelLogged" }, true)
		return true
	end

	return false
end

function QuestService:KnitStart()
	local Players = game:GetService("Players")
	local PlayerDataService = Knit.GetService("PlayerDataService")

	Players.PlayerRemoving:Connect(function(player)
		self:FlushPendingStats(player)
		pendingQuestStats[player] = nil
		questStatFlushScheduled[player] = nil
	end)

	local function bindPlayer(player: Player)
		task.spawn(function()
			PlayerDataService:WaitForData(player)

			PlayerDataService:Observe(player, "PlaytimeSeconds", function()
				if areQuestsUnlocked(PlayerDataService, player) then
					self:RefreshPlaytimeProgress(player)
				end
			end)

			PlayerDataService:Observe(player, "Units", function()
				if areQuestsUnlocked(PlayerDataService, player) then
					self:EnsureQuestsFresh(player)
				end
			end)

			PlayerDataService:Observe(player, "Rebirths", function()
				if areQuestsUnlocked(PlayerDataService, player) then
					self:EnsureQuestsFresh(player)
				end
			end)
		end)
	end

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)

	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Players:GetPlayers() do
				pcall(function()
					if areQuestsUnlocked(PlayerDataService, player) then
						self:EnsureQuestsFresh(player)
						self:RefreshPlaytimeProgress(player)
					end
				end)
			end
		end
	end)
end

return QuestService
