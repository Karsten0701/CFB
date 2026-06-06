local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)

local CapsuleRenderer = {}
CapsuleRenderer.__index = CapsuleRenderer

local CAPSULE_COLLISION_GROUP = "CapsuleDrops"
local DROP_COLLISION_GROUP = "ManaDrops"
local DROP_WALL_COLLISION_GROUP = "DropWalls"
local PLAYER_COLLISION_GROUP = "PlayerCharacters"
local CAPSULE_BOTTOM_COLORS = {
	Color3.fromRGB(235, 64, 52),
	Color3.fromRGB(52, 205, 82),
	Color3.fromRGB(52, 127, 235),
	Color3.fromRGB(255, 215, 52),
	Color3.fromRGB(190, 86, 255),
	Color3.fromRGB(255, 128, 40),
	Color3.fromRGB(40, 220, 220),
}

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
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, CAPSULE_COLLISION_GROUP, false)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, true)
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

local unitTemplateCache: { [number]: { Model: Model, IsPreScaled: boolean } } = {}

local function getCapsuleTemplatesFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	local templates = assets:FindFirstChild("CapsuleTemplates")
	return if templates and templates:IsA("Folder") then templates else nil
end

local function getUnitTemplate(tier: number): (Model?, boolean)
	local cached = unitTemplateCache[tier]
	if cached and cached.Model.Parent then
		return cached.Model, cached.IsPreScaled
	end

	tier = math.clamp(math.floor(tier), 1, AnimeDroppers.MaxTier)

	local capsuleTemplates = getCapsuleTemplatesFolder()
	if capsuleTemplates then
		for fallbackTier = tier, 1, -1 do
			local tierData = AnimeDroppers.Tiers[fallbackTier]
			local model = tierData and capsuleTemplates:FindFirstChild(tierData.ModelName)
			if model and model:IsA("Model") then
				unitTemplateCache[tier] = {
					Model = model,
					IsPreScaled = true,
				}
				return model, true
			end
		end

		for fallbackTier = tier + 1, AnimeDroppers.MaxTier do
			local tierData = AnimeDroppers.Tiers[fallbackTier]
			local model = tierData and capsuleTemplates:FindFirstChild(tierData.ModelName)
			if model and model:IsA("Model") then
				unitTemplateCache[tier] = {
					Model = model,
					IsPreScaled = true,
				}
				return model, true
			end
		end
	end

	local assets = getAnimeDroppersFolder()
	if not assets then
		return nil, false
	end

	for fallbackTier = tier, 1, -1 do
		local tierData = AnimeDroppers.Tiers[fallbackTier]
		if tierData then
			local model = assets:FindFirstChild(tierData.ModelName)
			if model and model:IsA("Model") then
				unitTemplateCache[tier] = {
					Model = model,
					IsPreScaled = false,
				}
				return model, false
			end
		end
	end

	for fallbackTier = tier + 1, AnimeDroppers.MaxTier do
		local tierData = AnimeDroppers.Tiers[fallbackTier]
		if tierData then
			local model = assets:FindFirstChild(tierData.ModelName)
			if model and model:IsA("Model") then
				unitTemplateCache[tier] = {
					Model = model,
					IsPreScaled = false,
				}
				return model, false
			end
		end
	end

	return nil, false
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

		return capsule
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
	local searchRoot = content or capsule

	local slot = searchRoot:FindFirstChild(slotName)
	if slot then
		return slot
	end

	local lower = string.lower(slotName)
	for _, child in searchRoot:GetChildren() do
		if string.lower(child.Name) == lower then
			return child
		end
	end

	local upper = string.upper(string.sub(slotName, 1, 1)) .. string.sub(slotName, 2)
	return searchRoot:FindFirstChild(upper)
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
	if part:IsA("Part") then
		part.Shape = Enum.PartType.Ball
	end
	part.RootPriority = 127
	part.CustomPhysicalProperties = PhysicalProperties.new(0.8, 0.75, 0, 1, 100)
	part:SetAttribute("IsCapsule", true)
	part:SetAttribute("IsPossibleDrop", true)
	part:SetAttribute("DropValue", nil)
	part:SetAttribute("Value", nil)
end

