local GuildConfig = {}

GuildConfig.DataStorePrefix = "CFB_Guilds_v1"

GuildConfig.CreateCost = 1e9
GuildConfig.MaxMembers = 10
GuildConfig.MaxNameLength = 24
GuildConfig.MinNameLength = 3
GuildConfig.TopGuildsCount = 100
GuildConfig.BrowseRandomCount = 50
GuildConfig.BrowseSearchMaxResults = 100
GuildConfig.BrowsePageSize = 50
GuildConfig.PowerSyncIntervalSeconds = 300
GuildConfig.LeaderboardCacheSeconds = 300
GuildConfig.GuildRecordCacheSeconds = 60
GuildConfig.LeaderboardWriteIntervalSeconds = 2
GuildConfig.MessagingTopicLeaderboard = GuildConfig.DataStorePrefix .. "_LeaderboardInvalidate"
GuildConfig.MessagingTopicGuildSync = GuildConfig.DataStorePrefix .. "_GuildSync"

GuildConfig.Roles = {
	Owner = "Owner",
	Member = "Member",
}

return GuildConfig
