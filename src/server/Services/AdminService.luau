local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(ReplicatedStorage.Shared.Data.AdminConfig)
local AdminRuntime = require(ReplicatedStorage.Shared.Features.Admin.AdminRuntime)
local Knit = require(ReplicatedStorage.Packages.knit)
local StudioHostAllowlist = require(script.Parent.Parent.Modules.Security.StudioHostAllowlist)

local AdminService = Knit.CreateService({
	Name = "AdminService",
	Client = {
		StateChanged = Knit.CreateSignal(),
		AdminBannerReceived = Knit.CreateSignal(),
		SpawnMutationDrops = Knit.CreateSignal(),
	},
})

local serverState = {
	AdminEvent = nil :: AdminRuntime.AdminEventState?,
	Boosts = {} :: { AdminRuntime.AdminBoostState },
}

local messagingReady = false
local processedAdminMessageIds: { [string]: boolean } = {}

local function getNow(): number
	local ok, serverTime = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(serverTime) == "number" then
		return math.floor(serverTime)
	end
	return os.time()
end

local function assertAdmin(player: Player): boolean
	return StudioHostAllowlist.isAdminPlayer(player)
end

local function copyBoost(boost: AdminRuntime.AdminBoostState): AdminRuntime.AdminBoostState
	return {
		Id = boost.Id,
		Name = boost.Name,
		Icon = boost.Icon,
		Description = boost.Description,
		Effects = table.clone(boost.Effects),
		StartedAt = boost.StartedAt,
		EndsAt = boost.EndsAt,
		StartedByName = boost.StartedByName,
	}
end

local function copyAdminEvent(adminEvent: AdminRuntime.AdminEventState): AdminRuntime.AdminEventState
	return {
		Id = adminEvent.Id,
		Name = adminEvent.Name,
		Icon = adminEvent.Icon,
		VFXKey = adminEvent.VFXKey,
		Description = adminEvent.Description,
		StartedAt = adminEvent.StartedAt,
		EndsAt = adminEvent.EndsAt,
		DurationSeconds = adminEvent.DurationSeconds,
		Effects = table.clone(adminEvent.Effects),
		StartedByName = adminEvent.StartedByName,
	}
end

local function cloneState()
	local boosts = {}
	for _, boost in serverState.Boosts do
		table.insert(boosts, copyBoost(boost))
	end

	return {
		AdminEvent = if serverState.AdminEvent then copyAdminEvent(serverState.AdminEvent) else nil,
		Boosts = boosts,
	}
end

local function findBoostIndex(boostId: string): number?
	for index, boost in serverState.Boosts do
		if boost.Id == boostId then
			return index
		end
	end
	return nil
end

local function pruneExpiredServerBoosts(now: number)
	local nextBoosts = {}
	for _, boost in serverState.Boosts do
		if type(boost) == "table" and math.floor(boost.EndsAt or 0) > now then
			table.insert(nextBoosts, boost)
		end
	end
	serverState.Boosts = nextBoosts
end

local function syncRuntimeAndBroadcast()
	local now = getNow()
	local adminEvent = serverState.AdminEvent
	if adminEvent and math.floor(adminEvent.EndsAt or 0) <= now then
		serverState.AdminEvent = nil
		adminEvent = nil
	end

	pruneExpiredServerBoosts(now)
	AdminRuntime.setReplicatedState(cloneState())
	AdminService.Client.StateChanged:FireAll(cloneState())
end

local function broadcastAdminBanner(kind: string, senderName: string, data: { [string]: any })
	AdminService.Client.AdminBannerReceived:FireAll(kind, senderName, data)
end

local function broadcastAdminMessage(senderName: string, message: string)
	broadcastAdminBanner("admin_message", senderName, { message = message })
end

local function broadcastEventStarted(senderName: string, adminEvent: AdminRuntime.AdminEventState)
	broadcastAdminBanner("event_started", senderName, { adminEvent = adminEvent })
end

local function broadcastBoostStarted(senderName: string, boost: AdminRuntime.AdminBoostState)
	broadcastAdminBanner("boost_started", senderName, { boost = boost })
end

local function broadcastSystemMessage(senderName: string, message: string)
	broadcastAdminBanner("system", senderName, { message = message })
end

