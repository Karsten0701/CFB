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
local valueStores: { [string]: GlobalDataStore } = {}
local lastPublishedValues: { [number]: { [string]: number } } = {}
local playerPublishConnections: { [Player]: { RBXScriptConnection } } = {}
local dirtyPlayers: { [Player]: boolean } = {}
local displayValueCache: { [string]: { [number]: { Value: number, FetchedAt: number } } } = {}
local dirtyDebounceScheduled: { [Player]: boolean } = {}
local publishQueue: { [Player]: boolean } = {}
local lastPublishAttemptAt: { [Player]: number } = {}
local publishWorkerRunning = false

local LOG_SORT_SCALE = 1_000_000
local DISPLAY_VALUE_CACHE_SECONDS = 300
local lastLowBudgetWarnAt = -math.huge
local lastPublishErrorWarnAt = -math.huge
local lastReadErrorWarnAt = -math.huge

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

local function getValueStore(boardConfig): GlobalDataStore
	local storeName = LeaderboardConfig.DataStorePrefix .. boardConfig.DataStoreName .. "_DisplayValues"
	local store = valueStores[storeName]
	if store then
		return store
	end

	store = DataStoreService:GetDataStore(storeName)
	valueStores[storeName] = store
	return store
end

local function getBudget(requestType: Enum.DataStoreRequestType): number
	return DataStoreService:GetRequestBudgetForRequestType(requestType)
end

local function waitForBudget(
	requestType: Enum.DataStoreRequestType,
	minimumBudget: number,
	timeoutSeconds: number?
): boolean
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

local function normalizeValue(value: any): number
	return math.max(math.floor(tonumber(value) or 0), 0)
end

local function getSortValue(boardConfig, value: number): number
	value = normalizeValue(value)
	if boardConfig.SortMode == "Logarithmic" then
		if value <= 1 then
			return value
		end

		return math.max(math.floor(math.log10(value) * LOG_SORT_SCALE), 1)
	end

	return value
end

local function getApproximateValueFromSort(boardConfig, sortValue: number): number
	sortValue = normalizeValue(sortValue)
	if boardConfig.SortMode == "Logarithmic" then
		return math.max(math.floor(10 ^ (sortValue / LOG_SORT_SCALE)), 0)
	end

	return sortValue
end

local function getPlayerValue(PlayerDataService, player: Player, boardConfig): number
	if boardConfig.DataPath == "PlaytimeSeconds" then
		return normalizeValue(PlayerDataService:GetPlaytimeSeconds(player))
	end

	return normalizeValue(PlayerDataService:Get(player, boardConfig.DataPath))
end

local function getWriteSpacing(): number
	return LeaderboardConfig.WriteSpacing or 0.6
end

function LeaderboardService:publishBoard(
	player: Player,
	boardName: string,
	boardConfig,
	value: number,
	sortValue: number
): boolean
	if boardConfig.SortMode == "Logarithmic" then
		if not waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync, 1) then
			warnLowBudget(Enum.DataStoreRequestType.SetIncrementAsync)
			return false
		end

		local valueStore = getValueStore(boardConfig)
		local displayOk, displayErr = pcall(function()
			valueStore:SetAsync(tostring(player.UserId), value)
		end)
		if not displayOk then
			warnPublishFailed(boardName, player.UserId, displayErr)
			return false
		end

		displayValueCache[boardName] = displayValueCache[boardName] or {}
		displayValueCache[boardName][player.UserId] = {
			Value = value,
			FetchedAt = os.clock(),
		}

		task.wait(getWriteSpacing())
	end

	if not waitForBudget(Enum.DataStoreRequestType.OrderedWrite, 1) then
		warnLowBudget(Enum.DataStoreRequestType.OrderedWrite)
		return false
	end

	local store = getStore(boardConfig)
	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), sortValue)
	end)

	if not ok then
		warnPublishFailed(boardName, player.UserId, err)
		return false
	end

	lastPublishedValues[player.UserId] = lastPublishedValues[player.UserId] or {}
	lastPublishedValues[player.UserId][boardName] = value
	return true
end

function LeaderboardService:publishPlayer(player: Player, force: boolean?): boolean
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	lastPublishedValues[player.UserId] = lastPublishedValues[player.UserId] or {}
	local hadFailure = false

	for boardName, boardConfig in LeaderboardConfig.Boards do
		local value = getPlayerValue(PlayerDataService, player, boardConfig)
		if value <= 0 then
			continue
		end

		local sortValue = getSortValue(boardConfig, value)
		if not force and lastPublishedValues[player.UserId][boardName] == value then
			continue
		end

		if not self:publishBoard(player, boardName, boardConfig, value, sortValue) then
			hadFailure = true
			break
		end

		task.wait(getWriteSpacing())
	end

	if hadFailure then
		dirtyPlayers[player] = true
		return false
	end

	dirtyPlayers[player] = nil
	return true
end

