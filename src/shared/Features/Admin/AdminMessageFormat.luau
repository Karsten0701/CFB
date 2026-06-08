local AdminMessageFormat = {}

AdminMessageFormat.Colors = {
	Username = "#FF9B3D",
	Action = "#E8ECFF",
	Connector = "#B8C4D9",
	Multiplier = "#6BFF7A",
	Duration = "#5CEBFF",
	AdminEvent = "#FF6BE8",
	AdminBoost = "#9B7CFF",
	AdminMessage = "#FFD86B",
	System = "#A8B4CC",
	MessageBody = "#FFFFFF",
}

AdminMessageFormat.EffectLabels = {
	YenMultiplier = "YEN",
	ManaMultiplier = "MANA",
	ProcessSpeedMultiplier = "PROCESS",
	DropSpeedMultiplier = "DROP",
	UnitSpawnTierBonus = "SPAWN TIER",
	CapsuleSpawnChanceMultiplier = "CAPSULE",
	AmbientCapsuleIntervalMultiplier = "AMBIENT",
}

AdminMessageFormat.EffectColors = {
	YenMultiplier = "#FFD84A",
	ManaMultiplier = "#42B6FF",
	ProcessSpeedMultiplier = "#FF9B5C",
	DropSpeedMultiplier = "#B88CFF",
	UnitSpawnTierBonus = "#47FF6A",
	CapsuleSpawnChanceMultiplier = "#FF8BE7",
	AmbientCapsuleIntervalMultiplier = "#7CFFE8",
}

local EFFECT_PRIORITY = {
	"YenMultiplier",
	"ManaMultiplier",
	"ProcessSpeedMultiplier",
	"DropSpeedMultiplier",
	"UnitSpawnTierBonus",
	"CapsuleSpawnChanceMultiplier",
	"AmbientCapsuleIntervalMultiplier",
}

local function colorTag(color: string, text: string): string
	return `<font color="{color}">{text}</font>`
end

local function escapeRichText(text: string): string
	return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function AdminMessageFormat.formatDurationBanner(seconds: number): string
	seconds = math.max(math.floor(seconds or 0), 0)
	if seconds >= 3600 then
		local hours = math.floor(seconds / 3600)
		local minutes = math.floor((seconds % 3600) / 60)
		if minutes > 0 then
			return `{hours}h {minutes}m`
		end
		return `{hours} hour` .. (if hours == 1 then "" else "s")
	end

	if seconds >= 60 then
		local minutes = math.floor(seconds / 60)
		local remainingSeconds = seconds % 60
		if remainingSeconds > 0 and minutes < 10 then
			return `{minutes}m {remainingSeconds}s`
		end
		return `{minutes} minute` .. (if minutes == 1 then "" else "s")
	end

	return `{seconds} second` .. (if seconds == 1 then "" else "s")
end

function AdminMessageFormat.getPrimaryEffect(effects: { [string]: number }?): (number?, string?, string?)
	if type(effects) ~= "table" then
		return nil, nil, nil
	end

	for _, effectKey in EFFECT_PRIORITY do
		local value = effects[effectKey]
		if type(value) == "number" and value == value then
			return value, AdminMessageFormat.EffectLabels[effectKey], AdminMessageFormat.EffectColors[effectKey]
		end
	end

	for effectKey, value in effects do
		if type(value) == "number" and value == value then
			return value, AdminMessageFormat.EffectLabels[effectKey] or string.upper(effectKey), "#FFFFFF"
		end
	end

	return nil, nil, nil
end

function AdminMessageFormat.formatMultiplier(value: number, effectKey: string?): string
	if effectKey == "UnitSpawnTierBonus" then
		return `+{math.floor(value)}`
	end

	local rounded = value
	if math.abs(rounded - math.floor(rounded + 0.0001)) < 0.001 then
		rounded = math.floor(rounded + 0.0001)
	else
		rounded = math.floor(rounded * 10 + 0.5) / 10
	end

	return `{rounded}X`
end

local function getPrimaryEffectKey(effects: { [string]: number }?): string?
	if type(effects) ~= "table" then
		return nil
	end

	for _, effectKey in EFFECT_PRIORITY do
		local value = effects[effectKey]
		if type(value) == "number" and value == value then
			return effectKey
		end
	end

	for effectKey, value in effects do
		if type(value) == "number" and value == value then
			return effectKey
		end
	end

	return nil