local function applyMessagingPayload(data: any)
	if type(data) ~= "table" or type(data.action) ~= "string" then
		return
	end

	local action = data.action
	local payload = data.payload
	if type(payload) == "table" then
		local messageId = payload.messageId
		if type(messageId) == "string" and messageId ~= "" then
			if processedAdminMessageIds[messageId] then
				return
			end
			processedAdminMessageIds[messageId] = true
		end
	end

	local senderName = if type(payload) == "table" then tostring(payload.senderName or "Admin") else "Admin"

	if action == "announce" and type(payload) == "table" then
		local message = tostring(payload.message or "")
		if message ~= "" then
			broadcastAdminMessage(senderName, message)
		end
		return
	end

	if action == "event_start" and type(payload) == "table" and type(payload.adminEvent) == "table" then
		local adminEvent = payload.adminEvent
		local alreadyActive = serverState.AdminEvent and serverState.AdminEvent.Id == adminEvent.Id
		serverState.AdminEvent = adminEvent
		syncRuntimeAndBroadcast()
		if not alreadyActive then
			broadcastEventStarted(senderName, adminEvent)
		end
		return
	end

	if action == "event_stop" then
		if serverState.AdminEvent then
			serverState.AdminEvent = nil
			syncRuntimeAndBroadcast()
			broadcastSystemMessage(senderName, "Event stopped.")
		end
		return
	end

	if action == "boost_start" and type(payload) == "table" and type(payload.boost) == "table" then
		local boost = payload.boost
		if findBoostIndex(boost.Id) then
			return
		end

		table.insert(serverState.Boosts, boost)
		syncRuntimeAndBroadcast()
		broadcastBoostStarted(senderName, boost)
		return
	end

	if action == "boost_stop_all" then
		if #serverState.Boosts > 0 then
			serverState.Boosts = {}
			syncRuntimeAndBroadcast()
			broadcastSystemMessage(senderName, "All admin boosts stopped.")
		end
		return
	end

	if action == "mutation_spawn" and type(payload) == "table" then
		local count = math.clamp(math.floor(tonumber(payload.count) or 0), 1, 5000)
		AdminService.Client.SpawnMutationDrops:FireAll(count)
		broadcastSystemMessage(senderName, `Spawned {count} mutation ball(s) for everyone.`)
	end
end

local function publishGlobal(action: string, payload: { [string]: any })
	local outgoingPayload = table.clone(payload)
	outgoingPayload.messageId = `{action}:{getNow()}:{HttpService:GenerateGUID(false)}`
	applyMessagingPayload({ action = action, payload = outgoingPayload })

	if not messagingReady then
		warn("[AdminService] MessagingService unavailable — global action applied on this server only.")
		return
	end

	local ok, err = pcall(function()
		MessagingService:PublishAsync(AdminConfig.MessagingTopic, {
			action = action,
			payload = outgoingPayload,
		})
	end)
	if not ok then
		warn("[AdminService] PublishAsync failed:", err)
	end
end

function AdminService:StartAdminEvent(
	player: Player,
	eventId: string,
	multiplier: number?,
	durationMinutes: number,
	global: boolean?
): (boolean, string?)
	if not assertAdmin(player) then
		return false, "Not authorized"
	end

	local resolvedMultiplier = tonumber(multiplier)
	if resolvedMultiplier ~= nil and resolvedMultiplier ~= resolvedMultiplier then
		resolvedMultiplier = nil
	end

	durationMinutes = math.max(tonumber(durationMinutes) or 5, 0.1)
	local durationSeconds = math.max(math.floor(durationMinutes * 60), 1)
	local adminEvent =
		AdminRuntime.buildAdminEvent(eventId, durationSeconds, player.Name, getNow(), resolvedMultiplier)
	if not adminEvent then
		return false, `Unknown event id "{eventId}"`
	end

	local payload = {
		adminEvent = adminEvent,
		senderName = player.Name,
	}

	if global ~= false then
		publishGlobal("event_start", payload)
	else
		applyMessagingPayload({ action = "event_start", payload = payload })
	end

	return true, nil
end

function AdminService:StopAdminEvent(player: Player, global: boolean?): (boolean, string?)
	if not assertAdmin(player) then
		return false, "Not authorized"
	end

	local payload = { senderName = player.Name }
	if global ~= false then
		publishGlobal("event_stop", payload)
	else
		applyMessagingPayload({ action = "event_stop", payload = payload })
	end

	return true, nil
end

function AdminService:StartAdminBoost(
	player: Player,
	boostType: string,
	multiplier: number,
	durationMinutes: number,
	global: boolean?
): (boolean, string?)
	if not assertAdmin(player) then
		return false, "Not authorized"
	end

	durationMinutes = math.max(tonumber(durationMinutes) or 5, 0.1)
	local durationSeconds = math.max(math.floor(durationMinutes * 60), 1)
	local boostConfig = AdminRuntime.getBoostType(boostType)
	local resolvedMultiplier = tonumber(multiplier)
	if resolvedMultiplier == nil or resolvedMultiplier ~= resolvedMultiplier then
		resolvedMultiplier = if boostConfig then boostConfig.DefaultMultiplier or 2 else 2
	end

	local boost = AdminRuntime.buildBoost(boostType, resolvedMultiplier, durationSeconds, player.Name, getNow())
	if not boost then
		return false, `Unknown boost type "{boostType}"`
	end

	local payload = {
		boost = boost,
		senderName = player.Name,
	}

	if global ~= false then
		publishGlobal("boost_start", payload)
	else
		applyMessagingPayload({ action = "boost_start", payload = payload })
	end

	return true, nil
