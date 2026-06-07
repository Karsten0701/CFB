local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local RebirthUpgrades = require(ReplicatedStorage.Shared.Data.RebirthUpgrades)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local CmdrUtil = require(script.Parent.CmdrUtil)

local Handlers = {}

local function getStarterUnits(): { { Tier: number } }
	local configured = TycoonConfig.StarterUnits
	if type(configured) ~= "table" or #configured <= 0 then
		return { { Tier = 1 } }
	end

	local units = {}
	for _, unit in configured do
		if type(unit) == "table" then
			table.insert(units, { Tier = CmdrUtil.clampTier(unit.Tier or 1) })
		end
	end

	if #units <= 0 then
		table.insert(units, { Tier = 1 })
	end

	return units
end

function Handlers.addYen(_context, targetPlayer: Player, amount: number)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local add = CmdrUtil.clampAmount(amount)
	if add <= 0 then
		return "Amount must be greater than 0."
	end

	PlayerDataService:AddYen(targetPlayer, add)
	return `Added {add} Yen to {targetPlayer.Name}. Balance: {PlayerDataService:Get(targetPlayer, "Yen")}.`
end

function Handlers.removeYen(_context, targetPlayer: Player, amount: number)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local remove = CmdrUtil.clampAmount(amount)
	if remove <= 0 then
		return "Amount must be greater than 0."
	end

	local newBalance = PlayerDataService:Update(targetPlayer, "Yen", function(current: number)
		return math.max(math.floor(tonumber(current) or 0) - remove, 0)
	end)

	return `Removed {remove} Yen from {targetPlayer.Name}. Balance: {newBalance}.`
end

function Handlers.addUnit(_context, targetPlayer: Player, tier: number, amount: number)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local unitTier = CmdrUtil.clampTier(tier)
	local count = CmdrUtil.clampAmount(amount)
	if count <= 0 then
		return "Amount must be greater than 0."
	end

	local units = PlayerDataService:GetUnits(targetPlayer)
	for _ = 1, count do
		table.insert(units, { Tier = unitTier })
	end

	PlayerDataService:SetUnits(targetPlayer, units)
	return `Added {count} tier {unitTier} unit(s) to {targetPlayer.Name}. Total units: {#units}.`
end

function Handlers.removeUnit(_context, targetPlayer: Player, tier: number, amount: number)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local unitTier = CmdrUtil.clampTier(tier)
	local count = CmdrUtil.clampAmount(amount)
	if count <= 0 then
		return "Amount must be greater than 0."
	end

	local units = PlayerDataService:GetUnits(targetPlayer)
	local removed = 0
	for index = #units, 1, -1 do
		if removed >= count then
			break
		end

		local unit = units[index]
		if type(unit) == "table" and math.floor(tonumber(unit.Tier) or 0) == unitTier then
			table.remove(units, index)
			removed += 1
		end
	end

	if removed <= 0 then
		return `No tier {unitTier} units found on {targetPlayer.Name}.`
	end

	PlayerDataService:SetUnits(targetPlayer, units)
	return `Removed {removed} tier {unitTier} unit(s) from {targetPlayer.Name}. Total units: {#units}.`
end

function Handlers.removeAllUnits(_context, targetPlayer: Player)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local starterUnits = getStarterUnits()
	PlayerDataService:SetUnits(targetPlayer, starterUnits)
	return `Reset {targetPlayer.Name}'s units to starter loadout ({#starterUnits} unit(s)).`
end

function Handlers.setRebirths(_context, targetPlayer: Player, amount: number)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local rebirths = math.max(math.floor(tonumber(amount) or 0), 0)
	PlayerDataService:Set(targetPlayer, "Rebirths", rebirths)
	return `Set {targetPlayer.Name}'s rebirths to {rebirths}.`
end

function Handlers.addRebirthTokens(_context, targetPlayer: Player, amount: number)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local add = CmdrUtil.clampAmount(amount)
	if add <= 0 then
		return "Amount must be greater than 0."
	end

	local balance = PlayerDataService:AddRebirthTokens(targetPlayer, add)
	return `Added {add} rebirth token(s) to {targetPlayer.Name}. Balance: {balance}.`
end

function Handlers.setRebirthTokens(_context, targetPlayer: Player, amount: number)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local tokens = math.max(math.floor(tonumber(amount) or 0), 0)
	PlayerDataService:Set(targetPlayer, "RebirthTokens", tokens)
	return `Set {targetPlayer.Name}'s rebirth tokens to {tokens}.`
end

function Handlers.giveGamepass(_context, targetPlayer: Player, gamePassKey: string)
	local _, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	if not Monetization.GamePasses[gamePassKey] then
		return `Unknown gamepass: {gamePassKey}`
	end

	local MonetizationService = CmdrUtil.getKnitService("MonetizationService")
	local granted = MonetizationService:AdminGrantGamePass(targetPlayer, gamePassKey)
	if not granted then
		return `Failed to grant gamepass {gamePassKey} to {targetPlayer.Name}.`
	end

	return `Granted gamepass {gamePassKey} to {targetPlayer.Name}.`
end

function Handlers.revokeGamepass(_context, targetPlayer: Player, gamePassKey: string)
	local _, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	if not Monetization.GamePasses[gamePassKey] then
		return `Unknown gamepass: {gamePassKey}`
	end

	local MonetizationService = CmdrUtil.getKnitService("MonetizationService")
	local revoked = MonetizationService:AdminRevokeGamePass(targetPlayer, gamePassKey)
	if not revoked then
		return `Failed to revoke granted gamepass {gamePassKey} for {targetPlayer.Name}.`
	end

	return `Revoked granted gamepass {gamePassKey} for {targetPlayer.Name}. (Roblox-owned passes are unchanged.)`
