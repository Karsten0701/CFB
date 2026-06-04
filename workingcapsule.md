local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)

local CapsuleRenderer = {}
CapsuleRenderer.__index = CapsuleRenderer

local CAPSULE_COLLISION_GROUP = "CapsuleDrops"
local DROP_COLLISION_GROUP = "ManaDrops"
local PLAYER_COLLISION_GROUP = "PlayerCharacters"

pcall(function()
	PhysicsService:RegisterCollisionGroup(CAPSULE_COLLISION_GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, DROP_COLLISION_GROUP, false)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, PLAYER_COLLISION_GROUP, true)
end)

local function getCapsuleConfig()
	return TycoonConfig.Capsules or {}
end

local function getAssetsFolder(): Folder?
	local config = getCapsuleConfig()
	local path = config.AssetsPath or TycoonConfig.AssetsPath
	local current: Instance = ReplicatedStorage
	for _, childName in path do
		local nextChild = current:FindFirstChild(childName)
		if not nextChild then
			return nil
		end
		current = nextChild
	end

	return if current:IsA("Folder") then current else nil
end

local function getAnimeDroppersFolder(): Folder?
	local current: Instance = ReplicatedStorage
	for _, childName in TycoonConfig.AssetsPath do
		local nextChild = current:FindFirstChild(childName)
		if not nextChild then
			return nil
		end
		current = nextChild
	end

	return if current:IsA("Folder") then current else nil
end

local unitTemplateCache: { [number]: Model? } = {}

local function getUnitTemplate(tier: number): Model?
	local cached = unitTemplateCache[tier]
	if cached and cached.Parent then
		return cached
	end

	local tierData = AnimeDroppers.Tiers[tier]
	if not tierData then
		return nil
	end

	local assets = getAnimeDroppersFolder()
	if not assets then
		return nil
	end

	local model = assets:FindFirstChild(tierData.ModelName)
	if model and model:IsA("Model") then
		unitTemplateCache[tier] = model
		return model
	end

	return nil
end

local function getCapsuleTemplate(): Model?
	local config = getCapsuleConfig()
	local assets = getAssetsFolder()
	if not assets then
		return nil
	end

	local modelName = config.CapsuleModelName or "Capsule"
	local template = assets:FindFirstChild(modelName)
	return if template and template:IsA("Model") then template else nil
end

local function findSlot(capsule: Model, slotName: string): Instance?
	local direct = capsule:FindFirstChild(slotName)
	if direct then
		return direct
	end

	local lower = string.lower(slotName)
	for _, child in capsule:GetChildren() do
		if string.lower(child.Name) == lower then
			return child
		end
	end

	local upper = string.upper(string.sub(slotName, 1, 1)) .. string.sub(slotName, 2)
	return capsule:FindFirstChild(upper)
end

local function getSlotAnchorPart(slot: Instance): BasePart?
	if slot:IsA("BasePart") then
		return slot
	end

	if slot:IsA("Model") then
		return slot.PrimaryPart or slot:FindFirstChildWhichIsA("BasePart", true)
	end

	return slot:FindFirstChildWhichIsA("BasePart", true)
end

local function getSlotPivot(slot: Instance): CFrame
	if slot:IsA("Model") then
		return slot:GetPivot()
	end

	if slot:IsA("BasePart") then
		return slot.CFrame
	end

	if slot:IsA("Attachment") then
		return slot.WorldCFrame
	end

	local part = getSlotAnchorPart(slot)
	if part then
		return part.CFrame
	end

	return CFrame.new()
end

local function setCapsulePartPhysics(part: BasePart)
	part.Anchored = false
	part.CanCollide = true
	part.CanTouch = true
	part.CanQuery = true
	part.Massless = false
	part.CollisionGroup = CAPSULE_COLLISION_GROUP
	part:SetAttribute("IsCapsule", true)
	part:SetAttribute("DropValue", nil)
	part:SetAttribute("Value", nil)
end