end

local function formatStartedBanner(
	senderName: string,
	effects: { [string]: number }?,
	durationSeconds: number,
	bannerLabel: string,
	bannerColor: string
): string?
	local colors = AdminMessageFormat.Colors
	local effectKey = getPrimaryEffectKey(effects)
	if not effectKey or type(effects) ~= "table" then
		return nil
	end

	local multiplier = effects[effectKey]
	local effectLabel = AdminMessageFormat.EffectLabels[effectKey]
	local effectColor = AdminMessageFormat.EffectColors[effectKey]
	if not effectLabel or not effectColor then
		return nil
	end

	local multText = AdminMessageFormat.formatMultiplier(multiplier, effectKey)
	local durationText = AdminMessageFormat.formatDurationBanner(durationSeconds)

	return table.concat({
		colorTag(colors.Username, escapeRichText(senderName)),
		colorTag(colors.Action, "just started a"),
		colorTag(colors.Multiplier, multText),
		colorTag(effectColor, effectLabel),
		colorTag(bannerColor, bannerLabel),
		colorTag(colors.Connector, "for"),
		colorTag(colors.Duration, durationText .. "!"),
	}, " ")
end

function AdminMessageFormat.formatEventStarted(senderName: string, adminEvent: any): string
	local effects = if type(adminEvent) == "table" then adminEvent.Effects else nil
	local durationSeconds = if type(adminEvent) == "table"
		then math.max(
			math.floor(adminEvent.DurationSeconds or (adminEvent.EndsAt or 0) - (adminEvent.StartedAt or 0)),
			1
		)
		else 0

	local richText = formatStartedBanner(
		senderName,
		effects,
		durationSeconds,
		"ADMIN EVENT",
		AdminMessageFormat.Colors.AdminEvent
	)
	if richText then
		return richText
	end

	local eventName = if type(adminEvent) == "table" then escapeRichText(adminEvent.Name or "Event") else "Event"
	local durationText = AdminMessageFormat.formatDurationBanner(durationSeconds)
	local colors = AdminMessageFormat.Colors

	return table.concat({
		colorTag(colors.Username, escapeRichText(senderName)),
		colorTag(colors.Action, "just started"),
		colorTag(colors.AdminEvent, eventName),
		colorTag(colors.Connector, "for"),
		colorTag(colors.Duration, durationText .. "!"),
	}, " ")
end

function AdminMessageFormat.formatBoostStarted(senderName: string, boost: any): string
	local effects = if type(boost) == "table" then boost.Effects else nil
	local durationSeconds = if type(boost) == "table"
		then math.max(math.floor((boost.EndsAt or 0) - (boost.StartedAt or 0)), 1)
		else 0

	local richText = formatStartedBanner(
		senderName,
		effects,
		durationSeconds,
		"ADMIN BOOST",
		AdminMessageFormat.Colors.AdminBoost
	)
	if richText then
		return richText
	end

	local boostName = if type(boost) == "table" then escapeRichText(boost.Name or "Boost") else "Boost"
	local durationText = AdminMessageFormat.formatDurationBanner(durationSeconds)
	local colors = AdminMessageFormat.Colors

	return table.concat({
		colorTag(colors.Username, escapeRichText(senderName)),
		colorTag(colors.Action, "just started"),
		colorTag(colors.AdminBoost, boostName),
		colorTag(colors.Connector, "for"),
		colorTag(colors.Duration, durationText .. "!"),
	}, " ")
end

function AdminMessageFormat.formatAdminMessage(senderName: string, message: string): string
	local colors = AdminMessageFormat.Colors
	return colorTag(colors.AdminMessage, escapeRichText(senderName))
		.. colorTag(colors.MessageBody, ": " .. escapeRichText(message))
end

function AdminMessageFormat.formatSystemMessage(senderName: string, message: string): string
	local colors = AdminMessageFormat.Colors
	return colorTag(colors.System, escapeRichText(senderName))
		.. colorTag(colors.MessageBody, ": " .. escapeRichText(message))
end

return AdminMessageFormat
