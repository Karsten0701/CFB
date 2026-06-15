local GuildConfig = {}

GuildConfig.DataStorePrefix = "CFB_Guilds_v1"

GuildConfig.CreateCost = 1e9
GuildConfig.MaxMembers = 10
GuildConfig.MaxNameLength = 24
GuildConfig.MinNameLength = 3
GuildConfig.TopGuildsCount = 50
GuildConfig.BrowsePageSize = 25

GuildConfig.Roles = {
	Owner = "Owner",
	Member = "Member",
}

return GuildConfig
