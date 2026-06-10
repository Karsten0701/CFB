local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
local QuestConfig = require(ReplicatedStorage.Shared.Data.QuestConfig)
local QuestUtil = require(ReplicatedStorage.Shared.Features.Quests.QuestUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local QuestService = Knit.CreateService({
	Name = "QuestService",
	Client = {},
})

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
	local nextSlots = {}
	local changed = false

	for slotIndex, slot in categoryData.Slots do
		if type(slot) ~= "table" then
			continue
		end

		local progress = QuestUtil.computeProgress(slot.Type, slot.Target, stats, baselines)
		local nextSlot = table.clone(slot)
		nextSlot.Progress = progress
		nextSlots[slotIndex] = nextSlot
		if slot.Progress ~= progress then
			changed = true
		end
	end

	if changed then
		PlayerDataService:Set(player, { "Quests", category, "Slots" }, nextSlots)
	end
end

local function incrementCategoryStat(player: Player, statKey: string, amount: number)
	if amount <= 0 then
		return
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	for _, category in QuestConfig.Categories do
		PlayerDataService:Update(player, { "Quests", category, "Stats", statKey }, function(current: number)
			return math.max(math.floor(tonumber(current) or 0), 0) + amount
		end)
		refreshCategoryProgress(PlayerDataService, player, category)
	end
end

function QuestService:TrackYenEarned(player: Player, amount: number)
	self:EnsureQuestsFresh(player)
	incrementCategoryStat(player, "YenEarned", amount)
end

function QuestService:TrackUnitsBought(player: Player, amount: number)
	self:EnsureQuestsFresh(player)
	incrementCategoryStat(player, "UnitsBought", amount)
end

function QuestService:TrackManaCollected(player: Player, amount: number)
	self:EnsureQuestsFresh(player)
	incrementCategoryStat(player, "ManaCollected", amount)
end

local function rollCategoryQuests(PlayerDataService, player: Player, category: string, now: number)
	local periodId = QuestUtil.getPeriodId(category, now)
	local periodEnd = QuestUtil.getPeriodEnd(category, now)
	local liveStats = getLiveStats(PlayerDataService, player, PlayerDataService:GetPlaytimeSeconds(player))
	local highestTier = liveStats.HighestTier
	local units = PlayerDataService:GetUnits(player)
	local unitCount = if type(units) == "table" then #units else 0
	local slots = QuestUtil.rollQuestSlots(player.UserId, category, periodId, highestTier, unitCount)
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
			or (tonumber(categoryData.PeriodEnd) or 0) <= now
			or type(firstSlot) ~= "table"
			or firstSlot.QuestId == ""
			or type(categoryData.Stats) ~= "table"

		if needsRoll then
			rollCategoryQuests(PlayerDataService, player, category, now)
		else
			if categoryData.PeriodEnd ~= periodEnd then
				PlayerDataService:Set(player, { "Quests", category, "PeriodEnd" }, periodEnd)
			end
			migrateLegacyPeriodStats(PlayerDataService, player, category)
			refreshCategoryProgress(PlayerDataService, player, category)
		end
	end
end

function QuestService:GetProgress(player: Player, category: string, slotIndex: number): number
	self:EnsureQuestsFresh(player)

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local slot = PlayerDataService:Get(player, { "Quests", category, "Slots", slotIndex })
	if type(slot) ~= "table" then
		return 0
	end

	return math.max(math.floor(tonumber(slot.Progress) or 0), 0)
end

function QuestService:IsComplete(player: Player, category: string, slotIndex: number): boolean
	self:EnsureQuestsFresh(player)
	refreshCategoryProgress(Knit.GetService("PlayerDataService"), player, category)

	local PlayerDataService = Knit.GetService("PlayerDataService")
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
	local highestTier = CapsuleUtil.getHighestUnitTier(units)
	local resolved = QuestUtil.resolveRewardAmount(reward, highestTier, category)
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
	return true, nil, QuestUtil.formatGrantedRewardText(resolvedReward)
end

function QuestService:KnitStart()
	local Players = game:GetService("Players")
	local PlayerDataService = Knit.GetService("PlayerDataService")

	local function bindPlayer(player: Player)
		task.spawn(function()
			PlayerDataService:WaitForData(player)

			PlayerDataService:Observe(player, "PlaytimeSeconds", function()
				self:EnsureQuestsFresh(player)
			end)

			PlayerDataService:Observe(player, "Units", function()
				self:EnsureQuestsFresh(player)
			end)
		end)
	end

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)

	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in Players:GetPlayers() do
				pcall(function()
					self:EnsureQuestsFresh(player)
				end)
			end
		end
	end)
end

return QuestService
