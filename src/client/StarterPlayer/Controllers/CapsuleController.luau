local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleOpenAnimation = require(script.Parent.Parent.Parent.Features.Capsules.CapsuleOpenAnimation)
local CapsuleRenderer = require(script.Parent.Parent.Parent.Features.Capsules.CapsuleRenderer)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local EventUtil = require(ReplicatedStorage.Shared.Features.Events.EventUtil)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local TycoonUtil = require(ReplicatedStorage.Shared.Features.Tycoon.TycoonUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local CapsuleController = Knit.CreateController({
	Name = "CapsuleController",
})

local localPlayer = Players.LocalPlayer
local renderer: any = nil
local ambientLoopRunning = false
local robuxPromptOpen = false
local openingCapsule = false
local pendingRobuxCapsuleId: string? = nil
local handledRobuxCapsules: { [string]: boolean } = {}
local OPEN_CAPSULE_PRODUCT = Monetization.DeveloperProducts.OpenCapsule
local ROBUX_REWARD_TIMEOUT = 8
local ROBUX_PROMPT_TIMEOUT = 45

local function getCapsuleConfig()
	return TycoonConfig.Capsules or {}
end

local function isLocalProductPromptFinished(firstArg: any): boolean
	if firstArg == localPlayer then
		return true
	end

	if type(firstArg) == "number" then
		return firstArg == localPlayer.UserId
	end

	return false
end

local function getOwnTycoon(): Instance?
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local tycoonName = PlayerDataController:Get("TycoonName")
	if type(tycoonName) ~= "string" or tycoonName == "" then
		return nil
	end

	return TycoonUtil.getPlayerTycoon(localPlayer, tycoonName)
end

local function getRandomTycoonSpawnCFrame(tycoon: Instance): CFrame?
	local spawnPart = tycoon:FindFirstChild("Spawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame + Vector3.new(math.random(-8, 8), 2.5, math.random(-8, 8))
	end

	local base = tycoon:FindFirstChildWhichIsA("BasePart", true)
	if base then
		return base.CFrame + Vector3.new(0, 3, 0)
	end

	return nil
end

function CapsuleController:ensureRenderer()
	if renderer then
		return renderer
	end

	local folder = Instance.new("Folder")
	folder.Name = "LocalCapsules"
	folder.Parent = workspace
	renderer = CapsuleRenderer.new(folder)
	return renderer
end

function CapsuleController:GetHeldCapsuleIds(): { string }
	if not renderer then
		return {}
	end

	return renderer:getHeldCapsuleIds()
end

function CapsuleController:GetHeldCapsuleInfo(capsuleId: string): { PreviewTiers: { number }, OpenPrice: number, HighestTier: number }?
	if not renderer then
		return nil
	end

	local entry = renderer:getEntry(capsuleId)
	if not entry or not entry.pickedUp then
		return nil
	end

	return {
		PreviewTiers = entry.previewTiers,
		OpenPrice = entry.openPrice,
		HighestTier = entry.highestTier,
	}
end

function CapsuleController:HasCapsule(capsuleId: string): boolean
	return renderer ~= nil and renderer:getEntry(capsuleId) ~= nil
end

function CapsuleController:ClearCapsules()
	openingCapsule = false
	robuxPromptOpen = false
	pendingRobuxCapsuleId = nil
	table.clear(handledRobuxCapsules)

	local MainGuiController = Knit.GetController("MainGuiController")
	MainGuiController:hideOpenCapsuleUI()

	if renderer then
		renderer:destroy()
	end
end

function CapsuleController:spawnCapsuleVisual(capsuleId: string, spawnCFrame: CFrame, payload: any, dropPart: BasePart?)
	local capsuleRenderer = self:ensureRenderer()
	local spawnOptions = nil

	if dropPart then
		local TycoonController = Knit.GetController("TycoonController")
		local tycoonRenderer = TycoonController:GetOwnRenderer()
		if tycoonRenderer then
			spawnOptions = {
				parent = tycoonRenderer:getDropsFolder(),
				rollDirection = dropPart.CFrame.LookVector,
				registerPossibleDrop = function(pickupPart: BasePart, container: Instance)
					tycoonRenderer:registerPossibleDrop(pickupPart, container, dropPart)
				end,
				unregisterPossibleDrop = function(pickupPart: BasePart)
					tycoonRenderer:unregisterPossibleDrop(pickupPart)
				end,
			}
		end
	end

	capsuleRenderer:spawnCapsule(
		capsuleId,
		spawnCFrame,
		payload.PreviewTiers,
		payload.OpenPrice,
		payload.HighestTier,
		function(id: string)
			self:onCapsulePickedUp(id)
		end,
		function(id: string)
			self:dismissCapsule(id)
		end,
		spawnOptions
	)
end

function CapsuleController:onCapsulePickedUp(capsuleId: string)
	SoundUtil.Pickup()
	self:showHeldCapsuleUI(capsuleId)
end

function CapsuleController:showHeldCapsuleUI(capsuleId: string)
	local entry = renderer and renderer:getEntry(capsuleId)
	if not entry then
		return
	end

	local MainGuiController = Knit.GetController("MainGuiController")
	MainGuiController:showOpenCapsuleUI(
		capsuleId,
		entry.previewTiers,
		entry.openPrice,
		entry.highestTier
	)
end

function CapsuleController:dropCapsule(capsuleId: string)
	if renderer then
		renderer:releaseHold(capsuleId)
	end
	self:dismissCapsule(capsuleId)
end

function CapsuleController:dismissCapsule(capsuleId: string)
	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:DismissCapsule(capsuleId)

	if renderer then
		renderer:destroyCapsule(capsuleId)
	end

	local MainGuiController = Knit.GetController("MainGuiController")
	if MainGuiController.activeCapsuleId == capsuleId then
		MainGuiController:hideOpenCapsuleUI()
	end
end

function CapsuleController:finishOpen(capsuleId: string, rewardTier: number?)
	if renderer then
		renderer:releaseHold(capsuleId)
		renderer:destroyCapsule(capsuleId)
	end

	local MainGuiController = Knit.GetController("MainGuiController")
	MainGuiController:hideOpenCapsuleUI()
	if rewardTier then
		MainGuiController:ShowCapsuleRewardMessage(rewardTier)
	end
end

function CapsuleController:claimRewardThenFinish(capsuleId: string, rewardTier: number?)
	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:ClaimCapsuleReward(capsuleId):andThen(function(success: boolean, err: string?)
		if not success then
			warn("[CapsuleController] Claim capsule reward failed:", err)
		end

		self:finishOpen(capsuleId, rewardTier)
	end):catch(function(err)
		warn("[CapsuleController] Claim capsule reward request failed:", err)
		self:finishOpen(capsuleId, rewardTier)
	end)
end

function CapsuleController:playOpenAnimation(capsuleId: string, rewardTier: number, onComplete: (() -> ())?)
	local entry = renderer and renderer:getEntry(capsuleId)
	if not entry or not entry.root or not entry.instance then
		if onComplete then
			onComplete()
		end
		return
	end

	local MainGuiController = Knit.GetController("MainGuiController")
	MainGuiController:hideOpenCapsuleUI()

	if renderer then
		renderer:releaseHold(capsuleId)
	end

	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		local openCFrame = rootPart.CFrame * CFrame.new(0, 1.25, -6)
		if entry.instance:IsA("Model") then
			entry.instance:PivotTo(openCFrame)
		else
			entry.root.CFrame = openCFrame
		end
	end

	task.spawn(function()
		CapsuleOpenAnimation.play(entry.instance, entry.root, rewardTier, onComplete)
	end)
end

function CapsuleController:openWithYen(capsuleId: string)
	if openingCapsule or robuxPromptOpen then
		return
	end

	openingCapsule = true

	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:OpenCapsule(capsuleId):andThen(function(success: boolean, err: string?, rewardTier: number?)
		if not success then
			openingCapsule = false
			if err == "Not enough yen" then
				SoundUtil.Error()
			elseif err and err ~= "Unknown capsule" then
				warn("[CapsuleController] Open capsule failed:", err)
			end

			local entry = renderer and renderer:getEntry(capsuleId)
			if entry and entry.pickedUp then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:showOpenCapsuleUI(
					capsuleId,
					entry.previewTiers,
					entry.openPrice,
					entry.highestTier
				)
			end
			return
		end

		if type(rewardTier) ~= "number" then
			openingCapsule = false
			warn("[CapsuleController] Open capsule returned no reward tier")
			local entry = renderer and renderer:getEntry(capsuleId)
			if entry and entry.pickedUp then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:showOpenCapsuleUI(
					capsuleId,
					entry.previewTiers,
					entry.openPrice,
					entry.highestTier
				)
			end
			return
		end

		if not self:HasCapsule(capsuleId) then
			openingCapsule = false
			return
		end

		self:playOpenAnimation(capsuleId, rewardTier or 1, function()
			if not self:HasCapsule(capsuleId) then
				openingCapsule = false
				return
			end

			openingCapsule = false
			self:claimRewardThenFinish(capsuleId, rewardTier)
		end)
	end):catch(function(err)
		openingCapsule = false
		warn("[CapsuleController] Open capsule request failed:", err)
	end)
end

function CapsuleController:waitForRobuxReward(capsuleId: string, startedAt: number)
	if handledRobuxCapsules[capsuleId] then
		return
	end

	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:GetPendingCapsuleReward(capsuleId):andThen(function(rewardTier: number?)
		if handledRobuxCapsules[capsuleId] then
			return
		end

		local entry = renderer and renderer:getEntry(capsuleId)
		if not entry then
			openingCapsule = false
			return
		end

		if type(rewardTier) == "number" then
			if not self:HasCapsule(capsuleId) then
				openingCapsule = false
				handledRobuxCapsules[capsuleId] = nil
				return
			end

			handledRobuxCapsules[capsuleId] = true
			openingCapsule = true
			self:playOpenAnimation(capsuleId, rewardTier, function()
				if not self:HasCapsule(capsuleId) then
					openingCapsule = false
					handledRobuxCapsules[capsuleId] = nil
					return
				end

				openingCapsule = false
				self:claimRewardThenFinish(capsuleId, rewardTier)
				handledRobuxCapsules[capsuleId] = nil
			end)
			return
		end

		if os.clock() - startedAt >= ROBUX_REWARD_TIMEOUT then
			openingCapsule = false
			warn("[CapsuleController] Timed out waiting for capsule robux reward")
			if entry.pickedUp then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:showOpenCapsuleUI(
					capsuleId,
					entry.previewTiers,
					entry.openPrice,
					entry.highestTier
				)
			end
			handledRobuxCapsules[capsuleId] = nil
			return
		end

		task.delay(0.25, function()
			self:waitForRobuxReward(capsuleId, startedAt)
		end)
	end):catch(function(err)
		openingCapsule = false
		warn("[CapsuleController] Get pending capsule reward failed:", err)
	end)
end

function CapsuleController:onRobuxCapsuleOpened(capsuleId: string, rewardTier: number?)
	if type(capsuleId) ~= "string" or capsuleId == "" or handledRobuxCapsules[capsuleId] then
		return
	end

	handledRobuxCapsules[capsuleId] = true
	robuxPromptOpen = false
	pendingRobuxCapsuleId = nil

	if type(rewardTier) == "number" then
		if not self:HasCapsule(capsuleId) then
			openingCapsule = false
			handledRobuxCapsules[capsuleId] = nil
			return
		end

		openingCapsule = true
		self:playOpenAnimation(capsuleId, rewardTier, function()
			if not self:HasCapsule(capsuleId) then
				openingCapsule = false
				handledRobuxCapsules[capsuleId] = nil
				return
			end

			openingCapsule = false
			self:claimRewardThenFinish(capsuleId, rewardTier)
			handledRobuxCapsules[capsuleId] = nil
		end)
		return
	end

	openingCapsule = true
	self:waitForRobuxReward(capsuleId, os.clock())
end

function CapsuleController:openWithRobux(capsuleId: string)
	if robuxPromptOpen or openingCapsule then
		return
	end

	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:PrepareCapsuleRobuxOpen(capsuleId):andThen(function(prepared: boolean)
		if not prepared then
			SoundUtil.Error()
			warn("[CapsuleController] Prepare capsule robux open failed")
			return
		end

		pendingRobuxCapsuleId = capsuleId
		robuxPromptOpen = true
		local promptCapsuleId = capsuleId

		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, OPEN_CAPSULE_PRODUCT.ProductId)
		end)

		if not ok then
			robuxPromptOpen = false
			pendingRobuxCapsuleId = nil
			local MainGuiController = Knit.GetController("MainGuiController")
			local entry = renderer and renderer:getEntry(capsuleId)
			if entry and entry.pickedUp then
				MainGuiController:showOpenCapsuleUI(
					capsuleId,
					entry.previewTiers,
					entry.openPrice,
					entry.highestTier
				)
			end
			warn("[CapsuleController] Capsule robux prompt failed:", err)
			return
		end

		task.delay(ROBUX_PROMPT_TIMEOUT, function()
			if robuxPromptOpen and pendingRobuxCapsuleId == promptCapsuleId then
				robuxPromptOpen = false
				pendingRobuxCapsuleId = nil
			end
		end)
	end):catch(function(err)
		robuxPromptOpen = false
		pendingRobuxCapsuleId = nil
		warn("[CapsuleController] Prepare capsule robux open request failed:", err)
	end)
