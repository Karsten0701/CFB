local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
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

local topGuildsCache: {
	entries: { { guild: { [string]: any }, rank: number } },
	rankMap: { [string]: number },
	expiresAt: number,
}? = nil

local guildRecordCache: { [string]: { guild: { [string]: any }?, expiresAt: number } } = {}
local pendingLeaderboardWrites: { [string]: number } = {}
local batchLeaderboardMode = false
local leaderboardFlushThread: thread? = nil
local messagingSubscribed = false
local guildSyncSubscribed = false

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

local function getGuildRecordCacheSeconds(): number
	return math.max(math.floor(tonumber(GuildConfig.GuildRecordCacheSeconds) or 60), 1)
end

local function getLeaderboardCacheSeconds(): number
	return math.max(math.floor(tonumber(GuildConfig.LeaderboardCacheSeconds) or 300), 1)
end

local function invalidateGuildRecordCache(guildId: string?)
	if guildId then
		guildRecordCache[guildId] = nil
	else
		table.clear(guildRecordCache)
	end
end

function GuildDataStore.setBatchLeaderboardMode(enabled: boolean)
	batchLeaderboardMode = enabled == true
end

function GuildDataStore.publishLeaderboardInvalidation()
	pcall(function()
		MessagingService:PublishAsync(GuildConfig.MessagingTopicLeaderboard, {
			At = os.time(),
		})
	end)
end

function GuildDataStore.subscribeLeaderboardInvalidation()
	if messagingSubscribed then
		return
	end

	messagingSubscribed = true
	pcall(function()
		MessagingService:SubscribeAsync(GuildConfig.MessagingTopicLeaderboard, function()
			GuildDataStore.invalidateTopGuildsCache()
		end)
	end)
end

function GuildDataStore.invalidateGuildCache(guildId: string?)
	invalidateGuildRecordCache(guildId)
end

function GuildDataStore.publishGuildSync(payload: { [string]: any })
	local message = table.clone(payload)
	message.OriginJobId = game.JobId
	message.At = os.time()

	pcall(function()
		MessagingService:PublishAsync(GuildConfig.MessagingTopicGuildSync, message)
	end)
end

function GuildDataStore.subscribeGuildSync(handler: (message: { [string]: any }) -> ())
	if guildSyncSubscribed then
		return
	end

	guildSyncSubscribed = true
	pcall(function()
		MessagingService:SubscribeAsync(GuildConfig.MessagingTopicGuildSync, function(message)
			local data = message.Data
			if type(data) ~= "table" then
				return
			end

			if data.OriginJobId == game.JobId then
				return
			end

			handler(data)
		end)
	end)
end

local function writeLeaderboardScore(guildId: string, score: number)
	score = math.max(math.floor(tonumber(score) or 0), 0)
	retryAsync(function()
		leaderboardStore:SetAsync(guildId, score)
	end)
end

function GuildDataStore.queueLeaderboardScore(guildId: string, score: number)
	if type(guildId) ~= "string" or guildId == "" then
		return
	end

	pendingLeaderboardWrites[guildId] = math.max(math.floor(tonumber(score) or 0), 0)

	if leaderboardFlushThread then
		return
	end

	local delaySeconds = math.max(tonumber(GuildConfig.LeaderboardWriteIntervalSeconds) or 2, 0.5)
	leaderboardFlushThread = task.delay(delaySeconds, function()
		leaderboardFlushThread = nil
		GuildDataStore.flushLeaderboardScores()
	end)
end

function GuildDataStore.flushLeaderboardScores()
	if leaderboardFlushThread then
		task.cancel(leaderboardFlushThread)
		leaderboardFlushThread = nil
	end

	local writes = pendingLeaderboardWrites
	pendingLeaderboardWrites = {}

	local wroteAny = false
	for guildId, score in writes do
		writeLeaderboardScore(guildId, score)
		wroteAny = true
		task.wait(0.15)
	end

	if wroteAny then
		GuildDataStore.invalidateTopGuildsCache()
		GuildDataStore.publishLeaderboardInvalidation()
	end
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

