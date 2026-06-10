local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
local EventUtil = require(ReplicatedStorage.Shared.Features.Events.EventUtil)
local Merge = require(ReplicatedStorage.Shared.Features.Tycoon.Merge)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local RebirthUpgrades = require(ReplicatedStorage.Shared.Data.RebirthUpgrades)
local YenUpgrades = require(ReplicatedStorage.Shared.Data.YenUpgrades)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local TycoonUtil = require(ReplicatedStorage.Shared.Features.Tycoon.TycoonUtil)
local Knit = require(ReplicatedStorage.Packages.knit)
local TierUnlockAnalytics = require(script.Parent.Parent.Features.Analytics.TierUnlockAnalytics)

local TycoonService = Knit.CreateService({
	Name = "TycoonService",
	Client = {
		CapsuleRobuxOpened = Knit.CreateSignal(),
		Offline5xRewardClaimed = Knit.CreateSignal(),
	},
})

local playerTycoons: { [Player]: Instance } = {}
local playerCharacterConnections: { [Player]: RBXScriptConnection } = {}
local pickupBudget: { [Player]: number } = {}
local pickupBudgetUpdatedAt: { [Player]: number } = {}
local mutationPickupAt: { [Player]: number } = {}
local pendingBagMana: { [Player]: number } = {}
local pendingDepositMana: { [Player]: number } = {}
local manaFlushScheduled: { [Player]: boolean } = {}
local processElapsed: { [Player]: number } = {}
local visualDataRequestAt: { [Player]: { [string]: number } } = {}
local pickupBlockedUntil: { [Player]: number } = {}
local pendingOfflineRewards: { [Player]: any } = {}
local pendingOffline5xReward: { [Player]: boolean } = {}
local activeCapsules: { [Player]: { [string]: any } } = {}
local lastCapsuleSpawnAt: { [Player]: number } = {}
local lastAmbientCapsuleAt: { [Player]: number } = {}
local pendingCapsuleRobux: { [Player]: string } = {}
local lastCapsuleRewardTier: { [Player]: number } = {}
local pendingCapsuleRewards: { [Player]: { [string]: number } } = {}

local PROCESS_INTERVAL = 1
local DROP_INTERVAL = 60
local MAX_ACTIVE_DROPS = 150
local PLAYER_COLLISION_GROUP = "PlayerCharacters"
local DROP_COLLISION_GROUP = "ManaDrops"
local DROP_WALL_COLLISION_GROUP = "DropWalls"
local CAPSULE_COLLISION_GROUP = "CapsuleDrops"
local VISUAL_DATA_REQUEST_COOLDOWN = 0.35
local MUTATION_PICKUP_COOLDOWN_PADDING = 0.8
local TUTORIAL_STEPS = {
	Prompt = 0,
	PickupDrop = 1,
	DepositMana = 2,
	BuySecondUnit = 3,
	PickupDropAgain = 4,
	UpgradeRate = 5,
	DepositManaAgain = 6,
	BuyThirdUnit = 7,
	MergeUnits = 8,
	VisitGroupReward = 9,
	WaitForRebirthReady = 10,
	Rebirth = 11,
	OpenUpgrades = 12,
	UpgradeUnitSpawnTier = 13,
	Completed = 14,
	Cancelled = 99,
}

local function resetPickupBudgetTimer(player: Player)
	pickupBudget[player] = 0
	pickupBudgetUpdatedAt[player] = os.clock()
end

local function clearPlayerCapsuleState(player: Player, clearCooldowns: boolean?)
	activeCapsules[player] = nil
	pendingCapsuleRobux[player] = nil
	lastCapsuleRewardTier[player] = nil
	pendingCapsuleRewards[player] = nil

	if clearCooldowns then
		lastCapsuleSpawnAt[player] = nil
		lastAmbientCapsuleAt[player] = nil
	end
end

local function flushQueuedMana(player: Player)
	manaFlushScheduled[player] = nil

	local bagAmount = pendingBagMana[player] or 0
	local depositAmount = pendingDepositMana[player] or 0
	pendingBagMana[player] = nil
	pendingDepositMana[player] = nil

	if bagAmount <= 0 and depositAmount <= 0 then
		return
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local totalCollected = bagAmount + depositAmount
	if totalCollected > 0 then
		pcall(function()
			Knit.GetService("QuestService"):TrackManaCollected(player, totalCollected)
		end)
	end

	if bagAmount > 0 then
		PlayerDataService:Update(player, "ManaInBag", function(current: number)
			return current + bagAmount
		end)
	end

	if depositAmount > 0 then
		PlayerDataService:Update(player, "ManaInDeposit", function(current: number)
			return current + depositAmount
		end)
	end
end

local function queueManaReward(player: Player, amount: number, shouldDeposit: boolean)
	if amount <= 0 then
		return
	end

	if shouldDeposit then
		pendingDepositMana[player] = (pendingDepositMana[player] or 0) + amount
	else
		pendingBagMana[player] = (pendingBagMana[player] or 0) + amount
	end

	if manaFlushScheduled[player] then
		return
	end

	manaFlushScheduled[player] = true
	task.delay(0.2, function()
		if player.Parent then
			flushQueuedMana(player)
		end
	end)
end