local function getAssemblyRoot(capsule: Model): BasePart?
	local bottom = capsule:FindFirstChild("Bottom")
	if bottom and bottom:IsA("BasePart") then
		return bottom
	end

	local top = capsule:FindFirstChild("Top")
	if top and top:IsA("BasePart") then
		return top
	end

	return capsule.PrimaryPart or capsule:FindFirstChildWhichIsA("BasePart", true)
end

local function weldPartToRoot(part: BasePart, root: BasePart)
	if part == root then
		return
	end

	for _, child in root:GetChildren() do
		if
			child:IsA("WeldConstraint")
			and child.Name == "CapsuleAssemblyWeld"
			and (child.Part0 == root and child.Part1 == part)
		then
			return
		end
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "CapsuleAssemblyWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = root
end

local function weldCapsuleAssembly(capsule: Model)
	local root = getAssemblyRoot(capsule)
	if not root then
		return nil
	end

	capsule.PrimaryPart = root

	for _, child in capsule:GetChildren() do
		if child:IsA("Folder") then
			continue
		end

		if child:IsA("BasePart") then
			weldPartToRoot(child, root)
		elseif child:IsA("Model") then
			for _, descendant in child:GetDescendants() do
				if descendant:IsA("BasePart") then
					weldPartToRoot(descendant, root)
				end
			end
		end
	end

	return root
end

local function applyCapsulePhysics(model: Model)
	model:SetAttribute("IsCapsule", true)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			setCapsulePartPhysics(descendant)
		end
	end
end

