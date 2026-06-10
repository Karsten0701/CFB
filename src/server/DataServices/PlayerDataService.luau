local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local RebirthUpgrades = require(ReplicatedStorage.Shared.Data.RebirthUpgrades)
local YenUpgrades = require(ReplicatedStorage.Shared.Data.YenUpgrades)
local QuestConfig = require(ReplicatedStorage.Shared.Data.QuestConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local DataService = require(ReplicatedStorage.Packages.dataservice).server
local GameShutdown = require(script.Parent.Parent.Modules.GameShutdown)
local Knit = require(ReplicatedStorage.Packages.knit)
local DataTemplate = require(script.Parent.DataTemplate)
local TierUnlockAnalytics = require(script.Parent.Parent.Features.Analytics.TierUnlockAnalytics)

type Path = string | { string | number }

local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {},
})

local leaderstatValues: {
	[Player]: { Yen: StringValue, Units: StringValue, Rebirths: StringValue },
} = {}
local playtimeSessionStartedAt: { [Player]: number } = {}
local recordingLeaderboardAchievedAt = false

local PLAYTIME_PERSIST_INTERVAL = 60
local MAX_REASONABLE_PLAYTIME_SECONDS = 10 * 365 * 24 * 60 * 60

local LEADERBOARD_STAT_PATHS = {
	Rebirths = true,
	LifetimeYen = true,
	TotalUnitsBought = true,
	PlaytimeSeconds = true,
}

local function migrateNumberFieldInData(data: { [string]: any }, oldPath: string, newPath: string, defaultValue: number)
	if type(data[newPath]) == "number" then
		return
	end

	data[newPath] = if type(data[oldPath]) == "number" then data[oldPath] else defaultValue
end

local function isValidVolume(volume: any): boolean
	return type(volume) == "number" and volume == volume and volume >= 0 and volume <= 1
end

local function deepEqual(left: any, right: any): boolean
	if left == right then
		return true
	end

	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end

	for key, value in left do
		if not deepEqual(value, right[key]) then
			return false
		end
	end

	for key in right do
		if left[key] == nil then
			return false
		end
	end

	return true
end

local function getStarterUnits(): { { Tier: number } }
	local configuredStarterUnits = TycoonConfig.StarterUnits
	if type(configuredStarterUnits) ~= "table" then
		configuredStarterUnits = { { Tier = 1 } }
	end

	local starterUnits = {}
	for _, unit in configuredStarterUnits do
		if type(unit) ~= "table" then
			continue
		end

		table.insert(starterUnits, {
			Tier = unit.Tier or 1,
		})
	end

	if #starterUnits <= 0 then
		table.insert(starterUnits, { Tier = 1 })
	end

	return starterUnits
end

local function normalizeUnits(units: any): { { Tier: number, Slot: number } }
	local normalizedUnits = {}
	if type(units) ~= "table" then
		return normalizedUnits
	end

	for _, unit in units do
		if type(unit) ~= "table" then
			continue
		end

		local tier = math.clamp(math.floor(tonumber(unit.Tier) or 1), 1, AnimeDroppers.MaxTier)
		if AnimeDroppers.Tiers[tier] then
			table.insert(normalizedUnits, {
				Tier = tier,
				Slot = tonumber(unit.Slot) or math.huge,
			})
		end
	end

	table.sort(normalizedUnits, function(left, right)
		if left.Tier == right.Tier then
			return left.Slot < right.Slot
		end

		return left.Tier > right.Tier
	end)

	for slot, unit in normalizedUnits do
		unit.Slot = slot
	end

	return normalizedUnits
end

local function normalizeUnlockedAnimeDroppers(unlockedDroppers: any, units: { { Tier: number } }): { [number]: boolean }
	local normalized = {}

	if type(unlockedDroppers) == "table" then
		for tier, unlocked in unlockedDroppers do
			local normalizedTier = math.floor(tonumber(tier) or 0)
			if unlocked == true and AnimeDroppers.Tiers[normalizedTier] then
				normalized[normalizedTier] = true
			end
		end
	end

	local mergeTargets = {}
	for tier, tierData in AnimeDroppers.Tiers do
		local targetTier = tierData and tierData.MergeInto
		if type(targetTier) == "number" and AnimeDroppers.Tiers[targetTier] then
			mergeTargets[targetTier] = mergeTargets[targetTier] or {}
			table.insert(mergeTargets[targetTier], tier)
		end
	end

	local visitedTiers = {}
	local function unlockTierAndMergeRequirements(tier: number)
		if not AnimeDroppers.Tiers[tier] or visitedTiers[tier] == true then
			return
		end

		visitedTiers[tier] = true
		normalized[tier] = true
		local sourceTiers = mergeTargets[tier]
		if not sourceTiers then
			return
		end

		for _, sourceTier in sourceTiers do
			unlockTierAndMergeRequirements(sourceTier)
		end
	end

	local alreadyUnlockedTiers = {}
	for tier in normalized do
		table.insert(alreadyUnlockedTiers, tier)
	end
	for _, tier in alreadyUnlockedTiers do
		unlockTierAndMergeRequirements(tier)
	end

	for _, unit in units do
		local tier = math.floor(tonumber(unit.Tier) or 0)
		unlockTierAndMergeRequirements(tier)
	end

	return normalized
end

