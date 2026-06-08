local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.knit)
local LeaderboardConfig = require(script.Parent.Parent.Features.Leaderboards.LeaderboardConfig)
local TopTierRig = require(script.Parent.Parent.Features.Leaderboards.TopTierRig)
local WorldLeaderboardRenderer = require(script.Parent.Parent.Features.Leaderboards.WorldLeaderboardRenderer)

local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",
	Client = {},
})

local orderedStores: { [string]: OrderedDataStore } = {}
local displayValueStores: { [string]: GlobalDataStore } = {}
local lastPublishedValues: { [number]: { [string]: number } } = {}
local failedOrderedReads: { [string]: { [number]: boolean } } = {}
local failedDisplayReads: { [string]: { [number]: boolean } } = {}
local sortedReadUnavailable: { [string]: boolean } = {}
local playerPublishConnections: { [Player]: { RBXScriptConnection } } = {}
local dirtyPlayers: { [Player]: boolean } = {}
local displayValueCache: { [string]: { [number]: { Value: number, FetchedAt: number } } } = {}
local dirtyDebounceScheduled: { [Player]: boolean } = {}
local publishQueue: { [Player]: boolean } = {}
local lastPublishAttemptAt: { [Player]: number } = {}
local publishWorkerRunning = false
local excludedFromBoards: { [number]: { [string]: boolean } } = {}
local isShuttingDown = false

type PublishOptions = {
	fast: boolean?,
	allowOnShutdown: boolean?,
}

local function resolvePublishOptions(options: PublishOptions?): PublishOptions
	return options or {}
end

local LOG_SORT_SCALE = 1_000_000
local ORDERED_SORT_MAX = 2_147_483_647
local DISPLAY_VALUE_CACHE_SECONDS = 300
local lastLowBudgetWarnAt = -math.huge
local lastPublishErrorWarnAt = -math.huge
local lastReadErrorWarnAt = -math.huge

local function normalizeValue(value: any): number
	return math.max(math.floor(tonumber(value) or 0), 0)
end

local function getLegacyTieBreakModulus(): number
	return math.max(math.floor(tonumber(LeaderboardConfig.LegacyTieBreakModulus) or LOG_SORT_SCALE), 2)
end

local function getSanityMax(boardConfig): number?
	local sanityMax = LeaderboardConfig.SanityMax
	if type(sanityMax) ~= "table" or type(boardConfig.DataPath) ~= "string" then
		return nil
	end

	local maxValue = tonumber(sanityMax[boardConfig.DataPath])
	if maxValue == nil or maxValue ~= maxValue then
		return nil
	end

	return math.max(math.floor(maxValue), 1)
end

local function shouldResetExcessiveValue(boardConfig, value: number): boolean
	local maxValue = getSanityMax(boardConfig)
	if not maxValue then
		return false
	end

	return normalizeValue(value) > maxValue
end

local function resetLeaderboardStatForPlayer(PlayerDataService, player: Player, statPath: string)
	pcall(function()
		PlayerDataService:ResetLeaderboardStat(player, statPath)
	end)
end

local publishBoardForUserId

local function prepareLeaderboardValue(
	PlayerDataService,
	player: Player?,
	boardConfig,
	rawValue: number
): number
	rawValue = normalizeValue(rawValue)
	if not shouldResetExcessiveValue(boardConfig, rawValue) then
		return rawValue
	end

	if player and type(boardConfig.DataPath) == "string" then
		resetLeaderboardStatForPlayer(PlayerDataService, player, boardConfig.DataPath)
	end

	return 0
end

local function decodeLegacyLinearSortValue(sortValue: number): number
	sortValue = normalizeValue(sortValue)
	local modulus = getLegacyTieBreakModulus()
	if sortValue < modulus then
		return sortValue
	end

	local legacyPrimary = math.floor(sortValue / modulus)
	local remainder = sortValue % modulus
	if remainder > 0 and legacyPrimary > 0 and legacyPrimary < sortValue then
		return legacyPrimary
	end

	return sortValue
end

local function getStore(boardConfig): OrderedDataStore
	local storeName = LeaderboardConfig.DataStorePrefix .. boardConfig.DataStoreName
	local store = orderedStores[storeName]
	if store then
		return store
	end

	store = DataStoreService:GetOrderedDataStore(storeName)
	orderedStores[storeName] = store
	return store
end

