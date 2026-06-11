local TweenService = game:GetService("TweenService")

local ButtonNoti = {}

local WIGGLE_INTERVAL = 10
local WIGGLE_DEGREES = 10
local WIGGLE_STEP_DURATION = 0.12

type NotiState = {
	wiggleToken: number,
	wiggleRunning: boolean,
	baseRotation: number,
}

local states: { [string]: NotiState } = {}

local function getState(buttonKey: string): NotiState
	local state = states[buttonKey]
	if not state then
		state = {
			wiggleToken = 0,
			wiggleRunning = false,
			baseRotation = 0,
		}
		states[buttonKey] = state
	end

	return state
end

local function tweenRotation(noti: GuiObject, rotation: number, duration: number)
	local tween = TweenService:Create(
		noti,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Rotation = rotation }
	)
	tween:Play()
	tween.Completed:Wait()
end

local function playWiggleStep(noti: GuiObject, baseRotation: number, flipPositive: boolean)
	local offset = if flipPositive then WIGGLE_DEGREES else -WIGGLE_DEGREES
	tweenRotation(noti, baseRotation + offset, WIGGLE_STEP_DURATION)
	tweenRotation(noti, baseRotation - offset, WIGGLE_STEP_DURATION * 2)
	tweenRotation(noti, baseRotation, WIGGLE_STEP_DURATION)
end

function ButtonNoti.getNoti(MainGuiController, buttonName: string): GuiObject?
	local button = MainGuiController:getRightSideButton(buttonName)
	if not button then
		return nil
	end

	local noti = button:FindFirstChild("Noti")
	return if noti and noti:IsA("GuiObject") then noti else nil
end

function ButtonNoti.hideInitially(MainGuiController, buttonName: string)
	local noti = ButtonNoti.getNoti(MainGuiController, buttonName)
	if noti then
		noti.Visible = false
	end
end

function ButtonNoti.stop(buttonKey: string, noti: GuiObject?)
	local state = getState(buttonKey)
	state.wiggleToken += 1
	state.wiggleRunning = false
	if noti then
		noti.Rotation = state.baseRotation
	end
end

function ButtonNoti.start(buttonKey: string, noti: GuiObject)
	local state = getState(buttonKey)
	if state.wiggleRunning then
		return
	end

	state.wiggleRunning = true
	state.wiggleToken += 1
	state.baseRotation = noti.Rotation
	local wiggleToken = state.wiggleToken

	task.spawn(function()
		local flipPositive = false
		while wiggleToken == state.wiggleToken and noti.Parent and noti.Visible do
			flipPositive = not flipPositive
			playWiggleStep(noti, state.baseRotation, flipPositive)

			if wiggleToken ~= state.wiggleToken or not noti.Parent or not noti.Visible then
				break
			end

			task.wait(WIGGLE_INTERVAL)
		end

		state.wiggleRunning = false
		if wiggleToken == state.wiggleToken and noti.Parent then
			noti.Rotation = state.baseRotation
		end
	end)
end

function ButtonNoti.update(MainGuiController, buttonKey: string, buttonName: string, show: boolean)
	local noti = ButtonNoti.getNoti(MainGuiController, buttonName)
	if not noti then
		return
	end

	noti.Visible = show
	if show then
		ButtonNoti.start(buttonKey, noti)
	else
		ButtonNoti.stop(buttonKey, noti)
	end
end

return ButtonNoti
