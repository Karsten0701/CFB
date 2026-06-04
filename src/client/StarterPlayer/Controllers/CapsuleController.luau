local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleOpenAnimation = require(script.Parent.Parent.Parent.Features.Capsules.CapsuleOpenAnimation)
local CapsuleRenderer = require(script.Parent.Parent.Parent.Features.Capsules.CapsuleRenderer)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
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
local OPEN_CAPSULE_PRODUCT = Monetization.DeveloperProducts.OpenCapsule

local function getCapsuleConfig()
	return TycoonConfig.Capsules or {}
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

function CapsuleController:spawnCapsuleVisual(capsuleId: string, spawnCFrame: CFrame, payload: any, dropPart: BasePart?)
	local capsuleRenderer = self:ensureRenderer()
	local spawnOptions = nil

	if dropPart then
		local TycoonController = Knit.GetController("TycoonController")
		local tycoonRenderer = TycoonController:GetOwnRenderer()
		if tycoonRenderer then
			spawnOptions = {
				parent = tycoonRenderer:getDropsFolder(),
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
			return
		end

		self:playOpenAnimation(capsuleId, rewardTier or 1, function()
			openingCapsule = false
			self:finishOpen(capsuleId, rewardTier)
		end)
	end)
end

function CapsuleController:openWithRobux(capsuleId: string)
	if robuxPromptOpen or openingCapsule then
		return
	end

	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:PrepareCapsuleRobuxOpen(capsuleId):andThen(function(prepared: boolean)
		if not prepared then
			return
		end

		pendingRobuxCapsuleId = capsuleId
		robuxPromptOpen = true

		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, OPEN_CAPSULE_PRODUCT.ProductId)
		end)

		if not ok then
			robuxPromptOpen = false
			pendingRobuxCapsuleId = nil
			warn("[CapsuleController] Capsule robux prompt failed:", err)
		end
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
			task.wait(interval)
			if ambientLoopRunning then
				self:trySpawnAmbientCapsule()
			end
		end
	end)
end

function CapsuleController:KnitStart()
	self:ensureRenderer()
	self:startAmbientLoop()

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(player, productId, wasPurchased)
		if player ~= localPlayer or productId ~= OPEN_CAPSULE_PRODUCT.ProductId then
			return
		end

		robuxPromptOpen = false
		local capsuleId = pendingRobuxCapsuleId
		pendingRobuxCapsuleId = nil

		if not wasPurchased or not capsuleId then
			openingCapsule = false
			return
		end

		task.delay(0.2, function()
			local TycoonService = Knit.GetService("TycoonService")
			TycoonService:GetLastCapsuleReward():andThen(function(rewardTier: number?)
				openingCapsule = true
				self:playOpenAnimation(capsuleId, rewardTier or 1, function()
					openingCapsule = false
					self:finishOpen(capsuleId, rewardTier)
				end)
			end)
		end)
	end)
end

return CapsuleController
