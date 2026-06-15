local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuildConfig = require(ReplicatedStorage.Shared.Data.GuildConfig)
local GuildUtil = require(ReplicatedStorage.Shared.Features.Guilds.GuildUtil)

local GuildDataStore = {}

local guildStore = DataStoreService:GetDataStore(GuildConfig.DataStorePrefix .. "_Guilds")
local nameStore = DataStoreService:GetDataStore(GuildConfig.DataStorePrefix .. "_Names")
local leaderboardStore = DataStoreService:GetOrderedDataStore(GuildConfig.DataStorePrefix .. "_Leaderboard")
local publicIndexStore = DataStoreService:GetDataStore(GuildConfig.DataStorePrefix .. "_PublicIndex")

local PUBLIC_INDEX_KEY = "GuildIds"
local DATASTORE_RETRIES = 3

local function retryAsync(callback: () -> any): (boolean, any)
	local lastErr: any = nil
	for attempt = 1, DATASTORE_RETRIES do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(0.25 * attempt)
	end
	return false, lastErr
end

local function normalizeGuildRecord(guild: any): { [string]: any }?
	if type(guild) ~= "table" or type(guild.Id) ~= "string" or guild.Id == "" then
		return nil
	end

	if type(guild.Members) ~= "table" then
		guild.Members = {}
	end

	guild.IconId = math.max(math.floor(tonumber(guild.IconId) or 0), 0)
	guild.GuildScore = math.max(math.floor(tonumber(guild.GuildScore) or 0), 0)
	guild.MaxMembers = math.max(math.floor(tonumber(guild.MaxMembers) or GuildConfig.MaxMembers), 1)
	guild.CreatedAt = math.max(math.floor(tonumber(guild.CreatedAt) or 0), 0)
	guild.IsPublic = guild.IsPublic == true
	guild.Name = tostring(guild.Name or "")
	guild.NameKey = tostring(guild.NameKey or GuildUtil.getNameKey(guild.Name))
	guild.OwnerId = math.max(math.floor(tonumber(guild.OwnerId) or 0), 0)

	return guild
end

local function appendPublicGuildId(guildId: string)
	retryAsync(function()
		publicIndexStore:UpdateAsync(PUBLIC_INDEX_KEY, function(current)
			local ids = if type(current) == "table" then current else {}
			if table.find(ids, guildId) then
				return ids
			end
			table.insert(ids, guildId)
			return ids
		end)
	end)
end

local function getPublicGuildIds(): { string }
	local ok, result = retryAsync(function()
		return publicIndexStore:GetAsync(PUBLIC_INDEX_KEY)
	end)
	if not ok or type(result) ~= "table" then
		return {}
	end

	local ids = {}
	for _, guildId in result do
		if type(guildId) == "string" and guildId ~= "" then
			table.insert(ids, guildId)
		end
	end
	return ids
end

function GuildDataStore.generateGuildId(): string
	return HttpService:GenerateGUID(false)
end

function GuildDataStore.reserveName(nameKey: string, guildId: string): (boolean, string?)
	if nameKey == "" or guildId == "" then
		return false, "Invalid name"
	end

	local reserved = false
	local ok, err = retryAsync(function()
		nameStore:UpdateAsync(nameKey, function(current)
			if current ~= nil then
				return nil
			end
			reserved = true
			return guildId
		end)
	end)

	if not ok then
		return false, tostring(err)
	end

	if not reserved then
		return false, "Guild name already taken"
	end

	return true, nil
end

function GuildDataStore.releaseName(nameKey: string, guildId: string)
	if nameKey == "" then
		return
	end

	retryAsync(function()
		nameStore:UpdateAsync(nameKey, function(current)
			if current == guildId then
				return nil
			end
			return current
		end)
	end)
end

function GuildDataStore.appendPublicGuildId(guildId: string)
	appendPublicGuildId(guildId)
end

function GuildDataStore.saveGuild(guild: { [string]: any }): (boolean, string?)
	local normalized = normalizeGuildRecord(guild)
	if not normalized then
		return false, "Invalid guild record"
	end

	local ok, err = retryAsync(function()
		guildStore:SetAsync(normalized.Id, normalized)
	end)
	if not ok then
		return false, tostring(err)
	end

	retryAsync(function()
		leaderboardStore:SetAsync(normalized.Id, normalized.GuildScore)
	end)

	if normalized.IsPublic then
		appendPublicGuildId(normalized.Id)
	end

	return true, nil
