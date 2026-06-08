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
	local LeaderboardService = CmdrUtil.getKnitService("LeaderboardService")
	local cleared, err = LeaderboardService:ClearUserFromLeaderboards(userId, boardName)
	if err then
		return err
	end

	if cleared <= 0 then
		return `Failed to remove user {userId} from leaderboard.`
	end

	local boardLabel = if boardName == "all" then "all boards" else boardName
	return `Removed user {userId} from {boardLabel}. Player data was not changed.`
end

function Handlers.resetData(_context, targetPlayer: Player)
	local PlayerDataService, err = CmdrUtil.requirePlayerData(targetPlayer)
	if err then
		return `Failed: {err}`
	end

	PlayerDataService:ResetPlayerData(targetPlayer)
	return `Fully reset {targetPlayer.Name}'s data. They were kicked to rejoin with a fresh save.`
end

function Handlers.resetDataUser(_context, userId: number)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return "UserId must be greater than 0."
	end

	local PlayerDataService = CmdrUtil.getKnitService("PlayerDataService")
	local ok, resetErr = PlayerDataService:ResetPlayerDataByUserId(userId)
	if not ok then
		return `Failed to reset data for user {userId}: {resetErr or "unknown"}`
	end

	local onlinePlayer = game:GetService("Players"):GetPlayerByUserId(userId)
	if onlinePlayer then
		return `Fully reset user {userId} ({onlinePlayer.Name}). They were kicked to rejoin with a fresh save.`
	end

	return `Fully reset saved data for offline user {userId}.`
end

function Handlers.resetUserLeaderboard(_context, userId: number)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return "UserId must be greater than 0."
	end

	local LeaderboardService = CmdrUtil.getKnitService("LeaderboardService")
	local published, err = LeaderboardService:ResetUserLeaderboard(userId)
	if published == nil then
		return `Failed to reset leaderboard for user {userId}: {err or "unknown"}`
	end

	if err then
		return `Reset leaderboard stats for user {userId} to 0 and republished {published} board(s), but: {err}`
	end

	return `Reset leaderboard stats for user {userId} to 0 and republished on {published} board(s). Player stays visible on leaderboards.`
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

local function isGlobalScope(scope: string?): boolean
	return tostring(scope or "global") ~= "server"
end

function Handlers.startAdminEvent(_context, eventId: string, multiplier: number, durationMinutes: number, scope: string?)
	local player = _context.Executor
	if not player or not player:IsA("Player") then
		return "Run this command in-game as an admin player."
	end

	local resolvedMultiplier = if multiplier > 0 then multiplier else nil
	local AdminService = CmdrUtil.getKnitService("AdminService")
	local ok, err = AdminService:StartAdminEvent(player, eventId, resolvedMultiplier, durationMinutes, isGlobalScope(scope))
	if not ok then
		return `Failed to start admin event: {err or "unknown"}`
	end

	local scopeLabel = if isGlobalScope(scope) then "all servers" else "this server"
	local multiplierText = if resolvedMultiplier ~= nil then ` at {resolvedMultiplier}x` else ""
	return `Started admin event "{eventId}"{multiplierText} for {durationMinutes} min on {scopeLabel}.`
end

function Handlers.stopAdminEvent(_context, scope: string?)
	local player = _context.Executor
	if not player or not player:IsA("Player") then
		return "Run this command in-game as an admin player."
	end

	local AdminService = CmdrUtil.getKnitService("AdminService")
	local ok, err = AdminService:StopAdminEvent(player, isGlobalScope(scope))
	if not ok then
		return `Failed to stop admin event: {err or "unknown"}`
	end

	return `Stopped admin event ({if isGlobalScope(scope) then "global" else "server"}).`
end

function Handlers.startAdminBoost(_context, boostType: string, multiplier: number, durationMinutes: number, scope: string?)
	local player = _context.Executor
	if not player or not player:IsA("Player") then
		return "Run this command in-game as an admin player."
	end

	local resolvedMultiplier = if multiplier > 0 then multiplier else nil
	local AdminService = CmdrUtil.getKnitService("AdminService")
	local ok, err = AdminService:StartAdminBoost(player, boostType, resolvedMultiplier, durationMinutes, isGlobalScope(scope))
	if not ok then
		return `Failed to start admin boost: {err or "unknown"}`
	end

	local multiplierText = if resolvedMultiplier ~= nil then tostring(resolvedMultiplier) else "default"
	return `Started {boostType} boost ({multiplierText}x) for {durationMinutes} min.`
end

function Handlers.stopAdminBoosts(_context, scope: string?)
	local player = _context.Executor
	if not player or not player:IsA("Player") then
		return "Run this command in-game as an admin player."
	end

	local AdminService = CmdrUtil.getKnitService("AdminService")
	local ok, err = AdminService:StopAdminBoosts(player, isGlobalScope(scope))
	if not ok then
		return `Failed to stop admin boosts: {err or "unknown"}`
	end

	return "Stopped all admin boosts."
end

function Handlers.spawnMutationBalls(_context, count: number, scope: string?)
	local player = _context.Executor
	if not player or not player:IsA("Player") then
		return "Run this command in-game as an admin player."
	end

	local AdminService = CmdrUtil.getKnitService("AdminService")
	local ok, err = AdminService:SpawnMutationBalls(player, count, isGlobalScope(scope))
	if not ok then
		return `Failed to spawn mutation balls: {err or "unknown"}`
	end

	return `Spawned {math.floor(count)} mutation ball(s) ({if isGlobalScope(scope) then "global" else "server"}).`
end

function Handlers.addLeaderboard(_context, userId: number)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return "UserId must be greater than 0."
	end

	local LeaderboardService = CmdrUtil.getKnitService("LeaderboardService")
	local ok, err = LeaderboardService:RestoreUserToLeaderboards(userId)
	if not ok then
		return `Failed to restore user {userId} to leaderboards: {err or "unknown"}`
	end

	return `User {userId} can show on leaderboards again. They will republish when online or on next update.`
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