local function setHeldPartPhysics(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CollisionGroup = CAPSULE_COLLISION_GROUP
end

local function setPreviewPartPhysics(part: BasePart)
	-- Anchored = false: capsule moves via welds; anchored previews would stay in world space.
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CollisionGroup = CAPSULE_COLLISION_GROUP
	part:SetAttribute("IsCapsule", true)
end

local function hideSlotPlaceholder(slot: Instance)
	for _, descendant in slot:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	if slot:IsA("BasePart") then
		slot.Transparency = 1
		slot.CanCollide = false
		slot.CanTouch = false
		slot.CanQuery = false
		slot.Massless = true
	end
end

local function stripPreviewDecorations(unitModel: Model)
	for _, child in unitModel:GetChildren() do
		if child:IsA("BillboardGui") or child.Name == "Overhead" then
			child:Destroy()
		end
	end

	for _, descendant in unitModel:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
end

local function weldModelPartsToRoot(
	model: Model,
	assemblyRoot: BasePart,
	targetCFrame: CFrame,
	parentInstance: Instance?
)
	if parentInstance then
		model.Parent = parentInstance
	end

	model:PivotTo(targetCFrame)

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
			or model:FindFirstChildWhichIsA("BasePart", true)
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			setPreviewPartPhysics(descendant)
			weldPartToRoot(descendant, assemblyRoot)
		end
	end
end

local function isLocalCharacterPart(part: BasePart): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil and part:IsDescendantOf(character)
end

function CapsuleRenderer.populatePreviewUnits(capsule: Model, previewTiers: { number })
	local config = getCapsuleConfig()
	local unitScale = tonumber(config.UnitScale) or 0.2
	local slotNames = CapsuleUtil.getSlotNames()
	local assemblyRoot = getAssemblyRoot(capsule)
	if not assemblyRoot then
		warn("[CapsuleRenderer] Cannot populate previews without assembly root")
		return
	end

	local previewFolder = capsule:FindFirstChild("PreviewUnits")
	if not previewFolder then
		previewFolder = Instance.new("Folder")
		previewFolder.Name = "PreviewUnits"
		previewFolder.Parent = capsule
	else
		previewFolder:ClearAllChildren()
	end

	for index, tier in previewTiers do
		local slotName = slotNames[index]
		if not slotName then
			continue
		end

		local slot = findSlot(capsule, slotName)
		local template = getUnitTemplate(tier)
		if not slot or not template then
			if not slot then
				warn("[CapsuleRenderer] Missing slot:", slotName)
			end
			if not template then
				warn("[CapsuleRenderer] Missing unit template for tier:", tier)
			end
			continue
		end

		hideSlotPlaceholder(slot)

		local unitModel = template:Clone()
		unitModel.Name = `Preview_{tier}`
		stripPreviewDecorations(unitModel)
		pcall(function()
			unitModel:ScaleTo(unitScale)
		end)

		local slotParent = if slot:IsA("Model") or slot:IsA("Folder") then slot else previewFolder
		weldModelPartsToRoot(unitModel, assemblyRoot, getSlotPivot(slot), slotParent)
	end
end

function CapsuleRenderer.new(parentFolder: Instance)
	local self = setmetatable({}, CapsuleRenderer)
	self.parentFolder = parentFolder
	self.entries = {}
	return self
end

function CapsuleRenderer:getFolder(): Folder
	if self.parentFolder and self.parentFolder.Parent then
		return self.parentFolder
	end

	local folder = Instance.new("Folder")
	folder.Name = "Capsules"
	folder.Parent = workspace
	self.parentFolder = folder
	return folder
end

function CapsuleRenderer:getEntry(capsuleId: string): any?
	return self.entries[capsuleId]
end

function CapsuleRenderer:getHeldCapsuleIds(): { string }
	local held = {}
	for capsuleId, entry in self.entries do
		if entry and entry.pickedUp then
			table.insert(held, capsuleId)
		end
	end
	return held
end

function CapsuleRenderer:destroyCapsule(capsuleId: string)
	local entry = self.entries[capsuleId]
	if not entry then
		return
	end

	if entry.touchConnection then
		entry.touchConnection:Disconnect()
	end

	if entry.holdWeld then
		entry.holdWeld:Destroy()
	end

	if entry.lifetimeThread then
		task.cancel(entry.lifetimeThread)
	end

	if entry.model and entry.model.Parent then
		entry.model:Destroy()
	end

	self.entries[capsuleId] = nil
end

function CapsuleRenderer:releaseHold(capsuleId: string)
	local entry = self.entries[capsuleId]
	if not entry or not entry.holdWeld then
		return
	end

	entry.holdWeld:Destroy()
	entry.holdWeld = nil
end

function CapsuleRenderer:pickupCapsule(capsuleId: string, onPickedUp: ((string) -> ())?)
	local entry = self.entries[capsuleId]
	if not entry or entry.pickedUp or not entry.model or not entry.model.Parent then
		return
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local model = entry.model
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		return
	end

	entry.pickedUp = true

	if entry.lifetimeThread then
		task.cancel(entry.lifetimeThread)
		entry.lifetimeThread = nil
	end

	if entry.touchConnection then
		entry.touchConnection:Disconnect()
		entry.touchConnection = nil
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			setHeldPartPhysics(descendant)
		end
	end

	primary.CanQuery = true

	local holdOffset = CFrame.new(0, 1.25, -2.75)
	primary.CFrame = root.CFrame * holdOffset

	local holdWeld = Instance.new("WeldConstraint")
	holdWeld.Name = "CapsuleHoldWeld"
	holdWeld.Part0 = root
	holdWeld.Part1 = primary
	holdWeld.Parent = primary
	entry.holdWeld = holdWeld

	if onPickedUp then
		onPickedUp(capsuleId)
	end
end

function CapsuleRenderer:spawnCapsule(
	capsuleId: string,
	spawnCFrame: CFrame,
	previewTiers: { number },
	openPrice: number,
	highestTier: number,
	onPickup: ((string) -> ())?,
	onExpired: ((string) -> ())?
): Model?
	self:destroyCapsule(capsuleId)

	local template = getCapsuleTemplate()
	if not template then
		warn("[CapsuleRenderer] Capsule template missing at ReplicatedStorage.Assets.Drops.Capsule")
		return nil
	end

	local capsule = template:Clone()
	capsule.Name = `Capsule_{capsuleId}`
	capsule:SetAttribute("CapsuleId", capsuleId)
	capsule:SetAttribute("OpenPrice", openPrice)
	capsule:SetAttribute("IsCapsule", true)

	applyCapsulePhysics(capsule)
	local primary = weldCapsuleAssembly(capsule)
	if not primary then
		capsule:Destroy()
		warn("[CapsuleRenderer] Capsule has no assembly root part")
		return nil
	end

	for _, slotName in CapsuleUtil.getSlotNames() do
		local slot = findSlot(capsule, slotName)
		if slot then
			hideSlotPlaceholder(slot)
		end
	end

	capsule:PivotTo(spawnCFrame)
	capsule.Parent = self:getFolder()
	if primary then
		primary.AssemblyLinearVelocity = Vector3.new(math.random(-2, 2), 5, math.random(-2, 2))
	end

	CapsuleRenderer.populatePreviewUnits(capsule, previewTiers)

	local entry = {
		model = capsule,
		previewTiers = previewTiers,
		openPrice = openPrice,
		highestTier = highestTier,
		pickedUp = false,
		previewsPopulated = true,
		touchConnection = nil,
		holdWeld = nil,
		lifetimeThread = nil,
	}
	self.entries[capsuleId] = entry

	if primary then
		entry.touchConnection = primary.Touched:Connect(function(hit: BasePart)
			local currentEntry = self.entries[capsuleId]
			if not currentEntry or currentEntry.pickedUp then
				return
			end

			if not hit or not hit:IsA("BasePart") then
				return
			end

			if hit:GetAttribute("IsCapsule") == true then
				return
			end

			if tonumber(hit:GetAttribute("DropValue")) ~= nil or tonumber(hit:GetAttribute("Value")) ~= nil then
				return
			end

			if not isLocalCharacterPart(hit) then
				return
			end

			self:pickupCapsule(capsuleId, onPickup)
		end)
	end

	local lifetime = tonumber(getCapsuleConfig().CapsuleLifetime) or 180
	entry.lifetimeThread = task.delay(lifetime, function()
		local currentEntry = self.entries[capsuleId]
		if currentEntry and not currentEntry.pickedUp then
			if onExpired then
				onExpired(capsuleId)
			end
			self:destroyCapsule(capsuleId)
		end
	end)

	return capsule
end

function CapsuleRenderer:destroy()
	for capsuleId in self.entries do
		self:destroyCapsule(capsuleId)
	end
end

return CapsuleRenderer
//
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)

