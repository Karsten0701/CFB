local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Knit = require(ReplicatedStorage.Packages.knit)

local Offline = {}

local offlineRewardConnections: { RBXScriptConnection } = {}
local offlineRewardRequestOpen = false
local offlineRewardClaimed = false

function Offline.Install(MainGuiController)

function MainGuiController:clearOfflineRewardConnections()
	for _, connection in offlineRewardConnections do
		connection:Disconnect()
	end

	table.clear(offlineRewardConnections)
end

function MainGuiController:connectOfflineRewardGuiActivated(guiObject: GuiObject, callback: () -> ())
	local clickable = self:getClickableGui(guiObject)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		table.insert(offlineRewardConnections, clickable.Activated:Connect(callback))
	else
		table.insert(
			offlineRewardConnections,
			clickable.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					callback()
				end
			end)
		)
	end
end

function MainGuiController:formatOfflineDuration(seconds: number): string
	seconds = math.max(math.floor(seconds or 0), 0)
	local totalMinutes = math.floor(seconds / 60 + 0.5)
	local hours = math.floor(totalMinutes / 60)
	local minutes = totalMinutes % 60

	if hours <= 0 then
		local minuteLabel = if minutes == 1 then " minute" else " minutes"
		return tostring(minutes) .. minuteLabel
	end

	if minutes <= 0 then
		local hourLabel = if hours == 1 then " hour" else " hours"
		return tostring(hours) .. hourLabel
	end

	local hourLabel = if hours == 1 then " hour and " else " hours and "
	local minuteLabel = if minutes == 1 then " minute" else " minutes"
	return tostring(hours) .. hourLabel .. tostring(minutes) .. minuteLabel
end

function MainGuiController:updateOfflineEarningFrame(payload: any)
	local frame = self:getOfflineEarningFrame()
	if not frame or type(payload) ~= "table" then
		return
	end

	local offlineSeconds = math.max(math.floor(payload.OfflineSeconds or 0), 0)
	local reward = math.max(math.floor(payload.Reward or 0), 0)
	self:setNamedText(frame, "OfflineTime", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflineTimer", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflienTime", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflineReward", Pricing.formatYen(reward))
end

function MainGuiController:claimOfflineReward(frame: GuiObject?)
	if offlineRewardClaimed or offlineRewardRequestOpen then
		if frame then
			OpenFrame.Toggle(frame, false)
		end
		return
	end

	offlineRewardRequestOpen = true
	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:ClaimOfflineReward()
		:andThen(function(success, err, reward)
			offlineRewardRequestOpen = false
			offlineRewardClaimed = true
			if frame then
				OpenFrame.Toggle(frame, false)
			end

			if success then
				SoundUtil.RewardClaim()
				self:ShowOfflineRewardMessage(reward or 0)
			elseif err and err ~= "No reward" then
				warn("[MainGuiController] Offline reward failed:", err)
			end
		end)
		:catch(function(err)
			offlineRewardRequestOpen = false
			if frame then
				OpenFrame.Toggle(frame, false)
			end
			warn("[MainGuiController] Offline reward failed:", err)
		end)
end

function MainGuiController:setupOfflineEarningFrame()
	self:clearOfflineRewardConnections()

	local frame = self:getOfflineEarningFrame()
	if not frame then
		return
	end

	frame.Visible = false
	OpenFrame.SetupFrame(frame)

	local topBar = frame:FindFirstChild("TopBar")
	local closeButton = topBar and topBar:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiObject") then
		self:connectOfflineRewardGuiActivated(closeButton, function()
			self:claimOfflineReward(frame)
		end)
	end

	local claimButton = frame:FindFirstChild("Claim", true)
	if claimButton and claimButton:IsA("GuiObject") then
		self:connectOfflineRewardGuiActivated(claimButton, function()
			self:claimOfflineReward(frame)
		end)
	end
end

function MainGuiController:showOfflineEarningAfterDelay()
	if offlineRewardClaimed then
		return
	end

	local offlineConfig = TycoonConfig.OfflineReward or {}
	task.delay(tonumber(offlineConfig.ClaimPopupDelay) or 20, function()
		if offlineRewardClaimed then
			return
		end

		local frame = self:getOfflineEarningFrame()
		if not frame then
			return
		end

		local TycoonService = Knit.GetService("TycoonService")
		TycoonService:GetOfflineReward()
			:andThen(function(success, payload)
				if not success or type(payload) ~= "table" or payload.Eligible ~= true then
					return
				end

				self:updateOfflineEarningFrame(payload)
				OpenFrame.Toggle(frame, true)
			end)
			:catch(function(err)
				warn("[MainGuiController] Failed to get offline reward:", err)
			end)
	end)
end


end

return Offline
