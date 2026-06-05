local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EventConfig = require(ReplicatedStorage.Shared.Data.Events)
local EventRotator = require(script.Parent.EventRotator)

local EventUtil = {}
local rotator = EventRotator.new(EventConfig)

function EventUtil.getNow(): number
	local ok, serverTime = pcall(function()
		return Workspace:GetServerTimeNow()
	end)

	if ok and type(serverTime) == "number" and serverTime == serverTime then
		return serverTime
	end

	return os.time()
end

function EventUtil.getActiveEvent(now: number?)
	return rotator:getActiveEvent(now or EventUtil.getNow())
end

function EventUtil.getNextEventStartsAt(now: number?): number
	return rotator:getNextEventStartsAt(now or EventUtil.getNow())
end

function EventUtil.getNextEvent(now: number?)
	return rotator:getNextEvent(now or EventUtil.getNow())
end

function EventUtil.getEffectMultiplier(effectName: string, fallback: number?, now: number?): number
	local activeEvent = EventUtil.getActiveEvent(now)
	local value = activeEvent and activeEvent.Effects[effectName]
	if type(value) ~= "number" or value ~= value then
		return fallback or 1
	end

	return value
end

function EventUtil.getEffectBonus(effectName: string, fallback: number?, now: number?): number
	local activeEvent = EventUtil.getActiveEvent(now)
	local value = activeEvent and activeEvent.Effects[effectName]
	if type(value) ~= "number" or value ~= value then
		return fallback or 0
	end

	return value
end

function EventUtil.formatTime(seconds: number): string
	seconds = math.max(math.floor(seconds or 0), 0)
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

return EventUtil