local OPEN_CAPSULE_PRODUCT = Monetization.DeveloperProducts.OpenCapsule

local CapsuleFeature = {}

function CapsuleFeature.Install(MainGuiController)
	function MainGuiController:getOpenCapsuleFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local frame = mainGui:FindFirstChild("OpenCapsuleFrame", true)
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:hideOpenCapsuleUI()
		local frame = self:getOpenCapsuleFrame()
		if frame then
			frame.Visible = false
		end
		self.activeCapsuleId = nil
	end

	function MainGuiController:showOpenCapsuleUI(
		capsuleId: string,
		_previewTiers: { number },
		openPrice: number,
		highestTier: number
	)
		local frame = self:getOpenCapsuleFrame()
		if not frame then
			warn("[MainGuiController] OpenCapsuleFrame not found")
			return
		end

		self.activeCapsuleId = capsuleId
		local displayEntries = CapsuleUtil.getPreviewDisplayEntries(highestTier)

		local unitsFrame = frame:FindFirstChild("Units", true)
		if unitsFrame then
			for index = 1, 3 do
				local label = unitsFrame:FindFirstChild(`Unit{index}`)
				local entry = displayEntries[index]
				if label and label:IsA("TextLabel") and entry then
					label.Text = `{entry.DisplayName} [{CapsuleUtil.formatChancePercent(entry.Chance)}]`
					label.Visible = true
				elseif label and label:IsA("TextLabel") then
					label.Visible = false
				end
			end
		end

		local openButton = frame:FindFirstChild("Open", true)
		if openButton then
			local priceLabel = openButton:FindFirstChild("Price", true)
			if priceLabel and priceLabel:IsA("TextLabel") then
				priceLabel.Text = Pricing.formatYen(openPrice)
			end
		end

		local robuxButton = frame:FindFirstChild("OpenRobux", true)
		if robuxButton then
			local priceLabel = robuxButton:FindFirstChild("Price", true)
			if priceLabel and priceLabel:IsA("TextLabel") then
				priceLabel.Text = `{OPEN_CAPSULE_PRODUCT.Price or 49} Robux`
			end
		end

		frame.Visible = true
	end

	function MainGuiController:setupOpenCapsuleFrame()
		local frame = self:getOpenCapsuleFrame()
		if not frame then
			return
		end

		frame.Visible = false
		self.activeCapsuleId = nil

		local function bindOpenButton(buttonName: string, opener: (string) -> ())
			local button = frame:FindFirstChild(buttonName, true)
			if not button or not button:IsA("GuiButton") then
				return
			end

			button.Activated:Connect(function()
				local capsuleId = self.activeCapsuleId
				if type(capsuleId) ~= "string" or capsuleId == "" then
					return
				end

				opener(capsuleId)
			end)
		end

		local Knit = require(ReplicatedStorage.Packages.knit)
		bindOpenButton("Open", function(capsuleId: string)
			Knit.GetController("CapsuleController"):openWithYen(capsuleId)
		end)
		bindOpenButton("OpenRobux", function(capsuleId: string)
			Knit.GetController("CapsuleController"):openWithRobux(capsuleId)
		end)
	end