local function getRebirthTokenReward(rebirthNumber: number): number
	rebirthNumber = math.max(math.floor(rebirthNumber), 1)
	local rebirthConfig = TycoonConfig.Rebirth or {}
	local tokensPerRebirth = rebirthConfig.TokensPerRebirth
	if type(tokensPerRebirth) == "table" then
		local configuredReward = tokensPerRebirth[rebirthNumber]
		if configuredReward == nil then
			local fallbackRebirth = 0
			for configuredRebirth in tokensPerRebirth do
				local numericRebirth = math.floor(tonumber(configuredRebirth) or 0)
				if numericRebirth > fallbackRebirth and numericRebirth <= rebirthNumber then
					fallbackRebirth = numericRebirth
					configuredReward = tokensPerRebirth[configuredRebirth]
				end
			end
		end

		if configuredReward ~= nil then
			return math.max(math.floor(tonumber(configuredReward) or 0), 0)
		end
	elseif tonumber(tokensPerRebirth) then
		return math.max(math.floor(tonumber(tokensPerRebirth) or 0), 0)
	end

	local previousReward = 1
	local reward = 1

	for _ = 2, rebirthNumber do
		local nextReward = previousReward + reward
		previousReward = reward
		reward = nextReward
	end

	return reward
end

local function getTotalRebirthTokenEntitlement(rebirths: number): number
	local total = 0
	for rebirthNumber = 1, math.max(math.floor(tonumber(rebirths) or 0), 0) do
		total += getRebirthTokenReward(rebirthNumber)
	end

	return total
end

local function getSpentRebirthTokensFromData(data: { [string]: any }): number
	local upgrades = if type(data.RebirthUpgrades) == "table" then data.RebirthUpgrades else {}
	local spent = 0

	for upgradeKey, config in RebirthUpgrades do
		if type(config) ~= "table" or config.kind ~= "RebirthTokens" then
			continue
		end

		local level = math.max(math.floor(tonumber(upgrades[upgradeKey]) or 0), 0)
		for paidLevel = 0, level - 1 do
			spent += math.max(math.floor(tonumber(RebirthUpgrades.getCost(upgradeKey, paidLevel)) or 0), 0)
		end
	end

	return spent
end

local function repairRebirthTokenEntitlement(data: { [string]: any })
	data.RebirthTokens = math.max(math.floor(tonumber(data.RebirthTokens) or 0), 0)

	local expectedTotal = getTotalRebirthTokenEntitlement(data.Rebirths)
	local grantedTotal
	if data.RebirthTokenEntitlementMigrated == true then
		grantedTotal = math.max(math.floor(tonumber(data.RebirthTokenEntitlementGranted) or 0), 0)
	else
		grantedTotal = data.RebirthTokens + getSpentRebirthTokensFromData(data)
	end

	local missingTokens = expectedTotal - grantedTotal
	if missingTokens > 0 then
		data.RebirthTokens += missingTokens
		grantedTotal += missingTokens
	end

	data.RebirthTokenEntitlementGranted = math.max(grantedTotal, 0)
	data.RebirthTokenEntitlementMigrated = true
end

local function repairQuestSlot(slot: any)
	if type(slot) ~= "table" then
		return {
			QuestId = "",
			Type = "",
			Target = 1,
			Reward = { Kind = "Yen", Amount = 0 },
			Progress = 0,
			Claimed = false,
		}
	end

	slot.QuestId = if type(slot.QuestId) == "string" then slot.QuestId else ""
	slot.Type = if type(slot.Type) == "string" then slot.Type else ""
	slot.Target = math.max(math.floor(tonumber(slot.Target) or 1), 1)
	slot.Progress = math.max(math.floor(tonumber(slot.Progress) or 0), 0)
	slot.Claimed = slot.Claimed == true
	if type(slot.Reward) ~= "table" then
		slot.Reward = { Kind = "Yen", Amount = 0 }
	end

	return slot
end

local function repairQuestCategory(categoryData: any)
	if type(categoryData) ~= "table" then
		categoryData = {}
	end

	categoryData.PeriodId = if type(categoryData.PeriodId) == "string" then categoryData.PeriodId else ""
	categoryData.PeriodEnd = math.max(math.floor(tonumber(categoryData.PeriodEnd) or 0), 0)

	if type(categoryData.Baselines) ~= "table" then
		categoryData.Baselines = {}
	end

	if type(categoryData.Stats) ~= "table" then
		categoryData.Stats = {}
	end
	categoryData.Stats.YenEarned = math.max(math.floor(tonumber(categoryData.Stats.YenEarned) or 0), 0)
	categoryData.Stats.UnitsBought = math.max(math.floor(tonumber(categoryData.Stats.UnitsBought) or 0), 0)
	categoryData.Stats.ManaCollected = math.max(math.floor(tonumber(categoryData.Stats.ManaCollected) or 0), 0)

	if type(categoryData.Slots) ~= "table" then
		categoryData.Slots = {}
	end

	local slots = {}
	for slotIndex = 1, QuestConfig.QuestCount do
		slots[slotIndex] = repairQuestSlot(categoryData.Slots[slotIndex])
	end
	categoryData.Slots = slots

	return categoryData
end

