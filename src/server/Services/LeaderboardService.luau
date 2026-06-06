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
local lastPublishedValues: { [number]: { [string]: number } } = {}

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

local function getBudget(requestType: Enum.DataStoreRequestType): number
	return DataStoreService:GetRequestBudgetForRequestType(requestType)
end

local function waitForBudget(requestType: Enum.DataStoreRequestType, minimumBudget: number): boolean
	local waited = 0
	while getBudget(requestType) < minimumBudget do
		if waited >= 10 then
			return false
		end

		waited += 1
		task.wait(1)
	end

	return true
end

local function normalizeValue(value: any): number
	return math.max(math.floor(tonumber(value) or 0), 0)
end

local function getPlayerValue(PlayerDataService, player: Player, boardConfig): number
	if boardConfig.DataPath == "PlaytimeSeconds" then
		return normalizeValue(PlayerDataService:GetPlaytimeSeconds(player))
	end

	return normalizeValue(PlayerDataService:Get(player, boardConfig.DataPath))
end

function LeaderboardService:publishPlayer(player: Player, force: boolean?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	lastPublishedValues[player.UserId] = lastPublishedValues[player.UserId] or {}

	for boardName, boardConfig in LeaderboardConfig.Boards do
		local value = getPlayerValue(PlayerDataService, player, boardConfig)
		if value <= 0 then
			continue
		end

		if not force and lastPublishedValues[player.UserId][boardName] == value then
			continue
		end

		if not waitForBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync, 1) then
			warn("[LeaderboardService] Skipping leaderboard write; datastore write budget is low.")
			return
		end

		local store = getStore(boardConfig)
		local ok, err = pcall(function()
			store:SetAsync(tostring(player.UserId), value)
		end)

		if ok then
			lastPublishedValues[player.UserId][boardName] = value
		else
			warn("[LeaderboardService] Failed to publish", boardName, player.UserId, err)
		end

		task.wait(0.05)
	end
end

function LeaderboardService:publishOnlinePlayers(force: boolean?)
	for _, player in Players:GetPlayers() do
		self:publishPlayer(player, force)
	end
end

function LeaderboardService:renderBoard(boardName: string, boardConfig)
	if not waitForBudget(Enum.DataStoreRequestType.OrderedList, 1) then
		warn("[LeaderboardService] Skipping leaderboard read; datastore read budget is low.")
		return
	end

	local store = getStore(boardConfig)
	local ok, pagesOrErr = pcall(function()
		return store:GetSortedAsync(false, LeaderboardConfig.MaxEntries)
	end)

	if not ok then
		warn("[LeaderboardService] Failed to read", boardName, pagesOrErr)
		return
	end

	local entries = {}
	for _, item in pagesOrErr:GetCurrentPage() do
		table.insert(entries, {
			UserId = tonumber(item.key),
			Value = normalizeValue(item.value),
		})
	end

	WorldLeaderboardRenderer.render(boardName, entries, boardConfig.AmountSuffix)
end

function LeaderboardService:renderBoards()
	for boardName, boardConfig in LeaderboardConfig.Boards do
		self:renderBoard(boardName, boardConfig)
		task.wait(0.1)
	end
end

function LeaderboardService:updateNow(forcePublish: boolean?)
	self:publishOnlinePlayers(forcePublish)
	self:renderBoards()
end

function LeaderboardService:KnitStart()
	local PlayerDataService = Knit.GetService("PlayerDataService")

	Players.PlayerRemoving:Connect(function(player)
		pcall(function()
			self:publishPlayer(player, true)
		end)
		lastPublishedValues[player.UserId] = nil
	end)

	task.spawn(function()
		task.wait(10)
		while true do
			self:updateNow(false)
			task.wait(LeaderboardConfig.UpdateInterval)
		end
	end)

	task.spawn(function()
		task.wait(5)
		while true do
			pcall(function()
				TopTierRig.refresh(PlayerDataService)
			end)
			task.wait(LeaderboardConfig.TopTierRigRefreshInterval)
		end
	end)
end

return LeaderboardService