end

return CapsuleFeature
//
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
		local offset = Vector3.new(math.random(-8, 8), 2.5, math.random(-8, 8))
		return spawnPart.CFrame + offset
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

function CapsuleController:spawnCapsuleVisual(capsuleId: string, spawnCFrame: CFrame, payload: any)
	local capsuleRenderer = self:ensureRenderer()
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
		end
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

function CapsuleController:dismissCapsule(capsuleId: string)
	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:DismissCapsule(capsuleId)

	if renderer then
		renderer:destroyCapsule(capsuleId)
	end

	local MainGuiController = Knit.GetController("MainGuiController")
	MainGuiController:hideOpenCapsuleUI()
end

function CapsuleController:finishOpen(capsuleId: string, rewardTier: number?)
	if renderer then
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
	if not entry or not entry.model then
		if onComplete then
			onComplete()
		end
		return
	end

	if renderer then
		renderer:releaseHold(capsuleId)
	end

	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and entry.model.PrimaryPart then
		entry.model:PivotTo(root.CFrame * CFrame.new(0, 0.5, -5))
	end

	task.spawn(function()
		CapsuleOpenAnimation.play(entry.model, rewardTier, onComplete)
	end)
end

function CapsuleController:openWithYen(capsuleId: string)
	if openingCapsule then
		return
	end

	openingCapsule = true
	local MainGuiController = Knit.GetController("MainGuiController")
	MainGuiController:hideOpenCapsuleUI()

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
				MainGuiController:showOpenCapsuleUI(
					capsuleId,
					entry.previewTiers,
					entry.openPrice,
					entry.highestTier
				)
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
		local MainGuiController = Knit.GetController("MainGuiController")
		MainGuiController:hideOpenCapsuleUI()

		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, OPEN_CAPSULE_PRODUCT.ProductId)
		end)

		if not ok then
			robuxPromptOpen = false
			pendingRobuxCapsuleId = nil
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
		end
	end)
end

function CapsuleController:trySpawnCapsuleFromDrop(dropPart: BasePart)
	if not dropPart or not dropPart.Parent then
		return
	end

	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:RequestCapsuleDrop():andThen(function(success: boolean, payload: any)
		if not success or type(payload) ~= "table" then
			return
		end

		local spawnCFrame = dropPart.CFrame + Vector3.new(0, 2.5, 0)
		self:spawnCapsuleVisual(payload.Id, spawnCFrame, payload)
	end)
end

function CapsuleController:trySpawnAmbientCapsule()
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
		if not wasPurchased then
			pendingRobuxCapsuleId = nil
			openingCapsule = false
			return
		end

		local capsuleId = pendingRobuxCapsuleId
		pendingRobuxCapsuleId = nil
		if not capsuleId then
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
//
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)

local CapsuleOpenAnimation = {}

local function getConfig()
	return TycoonConfig.Capsules or {}
end

local function getAnimeAssetsFolder(): Folder?
	local current: Instance = ReplicatedStorage
	for _, childName in TycoonConfig.AssetsPath do
		local nextChild = current:FindFirstChild(childName)
		if not nextChild then
			return nil
		end
		current = nextChild
	end

	return if current:IsA("Folder") then current else nil