local function getDisplayValueStore(boardConfig): GlobalDataStore?
	if boardConfig.SortMode ~= "Logarithmic" then
		return nil
	end

	local storeName = LeaderboardConfig.DataStorePrefix .. boardConfig.DataStoreName .. "_DisplayValues"
	local store = displayValueStores[storeName]
	if store then
		return store
	end

	store = DataStoreService:GetDataStore(storeName)
	displayValueStores[storeName] = store
	return store
end

local function hasDisplayReadFailed(storeName: string, userId: number): boolean
	local failedUsers = failedDisplayReads[storeName]
	return type(failedUsers) == "table" and failedUsers[userId] == true
end

local function markDisplayReadFailed(storeName: string, userId: number)
	failedDisplayReads[storeName] = failedDisplayReads[storeName] or {}
	failedDisplayReads[storeName][userId] = true
end

local function safeDisplayValueGetAsync(boardConfig, userId: number): (boolean, number?)
	local valueStore = getDisplayValueStore(boardConfig)
	if not valueStore then
		return false, nil
	end

	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return false, nil
	end

	local storeName = LeaderboardConfig.DataStorePrefix .. boardConfig.DataStoreName .. "_DisplayValues"
	if hasDisplayReadFailed(storeName, userId) then
		return false, nil
	end

	local ok, result = pcall(function()
		return valueStore:GetAsync(tostring(userId))
	end)
	if ok and type(result) == "number" and result >= 0 then
		return true, normalizeValue(result)
	end

	markDisplayReadFailed(storeName, userId)
	return false, nil
end

local function getReadRetrySettings(): (number, number)
	local readRetries = math.max(math.floor(tonumber(LeaderboardConfig.ReadRetryCount) or 3), 1)
	local readRetryDelay = math.max(tonumber(LeaderboardConfig.ReadRetryDelaySeconds) or 2, 0.5)
	return readRetries, readRetryDelay
end

local function hasOrderedReadFailed(storeName: string, userId: number): boolean
	local failedUsers = failedOrderedReads[storeName]
	return type(failedUsers) == "table" and failedUsers[userId] == true
end

local function markOrderedReadFailed(storeName: string, userId: number)
	failedOrderedReads[storeName] = failedOrderedReads[storeName] or {}
	failedOrderedReads[storeName][userId] = true
end

local function safeOrderedGetAsync(store: OrderedDataStore, storeName: string, userId: number): (boolean, number?)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 or hasOrderedReadFailed(storeName, userId) then
		return false, nil
	end

	local readRetries, readRetryDelay = getReadRetrySettings()
	for attempt = 1, readRetries do
		local ok, result = pcall(function()
			return store:GetAsync(tostring(userId))
		end)
		if ok and type(result) == "number" then
			return true, normalizeValue(result)
		end

		if attempt < readRetries then
			task.wait(readRetryDelay * attempt)
		end
	end

	markOrderedReadFailed(storeName, userId)
	return false, nil
end

local function getBudget(requestType: Enum.DataStoreRequestType): number
	return DataStoreService:GetRequestBudgetForRequestType(requestType)
end

local function waitForBudget(
	requestType: Enum.DataStoreRequestType,
	minimumBudget: number,
	timeoutSeconds: number?
): boolean
	if isShuttingDown then
		return getBudget(requestType) >= minimumBudget
	end

	local timeout = timeoutSeconds or LeaderboardConfig.WriteBudgetWaitTimeout or 25
	local deadline = os.clock() + timeout

	while os.clock() < deadline do
		if getBudget(requestType) >= minimumBudget then
			return true
		end
		task.wait(0.5)
	end

	return false
end

local function hasWriteBudget(requestType: Enum.DataStoreRequestType, minimumBudget: number): boolean
	return getBudget(requestType) >= minimumBudget
end

local function safeDisplayValueSetAsync(boardConfig, userId: number, value: number): boolean
	local valueStore = getDisplayValueStore(boardConfig)
	if not valueStore then
		return false
	end

	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return false
	end

	if not waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync, 1, 5) then
		return false
	end

	local ok = pcall(function()
		valueStore:SetAsync(tostring(userId), normalizeValue(value))
	end)
	return ok
end

local function warnLowBudget(requestType: Enum.DataStoreRequestType)
	local now = os.clock()
	if now - lastLowBudgetWarnAt < (LeaderboardConfig.LowBudgetWarnCooldown or 300) then
		return
	end

	lastLowBudgetWarnAt = now
	warn("[LeaderboardService] Datastore budget unavailable for", requestType.Name)
end

local function warnPublishFailed(boardName: string, userId: number, err: any)
	local now = os.clock()
	if now - lastPublishErrorWarnAt < (LeaderboardConfig.LowBudgetWarnCooldown or 300) then
		return
	end

	lastPublishErrorWarnAt = now
	warn("[LeaderboardService] Failed to publish", boardName, userId, err)
