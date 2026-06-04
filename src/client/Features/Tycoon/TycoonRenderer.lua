local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Grid = require(ReplicatedStorage.Shared.Features.Tycoon.Grid)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)

local TycoonRenderer = {}
TycoonRenderer.__index = TycoonRenderer

local DROP_INTERVAL = 6
local DOUBLE_DROP_SPEED_INTERVAL = 3
local MAX_ACTIVE_DROPS = 150
local MAX_DROP_SPAWNS_PER_FRAME = 4
local DROP_STAGGER_HASH = 0.61803398875
local PICKUP_ANIMATION_TIME = 0.42
local PICKUP_POPUP_LIFETIME = 0.72
local PICKUP_POPUP_RISE = 1.65
local PICKUP_POPUP_FADE_TIME = 0.16
local PICKUP_POPUP_SIZE = UDim2.fromOffset(280, 78)
local PICKUP_POPUP_TEXT_SIZE = 36
local UNIT_SPAWN_BATCH_SIZE = 8
local UNIT_SPAWN_BATCH_DELAY = 0.02
local UNIT_RENDER_BATCH_SIZE = 8
local UNIT_RENDER_BATCH_DELAY = 0.02
local UNIT_POOL_LIMIT_PER_TIER = 18
local UNIT_POOL_CFRAME = CFrame.new(0, -10000, 0)
local PLAYER_COLLISION_GROUP = "PlayerCharacters"
local DROP_COLLISION_GROUP = "ManaDrops"
local DROP_WALL_COLLISION_GROUP = "DropWalls"
local DEFAULT_MUTATION_INTERVAL = 60
local DEFAULT_MUTATION_WEIGHT_POWER = 4
local DEFAULT_GOLD_MULTIPLIERS = { 2, 5, 10, 25, 100 }