end

local function getUnitTemplate(tier: number): Model?
	local tierData = AnimeDroppers.Tiers[tier]
	if not tierData then
		return nil
	end

	local assets = getAnimeAssetsFolder()
	if not assets then
		return nil
	end

	local model = assets:FindFirstChild(tierData.ModelName)
	return if model and model:IsA("Model") then model else nil
end

local function anchorParts(model: Instance, anchored: boolean)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
end

local function tweenCameraTo(targetCFrame: CFrame, duration: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local tween = TweenService:Create(camera, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = targetCFrame,
	})
	tween:Play()
	tween.Completed:Wait()
end

function CapsuleOpenAnimation.play(capsuleModel: Model?, rewardTier: number, onComplete: (() -> ())?)
	if not capsuleModel or not capsuleModel.Parent then
		if onComplete then
			onComplete()
		end
		return
	end

	local config = getConfig()
	local revealStartScale = tonumber(config.UnitScale) or 0.2
	local revealEndScale = tonumber(config.RevealScale) or 0.5

	local assemblyRoot = capsuleModel:FindFirstChild("Bottom")
	if not assemblyRoot or not assemblyRoot:IsA("BasePart") then
		assemblyRoot = capsuleModel.PrimaryPart or capsuleModel:FindFirstChildWhichIsA("BasePart", true)
	end

	if not assemblyRoot then
		if onComplete then
			onComplete()
		end
		return
	end

	local previewFolder = capsuleModel:FindFirstChild("PreviewUnits")
	if previewFolder then
		previewFolder:Destroy()
	end

	for _, descendant in capsuleModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local camera = Workspace.CurrentCamera
	local previousCameraType = if camera then camera.CameraType else Enum.CameraType.Custom
	local previousCameraSubject = if camera then camera.CameraSubject else nil

	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		local focus = assemblyRoot.Position + Vector3.new(0, 1.25, 0)
		local cameraPosition = focus + Vector3.new(0, 2.5, 7.5)
		tweenCameraTo(CFrame.lookAt(cameraPosition, focus), 0.45)
	end

	local shakeStart = os.clock()
	local shakeDuration = 1.6
	local shakeConnection: RBXScriptConnection? = nil
	shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - shakeStart
		if elapsed >= shakeDuration then
			if shakeConnection then
				shakeConnection:Disconnect()
			end
			return
		end

		local intensity = 1 - (elapsed / shakeDuration)
		assemblyRoot.CFrame = assemblyRoot.CFrame
			* CFrame.Angles(
				math.rad(math.random(-4, 4) * intensity),
				math.rad(math.random(-4, 4) * intensity),
				math.rad(math.random(-4, 4) * intensity)
			)
	end)

	task.wait(shakeDuration)

	local top = capsuleModel:FindFirstChild("Top")
	if top and top:IsA("BasePart") then
		for _, child in assemblyRoot:GetChildren() do
			if child:IsA("WeldConstraint") and child.Part1 == top then
				child:Destroy()
			end
		end

		local liftTween = TweenService:Create(
			top,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = top.CFrame * CFrame.new(0, 2.75, 0) }
		)
		liftTween:Play()
		liftTween.Completed:Wait()
	end

	local template = getUnitTemplate(rewardTier)
	local revealModel: Model? = nil
	if template then
		revealModel = template:Clone()
		revealModel.Name = "CapsuleReveal"
		anchorParts(revealModel, true)
		revealModel:ScaleTo(revealStartScale)
		revealModel:PivotTo(assemblyRoot.CFrame * CFrame.new(0, 1.1, 0))
		revealModel.Parent = capsuleModel

		local steps = 10
		for step = 1, steps do
			local alpha = step / steps
			local scale = revealStartScale + (revealEndScale - revealStartScale) * alpha
			pcall(function()
				revealModel:ScaleTo(scale)
			end)
			task.wait(0.05)
		end
	end

	task.wait(0.35)

	if camera then
		camera.CameraType = previousCameraType
		if previousCameraSubject then
			camera.CameraSubject = previousCameraSubject
		end
	end

	if onComplete then
		onComplete()
	end