local function setWeldedPartPhysics(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = false
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
	part.Massless = false
	part.CollisionGroup = CAPSULE_COLLISION_GROUP
end

local function getHoldAttachmentFolder(assemblyRoot: BasePart): Folder
	local folder = assemblyRoot:FindFirstChild("CapsuleHold")
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = "CapsuleHold"
	folder.Parent = assemblyRoot
	return folder
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
	setCapsulePartPhysics(assemblyRoot)

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
			local lowerName = string.lower(descendant.Name)
			local isHiddenHelper = lowerName == "humanoidrootpart"
				or lowerName == "rootpart"
				or string.find(lowerName, "hitbox") ~= nil
				or string.find(lowerName, "collision") ~= nil

			if isHiddenHelper then
				descendant.Transparency = 1
				descendant.LocalTransparencyModifier = 1
			elseif descendant.Transparency >= 1 then
				descendant.Transparency = 0
				descendant.LocalTransparencyModifier = 0
			else
				descendant.LocalTransparencyModifier = 0
			end
		end
	end
end

local function hideSlotPlaceholder(slot: Instance)
	for _, descendant in slot:GetDescendants() do
		if descendant:IsA("Model") and isPreviewModel(descendant) then
			continue
		end

		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = false
		end
	end

	if slot:IsA("BasePart") then
		slot.Anchored = false
		slot.Transparency = 1
		slot.CanCollide = false
		slot.CanTouch = false
		slot.CanQuery = false
		slot.Massless = false
	end
end

local function getColorIndexFromId(capsuleId: string): number
	local hash = 0
	for index = 1, #capsuleId do
		hash = (hash * 31 + string.byte(capsuleId, index)) % 100000
	end

	return (hash % #CAPSULE_BOTTOM_COLORS) + 1
end

local function applyCapsuleBottomColor(capsule: Instance, capsuleId: string)
	local color = CAPSULE_BOTTOM_COLORS[getColorIndexFromId(capsuleId)]

	if capsule:IsA("BasePart") and capsule.Name == "Bottom" then
		capsule.Color = color
	end

	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "Bottom" then
			descendant.Color = color
		end
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
	weldPartToRoot(anchor, assemblyRoot, "CapsulePreviewWeld")
end

local function isLocalCharacterPart(part: BasePart): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil and part:IsDescendantOf(character)
end

local function getUprightHoldCFrame(humanoidRoot: BasePart, offset: CFrame): CFrame
	local targetPosition = (humanoidRoot.CFrame * offset).Position
	local look = humanoidRoot.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.001 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	return CFrame.lookAt(targetPosition, targetPosition + flatLook)
end

local function startCapsulePhysicsDebug(capsuleId: string, assemblyRoot: BasePart)
	if getCapsuleConfig().DebugPhysics ~= true then
		return
	end

	task.spawn(function()
		local lastPosition = assemblyRoot.Position
		local lastOrientation = assemblyRoot.Orientation

		for sample = 1, 8 do
			if not assemblyRoot.Parent then
				return
			end

			local position = assemblyRoot.Position
			local orientation = assemblyRoot.Orientation
			local moved = (position - lastPosition).Magnitude
			local rotated = (orientation - lastOrientation).Magnitude
			print(
				`[CapsuleDebug] {capsuleId} sample={sample} pos={position} orient={orientation} moved={string.format(
					"%.3f",
					moved
				)} rotated={string.format("%.3f", rotated)} linVel={assemblyRoot.AssemblyLinearVelocity} angVel={assemblyRoot.AssemblyAngularVelocity} anchored={assemblyRoot.Anchored} massless={assemblyRoot.Massless} canCollide={assemblyRoot.CanCollide} group={assemblyRoot.CollisionGroup} rollDrive={assemblyRoot:FindFirstChild(
					"CapsuleRollDrive"
				) ~= nil}`
			)

			lastPosition = position
			lastOrientation = orientation
			task.wait(0.75)
		end
	end)
end

local function getHorizontalDirection(direction: Vector3?): Vector3?
	if not direction then
		return nil
	end

	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude < 0.001 then
		return nil
	end

	return horizontal.Unit
end

local function applyRollKick(assemblyRoot: BasePart, strength: number, preferredDirection: Vector3?)
	if not assemblyRoot.Parent then
		return
	end

	local direction = getHorizontalDirection(preferredDirection)
	if not direction then
		local angle = math.random() * math.pi * 2
		direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	end

	local mass = math.max(assemblyRoot.AssemblyMass, 1)
	local linearVelocity = direction * strength
	local spinAxis = Vector3.new(-direction.Z, 0, direction.X)

	assemblyRoot:ApplyImpulse(linearVelocity * mass)
	assemblyRoot:ApplyAngularImpulse(spinAxis * mass * strength * 1.1)
end

local function getRaycastExcludes(excludeRoot: Instance?, extraExclude: Instance?): { Instance }
	local excludes = {}
	if excludeRoot then
		table.insert(excludes, excludeRoot)
	else
		table.insert(excludes, extraExclude or Workspace)
	end
	if extraExclude and extraExclude ~= excludeRoot then
		table.insert(excludes, extraExclude)
	end
	return excludes
end

local function isManaDropPart(part: Instance?): boolean
	if not part or not part:IsA("BasePart") then
		return false
	end

	if part.CollisionGroup == DROP_COLLISION_GROUP then
		return true
	end

	if tonumber(part:GetAttribute("DropValue")) ~= nil or tonumber(part:GetAttribute("Value")) ~= nil then
		return true
	end

	local ancestor = part.Parent
	while ancestor and ancestor ~= Workspace do
		if ancestor.Name == "ManaDrops" then
			return true
		end
		ancestor = ancestor.Parent
	end

	return false
end

local function isFirstLayerBottom(part: Instance?): boolean
	if not part or not part:IsA("BasePart") or part.Name ~= "Bottom" then
		return false
	end

	local model = part.Parent
	local firstLayerStuff = model and model.Parent
	return model ~= nil and model.Name == "Model" and firstLayerStuff ~= nil and firstLayerStuff.Name == "FirstLayerStuff"
end

local function getBottomEdgePushDirection(bottom: BasePart?, assemblyRoot: BasePart): Vector3?
	if not bottom then
		return nil
	end

	local localPosition = bottom.CFrame:PointToObjectSpace(assemblyRoot.Position)
	local halfSize = bottom.Size * 0.5
	local radius = math.max(assemblyRoot.Size.X, assemblyRoot.Size.Y, assemblyRoot.Size.Z) * 0.5
	local margin = math.min(math.max(radius * 0.75, 0.75), math.min(halfSize.X, halfSize.Z) * 0.45)

	if math.abs(localPosition.X) <= halfSize.X - margin and math.abs(localPosition.Z) <= halfSize.Z - margin then
		return nil
	end

	local centerDirection = bottom.Position - assemblyRoot.Position
	return getHorizontalDirection(centerDirection)
end

local function getGroundRollDirection(
	assemblyRoot: BasePart,
	excludeRoot: Instance?,
	extraExclude: Instance?
): (Vector3?, boolean, boolean, BasePart?, boolean, Vector3)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = getRaycastExcludes(excludeRoot or assemblyRoot, extraExclude)
	raycastParams.IgnoreWater = true
	raycastParams.CollisionGroup = CAPSULE_COLLISION_GROUP
	raycastParams.RespectCanCollide = true

	local radius = math.max(assemblyRoot.Size.X, assemblyRoot.Size.Y, assemblyRoot.Size.Z) * 0.5
	local result = Workspace:Raycast(assemblyRoot.Position, Vector3.new(0, -(radius + 1.25), 0), raycastParams)
	local retryCount = 0
	while result and isManaDropPart(result.Instance) and retryCount < 4 do
		retryCount += 1
		local excludes = table.clone(raycastParams.FilterDescendantsInstances)
		table.insert(excludes, result.Instance)
		raycastParams.FilterDescendantsInstances = excludes
		result = Workspace:Raycast(assemblyRoot.Position, Vector3.new(0, -(radius + 1.25), 0), raycastParams)
	end

	if not result or not result.Instance:IsA("BasePart") then
		return nil, false, false, nil, false, Vector3.yAxis
	end

	local grounded = result.Distance <= radius + 0.45
	if not grounded then
		return nil, false, false, nil, false, result.Normal
	end

	local normal = result.Normal
	local hitPart = result.Instance
	local onFirstLayerBottom = isFirstLayerBottom(hitPart)
	if normal.Y > 0.985 then
		return nil, false, true, hitPart, onFirstLayerBottom, normal
	end

	local gravityDirection = Vector3.new(0, -1, 0)
	local downhill = gravityDirection - normal * gravityDirection:Dot(normal)
	if downhill.Magnitude < 0.02 then
		return nil, false, true, hitPart, onFirstLayerBottom, normal
	end

	return downhill.Unit, true, true, hitPart, onFirstLayerBottom, normal
end

local function pushGroundedHorizontalVelocity(assemblyRoot: BasePart, direction: Vector3, targetSpeed: number)
	local horizontalDirection = getHorizontalDirection(direction)
	if not horizontalDirection then
		return
	end

	local velocity = assemblyRoot.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	if horizontalVelocity.Magnitude >= targetSpeed then
		return
	end

	local newHorizontalVelocity = horizontalDirection * targetSpeed
	assemblyRoot.AssemblyLinearVelocity = Vector3.new(newHorizontalVelocity.X, velocity.Y, newHorizontalVelocity.Z)
end

local function syncGroundedRollSpin(assemblyRoot: BasePart, direction: Vector3, targetSpeed: number)
	local horizontalDirection = getHorizontalDirection(direction)
	if not horizontalDirection then
		return
	end

	local radius = math.max(math.max(assemblyRoot.Size.X, assemblyRoot.Size.Y, assemblyRoot.Size.Z) * 0.5, 0.25)
	local spinAxis = Vector3.new(-horizontalDirection.Z, 0, horizontalDirection.X)
	local targetAngularSpeed = math.clamp(targetSpeed / radius, 1.5, 8)
	local currentAngularVelocity = assemblyRoot.AssemblyAngularVelocity
	local currentRollSpeed = math.abs(currentAngularVelocity:Dot(spinAxis))
	if currentRollSpeed >= targetAngularSpeed * 0.7 then
		return
	end

	assemblyRoot.AssemblyAngularVelocity = spinAxis * targetAngularSpeed + Vector3.new(0, currentAngularVelocity.Y, 0)
end

local function getCapsuleSeparationDirection(entry: any, assemblyRoot: BasePart): Vector3?
	local entries = entry.entries
	if type(entries) ~= "table" then
		return nil
	end

	local config = getCapsuleConfig()
	local radius = math.max(assemblyRoot.Size.X, assemblyRoot.Size.Y, assemblyRoot.Size.Z) * 0.5
	local separationRange = math.max(tonumber(config.CapsuleSeparationRange) or radius * 3.25, radius * 1.5)
	local position = assemblyRoot.Position
	local push = Vector3.zero

	for _, otherEntry in entries do
		if otherEntry == entry or otherEntry.pickedUp or not otherEntry.root or not otherEntry.root.Parent then
			continue
		end

		local delta = position - otherEntry.root.Position
		local horizontal = Vector3.new(delta.X, 0, delta.Z)
		local distance = horizontal.Magnitude
		if distance > separationRange then
			continue
		end

		if distance <= 0.05 then
			local angle = (os.clock() * 17 + radius * 11) % (math.pi * 2)
			horizontal = Vector3.new(math.cos(angle), 0, math.sin(angle))
			distance = 0.05
		end

		push += horizontal.Unit * ((separationRange - distance) / separationRange)
	end

	if push.Magnitude < 0.01 then
		return nil
	end

	return push.Unit
end

local function destroyRollDrive(entry: any)
	if entry.rollConnection then
		entry.rollConnection:Disconnect()
		entry.rollConnection = nil
	end

	if entry.rollDriveAttachment then
		entry.rollDriveAttachment:Destroy()
		entry.rollDriveAttachment = nil
	end

	if entry.rollDriveFolder then
		entry.rollDriveFolder:Destroy()
		entry.rollDriveFolder = nil
	end
end

local function startRollingAssist(entry: any, assemblyRoot: BasePart, preferredDirection: Vector3?)
	destroyRollDrive(entry)

	local folder = Instance.new("Folder")
	folder.Name = "CapsuleRollDrive"
	folder.Parent = assemblyRoot
	entry.rollDriveFolder = folder

	local attachment = Instance.new("Attachment")
	attachment.Name = "CapsuleRollAttachment"
	attachment.Parent = assemblyRoot
	entry.rollDriveAttachment = attachment

	local torque = Instance.new("Torque")
	torque.Name = "CapsuleRollTorque"
	torque.Attachment0 = attachment
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Torque = Vector3.zero
	torque.Parent = folder

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "CapsuleRollVectorForce"
	vectorForce.Attachment0 = attachment
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Force = Vector3.zero
	vectorForce.Parent = folder

	local rollDirection = getHorizontalDirection(preferredDirection) or Vector3.new(1, 0, 0)
	local nextKickAt = 0
	local driveStartedAt = os.clock()
	local bottomStableSince: number? = nil
	local bottomLandedAt: number? = nil
	entry.rollConnection = RunService.Heartbeat:Connect(function()
		if entry.destroying or entry.pickedUp or not assemblyRoot.Parent then
			destroyRollDrive(entry)
			return
		end

		local now = os.clock()
		local horizontalVelocity =
			Vector3.new(assemblyRoot.AssemblyLinearVelocity.X, 0, assemblyRoot.AssemblyLinearVelocity.Z)
		local driveAge = now - driveStartedAt

		local separationDirection = getCapsuleSeparationDirection(entry, assemblyRoot)

		local slopeDirection, onSlope, grounded, groundPart, onFirstLayerBottom, groundNormal =
			getGroundRollDirection(assemblyRoot, entry.instance)

		local bottomEdgePushDirection =
			if onFirstLayerBottom then getBottomEdgePushDirection(groundPart, assemblyRoot) else nil
		local stableOnBottom = onFirstLayerBottom and grounded and not onSlope and groundNormal.Y > 0.985
			and bottomEdgePushDirection == nil
		if stableOnBottom then
			bottomStableSince = bottomStableSince or now
			if not bottomLandedAt and now - bottomStableSince >= 0.35 then
				bottomLandedAt = now
			end
		elseif not stableOnBottom then
			bottomStableSince = nil
			bottomLandedAt = nil
		end

		if bottomLandedAt and now - bottomLandedAt >= 20 then
			assemblyRoot.AssemblyLinearVelocity = Vector3.zero
			assemblyRoot.AssemblyAngularVelocity = Vector3.zero
			destroyRollDrive(entry)
			return
		end

		local bottomRollAlpha = if bottomLandedAt then math.clamp(1 - ((now - bottomLandedAt) / 20), 0.2, 1) else 1
		local assistAlpha = math.clamp(1 - (driveAge / 120), 0.7, 1) * bottomRollAlpha
		if slopeDirection then
			local horizontalSlopeDirection = getHorizontalDirection(slopeDirection)
			if horizontalSlopeDirection then
				rollDirection = horizontalSlopeDirection
			end
		elseif horizontalVelocity.Magnitude > 0.35 then
			rollDirection = horizontalVelocity.Unit
		end

		local mass = math.max(assemblyRoot.AssemblyMass, 1)
		local canFlatAssist = grounded and not onSlope
		local assistDirection = if slopeDirection then slopeDirection else if canFlatAssist then rollDirection else nil
		if separationDirection and assistDirection then
			assistDirection = (assistDirection + separationDirection * 0.75).Unit
		elseif separationDirection then
			assistDirection = separationDirection
		end
		if bottomEdgePushDirection and assistDirection then
			assistDirection = (assistDirection + bottomEdgePushDirection * 1.35).Unit
		elseif bottomEdgePushDirection then
			assistDirection = bottomEdgePushDirection
		end

		if assistDirection then
			local forceStrength = if bottomEdgePushDirection then 125 else if separationDirection then 55 else if onSlope then 115 else 70
			local torqueStrength = if bottomEdgePushDirection then 950 else if separationDirection then 500 else if onSlope then 950 else 700
			local torqueDirection = getHorizontalDirection(assistDirection) or rollDirection
			local spinAxis = Vector3.new(-torqueDirection.Z, 0, torqueDirection.X)
			vectorForce.Force = assistDirection * mass * forceStrength * assistAlpha
			torque.Torque = spinAxis * mass * torqueStrength * assistAlpha

			local targetSpeed = if bottomEdgePushDirection then 5 else if separationDirection then 2.4 else if onSlope then 5.5 else 3.5
			pushGroundedHorizontalVelocity(assemblyRoot, assistDirection, targetSpeed * assistAlpha)
			syncGroundedRollSpin(assemblyRoot, assistDirection, targetSpeed * assistAlpha)
		else
			vectorForce.Force = Vector3.zero
			torque.Torque = Vector3.zero
		end

		if now < nextKickAt then
			return
		end

		nextKickAt = now + 1
		if grounded and assistDirection and horizontalVelocity.Magnitude < 0.65 and assistAlpha > 0 then
			applyRollKick(assemblyRoot, if onSlope then 2.2 else 1.5, rollDirection)
		end
	end)
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
			return dropSpot.WorldCFrame
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

	clearExistingPreviews(capsule, assemblyRoot)

	for index = 1, #previewTiers do
		local tier = previewTiers[index]
		local slotName = CapsuleUtil.getSlotNames()[index]
		if not slotName or type(tier) ~= "number" then
			continue
		end

		local slot = findUnitSlot(capsule, slotName)
		local template, isPreScaled = getUnitTemplate(tier)
		if not slot then
			warn("[CapsuleRenderer] Missing slot:", slotName)
			continue
		end
		if not template then
			warn("[CapsuleRenderer] Missing unit template for tier:", tier)
			continue
		end

		hideSlotPlaceholder(slot)

		local unitModel = template:Clone()
		unitModel.Name = `Preview_{tier}`
		stripPreviewDecorations(unitModel)

		if not isPreScaled then
			local scaleOk = pcall(function()
				unitModel:ScaleTo(unitScale)
			end)
			if not scaleOk then
				warn("[CapsuleRenderer] ScaleTo failed for preview tier:", tier)
			end
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

local function clearHold(entry: any)
	if not entry then
		return
	end

	if entry.holdConnection then
		entry.holdConnection:Disconnect()
		entry.holdConnection = nil
	end

	if entry.holdWeld then
		entry.holdWeld:Destroy()
		entry.holdWeld = nil
	end

	if entry.holdFolder then
		entry.holdFolder:Destroy()
		entry.holdFolder = nil
	end

	if entry.rootHoldAttachment then
		entry.rootHoldAttachment:Destroy()
		entry.rootHoldAttachment = nil
	end

	if entry.characterHoldAttachment then
		entry.characterHoldAttachment:Destroy()
		entry.characterHoldAttachment = nil
	end

	if entry.root and entry.root.Parent then
		entry.root.Anchored = false
		entry.root.Massless = false
		entry.root.AssemblyLinearVelocity = Vector3.zero
		entry.root.AssemblyAngularVelocity = Vector3.zero
	end
end

function CapsuleRenderer:releaseHold(capsuleId: string)
	clearHold(self.entries[capsuleId])
end

local function unregisterPossibleDrop(entry: any)
	if entry and entry.unregisterPossibleDrop and entry.root then
		entry.unregisterPossibleDrop(entry.root)
		entry.unregisterPossibleDrop = nil
	end
end

local function cancelThreadSafely(threadHandle: thread?)
	if not threadHandle or coroutine.running() == threadHandle then
		return
	end

	pcall(function()
		task.cancel(threadHandle)
	end)
end

function CapsuleRenderer:destroyCapsule(capsuleId: string)
	local entry = self.entries[capsuleId]
	if not entry or entry.destroying then
		return
	end

	entry.destroying = true
	self.entries[capsuleId] = nil

	unregisterPossibleDrop(entry)
	self:releaseHold(capsuleId)

	if entry.touchConnection then
		entry.touchConnection:Disconnect()
		entry.touchConnection = nil
	end

	destroyRollDrive(entry)

	if entry.lifetimeThread then
		cancelThreadSafely(entry.lifetimeThread)
		entry.lifetimeThread = nil
	end

	if entry.instance and entry.instance.Parent then
		entry.instance:Destroy()
	end
end

function CapsuleRenderer:attachHeldCapsuleToRoot(entry: any, humanoidRoot: BasePart): boolean
	if not entry or not entry.instance or not entry.instance.Parent or not entry.root or not entry.root.Parent then
		return false
	end

	clearHold(entry)

	local instance = entry.instance
	local assemblyRoot = entry.root
	assemblyRoot.AssemblyLinearVelocity = Vector3.zero
	assemblyRoot.AssemblyAngularVelocity = Vector3.zero

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= assemblyRoot then
			setWeldedPartPhysics(descendant)
		end
	end

	setHeldPartPhysics(assemblyRoot)
	assemblyRoot.CanQuery = true
	assemblyRoot.Anchored = false

	local holdOffset = CFrame.new(0, 1.25, -2.75)
	local holdCFrame = getUprightHoldCFrame(humanoidRoot, holdOffset)
	if instance:IsA("Model") then
		instance:PivotTo(holdCFrame)
	else
		assemblyRoot.CFrame = holdCFrame
	end

	local holdFolder = getHoldAttachmentFolder(assemblyRoot)
	holdFolder:ClearAllChildren()
	entry.holdFolder = holdFolder

	local rootAttachment = Instance.new("Attachment")
	rootAttachment.Name = "CapsuleHoldAttachment"
	rootAttachment.Parent = assemblyRoot
	entry.rootHoldAttachment = rootAttachment

	local characterAttachment = Instance.new("Attachment")
	characterAttachment.Name = "CapsuleHoldTarget"
	characterAttachment.CFrame = holdOffset
	characterAttachment.Parent = humanoidRoot
	entry.characterHoldAttachment = characterAttachment

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "CapsuleHoldPosition"
	alignPosition.Attachment0 = rootAttachment
	alignPosition.Attachment1 = characterAttachment
	alignPosition.MaxForce = 25000
	alignPosition.MaxVelocity = 80
	alignPosition.Responsiveness = 35
	alignPosition.RigidityEnabled = false
	alignPosition.Parent = holdFolder

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "CapsuleHoldOrientation"
	alignOrientation.Attachment0 = rootAttachment
	alignOrientation.Attachment1 = characterAttachment
	alignOrientation.MaxTorque = 25000
	alignOrientation.MaxAngularVelocity = 80
	alignOrientation.Responsiveness = 35
	alignOrientation.RigidityEnabled = false
	alignOrientation.Parent = holdFolder

	assemblyRoot.AssemblyLinearVelocity = Vector3.zero
	assemblyRoot.AssemblyAngularVelocity = Vector3.zero
	return true
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

	entry.pickedUp = true
	entry.onPickedUp = onPickedUp
	unregisterPossibleDrop(entry)

	if entry.lifetimeThread then
		cancelThreadSafely(entry.lifetimeThread)
		entry.lifetimeThread = nil
	end

	if entry.touchConnection then
		entry.touchConnection:Disconnect()
		entry.touchConnection = nil
	end

	destroyRollDrive(entry)
	self:attachHeldCapsuleToRoot(entry, humanoidRoot)

	if onPickedUp then
		onPickedUp(capsuleId)
	end
end

function CapsuleRenderer:reattachHeldCapsules(onReattached: ((string) -> ())?)
	local character = Players.LocalPlayer.Character
	local humanoidRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot or not humanoidRoot:IsA("BasePart") then
		return
	end

	for capsuleId, entry in self.entries do
		if entry and entry.pickedUp and self:attachHeldCapsuleToRoot(entry, humanoidRoot) then
			if onReattached then
				onReattached(capsuleId)
			elseif entry.onPickedUp then
				entry.onPickedUp(capsuleId)
			end
		end
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
		rollDirection: Vector3?,
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
	applyCapsuleBottomColor(instance, capsuleId)

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
		entries = self.entries,
		pickedUp = false,
		touchConnection = nil,
		rollConnection = nil,
		rollDriveFolder = nil,
		rollDriveAttachment = nil,
		holdWeld = nil,
		holdConnection = nil,
		holdFolder = nil,
		rootHoldAttachment = nil,
		characterHoldAttachment = nil,
		onPickedUp = nil,
		lifetimeThread = nil,
		destroying = false,
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

	local rollDirection = spawnOptions and spawnOptions.rollDirection or nil
	applyRollKick(assemblyRoot, 2.2, rollDirection)
	startRollingAssist(entry, assemblyRoot, rollDirection)
	task.delay(0.65, function()
		local current = self.entries[capsuleId]
		if not current or current.pickedUp or not assemblyRoot.Parent then
			return
		end

		local horizontalVelocity =
			Vector3.new(assemblyRoot.AssemblyLinearVelocity.X, 0, assemblyRoot.AssemblyLinearVelocity.Z)
		if horizontalVelocity.Magnitude < 1 then
			applyRollKick(assemblyRoot, 1.4, rollDirection)
		end
	end)
	startCapsulePhysicsDebug(capsuleId, assemblyRoot)

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
			current.lifetimeThread = nil
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