end

function GuildDataStore.getGuild(guildId: string): { [string]: any }?
	if type(guildId) ~= "string" or guildId == "" then
		return nil
	end

	local ok, result = retryAsync(function()
		return guildStore:GetAsync(guildId)
	end)
	if not ok then
		return nil
	end

	return normalizeGuildRecord(result)
end

function GuildDataStore.getGuildByName(name: string): { [string]: any }?
	local nameKey = GuildUtil.getNameKey(name)
	if nameKey == "" then
		return nil
	end

	local ok, guildId = retryAsync(function()
		return nameStore:GetAsync(nameKey)
	end)
	if not ok or type(guildId) ~= "string" or guildId == "" then
		return nil
	end

	return GuildDataStore.getGuild(guildId)
end

function GuildDataStore.updateGuild(
	guildId: string,
	mutator: (current: { [string]: any }?) -> { [string]: any }?
): ({ [string]: any }?, string?)
	if type(guildId) ~= "string" or guildId == "" then
		return nil, "Invalid guild"
	end

	local updatedGuild: { [string]: any }? = nil
	local ok, err = retryAsync(function()
		guildStore:UpdateAsync(guildId, function(current)
			local normalized = normalizeGuildRecord(current)
			if not normalized then
				return nil
			end

			local nextGuild = mutator(normalized)
			if type(nextGuild) ~= "table" then
				return nil
			end

			nextGuild.Id = guildId
			updatedGuild = normalizeGuildRecord(nextGuild)
			return updatedGuild
		end)
	end)

	if not ok then
		return nil, tostring(err)
	end

	if updatedGuild then
		retryAsync(function()
			leaderboardStore:SetAsync(guildId, updatedGuild.GuildScore)
		end)
	end

	return updatedGuild, nil
end

function GuildDataStore.publishScore(guildId: string, score: number): boolean
	score = math.max(math.floor(tonumber(score) or 0), 0)
	local ok = retryAsync(function()
		leaderboardStore:SetAsync(guildId, score)
	end)
	return ok
end

function GuildDataStore.getGuildRank(guildId: string): number
	if type(guildId) ~= "string" or guildId == "" then
		return 0
	end

	local entries = GuildDataStore.getTopGuilds(GuildConfig.TopGuildsCount)
	for _, entry in entries do
		if entry.guild.Id == guildId then
			return entry.rank
		end
	end

	return 0
end

function GuildDataStore.getTopGuilds(limit: number?): { { guild: { [string]: any }, rank: number } }
	limit = math.max(math.floor(tonumber(limit) or GuildConfig.TopGuildsCount), 1)

	local ok, pages = retryAsync(function()
		return leaderboardStore:GetSortedAsync(false, limit)
	end)
	if not ok or not pages then
		return {}
	end

	local entries = {}
	local rank = 0
	for _, item in pages:GetCurrentPage() do
		rank += 1
		local guild = GuildDataStore.getGuild(item.key)
		if guild then
			table.insert(entries, {
				guild = guild,
				rank = rank,
			})
		end
	end

	return entries
end

function GuildDataStore.getPublicGuildsPage(page: number, pageSize: number?): ({ { guild: { [string]: any } } }, boolean)
	page = math.max(math.floor(tonumber(page) or 1), 1)
	pageSize = math.max(math.floor(tonumber(pageSize) or GuildConfig.BrowsePageSize), 1)

	local guildIds = getPublicGuildIds()
	local guilds = {}

	for _, guildId in guildIds do
		local guild = GuildDataStore.getGuild(guildId)
		if guild and guild.IsPublic then
			table.insert(guilds, guild)
		end
	end

	table.sort(guilds, function(left, right)
		if left.CreatedAt == right.CreatedAt then
			return left.Name < right.Name
		end
		return left.CreatedAt > right.CreatedAt
	end)

	local startIndex = (page - 1) * pageSize + 1
	local endIndex = page * pageSize
	local pageGuilds = {}

	for index = startIndex, math.min(endIndex, #guilds) do
		local guild = guilds[index]
		if guild then
			table.insert(pageGuilds, { guild = guild })
		end
	end

	return pageGuilds, endIndex < #guilds
end

return GuildDataStore