end

return CapsuleOpenAnimation
//
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)

local CapsuleUtil = {}

local function getCapsuleConfig()
	return TycoonConfig.Capsules or {}
end

function CapsuleUtil.getHighestUnitTier(units: { { Tier: number } }?): number
	local highest = 1
	if type(units) ~= "table" then
		return highest
	end

	for _, unit in units do
		if type(unit) == "table" then
			local tier = math.clamp(math.floor(tonumber(unit.Tier) or 1), 1, AnimeDroppers.MaxTier)
			if tier > highest then
				highest = tier
			end
		end
	end

	return highest
end

function CapsuleUtil.getPreviewTiers(highestTier: number): { number }
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local config = getCapsuleConfig()
	local weights = config.TierWeights
	if type(weights) ~= "table" or #weights <= 0 then
		return {
			math.max(highestTier - 1, 1),
			highestTier,
			math.min(highestTier + 1, AnimeDroppers.MaxTier),
		}
	end

	local previewTiers = table.create(#weights)
	for index, entry in weights do
		local offset = if type(entry) == "table" then math.floor(tonumber(entry.Offset) or 0) else 0
		previewTiers[index] = math.clamp(highestTier + offset, 1, AnimeDroppers.MaxTier)
	end

	return previewTiers
end

function CapsuleUtil.rollRewardTier(highestTier: number): number?
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local config = getCapsuleConfig()
	local weights = config.TierWeights
	if type(weights) ~= "table" or #weights <= 0 then
		return highestTier
	end

	local roll = math.random()
	local cumulative = 0
	for _, entry in weights do
		if type(entry) ~= "table" then
			continue
		end

		local chance = tonumber(entry.Chance) or 0
		cumulative += chance
		if roll <= cumulative then
			local offset = math.floor(tonumber(entry.Offset) or 0)
			return math.clamp(highestTier + offset, 1, AnimeDroppers.MaxTier)
		end
	end

	local lastEntry = weights[#weights]
	if type(lastEntry) == "table" then
		local offset = math.floor(tonumber(lastEntry.Offset) or 0)
		return math.clamp(highestTier + offset, 1, AnimeDroppers.MaxTier)
	end

	return highestTier
end

function CapsuleUtil.getOpenPrice(highestTier: number): number
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local config = getCapsuleConfig()
	local tierData = AnimeDroppers.Tiers[highestTier]
	local dropValue = if tierData then tonumber(tierData.DropValue) or 1 else 1
	local multiplier = tonumber(config.OpenPriceMultiplier) or 50
	local minPrice = tonumber(config.MinOpenPrice) or 100
	return math.max(math.floor(dropValue * multiplier), minPrice)
end

function CapsuleUtil.getPreviewDisplayEntries(highestTier: number): { { Tier: number, DisplayName: string, Chance: number } }
	highestTier = math.clamp(math.floor(highestTier or 1), 1, AnimeDroppers.MaxTier)
	local previewTiers = CapsuleUtil.getPreviewTiers(highestTier)
	local config = getCapsuleConfig()
	local weights = config.TierWeights or {}
	local entries = table.create(#previewTiers)

	for index, tier in previewTiers do
		local tierData = AnimeDroppers.Tiers[tier]
		local weightEntry = weights[index]
		local chance = if type(weightEntry) == "table" then tonumber(weightEntry.Chance) or 0 else 0
		table.insert(entries, {
			Tier = tier,
			DisplayName = if tierData then tierData.DisplayName else `Tier {tier}`,
			Chance = chance,
		})
	end

	return entries
end

function CapsuleUtil.formatChancePercent(chance: number): string
	chance = math.clamp(chance or 0, 0, 1)
	return string.format("%.0f%%", chance * 100)
end

function CapsuleUtil.getSlotNames(): { string }
	local config = getCapsuleConfig()
	if type(config.SlotNames) == "table" and #config.SlotNames > 0 then
		return config.SlotNames
	end

	return { "unit1", "unit2", "unit3" }
end

return CapsuleUtil