local function repairQuestData(data: { [string]: any })
	if type(data.Quests) ~= "table" then
		data.Quests = {}
	end

	data.Quests.TotalManaCollected = math.max(math.floor(tonumber(data.Quests.TotalManaCollected) or 0), 0)
	data.Quests.Hourly = repairQuestCategory(data.Quests.Hourly)
	data.Quests.Daily = repairQuestCategory(data.Quests.Daily)
	data.Quests.Weekly = repairQuestCategory(data.Quests.Weekly)
end

local function ensureManaData(data: { [string]: any })
	migrateNumberFieldInData(data, "Money", "Yen", TycoonConfig.StarterYen or 0)
	migrateNumberFieldInData(data, "MagicPowerInBag", "ManaInBag", 0)
	migrateNumberFieldInData(data, "MagicPowerInDeposit", "ManaInDeposit", 0)
	migrateNumberFieldInData(data, "ManaPowerInBag", "ManaInBag", 0)
	migrateNumberFieldInData(data, "ManaPowerInDeposit", "ManaInDeposit", 0)

	if type(data.Yen) ~= "number" then
		data.Yen = TycoonConfig.StarterYen or 0
	end

	if type(data.Rebirths) ~= "number" then
		data.Rebirths = 0
	end
	data.Rebirths = math.max(math.floor(data.Rebirths), 0)

	if type(data.RebirthTokens) ~= "number" then
		data.RebirthTokens = 0
	end
	data.RebirthTokens = math.max(math.floor(data.RebirthTokens), 0)

	if type(data.LastGroupRewardClaimAt) ~= "number" then
		data.LastGroupRewardClaimAt = 0
	end
	data.LastGroupRewardClaimAt = math.max(math.floor(data.LastGroupRewardClaimAt), 0)

	if type(data.GroupLikeReminderCount) ~= "number" then
		data.GroupLikeReminderCount = 0
	end
	data.GroupLikeReminderCount = math.max(math.floor(data.GroupLikeReminderCount), 0)

	if type(data.GroupRewardLikeUnlocked) ~= "boolean" then
		local likeRequired = math.max(
			math.floor(tonumber(TycoonConfig.GroupReward and TycoonConfig.GroupReward.LikeReminderRequired) or 3),
			1
		)
		data.GroupRewardLikeUnlocked = data.GroupLikeReminderCount >= likeRequired or data.LastGroupRewardClaimAt > 0
	end

	if type(data.LastLogoutAt) ~= "number" then
		data.LastLogoutAt = 0
	end
	data.LastLogoutAt = math.max(math.floor(data.LastLogoutAt), 0)

	if type(data.FavoritePromptShown) ~= "boolean" then
		data.FavoritePromptShown = false
	end

	if type(data.ManaInBag) ~= "number" then
		data.ManaInBag = 0
	end

	if type(data.ManaInDeposit) ~= "number" then
		data.ManaInDeposit = 0
	end

	if type(data.LifetimeYen) ~= "number" then
		data.LifetimeYen = math.max(math.floor(tonumber(data.Yen) or 0), 0)
	end
	data.LifetimeYen = math.max(math.floor(data.LifetimeYen), 0)

	if type(data.TotalUnitsBought) ~= "number" then
		data.TotalUnitsBought = math.max(math.floor(tonumber(data.TotalUnitsPurchased) or 0), 0)
	end
	data.TotalUnitsBought = math.max(math.floor(data.TotalUnitsBought), 0)

	if type(data.TotalUnitsPurchased) ~= "number" then
		data.TotalUnitsPurchased = 0
	end
	data.TotalUnitsPurchased = math.max(math.floor(data.TotalUnitsPurchased), 0)

	if type(data.PlaytimeSeconds) ~= "number" then
		data.PlaytimeSeconds = 0
	end
	data.PlaytimeSeconds = math.clamp(math.floor(data.PlaytimeSeconds), 0, MAX_REASONABLE_PLAYTIME_SECONDS)

	if type(data.LeaderboardAchievedAt) ~= "table" then
		data.LeaderboardAchievedAt = {}
	end
	for statPath in LEADERBOARD_STAT_PATHS do
		local achievedAt = data.LeaderboardAchievedAt[statPath]
		if type(achievedAt) ~= "number" then
			data.LeaderboardAchievedAt[statPath] = 0
		else
			data.LeaderboardAchievedAt[statPath] = math.max(math.floor(achievedAt), 0)
		end
	end

	if type(data.ProcessedReceipts) ~= "table" then
		data.ProcessedReceipts = {}
	end

	if type(data.PurchasedProducts) ~= "table" then
		data.PurchasedProducts = {}
	end

	if type(data.GrantedGamePasses) ~= "table" then
		data.GrantedGamePasses = {}
	end

	if type(data.Potions) ~= "table" then
		data.Potions = {}
	end
	for _, potionType in { "Yen", "Mana", "Deposit" } do
		local amount = tonumber(data.Potions[potionType]) or 0
		data.Potions[potionType] = math.max(math.floor(amount), 0)
	end

	if type(data.ActivePotionBoosts) ~= "table" then
		data.ActivePotionBoosts = {}
	end
	for potionType, boost in data.ActivePotionBoosts do
		if type(boost) ~= "table" then
			data.ActivePotionBoosts[potionType] = nil
			continue
		end

		local remaining = math.max(math.floor(tonumber(boost.RemainingSeconds) or 0), 0)
		local multiplier = tonumber(boost.Multiplier) or 2
		if remaining <= 0 then
			data.ActivePotionBoosts[potionType] = nil
		else
			data.ActivePotionBoosts[potionType] = {
				RemainingSeconds = remaining,
				Multiplier = math.max(multiplier, 1),
			}
		end
	end

	if type(data.Analytics) ~= "table" then
		data.Analytics = {}
	end
	data.Analytics.FirstJoinFunnelLogged = data.Analytics.FirstJoinFunnelLogged == true
	data.Analytics.TutorialCompleteFunnelLogged = data.Analytics.TutorialCompleteFunnelLogged == true
	if type(data.Analytics.TierUnlockFunnelLogged) ~= "table" then
		data.Analytics.TierUnlockFunnelLogged = {}
	end

	if type(data.RebirthUpgrades) ~= "table" then
		data.RebirthUpgrades = {}
	end
	data.RebirthUpgrades.UnitSpawnTier = math.max(math.floor(tonumber(data.RebirthUpgrades.UnitSpawnTier) or 0), 0)
	data.RebirthUpgrades.MoreMana = math.max(math.floor(tonumber(data.RebirthUpgrades.MoreMana) or 0), 0)

	local legacyBetterMax = 0
	if data.RebirthUpgrades.BetterMaxButton ~= nil then
		legacyBetterMax = math.max(math.floor(tonumber(data.RebirthUpgrades.BetterMaxButton) or 0), 0)
	end

	if type(data.YenUpgrades) ~= "table" then
		data.YenUpgrades = {}
	end

	local betterMaxConfig = YenUpgrades.BetterMaxButton
	local betterMaxMaxLevel = if type(betterMaxConfig) == "table" then betterMaxConfig.MaxLevel or 0 else 0
	data.YenUpgrades.BetterMaxButton = math.clamp(
		math.max(
			math.max(math.floor(tonumber(data.YenUpgrades.BetterMaxButton) or 0), 0),
			legacyBetterMax
		),
		0,
		betterMaxMaxLevel
	)

	if legacyBetterMax > 0 or data.RebirthUpgrades.BetterMaxButton ~= nil then
		data.RebirthUpgrades.BetterMaxButton = nil
	end

	data.YenUpgrades.BetterGoldenDrops = math.max(math.floor(tonumber(data.YenUpgrades.BetterGoldenDrops) or 0), 0)
	data.YenUpgrades.Pickuprange = math.max(math.floor(tonumber(data.YenUpgrades.Pickuprange) or 0), 0)
	repairQuestData(data)
	repairRebirthTokenEntitlement(data)

	if type(data.Tutorial) ~= "table" then
		data.Tutorial = {}
	end
	data.Tutorial.Prompted = data.Tutorial.Prompted == true
	data.Tutorial.Accepted = data.Tutorial.Accepted == true
	data.Tutorial.Cancelled = data.Tutorial.Cancelled == true
	data.Tutorial.Completed = data.Tutorial.Completed == true
	data.Tutorial.RewardClaimed = data.Tutorial.RewardClaimed == true
	if type(data.Tutorial.Step) ~= "string" or data.Tutorial.Step == "" then
		data.Tutorial.Step = "Prompt"
	end
	local legacyTutorialStepMap = {
		SaveForSecondUnit = "BuySecondUnit",
		SaveForThirdUnit = "BuyThirdUnit",
		WaitForTier5 = "WaitForRebirthReady",
	}
	data.Tutorial.Step = legacyTutorialStepMap[data.Tutorial.Step] or data.Tutorial.Step
	if
		data.Tutorial.Completed == true
		and data.Tutorial.RewardClaimed ~= true
		and (data.Rebirths < 1 or data.RebirthUpgrades.UnitSpawnTier < 1)
	then
		data.Tutorial.Completed = false
		data.Tutorial.Accepted = true
		data.Tutorial.Cancelled = false
		data.Tutorial.Prompted = true
		data.Tutorial.Step = if data.Rebirths >= 1 then "OpenUpgrades" else "WaitForRebirthReady"
	end

	if type(data.TutorialBoostEndsAt) ~= "number" then
		data.TutorialBoostEndsAt = 0
	end
	data.TutorialBoostEndsAt = math.max(math.floor(data.TutorialBoostEndsAt), 0)

	if type(data.Settings) ~= "table" then
		data.Settings = {}
	end

	if type(data.Settings.ShowOthers) ~= "boolean" then
		data.Settings.ShowOthers = true
	end

	if type(data.Settings.ShowOtherTycoons) ~= "boolean" then
		data.Settings.ShowOtherTycoons = true
	end

	local autoMergeAt = tonumber(data.Settings.AutoMergeAt) or 100
	data.Settings.AutoMergeAt = math.clamp(math.floor(autoMergeAt), 0, 100)

	if type(data.Settings.AutoCollect) ~= "boolean" then
		data.Settings.AutoCollect = false
	end

	if type(data.Settings.AutoDeposit) ~= "boolean" then
		data.Settings.AutoDeposit = false
	end

	if type(data.Settings.GamePassSettingDisabled) ~= "table" then
		data.Settings.GamePassSettingDisabled = {}
	end
	data.Settings.GamePassSettingDisabled.AutoCollect = data.Settings.GamePassSettingDisabled.AutoCollect == true
	data.Settings.GamePassSettingDisabled.AutoDeposit = data.Settings.GamePassSettingDisabled.AutoDeposit == true

	if type(data.Settings.ShowVFX) ~= "boolean" then
		data.Settings.ShowVFX = true
	end

	if type(data.Settings.ShowManaPopup) ~= "boolean" then
		data.Settings.ShowManaPopup = true
	end

	if type(data.Settings.Sound) ~= "boolean" then
		data.Settings.Sound = true
	end

	if type(data.Settings.Music) ~= "boolean" then
		data.Settings.Music = true
	end

	if not isValidVolume(data.Settings.musicVolume) then
		data.Settings.musicVolume = 1
	end

	if not isValidVolume(data.Settings.sfxVolume) then
		data.Settings.sfxVolume = 1
	end

	data.Units = normalizeUnits(data.Units)
	if #data.Units <= 0 then
		data.Units = normalizeUnits(getStarterUnits())
	end
	data.TotalUnitsBought = math.max(data.TotalUnitsBought, math.floor(Pricing.getBaseUnitCount(data.Units)))

	data.UnlockedAnimeDroppers = normalizeUnlockedAnimeDroppers(data.UnlockedAnimeDroppers, data.Units)
