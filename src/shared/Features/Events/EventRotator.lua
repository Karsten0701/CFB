local EventRotator = {}
EventRotator.__index = EventRotator

export type EventDefinition = {
	Id: string,
	Name: string,
	Icon: string?,
	VFXKey: string?,
	Description: string?,
	DurationSeconds: number?,
	Effects: { [string]: number }?,
}

export type ActiveEvent = {
	Id: string,
	Name: string,
	Icon: string?,
	VFXKey: string?,
	Description: string,
	StartedAt: number,
	EndsAt: number,
	NextStartsAt: number,
	DurationSeconds: number,
	Effects: { [string]: number },
}

local DEFAULT_DURATION = 5 * 60
local DEFAULT_CYCLE = 15 * 60
local DEFAULT_MIN_COOLDOWN = 2 * 60
local DEFAULT_MAX_COOLDOWN = 5 * 60

local function getStableHash(value: string): number
	local hash = 2166136261
	for index = 1, #value do
		hash = bit32.bxor(hash, string.byte(value, index))
		hash = (hash * 16777619) % 4294967296
	end

	return hash
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

function EventRotator.new(config: { [string]: any })
	local self = setmetatable({}, EventRotator)
	self.config = config or {}
	return self
end

function EventRotator:getEvents(): { EventDefinition }
	local events = self.config.Events
	return if type(events) == "table" then events else {}
end

function EventRotator:getCycleSeconds(): number
	local events = self:getEvents()
	if #events <= 0 then
		return math.max(math.floor(tonumber(self.config.CycleSeconds) or DEFAULT_CYCLE), 1)
	end

	local total = 0
	for index, event in events do
		total += self:getDurationSeconds(event)
		total += self:getCooldownSeconds(event, index)
	end

	return math.max(total, 1)
end

function EventRotator:getGlobalEpochSeconds(): number
	return math.max(math.floor(tonumber(self.config.GlobalEpochSeconds) or 0), 0)
end

function EventRotator:getDurationSeconds(event: EventDefinition?): number
	local configuredDuration = event and tonumber(event.DurationSeconds)
	local fallbackDuration = tonumber(self.config.DefaultDurationSeconds) or DEFAULT_DURATION
	return math.max(math.floor(configuredDuration or fallbackDuration), 1)
end

function EventRotator:getCooldownSeconds(event: EventDefinition?, eventIndex: number): number
	local configuredCooldown = event and tonumber((event :: any).CooldownSeconds)
	if configuredCooldown then
		return math.max(math.floor(configuredCooldown), 0)
	end

	local minCooldown = math.max(math.floor(tonumber(self.config.MinCooldownSeconds) or DEFAULT_MIN_COOLDOWN), 0)
	local maxCooldown = math.max(math.floor(tonumber(self.config.MaxCooldownSeconds) or DEFAULT_MAX_COOLDOWN), minCooldown)
	if maxCooldown <= minCooldown then
		return minCooldown
	end

	local seed = tostring(self.config.CooldownSeed or 0)
	local id = if event and type(event.Id) == "string" then event.Id else tostring(eventIndex)
	local hash = getStableHash(seed .. ":" .. tostring(eventIndex) .. ":" .. id)
	return minCooldown + (hash % (maxCooldown - minCooldown + 1))
end

function EventRotator:getTimelinePosition(now: number?)
	local events = self:getEvents()
	if #events <= 0 then
		return nil
	end

	local epochSeconds = self:getGlobalEpochSeconds()
	local cycleSeconds = self:getCycleSeconds()
	local timestamp = math.max(math.floor(now or os.time()) - epochSeconds, 0)
	local cycleIndex = math.floor(timestamp / cycleSeconds)
	local cycleStartedAt = epochSeconds + cycleIndex * cycleSeconds
	local position = timestamp % cycleSeconds
	local cursor = 0

	for index, event in events do
		local durationSeconds = self:getDurationSeconds(event)
		local cooldownSeconds = self:getCooldownSeconds(event, index)
		local eventStartedAt = cycleStartedAt + cursor
		local eventEndsAt = eventStartedAt + durationSeconds
		local nextStartsAt = eventEndsAt + cooldownSeconds

		if position < cursor + durationSeconds then
			return {
				Event = event,
				EventIndex = index,
				IsActive = true,
				StartedAt = eventStartedAt,
				EndsAt = eventEndsAt,
				NextStartsAt = nextStartsAt,
				DurationSeconds = durationSeconds,
			}
		end

		if position < cursor + durationSeconds + cooldownSeconds then
			local nextIndex = if index >= #events then 1 else index + 1
			local nextEvent = events[nextIndex]
			local nextEventStartsAt = nextStartsAt
			if index >= #events then
				nextEventStartsAt = cycleStartedAt + cycleSeconds
			end

			return {
				Event = nextEvent,
				EventIndex = nextIndex,
				IsActive = false,
				StartedAt = nextEventStartsAt,
				EndsAt = nextEventStartsAt + self:getDurationSeconds(nextEvent),
				NextStartsAt = nextEventStartsAt,
				DurationSeconds = self:getDurationSeconds(nextEvent),
			}
		end

		cursor += durationSeconds + cooldownSeconds
	end

	local firstEvent = events[1]
	local nextStartsAt = cycleStartedAt + cycleSeconds
	return {
		Event = firstEvent,
		EventIndex = 1,
		IsActive = false,
		StartedAt = nextStartsAt,
		EndsAt = nextStartsAt + self:getDurationSeconds(firstEvent),
		NextStartsAt = nextStartsAt,
		DurationSeconds = self:getDurationSeconds(firstEvent),
	}
end

function EventRotator:getActiveEvent(now: number?): ActiveEvent?
	local timeline = self:getTimelinePosition(now)
	if not timeline or not timeline.IsActive then
		return nil
	end

	local event = timeline.Event
	return {
		Id = event.Id or tostring(timeline.EventIndex),
		Name = event.Name or "Anime Event",
		Icon = event.Icon,
		VFXKey = event.VFXKey,
		Description = event.Description or "",
		StartedAt = timeline.StartedAt,
		EndsAt = timeline.EndsAt,
		NextStartsAt = timeline.NextStartsAt,
		DurationSeconds = timeline.DurationSeconds,
		Effects = copyEffects(event.Effects),
	}
end

function EventRotator:getNextEventStartsAt(now: number?): number
	local timeline = self:getTimelinePosition(now)
	return if timeline then timeline.NextStartsAt else math.floor(now or os.time())
end

function EventRotator:getNextEvent(now: number?): EventDefinition?
	local timeline = self:getTimelinePosition(now)
	return if timeline then timeline.Event else nil
end

return EventRotator
