local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Knit = require(ReplicatedStorage.Packages.knit)

local Offline = {}

local localPlayer = Players.LocalPlayer
local OFFLINE_5X_PRODUCT = Monetization.DeveloperProducts.Offline5xReward
local ROBUX_PROMPT_TIMEOUT = 45

local offlineRewardConnections: { RBXScriptConnection } = {}
local offlineRewardRequestOpen = false
local offlineRewardClaimed = false
local offlineRobuxPromptOpen = false
local offlineRewardListenersBound = false

local function isLocalProductPromptFinished(firstArg: any): boolean
	if firstArg == localPlayer then
		return true
	end

	if type(firstArg) == "number" then
		return firstArg == localPlayer.UserId
	end

	return false
end

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
	local multiplier = math.max(math.floor(tonumber(OFFLINE_5X_PRODUCT.Multiplier) or 5), 2)
	self:setNamedText(frame, "OfflineTime", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflineTimer", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflienTime", "You were offline for " .. self:formatOfflineDuration(offlineSeconds))
	self:setNamedText(frame, "OfflineReward", Pricing.formatYen(reward))

	local buy5xButton = frame:FindFirstChild("Buy5x", true)
	if buy5xButton and buy5xButton:IsA("GuiObject") then
		self:setNamedText(buy5xButton, "Price", tostring(OFFLINE_5X_PRODUCT.Price or 39))
		self:setNamedText(buy5xButton, "Reward", Pricing.formatYen(reward * multiplier))
	end
end

function MainGuiController:finishOfflineRewardClaim(frame: GuiObject?, reward: number, multiplier: number?)
	offlineRewardRequestOpen = false
	offlineRobuxPromptOpen = false
	offlineRewardClaimed = true

	if frame then
		OpenFrame.Toggle(frame, false)
	end

	if reward > 0 then
		SoundUtil.RewardClaim()
		self:ShowOfflineRewardMessage(reward, multiplier)
	end
end

function MainGuiController:claimOfflineReward(frame: GuiObject?)
	if offlineRewardClaimed or offlineRewardRequestOpen or offlineRobuxPromptOpen then
		if frame then
			OpenFrame.Toggle(frame, false)
		end
		return
	end

	offlineRewardRequestOpen = true
	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:ClaimOfflineReward()
		:andThen(function(success, err, reward)
			if not success then
				offlineRewardRequestOpen = false
				if err and err ~= "No reward" then
					warn("[MainGuiController] Offline reward failed:", err)
				end
				return
			end

			self:finishOfflineRewardClaim(frame, reward or 0, nil)
		end)
		:catch(function(err)
			offlineRewardRequestOpen = false
			warn("[MainGuiController] Offline reward failed:", err)
		end)
end

function MainGuiController:buyOffline5xReward(frame: GuiObject?)
	if not Monetization.isEnabled() then
		return
	end

	if offlineRewardClaimed or offlineRewardRequestOpen or offlineRobuxPromptOpen then
		return
	end

	offlineRobuxPromptOpen = true
	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:PrepareOffline5xReward():andThen(function(prepared: boolean)
		if not prepared then
			offlineRobuxPromptOpen = false
			SoundUtil.Error()
			warn("[MainGuiController] Prepare offline 5x reward failed")
			return
		end

		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, OFFLINE_5X_PRODUCT.ProductId)
		end)

		if not ok then
			offlineRobuxPromptOpen = false
			TycoonService:CancelOffline5xReward()
			warn("[MainGuiController] Offline 5x robux prompt failed:", err)
			return
		end

		task.delay(ROBUX_PROMPT_TIMEOUT, function()
			if offlineRobuxPromptOpen then
				offlineRobuxPromptOpen = false
				TycoonService:CancelOffline5xReward()
			end
		end)
	end):catch(function(err)
		offlineRobuxPromptOpen = false
		warn("[MainGuiController] Prepare offline 5x reward request failed:", err)
	end)
end

function MainGuiController:bindOfflineRewardListeners()
	if offlineRewardListenersBound then
		return
	end

	offlineRewardListenersBound = true
	local TycoonService = Knit.GetService("TycoonService")

	TycoonService.Offline5xRewardClaimed:Connect(function(reward: number, multiplier: number?)
		if offlineRewardClaimed then
			return
		end

		local frame = self:getOfflineEarningFrame()
		self:finishOfflineRewardClaim(frame, reward or 0, multiplier)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(playerOrUserId, productId, wasPurchased)
		if not Monetization.isEnabled() then
			offlineRobuxPromptOpen = false
			offlineRewardRequestOpen = false
			return
		end

		if productId ~= OFFLINE_5X_PRODUCT.ProductId or not isLocalProductPromptFinished(playerOrUserId) then
			return
		end

		offlineRobuxPromptOpen = false
		if wasPurchased then
			offlineRewardRequestOpen = true
		else
			TycoonService:CancelOffline5xReward()
		end
	end)
end

function MainGuiController:setupOfflineEarningFrame()
	self:bindOfflineRewardListeners()
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

	local buy5xButton = frame:FindFirstChild("Buy5x", true)
	if buy5xButton and buy5xButton:IsA("GuiObject") then
		self:connectOfflineRewardGuiActivated(buy5xButton, function()
			self:buyOffline5xReward(frame)
		end)
	end
end

function MainGuiController:showOfflineEarningAfterDelay()
	if offlineRewardClaimed then
		return
	end

	self:bindOfflineRewardListeners()

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