function LeaderboardService:getDisplayValue(boardName: string, boardConfig, userId: number, sortValue: number): number
	if boardConfig.SortMode ~= "Logarithmic" then
		return normalizeValue(sortValue)
	end

	displayValueCache[boardName] = displayValueCache[boardName] or {}
	local cached = displayValueCache[boardName][userId]
	if cached and os.clock() - cached.FetchedAt < DISPLAY_VALUE_CACHE_SECONDS then
		return cached.Value
	end

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local ok, value = pcall(function()
			return getPlayerValue(PlayerDataService, onlinePlayer, boardConfig)
		end)
		if ok and value > 0 then
			displayValueCache[boardName][userId] = {
				Value = value,
				FetchedAt = os.clock(),
			}
			return value
		end
	end

	return getApproximateValueFromSort(boardConfig, sortValue)
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
	if force then
		publishQueue[player] = true
	else
		publishQueue[player] = publishQueue[player] == true
	end

	self:startPublishWorker()
end

function LeaderboardService:startPublishWorker()
	if publishWorkerRunning then
		return
	end

	publishWorkerRunning = true
	task.spawn(function()
		while next(publishQueue) ~= nil do
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

function LeaderboardService:renderBoard(boardName: string, boardConfig)
	if not waitForBudget(Enum.DataStoreRequestType.OrderedList, 1, 10) then
		warnReadFailed("[LeaderboardService] Skipping leaderboard read; datastore read budget is low.")
		return
	end

	local store = getStore(boardConfig)
	local ok, pagesOrErr = pcall(function()
		return store:GetSortedAsync(false, LeaderboardConfig.MaxEntries)
	end)

	if not ok then
		warnReadFailed("[LeaderboardService] Failed to read", boardName, pagesOrErr)
		return
	end

	local entries = {}
	for _, item in pagesOrErr:GetCurrentPage() do
		local userId = tonumber(item.key)
		if not userId then
			continue
		end

		local sortValue = normalizeValue(item.value)
		table.insert(entries, {
			UserId = userId,
			Value = self:getDisplayValue(boardName, boardConfig, userId, sortValue),
		})
	end

	WorldLeaderboardRenderer.render(boardName, entries, boardConfig.AmountSuffix)
	task.wait(getWriteSpacing())
end

function LeaderboardService:renderBoards()
	for boardName, boardConfig in LeaderboardConfig.Boards do
		self:renderBoard(boardName, boardConfig)
	end
end

function LeaderboardService:RemoveUserFromBoard(boardName: string, userId: number): boolean
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

	if boardConfig.SortMode == "Logarithmic" then
		local valueStore = getValueStore(boardConfig)
		pcall(function()
			valueStore:RemoveAsync(key)
		end)
	end

	if displayValueCache[boardName] then
		displayValueCache[boardName][userId] = nil
	end
	if lastPublishedValues[userId] then
		lastPublishedValues[userId][boardName] = nil
	end

	return true
end

function LeaderboardService:RemoveUserFromAllBoards(userId: number): number
	local cleared = 0
	for boardName in LeaderboardConfig.Boards do
		if self:RemoveUserFromBoard(boardName, userId) then
			cleared += 1
		end
	end
	return cleared
end

function LeaderboardService:ResetUserLeaderboard(userId: number): (number?, string?)
	userId = math.floor(tonumber(userId) or 0)
	if userId <= 0 then
		return nil, "UserId must be greater than 0."
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local ok, err = PlayerDataService:ResetLeaderboardStatsByUserId(userId)
	if not ok then
		return nil, err or "Failed to reset leaderboard stats."
	end

	local cleared = self:RemoveUserFromAllBoards(userId)
	lastPublishedValues[userId] = nil

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		dirtyPlayers[onlinePlayer] = nil
		publishQueue[onlinePlayer] = nil
		lastPublishAttemptAt[onlinePlayer] = nil
	end

	return cleared, nil
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
		if boardConfig.DataPath == "PlaytimeSeconds" then
			continue
		end

		table.insert(
			connections,
			PlayerDataService:Observe(player, boardConfig.DataPath, function()
				self:markPlayerDirty(player, false)
			end)
		)
	end

	self:markPlayerDirty(player, false)
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
	local shuttingDown = false

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			pcall(function()
				self:setupPlayerPublishing(player)
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		if shuttingDown then
			self:clearPlayerPublishing(player)
			return
		end

		publishQueue[player] = true
		pcall(function()
			self:publishPlayer(player, true)
		end)
		self:clearPlayerPublishing(player)
		task.defer(function()
			pcall(function()
				TopTierRig.refresh(PlayerDataService)
			end)
		end)
	end)

	game:BindToClose(function()
		shuttingDown = true
		local startedAt = os.clock()
		for _, player in Players:GetPlayers() do
			if os.clock() - startedAt >= 25 then
				break
			end

			pcall(function()
				self:publishPlayer(player, true)
			end)
			task.wait(LeaderboardConfig.PublishPlayerDelay or 2)
		end
	end)

	task.spawn(function()
		for _, player in Players:GetPlayers() do
			pcall(function()
				self:setupPlayerPublishing(player)
			end)
		end

		task.wait(LeaderboardConfig.InitialUpdateDelay or 60)
		while not shuttingDown do
			for _, player in Players:GetPlayers() do
				self:schedulePlayerPublish(player, false)
			end
			self:renderBoards()
			task.wait(LeaderboardConfig.UpdateInterval)
		end
	end)

	task.spawn(function()
		task.wait(5)
		while not shuttingDown do
			pcall(function()
				TopTierRig.refresh(PlayerDataService)
			end)
			task.wait(LeaderboardConfig.TopTierRigRefreshInterval)
		end
	end)
end

return LeaderboardService
