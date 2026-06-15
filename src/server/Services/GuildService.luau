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

local function getMemberPoints(PlayerDataService, userId: number): number
	local points = PlayerDataService:GetLeaderboardValueByUserId(userId, "TotalUnitsBought")
	return math.max(math.floor(tonumber(points) or 0), 0)
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
				Points = getMemberPoints(PlayerDataService, userId),
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
	if not added then
		return false, addErr or "Could not send invite"
	end

	local invitedPlayer = Players:GetPlayerByUserId(targetUserId)
	if invitedPlayer then
		self:FireGuildInvitesUpdated(invitedPlayer)
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

function GuildService:FireGuildInvitesUpdated(player: Player)
	self.Client.GuildInvitesUpdated:Fire(player)
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
		releaseLock(player.UserId)
		return false, "You already created a guild", nil
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
		GuildScore = 0,
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
	self.Server:FireGuildUpdated(guildId)
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

function GuildService.Client:BrowseGuilds(player: Player, page: any): ({ guilds: { { [string]: any } } }, boolean)
	page = math.max(math.floor(tonumber(page) or 1), 1)
	local pageEntries, hasMore = GuildDataStore.getPublicGuildsPage(page, GuildConfig.BrowsePageSize)
	local guilds = {}

	for _, entry in pageEntries do
		local summary = buildSummary(entry.guild, 0)
		if summary then
			table.insert(guilds, summary)
		end
	end

	return { guilds = guilds }, hasMore
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
		releaseLock(player.UserId)
		if guildData.GuildId == guildId then
			return false, "Already in this guild"
		end
		return false, "Already in a guild"
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

	self.Server:FireGuildUpdated(guildId)
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
	end

	self.Server:FireGuildUpdated(guildId)
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
		releaseLock(player.UserId)
		return false, "Already in a guild"
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

	self.Server:FireGuildUpdated(guildId)
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

	if guildData.Role == GuildUtil.RoleOwner then
		releaseLock(player.UserId)
		return false, "Owner cannot leave"
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
		releaseLock(player.UserId)
		return false, "Could not leave guild"
	end

	PlayerDataService:SetGuildMembership(player, "", "", guildData.OwnedGuildId)
	self.Server:FireGuildUpdated(guildId)
	releaseLock(player.UserId)
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
	self.Server:FireGuildUpdated(guildId)
	releaseLock(player.UserId)
	return true, nil
end

return GuildService
