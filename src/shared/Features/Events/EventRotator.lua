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
	return math.max(math.floor(tonumber(self.config.CycleSeconds) or DEFAULT_CYCLE), 1)
end

function EventRotator:getDurationSeconds(event: EventDefinition?): number
	local configuredDuration = event and tonumber(event.DurationSeconds)
	local fallbackDuration = tonumber(self.config.DefaultDurationSeconds) or DEFAULT_DURATION
	return math.clamp(math.floor(configuredDuration or fallbackDuration), 1, self:getCycleSeconds())
end

function EventRotator:getActiveEvent(now: number?): ActiveEvent?
	local events = self:getEvents()
	if #events <= 0 then
		return nil
	end

	local timestamp = math.max(math.floor(now or os.time()), 0)
	local cycleSeconds = self:getCycleSeconds()
	local cycleIndex = math.floor(timestamp / cycleSeconds)
	local cycleStartedAt = cycleIndex * cycleSeconds
	local nextStartsAt = cycleStartedAt + cycleSeconds
	local event = events[(cycleIndex % #events) + 1]
	local durationSeconds = self:getDurationSeconds(event)
	local endsAt = cycleStartedAt + durationSeconds

	if timestamp >= endsAt then
		return nil
	end

	return {
		Id = event.Id or tostring(cycleIndex),
		Name = event.Name or "Anime Event",
		Icon = event.Icon,
		VFXKey = event.VFXKey,
		Description = event.Description or "",
		StartedAt = cycleStartedAt,
		EndsAt = endsAt,
		NextStartsAt = nextStartsAt,
		DurationSeconds = durationSeconds,
		Effects = copyEffects(event.Effects),
	}
end

function EventRotator:getNextEventStartsAt(now: number?): number
	local timestamp = math.max(math.floor(now or os.time()), 0)
	local cycleSeconds = self:getCycleSeconds()
	return (math.floor(timestamp / cycleSeconds) + 1) * cycleSeconds
end

function EventRotator:getNextEvent(now: number?): EventDefinition?
	local events = self:getEvents()
	if #events <= 0 then
		return nil
	end

	local timestamp = math.max(math.floor(now or os.time()), 0)
	local cycleIndex = math.floor(timestamp / self:getCycleSeconds()) + 1
	return events[(cycleIndex % #events) + 1]
end

return EventRotator