end

local function warnReadFailed(message: string, ...)
	local now = os.clock()
	if now - lastReadErrorWarnAt < (LeaderboardConfig.LowBudgetWarnCooldown or 300) then
		return
	end

	lastReadErrorWarnAt = now
	warn(message, ...)
end

local function getPrimarySortValue(boardConfig, value: number): number
	value = normalizeValue(value)
	if boardConfig.SortMode == "Logarithmic" then
		if value <= 1 then
			return value
		end

		return math.max(math.floor(math.log10(value) * LOG_SORT_SCALE), 1)
	end

	return value
end

local function decodeLogSortValue(sortValue: number): number
	return math.floor(10 ^ (normalizeValue(sortValue) / LOG_SORT_SCALE))
end

local function isLogEncodedSortValue(sortValue: number): boolean
	sortValue = normalizeValue(sortValue)
	if sortValue <= 1 then
		return true
	end

	local decodedValue = decodeLogSortValue(sortValue)
	if decodedValue < 2 then
		return false
	end

	-- Legacy boards stored raw yen directly in the ordered datastore.
	if sortValue >= LOG_SORT_SCALE and decodedValue < sortValue / 10 then
		return false
	end

	local reencoded = math.floor(math.log10(decodedValue) * LOG_SORT_SCALE)
	return math.abs(reencoded - sortValue) <= 1
end

local function resolveLogarithmicDisplayValue(sortValue: number): number
	sortValue = normalizeValue(sortValue)
	if sortValue <= 1 then
		return sortValue
	end

	if isLogEncodedSortValue(sortValue) then
		return decodeLogSortValue(sortValue)
	end

	return decodeLegacyLinearSortValue(sortValue)
end

local function getSortValue(boardConfig, value: number): number
	return getPrimarySortValue(boardConfig, value)
end

local function getPlayerValue(PlayerDataService, player: Player, boardConfig): number
	local rawValue = if boardConfig.DataPath == "PlaytimeSeconds"
		then PlayerDataService:GetPlaytimeSeconds(player)
		else PlayerDataService:Get(player, boardConfig.DataPath)

	return prepareLeaderboardValue(PlayerDataService, player, boardConfig, rawValue)
end

local function resolveDisplayValue(boardConfig, sortValue: number): number
	if boardConfig.SortMode == "Logarithmic" then
		return resolveLogarithmicDisplayValue(sortValue)
	end

	return decodeLegacyLinearSortValue(sortValue)
end

local function isCorruptOrderedSortValue(boardConfig, sortValue: number): boolean
	sortValue = normalizeValue(sortValue)
	if boardConfig.SortMode ~= "Logarithmic" and sortValue > ORDERED_SORT_MAX then
		return true
	end

	return shouldResetExcessiveValue(boardConfig, resolveDisplayValue(boardConfig, sortValue))
end

local function tryGetSortedPages(
	store: OrderedDataStore,
	ascending: boolean,
	pageSize: number,
	readRetries: number,
	readRetryDelay: number
): (boolean, any)
	local ok = false
	local pagesOrErr: any = nil

	for attempt = 1, readRetries do
		ok, pagesOrErr = pcall(function()
			return store:GetSortedAsync(ascending, pageSize)
		end)
		if ok then
			return true, pagesOrErr
		end

		if attempt < readRetries then
			task.wait(readRetryDelay * attempt)
		end
	end

	return false, pagesOrErr
end

local function getWriteSpacing(): number
	return LeaderboardConfig.WriteSpacing or 0.6
end

local function isUserExcludedFromBoard(userId: number, boardName: string): boolean
	local userBoards = excludedFromBoards[userId]
	return type(userBoards) == "table" and userBoards[boardName] == true
end

local function excludeUserFromBoard(userId: number, boardName: string)
	excludedFromBoards[userId] = excludedFromBoards[userId] or {}
	excludedFromBoards[userId][boardName] = true
end

local function clearOnlinePublishState(userId: number)
	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if not onlinePlayer then
		return
	end

	dirtyPlayers[onlinePlayer] = nil
	dirtyDebounceScheduled[onlinePlayer] = nil
	publishQueue[onlinePlayer] = nil
	lastPublishAttemptAt[onlinePlayer] = nil
end