local function setupCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(DROP_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(DROP_WALL_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CAPSULE_COLLISION_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(DROP_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(DROP_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, DROP_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, CAPSULE_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
end

local function setCharacterCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end

	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end)
end

local function getYenMultiplier(player: Player): number
	local MonetizationService = Knit.GetService("MonetizationService")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local multiplier = 1

	if MonetizationService:OwnsGamePassOnly(player, "DoubleYen") then
		multiplier *= 2
	end

	if MonetizationService:OwnsProductEntitlement(player, "DoubleYen") then
		multiplier *= 2
	end

	local rebirths = math.max(math.floor(PlayerDataService:Get(player, "Rebirths") or 0), 0)
	local rebirthConfig = TycoonConfig.Rebirth
	multiplier *= (rebirthConfig.BaseYenMultiplier or 1) + rebirths * (rebirthConfig.YenMultiplierPerRebirth or 0)
	multiplier *= EventUtil.getEffectMultiplier("YenMultiplier", 1)

	local tutorialBoostEndsAt = math.max(math.floor(PlayerDataService:Get(player, "TutorialBoostEndsAt") or 0), 0)
	if tutorialBoostEndsAt > os.time() then
		local tutorialConfig = TycoonConfig.Tutorial or {}
		multiplier *= math.max(tonumber(tutorialConfig.RewardMultiplier) or 2, 1)
	end

	local PotionService = Knit.GetService("PotionService")
	multiplier *= PotionService:GetPotionMultiplier(player, "YenMultiplier")

	return multiplier
end

local function getTutorialData(PlayerDataService, player: Player): { [string]: any }
	local tutorial = PlayerDataService:Get(player, "Tutorial")
	return if type(tutorial) == "table" then tutorial else {}
end

local function grantTutorialReward(PlayerDataService, player: Player): number
	local tutorial = getTutorialData(PlayerDataService, player)
	if tutorial.RewardClaimed == true then
		return math.max(math.floor(PlayerDataService:Get(player, "TutorialBoostEndsAt") or 0), 0)
	end

	local tutorialConfig = TycoonConfig.Tutorial or {}
	local configuredRewardSeconds = if tutorial.Cancelled == true
		then tutorialConfig.CancelledRewardSeconds
		else tutorialConfig.RewardSeconds
	local rewardSeconds = math.max(math.floor(tonumber(configuredRewardSeconds) or 15 * 60), 1)
	local now = os.time()
	local currentEndsAt = math.max(math.floor(PlayerDataService:Get(player, "TutorialBoostEndsAt") or 0), 0)
	local nextEndsAt = math.max(currentEndsAt, now) + rewardSeconds
	PlayerDataService:Set(player, "TutorialBoostEndsAt", nextEndsAt)
	PlayerDataService:Set(player, { "Tutorial", "RewardClaimed" }, true)
	return nextEndsAt
end

local function getOfflineYenMultiplier(player: Player): number
	local MonetizationService = Knit.GetService("MonetizationService")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local multiplier = 1

	if MonetizationService:OwnsProductEntitlement(player, "DoubleYen") then
		multiplier *= 2
	end

	local rebirths = math.max(math.floor(PlayerDataService:Get(player, "Rebirths") or 0), 0)
	local rebirthConfig = TycoonConfig.Rebirth
	multiplier *= (rebirthConfig.BaseYenMultiplier or 1) + rebirths * (rebirthConfig.YenMultiplierPerRebirth or 0)
	multiplier *= EventUtil.getEffectMultiplier("YenMultiplier", 1)

	return multiplier
end

local function getUnitManaPerSecond(units: { { Tier: number } }): number
	local total = 0
	for _, unit in units do
		local tierData = AnimeDroppers.Tiers[unit.Tier or 1]
		if tierData then
			total += (tierData.DropValue or 1) / DROP_INTERVAL
		end
	end

	return math.max(total, 0)
end

local function getOfflineRewardPayload(player: Player)
	local cached = pendingOfflineRewards[player]
	if cached ~= nil then
		return cached
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local offlineConfig = TycoonConfig.OfflineReward or {}
	local minimumOfflineSeconds = math.max(math.floor(tonumber(offlineConfig.MinimumOfflineSeconds) or 3600), 0)
	local rewardMultiplier = math.clamp(tonumber(offlineConfig.RewardMultiplier) or 0.75, 0, 1)
	local maxOfflineSeconds =
		math.max(math.floor(tonumber(offlineConfig.MaxOfflineSeconds) or 24 * 60 * 60), minimumOfflineSeconds)
	local now = os.time()
	local lastLogoutAt = math.max(math.floor(PlayerDataService:Get(player, "LastLogoutAt") or 0), 0)
	local offlineSeconds = math.max(now - lastLogoutAt, 0)

	if lastLogoutAt <= 0 or offlineSeconds < minimumOfflineSeconds then
		pendingOfflineRewards[player] = false
		return false
	end

	local rewardedSeconds = math.min(offlineSeconds, maxOfflineSeconds)
	local units = PlayerDataService:GetUnits(player)
	local yenPerSecond = getUnitManaPerSecond(units) * getOfflineYenMultiplier(player)
	local reward = math.max(math.floor(yenPerSecond * rewardedSeconds * rewardMultiplier), 0)
	if reward <= 0 then
		pendingOfflineRewards[player] = false
		return false
	end

	local payload = {
		OfflineSeconds = offlineSeconds,
		RewardedSeconds = rewardedSeconds,
		Reward = reward,
		YenPerHour = yenPerSecond * 60 * 60,
		RewardMultiplier = rewardMultiplier,
	}
	pendingOfflineRewards[player] = payload
	return payload
end

local function getRebirthRequiredTier(rebirths: number): number
	local rebirthConfig = TycoonConfig.Rebirth
	return math.max(
		math.floor((rebirthConfig.FirstRequiredTier or 15) + rebirths * (rebirthConfig.RequiredTierStep or 5)),
		1
	)
end

local function hasRequiredRebirthTier(units: { { Tier: number } }, requiredTier: number): boolean
	for _, unit in units do
		if (unit.Tier or 1) >= requiredTier then
			return true
		end
	end

	return false
end

local function getGroupRewardAmount(units: { { Tier: number } }): number
	local groupRewardConfig = TycoonConfig.GroupReward or {}
	local baseYen = tonumber(groupRewardConfig.BaseYen) or 500
	local yenPerBaseUnit = tonumber(groupRewardConfig.YenPerBaseUnit) or 50
	local baseUnitCount = Pricing.getBaseUnitCount(units)
	local growthMultiplier = tonumber(groupRewardConfig.GrowthMultiplier) or 1
	local growthUnitsPerStep = math.max(tonumber(groupRewardConfig.GrowthUnitsPerStep) or 1, 1)
	local maxGrowthMultiplier = math.max(tonumber(groupRewardConfig.MaxGrowthMultiplier) or math.huge, 1)
	local reward = baseYen + baseUnitCount * yenPerBaseUnit
	local growth = math.min(growthMultiplier ^ (baseUnitCount / growthUnitsPerStep), maxGrowthMultiplier)
	return math.max(math.floor(reward * growth), 0)
end

local function getGroupRewardRemaining(lastClaimAt: number, now: number): number
	local groupRewardConfig = TycoonConfig.GroupReward or {}
	local cooldown = tonumber(groupRewardConfig.Cooldown) or 2 * 60 * 60
	return math.max(math.floor(cooldown - (now - lastClaimAt)), 0)
end

local function isPlayerInRewardGroup(player: Player): boolean
	local groupRewardConfig = TycoonConfig.GroupReward or {}
	local groupId = tonumber(groupRewardConfig.GroupId) or 0
	if groupId <= 0 then
		return false
	end

	local ok, isInGroup = pcall(function()
		return player:IsInGroup(groupId)
	end)

	return ok and isInGroup == true
end

local function getManaMultiplier(player: Player): number
	local MonetizationService = Knit.GetService("MonetizationService")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local upgrades = PlayerDataService:Get(player, "RebirthUpgrades")
	local moreManaLevel = if type(upgrades) == "table" then upgrades.MoreMana else 0
	local multiplier = RebirthUpgrades.getManaMultiplier(moreManaLevel)
	if MonetizationService:OwnsGamePass(player, "DoubleMana") then
		multiplier *= 2
	end
	multiplier *= EventUtil.getEffectMultiplier("ManaMultiplier", 1)

	local PotionService = Knit.GetService("PotionService")
	multiplier *= PotionService:GetPotionMultiplier(player, "ManaMultiplier")

	return multiplier
end

local function getDropInterval(player: Player?): number
	local gamePassMultiplier = 1
	if player then
		local MonetizationService = Knit.GetService("MonetizationService")
		if MonetizationService:OwnsGamePass(player, "DoubleDropSpeed") then
			gamePassMultiplier = 2
		end
	end

	local dropSpeedMultiplier = math.max(EventUtil.getEffectMultiplier("DropSpeedMultiplier", 1), 0.1)
	return DROP_INTERVAL / (gamePassMultiplier * dropSpeedMultiplier)
end

local function getMaxMutationMultiplier(player: Player): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local upgrades = PlayerDataService:Get(player, "YenUpgrades")
	local level = if type(upgrades) == "table" then upgrades.BetterGoldenDrops else 0
	return YenUpgrades.getMaxGoldMultiplier(level)
end

local function getMutationPickupCooldown(): number
	local mutationConfig = TycoonConfig.Mutations or {}
	return math.max((tonumber(mutationConfig.Interval) or 60) * MUTATION_PICKUP_COOLDOWN_PADDING, 1)
end

local function getDepositInterval(player: Player): number
	local MonetizationService = Knit.GetService("MonetizationService")
	local interval = if MonetizationService:OwnsGamePass(player, "DoubleDeposit") then 0.5 else PROCESS_INTERVAL
	local processSpeedMultiplier = math.max(EventUtil.getEffectMultiplier("ProcessSpeedMultiplier", 1), 0.1)
	local PotionService = Knit.GetService("PotionService")
	processSpeedMultiplier *= PotionService:GetPotionMultiplier(player, "ProcessSpeedMultiplier")
	return interval / processSpeedMultiplier
end

local function getTycoonOwnerPlayer(tycoon: Instance): Player?
	local ownerUserId = tycoon:GetAttribute("Owner")
	if type(ownerUserId) ~= "number" or ownerUserId <= 0 then
		return nil
	end

	return Players:GetPlayerByUserId(ownerUserId)
end

local function addTierOneUnits(
	units: { { Tier: number } },
	amount: number,
	shouldAutoMerge: boolean,
	startTier: number?
): { { Tier: number } }
	startTier = math.clamp(math.floor(startTier or 1), 1, AnimeDroppers.MaxTier)
	if not shouldAutoMerge and #units + amount <= TycoonConfig.MaxUnits then
		local nextUnits = table.clone(units)
		for _ = 1, amount do
			table.insert(nextUnits, { Tier = startTier })
		end

		return Merge.sortUnits(nextUnits)
	end

	local counts = {}
	for _, unit in units do
		local tier = math.clamp(unit.Tier or 1, 1, AnimeDroppers.MaxTier)
		counts[tier] = (counts[tier] or 0) + 1
	end

	counts[startTier] = (counts[startTier] or 0) + amount

	for tier = 1, AnimeDroppers.MaxTier do
		local tierData = AnimeDroppers.Tiers[tier]
		local targetTier = tierData and tierData.MergeInto
		if not targetTier or not AnimeDroppers.Tiers[targetTier] then
			continue
		end

		local count = counts[tier] or 0
		local mergeRatio = AnimeDroppers.getMergeRatio(tier)
		local mergeCount = math.floor(count / mergeRatio)
		if mergeCount > 0 then
			counts[tier] = count - mergeCount * mergeRatio
			counts[targetTier] = (counts[targetTier] or 0) + mergeCount
		end
	end

	local nextUnits = {}
	for tier = AnimeDroppers.MaxTier, 1, -1 do
		for _ = 1, (counts[tier] or 0) do
			table.insert(nextUnits, { Tier = tier })
		end
	end

	return nextUnits
end

local function getAutoMergeAt(PlayerDataService, player: Player): number
	local settings = PlayerDataService:Get(player, "Settings")
	if type(settings) ~= "table" then
		return 100
	end

	return math.clamp(math.floor(tonumber(settings.AutoMergeAt) or 100), 0, 100)
end

local function shouldAutoMergeUnitBuy(
	PlayerDataService,
	player: Player,
	currentUnitCount: number,
	amount: number
): boolean
	local autoMergeAt = getAutoMergeAt(PlayerDataService, player)
	return autoMergeAt <= 1
		or currentUnitCount + amount > autoMergeAt
		or currentUnitCount + amount > TycoonConfig.MaxUnits
end

local function getPlayerSettings(PlayerDataService, player: Player): { [string]: any }
	local settings = PlayerDataService:Get(player, "Settings")
	return if type(settings) == "table" then settings else {}
end

local function shouldAutoDeposit(PlayerDataService, player: Player): boolean
	local settings = getPlayerSettings(PlayerDataService, player)
	if settings.AutoDeposit ~= true then
		return false
	end

	local MonetizationService = Knit.GetService("MonetizationService")
	return MonetizationService:OwnsGamePass(player, "AutoDeposit")
end

local function getUnitSpawnTier(PlayerDataService, player: Player): number
	local upgrades = PlayerDataService:Get(player, "RebirthUpgrades")
	local level = if type(upgrades) == "table" then upgrades.UnitSpawnTier else 0
	local eventBonus = math.max(math.floor(EventUtil.getEffectBonus("UnitSpawnTierBonus", 0)), 0)
	return math.clamp(RebirthUpgrades.getUnitSpawnTier(level) + eventBonus, 1, AnimeDroppers.MaxTier)
end

local function getMaxButtonCount(PlayerDataService, player: Player): number
	local upgrades = PlayerDataService:Get(player, "YenUpgrades")
	local level = if type(upgrades) == "table" then upgrades.BetterMaxButton else 0
	return YenUpgrades.getMaxButtonCount(level)
end

local function getRebirthStarterUnits(PlayerDataService, player: Player): { { Tier: number } }
	local spawnTier = getUnitSpawnTier(PlayerDataService, player)
	local rebirthConfig = TycoonConfig.Rebirth
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

local function getMaxPickupRate(player: Player, units: { { Tier: number } }): number
	local dropInterval = getDropInterval(player)
	local total = 0
	for _, unit in units do
		local tierData = AnimeDroppers.Tiers[unit.Tier]
		if tierData then
			total += (tierData.DropValue or 1) / dropInterval
		end
	end
	return math.max(total, 1)
end

function TycoonService:AssignTycoon(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local existingName = PlayerDataService:Get(player, "TycoonName")
	if existingName and existingName ~= "" then
		local existingTycoon = TycoonUtil.getPlayerTycoon(player, existingName)
		if existingTycoon then
			playerTycoons[player] = existingTycoon
			resetPickupBudgetTimer(player)

			if not playerCharacterConnections[player] then
				playerCharacterConnections[player] = player.CharacterAdded:Connect(function()
					TycoonUtil.teleportToSpawn(player, existingTycoon)
				end)
			end

			TycoonUtil.teleportToSpawn(player, existingTycoon)
			return
		end
	end

	local tycoonsFolder = TycoonUtil.getTycoonsFolder()
	if not tycoonsFolder then
		warn("[TycoonService] Tycoons folder not found")
		return
	end

	for _, tycoon in tycoonsFolder:GetChildren() do
		if tycoon:GetAttribute("Claimed") ~= true then
			tycoon:SetAttribute("Claimed", true)
			tycoon:SetAttribute("Owner", player.UserId)
			PlayerDataService:Set(player, "TycoonName", tycoon.Name)
			playerTycoons[player] = tycoon
			resetPickupBudgetTimer(player)

			if not playerCharacterConnections[player] then
				playerCharacterConnections[player] = player.CharacterAdded:Connect(function()
					TycoonUtil.teleportToSpawn(player, tycoon)
				end)
			end

			if player.Character then
				TycoonUtil.teleportToSpawn(player, tycoon)
			end
			return
		end
	end

	warn("[TycoonService] No open tycoon for", player.Name)
end

function TycoonService:ReleaseTycoon(player: Player)
	local tycoon = playerTycoons[player]
	if tycoon then
		tycoon:SetAttribute("Claimed", false)
		tycoon:SetAttribute("Owner", 0)
	end

	playerTycoons[player] = nil
	pickupBudget[player] = nil
	pickupBudgetUpdatedAt[player] = nil
	mutationPickupAt[player] = nil
	flushQueuedMana(player)
	pendingBagMana[player] = nil
	pendingDepositMana[player] = nil
	manaFlushScheduled[player] = nil
	processElapsed[player] = nil
	visualDataRequestAt[player] = nil
	pickupBlockedUntil[player] = nil
	pendingOfflineRewards[player] = nil
	pendingOffline5xReward[player] = nil

	local characterConnection = playerCharacterConnections[player]
	if characterConnection then
		characterConnection:Disconnect()
		playerCharacterConnections[player] = nil
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local ok, tycoonName = pcall(function()
		return PlayerDataService:Get(player, "TycoonName")
	end)
	if ok and tycoonName and tycoonName ~= "" then
		pcall(function()
			PlayerDataService:Set(player, "TycoonName", "")
		end)
	end
end

function TycoonService.Client:CollectMana(player: Player, amount: number): (boolean, string?)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false, "Invalid amount"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if not playerTycoons[player] then
		return false, "No tycoon"
	end

	if os.clock() < (pickupBlockedUntil[player] or 0) then
		return true
	end

	local units = PlayerDataService:GetUnits(player)
	local maxRate = getMaxPickupRate(player, units)
	local dropInterval = getDropInterval(player)
	local now = os.clock()
	local lastUpdated = pickupBudgetUpdatedAt[player] or now
	local elapsed = math.max(now - lastUpdated, 0)
	local maxDropValue = 1

	for _, unit in units do
		local tierData = AnimeDroppers.Tiers[unit.Tier]
		if tierData then
			maxDropValue = math.max(maxDropValue, tierData.DropValue or 1)
		end
	end

	local maxStoredDropValue = math.max(maxRate * dropInterval * MAX_ACTIVE_DROPS, maxDropValue * MAX_ACTIVE_DROPS)
	pickupBudget[player] = math.min((pickupBudget[player] or 0) + maxRate * elapsed, maxStoredDropValue)
	pickupBudgetUpdatedAt[player] = now

	local availablePickupBudget = pickupBudget[player] or 0
	local remainingAmount = amount
	local normalPickupAmount = math.min(availablePickupBudget, remainingAmount)
	remainingAmount -= normalPickupAmount
	local normalBurstAllowance = math.max(maxRate * dropInterval + maxDropValue, maxDropValue)
	local burstPickupAmount = math.min(normalBurstAllowance, remainingAmount)
	remainingAmount -= burstPickupAmount
	local creditedAmount = normalPickupAmount + burstPickupAmount

	pickupBudget[player] = math.max(availablePickupBudget - normalPickupAmount, 0)

	if remainingAmount > 0.001 then
		local maxMutationValue = maxDropValue * getMaxMutationMultiplier(player)
		local cooldown = getMutationPickupCooldown()
		local lastMutationPickup = mutationPickupAt[player] or 0
		if now - lastMutationPickup >= cooldown then
			creditedAmount += math.min(remainingAmount, maxMutationValue)
			mutationPickupAt[player] = now
		end
	end

	if creditedAmount <= 0 then
		return true
	end

	local finalAmount = creditedAmount * getManaMultiplier(player)
	queueManaReward(player, finalAmount, shouldAutoDeposit(PlayerDataService, player))

	return true
end

function TycoonService.Client:TeleportHome(player: Player): (boolean, string?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoon = playerTycoons[player]
	if not tycoon then
		local tycoonName = PlayerDataService:Get(player, "TycoonName")
		if tycoonName and tycoonName ~= "" then
			tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
			if tycoon then
				playerTycoons[player] = tycoon
			end
		end
	end

	if not tycoon then
		return false, "No tycoon"
	end

	TycoonUtil.teleportToSpawn(player, tycoon)
	return true
end

function TycoonService.Client:TeleportToTycoon(player: Player, tycoonName: string): (boolean, string?)
	if type(tycoonName) ~= "string" or tycoonName == "" then
		return false, "Invalid tycoon"
	end

	local tycoon = TycoonUtil.getTycoonByName(tycoonName)
	if not tycoon or tycoon:GetAttribute("Claimed") ~= true then
		return false, "Not available"
	end

	local ownerUserId = tonumber(tycoon:GetAttribute("Owner")) or 0
	if ownerUserId <= 0 then
		return false, "Not available"
	end

	TycoonUtil.teleportToSpawn(player, tycoon)
	return true
end

function TycoonService.Client:GetOfflineReward(player: Player): (boolean, any)
	local payload = getOfflineRewardPayload(player)
	if not payload then
		return true, {
			Eligible = false,
			OfflineSeconds = 0,
			Reward = 0,
		}
	end

	return true,
		{
			Eligible = true,
			OfflineSeconds = payload.OfflineSeconds,
			RewardedSeconds = payload.RewardedSeconds,
			Reward = payload.Reward,
			YenPerHour = payload.YenPerHour,
			RewardMultiplier = payload.RewardMultiplier,
		}
end

function TycoonService.Client:ClaimOfflineReward(player: Player): (boolean, string?, number?)
	if pendingOffline5xReward[player] then
		return false, "Purchase pending", 0
	end

	local payload = getOfflineRewardPayload(player)
	if not payload then
		return false, "No reward", 0
	end

	pendingOffline5xReward[player] = nil
	pendingOfflineRewards[player] = false
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddYen(player, payload.Reward)
	return true, nil, payload.Reward
end

function TycoonService:ClaimOffline5xReward(player: Player): (boolean, number?)
	if not pendingOffline5xReward[player] then
		return false, 0
	end

	local payload = getOfflineRewardPayload(player)
	if not payload then
		pendingOffline5xReward[player] = nil
		return false, 0
	end

	local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
	local product = Monetization.DeveloperProducts.Offline5xReward
	local multiplier = math.max(math.floor(tonumber(product and product.Multiplier) or 5), 2)

	pendingOffline5xReward[player] = nil
	pendingOfflineRewards[player] = false

	local reward = math.max(math.floor(payload.Reward * multiplier), 0)
	if reward <= 0 then
		return false, 0
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddYen(player, reward)
	self.Client.Offline5xRewardClaimed:Fire(player, reward, multiplier)
	return true, reward
end

function TycoonService.Client:PrepareOffline5xReward(player: Player): boolean
	if pendingOffline5xReward[player] then
		return true
	end

	local payload = getOfflineRewardPayload(player)
	if not payload then
		return false
	end

	pendingOffline5xReward[player] = true
	return true
end

function TycoonService.Client:CancelOffline5xReward(player: Player)
	pendingOffline5xReward[player] = nil
end

function TycoonService.Client:GetTycoonVisualData(player: Player, tycoonName: string): (boolean, any)
	if type(tycoonName) ~= "string" or tycoonName == "" then
		return false, "Invalid tycoon"
	end

	local now = os.clock()
	visualDataRequestAt[player] = visualDataRequestAt[player] or {}
	if now - (visualDataRequestAt[player][tycoonName] or 0) < VISUAL_DATA_REQUEST_COOLDOWN then
		return false, "Too fast"
	end
	visualDataRequestAt[player][tycoonName] = now

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoon = TycoonUtil.getTycoonByName(tycoonName)
	if not tycoon or tycoon:GetAttribute("Claimed") ~= true then
		return false, "No tycoon"
	end

	local owner = getTycoonOwnerPlayer(tycoon)
	if not owner then
		return false, "No owner"
	end

	PlayerDataService:WaitForData(owner)
	local units = PlayerDataService:GetUnits(owner)
	local manaInDeposit = math.max(math.floor(PlayerDataService:Get(owner, "ManaInDeposit") or 0), 0)
	local rate = math.max(math.floor(PlayerDataService:Get(owner, "Rate") or 0), 0)
	local compactUnits = table.create(#units)
	for _, unit in units do
		table.insert(compactUnits, {
			Tier = unit.Tier,
			Slot = unit.Slot,
		})
	end

	-- Visual-only payload. Server stays authoritative for money, drops, buys and merges.
	return true,
		{
			TycoonName = tycoon.Name,
			OwnerUserId = owner.UserId,
			Units = compactUnits,
			ManaInDeposit = manaInDeposit,
			Rate = rate,
		}
end

function TycoonService:GrantUnits(player: Player, amount: number): boolean
	if type(amount) ~= "number" or amount <= 0 then
		return false
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if not playerTycoons[player] then
		local tycoonName = PlayerDataService:Get(player, "TycoonName")
		local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
		if tycoon then
			playerTycoons[player] = tycoon
		end
	end

	if not playerTycoons[player] then
		return false
	end

	local currentUnits = PlayerDataService:GetUnits(player)
	local units = addTierOneUnits(
		currentUnits,
		amount,
		shouldAutoMergeUnitBuy(PlayerDataService, player, #currentUnits, amount),
		getUnitSpawnTier(PlayerDataService, player)
	)

	PlayerDataService:SetUnits(player, units)
	return true
end

function TycoonService:SellAllProcessor(player: Player): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	flushQueuedMana(player)

	local deposit = PlayerDataService:Get(player, "ManaInDeposit") or 0
	if deposit <= 0 then
		return 0
	end

	PlayerDataService:Set(player, "ManaInDeposit", 0)
	PlayerDataService:AddYen(player, deposit * getYenMultiplier(player))
	return deposit
end

function TycoonService:AdminResetDeposit(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	pendingBagMana[player] = nil
	pendingDepositMana[player] = nil
	manaFlushScheduled[player] = nil
	processElapsed[player] = 0

	local resetRate = TycoonConfig.Rebirth.ResetRate or 1
	PlayerDataService:Set(player, "ManaInBag", 0)
	PlayerDataService:Set(player, "ManaInDeposit", 0)
	PlayerDataService:Set(player, "RateLevel", 0)
	PlayerDataService:Set(player, "Rate", resetRate)

	return resetRate
end

function TycoonService:ApplyRebirthProgressReset(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local rebirthConfig = TycoonConfig.Rebirth
	local resetYen = if rebirthConfig.ResetYen ~= nil then rebirthConfig.ResetYen else 100
	local starterUnits = getRebirthStarterUnits(PlayerDataService, player)

	PlayerDataService:Set(player, "Yen", resetYen)
	PlayerDataService:Set(player, "ManaInBag", 0)
	PlayerDataService:Set(player, "ManaInDeposit", 0)
	PlayerDataService:Set(player, "TotalUnitsPurchased", 0)
	PlayerDataService:Set(player, "RateLevel", 0)
	PlayerDataService:Set(player, "Rate", rebirthConfig.ResetRate or 1)
	PlayerDataService:SetUnits(player, starterUnits, { resetUnlocks = true })

	pendingBagMana[player] = nil
	pendingDepositMana[player] = nil
	manaFlushScheduled[player] = nil
	processElapsed[player] = 0
	clearPlayerCapsuleState(player, true)
	pickupBlockedUntil[player] = os.clock() + 1
	resetPickupBudgetTimer(player)
end

function TycoonService.Client:AcceptTutorial(player: Player): (boolean, string?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tutorial = getTutorialData(PlayerDataService, player)
	if tutorial.Completed == true or tutorial.Cancelled == true then
		return false, "Already finished"
	end

	PlayerDataService:Set(player, { "Tutorial", "Prompted" }, true)
	PlayerDataService:Set(player, { "Tutorial", "Accepted" }, true)
	PlayerDataService:Set(player, { "Tutorial", "Cancelled" }, false)
	PlayerDataService:Set(player, { "Tutorial", "Step" }, "PickupDrop")
	return true
end

function TycoonService.Client:CancelTutorial(player: Player): (boolean, string?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	PlayerDataService:Set(player, { "Tutorial", "Prompted" }, true)
	PlayerDataService:Set(player, { "Tutorial", "Accepted" }, false)
	PlayerDataService:Set(player, { "Tutorial", "Cancelled" }, true)
	PlayerDataService:Set(player, { "Tutorial", "Step" }, "Cancelled")
	return true
end

function TycoonService.Client:UpdateTutorialStep(player: Player, step: string): boolean
	if type(step) ~= "string" or TUTORIAL_STEPS[step] == nil or step == "Cancelled" then
		return false
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tutorial = getTutorialData(PlayerDataService, player)
	if tutorial.Accepted ~= true or tutorial.Cancelled == true or tutorial.Completed == true then
		return false
	end

	local currentStep = if type(tutorial.Step) == "string" then tutorial.Step else "Prompt"
	local currentIndex = TUTORIAL_STEPS[currentStep] or 0
	local nextIndex = TUTORIAL_STEPS[step] or 0
	if nextIndex < currentIndex then
		return false
	end

	PlayerDataService:Set(player, { "Tutorial", "Step" }, step)
	return true
end

function TycoonService.Client:CompleteTutorial(player: Player): (boolean, string?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tutorial = getTutorialData(PlayerDataService, player)
	if tutorial.Cancelled == true then
		return false, "Cancelled"
	end

	PlayerDataService:Set(player, { "Tutorial", "Prompted" }, true)
	PlayerDataService:Set(player, { "Tutorial", "Accepted" }, true)
	PlayerDataService:Set(player, { "Tutorial", "Completed" }, true)
	PlayerDataService:Set(player, { "Tutorial", "Step" }, "Completed")
	if PlayerDataService:Get(player, { "Analytics", "TutorialCompleteFunnelLogged" }) ~= true then
		if TierUnlockAnalytics.logTutorialCompleted(player) then
			PlayerDataService:Set(player, { "Analytics", "TutorialCompleteFunnelLogged" }, true)
		end
	end
	return true
end

function TycoonService.Client:ClaimTutorialReward(player: Player): (boolean, string?, number?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tutorial = getTutorialData(PlayerDataService, player)
	if tutorial.Completed ~= true and tutorial.Cancelled ~= true then
		return false, "Tutorial not finished"
	end

	if tutorial.RewardClaimed == true then
		return false,
			"Already claimed",
			math.max(math.floor(PlayerDataService:Get(player, "TutorialBoostEndsAt") or 0), 0)
	end

	return true, nil, grantTutorialReward(PlayerDataService, player)
end

function TycoonService.Client:DepositMana(player: Player): (boolean, string?, number?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local depositButton = tycoon:FindFirstChild("DepositButton")
	if not depositButton then
		for _, child in tycoon:GetChildren() do
			if TycoonUtil.isDepositButton(child) then
				depositButton = child
				break
			end
		end
	end

	if not depositButton or not TycoonUtil.isNearButton(player, depositButton) then
		return false, "Too far"
	end

	flushQueuedMana(player)
	local deposited = PlayerDataService:DepositMana(player)
	if deposited <= 0 then
		return false, "Nothing to deposit"
	end

	return true, nil, deposited
end

function TycoonService.Client:BuyUnits(player: Player, amount: number, buttonName: string): (boolean, string?)
	if type(amount) ~= "number" or amount <= 0 then
		return false, "Invalid amount"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local buttonModel = tycoon:FindFirstChild(buttonName)
	if not buttonModel or not TycoonUtil.isNearButton(player, buttonModel) then
		return false, "Too far"
	end

	if TycoonUtil.getRobuxBuyAmount(buttonModel) then
		return false, "Robux button"
	end

	local parsedAmount = TycoonUtil.getBuyAmount(buttonModel)
	if parsedAmount ~= amount then
		return false, "Invalid button"
	end

	local currentUnits = PlayerDataService:GetUnits(player)
	local purchasedUnitCount = math.max(math.floor(PlayerDataService:Get(player, "TotalUnitsPurchased") or 0), 0)
	local unitScaleCount = math.max(math.floor(PlayerDataService:Get(player, "TotalUnitsBought") or 0), purchasedUnitCount)
	local spawnTier = getUnitSpawnTier(PlayerDataService, player)
	local price = Pricing.getUnitBulkPrice(purchasedUnitCount, amount, false, spawnTier, unitScaleCount)
	if not PlayerDataService:TrySpendYen(player, price) then
		return false, "Not enough yen"
	end

	local units = addTierOneUnits(
		currentUnits,
		amount,
		shouldAutoMergeUnitBuy(PlayerDataService, player, #currentUnits, amount),
		spawnTier
	)

	PlayerDataService:SetUnits(player, units)
	PlayerDataService:Set(
		player,
		"TotalUnitsPurchased",
		math.max(math.floor(PlayerDataService:Get(player, "TotalUnitsPurchased") or 0), 0) + amount
	)

	pcall(function()
		Knit.GetService("QuestService"):TrackUnitsBought(player, amount)
	end)

	return true
end

function TycoonService.Client:BuyMaxUnits(player: Player, buttonName: string): (boolean, string?, number?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local buttonModel = tycoon:FindFirstChild(buttonName)
	if
		not buttonModel
		or not TycoonUtil.isBuyMaxUnitsButton(buttonModel)
		or not TycoonUtil.isNearButton(player, buttonModel)
	then
		return false, "Invalid button"
	end

	local currentUnits = PlayerDataService:GetUnits(player)
	local purchasedUnitCount = math.max(math.floor(PlayerDataService:Get(player, "TotalUnitsPurchased") or 0), 0)
	local unitScaleCount = math.max(math.floor(PlayerDataService:Get(player, "TotalUnitsBought") or 0), purchasedUnitCount)
	local yen = PlayerDataService:Get(player, "Yen") or 0
	local maxButtonCount = getMaxButtonCount(PlayerDataService, player)
	if maxButtonCount <= 0 then
		return false, "Max button locked"
	end

	local spawnTier = getUnitSpawnTier(PlayerDataService, player)
	local amount, price =
		Pricing.getMaxAffordableUnitPurchase(purchasedUnitCount, yen, maxButtonCount, spawnTier, unitScaleCount)
	if amount <= 0 or price <= 0 then
		return false, "Not enough yen"
	end

	if not PlayerDataService:TrySpendYen(player, price) then
		return false, "Not enough yen"
	end

	local units = addTierOneUnits(currentUnits, amount, true, spawnTier)

	PlayerDataService:SetUnits(player, units)
	PlayerDataService:Set(
		player,
		"TotalUnitsPurchased",
		math.max(math.floor(PlayerDataService:Get(player, "TotalUnitsPurchased") or 0), 0) + amount
	)

	pcall(function()
		Knit.GetService("QuestService"):TrackUnitsBought(player, amount)
	end)

	return true, nil, amount
end

function TycoonService.Client:MergeUnits(player: Player, buttonName: string): (boolean, string?, number?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local buttonModel = tycoon:FindFirstChild(buttonName)
	if
		not buttonModel
		or not TycoonUtil.isMergeButton(buttonModel)
		or not TycoonUtil.isNearButton(player, buttonModel)
	then
		return false, "Invalid button"
	end

	local units = PlayerDataService:GetUnits(player)
	local mergedUnits, changed, mergedUnitCount = Merge.runOnce(units)
	if not changed then
		return false, "Nothing to merge"
	end

	PlayerDataService:SetUnits(player, mergedUnits)
	return true, nil, mergedUnitCount
end

function TycoonService.Client:Rebirth(player: Player): (boolean, string?, number?, number?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local rebirths = math.max(math.floor(PlayerDataService:Get(player, "Rebirths") or 0), 0)
	local requiredTier = getRebirthRequiredTier(rebirths)
	local units = PlayerDataService:GetUnits(player)
	if not hasRequiredRebirthTier(units, requiredTier) then
		return false, "Required tier missing"
	end

	local nextRebirths = rebirths + 1
	local tokenReward = PlayerDataService:GetRebirthTokenReward(nextRebirths)
	PlayerDataService:Set(player, "Rebirths", nextRebirths)
	PlayerDataService:GrantRebirthTokenReward(player, nextRebirths)
	TycoonService:ApplyRebirthProgressReset(player)

	return true, nil, nextRebirths, tokenReward
end

function TycoonService.Client:BuyRebirthUpgrade(player: Player, upgradeKey: string): (boolean, string?, number?)
	if upgradeKey ~= "UnitSpawnTier" and upgradeKey ~= "MoreMana" then
		return false, "Invalid upgrade"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local upgrades = PlayerDataService:Get(player, "RebirthUpgrades")
	if type(upgrades) ~= "table" then
		upgrades = {}
	end

	local currentLevel = math.max(math.floor(tonumber(upgrades[upgradeKey]) or 0), 0)
	if RebirthUpgrades.isMaxed(upgradeKey, currentLevel) then
		return false, "Maxed"
	end

	local cost = RebirthUpgrades.getCost(upgradeKey, currentLevel)
	if not cost or cost <= 0 then
		return false, "Maxed"
	end

	local tokens = math.max(math.floor(PlayerDataService:Get(player, "RebirthTokens") or 0), 0)
	if tokens < cost then
		return false, "Not enough tokens"
	end

	PlayerDataService:Set(player, "RebirthTokens", tokens - cost)

	local nextLevel = currentLevel + 1
	PlayerDataService:Set(player, { "RebirthUpgrades", upgradeKey }, nextLevel)

	if upgradeKey == "UnitSpawnTier" then
		local units = PlayerDataService:GetUnits(player)
		local upgradedUnits, changed = RebirthUpgrades.upgradeUnitsForSpawnTier(units, currentLevel, nextLevel)
		if changed then
			PlayerDataService:SetUnits(player, upgradedUnits)
		end
	end

	return true, nil, nextLevel
end

function TycoonService.Client:BuyYenUpgrade(player: Player, upgradeKey: string): (boolean, string?, number?)
	if upgradeKey ~= "BetterMaxButton" and upgradeKey ~= "BetterGoldenDrops" and upgradeKey ~= "Pickuprange" then
		return false, "Invalid upgrade"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local upgrades = PlayerDataService:Get(player, "YenUpgrades")
	if type(upgrades) ~= "table" then
		upgrades = {}
	end

	local currentLevel = math.max(math.floor(tonumber(upgrades[upgradeKey]) or 0), 0)
	if YenUpgrades.isMaxed(upgradeKey, currentLevel) then
		return false, "Maxed"
	end

	local cost = YenUpgrades.getCost(upgradeKey, currentLevel)
	if not cost or cost <= 0 then
		return false, "Maxed"
	end

	if not PlayerDataService:TrySpendYen(player, cost) then
		return false, "Not enough yen"
	end

	local nextLevel = currentLevel + 1
	PlayerDataService:Set(player, { "YenUpgrades", upgradeKey }, nextLevel)

	return true, nil, nextLevel
end

function TycoonService.Client:UpgradeRate(
	player: Player,
	amount: number,
	buttonName: string
): (boolean, string?, number?, number?)
	if type(amount) ~= "number" or amount <= 0 then
		return false, "Invalid amount"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local buttonModel = tycoon:FindFirstChild(buttonName)
	if not buttonModel or not TycoonUtil.isNearButton(player, buttonModel) then
		return false, "Too far"
	end

	local parsedAmount = TycoonUtil.getRateAmount(buttonModel)
	if parsedAmount ~= amount then
		return false, "Invalid button"
	end

	local rateLevel = PlayerDataService:Get(player, "RateLevel")
	local price = Pricing.getRateUpgradePrice(rateLevel, amount)
	if not PlayerDataService:TrySpendYen(player, price) then
		return false, "Not enough yen"
	end

	local gain = Pricing.getRateGain(amount, rateLevel)
	local currentRate = PlayerDataService:Get(player, "Rate")

	PlayerDataService:Set(player, "Rate", currentRate + gain)
	PlayerDataService:Set(player, "RateLevel", rateLevel + amount)

	return true, nil, amount, gain
end

function TycoonService.Client:UpgradeRateMax(player: Player, buttonName: string): (boolean, string?, number?, number?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local buttonModel = tycoon:FindFirstChild(buttonName) or tycoon:FindFirstChild(buttonName, true)
	if
		not buttonModel
		or not TycoonUtil.isRateMaxButton(buttonModel)
		or not TycoonUtil.isNearButton(player, buttonModel)
	then
		return false, "Invalid button"
	end

	local rateLevel = PlayerDataService:Get(player, "RateLevel")
	local yen = PlayerDataService:Get(player, "Yen") or 0
	local maxButtonCount = getMaxButtonCount(PlayerDataService, player)
	if maxButtonCount <= 0 then
		return false, "Max button locked"
	end

	local amount, price, gain = Pricing.getMaxAffordableRateUpgrade(rateLevel, yen, maxButtonCount)
	if amount <= 0 or price <= 0 then
		return false, "Not enough yen"
	end

	if not PlayerDataService:TrySpendYen(player, price) then
		return false, "Not enough yen"
	end

	local currentRate = PlayerDataService:Get(player, "Rate")
	PlayerDataService:Set(player, "Rate", currentRate + gain)
	PlayerDataService:Set(player, "RateLevel", rateLevel + amount)

	return true, nil, amount, gain
end

local function getGroupLikeReminderRequired(): number
	local groupRewardConfig = TycoonConfig.GroupReward or {}
	return math.max(math.floor(tonumber(groupRewardConfig.LikeReminderRequired) or 3), 1)
end

local function hasGroupRewardLikeUnlocked(PlayerDataService, player: Player): boolean
	if PlayerDataService:Get(player, "GroupRewardLikeUnlocked") == true then
		return true
	end

	local count = math.max(math.floor(PlayerDataService:Get(player, "GroupLikeReminderCount") or 0), 0)
	return count >= getGroupLikeReminderRequired()
end

function TycoonService.Client:RegisterGroupLikeReminder(player: Player): (boolean, string?, number?, boolean?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if not isPlayerInRewardGroup(player) then
		return false, "Not in group", 0, false
	end

	if hasGroupRewardLikeUnlocked(PlayerDataService, player) then
		local count = math.max(math.floor(PlayerDataService:Get(player, "GroupLikeReminderCount") or 0), 0)
		return true, nil, count, true
	end

	local required = getGroupLikeReminderRequired()
	local count = math.max(math.floor(PlayerDataService:Get(player, "GroupLikeReminderCount") or 0), 0) + 1
	PlayerDataService:Set(player, "GroupLikeReminderCount", count)

	local unlocked = count >= required
	if unlocked then
		PlayerDataService:Set(player, "GroupRewardLikeUnlocked", true)
	end

	return true, nil, count, unlocked
end

function TycoonService.Client:ClaimGroupReward(player: Player, buttonName: string): (boolean, string?, number?, number?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local buttonModel = tycoon:FindFirstChild(buttonName)
	if
		not buttonModel
		or not TycoonUtil.isGroupRewardButton(buttonModel)
		or not TycoonUtil.isNearButton(player, buttonModel)
	then
		return false, "Invalid button"
	end

	if not isPlayerInRewardGroup(player) then
		return false, "Not in group"
	end

	if not hasGroupRewardLikeUnlocked(PlayerDataService, player) then
		return false, "Like required"
	end

	local now = os.time()
	local lastClaimAt = math.max(math.floor(PlayerDataService:Get(player, "LastGroupRewardClaimAt") or 0), 0)
	local remaining = getGroupRewardRemaining(lastClaimAt, now)
	local reward = getGroupRewardAmount(PlayerDataService:GetUnits(player))
	if remaining > 0 then
		return false, "Cooldown", remaining, reward
	end

	PlayerDataService:Set(player, "LastGroupRewardClaimAt", now)
	PlayerDataService:AddYen(player, reward)

	return true, nil, reward, getGroupRewardRemaining(now, now)
end

local function getCapsuleConfig()
	return TycoonConfig.Capsules or {}
end

local function getActiveCapsuleCount(player: Player): number
	local capsules = activeCapsules[player]
	if not capsules then
		return 0
	end

	local count = 0
	for _, capsule in capsules do
		if capsule ~= nil then
			count += 1
		end
	end

	return count
end

local function grantCapsuleUnit(player: Player, tier: number): (boolean, string?)
	if TycoonService:GrantUnitAtTier(player, tier, 1) then
		return true
	end

	return false, "Failed to grant unit"
end

function TycoonService:GrantUnitAtTier(player: Player, tier: number, amount: number?): boolean
	local grantAmount: number = math.max(math.floor(tonumber(amount) or 1), 1)
	tier = math.clamp(math.floor(tonumber(tier) or 1), 1, AnimeDroppers.MaxTier)

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if not playerTycoons[player] then
		local tycoonName = PlayerDataService:Get(player, "TycoonName")
		local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
		if tycoon then
			playerTycoons[player] = tycoon
		end
	end

	if not playerTycoons[player] then
		return false
	end

	local currentUnits = PlayerDataService:GetUnits(player)
	local nextUnits = currentUnits
	for _ = 1, grantAmount do
		nextUnits = Merge.makeRoom(nextUnits, 1)
		table.insert(nextUnits, {
			Tier = tier,
		})
		nextUnits = Merge.autoMerge(nextUnits)
	end

	PlayerDataService:SetUnits(player, nextUnits)
	return true
end

local function createCapsuleEntry(player: Player): (boolean, any?)
	local config = getCapsuleConfig()
	local maxActive = math.max(math.floor(tonumber(config.MaxActiveCapsules) or 6), 1)
	if getActiveCapsuleCount(player) >= maxActive then
		return false
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local units = PlayerDataService:GetUnits(player)
	local highestTier = CapsuleUtil.getHighestUnitTier(units)
	local previewTiers = CapsuleUtil.getPreviewTiers(highestTier)
	local purchasedUnitCount = math.max(math.floor(PlayerDataService:Get(player, "TotalUnitsPurchased") or 0), 0)
	local unitScaleCount = math.max(
		math.floor(PlayerDataService:Get(player, "TotalUnitsBought") or 0),
		purchasedUnitCount
	)
	local spawnTier = getUnitSpawnTier(PlayerDataService, player)
	local capsuleId = HttpService:GenerateGUID(false)

	activeCapsules[player] = activeCapsules[player] or {}
	activeCapsules[player][capsuleId] = {
		HighestTier = highestTier,
		PreviewTiers = previewTiers,
		OpenPrice = CapsuleUtil.getOpenPrice(highestTier, units, purchasedUnitCount, spawnTier, unitScaleCount),
		CreatedAt = os.clock(),
	}

	return true,
		{
			Id = capsuleId,
			PreviewTiers = previewTiers,
			OpenPrice = activeCapsules[player][capsuleId].OpenPrice,
			HighestTier = highestTier,
		}
end

function TycoonService:BeginOpenCapsuleForPlayer(
	player: Player,
	capsuleId: string,
	spentYen: boolean
): (boolean, string?, number?)
	local capsules = activeCapsules[player]
	local capsule = if capsules then capsules[capsuleId] else nil
	if not capsule then
		return false, "Unknown capsule"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	if spentYen then
		if not PlayerDataService:TrySpendYen(player, capsule.OpenPrice) then
			return false, "Not enough yen"
		end
	end

	local rewardTier = CapsuleUtil.rollRewardTier(capsule.HighestTier)

	capsules[capsuleId] = nil
	lastCapsuleRewardTier[player] = rewardTier
	pendingCapsuleRewards[player] = pendingCapsuleRewards[player] or {}
	pendingCapsuleRewards[player][capsuleId] = rewardTier
	return true, nil, rewardTier
end

function TycoonService.Client:GetLastCapsuleReward(player: Player): number?
	return lastCapsuleRewardTier[player]
end

function TycoonService.Client:GetPendingCapsuleReward(player: Player, capsuleId: string): number?
	if type(capsuleId) ~= "string" or capsuleId == "" then
		return nil
	end

	local rewards = pendingCapsuleRewards[player]
	return rewards and rewards[capsuleId] or nil
end

function TycoonService.Client:ClaimCapsuleReward(player: Player, capsuleId: string): (boolean, string?)
	if type(capsuleId) ~= "string" or capsuleId == "" then
		return false, "Invalid capsule"
	end

	local rewards = pendingCapsuleRewards[player]
	local rewardTier = rewards and rewards[capsuleId]
	if type(rewardTier) ~= "number" then
		return false, "No pending reward"
	end

	local granted, grantErr = grantCapsuleUnit(player, rewardTier)
	if not granted then
		return false, grantErr
	end

	rewards[capsuleId] = nil
	return true
end

function TycoonService:OpenPendingCapsulePurchase(player: Player): boolean
	local capsuleId = pendingCapsuleRobux[player]
	pendingCapsuleRobux[player] = nil
	if not capsuleId then
		return false
	end

	local success, _, rewardTier = self:BeginOpenCapsuleForPlayer(player, capsuleId, false)
	if success then
		self.Client.CapsuleRobuxOpened:Fire(player, capsuleId, rewardTier)
	end
	return success
end

function TycoonService.Client:RequestCapsuleDrop(player: Player): (boolean, any?)
	local config = getCapsuleConfig()
	local now = os.clock()
	local cooldown = tonumber(config.SpawnCooldown) or 30
	if now - (lastCapsuleSpawnAt[player] or 0) < cooldown then
		return false
	end

	local spawnChance = tonumber(config.SpawnChance) or 0.01
	spawnChance *= math.max(EventUtil.getEffectMultiplier("CapsuleSpawnChanceMultiplier", 1), 0)
	spawnChance = math.clamp(spawnChance, 0, 1)
	if math.random() > spawnChance then
		return false
	end

	lastCapsuleSpawnAt[player] = now
	return createCapsuleEntry(player)
end

function TycoonService.Client:RequestAmbientCapsule(player: Player): (boolean, any?)
	local config = getCapsuleConfig()
	local now = os.clock()
	local interval = tonumber(config.AmbientSpawnInterval) or 120
	interval *= math.max(EventUtil.getEffectMultiplier("AmbientCapsuleIntervalMultiplier", 1), 0.1)
	if now - (lastAmbientCapsuleAt[player] or 0) < interval then
		return false
	end

	lastAmbientCapsuleAt[player] = now
	return createCapsuleEntry(player)
end

function TycoonService.Client:PrepareCapsuleRobuxOpen(player: Player, capsuleId: string): boolean
	if type(capsuleId) ~= "string" or capsuleId == "" then
		return false
	end

	local capsules = activeCapsules[player]
	if not capsules or not capsules[capsuleId] then
		return false
	end

	pendingCapsuleRobux[player] = capsuleId
	lastCapsuleRewardTier[player] = nil
	return true
end

function TycoonService.Client:OpenCapsule(player: Player, capsuleId: string): (boolean, string?, number?)
	if type(capsuleId) ~= "string" or capsuleId == "" then
		return false, "Invalid capsule"
	end

	return self.Server:BeginOpenCapsuleForPlayer(player, capsuleId, true)
end

function TycoonService.Client:DismissCapsule(player: Player, capsuleId: string): boolean
	if type(capsuleId) ~= "string" or capsuleId == "" then
		return false
	end

	local capsules = activeCapsules[player]
	if not capsules or not capsules[capsuleId] then
		return false
	end

	capsules[capsuleId] = nil
	if pendingCapsuleRobux[player] == capsuleId then
		pendingCapsuleRobux[player] = nil
	end

	local rewards = pendingCapsuleRewards[player]
	if rewards then
		rewards[capsuleId] = nil
	end

	return true
end

function TycoonService:KnitStart()
	setupCollisionGroups()

	for _, player in Players:GetPlayers() do
		if player.Character then
			setCharacterCollisionGroup(player.Character)
		end
		player.CharacterAdded:Connect(setCharacterCollisionGroup)

		task.spawn(function()
			self:AssignTycoon(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		if player.Character then
			setCharacterCollisionGroup(player.Character)
		end
		player.CharacterAdded:Connect(setCharacterCollisionGroup)
		self:AssignTycoon(player)
	end)

	local GameShutdown = require(script.Parent.Parent.Modules.GameShutdown)
	local processConnection: RBXScriptConnection?

	GameShutdown.onRequested(function()
		if processConnection then
			processConnection:Disconnect()
			processConnection = nil
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if GameShutdown.isShuttingDown() then
			return
		end

		clearPlayerCapsuleState(player, true)
		self:ReleaseTycoon(player)
	end)

	local PlayerDataService = Knit.GetService("PlayerDataService")

	processConnection = RunService.Heartbeat:Connect(function(dt)
		if GameShutdown.isShuttingDown() then
			return
		end

		for _, player in Players:GetPlayers() do
			if not playerTycoons[player] then
				continue
			end

			local processInterval = getDepositInterval(player)
			processElapsed[player] = (processElapsed[player] or 0) + dt
			if processElapsed[player] < processInterval then
				continue
			end

			processElapsed[player] -= processInterval

			if shouldAutoDeposit(PlayerDataService, player) then
				PlayerDataService:DepositMana(player)
			end

			local deposit = math.floor(PlayerDataService:Get(player, "ManaInDeposit") or 0)
			local rate = math.floor(PlayerDataService:Get(player, "Rate") or 0)

			if deposit <= 0 or rate <= 0 then
				continue
			end

			local transfer = math.min(deposit, math.max(math.floor(rate), 1))
			if transfer <= 0 then
				continue
			end

			PlayerDataService:Set(player, "ManaInDeposit", deposit - transfer)
			PlayerDataService:AddYen(player, transfer * getYenMultiplier(player))
		end
	end)
end

return TycoonService