end

local function syncLeaderstats(player: Player)
	local values = leaderstatValues[player]
	if not values then
		return
	end

	local yen = PlayerDataService:Get(player, "Yen") or 0
	local units = PlayerDataService:GetUnits(player)
	local rebirths = PlayerDataService:Get(player, "Rebirths") or 0

	values.Yen.Value = Pricing.formatYen(yen)
	values.Units.Value = FormatUtil.formatNumber(Pricing.getBaseUnitCount(units))
	values.Rebirths.Value = FormatUtil.formatNumber(rebirths)
end

local function setupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local yenValue = Instance.new("StringValue")
	yenValue.Name = "Yen"
	yenValue.Parent = leaderstats

	local unitsValue = Instance.new("StringValue")
	unitsValue.Name = "Units"
	unitsValue.Parent = leaderstats

	local rebirthsValue = Instance.new("StringValue")
	rebirthsValue.Name = "Rebirths"
	rebirthsValue.Parent = leaderstats

	leaderstats.Parent = player
	leaderstatValues[player] = {
		Yen = yenValue,
		Units = unitsValue,
		Rebirths = rebirthsValue,
	}

	syncLeaderstats(player)
end

function PlayerDataService:KnitInit()
	local ProfileStore = require(ReplicatedStorage.Packages._Index["leifstout_dataservice@1.0.0"].ProfileStore)
	ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
		if isCritical then
			warn("[PlayerDataService] Roblox DataStore is in a critical state; ProfileStore will retry saves.")
		else
			warn("[PlayerDataService] Roblox DataStore recovered from critical state.")
		end
	end)

	function DataService:onPlayerInit(player: Player, data: any)
		ensureManaData(data)
		playtimeSessionStartedAt[player] = os.time()
		setupLeaderstats(player)
		task.defer(function()
			local ok, QuestService = pcall(function()
				return Knit.GetService("QuestService")
			end)
			if ok and QuestService then
				QuestService:EnsureQuestsFresh(player)
			end
		end)
		if data.Analytics.FirstJoinFunnelLogged ~= true and TierUnlockAnalytics.logFirstJoin(player) then
			data.Analytics.FirstJoinFunnelLogged = true
		end

		PlayerDataService:Observe(player, "Yen", function()
			syncLeaderstats(player)
		end)

		PlayerDataService:Observe(player, "Units", function()
			syncLeaderstats(player)
		end)

		PlayerDataService:Observe(player, "Rebirths", function()
			syncLeaderstats(player)
		end)
	end

	DataService:init({
		template = DataTemplate,
		profileStoreIndex = "PLAYERDATA", --PLAYERDATA gameversion
	})