local function correctExcessiveDatastoreEntry(
	boardName: string,
	boardConfig,
	userId: number,
	PlayerDataService
)
	task.spawn(function()
		if isShuttingDown then
			return
		end

		publishBoardForUserId(userId, boardName, boardConfig, 0, 0)
		displayValueCache[boardName] = displayValueCache[boardName] or {}
		displayValueCache[boardName][userId] = {
			Value = 0,
			FetchedAt = os.clock(),
		}

		local onlinePlayer = Players:GetPlayerByUserId(userId)
		if onlinePlayer and type(boardConfig.DataPath) == "string" then
			resetLeaderboardStatForPlayer(PlayerDataService, onlinePlayer, boardConfig.DataPath)
		end
	end)
end

publishBoardForUserId = function(
	userId: number,
	boardName: string,
	boardConfig,
	value: number,
	sortValue: number,
	options: PublishOptions?
): boolean
	local publishOptions = resolvePublishOptions(options)
	local fast = publishOptions.fast == true

	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return false
	end

	displayValueCache[boardName] = displayValueCache[boardName] or {}
	displayValueCache[boardName][userId] = {
		Value = value,
		FetchedAt = os.clock(),
	}

	if boardConfig.SortMode == "Logarithmic" and not fast and not isShuttingDown then
		safeDisplayValueSetAsync(boardConfig, userId, value)
		task.wait(getWriteSpacing())
	end

	local budgetOk = if fast or isShuttingDown
		then hasWriteBudget(Enum.DataStoreRequestType.OrderedWrite, 1)
		else waitForBudget(Enum.DataStoreRequestType.OrderedWrite, 1)
	if not budgetOk then
		if not fast then
			warnLowBudget(Enum.DataStoreRequestType.OrderedWrite)
		end
		return false
	end

	local store = getStore(boardConfig)
	local ok, err = pcall(function()
		store:SetAsync(tostring(userId), sortValue)
	end)

	if not ok then
		if not fast then
			warnPublishFailed(boardName, userId, err)
		end
		return false
	end

	lastPublishedValues[userId] = lastPublishedValues[userId] or {}
	lastPublishedValues[userId][boardName] = sortValue
	return true
end

local function collectRecoveryCandidateUserIds(boardName: string): { number }
	local userIds = {}
	local seen: { [number]: boolean } = {}

	local function addUserId(userId: number)
		userId = math.floor(tonumber(userId) or 0)
		if userId <= 0 or seen[userId] or isUserExcludedFromBoard(userId, boardName) then
			return
		end

		seen[userId] = true
		table.insert(userIds, userId)
	end

	for _, player in Players:GetPlayers() do
		addUserId(player.UserId)
	end

	for userId, boards in lastPublishedValues do
		if type(boards) == "table" and boards[boardName] ~= nil then
			addUserId(userId)
		end
	end

	return userIds
end

local function recoverCorruptBoardEntries(
	boardName: string,
	boardConfig,
	PlayerDataService
): number
	local store = getStore(boardConfig)
	local fixed = 0

	local storeName = LeaderboardConfig.DataStorePrefix .. boardConfig.DataStoreName
	for _, userId in collectRecoveryCandidateUserIds(boardName) do
		local readOk, sortValue = safeOrderedGetAsync(store, storeName, userId)
		if not readOk or sortValue == nil then
			continue
		end

		if isCorruptOrderedSortValue(boardConfig, sortValue) then
			correctExcessiveDatastoreEntry(boardName, boardConfig, userId, PlayerDataService)
			fixed += 1
			task.wait(getWriteSpacing())
		end
	end

	return fixed
end

local function finalizeEntriesForRender(
	boardName: string,
	boardConfig,
	entries: { { UserId: number, Value: number } }
)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local validEntries = {}
	for _, entry in entries do
		local value = normalizeValue(entry.Value)
		if value < 0 then
			continue
		end

		if shouldResetExcessiveValue(boardConfig, value) then
			correctExcessiveDatastoreEntry(boardName, boardConfig, entry.UserId, PlayerDataService)
			value = 0
		end

		table.insert(validEntries, {
			UserId = entry.UserId,
			Value = value,
		})
	end

	table.sort(validEntries, function(left, right)
		if left.Value == right.Value then
			return left.UserId < right.UserId
		end

		return left.Value > right.Value
	end)

	local maxEntries = LeaderboardConfig.MaxEntries or 100
	while #validEntries > maxEntries do
		table.remove(validEntries)
	end

	return validEntries
end

function LeaderboardService:publishBoard(
	player: Player,
	boardName: string,
	boardConfig,
	value: number,
	sortValue: number,
	options: PublishOptions?
): boolean
	return publishBoardForUserId(player.UserId, boardName, boardConfig, value, sortValue, options)
end