end

function Handlers.giveProduct(_context, targetPlayer: Player, productKey: string)
	local _, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local MonetizationService = CmdrUtil.getKnitService("MonetizationService")
	local granted, reason = MonetizationService:AdminGrantProduct(targetPlayer, productKey)
	if not granted then
		return `Failed to grant product {productKey}: {reason or "unknown"}`
	end

	return `Granted product {productKey} to {targetPlayer.Name}.`
end

function Handlers.sellAll(_context, targetPlayer: Player)
	local _, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local TycoonService = CmdrUtil.getKnitService("TycoonService")
	local depositSold = TycoonService:SellAllProcessor(targetPlayer)
	return `Sold processor mana for {targetPlayer.Name}. Deposit converted: {depositSold}.`
end

function Handlers.resetDeposit(_context, targetPlayer: Player)
	local _, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local TycoonService = CmdrUtil.getKnitService("TycoonService")
	local resetRate = TycoonService:AdminResetDeposit(targetPlayer)
	return `Reset {targetPlayer.Name}'s deposit (bag + deposit mana cleared, RateLevel 0, Rate {resetRate}).`
end

function Handlers.clearLeaderboard(_context, userId: number, boardName: string)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return "UserId must be greater than 0."
	end

	local LeaderboardService = CmdrUtil.getKnitService("LeaderboardService")
	if boardName == "all" then
		local cleared = LeaderboardService:RemoveUserFromAllBoards(userId)
		return `Cleared leaderboard data for user {userId} on {cleared} board(s).`
	end

	if not LeaderboardService:RemoveUserFromBoard(boardName, userId) then
		return `Failed to clear {boardName} leaderboard for user {userId}.`
	end

	return `Cleared {boardName} leaderboard entry for user {userId}.`
end

function Handlers.resetUserLeaderboard(_context, userId: number)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return "UserId must be greater than 0."
	end

	local LeaderboardService = CmdrUtil.getKnitService("LeaderboardService")
	local cleared, err = LeaderboardService:ResetUserLeaderboard(userId)
	if cleared == nil then
		return `Failed to reset leaderboard for user {userId}: {err or "unknown"}`
	end

	return `Reset leaderboard stats for user {userId} and applied rebirth-style progress reset (units/tiers, yen, mana, rate). Cleared {cleared} board(s).`
end

function Handlers.setRebirthUpgrade(_context, targetPlayer: Player, upgradeKey: string, level: number)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local config = RebirthUpgrades[upgradeKey]
	if type(config) ~= "table" or type(config.MaxLevel) ~= "number" then
		return `Unknown rebirth upgrade: {upgradeKey}`
	end

	local upgrades = PlayerDataService:Get(targetPlayer, "RebirthUpgrades")
	if type(upgrades) ~= "table" then
		upgrades = {}
	end

	local currentLevel = math.max(math.floor(tonumber(upgrades[upgradeKey]) or 0), 0)
	local nextLevel = math.clamp(math.floor(tonumber(level) or 0), 0, config.MaxLevel)

	PlayerDataService:Set(targetPlayer, { "RebirthUpgrades", upgradeKey }, nextLevel)

	if upgradeKey == "UnitSpawnTier" and nextLevel > currentLevel then
		local units = PlayerDataService:GetUnits(targetPlayer)
		local upgradedUnits, changed = RebirthUpgrades.upgradeUnitsForSpawnTier(units, currentLevel, nextLevel)
		if changed then
			PlayerDataService:SetUnits(targetPlayer, upgradedUnits)
		end
	end

	return `Set {targetPlayer.Name}'s {upgradeKey} to level {nextLevel} (max {config.MaxLevel}).`
end

function Handlers.viewData(_context, targetPlayer: Player)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	local units = PlayerDataService:GetUnits(targetPlayer)
	local rebirthUpgrades = PlayerDataService:Get(targetPlayer, "RebirthUpgrades") or {}
	return table.concat({
		`Player: {targetPlayer.Name} ({targetPlayer.UserId})`,
		`Yen: {PlayerDataService:Get(targetPlayer, "Yen")}`,
		`LifetimeYen: {PlayerDataService:Get(targetPlayer, "LifetimeYen")}`,
		`Rebirths: {PlayerDataService:Get(targetPlayer, "Rebirths")}`,
		`RebirthTokens: {PlayerDataService:Get(targetPlayer, "RebirthTokens")}`,
		`UnitSpawnTier: {math.floor(tonumber(rebirthUpgrades.UnitSpawnTier) or 0)}`,
		`MoreMana: {math.floor(tonumber(rebirthUpgrades.MoreMana) or 0)}`,
		`BetterMaxButton: {math.floor(tonumber(rebirthUpgrades.BetterMaxButton) or 0)}`,
		`Units: {#units}`,
		`TotalUnitsPurchased: {PlayerDataService:Get(targetPlayer, "TotalUnitsPurchased")}`,
		`TotalUnitsBought: {PlayerDataService:Get(targetPlayer, "TotalUnitsBought")}`,
		`ManaInBag: {PlayerDataService:Get(targetPlayer, "ManaInBag")}`,
		`ManaInDeposit: {PlayerDataService:Get(targetPlayer, "ManaInDeposit")}`,
		`RateLevel: {PlayerDataService:Get(targetPlayer, "RateLevel")}`,
		`Rate: {PlayerDataService:Get(targetPlayer, "Rate")}`,
		`PlaytimeSeconds: {PlayerDataService:GetPlaytimeSeconds(targetPlayer)}`,
		`TycoonName: {PlayerDataService:Get(targetPlayer, "TycoonName")}`,
	}, "\n")
end

return Handlers