end

function PlayerDataService:KnitStart()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		if not GameShutdown.isShuttingDown() then
			pcall(function()
				PlayerDataService:PersistPlaytime(player)
				PlayerDataService:Set(player, "LastLogoutAt", os.time())
			end)
		end

		playtimeSessionStartedAt[player] = nil
		leaderstatValues[player] = nil
	end)

	task.spawn(function()
		while not GameShutdown.isShuttingDown() do
			task.wait(PLAYTIME_PERSIST_INTERVAL)
			if GameShutdown.isShuttingDown() then
				break
			end

			for _, player in game:GetService("Players"):GetPlayers() do
				pcall(function()
					PlayerDataService:PersistPlaytime(player)
				end)
			end
		end
	end)
end

function PlayerDataService:WaitForData(player: Player)
	return DataService:waitForData(player)
end

function PlayerDataService:Get(player: Player, path: Path?)
	self:WaitForData(player)
	return DataService:get(player, path)
end

local function getLeaderboardStatPath(path: Path): string?
	if type(path) == "string" then
		return if LEADERBOARD_STAT_PATHS[path] then path else nil
	end

	if type(path) == "table" and #path == 1 and type(path[1]) == "string" then
		local statPath = path[1]
		return if LEADERBOARD_STAT_PATHS[statPath] then statPath else nil
	end

	return nil
end