function LeaderboardService:publishZeroLeaderboardForUser(userId: number): (number, boolean)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return 0, false
	end

	local published = 0
	for boardName, boardConfig in LeaderboardConfig.Boards do
		if isUserExcludedFromBoard(userId, boardName) then
			continue
		end

		if not publishBoardForUserId(userId, boardName, boardConfig, 0, 0) then
			return published, false
		end

		published += 1
		task.wait(getWriteSpacing())
	end

	return published, true
end

function LeaderboardService:publishPlayer(player: Player, force: boolean?, options: PublishOptions?): boolean
	local publishOptions = resolvePublishOptions(options)
	if isShuttingDown and not publishOptions.allowOnShutdown then
		return false
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local dataReady, dataErr = pcall(function()
		PlayerDataService:WaitForData(player)
	end)
	if not dataReady then
		if not publishOptions.fast then
			warn("[LeaderboardService] Skipping publish; player data unavailable.", dataErr)
		end
		return false
	end

	lastPublishedValues[player.UserId] = lastPublishedValues[player.UserId] or {}
	local hadFailure = false
	local fast = publishOptions.fast == true

	for boardName, boardConfig in LeaderboardConfig.Boards do
		if isShuttingDown and not publishOptions.allowOnShutdown then
			break
		end

		if isUserExcludedFromBoard(player.UserId, boardName) then
			continue
		end

		local value = getPlayerValue(PlayerDataService, player, boardConfig)
		if value <= 0 and not force then
			continue
		end

		local sortValue = getSortValue(boardConfig, value)
		if not force and lastPublishedValues[player.UserId][boardName] == sortValue then
			continue
		end

		if not self:publishBoard(player, boardName, boardConfig, value, sortValue, publishOptions) then
			hadFailure = true
			if not fast then
				break
			end
			continue
		end

		if not fast and not isShuttingDown then
			task.wait(getWriteSpacing())
		end
	end

	if hadFailure and not fast then
		dirtyPlayers[player] = true
		return false
	end

	dirtyPlayers[player] = nil
	return not hadFailure
end

function LeaderboardService:getDisplayValue(boardName: string, boardConfig, userId: number, sortValue: number): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	displayValueCache[boardName] = displayValueCache[boardName] or {}
	local cached = displayValueCache[boardName][userId]
	if cached and os.clock() - cached.FetchedAt < DISPLAY_VALUE_CACHE_SECONDS then
		return cached.Value
	end

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		local ok, value = pcall(function()
			return getPlayerValue(PlayerDataService, onlinePlayer, boardConfig)
		end)
		if ok and value >= 0 then
			local displayValue = prepareLeaderboardValue(PlayerDataService, onlinePlayer, boardConfig, value)
			displayValueCache[boardName][userId] = {
				Value = displayValue,
				FetchedAt = os.clock(),
			}
			return displayValue
		end
	end

	if isCorruptOrderedSortValue(boardConfig, sortValue) then
		correctExcessiveDatastoreEntry(boardName, boardConfig, userId, PlayerDataService)
		return 0
	end

	return resolveDisplayValue(boardConfig, sortValue)
end

local function enrichEntriesFromDisplayStore(
	boardName: string,
	boardConfig,
	entries: { { UserId: number, Value: number } },
	PlayerDataService
)
	if boardConfig.SortMode ~= "Logarithmic" then
		return
	end

	local spacing = math.max(tonumber(LeaderboardConfig.DisplayReadSpacing) or getWriteSpacing(), 0.25)
	for _, entry in entries do
		if isShuttingDown then
			break
		end

		if waitForBudget(Enum.DataStoreRequestType.GetAsync, 1, 5) then
			local readOk, storedValue = safeDisplayValueGetAsync(boardConfig, entry.UserId)
			if readOk and storedValue ~= nil then
				local displayValue = prepareLeaderboardValue(PlayerDataService, nil, boardConfig, storedValue)
				entry.Value = displayValue
				displayValueCache[boardName] = displayValueCache[boardName] or {}
				displayValueCache[boardName][entry.UserId] = {
					Value = displayValue,
					FetchedAt = os.clock(),
				}
			end
		end

		task.wait(spacing)
	end
end

function LeaderboardService:markPlayerDirty(player: Player, immediate: boolean?)
	if not player.Parent then
		return
	end

	if immediate then
		dirtyPlayers[player] = true
		self:schedulePlayerPublish(player, true)
		return
	end

	if dirtyDebounceScheduled[player] then
		return
	end

	dirtyDebounceScheduled[player] = true
	task.delay(LeaderboardConfig.PublishDebounceSeconds or 90, function()
		dirtyDebounceScheduled[player] = nil
		if not player.Parent then
			return
		end

		dirtyPlayers[player] = true
		self:schedulePlayerPublish(player, false)
	end)
