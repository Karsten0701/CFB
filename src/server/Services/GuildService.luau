local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local GuildConfig = require(ReplicatedStorage.Shared.Data.GuildConfig)
local GuildUtil = require(ReplicatedStorage.Shared.Features.Guilds.GuildUtil)
local GuildDataStore = require(script.Parent.Parent.Features.Guilds.GuildDataStore)
local Knit = require(ReplicatedStorage.Packages.knit)

local GuildService = Knit.CreateService({
	Name = "GuildService",
	Client = {
		GuildUpdated = Knit.CreateSignal(),
		GuildInvitesUpdated = Knit.CreateSignal(),
	},
})

local actionLocks: { [number]: boolean } = {}

local function acquireLock(userId: number): boolean
	if actionLocks[userId] then
		return false
	end

	actionLocks[userId] = true
	return true
end

local function releaseLock(userId: number)
	actionLocks[userId] = nil
end

local function filterGuildName(player: Player, name: string): (string?, string?)
	local filterResult
	local filterOk = pcall(function()
		filterResult = TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not filterOk or not filterResult then
		return nil, "Guild name not allowed"
	end

	local filtered
	local broadcastOk = pcall(function()
		filtered = filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if not broadcastOk or type(filtered) ~= "string" or filtered == "" then
		return nil, "Guild name not allowed"
	end

	if string.find(filtered, "#", 1, true) then
		return nil, "Guild name not allowed"
	end

	return filtered, nil
end

local function buildSummary(guild: { [string]: any }, rank: number?): { [string]: any }?
	return GuildUtil.toSummary(guild, rank)
end

local function getMemberPower(PlayerDataService, userId: number): number
	return PlayerDataService:GetUnitPowerByUserId(userId)
end

local function computeGuildScore(PlayerDataService, guild: { [string]: any }): number
	if type(guild.Members) ~= "table" then
		return 0
	end

	local total = 0
	for userIdStr in guild.Members do
		local userId = tonumber(userIdStr)
		if userId then
			total += getMemberPower(PlayerDataService, userId)
		end
	end

	return math.max(math.floor(total), 0)
end

local function buildRankMap(): { [string]: number }
	return GuildDataStore.getRankMap()
end

function GuildService:RecalculateGuildScore(guildId: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local guild = GuildDataStore.getGuild(guildId)
	if not guild then
		return
	end

	local score = computeGuildScore(PlayerDataService, guild)
	if score == guild.GuildScore then
		return
	end

	GuildDataStore.updateGuild(guildId, function(current)
		if not current then
			return nil
		end
		current.GuildScore = score
		return current
	end)
end

function GuildService:SyncGuildPowerScores()
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local guildIds: { [string]: boolean } = {}

	for _, player in Players:GetPlayers() do
		PlayerDataService:WaitForData(player)
		local guildData = PlayerDataService:GetGuildData(player)
		if guildData.GuildId ~= "" then
			guildIds[guildData.GuildId] = true
		end
	end

	if next(guildIds) ~= nil then
		GuildDataStore.setBatchLeaderboardMode(true)
		for guildId in guildIds do
			self:RecalculateGuildScore(guildId)
		end
		GuildDataStore.setBatchLeaderboardMode(false)
		GuildDataStore.flushLeaderboardScores()
	end

	for guildId in guildIds do
		self:FireGuildUpdated(guildId)
	end
end

local function buildMemberList(
	PlayerDataService,
	guild: { [string]: any }
): { { UserId: number, Role: string, DisplayName: string, Points: number } }
	local members = {}
	if type(guild.Members) ~= "table" then
		return members
	end

	for userIdStr, role in guild.Members do
		local userId = tonumber(userIdStr)
		if userId then
			local displayName = "Player"
			local memberPlayer = Players:GetPlayerByUserId(userId)
			if memberPlayer then
				displayName = memberPlayer.DisplayName
			else
				local ok, name = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				if ok and type(name) == "string" then
					displayName = name
				end
			end

			table.insert(members, {
				UserId = userId,
				Role = tostring(role),
				DisplayName = displayName,
				Points = getMemberPower(PlayerDataService, userId),
			})
		end
	end

	table.sort(members, function(left, right)
		if left.Role == right.Role then
			return left.DisplayName < right.DisplayName
		end
		if left.Role == GuildUtil.RoleOwner then
			return true
		end
		if right.Role == GuildUtil.RoleOwner then
			return false
		end
		return left.DisplayName < right.DisplayName
	end)

	return members
end

local function invitePlayerByUserId(
	self,
	player: Player,
	targetUserId: number
): (boolean, string?)
	targetUserId = math.floor(tonumber(targetUserId) or 0)
	if targetUserId <= 0 then
		return false, "Invalid player"
	end

	if targetUserId == player.UserId then
		return false, "Cannot invite yourself"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId == "" or guildData.Role ~= GuildUtil.RoleOwner then
		return false, "Not allowed"
	end

	local guild = GuildDataStore.getGuild(guildData.GuildId)
	if not guild then
		return false, "Guild not found"
	end

	if GuildUtil.getMemberCount(guild) >= GuildUtil.getMaxMembers(guild) then
		return false, "Guild is full"
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if targetPlayer then
		PlayerDataService:WaitForData(targetPlayer)
		local targetGuildData = PlayerDataService:GetGuildData(targetPlayer)
		if targetGuildData.GuildId ~= "" then
			return false, "Player already in a guild"
		end
		if PlayerDataService:HasGuildInvite(targetPlayer, guildData.GuildId) then
			return false, "Player already invited"
		end
	end

	local added, addErr = PlayerDataService:AddGuildInviteForUserId(targetUserId, guildData.GuildId)
	local targetOnThisServer = targetPlayer ~= nil
	if not added and targetOnThisServer then
		return false, addErr or "Could not send invite"
	end

	self:PublishGuildInvite(targetUserId, guildData.GuildId)

	if targetOnThisServer and targetPlayer then
		self:FireGuildInvitesUpdated(targetPlayer)
	end

	return true, nil
end

local function getOnlineMembers(guild: { [string]: any }): { Player }
	local members = {}
	if type(guild.Members) ~= "table" then
		return members
	end

	for userIdStr in guild.Members do
		local userId = tonumber(userIdStr)
		if userId then
			local memberPlayer = Players:GetPlayerByUserId(userId)
			if memberPlayer then
				table.insert(members, memberPlayer)
			end
		end
	end

	return members
end

function GuildService:FireGuildUpdated(guildId: string)
	local guild = GuildDataStore.getGuild(guildId)
	if not guild then
		return
	end

	for _, memberPlayer in getOnlineMembers(guild) do
		self.Client.GuildUpdated:Fire(memberPlayer, guildId)
	end
end

function GuildService:FireGuildUpdatedToPlayer(player: Player, guildId: string)
	self.Client.GuildUpdated:Fire(player, guildId)
end

function GuildService:BroadcastGuildUpdated(guildId: string)
	self:FireGuildUpdated(guildId)
	GuildDataStore.publishGuildSync({
		Type = "guild_updated",
		GuildId = guildId,
	})
end

function GuildService:PublishGuildInvite(targetUserId: number, guildId: string)
	GuildDataStore.publishGuildSync({
		Type = "invite",
		TargetUserId = targetUserId,
		GuildId = guildId,
	})
end

function GuildService:PublishPlayerGuildSync(
	userId: number,
	guildId: string,
	role: string,
	ownedGuildId: string?,
	clearOwnedGuildId: boolean?
)
	GuildDataStore.publishGuildSync({
		Type = "player_sync",
		UserId = userId,
		GuildId = guildId,
		Role = role,
		OwnedGuildId = ownedGuildId,
		ClearOwnedGuildId = clearOwnedGuildId == true,
	})
end

function GuildService:PublishGuildDisbanded(guildId: string)
	GuildDataStore.publishGuildSync({
		Type = "guild_disbanded",
		GuildId = guildId,
	})
end

local function applyRemotePlayerSync(guildService: typeof(GuildService), data: { [string]: any })
	local userId = math.floor(tonumber(data.UserId) or 0)
	if userId <= 0 then
		return
	end

	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local previousGuildId = PlayerDataService:GetGuildData(player).GuildId
	local guildId = if type(data.GuildId) == "string" then data.GuildId else ""
	local role = if type(data.Role) == "string" then data.Role else ""

	if guildId == "" then
		PlayerDataService:SetGuildMembership(player, "", "", if data.ClearOwnedGuildId == true then "" else nil)
	else
		local ownedGuildId = if type(data.OwnedGuildId) == "string" then data.OwnedGuildId else nil
		PlayerDataService:SetGuildMembership(player, guildId, role, ownedGuildId)
		PlayerDataService:RemoveGuildInvite(player, guildId)
	end

	guildService:FireGuildInvitesUpdated(player)

	if guildId ~= "" then
		guildService:FireGuildUpdated(guildId)
	elseif previousGuildId ~= "" then
		guildService:FireGuildUpdated(previousGuildId)
	end

	guildService:FireGuildUpdatedToPlayer(player, if guildId ~= "" then guildId else previousGuildId)
end

local function applyRemoteInvite(guildService: typeof(GuildService), data: { [string]: any })
	local targetUserId = math.floor(tonumber(data.TargetUserId) or 0)
	local guildId = data.GuildId
	if targetUserId <= 0 or type(guildId) ~= "string" or guildId == "" then
		return
	end

	local player = Players:GetPlayerByUserId(targetUserId)
	if not player then
		return
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId ~= "" then
		return
	end

	if not PlayerDataService:HasGuildInvite(player, guildId) then
		PlayerDataService:Update(player, "GuildInvites", function(current: any)
			local invites = if type(current) == "table" then current else {}
			table.insert(invites, {
				GuildId = guildId,
				InvitedAt = os.time(),
			})
			return invites
		end)
	end

	guildService:FireGuildInvitesUpdated(player)
end

local function applyRemoteGuildUpdated(guildService: typeof(GuildService), data: { [string]: any })
	local guildId = data.GuildId
	if type(guildId) ~= "string" or guildId == "" then
		return
	end

	GuildDataStore.invalidateGuildCache(guildId)
	guildService:FireGuildUpdated(guildId)
end

local function applyRemoteGuildDisbanded(guildService: typeof(GuildService), data: { [string]: any })
	local guildId = data.GuildId
	if type(guildId) ~= "string" or guildId == "" then
		return
	end

	GuildDataStore.invalidateGuildCache(guildId)
	GuildDataStore.invalidateTopGuildsCache()

	local PlayerDataService = Knit.GetService("PlayerDataService")
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			PlayerDataService:WaitForData(player)
			local guildData = PlayerDataService:GetGuildData(player)
			if guildData.GuildId ~= guildId then
				return
			end

			local clearOwned = guildData.Role == GuildUtil.RoleOwner
			PlayerDataService:SetGuildMembership(player, "", "", if clearOwned then "" else nil)
			guildService:FireGuildUpdatedToPlayer(player, guildId)
		end)
	end
end

local function handleGuildSyncMessage(guildService: typeof(GuildService), data: { [string]: any })
	local eventType = data.Type
	if eventType == "invite" then
		applyRemoteInvite(guildService, data)
	elseif eventType == "player_sync" then
		applyRemotePlayerSync(guildService, data)
	elseif eventType == "guild_updated" then
		applyRemoteGuildUpdated(guildService, data)
	elseif eventType == "guild_disbanded" then
		applyRemoteGuildDisbanded(guildService, data)
	end
end

function GuildService:FireGuildInvitesUpdated(player: Player)
	self.Client.GuildInvitesUpdated:Fire(player)
end

local function disbandGuild(
	guildService: typeof(GuildService),
	PlayerDataService,
	guildId: string
): (boolean, string?)
	local guild = GuildDataStore.getGuild(guildId)
	if not guild then
		return false, "Guild not found"
	end

	local memberUserIds: { number } = {}
	if type(guild.Members) == "table" then
		for userIdStr in guild.Members do
			local userId = tonumber(userIdStr)
			if userId then
				table.insert(memberUserIds, userId)
			end
		end
	end

	local onlineMembers = getOnlineMembers(guild)
	local ownerId = guild.OwnerId

	local deleted, deleteErr = GuildDataStore.deleteGuild(guildId)
	if not deleted then
		return false, deleteErr or "Could not disband guild"
	end

	for _, userId in memberUserIds do
		local clearOwned = userId == ownerId
		local memberPlayer = Players:GetPlayerByUserId(userId)
		if memberPlayer then
			PlayerDataService:SetGuildMembership(memberPlayer, "", "", if clearOwned then "" else nil)
		else
			PlayerDataService:ClearGuildMembershipForUserId(userId, clearOwned)
		end
	end

	for _, memberPlayer in onlineMembers do
		guildService.Client.GuildUpdated:Fire(memberPlayer, guildId)
	end

	for _, userId in memberUserIds do
		guildService:PublishPlayerGuildSync(userId, "", "", nil, userId == ownerId)
	end
	guildService:PublishGuildDisbanded(guildId)

	return true, nil
end

local function leaveMemberFromGuild(
	guildService: typeof(GuildService),
	PlayerDataService,
	player: Player
): (boolean, string?)
	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId == "" then
		return true, nil
	end

	if guildData.Role == GuildUtil.RoleOwner then
		return disbandGuild(guildService, PlayerDataService, guildData.GuildId)
	end

	local guildId = guildData.GuildId
	local userIdStr = tostring(player.UserId)
	local updatedGuild = GuildDataStore.updateGuild(guildId, function(current)
		if not current or type(current.Members) ~= "table" then
			return nil
		end
		current.Members[userIdStr] = nil
		return current
	end)

	if not updatedGuild then
		return false, "Could not leave guild"
	end

	PlayerDataService:SetGuildMembership(player, "", "", guildData.OwnedGuildId)
	guildService:RecalculateGuildScore(guildId)
	guildService:PublishPlayerGuildSync(player.UserId, "", "", nil, false)
	guildService:BroadcastGuildUpdated(guildId)
	return true, nil
end

local function addMemberToGuild(
	PlayerDataService,
	guildId: string,
	player: Player,
	role: string
): (boolean, string?)
	local userIdStr = tostring(player.UserId)
	local updatedGuild, updateErr = GuildDataStore.updateGuild(guildId, function(current)
		if not current or type(current.Members) ~= "table" then
			return nil
		end

		if current.Members[userIdStr] ~= nil then
			return current
		end

		if GuildUtil.getMemberCount(current) >= GuildUtil.getMaxMembers(current) then
			return nil
		end

		current.Members[userIdStr] = role
		return current
	end)

	if not updatedGuild then
		return false, updateErr or "Could not join guild"
	end

	local guildData = PlayerDataService:GetGuildData(player)
	PlayerDataService:SetGuildMembership(player, guildId, role, guildData.OwnedGuildId)
	PlayerDataService:RemoveGuildInvite(player, guildId)

	local guildService = Knit.GetService("GuildService")
	guildService:RecalculateGuildScore(guildId)
	return true, nil
end

function GuildService:ReconcilePlayerGuild(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId == "" then
		return
	end

	local guild = GuildDataStore.getGuild(guildData.GuildId)
	local userIdStr = tostring(player.UserId)
	if not guild or type(guild.Members) ~= "table" or guild.Members[userIdStr] == nil then
		PlayerDataService:SetGuildMembership(player, "", "", guildData.OwnedGuildId)
	end
end

function GuildService:KnitStart()
	GuildDataStore.subscribeLeaderboardInvalidation()
	GuildDataStore.subscribeGuildSync(function(data)
		handleGuildSyncMessage(self, data)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:ReconcilePlayerGuild(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:ReconcilePlayerGuild(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		releaseLock(player.UserId)
	end)

	task.spawn(function()
		local interval = math.max(math.floor(tonumber(GuildConfig.PowerSyncIntervalSeconds) or 300), 60)
		while true do
			task.wait(interval)
			pcall(function()
				self:SyncGuildPowerScores()
			end)
		end
	end)
end

function GuildService.Client:CreateGuild(
	player: Player,
	name: any,
	iconInput: any,
	isPublic: any
): (boolean, string?, { [string]: any }?)
	if not acquireLock(player.UserId) then
		return false, "Busy", nil
	end

	local userId = player.UserId
	task.defer(function()
		releaseLock(userId)
	end)

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId ~= "" then
		releaseLock(player.UserId)
		return false, "Already in a guild", nil
	end

	if guildData.OwnedGuildId ~= "" then
		local ownedGuild = GuildDataStore.getGuild(guildData.OwnedGuildId)
		if ownedGuild then
			releaseLock(player.UserId)
			return false, "You already created a guild", nil
		end

		PlayerDataService:SetGuildMembership(player, guildData.GuildId, guildData.Role, "")
	end

	local validName, nameErr = GuildUtil.isValidGuildName(name)
	if not validName then
		releaseLock(player.UserId)
		return false, nameErr, nil
	end

	local normalizedName = GuildUtil.normalizeGuildName(name)
	local filteredName, filterErr = filterGuildName(player, normalizedName)
	if not filteredName then
		releaseLock(player.UserId)
		return false, filterErr, nil
	end

	local iconId, iconErr = GuildUtil.parseIconIdOptional(iconInput)
	if iconErr then
		releaseLock(player.UserId)
		return false, iconErr, nil
	end

	local currentYen = PlayerDataService:Get(player, "Yen")
	if currentYen < GuildConfig.CreateCost then
		releaseLock(player.UserId)
		return false, "Not enough yen", nil
	end

	local guildId = GuildDataStore.generateGuildId()
	local nameKey = GuildUtil.getNameKey(filteredName)
	local reserved, reserveErr = GuildDataStore.reserveName(nameKey, guildId)
	if not reserved then
		releaseLock(player.UserId)
		return false, reserveErr or "Guild name already taken", nil
	end

	if not PlayerDataService:TrySpendYen(player, GuildConfig.CreateCost) then
		GuildDataStore.releaseName(nameKey, guildId)
		releaseLock(player.UserId)
		return false, "Not enough yen", nil
	end

	local guildRecord = {
		Id = guildId,
		Name = filteredName,
		NameKey = nameKey,
		IconId = iconId or 0,
		IsPublic = isPublic == true,
		OwnerId = player.UserId,
		Members = {
			[tostring(player.UserId)] = GuildUtil.RoleOwner,
		},
		GuildScore = PlayerDataService:GetUnitPowerByUserId(player.UserId),
		MaxMembers = GuildConfig.MaxMembers,
		CreatedAt = os.time(),
	}

	local saved, saveErr = GuildDataStore.saveGuild(guildRecord)
	if not saved then
		PlayerDataService:AddYen(player, GuildConfig.CreateCost)
		GuildDataStore.releaseName(nameKey, guildId)
		releaseLock(player.UserId)
		return false, saveErr or "Failed to create guild", nil
	end

	PlayerDataService:SetGuildMembership(player, guildId, GuildUtil.RoleOwner, guildId)
	self.Server:BroadcastGuildUpdated(guildId)
	releaseLock(player.UserId)

	return true, nil, buildSummary(guildRecord, 0)
end

function GuildService.Client:GetTopGuilds(player: Player): { guilds: { { [string]: any } } }
	local entries = GuildDataStore.getTopGuilds(GuildConfig.TopGuildsCount)
	local guilds = {}

	for _, entry in entries do
		local summary = buildSummary(entry.guild, entry.rank)
		if summary then
			table.insert(guilds, summary)
		end
	end

	return { guilds = guilds }
end

function GuildService.Client:BrowseGuilds(
	player: Player,
	searchQuery: any
): ({ guilds: { { [string]: any } } }, boolean)
	local query = if type(searchQuery) == "string" then GuildUtil.normalizeGuildName(searchQuery) else ""
	local browseEntries
	if query ~= "" then
		browseEntries = GuildDataStore.searchPublicGuilds(query, GuildConfig.BrowseSearchMaxResults)
	else
		browseEntries = GuildDataStore.getBrowseGuildsRandom(GuildConfig.BrowseRandomCount)
	end

	local rankMap = buildRankMap()
	local guilds = {}

	for _, entry in browseEntries do
		local summary = buildSummary(entry.guild, rankMap[entry.guild.Id] or 0)
		if summary then
			table.insert(guilds, summary)
		end
	end

	return { guilds = guilds }, false
end

function GuildService.Client:GetGuildDetails(
	player: Player,
	guildId: any
): ({ [string]: any }?, { { UserId: number, Role: string, DisplayName: string, Points: number } }?)
	if type(guildId) ~= "string" or guildId == "" then
		return nil, nil
	end

	local guild = GuildDataStore.getGuild(guildId)
	if not guild then
		return nil, nil
	end

	local summary = buildSummary(guild, GuildDataStore.getGuildRank(guildId))
	if not summary then
		return nil, nil
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	return summary, buildMemberList(PlayerDataService, guild)
end

function GuildService.Client:GetMyGuild(
	player: Player
): ({ [string]: any }?, { { UserId: number, Role: string, DisplayName: string, Points: number } }?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId == "" then
		return nil, nil
	end

	local guild = GuildDataStore.getGuild(guildData.GuildId)
	if not guild then
		return nil, nil
	end

	local summary = buildSummary(guild, GuildDataStore.getGuildRank(guildData.GuildId))
	if not summary then
		return nil, nil
	end

	return summary, buildMemberList(PlayerDataService, guild)
end

function GuildService.Client:GetGuildInvites(player: Player): { invites: { { [string]: any } } }
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local invites = {}
	for _, invite in PlayerDataService:GetGuildInvites(player) do
		local guild = GuildDataStore.getGuild(invite.GuildId)
		if guild then
			local summary = buildSummary(guild, 0)
			if summary then
				table.insert(invites, {
					Summary = summary,
					InvitedAt = invite.InvitedAt,
				})
			end
		else
			PlayerDataService:RemoveGuildInvite(player, invite.GuildId)
		end
	end

	return { invites = invites }
end

function GuildService.Client:DeclineGuildInvite(player: Player, guildId: any): (boolean, string?)
	if not acquireLock(player.UserId) then
		return false, "Busy"
	end

	if type(guildId) ~= "string" or guildId == "" then
		releaseLock(player.UserId)
		return false, "Invalid guild"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if not PlayerDataService:HasGuildInvite(player, guildId) then
		releaseLock(player.UserId)
		return false, "Invite not found"
	end

	PlayerDataService:RemoveGuildInvite(player, guildId)
	self.Server:FireGuildInvitesUpdated(player)
	releaseLock(player.UserId)
	return true, nil
end

function GuildService.Client:AcceptGuildInvite(player: Player, guildId: any): (boolean, string?)
	if not acquireLock(player.UserId) then
		return false, "Busy"
	end

	if type(guildId) ~= "string" or guildId == "" then
		releaseLock(player.UserId)
		return false, "Invalid guild"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	if not PlayerDataService:HasGuildInvite(player, guildId) then
		releaseLock(player.UserId)
		return false, "Invite not found"
	end

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId ~= "" then
		if guildData.GuildId == guildId then
			releaseLock(player.UserId)
			return false, "Already in this guild"
		end

		local left, leaveErr = leaveMemberFromGuild(self.Server, PlayerDataService, player)
		if not left then
			releaseLock(player.UserId)
			return false, leaveErr or "Could not leave current guild"
		end
	end

	local guild = GuildDataStore.getGuild(guildId)
	if not guild then
		PlayerDataService:RemoveGuildInvite(player, guildId)
		releaseLock(player.UserId)
		return false, "Guild not found"
	end

	if GuildUtil.getMemberCount(guild) >= GuildUtil.getMaxMembers(guild) then
		releaseLock(player.UserId)
		return false, "Guild is full"
	end

	local success, err = addMemberToGuild(PlayerDataService, guildId, player, GuildUtil.RoleMember)
	if not success then
		releaseLock(player.UserId)
		return false, err
	end

	local updatedGuildData = PlayerDataService:GetGuildData(player)
	self.Server:PublishPlayerGuildSync(player.UserId, guildId, GuildUtil.RoleMember, updatedGuildData.OwnedGuildId)
	self.Server:BroadcastGuildUpdated(guildId)
	self.Server:FireGuildInvitesUpdated(player)
	releaseLock(player.UserId)
	return true, nil
end

function GuildService.Client:InvitePlayer(player: Player, targetUserId: any): (boolean, string?)
	if not acquireLock(player.UserId) then
		return false, "Busy"
	end

	local userId = player.UserId
	task.defer(function()
		releaseLock(userId)
	end)

	local success, err = invitePlayerByUserId(self.Server, player, targetUserId)
	if not success then
		return false, err
	end

	return true, nil
end

function GuildService.Client:InvitePlayerByUsername(player: Player, username: any): (boolean, string?)
	if not acquireLock(player.UserId) then
		return false, "Busy"
	end

	local userId = player.UserId
	task.defer(function()
		releaseLock(userId)
	end)

	if type(username) ~= "string" then
		return false, "Invalid username"
	end

	local trimmed = string.gsub(username, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return false, "Username required"
	end

	local lookupOk, targetUserId = pcall(function()
		return Players:GetUserIdFromNameAsync(trimmed)
	end)
	if not lookupOk or type(targetUserId) ~= "number" or targetUserId <= 0 then
		return false, "Player not found"
	end

	local success, err = invitePlayerByUserId(self.Server, player, targetUserId)
	if not success then
		return false, err
	end

	return true, nil
end

function GuildService.Client:SetGuildVisibility(player: Player, isPublic: any): (boolean, string?)
	if not acquireLock(player.UserId) then
		return false, "Busy"
	end

	local userId = player.UserId
	task.defer(function()
		releaseLock(userId)
	end)

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId == "" or guildData.Role ~= GuildUtil.RoleOwner then
		return false, "Not allowed"
	end

	local nextIsPublic = isPublic == true
	local guildId = guildData.GuildId
	local updatedGuild = GuildDataStore.updateGuild(guildId, function(current)
		if not current then
			return nil
		end
		current.IsPublic = nextIsPublic
		return current
	end)

	if not updatedGuild then
		return false, "Could not update guild"
	end

	if nextIsPublic then
		GuildDataStore.appendPublicGuildId(guildId)
	else
		GuildDataStore.removePublicGuildId(guildId)
	end

	self.Server:BroadcastGuildUpdated(guildId)
	return true, nil
end

function GuildService.Client:JoinGuild(player: Player, guildId: any): (boolean, string?)
	if not acquireLock(player.UserId) then
		return false, "Busy"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId ~= "" then
		if guildData.GuildId == guildId then
			releaseLock(player.UserId)
			return false, "Already in this guild"
		end

		local left, leaveErr = leaveMemberFromGuild(self.Server, PlayerDataService, player)
		if not left then
			releaseLock(player.UserId)
			return false, leaveErr or "Could not leave current guild"
		end
	end

	if type(guildId) ~= "string" or guildId == "" then
		releaseLock(player.UserId)
		return false, "Invalid guild"
	end

	local guild = GuildDataStore.getGuild(guildId)
	if not guild then
		releaseLock(player.UserId)
		return false, "Guild not found"
	end

	if not GuildUtil.canJoin(guild) then
		releaseLock(player.UserId)
		if guild.IsPublic ~= true then
			return false, "Guild is private"
		end
		return false, "Guild is full"
	end

	local success, err = addMemberToGuild(PlayerDataService, guildId, player, GuildUtil.RoleMember)
	if not success then
		releaseLock(player.UserId)
		return false, err or "Could not join guild"
	end

	local updatedGuildData = PlayerDataService:GetGuildData(player)
	self.Server:PublishPlayerGuildSync(player.UserId, guildId, GuildUtil.RoleMember, updatedGuildData.OwnedGuildId)
	self.Server:BroadcastGuildUpdated(guildId)
	releaseLock(player.UserId)
	return true, nil
end

function GuildService.Client:LeaveGuild(player: Player): (boolean, string?)
	if not acquireLock(player.UserId) then
		return false, "Busy"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId == "" then
		releaseLock(player.UserId)
		return false, "Not in a guild"
	end

	local success, err = leaveMemberFromGuild(self.Server, PlayerDataService, player)
	releaseLock(player.UserId)
	if not success then
		return false, err or "Could not leave guild"
	end

	return true, nil
end

function GuildService.Client:KickMember(player: Player, targetUserId: any): (boolean, string?)
	if not acquireLock(player.UserId) then
		return false, "Busy"
	end

	targetUserId = math.floor(tonumber(targetUserId) or 0)
	if targetUserId <= 0 then
		releaseLock(player.UserId)
		return false, "Invalid player"
	end

	if targetUserId == player.UserId then
		releaseLock(player.UserId)
		return false, "Cannot kick yourself"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local guildData = PlayerDataService:GetGuildData(player)
	if guildData.GuildId == "" or guildData.Role ~= GuildUtil.RoleOwner then
		releaseLock(player.UserId)
		return false, "Not allowed"
	end

	local guildId = guildData.GuildId
	local targetIdStr = tostring(targetUserId)
	local updatedGuild = GuildDataStore.updateGuild(guildId, function(current)
		if not current or type(current.Members) ~= "table" then
			return nil
		end
		if current.Members[targetIdStr] == nil or current.Members[targetIdStr] == GuildUtil.RoleOwner then
			return nil
		end
		current.Members[targetIdStr] = nil
		return current
	end)

	if not updatedGuild then
		releaseLock(player.UserId)
		return false, "Could not kick member"
	end

	PlayerDataService:ClearGuildMembershipForUserId(targetUserId)
	self.Server:PublishPlayerGuildSync(targetUserId, "", "", nil, false)
	self.Server:RecalculateGuildScore(guildId)
	self.Server:BroadcastGuildUpdated(guildId)
	releaseLock(player.UserId)
	return true, nil
end

return GuildService
