local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AdminConfig = require(ReplicatedStorage.Shared.Data.AdminConfig)
local EventConfig = require(ReplicatedStorage.Shared.Data.Events)

local AdminRuntime = {}

export type AdminEventState = {
	Id: string,
	Name: string,
	Icon: string?,
	VFXKey: string?,
	Description: string,
	StartedAt: number,
	EndsAt: number,
	DurationSeconds: number,
	Effects: { [string]: number },
	StartedByName: string?,
}

export type AdminBoostState = {
	Id: string,
	Name: string,
	Icon: string?,
	Description: string?,
	Effects: { [string]: number },
	StartedAt: number,
	EndsAt: number,
	StartedByName: string?,
}

local replicatedState: {
	AdminEvent: AdminEventState?,
	Boosts: { AdminBoostState },
}? = nil

local function getNow(): number
	local ok, serverTime = pcall(function()
		return Workspace:GetServerTimeNow()
	end)

	if ok and type(serverTime) == "number" and serverTime == serverTime then
		return math.floor(serverTime)
	end

	return os.time()
end

local function copyEffects(effects: { [string]: number }?): { [string]: number }
	local copied = {}
	if type(effects) ~= "table" then
		return copied
	end

	for key, value in effects do
		if type(key) == "string" and type(value) == "number" and value == value then
			copied[key] = value
		end
	end

	return copied
end

local function copyBoostState(boost: AdminBoostState): AdminBoostState
	return {
		Id = boost.Id,
		Name = boost.Name,
		Icon = boost.Icon,
		Description = boost.Description,
		Effects = copyEffects(boost.Effects),
		StartedAt = boost.StartedAt,
		EndsAt = boost.EndsAt,
		StartedByName = boost.StartedByName,
	}
end

local function copyAdminEventState(adminEvent: AdminEventState): AdminEventState
	return {
		Id = adminEvent.Id,
		Name = adminEvent.Name,
		Icon = adminEvent.Icon,
		VFXKey = adminEvent.VFXKey,
		Description = adminEvent.Description,
		StartedAt = adminEvent.StartedAt,
		EndsAt = adminEvent.EndsAt,
		DurationSeconds = adminEvent.DurationSeconds,
		Effects = copyEffects(adminEvent.Effects),
		StartedByName = adminEvent.StartedByName,
	}
end

function AdminRuntime.setReplicatedState(state: { AdminEvent: AdminEventState?, Boosts: { AdminBoostState } }?)
	if type(state) ~= "table" then
		replicatedState = nil
		return
	end

	local boosts = {}
	if type(state.Boosts) == "table" then
		for _, boost in state.Boosts do
			if type(boost) == "table" then
				table.insert(boosts, copyBoostState(boost))
			end
		end
	end

	replicatedState = {
		AdminEvent = if type(state.AdminEvent) == "table"
			then copyAdminEventState(state.AdminEvent)
			else nil,
		Boosts = boosts,
	}
end

function AdminRuntime.getReplicatedState()
	return replicatedState
end

function AdminRuntime.findEventDefinition(eventId: string)
	eventId = tostring(eventId or "")
	if eventId == "" then
		return nil
	end

	for _, event in EventConfig.Events do
		if type(event) == "table" and event.Id == eventId then
			return event
		end
	end

	return nil
end

function AdminRuntime.getEventIds(): { string }
	local ids = {}
	for _, event in EventConfig.Events do
		if type(event) == "table" and type(event.Id) == "string" then
			table.insert(ids, event.Id)
		end
	end
	return ids
end

function AdminRuntime.getEventDefaultMultiplier(eventId: string): number?
	local definition = AdminRuntime.findEventDefinition(eventId)
	if not definition or type(definition.Effects) ~= "table" then
		return nil
	end

	for _, effect in definition.Effects do
		if type(effect) == "number" and effect == effect then
			return effect
		end
	end

	return nil
end

local function applyEventMultiplier(effects: { [string]: number }, multiplier: number): { [string]: number }
	local applied = copyEffects(effects)
	for key in applied do
		applied[key] = multiplier
	end
	return applied
end

function AdminRuntime.buildEventDescription(effects: { [string]: number }, durationSeconds: number): string
	return `{AdminRuntime.describeEffects(effects)} for {AdminRuntime.formatDuration(durationSeconds)}.`
end

function AdminRuntime.getBoostType(boostType: string)
	return AdminConfig.BoostTypes[boostType]
end

function AdminRuntime.getBoostTypeKeys(): { string }
	local keys = {}
	for key in AdminConfig.BoostTypes do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