end

function AdminService:StopAdminBoosts(player: Player, global: boolean?): (boolean, string?)
	if not assertAdmin(player) then
		return false, "Not authorized"
	end

	local payload = { senderName = player.Name }
	if global ~= false then
		publishGlobal("boost_stop_all", payload)
	else
		applyMessagingPayload({ action = "boost_stop_all", payload = payload })
	end

	return true, nil
end

function AdminService:SendServerAnnouncement(player: Player, message: string): (boolean, string?)
	if not assertAdmin(player) then
		return false, "Not authorized"
	end

	message = tostring(message or "")
	if message == "" then
		return false, "Message is empty"
	end

	broadcastAdminMessage(player.Name, message)
	return true, nil
end

function AdminService:SendGlobalAnnouncement(player: Player, message: string): (boolean, string?)
	if not assertAdmin(player) then
		return false, "Not authorized"
	end

	message = tostring(message or "")
	if message == "" then
		return false, "Message is empty"
	end

	publishGlobal("announce", {
		message = message,
		senderName = player.Name,
	})
	return true, nil
end

function AdminService:SpawnMutationBalls(player: Player, count: number, global: boolean?): (boolean, string?)
	if not assertAdmin(player) then
		return false, "Not authorized"
	end

	count = math.clamp(math.floor(tonumber(count) or 0), 1, 5000)
	local payload = {
		count = count,
		senderName = player.Name,
	}

	if global ~= false then
		publishGlobal("mutation_spawn", payload)
	else
		AdminService.Client.SpawnMutationDrops:FireAll(count)
		broadcastSystemMessage(player.Name, `Spawned {count} mutation ball(s) for everyone.`)
	end

	return true, nil
end

function AdminService.Client:GetState(player: Player)
	if not assertAdmin(player) then
		return nil
	end

	return cloneState()
end

function AdminService.Client:GetPublicState(_player: Player)
	return cloneState()
end

function AdminService.Client:SendServerAnnouncement(player: Player, message: string)
	return AdminService:SendServerAnnouncement(player, message)
end

function AdminService.Client:SendGlobalAnnouncement(player: Player, message: string)
	return AdminService:SendGlobalAnnouncement(player, message)
end

function AdminService.Client:StartAdminEvent(
	player: Player,
	eventId: string,
	multiplier: number?,
	durationMinutes: number,
	global: boolean?
)
	return AdminService:StartAdminEvent(player, eventId, multiplier, durationMinutes, global)
end

function AdminService.Client:StopAdminEvent(player: Player, global: boolean?)
	return AdminService:StopAdminEvent(player, global)
end

function AdminService.Client:StartAdminBoost(
	player: Player,
	boostType: string,
	multiplier: number?,
	durationMinutes: number,
	global: boolean?
)
	return AdminService:StartAdminBoost(player, boostType, multiplier, durationMinutes, global)
end

function AdminService.Client:StopAdminBoosts(player: Player, global: boolean?)
	return AdminService:StopAdminBoosts(player, global)
end

function AdminService:KnitStart()
	local ok = pcall(function()
		MessagingService:SubscribeAsync(AdminConfig.MessagingTopic, function(message)
			if type(message) == "table" and type(message.Data) == "table" then
				applyMessagingPayload(message.Data)
			end
		end)
	end)
	messagingReady = ok
	if not ok then
		warn("[AdminService] MessagingService subscribe failed — global admin actions are server-only.")
	end

	AdminRuntime.setReplicatedState(cloneState())

	local function syncPlayerState(player: Player)
		task.defer(function()
			if player.Parent then
				AdminService.Client.StateChanged:Fire(player, cloneState())
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		syncPlayerState(player)
	end

	Players.PlayerAdded:Connect(syncPlayerState)

	task.spawn(function()
		while true do
			task.wait(1)
			local hadEvent = serverState.AdminEvent ~= nil
			syncRuntimeAndBroadcast()
			if hadEvent and serverState.AdminEvent == nil then
				broadcastSystemMessage("Server", "Event ended.")
			end
		end
	end)
end

return AdminService