local function removePublicGuildId(guildId: string)
	retryAsync(function()
		publicIndexStore:UpdateAsync(PUBLIC_INDEX_KEY, function(current)
			local ids = if type(current) == "table" then current else {}
			local index = table.find(ids, guildId)
			if index then
				table.remove(ids, index)
			end
			return ids
		end)
	end)
end

local function shuffleInPlace(list: { any })
	for index = #list, 2, -1 do
		local swapIndex = math.random(1, index)
		list[index], list[swapIndex] = list[swapIndex], list[index]
	end
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

	local okGet, currentGuildId = retryAsync(function()
		return nameStore:GetAsync(nameKey)
	end)
	if okGet and type(currentGuildId) == "string" and currentGuildId ~= "" then
		local existingGuild = GuildDataStore.getGuild(currentGuildId, true)
		if existingGuild and currentGuildId ~= guildId then
			return false, "Guild name already taken"
		end
		if not existingGuild then
			GuildDataStore.forceReleaseName(nameKey)
		end
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

function GuildDataStore.releaseName(nameKey: string, guildId: string): boolean
	if nameKey == "" then
		return true
	end

	local released = false
	local ok = retryAsync(function()
		nameStore:UpdateAsync(nameKey, function(current)
			if current == guildId then
				released = true
				return nil
			end
			return current
		end)
	end)

	return ok == true and released
end

function GuildDataStore.forceReleaseName(nameKey: string): boolean
	if nameKey == "" then
		return true
	end

	local ok = retryAsync(function()
		nameStore:RemoveAsync(nameKey)
	end)

	return ok == true
end

function GuildDataStore.appendPublicGuildId(guildId: string)
	appendPublicGuildId(guildId)
end

function GuildDataStore.removePublicGuildId(guildId: string)
	removePublicGuildId(guildId)
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

	invalidateGuildRecordCache(normalized.Id)
	writeLeaderboardScore(normalized.Id, normalized.GuildScore)

	if normalized.IsPublic then
		appendPublicGuildId(normalized.Id)
	end

	GuildDataStore.invalidateTopGuildsCache()
	GuildDataStore.publishLeaderboardInvalidation()

	return true, nil
end