pcall(function()
	PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
end)
pcall(function()
	PhysicsService:RegisterCollisionGroup(DROP_COLLISION_GROUP)
end)
pcall(function()
	PhysicsService:RegisterCollisionGroup(DROP_WALL_COLLISION_GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(DROP_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(DROP_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, true)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, false)
end)

local function getAssetsFolder(): Folder?
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

local function getFloorModel(dropperHolder: Instance, floorIndex: number): Model?
	if floorIndex == 1 then
		local floorLayer = dropperHolder:FindFirstChild("FloorLayer")
		return if floorLayer and floorLayer:IsA("Model") then floorLayer else nil
	end

	local floor = dropperHolder:FindFirstChild("FloorLayer_" .. floorIndex)
	return if floor and floor:IsA("Model") then floor else nil
end

local function getSpotPart(floorModel: Model, spotIndex: number): BasePart?
	local spotsFolder = floorModel:FindFirstChild("DropperSpots")
	if not spotsFolder then
		return nil
	end

	local spot = spotsFolder:FindFirstChild(tostring(spotIndex))
	return if spot and spot:IsA("BasePart") then spot else nil
end

local function getUnitModel(tier: number): Model?
	local tierData = AnimeDroppers.Tiers[tier]
	if not tierData then
		return nil
	end

	local assets = getAssetsFolder()
	if not assets then
		return nil
	end

	local model = assets:FindFirstChild(tierData.ModelName)
	if model and model:IsA("Model") then
		return model
	end

	if tier > 1 then
		for fallbackTierIndex = tier - 1, 1, -1 do
			local fallbackTier = AnimeDroppers.Tiers[fallbackTierIndex]
			if fallbackTier then
				local fallback = assets:FindFirstChild(fallbackTier.ModelName)
				if fallback and fallback:IsA("Model") then
					return fallback
				end
			end
		end
	end

	return nil
end

local function getOverheadTemplate(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	return assets:FindFirstChild("OverheadTemplateUnit")
end

local function getPickupTemplate(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	return assets:FindFirstChild("Pickup")
end

local function getDropTemplate(tier: number): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local dropsFolder = assets and assets:FindFirstChild("Drops")
	if not dropsFolder then
		return nil
	end

	return dropsFolder:FindFirstChild("Tier" .. tier) or dropsFolder:FindFirstChild("Template")
end

local function getGoldDropTemplate(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local dropsFolder = assets and assets:FindFirstChild("Drops")
	if not dropsFolder then
		return nil
	end

	local mutationConfig = TycoonConfig.Mutations or {}
	local goldConfig = mutationConfig.Gold or {}
	return dropsFolder:FindFirstChild(goldConfig.TemplateName or "Gold")
end

local function getFirstBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function setDropPhysics(part: BasePart, value: number)
	part.Anchored = false
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = true
	part.CollisionGroup = DROP_COLLISION_GROUP
	part:SetAttribute("DropValue", value)
	part:SetAttribute("Value", value)
	part.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.35, 0.15)
end

local function prepareDropPickup(dropInstance: Instance, pickupPart: BasePart, value: number)
	setDropPhysics(pickupPart, value)

	for _, descendant in dropInstance:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= pickupPart then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CollisionGroup = DROP_COLLISION_GROUP

			local weld = Instance.new("WeldConstraint")
			weld.Name = "DropAssemblyWeld"
			weld.Part0 = pickupPart
			weld.Part1 = descendant
			weld.Parent = pickupPart
		end
	end
end

local function getAdorneePart(model: Model): BasePart?
	local head = model:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function setOverheadLabel(overhead: Instance, labelName: string, text: string)
	local label = overhead:FindFirstChild(labelName, true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function setFirstTextLabelText(instance: Instance, text: string)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("TextLabel") then
			descendant.Text = text
			return
		end
	end
end

local function setMutationLabel(instance: Instance, multiplier: number, tier: number)
	local label = instance:FindFirstChild("Name", true)
	if label and label:IsA("TextLabel") then
		label.Text = tostring(multiplier) .. "x [T" .. tostring(tier) .. "]"
	end
end

local function fadeTextLabels(instance: Instance, transparency: number)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("TextLabel") then
			descendant.TextTransparency = transparency
			descendant.TextStrokeTransparency = math.clamp(transparency, 0, 1)
		elseif descendant:IsA("UIStroke") then
			descendant.Transparency = transparency
		end
	end
end

local function preparePickupPopupInstance(instance: Instance)
	if instance:IsA("BillboardGui") then
		instance.Size = PICKUP_POPUP_SIZE
		instance.SizeOffset = Vector2.zero
		instance.AlwaysOnTop = true
		instance.MaxDistance = 150
	elseif instance:IsA("GuiObject") then
		instance.ClipsDescendants = false
	end

	if instance:IsA("TextLabel") then
		instance.AutomaticSize = Enum.AutomaticSize.None
		instance.Size = UDim2.fromScale(1, 1)
		instance.TextScaled = false
		instance.TextSize = PICKUP_POPUP_TEXT_SIZE
		instance.TextWrapped = false
		instance.TextXAlignment = Enum.TextXAlignment.Center
		instance.TextYAlignment = Enum.TextYAlignment.Center
	end
end

local function preparePickupPopup(popup: Instance)
	preparePickupPopupInstance(popup)
	for _, descendant in popup:GetDescendants() do
		preparePickupPopupInstance(descendant)
	end
end

local function quadraticBezier(
	startPosition: Vector3,
	controlPosition: Vector3,
	endPosition: Vector3,
	alpha: number
): Vector3
	local inverse = 1 - alpha
	return inverse * inverse * startPosition + 2 * inverse * alpha * controlPosition + alpha * alpha * endPosition
end

local function addOverhead(unitModel: Model, displayName: string, tier: number)
	local template = getOverheadTemplate()
	if not template then
		return
	end

	local overhead = template:Clone()
	overhead.Name = "Overhead"
	setOverheadLabel(overhead, "Name", displayName)
	setOverheadLabel(overhead, "Tier", "Tier " .. tier)

	if overhead:IsA("BillboardGui") then
		local adorneePart = getAdorneePart(unitModel)
		overhead.Adornee = adorneePart
		overhead.Parent = adorneePart or unitModel
	else
		overhead.Parent = unitModel
	end
end

local function anchorModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
end

function TycoonRenderer.new(tycoon: Instance, janitor: any, onPickup: ((number) -> ())?)
	local self = setmetatable({}, TycoonRenderer)
	self.tycoon = tycoon
	self.janitor = janitor
	self.onPickup = onPickup
	self.unitModels = {}
	self.unitEntries = {}
	self.unitPoolByTier = {}
	self.unitTemplateCache = {}
	self.unitModelInfo = {}
	self.spotCache = {}
	self.rebuildToken = 0
	self.activeOrbs = {}
	self.dropTouchConnections = {}
	self.isOwn = true
	self.entitlements = {}
	self.dropsFolder = nil
	self.dropBounds = nil
	self.autoCollectPart = nil
	self.autoCollectVisuals = nil
	self.pickupConnection = nil
	self.pickupAnimationConnection = nil
	self.pickupAnimations = {}
	self.dropLoopConnection = nil
	self.onManaDropSpawned = nil
	self.nextMutationAt = os.clock()
		+ (TycoonConfig.Mutations and TycoonConfig.Mutations.Interval or DEFAULT_MUTATION_INTERVAL)
	return self
end

function TycoonRenderer:setIsOwn(isOwn: boolean)
	self.isOwn = isOwn
end

function TycoonRenderer:setEntitlements(entitlements: { [string]: boolean })
	local oldInterval = self:getDropInterval()
	self.entitlements = entitlements or {}
	self:updateAutoCollectPad()

	local newInterval = self:getDropInterval()
	if oldInterval ~= newInterval then
		local now = os.clock()
		for unitIndex, entry in self.unitEntries do
			self:scheduleUnitDrop(entry, unitIndex, now, true)
		end
	end
end

function TycoonRenderer:getDropInterval(): number
	return if self.entitlements.DoubleDropSpeed then DOUBLE_DROP_SPEED_INTERVAL else DROP_INTERVAL
end

function TycoonRenderer:getManaRewardMultiplier(): number
	local multiplier = tonumber(self.entitlements.ManaMultiplier) or 1
	if multiplier <= 0 then
		return 1
	end

	return multiplier
end

function TycoonRenderer:getUnitDropPhase(unitIndex: number, interval: number): number
	local phase = (unitIndex * DROP_STAGGER_HASH) % 1
	return phase * interval
end

function TycoonRenderer:scheduleUnitDrop(entry, unitIndex: number, now: number?, force: boolean?)
	if not entry then
		return
	end

	now = now or os.clock()
	if entry.NextDropAt and not force then
		return
	end

	local interval = self:getDropInterval()
	entry.NextDropAt = now + self:getUnitDropPhase(unitIndex, interval)
end

function TycoonRenderer:getDropperHolder(): Instance?
	return self.tycoon:FindFirstChild("DropperHolder")
end

function TycoonRenderer:getDropsFolder(): Folder
	if self.dropsFolder and self.dropsFolder.Parent then
		return self.dropsFolder
	end

	local dropperHolder = self:getDropperHolder()
	assert(dropperHolder, "DropperHolder missing")

	local dropsFolder = dropperHolder:FindFirstChild("ManaDrops")
		or dropperHolder:FindFirstChild("ManaPowerDrops")
		or dropperHolder:FindFirstChild("MagicPowerDrops")
	if not dropsFolder then
		dropsFolder = Instance.new("Folder")
		dropsFolder.Parent = dropperHolder
	end
	dropsFolder.Name = "ManaDrops"

	self.dropsFolder = dropsFolder
	return dropsFolder
end

function TycoonRenderer:getUnitsFolder(): Folder
	local dropperHolder = self:getDropperHolder()
	assert(dropperHolder, "DropperHolder missing")

	local unitsFolder = dropperHolder:FindFirstChild("Units")
	if not unitsFolder then
		unitsFolder = Instance.new("Folder")
		unitsFolder.Name = "Units"
		unitsFolder.Parent = dropperHolder
	end

	return unitsFolder
end

function TycoonRenderer:getDropBounds(): BasePart?
	if self.dropBounds and self.dropBounds.Parent then
		return self.dropBounds
	end

	local dropperHolder = self:getDropperHolder()
	local firstLayerStuff = dropperHolder and dropperHolder:FindFirstChild("FirstLayerStuff")
	if firstLayerStuff then
		self:ensureDropWallCollision(firstLayerStuff)
	end

	local bounds = firstLayerStuff and firstLayerStuff:FindFirstChild("Bounds")
	if bounds and bounds:IsA("BasePart") then
		self.dropBounds = bounds
		return bounds
	end

	return nil
end

function TycoonRenderer:getAutoCollectPart(): BasePart?
	if self.autoCollectPart and self.autoCollectPart.Parent then
		return self.autoCollectPart
	end

	local dropperHolder = self:getDropperHolder()
	local firstLayerStuff = dropperHolder and dropperHolder:FindFirstChild("FirstLayerStuff")
	local autoCollect = firstLayerStuff and firstLayerStuff:FindFirstChild("AutoCollect")
	if autoCollect and autoCollect:IsA("BasePart") then
		self.autoCollectPart = autoCollect
		return autoCollect
	end

	return nil
end

function TycoonRenderer:updateAutoCollectPad()
	local autoCollect = self:getAutoCollectPart()
	if not autoCollect then
		return
	end

	if not self.autoCollectVisuals then
		local visuals = {
			Billboards = {},
			Parts = {},
		}

		for _, descendant in autoCollect:GetDescendants() do
			if descendant:IsA("BillboardGui") then
				table.insert(visuals.Billboards, descendant)
			elseif descendant:IsA("BasePart") then
				table.insert(visuals.Parts, descendant)
			end
		end

		self.autoCollectVisuals = visuals
	end

	local hasAutoCollect = self.entitlements.AutoCollect == true
	autoCollect.Transparency = if hasAutoCollect then 0 else 1
	autoCollect.CanCollide = false
	autoCollect.CanTouch = hasAutoCollect
	autoCollect.CanQuery = hasAutoCollect

	for index = #self.autoCollectVisuals.Billboards, 1, -1 do
		local billboard = self.autoCollectVisuals.Billboards[index]
		if not billboard.Parent then
			table.remove(self.autoCollectVisuals.Billboards, index)
		else
			billboard.Enabled = hasAutoCollect
		end
	end

	for index = #self.autoCollectVisuals.Parts, 1, -1 do
		local part = self.autoCollectVisuals.Parts[index]
		if not part.Parent then
			table.remove(self.autoCollectVisuals.Parts, index)
		else
			part.Transparency = if hasAutoCollect then 0 else 1
			part.CanCollide = false
			part.CanTouch = hasAutoCollect
			part.CanQuery = hasAutoCollect
		end
	end
end

function TycoonRenderer:ensureDropWallCollision(firstLayerStuff: Instance)
	local wall = firstLayerStuff:FindFirstChild("Wall")
	if not wall then
		return
	end

	if wall:IsA("BasePart") then
		wall.CanCollide = true
		wall.CanQuery = true
		wall.CollisionGroup = DROP_WALL_COLLISION_GROUP
	end

	for _, descendant in wall:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = true
			descendant.CanQuery = true
			descendant.CollisionGroup = DROP_WALL_COLLISION_GROUP
		end
	end
end

function TycoonRenderer:isInsideDropBounds(position: Vector3): boolean
	local bounds = self:getDropBounds()
	if not bounds then
		return true
	end

	local localPosition = bounds.CFrame:PointToObjectSpace(position)
	local halfSize = bounds.Size * 0.5

	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

function TycoonRenderer:ensureFloors(unitCount: number)
	local dropperHolder = self:getDropperHolder()
	if not dropperHolder then
		return
	end

	local template = dropperHolder:FindFirstChild("FloorLayer")
	if not template or not template:IsA("Model") then
		return
	end

	local required = Grid.requiredFloors(unitCount)
	local changedFloors = false

	for floorIndex = 2, required do
		local floorName = "FloorLayer_" .. floorIndex
		local floor = dropperHolder:FindFirstChild(floorName)
		if not floor then
			floor = template:Clone()
			floor.Name = floorName
			local yOffset = TycoonConfig.FloorYOffset * (floorIndex - 1)
			floor:PivotTo(template:GetPivot() * CFrame.new(0, yOffset, 0))
			floor.Parent = dropperHolder
			changedFloors = true
		end
	end

	for _, child in dropperHolder:GetChildren() do
		local floorIndex = string.match(child.Name, "^FloorLayer_(%d+)$")
		if floorIndex and tonumber(floorIndex) > required then
			child:Destroy()
			changedFloors = true
		end
	end

	if changedFloors then
		table.clear(self.spotCache)
	end
end

function TycoonRenderer:clearRenderedUnits()
	self.rebuildToken += 1

	for _, entry in self.unitEntries do
		if entry.Model then
			self.unitModelInfo[entry.Model] = nil
			entry.Model:Destroy()
		end
	end
	table.clear(self.unitModels)
	table.clear(self.unitEntries)

	for _, pool in self.unitPoolByTier do
		for _, model in pool do
			if model then
				self.unitModelInfo[model] = nil
				model:Destroy()
			end
		end
	end
	table.clear(self.unitPoolByTier)
	table.clear(self.unitModelInfo)

	local unitsFolder = self:getUnitsFolder()
	for _, child in unitsFolder:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

function TycoonRenderer:removeRenderedUnit(unitIndex: number)
	local entry = self.unitEntries[unitIndex]
	if not entry then
		return
	end

	self:recycleUnitEntry(entry)

	self.unitEntries[unitIndex] = nil
	self.unitModels[unitIndex] = nil
end

function TycoonRenderer:getUnitModelInfo(model: Model)
	local info = self.unitModelInfo[model]
	if info then
		return info
	end

	local billboards = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			table.insert(billboards, descendant)
		end
	end

	info = {
		BaseName = string.match(model.Name, "^(.-)_") or model.Name,
		Billboards = billboards,
	}
	self.unitModelInfo[model] = info
	return info
end

function TycoonRenderer:setUnitModelVisible(model: Model, visible: boolean)
	local info = self:getUnitModelInfo(model)
	for _, billboard in info.Billboards do
		if billboard.Parent then
			billboard.Enabled = visible
		end
	end
end

function TycoonRenderer:setUnitModelAssignment(model: Model, unitIndex: number?, tier: number?, pooled: boolean)
	if unitIndex then
		model:SetAttribute("UnitIndex", unitIndex)
	else
		model:SetAttribute("UnitIndex", nil)
	end

	if tier then
		model:SetAttribute("UnitTier", tier)
	else
		model:SetAttribute("UnitTier", nil)
	end

	model:SetAttribute("Pooled", pooled)
end

function TycoonRenderer:recycleUnitEntry(entry)
	if not entry or not entry.Model then
		return
	end

	local tier = entry.Tier or 1
	local pool = self.unitPoolByTier[tier]
	if not pool then
		pool = {}
		self.unitPoolByTier[tier] = pool
	end

	if #pool >= UNIT_POOL_LIMIT_PER_TIER then
		entry.Model:Destroy()
		self.unitModelInfo[entry.Model] = nil
		return
	end

	self:setUnitModelVisible(entry.Model, false)
	self:setUnitModelAssignment(entry.Model, nil, tier, true)
	entry.Model:PivotTo(UNIT_POOL_CFRAME)
	table.insert(pool, entry.Model)
end

function TycoonRenderer:getUnitTemplate(tier: number): Model?
	local cached = self.unitTemplateCache[tier]
	if cached and cached.Parent then
		return cached
	end

	local template = getUnitModel(tier)
	self.unitTemplateCache[tier] = template
	return template
end

function TycoonRenderer:getOrCreateUnitModel(tier: number, unitIndex: number): Model?
	local pool = self.unitPoolByTier[tier]
	local unitModel = pool and table.remove(pool)
	if unitModel then
		local info = self:getUnitModelInfo(unitModel)
		unitModel.Name = info.BaseName .. "_" .. unitIndex
		self:setUnitModelVisible(unitModel, true)
		self:setUnitModelAssignment(unitModel, unitIndex, tier, false)
		return unitModel
	end

	local template = self:getUnitTemplate(tier)
	if not template then
		return nil
	end

	unitModel = template:Clone()
	unitModel.Name = template.Name .. "_" .. unitIndex
	anchorModel(unitModel)
	local tierData = AnimeDroppers.Tiers[tier]
	addOverhead(unitModel, tierData and tierData.DisplayName or template.Name, tier)
	self:getUnitModelInfo(unitModel)
	self:setUnitModelAssignment(unitModel, unitIndex, tier, false)
	return unitModel
end

function TycoonRenderer:cleanupUnitFolderModels(unitsFolder: Instance)
	local validModels = {}
	local claimedIndices = {}

	for unitIndex, entry in self.unitEntries do
		if entry.Model and entry.Model.Parent then
			validModels[entry.Model] = true
			claimedIndices[unitIndex] = entry.Model
			self:setUnitModelAssignment(entry.Model, unitIndex, entry.Tier, false)
		end
	end

	for _, pool in self.unitPoolByTier do
		for _, model in pool do
			if model and model.Parent then
				validModels[model] = true
				self:setUnitModelVisible(model, false)
				self:setUnitModelAssignment(model, nil, tonumber(model:GetAttribute("UnitTier")), true)
			end
		end
	end

	for _, child in unitsFolder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end

		local unitIndex = tonumber(child:GetAttribute("UnitIndex"))
		local claimedModel = unitIndex and claimedIndices[unitIndex]
		if child:GetAttribute("Pooled") == true then
			self:setUnitModelVisible(child, false)
			continue
		end

		if not validModels[child] or (claimedModel and claimedModel ~= child) then
			self.unitModelInfo[child] = nil
			child:Destroy()
		end
	end
end

function TycoonRenderer:clearDrops()
	for orb, entry in self.activeOrbs do
		local container = if type(entry) == "table" then entry.Instance else orb
		if container and container.Parent then
			container:Destroy()
		end
	end
	table.clear(self.activeOrbs)

	for _, connection in self.dropTouchConnections do
		connection:Disconnect()
	end
	table.clear(self.dropTouchConnections)

	for orb in self.pickupAnimations do
		if orb.Parent then
			orb:Destroy()
		end
	end
	table.clear(self.pickupAnimations)
end

function TycoonRenderer:findDropPart(spotPart: BasePart): BasePart?
	local dropPart = spotPart:FindFirstChild("DropPart")
	if dropPart and dropPart:IsA("BasePart") then
		return dropPart
	end

	return spotPart
end

function TycoonRenderer:getMutationInterval(): number
	local mutationConfig = TycoonConfig.Mutations or {}
	return math.max(tonumber(mutationConfig.Interval) or DEFAULT_MUTATION_INTERVAL, 1)
end

function TycoonRenderer:getGoldMultipliers(): { number }
	local mutationConfig = TycoonConfig.Mutations or {}
	local goldConfig = mutationConfig.Gold or {}
	local multipliers = goldConfig.Multipliers
	if type(multipliers) ~= "table" or #multipliers <= 0 then
		return DEFAULT_GOLD_MULTIPLIERS
	end

	return multipliers
end

function TycoonRenderer:getRandomGoldMultiplier(): number
	local multipliers = self:getGoldMultipliers()
	return multipliers[math.random(1, #multipliers)] or 2
end

function TycoonRenderer:pruneActiveDrops(): number
	local activeDropCount = 0
	for orb in self.activeOrbs do
		if orb.Parent then
			activeDropCount += 1
		else
			self.activeOrbs[orb] = nil
			local touchConnection = self.dropTouchConnections[orb]
			if touchConnection then
				touchConnection:Disconnect()
				self.dropTouchConnections[orb] = nil
			end
		end
	end

	return activeDropCount
end

function TycoonRenderer:getWeightedMutationEntry()
	local mutationConfig = TycoonConfig.Mutations or {}
	local weightPower = tonumber(mutationConfig.BetterTierWeightPower) or DEFAULT_MUTATION_WEIGHT_POWER
	local candidates = {}
	local totalWeight = 0

	for _, entry in self.unitEntries do
		if not entry.Model or not entry.Model.Parent or not entry.DropPart then
			continue
		end

		local tier = math.max(entry.Tier or 1, 1)
		local weight = math.max(tier ^ weightPower, 1)
		totalWeight += weight
		table.insert(candidates, {
			Entry = entry,
			Weight = weight,
		})
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = math.random() * totalWeight
	local currentWeight = 0
	for _, candidate in candidates do
		currentWeight += candidate.Weight
		if roll <= currentWeight then
			return candidate.Entry
		end
	end

	return candidates[#candidates].Entry
end

function TycoonRenderer:registerPossibleDrop(pickupPart: BasePart, container: Instance, dropPart: BasePart?)
	if not self.isOwn or not pickupPart or not pickupPart.Parent then
		return
	end

	self:ensurePickupLoop()
	pickupPart:SetAttribute("IsPossibleDrop", true)
	pickupPart:SetAttribute("IsCapsule", true)
	pickupPart:SetAttribute("DropValue", nil)
	pickupPart:SetAttribute("Value", nil)

	self.activeOrbs[pickupPart] = {
		Instance = container,
		IsPossibleDrop = true,
		DropPart = dropPart,
	}
end

function TycoonRenderer:unregisterPossibleDrop(pickupPart: BasePart?)
	if not pickupPart then
		return
	end

	self.activeOrbs[pickupPart] = nil
	local touchConnection = self.dropTouchConnections[pickupPart]
	if touchConnection then
		touchConnection:Disconnect()
		self.dropTouchConnections[pickupPart] = nil
	end
end

function TycoonRenderer:pickupOrb(orb: BasePart)
	if orb:GetAttribute("IsCapsule") == true or orb:GetAttribute("IsPossibleDrop") == true then
		return
	end

	local entry = self.activeOrbs[orb]
	if not entry then
		return
	end

	self.activeOrbs[orb] = nil
	local touchConnection = self.dropTouchConnections[orb]
	if touchConnection then
		touchConnection:Disconnect()
		self.dropTouchConnections[orb] = nil
	end

	local value = tonumber(orb:GetAttribute("DropValue") or orb:GetAttribute("Value") or entry.Value) or 1
	local container = entry.Instance or orb
	local displayValue = value * self:getManaRewardMultiplier()
	SoundUtil.Pickup()
	self:showPickupBillboard(orb.Position, displayValue)
	self:animatePickupOrb(orb)

	if container ~= orb and container.Parent then
		task.delay(PICKUP_ANIMATION_TIME, function()
			if container.Parent then
				container:Destroy()
			end
		end)
	end

	if self.onPickup then
		self.onPickup(value)
	end
end

function TycoonRenderer:showPickupBillboard(position: Vector3, value: number)
	local template = getPickupTemplate()
	if not template then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "PickupPopupAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 1.25, 0))
	anchor.Parent = self:getDropsFolder()

	local popup = template:Clone()
	popup.Name = "PickupPopup"
	setFirstTextLabelText(popup, "+" .. FormatUtil.formatMana(value))
	preparePickupPopup(popup)
	fadeTextLabels(popup, 0)

	if popup:IsA("BillboardGui") then
		popup.Adornee = anchor
		popup.AlwaysOnTop = true
		popup.MaxDistance = 75
	end
	popup.Parent = anchor

	if popup:IsA("BillboardGui") then
		local startOffset = popup.StudsOffsetWorldSpace
		TweenService
			:Create(popup, TweenInfo.new(PICKUP_POPUP_LIFETIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				StudsOffsetWorldSpace = startOffset + Vector3.new(0, PICKUP_POPUP_RISE, 0),
			})
			:Play()
	else
		TweenService
			:Create(anchor, TweenInfo.new(PICKUP_POPUP_LIFETIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = anchor.Position + Vector3.new(0, PICKUP_POPUP_RISE, 0),
			})
			:Play()
	end

	task.delay(PICKUP_POPUP_LIFETIME, function()
		if not anchor.Parent or not popup.Parent then
			return
		end

		local fadeProgress = Instance.new("NumberValue")
		fadeProgress.Value = 0
		local connection = fadeProgress.Changed:Connect(function(valueNow)
			fadeTextLabels(popup, valueNow)
		end)

		local fadeTween = TweenService:Create(
			fadeProgress,
			TweenInfo.new(PICKUP_POPUP_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Value = 1,
			}
		)

		fadeTween:Play()
		fadeTween.Completed:Connect(function()
			connection:Disconnect()
			fadeProgress:Destroy()
			anchor:Destroy()
		end)
	end)
end

function TycoonRenderer:ensurePickupAnimationLoop()
	if self.pickupAnimationConnection then
		return
	end

	self.pickupAnimationConnection = RunService.Heartbeat:Connect(function()
		local root = self:getLocalRoot()
		local hasAnimations = false
		local now = os.clock()

		for orb, animation in self.pickupAnimations do
			if not orb.Parent or not root then
				self.pickupAnimations[orb] = nil
				orb:Destroy()
				continue
			end

			hasAnimations = true
			local alpha = math.clamp((now - animation.StartTime) / PICKUP_ANIMATION_TIME, 0, 1)
			local easedAlpha = 1 - (1 - alpha) ^ 3
			local endPosition = root.Position + Vector3.new(0, 0.5, 0)
			local pulse = math.sin(alpha * math.pi)

			orb.Position = quadraticBezier(animation.StartPosition, animation.ControlPosition, endPosition, easedAlpha)
			orb.Size = animation.StartSize:Lerp(Vector3.new(0.12, 0.12, 0.12), easedAlpha) * (1 + pulse * 0.22)
			orb.Transparency = easedAlpha * 0.45

			if alpha >= 1 then
				self.pickupAnimations[orb] = nil
				orb:Destroy()
			end
		end

		if not hasAnimations and self.pickupAnimationConnection then
			self.pickupAnimationConnection:Disconnect()
			self.pickupAnimationConnection = nil
		end
	end)
end

function TycoonRenderer:animatePickupOrb(orb: BasePart)
	local root = self:getLocalRoot()
	if not root then
		orb:Destroy()
		return
	end

	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false

	local startPosition = orb.Position
	self.pickupAnimations[orb] = {
		StartPosition = startPosition,
		StartSize = orb.Size,
		ControlPosition = startPosition:Lerp(root.Position, 0.45)
			+ Vector3.new(0, math.clamp((root.Position - startPosition).Magnitude * 0.45, 2.5, 7), 0),
		StartTime = os.clock(),
	}
	self:ensurePickupAnimationLoop()
end

function TycoonRenderer:getLocalRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function TycoonRenderer:ensurePickupLoop()
	if self.pickupConnection or not self.isOwn then
		return
	end

	self.pickupConnection = RunService.Heartbeat:Connect(function()
		local root = self:getLocalRoot()
		if not root then
			return
		end

		for orb in self.activeOrbs do
			if not orb.Parent then
				self.activeOrbs[orb] = nil
				continue
			end

			if (root.Position - orb.Position).Magnitude <= 3 or not self:isInsideDropBounds(orb.Position) then
				self:pickupOrb(orb)
			end
		end
	end)
end

function TycoonRenderer:setOnManaDropSpawned(handler: ((BasePart, (boolean) -> (), () -> boolean) -> ())?)
	self.onManaDropSpawned = handler
end

function TycoonRenderer:isLocalCharacterPart(part: BasePart): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil and part:IsDescendantOf(character)
end

function TycoonRenderer:spawnManaDrop(dropPart: BasePart, tier: number, value: number, skipPrune: boolean?): boolean
	if not self.isOwn then
		return false
	end

	if not skipPrune and self:pruneActiveDrops() >= MAX_ACTIVE_DROPS then
		return false
	end

	self:ensurePickupLoop()

	local dropsFolder = self:getDropsFolder()
	local template = getDropTemplate(tier)
	if not template then
		warn("[TycoonRenderer] No drop template found for tier:", tier)
		return false
	end

	local dropInstance = template:Clone()
	dropInstance.Name = "ManaDrop"
	dropInstance:SetAttribute("DropValue", value)
	dropInstance:SetAttribute("Value", value)

	local pickupPart = getFirstBasePart(dropInstance)
	if not pickupPart then
		dropInstance:Destroy()
		warn("[TycoonRenderer] Drop template has no BasePart:", template:GetFullName())
		return false
	end

	prepareDropPickup(dropInstance, pickupPart, value)

	if dropInstance:IsA("Model") then
		dropInstance:PivotTo(dropPart.CFrame + Vector3.new(0, 1.5, 0))
	elseif dropInstance:IsA("BasePart") then
		dropInstance.CFrame = dropPart.CFrame + Vector3.new(0, 1.5, 0)
	end

	dropInstance.Parent = dropsFolder
	pickupPart.AssemblyLinearVelocity = Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))

	self.activeOrbs[pickupPart] = {
		Value = value,
		Instance = dropInstance,
	}
	self.dropTouchConnections[pickupPart] = pickupPart.Touched:Connect(function(hit)
		if not self.activeOrbs[pickupPart] then
			return
		end

		if hit:GetAttribute("IsCapsule") == true or hit:GetAttribute("IsPossibleDrop") == true then
			return
		end

		if self:isLocalCharacterPart(hit) then
			self:pickupOrb(pickupPart)
			return
		end

		local autoCollect = self:getAutoCollectPart()
		if
			self.entitlements.AutoCollect
			and autoCollect
			and (hit == autoCollect or hit:IsDescendantOf(autoCollect))
		then
			self:pickupOrb(pickupPart)
		end
	end)

	return true
end

function TycoonRenderer:trySpawnManaDrop(dropPart: BasePart, tier: number, value: number, skipPrune: boolean?): boolean
	if not self.onManaDropSpawned then
		return self:spawnManaDrop(dropPart, tier, value, skipPrune)
	end

	local settled = false
	local spawnCapsule = false

	local function settle(replaced: boolean)
		if settled then
			return
		end

		settled = true
		spawnCapsule = replaced
	end

	self.onManaDropSpawned(dropPart, settle, function()
		return settled
	end)

	local deadline = os.clock() + 0.35
	while not settled and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end

	if not settled then
		settled = true
	end

	if spawnCapsule then
		return true
	end

	return self:spawnManaDrop(dropPart, tier, value, skipPrune)
end

function TycoonRenderer:spawnMutatedDrop(skipPrune: boolean?): boolean
	if not self.isOwn or (not skipPrune and self:pruneActiveDrops() >= MAX_ACTIVE_DROPS) then
		return false
	end

	self:ensurePickupLoop()

	local entry = self:getWeightedMutationEntry()
	if not entry then
		return false
	end

	local tierData = AnimeDroppers.Tiers[entry.Tier]
	if not tierData then
		return false
	end

	local template = getGoldDropTemplate()
	if not template then
		warn("[TycoonRenderer] No gold mutation drop template found")
		return false
	end

	local multiplier = self:getRandomGoldMultiplier()
	local baseValue = tierData.DropValue or 1
	local value = baseValue * multiplier
	local dropInstance = template:Clone()
	dropInstance.Name = "MutatedManaDrop"
	dropInstance:SetAttribute("DropValue", value)
	dropInstance:SetAttribute("Value", value)
	dropInstance:SetAttribute("Mutation", "Gold")
	dropInstance:SetAttribute("Multiplier", multiplier)
	dropInstance:SetAttribute("Tier", entry.Tier)
	setMutationLabel(dropInstance, multiplier, entry.Tier)

	local pickupPart = getFirstBasePart(dropInstance)
	if not pickupPart then
		dropInstance:Destroy()
		warn("[TycoonRenderer] Gold mutation drop template has no BasePart:", template:GetFullName())
		return false
	end

	prepareDropPickup(dropInstance, pickupPart, value)

	local spawnCFrame = entry.DropPart.CFrame + Vector3.new(0, 1.5, 0)
	if dropInstance:IsA("Model") then
		dropInstance:PivotTo(spawnCFrame)
	elseif dropInstance:IsA("BasePart") then
		dropInstance.CFrame = spawnCFrame
	end

	dropInstance.Parent = self:getDropsFolder()
	pickupPart.AssemblyLinearVelocity = Vector3.new(math.random(-2, 2), 4, math.random(-2, 2))

	self.activeOrbs[pickupPart] = {
		Value = value,
		Instance = dropInstance,
		Mutation = "Gold",
		Multiplier = multiplier,
		Tier = entry.Tier,
	}
	self.dropTouchConnections[pickupPart] = pickupPart.Touched:Connect(function(hit)
		if not self.activeOrbs[pickupPart] then
			return
		end

		if hit:GetAttribute("IsCapsule") == true or hit:GetAttribute("IsPossibleDrop") == true then
			return
		end

		if self:isLocalCharacterPart(hit) then
			self:pickupOrb(pickupPart)
			return
		end

		local autoCollect = self:getAutoCollectPart()
		if
			self.entitlements.AutoCollect
			and autoCollect
			and (hit == autoCollect or hit:IsDescendantOf(autoCollect))
		then
			self:pickupOrb(pickupPart)
		end
	end)

	return true
end

function TycoonRenderer:ensureDropLoop()
	if self.dropLoopConnection or not self.isOwn then
		return
	end

	self.nextMutationAt = os.clock() + self:getMutationInterval()
	self.dropLoopConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local interval = self:getDropInterval()
		local activeDropCount = self:pruneActiveDrops()
		local spawnBudget = math.max(MAX_ACTIVE_DROPS - activeDropCount, 0)
		local spawnedThisFrame = 0

		if now >= self.nextMutationAt then
			self.nextMutationAt += self:getMutationInterval()
			if self.nextMutationAt < now then
				self.nextMutationAt = now + self:getMutationInterval()
			end

			if spawnBudget > 0 and self:spawnMutatedDrop(true) then
				activeDropCount += 1
				spawnBudget -= 1
				spawnedThisFrame += 1
			end
		end

		if spawnBudget <= 0 or spawnedThisFrame >= MAX_DROP_SPAWNS_PER_FRAME then
			return
		end

		for unitIndex, entry in self.unitEntries do
			if spawnedThisFrame >= MAX_DROP_SPAWNS_PER_FRAME or spawnBudget <= 0 then
				break
			end

			if not entry.Model or not entry.Model.Parent or not entry.DropPart then
				continue
			end

			self:scheduleUnitDrop(entry, unitIndex, now)
			if entry.DropSpawnPending or now < (entry.NextDropAt or now + interval) then
				continue
			end

			local tierData = AnimeDroppers.Tiers[entry.Tier]
			if not tierData then
				entry.NextDropAt = now + interval
				continue
			end

			entry.DropSpawnPending = true
			entry.NextDropAt = now + interval

			if self:trySpawnManaDrop(entry.DropPart, entry.Tier, tierData.DropValue or 1, true) then
				spawnedThisFrame += 1
				activeDropCount += 1
				spawnBudget -= 1
			end

			entry.DropSpawnPending = false
		end
	end)
end

function TycoonRenderer:getSpotForUnitIndex(dropperHolder: Instance, unitIndex: number): BasePart?
	local cachedSpot = self.spotCache[unitIndex]
	if cachedSpot and cachedSpot.Parent then
		return cachedSpot
	end

	local floorIndex, spotIndex = Grid.getFloorAndSpot(unitIndex)
	local floorModel = getFloorModel(dropperHolder, floorIndex)
	if not floorModel then
		return nil
	end

	local spotPart = getSpotPart(floorModel, spotIndex)
	self.spotCache[unitIndex] = spotPart
	return spotPart
end

function TycoonRenderer:moveRenderedUnit(unitIndex: number, entry, spotPart: BasePart)
	entry.Model:PivotTo(spotPart.CFrame)
	entry.DropPart = self:findDropPart(spotPart)
	self:scheduleUnitDrop(entry, unitIndex, os.clock())
	self:setUnitModelVisible(entry.Model, true)
	self:setUnitModelAssignment(entry.Model, unitIndex, entry.Tier, false)

	self.unitEntries[unitIndex] = entry
	self.unitModels[unitIndex] = entry.Model
end

function TycoonRenderer:rebuild(units: { { Tier: number } })
	self.rebuildToken += 1
	local rebuildToken = self.rebuildToken
	self:updateAutoCollectPad()

	local sortedUnits = table.clone(units)
	table.sort(sortedUnits, function(left, right)
		if left.Slot and right.Slot and left.Slot ~= right.Slot then
			return left.Slot < right.Slot
		end

		return (left.Tier or 1) > (right.Tier or 1)
	end)

	self:ensureFloors(#sortedUnits)

	local dropperHolder = self:getDropperHolder()
	if not dropperHolder then
		return
	end

	local unitsFolder = self:getUnitsFolder()
	self:cleanupUnitFolderModels(unitsFolder)

	local unitsToSpawn = {}
	local unitsToMove = {}
	local unitsToDestroy = {}
	local reusableByTier = {}
	local renderOperationsThisBatch = 0

	local function queueRecycle(entry)
		if entry and entry.Model then
			table.insert(unitsToDestroy, entry)
		end
	end

	for unitIndex in self.unitEntries do
		if unitIndex > #sortedUnits then
			queueRecycle(self.unitEntries[unitIndex])
			self.unitEntries[unitIndex] = nil
			self.unitModels[unitIndex] = nil
		end
	end

	for unitIndex, unit in sortedUnits do
		local existingEntry = self.unitEntries[unitIndex]
		if existingEntry and existingEntry.Tier == unit.Tier and existingEntry.Model and existingEntry.Model.Parent then
			local spotPart = self:getSpotForUnitIndex(dropperHolder, unitIndex)
			if spotPart then
				table.insert(unitsToMove, {
					Index = unitIndex,
					Entry = existingEntry,
					SpotPart = spotPart,
				})
			end

			continue
		end

		if existingEntry then
			reusableByTier[existingEntry.Tier] = reusableByTier[existingEntry.Tier] or {}
			table.insert(reusableByTier[existingEntry.Tier], existingEntry)
			self.unitEntries[unitIndex] = nil
			self.unitModels[unitIndex] = nil
		end

		table.insert(unitsToSpawn, {
			Index = unitIndex,
			Tier = unit.Tier,
		})
	end

	local finalUnitsToSpawn = {}
	for _, spawnInfo in unitsToSpawn do
		local reusableEntries = reusableByTier[spawnInfo.Tier]
		local reusableEntry = reusableEntries and table.remove(reusableEntries)
		if reusableEntry and reusableEntry.Model and reusableEntry.Model.Parent then
			local spotPart = self:getSpotForUnitIndex(dropperHolder, spawnInfo.Index)
			if spotPart then
				table.insert(unitsToMove, {
					Index = spawnInfo.Index,
					Entry = reusableEntry,
					SpotPart = spotPart,
				})
				continue
			end
		end

		table.insert(finalUnitsToSpawn, spawnInfo)
	end

	for _, entries in reusableByTier do
		for _, entry in entries do
			queueRecycle(entry)
		end
	end

	self:ensureDropLoop()

	task.spawn(function()
		local function stepBatch()
			renderOperationsThisBatch += 1
			if renderOperationsThisBatch >= UNIT_RENDER_BATCH_SIZE then
				renderOperationsThisBatch = 0
				task.wait(UNIT_RENDER_BATCH_DELAY)
			end
		end

		for _, entry in unitsToDestroy do
			if rebuildToken ~= self.rebuildToken then
				return
			end

			self:recycleUnitEntry(entry)

			stepBatch()
		end

		for _, moveInfo in unitsToMove do
			if rebuildToken ~= self.rebuildToken then
				return
			end

			self:moveRenderedUnit(moveInfo.Index, moveInfo.Entry, moveInfo.SpotPart)
			stepBatch()
		end

		for _, spawnInfo in finalUnitsToSpawn do
			if rebuildToken ~= self.rebuildToken then
				return
			end

			local unitIndex = spawnInfo.Index
			local tier = spawnInfo.Tier
			local spotPart = self:getSpotForUnitIndex(dropperHolder, unitIndex)
			if not spotPart then
				continue
			end

			local unitModel = self:getOrCreateUnitModel(tier, unitIndex)
			if not unitModel then
				continue
			end

			unitModel:PivotTo(spotPart.CFrame)
			if unitModel.Parent ~= unitsFolder then
				unitModel.Parent = unitsFolder
			end
			self:setUnitModelAssignment(unitModel, unitIndex, tier, false)
			self:setUnitModelVisible(unitModel, true)

			self.unitModels[unitIndex] = unitModel

			local dropPart = self:findDropPart(spotPart)

			self.unitEntries[unitIndex] = {
				Model = unitModel,
				Tier = tier,
				DropPart = dropPart,
			}
			self:scheduleUnitDrop(self.unitEntries[unitIndex], unitIndex, os.clock())

			renderOperationsThisBatch += 1
			if renderOperationsThisBatch >= UNIT_SPAWN_BATCH_SIZE then
				renderOperationsThisBatch = 0
				task.wait(UNIT_SPAWN_BATCH_DELAY)
			end
		end
	end)
end

function TycoonRenderer:destroy()
	self:clearRenderedUnits()
	self:clearDrops()

	if self.pickupConnection then
		self.pickupConnection:Disconnect()
		self.pickupConnection = nil
	end

	if self.pickupAnimationConnection then
		self.pickupAnimationConnection:Disconnect()
		self.pickupAnimationConnection = nil
	end
	table.clear(self.pickupAnimations)

	if self.dropLoopConnection then
		self.dropLoopConnection:Disconnect()
		self.dropLoopConnection = nil
	end

	for _, connection in self.dropTouchConnections do
		connection:Disconnect()
	end
	table.clear(self.dropTouchConnections)
end

return TycoonRenderer