local function maybeRecordLeaderboardAchieved(player: Player, path: Path, oldValue: any, newValue: any)
	if recordingLeaderboardAchievedAt then
		return
	end

	local statPath = getLeaderboardStatPath(path)
	if not statPath then
		return
	end

	local previousValue = math.max(math.floor(tonumber(oldValue) or 0), 0)
	local nextValue = math.max(math.floor(tonumber(newValue) or 0), 0)
	if nextValue <= 0 or nextValue <= previousValue then
		return
	end

	recordingLeaderboardAchievedAt = true
	DataService:set(player, { "LeaderboardAchievedAt", statPath }, os.time())
	recordingLeaderboardAchievedAt = false
end

function PlayerDataService:Set(player: Player, path: Path, value: any)
	self:WaitForData(player)
	local currentValue = DataService:get(player, path)
	if deepEqual(currentValue, value) then
		return
	end

	maybeRecordLeaderboardAchieved(player, path, currentValue, value)
	DataService:set(player, path, value)
end

function PlayerDataService:Update(player: Player, path: Path, callback: (any) -> any)
	self:WaitForData(player)
	local currentValue = DataService:get(player, path)
	local nextValue = callback(currentValue)
	if deepEqual(currentValue, nextValue) then
		return currentValue
	end

	maybeRecordLeaderboardAchieved(player, path, currentValue, nextValue)
	DataService:set(player, path, nextValue)
	return nextValue
end

function PlayerDataService:GetLeaderboardAchievedAt(player: Player, statPath: string): number
	self:WaitForData(player)
	local achievedAt = self:Get(player, { "LeaderboardAchievedAt", statPath })
	if type(achievedAt) == "number" and achievedAt > 0 then
		return math.floor(achievedAt)
	end

	return 0
end

function PlayerDataService:AddYen(player: Player, amount: number)
	assert(amount >= 0, "Yen reward amount cannot be negative")

	if amount > 0 then
		self:Update(player, "LifetimeYen", function(currentLifetimeYen: number)
			return math.max(math.floor(tonumber(currentLifetimeYen) or 0), 0) + amount
		end)

		pcall(function()
			local QuestService = Knit.GetService("QuestService")
			QuestService:TrackYenEarned(player, amount)
		end)
	end

	return self:Update(player, "Yen", function(currentYen: number)
		return currentYen + amount
	end)
end

function PlayerDataService:GetRebirthTokenReward(rebirthNumber: number): number
	return getRebirthTokenReward(rebirthNumber)
end

function PlayerDataService:GetTotalRebirthTokenEntitlement(rebirths: number): number
	return getTotalRebirthTokenEntitlement(rebirths)
end

function PlayerDataService:AddRebirthTokens(player: Player, amount: number)
	local normalizedAmount = math.max(math.floor(tonumber(amount) or 0), 0)
	if normalizedAmount <= 0 then
		return self:Get(player, "RebirthTokens")
	end

	return self:Update(player, "RebirthTokens", function(currentTokens: number)
		return math.max(math.floor(tonumber(currentTokens) or 0), 0) + normalizedAmount
	end)
end

function PlayerDataService:GrantRebirthTokenReward(player: Player, rebirthNumber: number): number
	local tokenReward = getRebirthTokenReward(rebirthNumber)
	if tokenReward <= 0 then
		return 0
	end

	self:AddRebirthTokens(player, tokenReward)
	self:Update(player, "RebirthTokenEntitlementGranted", function(currentGranted: number)
		return math.max(math.floor(tonumber(currentGranted) or 0), 0) + tokenReward
	end)
	self:Set(player, "RebirthTokenEntitlementMigrated", true)
	return tokenReward
end

function PlayerDataService:AddUnitsBought(player: Player, amount: number)
	local normalizedAmount = math.floor(tonumber(amount) or 0)
	if normalizedAmount <= 0 then
		return
	end

	self:Update(player, "TotalUnitsBought", function(current: number)
		return math.max(math.floor(tonumber(current) or 0), 0) + normalizedAmount
	end)
end

function PlayerDataService:GetPlaytimeSeconds(player: Player): number
	local savedPlaytime = math.clamp(math.floor(tonumber(self:Get(player, "PlaytimeSeconds")) or 0), 0, MAX_REASONABLE_PLAYTIME_SECONDS)
	local startedAt = playtimeSessionStartedAt[player]
	if not startedAt then
		return savedPlaytime
	end

	return math.min(savedPlaytime + math.max(os.time() - startedAt, 0), MAX_REASONABLE_PLAYTIME_SECONDS)
end

function PlayerDataService:PersistPlaytime(player: Player)
	local startedAt = playtimeSessionStartedAt[player]
	if not startedAt then
		return
	end

	local now = os.time()
	local elapsed = math.max(now - startedAt, 0)
	if elapsed <= 0 then
		return
	end

	playtimeSessionStartedAt[player] = now
	self:Update(player, "PlaytimeSeconds", function(current: number)
		local nextPlaytime = math.max(math.floor(tonumber(current) or 0), 0) + elapsed
		return math.min(nextPlaytime, MAX_REASONABLE_PLAYTIME_SECONDS)
	end)
end

local function getUnitSpawnTierFromData(data: { [string]: any }): number
	local upgrades = data.RebirthUpgrades
	local level = if type(upgrades) == "table"
		then math.max(math.floor(tonumber(upgrades.UnitSpawnTier) or 0), 0)
		else 0
	return RebirthUpgrades.getUnitSpawnTier(level)
end

