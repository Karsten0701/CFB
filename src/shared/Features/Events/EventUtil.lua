local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AdminRuntime = require(ReplicatedStorage.Shared.Features.Admin.AdminRuntime)
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
	now = now or EventUtil.getNow()
	local adminEvent = AdminRuntime.getActiveAdminEvent(now)
	if adminEvent then
		return {
			Id = adminEvent.Id,
			Name = adminEvent.Name,
			Icon = adminEvent.Icon,
			VFXKey = adminEvent.VFXKey,
			Description = adminEvent.Description,
			StartedAt = adminEvent.StartedAt,
			EndsAt = adminEvent.EndsAt,
			NextStartsAt = adminEvent.EndsAt,
			DurationSeconds = adminEvent.DurationSeconds,
			Effects = adminEvent.Effects,
		}
	end

	return rotator:getActiveEvent(now)
end

function EventUtil.getNextEventStartsAt(now: number?): number
	return rotator:getNextEventStartsAt(now or EventUtil.getNow())
end

function EventUtil.getNextEvent(now: number?)
	return rotator:getNextEvent(now or EventUtil.getNow())
end

local function applyAdminBoostMultipliers(effectName: string, value: number, now: number): number
	for _, boost in AdminRuntime.getActiveBoosts(now) do
		local boostValue = boost.Effects[effectName]
		if type(boostValue) == "number" and boostValue == boostValue then
			value *= boostValue
		end
	end
	return value
end

local function applyAdminBoostBonuses(effectName: string, value: number, now: number): number
	for _, boost in AdminRuntime.getActiveBoosts(now) do
		local boostValue = boost.Effects[effectName]
		if type(boostValue) == "number" and boostValue == boostValue then
			value += boostValue
		end
	end
	return value
end

function EventUtil.getEffectMultiplier(effectName: string, fallback: number?, now: number?): number
	now = now or EventUtil.getNow()
	if effectName == "UnitSpawnTierBonus" then
		return fallback or 1
	end

	local activeEvent = EventUtil.getActiveEvent(now)
	local value = activeEvent and activeEvent.Effects[effectName]
	if type(value) ~= "number" or value ~= value then
		value = fallback or 1
	end

	return applyAdminBoostMultipliers(effectName, value, now)
end

function EventUtil.getEffectBonus(effectName: string, fallback: number?, now: number?): number
	now = now or EventUtil.getNow()
	if effectName ~= "UnitSpawnTierBonus" then
		return fallback or 0
	end

	local activeEvent = EventUtil.getActiveEvent(now)
	local value = activeEvent and activeEvent.Effects[effectName]
	if type(value) ~= "number" or value ~= value then
		value = fallback or 0
	end

	return applyAdminBoostBonuses(effectName, value, now)
end

function EventUtil.formatTime(seconds: number): string
	seconds = math.max(math.floor(seconds or 0), 0)
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

return EventUtil
