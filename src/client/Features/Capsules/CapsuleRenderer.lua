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
local DROP_WALL_COLLISION_GROUP = "DropWalls"
local PLAYER_COLLISION_GROUP = "PlayerCharacters"

pcall(function()
	PhysicsService:RegisterCollisionGroup(CAPSULE_COLLISION_GROUP)
end)
pcall(function()
	PhysicsService:RegisterCollisionGroup(DROP_WALL_COLLISION_GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, DROP_COLLISION_GROUP, false)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, false)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
end)

local function getCapsuleConfig()
	return TycoonConfig.Capsules or {}
end

local function getAssetsFolder(): Folder?
	local config = getCapsuleConfig()
	local path = config.AssetsPath or { "Assets", "Drops" }
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

	local assets = getAnimeDroppersFolder()
	if not assets then
		return nil
	end

	tier = math.clamp(math.floor(tier), 1, AnimeDroppers.MaxTier)

	for fallbackTier = tier, 1, -1 do
		local tierData = AnimeDroppers.Tiers[fallbackTier]
		if tierData then
			local model = assets:FindFirstChild(tierData.ModelName)
			if model and model:IsA("Model") then
				unitTemplateCache[tier] = model
				return model
			end
		end
	end

	for fallbackTier = tier + 1, AnimeDroppers.MaxTier do
		local tierData = AnimeDroppers.Tiers[fallbackTier]
		if tierData then
			local model = assets:FindFirstChild(tierData.ModelName)
			if model and model:IsA("Model") then
				unitTemplateCache[tier] = model
				return model
			end
		end
	end

	return nil
end

local function isPreviewModel(instance: Instance): boolean
	return instance:IsA("Model") and string.match(instance.Name, "^Preview_") ~= nil
end

local function getCapsuleTemplate(): Instance?
	local config = getCapsuleConfig()
	local assets = getAssetsFolder()
	if not assets then
		return nil
	end

	local modelName = config.CapsuleModelName or "Capsule"
	local template = assets:FindFirstChild(modelName)
	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		return template
	end

	return nil
end

local function getContentModel(capsule: Instance): Model?
	if capsule:IsA("Model") then
		local inner = capsule:FindFirstChild("Capsule")
		if inner and inner:IsA("Model") and inner ~= capsule then
			return inner
		end
	end

	if capsule:IsA("BasePart") then
		local inner = capsule:FindFirstChild("Capsule")
		if inner and inner:IsA("Model") then
			return inner
		end
	end

	return nil
end

local function resolveAssemblyRoot(capsule: Instance): BasePart?
	local config = getCapsuleConfig()
	local preferredName = config.AssemblyRootName or "Capsule"

	if capsule:IsA("BasePart") then
		if capsule.Name == preferredName then
			return capsule
		end
		return capsule
	end

	local content = getContentModel(capsule)
	if content then
		local contentPart = content:FindFirstChild(preferredName)
		if contentPart and contentPart:IsA("BasePart") then
			return contentPart
		end
	end

	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == preferredName then
			return descendant
		end
	end

	if capsule:IsA("Model") then
		local bottom = capsule:FindFirstChild("Bottom", true)
		if bottom and bottom:IsA("BasePart") then
			return bottom
		end

		local top = capsule:FindFirstChild("Top", true)
		if top and top:IsA("BasePart") then
			return top
		end

		if capsule.PrimaryPart and capsule.PrimaryPart:IsA("BasePart") then
			return capsule.PrimaryPart
		end

		return capsule:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function findUnitSlot(capsule: Instance, slotName: string): Instance?
	local content = getContentModel(capsule)
	if not content then
		return nil
	end

	local slot = content:FindFirstChild(slotName)
	if slot then
		return slot
	end

	local lower = string.lower(slotName)
	for _, child in content:GetChildren() do
		if string.lower(child.Name) == lower then
			return child
		end
	end

	local upper = string.upper(string.sub(slotName, 1, 1)) .. string.sub(slotName, 2)
	return content:FindFirstChild(upper)
end

