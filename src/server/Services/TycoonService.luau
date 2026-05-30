local Players = game:GetService("Players")
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
local processElapsed: { [Player]: number } = {}

local PROCESS_INTERVAL = 1

local function getYenMultiplier(player: Player): number
	local MonetizationService = Knit.GetService("MonetizationService")
	return if MonetizationService:OwnsGamePass(player, "DoubleYen") then 2 else 1
end

local function getManaPowerMultiplier(player: Player): number
	local MonetizationService = Knit.GetService("MonetizationService")
	return if MonetizationService:OwnsGamePass(player, "DoubleManaPower") then 2 else 1
end

local function getDepositInterval(player: Player): number
	local MonetizationService = Knit.GetService("MonetizationService")
	return if MonetizationService:OwnsGamePass(player, "DoubleDeposit") then 0.5 else PROCESS_INTERVAL
end

local function addTierOneUnits(units: { { Tier: number } }, amount: number, shouldAutoMerge: boolean): { { Tier: number } }
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

local function getMaxPickupRate(units: { { Tier: number } }): number
	local total = 0
	for _, unit in units do
		local tierData = AnimeDroppers.Tiers[unit.Tier]
		if tierData then
			total += (tierData.DropValue or 1) / 5
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
	processElapsed[player] = nil

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

function TycoonService.Client:CollectManaPower(player: Player, amount: number): (boolean, string?)
	if type(amount) ~= "number" or amount <= 0 or amount > 1_000_000_000 then
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

	if amount > maxDropValue then
		return false, "Invalid amount"
	end

	pickupBudget[player] = math.min((pickupBudget[player] or maxDropValue) + maxRate * elapsed, math.max(maxRate * 10, maxDropValue * 2))
	pickupBudgetUpdatedAt[player] = now

	if pickupBudget[player] < amount then
		return false, "Too fast"
	end

	pickupBudget[player] -= amount

	local finalAmount = amount * getManaPowerMultiplier(player)
	local MonetizationService = Knit.GetService("MonetizationService")
	if MonetizationService:OwnsGamePass(player, "AutoDeposit") then
		local depositAmount = PlayerDataService:Get(player, "ManaPowerInDeposit") or 0
		PlayerDataService:Set(player, "ManaPowerInDeposit", depositAmount + finalAmount)
	else
		PlayerDataService:AddManaPowerToBag(player, finalAmount)
	end

	return true
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

	local units = addTierOneUnits(PlayerDataService:GetUnits(player), amount, true)
	if #units > TycoonConfig.MaxUnits then
		return false
	end

	PlayerDataService:SetUnits(player, units)
	return true
end

function TycoonService:SellAllProcessor(player: Player): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local deposit = PlayerDataService:Get(player, "ManaPowerInDeposit") or 0
	if deposit <= 0 then
		return 0
	end

	PlayerDataService:Set(player, "ManaPowerInDeposit", 0)
	PlayerDataService:AddYen(player, deposit * getYenMultiplier(player))
	return deposit
end

function TycoonService.Client:DepositManaPower(player: Player): (boolean, string?)
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

	local deposited = PlayerDataService:DepositManaPower(player)
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

	local totalPurchased = PlayerDataService:Get(player, "TotalUnitsPurchased")
	local price = Pricing.getUnitBulkPrice(totalPurchased, amount)
	if not PlayerDataService:TrySpendYen(player, price) then
		return false, "Not enough yen"
	end

	local currentUnits = PlayerDataService:GetUnits(player)
	local units = addTierOneUnits(currentUnits, amount, #currentUnits + amount > TycoonConfig.MaxUnits)
	if #units > TycoonConfig.MaxUnits then
		PlayerDataService:AddYen(player, price)
		return false, "Grid full"
	end

	PlayerDataService:SetUnits(player, units)
	PlayerDataService:Set(player, "TotalUnitsPurchased", totalPurchased + amount)

	return true
end

function TycoonService.Client:MergeUnits(player: Player, buttonName: string): (boolean, string?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local tycoonName = PlayerDataService:Get(player, "TycoonName")
	local tycoon = TycoonUtil.getPlayerTycoon(player, tycoonName)
	if not tycoon then
		return false, "No tycoon"
	end

	local buttonModel = tycoon:FindFirstChild(buttonName)
	if not buttonModel or not TycoonUtil.isMergeButton(buttonModel) or not TycoonUtil.isNearButton(player, buttonModel) then
		return false, "Invalid button"
	end

	local units = PlayerDataService:GetUnits(player)
	local mergedUnits, changed = Merge.runOnce(units)
	if not changed then
		return false, "Nothing to merge"
	end

	PlayerDataService:SetUnits(player, mergedUnits)
	return true
end

function TycoonService.Client:UpgradeRate(player: Player, amount: number, buttonName: string): (boolean, string?)
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

	return true
end

function TycoonService:KnitStart()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:AssignTycoon(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
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

			local MonetizationService = Knit.GetService("MonetizationService")
			if MonetizationService:OwnsGamePass(player, "AutoDeposit") then
				PlayerDataService:DepositManaPower(player)
			end

			local deposit = math.floor(PlayerDataService:Get(player, "ManaPowerInDeposit") or 0)
			local rate = math.floor(PlayerDataService:Get(player, "Rate") or 0)

			if deposit <= 0 or rate <= 0 then
				continue
			end

			local transfer = math.min(deposit, math.max(math.floor(rate), 1))
			if transfer <= 0 then
				continue
			end

			PlayerDataService:Set(player, "ManaPowerInDeposit", deposit - transfer)
			PlayerDataService:AddYen(player, transfer * getYenMultiplier(player))
		end
	end)
end

return TycoonService