end

function CapsuleController:trySpawnCapsuleFromDrop(
	dropPart: BasePart,
	onResult: ((boolean) -> ())?,
	isCancelled: (() -> boolean)?
)
	if not dropPart or not dropPart.Parent or self:GetHeldCapsuleIds()[1] then
		if onResult then
			onResult(false)
		end
		return
	end

	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:RequestCapsuleDrop():andThen(function(success: boolean, payload: any)
		if isCancelled and isCancelled() then
			return
		end

		if not success or type(payload) ~= "table" then
			if onResult then
				onResult(false)
			end
			return
		end

		if isCancelled and isCancelled() then
			return
		end

		local spawnCFrame = CapsuleRenderer.getDropSpawnCFrame(dropPart)
		self:spawnCapsuleVisual(payload.Id, spawnCFrame, payload, dropPart)

		if onResult then
			onResult(true)
		end
	end)
end

function CapsuleController:trySpawnAmbientCapsule()
	if self:GetHeldCapsuleIds()[1] then
		return
	end

	local tycoon = getOwnTycoon()
	if not tycoon then
		return
	end

	local spawnCFrame = getRandomTycoonSpawnCFrame(tycoon)
	if not spawnCFrame then
		return
	end

	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:RequestAmbientCapsule():andThen(function(success: boolean, payload: any)
		if not success or type(payload) ~= "table" then
			return
		end

		self:spawnCapsuleVisual(payload.Id, spawnCFrame, payload)
	end)