local function getSlotPivot(slot: Instance): CFrame
	local previewAttachment = slot:FindFirstChild("PreviewAttachment", true)
	if previewAttachment and previewAttachment:IsA("Attachment") then
		return previewAttachment.WorldCFrame
	end

	if slot:IsA("Model") then
		local ok, boundingCFrame = pcall(function()
			return slot:GetBoundingBox()
		end)
		if ok and typeof(boundingCFrame) == "CFrame" then
			return boundingCFrame
		end
		return slot:GetPivot()
	end

	if slot:IsA("BasePart") then
		return slot.CFrame
	end

	if slot:IsA("Attachment") then
		return slot.WorldCFrame
	end

	if slot:IsA("Folder") then
		local part = slot:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part.CFrame
		end
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
	part:SetAttribute("IsPossibleDrop", true)
	part:SetAttribute("DropValue", nil)
	part:SetAttribute("Value", nil)
end

local function setWeldedPartPhysics(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CollisionGroup = CAPSULE_COLLISION_GROUP
	part:SetAttribute("IsCapsule", true)
	part:SetAttribute("DropValue", nil)
	part:SetAttribute("Value", nil)
end

local function setHeldPartPhysics(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CollisionGroup = PLAYER_COLLISION_GROUP
end

local function setPreviewPartPhysics(part: BasePart)
	setWeldedPartPhysics(part)
end

local function clearTemplateWelds(capsule: Instance)
	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") then
			descendant:Destroy()
		end
	end
end

local function getAssemblyWeldFolder(assemblyRoot: BasePart): Folder
	local folder = assemblyRoot:FindFirstChild("CapsuleWelds")
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = "CapsuleWelds"
	folder.Parent = assemblyRoot
	return folder
end

local function isValidWeldPart(part: BasePart?): boolean
	return part ~= nil and part:IsA("BasePart") and part.Parent ~= nil
end

local function purgeBrokenWelds(capsule: Instance)
	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") then
			if descendant:IsA("WeldConstraint") then
				if not isValidWeldPart(descendant.Part0) or not isValidWeldPart(descendant.Part1) then
					descendant:Destroy()
				end
			elseif descendant:IsA("Weld") then
				if not isValidWeldPart(descendant.Part0) or not isValidWeldPart(descendant.Part1) then
					descendant:Destroy()
				end
			end
		end
	end
end

local function clearRuntimeWelds(assemblyRoot: BasePart, capsule: Instance)
	local weldFolder = assemblyRoot:FindFirstChild("CapsuleWelds")
	if weldFolder then
		weldFolder:ClearAllChildren()
	end

	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("WeldConstraint") and descendant.Name == "CapsuleAssemblyWeld" then
			descendant:Destroy()
		end
	end
end

local function weldPartToRoot(part: BasePart, assemblyRoot: BasePart, weldName: string?)
	if part == assemblyRoot then
		return
	end

	if not isValidWeldPart(part) or not isValidWeldPart(assemblyRoot) then
		return
	end

	local weldFolder = getAssemblyWeldFolder(assemblyRoot)
	for _, child in weldFolder:GetChildren() do
		if child:IsA("WeldConstraint") and child.Part0 == assemblyRoot and child.Part1 == part then
			return
		end
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = weldName or "CapsuleAssemblyWeld"
	weld.Part0 = assemblyRoot
	weld.Part1 = part
	weld.Parent = weldFolder
end

local function getPreviewWeldFolder(unitModel: Model): Folder
	local folder = unitModel:FindFirstChild("PreviewWelds")
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = "PreviewWelds"
	folder.Parent = unitModel
	return folder
end

local function clearPreviewWelds(unitModel: Model)
	local folder = unitModel:FindFirstChild("PreviewWelds")
	if folder then
		folder:ClearAllChildren()
	end
end

local function weldPreviewPartsToAnchor(unitModel: Model, anchor: BasePart)
	clearPreviewWelds(unitModel)

	local weldFolder = getPreviewWeldFolder(unitModel)
	for _, descendant in unitModel:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= anchor and isValidWeldPart(descendant) then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "PreviewRigWeld"
			weld.Part0 = anchor
			weld.Part1 = descendant
			weld.Parent = weldFolder
		end
	end
end

local function weldCapsuleAssembly(capsule: Instance, assemblyRoot: BasePart)
	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant == assemblyRoot then
				setCapsulePartPhysics(descendant)
			else
				setWeldedPartPhysics(descendant)
				weldPartToRoot(descendant, assemblyRoot)
			end
		elseif descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		end
	end
end

local function placeAssemblyAt(capsule: Instance, assemblyRoot: BasePart, spawnCFrame: CFrame)
	if capsule:IsA("Model") then
		local delta = spawnCFrame * assemblyRoot.CFrame:Inverse()
		capsule:PivotTo(delta * capsule:GetPivot())
	elseif capsule:IsA("BasePart") then
		capsule.CFrame = spawnCFrame
	end

	assemblyRoot.CFrame = spawnCFrame
end

local function ensurePreviewVisible(unitModel: Model)
	for _, descendant in unitModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Transparency >= 1 then
				descendant.Transparency = 0
			end
			descendant.LocalTransparencyModifier = 0
		end
	end
end

local function hideSlotPlaceholder(slot: Instance)
	for _, descendant in slot:GetDescendants() do
		if descendant:IsA("Model") and isPreviewModel(descendant) then
			continue
		end

		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	if slot:IsA("BasePart") then
		slot.Anchored = true
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

local function getPreviewAnchor(unitModel: Model): BasePart?
	if unitModel.PrimaryPart and unitModel.PrimaryPart:IsA("BasePart") then
		return unitModel.PrimaryPart
	end

	local humanoidRoot = unitModel:FindFirstChild("HumanoidRootPart")
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		unitModel.PrimaryPart = humanoidRoot
		return humanoidRoot
	end

	local fallbackPart = unitModel:FindFirstChildWhichIsA("BasePart", true)
	if fallbackPart then
		unitModel.PrimaryPart = fallbackPart
	end

	return fallbackPart
end

local function attachPreviewToSlot(unitModel: Model, assemblyRoot: BasePart, slot: Instance)
	local slotCFrame = getSlotPivot(slot)

	unitModel.Parent = slot
	unitModel:PivotTo(slotCFrame)

	local anchor = getPreviewAnchor(unitModel)
	if not anchor then
		warn("[CapsuleRenderer] Preview unit has no BasePart:", unitModel.Name)
		return
	end

	ensurePreviewVisible(unitModel)

	for _, descendant in unitModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			setPreviewPartPhysics(descendant)
		end
	end

	weldPreviewPartsToAnchor(unitModel, anchor)
end

local function isLocalCharacterPart(part: BasePart): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil and part:IsDescendantOf(character)
end

function CapsuleRenderer.getDropSpawnCFrame(dropPart: BasePart): CFrame
	local config = getCapsuleConfig()
	local yOffset = tonumber(config.SpawnYOffset) or 1.5

	local dropSpot = dropPart:FindFirstChild("DropSpot")
	if not dropSpot and dropPart.Parent then
		dropSpot = dropPart.Parent:FindFirstChild("DropSpot")
	end

	if dropSpot then
		if dropSpot:IsA("BasePart") then
			return dropSpot.CFrame
		end
		if dropSpot:IsA("Attachment") then
			return dropPart.CFrame * dropSpot.CFrame
		end
	end

	return dropPart.CFrame + Vector3.new(0, yOffset, 0)
end

local function clearExistingPreviews(capsule: Instance, assemblyRoot: BasePart)
	clearRuntimeWelds(assemblyRoot, capsule)

	local content = getContentModel(capsule)
	if content then
		local legacyFolder = content:FindFirstChild("PreviewUnits")
		if legacyFolder then
			legacyFolder:Destroy()
		end
	end

	for _, slotName in CapsuleUtil.getSlotNames() do
		local slot = findUnitSlot(capsule, slotName)
		if not slot then
			continue
		end

		for _, child in slot:GetChildren() do
			if isPreviewModel(child) then
				clearPreviewWelds(child)
				child:Destroy()
			end
		end

		hideSlotPlaceholder(slot)
	end

	purgeBrokenWelds(capsule)
end

function CapsuleRenderer.populatePreviewUnits(capsule: Instance, assemblyRoot: BasePart, previewTiers: { number })
	local config = getCapsuleConfig()
	local unitScale = tonumber(config.UnitScale) or 0.2

	if not getContentModel(capsule) then
		warn("[CapsuleRenderer] Missing nested Capsule model")
		return
	end

	clearExistingPreviews(capsule, assemblyRoot)

	for index = 1, #previewTiers do
		local tier = previewTiers[index]
		local slotName = CapsuleUtil.getSlotNames()[index]
		if not slotName or type(tier) ~= "number" then
			continue
		end

		local slot = findUnitSlot(capsule, slotName)
		local template = getUnitTemplate(tier)
		if not slot then
			warn("[CapsuleRenderer] Missing slot:", slotName)
			continue
		end
		if not template then
			warn("[CapsuleRenderer] Missing unit template for tier:", tier)
			continue
		end

		if not slot:IsA("Model") and not slot:IsA("Folder") then
			warn("[CapsuleRenderer] Slot must be a Model or Folder:", slotName, slot.ClassName)
			continue
		end

		hideSlotPlaceholder(slot)

		local unitModel = template:Clone()
		unitModel.Name = `Preview_{tier}`
		stripPreviewDecorations(unitModel)

		local scaleOk = pcall(function()
			unitModel:ScaleTo(unitScale)
		end)
		if not scaleOk then
			warn("[CapsuleRenderer] ScaleTo failed for preview tier:", tier)
		end

		attachPreviewToSlot(unitModel, assemblyRoot, slot)
	end

	weldCapsuleAssembly(capsule, assemblyRoot)
	purgeBrokenWelds(capsule)
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
	folder.Name = "LocalCapsules"
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

function CapsuleRenderer:hasHeldCapsule(): boolean
	return #self:getHeldCapsuleIds() > 0
end

function CapsuleRenderer:releaseHold(capsuleId: string)
	local entry = self.entries[capsuleId]
	if not entry or not entry.holdWeld then
		return
	end

	entry.holdWeld:Destroy()
	entry.holdWeld = nil
end

local function unregisterPossibleDrop(entry: any)
	if entry and entry.unregisterPossibleDrop and entry.root then
		entry.unregisterPossibleDrop(entry.root)
		entry.unregisterPossibleDrop = nil
	end
end

function CapsuleRenderer:destroyCapsule(capsuleId: string)
	local entry = self.entries[capsuleId]
	if not entry then
		return
	end

	unregisterPossibleDrop(entry)
	self:releaseHold(capsuleId)

	if entry.touchConnection then
		entry.touchConnection:Disconnect()
	end

	if entry.lifetimeThread then
		task.cancel(entry.lifetimeThread)
	end

	if entry.instance and entry.instance.Parent then
		entry.instance:Destroy()
	end

	self.entries[capsuleId] = nil
end

function CapsuleRenderer:pickupCapsule(capsuleId: string, onPickedUp: ((string) -> ())?)
	if self:hasHeldCapsule() then
		return
	end

	local entry = self.entries[capsuleId]
	if not entry or entry.pickedUp or not entry.instance or not entry.instance.Parent then
		return
	end

	local character = Players.LocalPlayer.Character
	local humanoidRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot or not humanoidRoot:IsA("BasePart") then
		return
	end

	local instance = entry.instance
	local assemblyRoot = entry.root
	entry.pickedUp = true
	unregisterPossibleDrop(entry)

	if entry.lifetimeThread then
		task.cancel(entry.lifetimeThread)
		entry.lifetimeThread = nil
	end

	if entry.touchConnection then
		entry.touchConnection:Disconnect()
		entry.touchConnection = nil
	end

	assemblyRoot.AssemblyLinearVelocity = Vector3.zero
	assemblyRoot.AssemblyAngularVelocity = Vector3.zero

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= assemblyRoot then
			setWeldedPartPhysics(descendant)
		end
	end

	setHeldPartPhysics(assemblyRoot)
	assemblyRoot.CanQuery = true

	local holdOffset = CFrame.new(0, 1.25, -2.75)
	if instance:IsA("Model") then
		instance:PivotTo(humanoidRoot.CFrame * holdOffset)
	else
		assemblyRoot.CFrame = humanoidRoot.CFrame * holdOffset
	end

	pcall(function()
		assemblyRoot:SetNetworkOwner(Players.LocalPlayer)
	end)

	local holdWeld = Instance.new("WeldConstraint")
	holdWeld.Name = "CapsuleHoldWeld"
	holdWeld.Part0 = humanoidRoot
	holdWeld.Part1 = assemblyRoot
	holdWeld.Parent = getAssemblyWeldFolder(assemblyRoot)
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
	onExpired: ((string) -> ())?,
	spawnOptions: {
		parent: Instance?,
		registerPossibleDrop: ((BasePart, Instance) -> ())?,
		unregisterPossibleDrop: ((BasePart) -> ())?,
	}?
): BasePart?
	self:destroyCapsule(capsuleId)

	local template = getCapsuleTemplate()
	if not template then
		warn("[CapsuleRenderer] Capsule template missing at ReplicatedStorage.Assets.Drops.Capsule (Model or Part)")
		return nil
	end

	local instance = template:Clone()
	instance.Name = `Capsule_{capsuleId}`
	instance:SetAttribute("CapsuleId", capsuleId)
	instance:SetAttribute("OpenPrice", openPrice)
	instance:SetAttribute("IsCapsule", true)

	local assemblyRoot = resolveAssemblyRoot(instance)
	if not assemblyRoot then
		instance:Destroy()
		warn("[CapsuleRenderer] Capsule has no assembly root part (Capsule/Bottom/Top)")
		return nil
	end

	instance:SetAttribute("IsPossibleDrop", true)
	instance:SetAttribute("DropValue", nil)
	instance:SetAttribute("Value", nil)

	clearTemplateWelds(instance)

	for _, slotName in CapsuleUtil.getSlotNames() do
		local slot = findUnitSlot(instance, slotName)
		if slot then
			hideSlotPlaceholder(slot)
		end
	end

	if instance:IsA("Model") then
		instance.PrimaryPart = assemblyRoot
	end

	local entry = {
		instance = instance,
		root = assemblyRoot,
		previewTiers = previewTiers,
		openPrice = openPrice,
		highestTier = highestTier,
		pickedUp = false,
		touchConnection = nil,
		holdWeld = nil,
		lifetimeThread = nil,
		unregisterPossibleDrop = spawnOptions and spawnOptions.unregisterPossibleDrop or nil,
	}
	self.entries[capsuleId] = entry

	local parent = if spawnOptions and spawnOptions.parent then spawnOptions.parent else self:getFolder()
	instance.Parent = parent
	CapsuleRenderer.populatePreviewUnits(instance, assemblyRoot, previewTiers)
	placeAssemblyAt(instance, assemblyRoot, spawnCFrame)

	if spawnOptions and spawnOptions.registerPossibleDrop then
		spawnOptions.registerPossibleDrop(assemblyRoot, instance)
	end

	assemblyRoot.AssemblyLinearVelocity = Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))

	entry.touchConnection = assemblyRoot.Touched:Connect(function(hit: BasePart)
		local current = self.entries[capsuleId]
		if not current or current.pickedUp or self:hasHeldCapsule() then
			return
		end

		if not hit or not hit:IsA("BasePart") then
			return
		end

		if hit:GetAttribute("IsCapsule") == true then
			return
		end

		if hit:GetAttribute("IsPossibleDrop") == true then
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

	local lifetime = tonumber(getCapsuleConfig().CapsuleLifetime) or 180
	entry.lifetimeThread = task.delay(lifetime, function()
		local current = self.entries[capsuleId]
		if current and not current.pickedUp then
			if onExpired then
				onExpired(capsuleId)
			end
			self:destroyCapsule(capsuleId)
		end
	end)

	return assemblyRoot
end

function CapsuleRenderer:destroy()
	for capsuleId in self.entries do
		self:destroyCapsule(capsuleId)
	end
end

return CapsuleRenderer
