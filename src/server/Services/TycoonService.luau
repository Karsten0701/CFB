local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local Merge = require(ReplicatedStorage.Shared.Features.Tycoon.Merge)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local TycoonUtil = require(ReplicatedStorage.Shared.Features.Tycoon.TycoonUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local TycoonService = Knit.CreateService({
	Name = "TycoonService",
	Client = {},
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

local PROCESS_INTERVAL = 1
local DROP_INTERVAL = 5
local MAX_ACTIVE_DROPS = 200
local PLAYER_COLLISION_GROUP = "PlayerCharacters"
local DROP_COLLISION_GROUP = "ManaDrops"
local DROP_WALL_COLLISION_GROUP = "DropWalls"
local VISUAL_DATA_REQUEST_COOLDOWN = 0.35
local MUTATION_PICKUP_COOLDOWN_PADDING = 0.8

local function resetPickupBudgetTimer(player: Player)
	pickupBudget[player] = 0
	pickupBudgetUpdatedAt[player] = os.clock()
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
	if bagAmount > 0 then
		PlayerDataService:AddManaToBag(player, bagAmount)
	end

	if depositAmount > 0 then
		local currentDeposit = PlayerDataService:Get(player, "ManaInDeposit") or 0
		PlayerDataService:Set(player, "ManaInDeposit", currentDeposit + depositAmount)
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
	PhysicsService:CollisionGroupSetCollidable(DROP_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(DROP_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, false)
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

	return multiplier
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

local function getRebirthTokenReward(rebirthNumber: number): number
	rebirthNumber = math.max(math.floor(rebirthNumber), 1)
	local previousReward = 1
	local reward = 1

	for _ = 2, rebirthNumber do
		local nextReward = previousReward + reward
		previousReward = reward
		reward = nextReward
	end

	return reward
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
	return if MonetizationService:OwnsGamePass(player, "DoubleMana") then 2 else 1
end

local function getMaxMutationMultiplier(): number
	local mutationConfig = TycoonConfig.Mutations or {}
	local goldConfig = mutationConfig.Gold or {}
	local multipliers = goldConfig.Multipliers
	local maxMultiplier = 1

	if type(multipliers) == "table" then
		for _, multiplier in multipliers do
			if type(multiplier) == "number" then
				maxMultiplier = math.max(maxMultiplier, multiplier)
			end
		end
	end

	return maxMultiplier
end

local function getMutationPickupCooldown(): number
	local mutationConfig = TycoonConfig.Mutations or {}
	return math.max((tonumber(mutationConfig.Interval) or 60) * MUTATION_PICKUP_COOLDOWN_PADDING, 1)
end

local function getDepositInterval(player: Player): number
	local MonetizationService = Knit.GetService("MonetizationService")
	return if MonetizationService:OwnsGamePass(player, "DoubleDeposit") then 0.5 else PROCESS_INTERVAL
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
	shouldAutoMerge: boolean
): { { Tier: number } }
	if not shouldAutoMerge and #units + amount <= TycoonConfig.MaxUnits then
		local nextUnits = table.clone(units)
		for _ = 1, amount do
			table.insert(nextUnits, { Tier = 1 })
		end

		return Merge.sortUnits(nextUnits)
	end

	local counts = {}
	for _, unit in units do
		local tier = math.clamp(unit.Tier or 1, 1, AnimeDroppers.MaxTier)
		counts[tier] = (counts[tier] or 0) + 1
	end

	counts[1] = (counts[1] or 0) + amount

	for tier = 1, AnimeDroppers.MaxTier do
		local tierData = AnimeDroppers.Tiers[tier]
		local targetTier = tierData and tierData.MergeInto
		if not targetTier or not AnimeDroppers.Tiers[targetTier] then
			continue
		end

		local count = counts[tier] or 0
		local mergeCount = math.floor(count / TycoonConfig.MergeRatio)
		if mergeCount > 0 then
			counts[tier] = count - mergeCount * TycoonConfig.MergeRatio
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
	return autoMergeAt <= 1 or currentUnitCount + amount > autoMergeAt or currentUnitCount + amount > TycoonConfig.MaxUnits
end

local function getPlayerSettings(PlayerDataService, player: Player): { [string]: any }
	local settings = PlayerDataService:Get(player, "Settings")
	return if type(settings) == "table" then settings else {}
end

local function shouldAutoDeposit(PlayerDataService, player: Player): boolean
	local settings = getPlayerSettings(PlayerDataService, player)
	return settings.AutoDeposit == true
end

local function getMaxPickupRate(units: { { Tier: number } }): number
	local total = 0
	for _, unit in units do
		local tierData = AnimeDroppers.Tiers[unit.Tier]
		if tierData then
			total += (tierData.DropValue or 1) / DROP_INTERVAL
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

	local units = PlayerDataService:GetUnits(player)
	local maxRate = getMaxPickupRate(units)
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

	local maxStoredDropValue = math.max(maxRate * DROP_INTERVAL * MAX_ACTIVE_DROPS, maxDropValue * MAX_ACTIVE_DROPS)
	pickupBudget[player] = math.min((pickupBudget[player] or 0) + maxRate * elapsed, maxStoredDropValue)
	pickupBudgetUpdatedAt[player] = now

	local availablePickupBudget = pickupBudget[player] or 0
	local remainingAmount = amount
	local normalPickupAmount = math.min(availablePickupBudget, remainingAmount)
	remainingAmount -= normalPickupAmount
	local normalBurstAllowance = math.max(maxRate * DROP_INTERVAL + maxDropValue, maxDropValue)
	local burstPickupAmount = math.min(normalBurstAllowance, remainingAmount)
	remainingAmount -= burstPickupAmount
	local creditedAmount = normalPickupAmount + burstPickupAmount

	pickupBudget[player] = math.max(availablePickupBudget - normalPickupAmount, 0)

	if remainingAmount > 0.001 then
		local maxMutationValue = maxDropValue * getMaxMutationMultiplier()
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
	local compactUnits = table.create(#units)
	for _, unit in units do
		table.insert(compactUnits, {
			Tier = unit.Tier,
			Slot = unit.Slot,
		})
	end

	-- Visual-only payload. Server stays authoritative for money, drops, buys and merges.
	return true, {
		TycoonName = tycoon.Name,
		OwnerUserId = owner.UserId,
		Units = compactUnits,
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
	local units =
		addTierOneUnits(currentUnits, amount, shouldAutoMergeUnitBuy(PlayerDataService, player, #currentUnits, amount))
	if #units > TycoonConfig.MaxUnits then
		return false
	end

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

function TycoonService.Client:DepositMana(player: Player): (boolean, string?)
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

	return true
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
	local baseUnitCount = Pricing.getBaseUnitCount(currentUnits)
	local price = Pricing.getUnitBulkPrice(baseUnitCount, amount)
	if not PlayerDataService:TrySpendYen(player, price) then
		return false, "Not enough yen"
	end

	local units =
		addTierOneUnits(currentUnits, amount, shouldAutoMergeUnitBuy(PlayerDataService, player, #currentUnits, amount))
	if #units > TycoonConfig.MaxUnits then
		PlayerDataService:AddYen(player, price)
		return false, "Grid full"
	end

	PlayerDataService:SetUnits(player, units)
	PlayerDataService:Set(player, "TotalUnitsPurchased", baseUnitCount + amount)

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
	if not buttonModel or not TycoonUtil.isBuyMaxUnitsButton(buttonModel) or not TycoonUtil.isNearButton(player, buttonModel) then
		return false, "Invalid button"
	end

	local currentUnits = PlayerDataService:GetUnits(player)
	local baseUnitCount = Pricing.getBaseUnitCount(currentUnits)
	local yen = PlayerDataService:Get(player, "Yen") or 0
	local amount, price = Pricing.getMaxAffordableUnitPurchase(baseUnitCount, yen)
	if amount <= 0 or price <= 0 then
		return false, "Not enough yen"
	end

	if not PlayerDataService:TrySpendYen(player, price) then
		return false, "Not enough yen"
	end

	local units = addTierOneUnits(currentUnits, amount, true)
	if #units > TycoonConfig.MaxUnits then
		PlayerDataService:AddYen(player, price)
		return false, "Grid full"
	end

	PlayerDataService:SetUnits(player, units)
	PlayerDataService:Set(player, "TotalUnitsPurchased", baseUnitCount + amount)

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

	local rebirthConfig = TycoonConfig.Rebirth
	local nextRebirths = rebirths + 1
	local tokenReward = getRebirthTokenReward(nextRebirths)
	local currentTokens = math.max(math.floor(PlayerDataService:Get(player, "RebirthTokens") or 0), 0)
	local resetYen = if rebirthConfig.ResetYen ~= nil then rebirthConfig.ResetYen else 100
	PlayerDataService:Set(player, "Rebirths", nextRebirths)
	PlayerDataService:Set(player, "RebirthTokens", currentTokens + tokenReward)
	PlayerDataService:Set(player, "Yen", resetYen)
	PlayerDataService:Set(player, "ManaInBag", 0)
	PlayerDataService:Set(player, "ManaInDeposit", 0)
	PlayerDataService:Set(player, "TotalUnitsPurchased", 0)
	PlayerDataService:Set(player, "RateLevel", 0)
	PlayerDataService:Set(player, "Rate", rebirthConfig.ResetRate or 1)
	PlayerDataService:SetUnits(player, rebirthConfig.StarterUnits or { { Tier = 1 } })
	resetPickupBudgetTimer(player)

	return true, nil, nextRebirths, tokenReward
end

function TycoonService.Client:UpgradeRate(player: Player, amount: number, buttonName: string): (boolean, string?, number?)
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

	return true, nil, gain
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
	if not buttonModel or not TycoonUtil.isRateMaxButton(buttonModel) or not TycoonUtil.isNearButton(player, buttonModel) then
		return false, "Invalid button"
	end

	local rateLevel = PlayerDataService:Get(player, "RateLevel")
	local yen = PlayerDataService:Get(player, "Yen") or 0
	local amount, price, gain = Pricing.getMaxAffordableRateUpgrade(rateLevel, yen)
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

function TycoonService.Client:ClaimGroupReward(player: Player, buttonName: string): (boolean, string?, number?, number?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local buttonModel = tycoon:FindFirstChild(buttonName)
	if not buttonModel or not TycoonUtil.isGroupRewardButton(buttonModel) or not TycoonUtil.isNearButton(player, buttonModel) then
		return false, "Invalid button"
	end

	if not isPlayerInRewardGroup(player) then
		return false, "Not in group"
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

	Players.PlayerRemoving:Connect(function(player)
		self:ReleaseTycoon(player)
	end)

	local PlayerDataService = Knit.GetService("PlayerDataService")

	RunService.Heartbeat:Connect(function(dt)
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