end

function LeaderboardService:schedulePlayerPublish(player: Player, force: boolean?)
	if isShuttingDown then
		return
	end

	if force then
		publishQueue[player] = true
	else
		publishQueue[player] = publishQueue[player] == true
	end

	self:startPublishWorker()
end

function LeaderboardService:startPublishWorker()
	if publishWorkerRunning or isShuttingDown then
		return
	end

	publishWorkerRunning = true
	task.spawn(function()
		while next(publishQueue) ~= nil do
			if isShuttingDown then
				for queuedPlayer in publishQueue do
					publishQueue[queuedPlayer] = nil
				end
				break
			end

			local nextPlayer: Player? = nil
			local forcePublish = false

			for player, forced in publishQueue do
				nextPlayer = player
				forcePublish = forced == true
				break
			end

			if not nextPlayer then
				break
			end

			publishQueue[nextPlayer] = nil

			if not nextPlayer.Parent and not forcePublish then
				continue
			end

			local minInterval = LeaderboardConfig.MinPublishIntervalSeconds or 180
			local lastAttempt = lastPublishAttemptAt[nextPlayer] or 0
			if not forcePublish and os.clock() - lastAttempt < minInterval then
				local retryDelay = minInterval - (os.clock() - lastAttempt)
				task.delay(retryDelay, function()
					if nextPlayer.Parent or forcePublish then
						self:schedulePlayerPublish(nextPlayer, forcePublish)
					end
				end)
				continue
			end

			lastPublishAttemptAt[nextPlayer] = os.clock()
			self:publishPlayer(nextPlayer, forcePublish)
			task.wait(LeaderboardConfig.PublishPlayerDelay or 2)
		end

		publishWorkerRunning = false
	end)
end

function LeaderboardService:publishOnlinePlayers(force: boolean?)
	for _, player in Players:GetPlayers() do
		if force or dirtyPlayers[player] then
			self:schedulePlayerPublish(player, force == true)
		end
	end
end

function LeaderboardService:buildBoardEntriesFromPages(
	boardName: string,
	boardConfig,
	pages: any
): { { UserId: number, Value: number } }
	local entries = {}
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if not userId or isUserExcludedFromBoard(userId, boardName) then
			continue
		end

		local sortValue = normalizeValue(item.value)
		table.insert(entries, {
			UserId = userId,
			Value = self:getDisplayValue(boardName, boardConfig, userId, sortValue),
		})
	end

	return entries
end

function LeaderboardService:buildFallbackBoardEntries(boardName: string, boardConfig): { { UserId: number, Value: number } }
	local store = getStore(boardConfig)
	local storeName = LeaderboardConfig.DataStorePrefix .. boardConfig.DataStoreName
	local entriesByUser: { [number]: { UserId: number, Value: number } } = {}

	local function addEntry(userId: number, sortValue: number)
		if isUserExcludedFromBoard(userId, boardName) then
			return
		end

		entriesByUser[userId] = {
			UserId = userId,
			Value = self:getDisplayValue(boardName, boardConfig, userId, sortValue),
		}
	end

	for _, userId in collectRecoveryCandidateUserIds(boardName) do
		local readOk, sortValue = safeOrderedGetAsync(store, storeName, userId)
		if readOk and sortValue ~= nil then
			addEntry(userId, sortValue)
			continue
		end

		local publishedBoards = lastPublishedValues[userId]
		if type(publishedBoards) == "table" and publishedBoards[boardName] ~= nil then
			addEntry(userId, publishedBoards[boardName])
		end
	end

	if not sortedReadUnavailable[boardName] then
		local _, readRetryDelay = getReadRetrySettings()
		local ascendingOk, ascendingPages = tryGetSortedPages(
			store,
			true,
			LeaderboardConfig.MaxEntries,
			1,
			readRetryDelay
		)
		if ascendingOk then
			for _, entry in self:buildBoardEntriesFromPages(boardName, boardConfig, ascendingPages) do
				entriesByUser[entry.UserId] = entry
			end
		end
	end

	local entries = {}
	for _, entry in entriesByUser do
		table.insert(entries, entry)
	end

	return entries
end