end

function CapsuleController:startAmbientLoop()
	if ambientLoopRunning then
		return
	end

	ambientLoopRunning = true
	task.spawn(function()
		while ambientLoopRunning do
			local interval = tonumber(getCapsuleConfig().AmbientSpawnInterval) or 120
			interval *= math.max(EventUtil.getEffectMultiplier("AmbientCapsuleIntervalMultiplier", 1), 0.1)
			task.wait(interval)
			if ambientLoopRunning then
				self:trySpawnAmbientCapsule()
			end
		end
	end)
end

function CapsuleController:KnitStart()
	self:ensureRenderer()

	localPlayer.CharacterAdded:Connect(function()
		task.wait(0.35)
		if openingCapsule or not renderer then
			return
		end

		renderer:reattachHeldCapsules(function(capsuleId: string)
			self:showHeldCapsuleUI(capsuleId)
			task.delay(0.75, function()
				local entry = renderer and renderer:getEntry(capsuleId)
				if entry and entry.pickedUp and not openingCapsule then
					self:showHeldCapsuleUI(capsuleId)
				end
			end)
		end)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(playerOrUserId, productId, wasPurchased)
		if not isLocalProductPromptFinished(playerOrUserId) or productId ~= OPEN_CAPSULE_PRODUCT.ProductId then
			return
		end

		robuxPromptOpen = false
		local capsuleId = pendingRobuxCapsuleId
		pendingRobuxCapsuleId = nil

		if not wasPurchased or not capsuleId then
			openingCapsule = false
			local entry = renderer and capsuleId and renderer:getEntry(capsuleId)
			if entry and entry.pickedUp then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:showOpenCapsuleUI(
					capsuleId,
					entry.previewTiers,
					entry.openPrice,
					entry.highestTier
				)
			end
			return
		end

		openingCapsule = true
		self:waitForRobuxReward(capsuleId, os.clock())
	end)

	local TycoonService = Knit.GetService("TycoonService")
	TycoonService.CapsuleRobuxOpened:Connect(function(capsuleId: string, rewardTier: number?)
		self:onRobuxCapsuleOpened(capsuleId, rewardTier)
	end)
end

return CapsuleController
