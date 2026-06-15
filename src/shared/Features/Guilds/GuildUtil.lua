local GuildConfig = require(script.Parent.Parent.Parent.Data.GuildConfig)

local GuildUtil = {}

GuildUtil.RoleOwner = GuildConfig.Roles.Owner
GuildUtil.RoleMember = GuildConfig.Roles.Member

function GuildUtil.normalizeGuildName(name: any): string
	if type(name) ~= "string" then
		return ""
	end

	local trimmed = string.gsub(name, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	trimmed = string.gsub(trimmed, "%s+", " ")
	return trimmed
end

function GuildUtil.getNameKey(name: string): string
	return string.lower(GuildUtil.normalizeGuildName(name))
end

function GuildUtil.isValidGuildName(name: any): (boolean, string?)
	local normalized = GuildUtil.normalizeGuildName(name)
	if normalized == "" then
		return false, "Guild name is required"
	end

	if #normalized < GuildConfig.MinNameLength then
		return false, `Guild name must be at least {GuildConfig.MinNameLength} characters`
	end

	if #normalized > GuildConfig.MaxNameLength then
		return false, `Guild name must be at most {GuildConfig.MaxNameLength} characters`
	end

	return true, nil
end

function GuildUtil.parseIconId(input: any): number?
	if type(input) == "number" then
		local iconId = math.floor(input)
		if iconId > 0 then
			return iconId
		end
		return nil
	end

	if type(input) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(input, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")

	local fromAsset = string.match(trimmed, "^rbxassetid://(%d+)$")
	if fromAsset then
		local iconId = tonumber(fromAsset)
		if iconId and iconId > 0 then
			return math.floor(iconId)
		end
		return nil
	end

	local digitsOnly = string.match(trimmed, "^(%d+)$")
	if digitsOnly then
		local iconId = tonumber(digitsOnly)
		if iconId and iconId > 0 then
			return math.floor(iconId)
		end
	end

	return nil
end

function GuildUtil.isIconInputEmpty(input: any): boolean
	if input == nil then
		return true
	end

	if type(input) == "number" then
		return input <= 0
	end

	if type(input) ~= "string" then
		return true
	end

	local trimmed = string.gsub(input, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	return trimmed == "" or trimmed == "rbxassetid://" or trimmed == "rbxassetid://0"
end

function GuildUtil.parseIconIdOptional(input: any): (number?, string?)
	if GuildUtil.isIconInputEmpty(input) then
		return 0, nil
	end

	local iconId = GuildUtil.parseIconId(input)
	if not iconId then
		return nil, "Invalid guild icon"
	end

	return iconId, nil
end

function GuildUtil.formatIconImage(iconId: number?): string
	if type(iconId) ~= "number" or iconId <= 0 then
		return ""
	end

	return `rbxassetid://{math.floor(iconId)}`
end

function GuildUtil.getMemberCount(guild: any): number
	if type(guild) ~= "table" or type(guild.Members) ~= "table" then
		return 0
	end

	local count = 0
	for _ in guild.Members do
		count += 1
	end
	return count
end

function GuildUtil.getMaxMembers(guild: any): number
	if type(guild) ~= "table" then
		return GuildConfig.MaxMembers
	end

	return math.max(math.floor(tonumber(guild.MaxMembers) or GuildConfig.MaxMembers), 1)
end

function GuildUtil.canJoin(guild: any): boolean
	if type(guild) ~= "table" then
		return false
	end

	if guild.IsPublic ~= true then
		return false
	end

	return GuildUtil.getMemberCount(guild) < GuildUtil.getMaxMembers(guild)
end

function GuildUtil.isOwner(role: any): boolean
	return role == GuildUtil.RoleOwner
end

function GuildUtil.isMemberRole(role: any): boolean
	return role == GuildUtil.RoleOwner or role == GuildUtil.RoleMember
end

function GuildUtil.toSummary(guild: any, rank: number?): { [string]: any }?
	if type(guild) ~= "table" or type(guild.Id) ~= "string" or guild.Id == "" then
		return nil
	end

	return {
		Id = guild.Id,
		Name = tostring(guild.Name or ""),
		IconId = math.max(math.floor(tonumber(guild.IconId) or 0), 0),
		IsPublic = guild.IsPublic == true,
		MemberCount = GuildUtil.getMemberCount(guild),
		MaxMembers = GuildUtil.getMaxMembers(guild),
		Rank = if type(rank) == "number" then math.max(math.floor(rank), 0) else 0,
		GuildScore = math.max(math.floor(tonumber(guild.GuildScore) or 0), 0),
	}
end

return GuildUtil