function GuildDataStore.getGuild(guildId: string, bypassCache: boolean?): { [string]: any }?
	if type(guildId) ~= "string" or guildId == "" then
		return nil
	end

	if bypassCache ~= true then
		local cached = guildRecordCache[guildId]
		if cached and cached.expiresAt > os.clock() then
			return cached.guild
		end
	end

	local ok, result = retryAsync(function()
		return guildStore:GetAsync(guildId)
	end)
	if not ok then
		return nil
	end

	local normalized = normalizeGuildRecord(result)
	guildRecordCache[guildId] = {
		guild = normalized,
		expiresAt = os.clock() + getGuildRecordCacheSeconds(),
	}

	return normalized
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
	local previousScore: number? = nil
	local ok, err = retryAsync(function()
		guildStore:UpdateAsync(guildId, function(current)
			local normalized = normalizeGuildRecord(current)
			if not normalized then
				return nil
			end

			previousScore = normalized.GuildScore

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

	invalidateGuildRecordCache(guildId)

	if updatedGuild and updatedGuild.GuildScore ~= previousScore then
		if batchLeaderboardMode then
			GuildDataStore.queueLeaderboardScore(guildId, updatedGuild.GuildScore)
		else
			writeLeaderboardScore(guildId, updatedGuild.GuildScore)
			GuildDataStore.invalidateTopGuildsCache()
			GuildDataStore.publishLeaderboardInvalidation()
		end
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

function GuildDataStore.invalidateTopGuildsCache()
	topGuildsCache = nil
end

function GuildDataStore.getRankMap(): { [string]: number }
	GuildDataStore.getTopGuilds(GuildConfig.TopGuildsCount)
	if topGuildsCache and topGuildsCache.rankMap then
		return topGuildsCache.rankMap
	end
	return {}
end

function GuildDataStore.getGuildRank(guildId: string): number
	if type(guildId) ~= "string" or guildId == "" then
		return 0
	end

	local rankMap = GuildDataStore.getRankMap()
	return rankMap[guildId] or 0
end

function GuildDataStore.getTopGuilds(limit: number?): { { guild: { [string]: any }, rank: number } }
	limit = math.max(math.floor(tonumber(limit) or GuildConfig.TopGuildsCount), 1)

	if topGuildsCache and topGuildsCache.expiresAt > os.clock() then
		local cached = {}
		for index = 1, math.min(limit, #topGuildsCache.entries) do
			local entry = topGuildsCache.entries[index]
			if entry then
				table.insert(cached, entry)
			end
		end
		return cached
	end

	local ok, pages = retryAsync(function()
		return leaderboardStore:GetSortedAsync(false, limit)
	end)
	if not ok or not pages then
		return topGuildsCache and topGuildsCache.entries or {}
	end

	local entries = {}
	local rankMap: { [string]: number } = {}
	local rank = 0
	for _, item in pages:GetCurrentPage() do
		rank += 1
		local guild = GuildDataStore.getGuild(item.key)
		if guild then
			rankMap[guild.Id] = rank
			table.insert(entries, {
				guild = guild,
				rank = rank,
			})
		end
	end

	topGuildsCache = {
		entries = entries,
		rankMap = rankMap,
		expiresAt = os.clock() + getLeaderboardCacheSeconds(),
	}

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

function GuildDataStore.getBrowseGuildsRandom(limit: number?): { { guild: { [string]: any } } }
	limit = math.max(math.floor(tonumber(limit) or GuildConfig.BrowseRandomCount), 1)

	local guildIds = getPublicGuildIds()
	shuffleInPlace(guildIds)

	local result = {}
	for index = 1, math.min(limit, #guildIds) do
		local guildId = guildIds[index]
		if type(guildId) == "string" and guildId ~= "" then
			local guild = GuildDataStore.getGuild(guildId)
			if guild and guild.IsPublic then
				table.insert(result, { guild = guild })
			end
		end
	end

	return result
end

function GuildDataStore.searchPublicGuilds(query: string, limit: number?): { { guild: { [string]: any } } }
	limit = math.max(math.floor(tonumber(limit) or GuildConfig.BrowseSearchMaxResults), 1)

	local nameKey = GuildUtil.getNameKey(query)
	if nameKey == "" then
		return {}
	end

	local guildIds = getPublicGuildIds()
	local results = {}

	for _, guildId in guildIds do
		if #results >= limit then
			break
		end

		local guild = GuildDataStore.getGuild(guildId)
		if guild and guild.IsPublic then
			local guildNameKey = GuildUtil.getNameKey(guild.Name)
			if string.find(guildNameKey, nameKey, 1, true) then
				table.insert(results, { guild = guild })
			end
		end
	end

	table.sort(results, function(left, right)
		return left.guild.Name < right.guild.Name
	end)

	return results
end

function GuildDataStore.deleteGuild(guildId: string): (boolean, string?)
	if type(guildId) ~= "string" or guildId == "" then
		return false, "Invalid guild"
	end

	local guild = GuildDataStore.getGuild(guildId, true)
	if not guild then
		return false, "Guild not found"
	end

	local nameKey = guild.NameKey
	local ok, err = retryAsync(function()
		guildStore:RemoveAsync(guildId)
	end)
	if not ok then
		return false, tostring(err)
	end

	retryAsync(function()
		leaderboardStore:RemoveAsync(guildId)
	end)

	if not GuildDataStore.forceReleaseName(nameKey) then
		GuildDataStore.releaseName(nameKey, guildId)
	end
	removePublicGuildId(guildId)
	invalidateGuildRecordCache(guildId)
	pendingLeaderboardWrites[guildId] = nil
	GuildDataStore.invalidateTopGuildsCache()
	GuildDataStore.publishLeaderboardInvalidation()

	return true, nil
end

return GuildDataStore