function LeaderboardService:renderBoard(boardName: string, boardConfig)
	if isShuttingDown then
		return
	end

	if not waitForBudget(Enum.DataStoreRequestType.OrderedList, 1, 10) then
		warnReadFailed("[LeaderboardService] Skipping leaderboard read; datastore read budget is low.")
		return
	end

	local store = getStore(boardConfig)
	local readRetries, readRetryDelay = getReadRetrySettings()
	local maxEntries = LeaderboardConfig.MaxEntries or 100
	local PlayerDataService = Knit.GetService("PlayerDataService")

	local entries
	if sortedReadUnavailable[boardName] then
		entries = self:buildFallbackBoardEntries(boardName, boardConfig)
	else
		local ok, pagesOrErr = tryGetSortedPages(store, false, maxEntries, readRetries, readRetryDelay)
		if not ok then
			local fixed = recoverCorruptBoardEntries(boardName, boardConfig, PlayerDataService)
			if fixed > 0 then
				task.wait(readRetryDelay)
				ok, pagesOrErr = tryGetSortedPages(store, false, maxEntries, 1, readRetryDelay)
			end
		end

		if ok then
			sortedReadUnavailable[boardName] = nil
			entries = self:buildBoardEntriesFromPages(boardName, boardConfig, pagesOrErr)
		else
			sortedReadUnavailable[boardName] = true
			warnReadFailed(
				"[LeaderboardService] Failed to read",
				boardName,
				pagesOrErr,
				"- using fallback entries for this server session."
			)
			entries = self:buildFallbackBoardEntries(boardName, boardConfig)
		end
	end

	entries = finalizeEntriesForRender(boardName, boardConfig, entries)
	WorldLeaderboardRenderer.render(boardName, entries, boardConfig.AmountSuffix)

	if boardConfig.SortMode == "Logarithmic" and #entries > 0 and not isShuttingDown then
		task.spawn(function()
			local enrichedEntries = table.create(#entries)
			for index, entry in entries do
				enrichedEntries[index] = {
					UserId = entry.UserId,
					Value = entry.Value,
				}
			end

			enrichEntriesFromDisplayStore(boardName, boardConfig, enrichedEntries, PlayerDataService)
			if isShuttingDown then
				return
			end

			local refreshedEntries = finalizeEntriesForRender(boardName, boardConfig, enrichedEntries)
			WorldLeaderboardRenderer.render(boardName, refreshedEntries, boardConfig.AmountSuffix)
		end)
	end

	if not isShuttingDown then
		task.wait(getWriteSpacing())
	end
end

function LeaderboardService:renderBoards()
	for boardName, boardConfig in LeaderboardConfig.Boards do
		self:renderBoard(boardName, boardConfig)
	end
end

function LeaderboardService:RemoveUserFromBoard(
	boardName: string,
	userId: number,
	options: { ExcludeFromRepublish: boolean?, Rerender: boolean? }?
): boolean
	local boardConfig = LeaderboardConfig.Boards[boardName]
	if not boardConfig then
		return false
	end

	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return false
	end

	local key = tostring(userId)
	local store = getStore(boardConfig)
	local orderedOk = pcall(function()
		store:RemoveAsync(key)
	end)
	if not orderedOk then
		return false
	end

	if displayValueCache[boardName] then
		displayValueCache[boardName][userId] = nil
	end
	if lastPublishedValues[userId] then
		lastPublishedValues[userId][boardName] = nil
	end

	if options and options.ExcludeFromRepublish then
		excludeUserFromBoard(userId, boardName)
		clearOnlinePublishState(userId)
	end

	if options and options.Rerender then
		task.spawn(function()
			self:renderBoard(boardName, boardConfig)
		end)
	end

	return true
end

function LeaderboardService:RemoveUserFromAllBoards(
	userId: number,
	options: { ExcludeFromRepublish: boolean?, Rerender: boolean? }?
): number
	local cleared = 0
	local perBoardOptions = if options
		then {
			ExcludeFromRepublish = options.ExcludeFromRepublish,
			Rerender = false,
		}
		else nil

	for boardName in LeaderboardConfig.Boards do
		if self:RemoveUserFromBoard(boardName, userId, perBoardOptions) then
			cleared += 1
		end
	end

	if cleared > 0 and options and options.Rerender then
		task.spawn(function()
			self:renderBoards()
		end)
	end

	return cleared
end

local function includeUserFromBoard(userId: number, boardName: string)
	local userBoards = excludedFromBoards[userId]
	if type(userBoards) ~= "table" then
		return
	end

	userBoards[boardName] = nil
	if next(userBoards) == nil then
		excludedFromBoards[userId] = nil
	end
end

function LeaderboardService:RestoreUserToLeaderboards(userId: number): (boolean, string?)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return false, "UserId must be greater than 0."
	end

	for boardName in LeaderboardConfig.Boards do
		includeUserFromBoard(userId, boardName)
	end

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		dirtyPlayers[onlinePlayer] = true
		self:schedulePlayerPublish(onlinePlayer, true)
	end

	return true, nil
end

function LeaderboardService:ClearUserFromLeaderboards(userId: number, boardName: string?): (number, string?)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return 0, "UserId must be greater than 0."
	end

	local options = {
		ExcludeFromRepublish = true,
		Rerender = true,
	}

	if boardName == "all" or boardName == nil or boardName == "" then
		local cleared = self:RemoveUserFromAllBoards(userId, options)
		return cleared, nil
	end

	if not LeaderboardConfig.Boards[boardName] then
		return 0, `Unknown leaderboard board "{boardName}".`
	end

	if not self:RemoveUserFromBoard(boardName, userId, options) then
		return 0, `Failed to remove user {userId} from {boardName}.`
	end

	return 1, nil
end

function LeaderboardService:ResetUserLeaderboard(userId: number): (number?, string?)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return nil, "UserId must be greater than 0."
	end

	self:RestoreUserToLeaderboards(userId)

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local ok, err = PlayerDataService:ResetLeaderboardStatsByUserId(userId)
	if not ok then
		return nil, err or "Failed to reset leaderboard stats."
	end

	lastPublishedValues[userId] = {}
	local published, publishOk = self:publishZeroLeaderboardForUser(userId)
	if not publishOk then
		return published, "Leaderboard stats reset, but publishing zero values to some boards failed."
	end

	task.spawn(function()
		self:renderBoards()
	end)

	return published, nil
end

function LeaderboardService:updateNow(forcePublish: boolean?)
	if forcePublish then
		for _, player in Players:GetPlayers() do
			dirtyPlayers[player] = true
		end
	end

	self:publishOnlinePlayers(forcePublish)
	self:renderBoards()
end

function LeaderboardService:setupPlayerPublishing(player: Player)
	if playerPublishConnections[player] then
		return
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local connections = {}
	playerPublishConnections[player] = connections

	for _, boardConfig in LeaderboardConfig.Boards do
		table.insert(
			connections,
			PlayerDataService:Observe(player, boardConfig.DataPath, function()
				self:markPlayerDirty(player, false)
			end)
		)
	end

	self:markPlayerDirty(player, true)
end

function LeaderboardService:clearPlayerPublishing(player: Player)
	local connections = playerPublishConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	playerPublishConnections[player] = nil
	dirtyPlayers[player] = nil
	dirtyDebounceScheduled[player] = nil
	publishQueue[player] = nil
	lastPublishAttemptAt[player] = nil
	lastPublishedValues[player.UserId] = nil
end

function LeaderboardService:KnitStart()
	local PlayerDataService = Knit.GetService("PlayerDataService")

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			pcall(function()
				self:setupPlayerPublishing(player)
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:clearPlayerPublishing(player)

		if isShuttingDown then
			return
		end

		task.spawn(function()
			pcall(function()
				self:publishPlayer(player, true, { fast = true })
			end)
		end)

		task.defer(function()
			if isShuttingDown then
				return
			end

			pcall(function()
				TopTierRig.refresh(PlayerDataService)
			end)
		end)
	end)

	game:BindToClose(function()
		isShuttingDown = true

		local startedAt = os.clock()
		local shutdownBudget = math.min(tonumber(LeaderboardConfig.ShutdownPublishBudgetSeconds) or 8, 20)
		for _, player in Players:GetPlayers() do
			if os.clock() - startedAt >= shutdownBudget then
				break
			end

			pcall(function()
				self:publishPlayer(player, true, {
					fast = true,
					allowOnShutdown = true,
				})
			end)
		end
	end)

	task.spawn(function()
		for _, player in Players:GetPlayers() do
			pcall(function()
				self:setupPlayerPublishing(player)
			end)
		end

		task.wait(math.min(LeaderboardConfig.InitialUpdateDelay or 60, 20))
		if not isShuttingDown then
			self:renderBoards()
		end

		while not isShuttingDown do
			for _, player in Players:GetPlayers() do
				self:schedulePlayerPublish(player, false)
			end
			self:renderBoards()
			task.wait(LeaderboardConfig.UpdateInterval)
		end
	end)

	task.spawn(function()
		task.wait(5)
		while not isShuttingDown do
			pcall(function()
				TopTierRig.refresh(PlayerDataService)
			end)
			task.wait(LeaderboardConfig.TopTierRigRefreshInterval)
		end
	end)
end

return LeaderboardService
