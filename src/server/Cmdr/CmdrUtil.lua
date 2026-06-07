--[[
	Shared helpers for CFB Cmdr server command modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.knit)

local CmdrUtil = {}

function CmdrUtil.getKnitService(name: string): any
	return Knit.GetService(name)
end

function CmdrUtil.getPlayerDataService(): any
	return Knit.GetService("PlayerDataService")
end

function CmdrUtil.requirePlayerData(player: Player): (any?, string?)
	local PlayerDataService = CmdrUtil.getPlayerDataService()
	PlayerDataService:WaitForData(player)
	return PlayerDataService, nil
end

function CmdrUtil.clampTier(tier: number): number
	local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
	return math.clamp(math.floor(tonumber(tier) or 1), 1, AnimeDroppers.MaxTier)
end

function CmdrUtil.clampAmount(amount: number): number
	return math.max(math.floor(tonumber(amount) or 0), 0)
end

return CmdrUtil