local function getRebirthStarterUnitsFromData(data: { [string]: any }): { { Tier: number } }
	local spawnTier = getUnitSpawnTierFromData(data)
	local rebirthConfig = TycoonConfig.Rebirth or {}
	local configuredUnits = rebirthConfig.StarterUnits or { { Tier = 1 } }
	local units = {}

	for _, unit in configuredUnits do
		if type(unit) ~= "table" then
			continue
		end

		table.insert(units, {
			Tier = math.max(tonumber(unit.Tier) or 1, spawnTier),
		})
	end

	if #units <= 0 then
		table.insert(units, { Tier = spawnTier })
	end

	return units
end

local function applyLeaderboardStatsReset(data: { [string]: any })
	data.LifetimeYen = 0
	data.Rebirths = 0
	data.TotalUnitsBought = 0
	data.PlaytimeSeconds = 0
	data.LeaderboardAchievedAt = {
		Rebirths = 0,
		LifetimeYen = 0,
		TotalUnitsBought = 0,
		PlaytimeSeconds = 0,
	}
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end

	return copy
end

local function wipeDataToTemplate(data: { [string]: any })
	for key in data do
		data[key] = nil
	end

	for key, value in deepCopy(DataTemplate) do
		data[key] = value
	end

	ensureManaData(data)
end

local function _applyRebirthProgressResetToData(data: { [string]: any })
	local rebirthConfig = TycoonConfig.Rebirth or {}
	local resetYen = if rebirthConfig.ResetYen ~= nil then rebirthConfig.ResetYen else 100
	local starterUnits = getRebirthStarterUnitsFromData(data)
	local normalizedUnits = normalizeUnits(starterUnits)
	local nextBaseUnitCount = math.max(math.floor(Pricing.getBaseUnitCount(normalizedUnits)), 0)

	data.Yen = resetYen
	data.ManaInBag = 0
	data.ManaInDeposit = 0
	data.TotalUnitsPurchased = 0
	data.RateLevel = 0
	data.Rate = rebirthConfig.ResetRate or 1
	data.Units = normalizedUnits
	data.TotalUnitsBought = nextBaseUnitCount
	data.UnlockedAnimeDroppers = normalizeUnlockedAnimeDroppers({}, normalizedUnits)
end

function PlayerDataService:ResetLeaderboardStat(player: Player, statPath: string)
	self:WaitForData(player)

	if statPath == "PlaytimeSeconds" then
		self:Set(player, statPath, 0)
		playtimeSessionStartedAt[player] = os.time()
	else
		self:Set(player, statPath, 0)
	end

	recordingLeaderboardAchievedAt = true
	self:Set(player, { "LeaderboardAchievedAt", statPath }, 0)
	recordingLeaderboardAchievedAt = false
end

function PlayerDataService:ResetLeaderboardStats(player: Player)
	recordingLeaderboardAchievedAt = true
	self:Set(player, "LifetimeYen", 0)
	self:Set(player, "Rebirths", 0)
	self:Set(player, "TotalUnitsBought", 0)
	self:Set(player, "PlaytimeSeconds", 0)
	self:Set(player, "LeaderboardAchievedAt", {
		Rebirths = 0,
		LifetimeYen = 0,
		TotalUnitsBought = 0,
		PlaytimeSeconds = 0,
	})
	recordingLeaderboardAchievedAt = false
	playtimeSessionStartedAt[player] = os.time()
end

function PlayerDataService:ResetPlayerData(player: Player)
	self:WaitForData(player)
	local userId = player.UserId

	pcall(function()
		Knit.GetService("TycoonService"):ReleaseTycoon(player)
	end)

	pcall(function()
		local LeaderboardService = Knit.GetService("LeaderboardService")
		LeaderboardService:RemoveUserFromAllBoards(userId, {
			ExcludeFromRepublish = false,
			Rerender = false,
		})
		LeaderboardService:RestoreUserToLeaderboards(userId)
	end)

	DataService:resetData(player)
end

function PlayerDataService:ResetPlayerDataByUserId(userId: number): (boolean, string?)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return false, "UserId must be greater than 0."
	end

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		self:ResetPlayerData(onlinePlayer)
		return true, nil
	end

	local profile = DataService:asyncGetProfile(userId)
	if not profile then
		return false, `No saved data found for user {userId}.`
	end

	wipeDataToTemplate(profile.Data)
	local ok, err = pcall(function()
		profile:SetAsync()
	end)
	if not ok then
		return false, tostring(err)
	end

	pcall(function()
		local LeaderboardService = Knit.GetService("LeaderboardService")
		LeaderboardService:RemoveUserFromAllBoards(userId, {
			ExcludeFromRepublish = false,
			Rerender = true,
		})
		LeaderboardService:RestoreUserToLeaderboards(userId)
	end)

	return true, nil
end

function PlayerDataService:ResetLeaderboardStatsByUserId(userId: number): (boolean, string?)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return false, "UserId must be greater than 0."
	end

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		self:WaitForData(onlinePlayer)
		self:ResetLeaderboardStats(onlinePlayer)
		return true, nil
	end

	local profile = DataService:asyncGetProfile(userId)
	if not profile then
		return false, `No saved data found for user {userId}.`
	end

	applyLeaderboardStatsReset(profile.Data)
	local ok, err = pcall(function()
		profile:SetAsync()
	end)
	if not ok then
		return false, tostring(err)
	end

	return true, nil