function AdminRuntime.buildAdminEvent(
	eventId: string,
	durationSeconds: number,
	startedByName: string?,
	now: number?,
	multiplier: number?
): AdminEventState?
	local definition = AdminRuntime.findEventDefinition(eventId)
	if not definition then
		return nil
	end

	now = math.floor(now or getNow())
	durationSeconds = math.max(math.floor(durationSeconds), 1)

	local effects = copyEffects(definition.Effects)
	local resolvedMultiplier = tonumber(multiplier)
	if resolvedMultiplier ~= nil and resolvedMultiplier == resolvedMultiplier then
		resolvedMultiplier = math.max(resolvedMultiplier, 0.01)
		effects = applyEventMultiplier(effects, resolvedMultiplier)
	end

	local description = if resolvedMultiplier ~= nil
		then AdminRuntime.buildEventDescription(effects, durationSeconds)
		else definition.Description or AdminRuntime.buildEventDescription(effects, durationSeconds)

	return {
		Id = "admin:" .. definition.Id,
		Name = definition.Name,
		Icon = definition.Icon,
		VFXKey = definition.VFXKey,
		Description = description,
		StartedAt = now,
		EndsAt = now + durationSeconds,
		DurationSeconds = durationSeconds,
		Effects = effects,
		StartedByName = startedByName,
	}
end

function AdminRuntime.buildBoost(
	boostType: string,
	multiplier: number,
	durationSeconds: number,
	startedByName: string?,
	now: number?
): AdminBoostState?
	local boostConfig = AdminRuntime.getBoostType(boostType)
	if not boostConfig then
		return nil
	end

	now = math.floor(now or getNow())
	durationSeconds = math.max(math.floor(durationSeconds), 1)
	multiplier = math.max(tonumber(multiplier) or boostConfig.DefaultMultiplier or 1, 0.01)

	local label = boostConfig.Label or boostType
	local name = if boostConfig.IsBonus then `+{multiplier} {label}` else `{multiplier}x {label}`
	local description =
		`{AdminRuntime.describeEffects({ [boostConfig.EffectKey] = multiplier })} for {AdminRuntime.formatDuration(durationSeconds)}.`

	return {
		Id = `boost_{boostType}_{now}_{math.random(100000, 999999)}`,
		Name = name,
		Icon = boostConfig.Icon,
		Description = description,
		Effects = {
			[boostConfig.EffectKey] = multiplier,
		},
		StartedAt = now,
		EndsAt = now + durationSeconds,
		StartedByName = startedByName,
	}
end

local function pruneExpiredBoosts(boosts: { AdminBoostState }, now: number): { AdminBoostState }
	local nextBoosts = {}
	for _, boost in boosts do
		if type(boost) == "table" and math.floor(boost.EndsAt or 0) > now then
			table.insert(nextBoosts, boost)
		end
	end
	return nextBoosts
end

function AdminRuntime.getActiveAdminEvent(now: number?): AdminEventState?
	now = math.floor(now or getNow())
	local state = replicatedState
	local adminEvent = state and state.AdminEvent
	if type(adminEvent) ~= "table" then
		return nil
	end

	if math.floor(adminEvent.EndsAt or 0) <= now then
		return nil
	end

	return adminEvent
end

function AdminRuntime.getActiveBoosts(now: number?): { AdminBoostState }
	now = math.floor(now or getNow())
	local state = replicatedState
	if not state or type(state.Boosts) ~= "table" then
		return {}
	end

	return pruneExpiredBoosts(state.Boosts, now)
end

function AdminRuntime.formatDuration(seconds: number): string
	seconds = math.max(math.floor(seconds or 0), 0)
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	if minutes > 0 and remainingSeconds > 0 then
		return `{minutes} min {remainingSeconds}s`
	end
	if minutes > 0 then
		return `{minutes} min`
	end
	return `{remainingSeconds}s`
end

function AdminRuntime.describeEffects(effects: { [string]: number }): string
	local labels = {
		YenMultiplier = "Yen",
		ManaMultiplier = "Mana",
		ProcessSpeedMultiplier = "Process Speed",
		DropSpeedMultiplier = "Drop Speed",
		UnitSpawnTierBonus = "Spawn Tier",
		CapsuleSpawnChanceMultiplier = "Capsule Spawn",
		AmbientCapsuleIntervalMultiplier = "Ambient Capsules",
	}

	local parts = {}
	for key, value in effects do
		local label = labels[key] or key
		if key == "UnitSpawnTierBonus" then
			table.insert(parts, `+{value} {label}`)
		else
			table.insert(parts, `{value}x {label}`)
		end
	end

	table.sort(parts)
	if #parts <= 0 then
		return "boost"
	end
	return table.concat(parts, ", ")
end

return AdminRuntime