end

function PlayerDataService:TrySpendYen(player: Player, amount: number): boolean
	if amount < 0 then
		return false
	end

	local currentYen = self:Get(player, "Yen")
	if currentYen < amount then
		return false
	end

	self:Set(player, "Yen", currentYen - amount)
	return true
end

function PlayerDataService:AddManaToBag(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	self:Update(player, "ManaInBag", function(current: number)
		return current + amount
	end)
end

function PlayerDataService:DepositMana(player: Player): number
	local bagAmount = self:Get(player, "ManaInBag") or 0
	if bagAmount <= 0 then
		return 0
	end

	local depositAmount = self:Get(player, "ManaInDeposit") or 0
	self:Set(player, "ManaInBag", 0)
	self:Set(player, "ManaInDeposit", depositAmount + bagAmount)

	return bagAmount
end

function PlayerDataService:GetUnits(player: Player): { { Tier: number, Slot: number } }
	return self:Get(player, "Units") or {}
end

function PlayerDataService:SetUnits(player: Player, units: { { Tier: number } }, options: { resetUnlocks: boolean }?)
	local currentUnits = self:GetUnits(player)
	local currentBaseUnitCount = math.max(math.floor(Pricing.getBaseUnitCount(currentUnits)), 0)
	local normalizedUnits = normalizeUnits(units)
	local nextBaseUnitCount = math.max(math.floor(Pricing.getBaseUnitCount(normalizedUnits)), 0)
	local gainedBaseUnits = nextBaseUnitCount - currentBaseUnitCount
	local resetUnlocks = options ~= nil and options.resetUnlocks == true

	if gainedBaseUnits > 0 then
		self:Update(player, "TotalUnitsBought", function(current: number)
			return math.max(math.floor(tonumber(current) or 0), 0) + gainedBaseUnits
		end)
	elseif nextBaseUnitCount < currentBaseUnitCount then
		self:Set(player, "TotalUnitsPurchased", 0)
		self:Set(player, "TotalUnitsBought", nextBaseUnitCount)
	end

	self:Set(player, "Units", normalizedUnits)

	local previousUnlocked = self:Get(player, "UnlockedAnimeDroppers")
	local nextUnlocked = self:Update(player, "UnlockedAnimeDroppers", function(currentUnlocked: any)
		if resetUnlocks then
			return normalizeUnlockedAnimeDroppers({}, normalizedUnits)
		end
		return normalizeUnlockedAnimeDroppers(currentUnlocked, normalizedUnits)
	end)
	local loggedTiers = self:Get(player, { "Analytics", "TierUnlockFunnelLogged" })
	for _, tier in TierUnlockAnalytics.getNewUnlockTiers(previousUnlocked, nextUnlocked, loggedTiers) do
		if TierUnlockAnalytics.logTierUnlocked(player, tier) then
			self:Set(player, { "Analytics", "TierUnlockFunnelLogged", tostring(tier) }, true)
		end
	end
end

function PlayerDataService:Observe(player: Player, path: Path, callback: (any, any?) -> ())
	self:WaitForData(player)
	return DataService:getChangedSignal(player, path):Connect(callback)
end

local function isValidSetting(path: any, value: any): boolean
	if type(path) ~= "string" then
		return false
	end

	if
		path == "AutoCollect"
		or path == "AutoDeposit"
		or path == "ShowOtherTycoons"
		or path == "ShowOthers"
		or path == "ShowVFX"
		or path == "ShowManaPopup"
		or path == "Sound"
		or path == "Music"
	then
		return type(value) == "boolean"
	elseif path == "AutoMergeAt" then
		return type(value) == "number" and value == value and value >= 0 and value <= 100
	elseif path == "musicVolume" or path == "sfxVolume" then
		return isValidVolume(value)
	end

	return false
end

function PlayerDataService.Client:SetMusicVolume(player: Player, volume: number): boolean
	if not isValidVolume(volume) then
		return false
	end

	self.Server:Set(player, { "Settings", "musicVolume" }, volume)
	return true
end

function PlayerDataService.Client:SetSfxVolume(player: Player, volume: number): boolean
	if not isValidVolume(volume) then
		return false
	end

	self.Server:Set(player, { "Settings", "sfxVolume" }, volume)
	return true
end

function PlayerDataService.Client:SetSetting(player: Player, settingName: string, value: any): boolean
	if not isValidSetting(settingName, value) then
		return false
	end

	local isGamePassSetting = settingName == "AutoCollect" or settingName == "AutoDeposit"
	if value == true and isGamePassSetting then
		local MonetizationService = Knit.GetService("MonetizationService")
		if not MonetizationService:OwnsGamePass(player, settingName) then
			self.Server:Set(player, { "Settings", settingName }, false)
			return false
		end
	end

	if settingName == "AutoMergeAt" then
		value = math.clamp(math.floor(value), 0, 100)
	end

	self.Server:Set(player, { "Settings", settingName }, value)
	if isGamePassSetting then
		self.Server:Set(player, { "Settings", "GamePassSettingDisabled", settingName }, value ~= true)
	end
	return true
end

function PlayerDataService.Client:MarkFavoritePromptShown(player: Player): boolean
	self.Server:Set(player, "FavoritePromptShown", true)
	return true
end

return PlayerDataService
