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
local YenUpgrades = require(ReplicatedStorage.Shared.Data.YenUpgrades)

local TycoonRenderer = {}
TycoonRenderer.__index = TycoonRenderer

local DROP_INTERVAL = 6
local MAX_ACTIVE_DROPS = 150
local MAX_DROP_SPAWNS_PER_FRAME = 4
local DROP_MAX_FALL_SPEED = 26
local DROP_NEAR_FLOOR_HEIGHT = 5
local DROP_NEAR_FLOOR_MAX_SPEED = 5
local DROP_FLOOR_CLEARANCE = 0.08
local DROP_STAGGER_HASH = 0.61803398875
local PICKUP_ANIMATION_TIME = 0.42
local PICKUP_POPUP_LIFETIME = 0.72
local PICKUP_POPUP_RISE = 1.65
local PICKUP_POPUP_FADE_TIME = 0.16
local PICKUP_POPUP_SIZE = UDim2.fromOffset(280, 78)
local PICKUP_POPUP_TEXT_SIZE = 36
local UNIT_SPAWN_BATCH_SIZE = 8
local OTHER_UNIT_SPAWN_BATCH_SIZE = 3
local UNIT_SPAWN_BATCH_DELAY = 0.02
local OTHER_UNIT_SPAWN_BATCH_DELAY = 0.035
local UNIT_RENDER_BATCH_SIZE = 8
local OTHER_UNIT_RENDER_BATCH_SIZE = 4
local UNIT_RENDER_BATCH_DELAY = 0.02
local OTHER_UNIT_RENDER_BATCH_DELAY = 0.03
local UNIT_POOL_LIMIT_PER_TIER = 18
local OTHER_UNIT_POOL_LIMIT_PER_TIER = 80
local UNIT_DESTROY_BATCH_SIZE = 4
local UNIT_DESTROY_BATCH_DELAY = 0.03
local UNIT_POOL_CFRAME = CFrame.new(0, -10000, 0)
local UNIT_DROP_HOP_TOP_FLOORS_SKIPPED = 5
local UNIT_DROP_HOP_MAX_STARTS_PER_FRAME = 18
local UNIT_DROP_HOP_DURATION = 0.34
local UNIT_DROP_HOP_HEIGHT = 1.15
local PLAYER_COLLISION_GROUP = "PlayerCharacters"
local DROP_COLLISION_GROUP = "ManaDrops"
local DROP_WALL_COLLISION_GROUP = "DropWalls"
local CAPSULE_COLLISION_GROUP = "CapsuleDrops"
local DEFAULT_MUTATION_INTERVAL = 60
local DEFAULT_MUTATION_WEIGHT_POWER = 4
local DEFAULT_GOLD_MULTIPLIERS = { 2, 5, 10, 25, 100 }
local AUTO_COLLECT_RETRY_INTERVAL = 2
local AUTO_COLLECT_BIND_TIMEOUT = 30
local AUTO_COLLECT_BIND_POLL_INTERVAL = 0.25

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
	PhysicsService:RegisterCollisionGroup(CAPSULE_COLLISION_GROUP)
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
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, DROP_COLLISION_GROUP, false)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, CAPSULE_COLLISION_GROUP, false)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, DROP_WALL_COLLISION_GROUP, false)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CAPSULE_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
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

local function getDisplayRootForTycoon(tycoon: Instance): Instance?
	local display = tycoon:FindFirstChild("Display")
	if display then
		return display
	end

	local unitSpot = tycoon:FindFirstChild("UnitSpot", true)
	return if unitSpot then unitSpot.Parent else nil
end

local function getDisplayUnitSpotForTycoon(tycoon: Instance): Instance?
	local display = getDisplayRootForTycoon(tycoon)
	if not display then
		return nil
	end

	return display:FindFirstChild("UnitSpot", true)
end

local function clearHighestDisplayForTycoon(tycoon: Instance)
	local unitSpot = getDisplayUnitSpotForTycoon(tycoon)
	if unitSpot then
		for _, child in unitSpot:GetChildren() do
			if
				child:IsA("Model")
				and (child.Name == "HighestTierDisplayUnit" or child:GetAttribute("HighestTierDisplay") == true)
			then
				child:Destroy()
			end
		end
	end

	local display = getDisplayRootForTycoon(tycoon)
	if display then
		for _, descendant in display:GetDescendants() do
			if
				descendant:IsA("Model")
				and (
					descendant.Name == "HighestTierDisplayUnit"
					or descendant:GetAttribute("HighestTierDisplay") == true
				)
			then
				descendant:Destroy()
			end
		end
	end
end

local function clearTowerUnitsForTycoon(tycoon: Instance)
	local dropperHolder = tycoon:FindFirstChild("DropperHolder")
	if not dropperHolder then
		return
	end

	local unitsFolder = dropperHolder:FindFirstChild("Units")
	if not unitsFolder then
		return
	end

	for _, child in unitsFolder:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

local function removeExtraFloorsForTycoon(tycoon: Instance)
	local dropperHolder = tycoon:FindFirstChild("DropperHolder")
	if not dropperHolder then
		return
	end

	for _, child in dropperHolder:GetChildren() do
		if child.Name == "FirstLayerStuff" or child.Name == "AutoCollect" then
			continue
		end

		local floorIndex = string.match(child.Name, "^FloorLayer_(%d+)$")
		if floorIndex and tonumber(floorIndex) > 1 then
			child:Destroy()
		end
	end
end

local function clearTowerDropsForTycoon(tycoon: Instance)
	local dropperHolder = tycoon:FindFirstChild("DropperHolder")
	if not dropperHolder then
		return
	end

	for _, folderName in { "ManaDrops", "ManaPowerDrops", "MagicPowerDrops" } do
		local folder = dropperHolder:FindFirstChild(folderName)
		if folder then
			for _, child in folder:GetChildren() do
				child:Destroy()
			end
		end
	end
end

local function cleanupUnclaimedTycoonVisuals(tycoon: Instance)
	clearHighestDisplayForTycoon(tycoon)
	clearTowerUnitsForTycoon(tycoon)
	removeExtraFloorsForTycoon(tycoon)
	clearTowerDropsForTycoon(tycoon)
end

function TycoonRenderer.cleanupUnclaimedTycoon(tycoon: Instance)
	cleanupUnclaimedTycoonVisuals(tycoon)
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

local function getDropParts(container: Instance?, fallbackPart: BasePart): { BasePart }
	local parts = {}
	if container and container:IsA("BasePart") then
		table.insert(parts, container)
	end

	if container then
		for _, descendant in container:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	if #parts <= 0 then
		table.insert(parts, fallbackPart)
	end

	return parts
end

local function pivotDropContainer(
	container: Instance?,
	pickupPart: BasePart,
	targetCFrame: CFrame,
	pivotOffset: CFrame?
)
	if container and container:IsA("Model") then
		container:PivotTo(targetCFrame * (pivotOffset or CFrame.identity))
	elseif container and container:IsA("BasePart") then
		container.CFrame = targetCFrame
	else
		pickupPart.CFrame = targetCFrame
	end
end

local function setDropPhysics(part: BasePart, value: number)
	part.Anchored = false
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CollisionGroup = DROP_COLLISION_GROUP
	part:SetAttribute("DropValue", value)
	part:SetAttribute("Value", value)
	part.CustomPhysicalProperties = PhysicalProperties.new(0.25, 0.65, 0.05)
end

local function prepareDropPickup(dropInstance: Instance, pickupPart: BasePart, value: number)
	setDropPhysics(pickupPart, value)

	for _, descendant in dropInstance:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= pickupPart then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = false
			descendant.CollisionGroup = DROP_COLLISION_GROUP

			local weld = Instance.new("WeldConstraint")
			weld.Name = "DropAssemblyWeld"
			weld.Part0 = pickupPart
			weld.Part1 = descendant
			weld.Parent = pickupPart
		end
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
	self.pendingDestroyModels = {}
	self.destroyQueueRunning = false
	self.highestDisplayModel = nil
	self.highestDisplayTier = nil
	self.lastUnits = {}
	self.lastRenderSignature = nil
	self.renderedFloorCount = 0
	self.spotCache = {}
	self.rebuildToken = 0
	self.activeOrbs = {}
	self.dropTouchConnections = {}
	self.isOwn = false
	self.entitlements = {}
	self.dropsFolder = nil
	self.dropBounds = nil
	self.autoCollectRoot = nil
	self.autoCollectPart = nil
	self.autoCollectVisuals = nil
	self.autoCollectPadUpdateScheduled = false
	self.autoCollectBindStarted = false
	self.lastAutoCollectRetryAt = 0
	self.pickupConnection = nil
	self.pickupAnimationConnection = nil
	self.pickupAnimations = {}
	self.unitHopAnimations = {}
	self.unitHopQueue = {}
	self.unitHopLoopConnection = nil
	self.unitHopQueueRunning = false
	self.dropLoopConnection = nil
	self.onManaDropSpawned = nil
	self.nextMutationAt = os.clock()
		+ (TycoonConfig.Mutations and TycoonConfig.Mutations.Interval or DEFAULT_MUTATION_INTERVAL)
	if janitor then
		janitor:Add(tycoon.DescendantAdded:Connect(function(descendant)
			if
				descendant.Name == "DropperHolder"
				or descendant.Name == "AutoCollect"
				or descendant.Name == "FirstLayerStuff"
			then
				self:invalidateAutoCollectCache()
				self:scheduleAutoCollectPadUpdate()
			elseif
				self.autoCollectRoot
				and descendant:IsDescendantOf(self.autoCollectRoot)
				and (descendant:IsA("BasePart") or descendant:IsA("BillboardGui"))
			then
				self.autoCollectVisuals = nil
				self:scheduleAutoCollectPadUpdate()
			end

			if descendant.Name == "Display" or descendant.Name == "UnitSpot" then
				task.defer(function()
					if self.tycoon.Parent then
						self:updateHighestDisplayUnit(self.lastUnits or {}, true)
					end
				end)
			end
		end))
		janitor:Add(tycoon.DescendantRemoving:Connect(function(descendant)
			if descendant == self.autoCollectRoot or descendant == self.autoCollectPart then
				self:invalidateAutoCollectCache()
				self.autoCollectBindStarted = false
				self:beginAutoCollectPadBinding()
				self:scheduleAutoCollectPadUpdate()
			elseif self.autoCollectRoot and descendant:IsDescendantOf(self.autoCollectRoot) then
				self.autoCollectVisuals = nil
				self:scheduleAutoCollectPadUpdate()
			end
		end))
		janitor:Add(tycoon:GetAttributeChangedSignal("Claimed"):Connect(function()
			if tycoon:GetAttribute("Claimed") ~= true then
				self:resetTowerToEmpty()
			end
		end))
		janitor:Add(RunService.Heartbeat:Connect(function()
			if not self.isOwn then
				return
			end

			local now = os.clock()
			if now - self.lastAutoCollectRetryAt < AUTO_COLLECT_RETRY_INTERVAL then
				return
			end

			self.lastAutoCollectRetryAt = now
			if not self:getAutoCollectPart() then
				self:beginAutoCollectPadBinding()
			end
			self:updateAutoCollectPad()
		end))
	end

	self:beginAutoCollectPadBinding()
	return self
end

local function getUnitSignature(units: { { Tier: number } }): string
	local parts = table.create(#units)
	for index, unit in units do
		local tier = if type(unit) == "table" then math.floor(tonumber(unit.Tier) or 1) else 1
		local slot = if type(unit) == "table" then unit.Slot else nil
		parts[index] = tostring(tier) .. ":" .. tostring(slot or "")
	end

	return table.concat(parts, "|")
end

function TycoonRenderer:setIsOwn(isOwn: boolean)
	self.isOwn = isOwn
	if isOwn then
		self:beginAutoCollectPadBinding()
		self:scheduleAutoCollectPadUpdate()
	end
end

function TycoonRenderer:invalidateAutoCollectCache()
	self.autoCollectRoot = nil
	self.autoCollectPart = nil
	self.autoCollectVisuals = nil
end

function TycoonRenderer:resolveAutoCollectInstance(): Instance?
	local dropperHolder = self:getDropperHolder()
	if not dropperHolder then
		return nil
	end

	local firstLayerStuff = dropperHolder:FindFirstChild("FirstLayerStuff")
	if not firstLayerStuff then
		return nil
	end

	return firstLayerStuff:FindFirstChild("AutoCollect")
end

function TycoonRenderer:beginAutoCollectPadBinding()
	if self.autoCollectBindStarted then
		return
	end

	if self:resolveAutoCollectInstance() then
		self:scheduleAutoCollectPadUpdate()
		return
	end

	self.autoCollectBindStarted = true
	task.spawn(function()
		local deadline = os.clock() + AUTO_COLLECT_BIND_TIMEOUT

		while os.clock() < deadline do
			if not self.tycoon.Parent then
				self.autoCollectBindStarted = false
				return
			end

			if self:resolveAutoCollectInstance() then
				self:invalidateAutoCollectCache()
				self.autoCollectBindStarted = false
				self:scheduleAutoCollectPadUpdate()
				return
			end

			task.wait(AUTO_COLLECT_BIND_POLL_INTERVAL)
		end

		self.autoCollectBindStarted = false
	end)
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

function TycoonRenderer:scheduleAutoCollectPadUpdate()
	if self.autoCollectPadUpdateScheduled then
		return
	end

	self.autoCollectPadUpdateScheduled = true
	task.defer(function()
		self.autoCollectPadUpdateScheduled = false
		if self.tycoon.Parent then
			self:updateAutoCollectPad()
		end
	end)
end

function TycoonRenderer:getDropInterval(): number
	local multiplier = if self.entitlements.DoubleDropSpeed then 2 else 1
	multiplier *= math.max(tonumber(self.entitlements.DropSpeedMultiplier) or 1, 0.1)
	return DROP_INTERVAL / multiplier
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

function TycoonRenderer:shouldAnimateUnitDropHop(unitIndex: number): boolean
	if not self.isOwn then
		return false
	end

	local floorIndex = Grid.getFloorAndSpot(unitIndex)
	local renderedFloorCount = math.max(math.floor(tonumber(self.renderedFloorCount) or 0), 1)
	if
		renderedFloorCount > UNIT_DROP_HOP_TOP_FLOORS_SKIPPED
		and floorIndex > renderedFloorCount - UNIT_DROP_HOP_TOP_FLOORS_SKIPPED
	then
		return false
	end

	return true
end

function TycoonRenderer:clearUnitDropHop(model: Model?)
	if not model then
		return
	end

	local animation = self.unitHopAnimations[model]
	if animation then
		if model.Parent then
			model:PivotTo(animation.BaseCFrame)
		end
		self.unitHopAnimations[model] = nil
	end
end

function TycoonRenderer:clearUnitDropHops()
	for model in self.unitHopAnimations do
		self:clearUnitDropHop(model)
	end

	table.clear(self.unitHopAnimations)
	table.clear(self.unitHopQueue)
	self.unitHopQueueRunning = false
	if self.unitHopLoopConnection then
		self.unitHopLoopConnection:Disconnect()
		self.unitHopLoopConnection = nil
	end
end

function TycoonRenderer:ensureUnitHopLoop()
	if self.unitHopLoopConnection then
		return
	end

	self.unitHopLoopConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local hasActive = false

		for model, animation in self.unitHopAnimations do
			local entry = self.unitEntries[animation.UnitIndex]
			if not model.Parent or not entry or entry.Model ~= model then
				self.unitHopAnimations[model] = nil
				continue
			end

			local alpha = math.clamp((now - animation.StartedAt) / UNIT_DROP_HOP_DURATION, 0, 1)
			local offsetY = math.sin(alpha * math.pi) * UNIT_DROP_HOP_HEIGHT
			model:PivotTo(animation.BaseCFrame * CFrame.new(0, offsetY, 0))

			if alpha >= 1 then
				model:PivotTo(animation.BaseCFrame)
				self.unitHopAnimations[model] = nil
			else
				hasActive = true
			end
		end

		if not hasActive and next(self.unitHopAnimations) == nil and #self.unitHopQueue <= 0 then
			self.unitHopLoopConnection:Disconnect()
			self.unitHopLoopConnection = nil
		end
	end)
end

function TycoonRenderer:flushUnitHopQueue()
	if self.unitHopQueueRunning then
		return
	end

	self.unitHopQueueRunning = true
	task.spawn(function()
		local readIndex = 1
		while readIndex <= #self.unitHopQueue do
			local started = 0
			local now = os.clock()

			while started < UNIT_DROP_HOP_MAX_STARTS_PER_FRAME and readIndex <= #self.unitHopQueue do
				local request = self.unitHopQueue[readIndex]
				readIndex += 1

				local entry = self.unitEntries[request.UnitIndex]
				local model = request.Model
				if model and model.Parent and entry and entry.Model == model then
					local active = self.unitHopAnimations[model]
					local baseCFrame = if active then active.BaseCFrame else model:GetPivot()
					self.unitHopAnimations[model] = {
						BaseCFrame = baseCFrame,
						StartedAt = now,
						UnitIndex = request.UnitIndex,
					}
					started += 1
				end
			end

			if started > 0 then
				self:ensureUnitHopLoop()
			end

			if readIndex <= #self.unitHopQueue then
				RunService.Heartbeat:Wait()
			end
		end

		table.clear(self.unitHopQueue)
		self.unitHopQueueRunning = false
	end)
end

function TycoonRenderer:playUnitDropHop(entry, unitIndex: number)
	if not entry or not entry.Model or not self:shouldAnimateUnitDropHop(unitIndex) then
		return
	end

	table.insert(self.unitHopQueue, {
		Model = entry.Model,
		UnitIndex = unitIndex,
	})
	self:flushUnitHopQueue()
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
	if
		self.autoCollectPart
		and self.autoCollectPart.Parent
		and self.autoCollectRoot
		and self.autoCollectRoot.Parent
	then
		return self.autoCollectPart
	end

	self:invalidateAutoCollectCache()

	local autoCollect = self:resolveAutoCollectInstance()
	if not autoCollect then
		return nil
	end

	local autoCollectPart = if autoCollect:IsA("BasePart") then autoCollect else getFirstBasePart(autoCollect)
	if not autoCollectPart then
		return nil
	end

	self.autoCollectRoot = autoCollect
	self.autoCollectPart = autoCollectPart
	return autoCollectPart
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

		local visualRoot = self.autoCollectRoot or autoCollect
		if visualRoot:IsA("BasePart") then
			table.insert(visuals.Parts, visualRoot)
		end

		for _, descendant in visualRoot:GetDescendants() do
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

function TycoonRenderer:getDropFloorY(pickupPart: BasePart): number
	local bounds = self:getDropBounds()
	if bounds then
		return bounds.Position.Y - bounds.Size.Y * 0.5 + pickupPart.Size.Y * 0.5 + DROP_FLOOR_CLEARANCE
	end

	return pickupPart.Position.Y - 24
end

function TycoonRenderer:isPointInsidePart(part: BasePart, position: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

function TycoonRenderer:limitDropFallSpeed(orb: BasePart, entry)
	if type(entry) ~= "table" or entry.IsPossibleDrop or orb:GetAttribute("IsCapsule") == true then
		return
	end

	local velocity = orb.AssemblyLinearVelocity
	local downwardSpeed = -velocity.Y
	if downwardSpeed <= 0 then
		return
	end

	local maxFallSpeed = DROP_MAX_FALL_SPEED
	local floorY = entry.FloorY or self:getDropFloorY(orb)
	if orb.Position.Y - floorY <= DROP_NEAR_FLOOR_HEIGHT then
		maxFallSpeed = DROP_NEAR_FLOOR_MAX_SPEED
	end

	if downwardSpeed > maxFallSpeed then
		orb.AssemblyLinearVelocity = Vector3.new(velocity.X, -maxFallSpeed, velocity.Z)
	end
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
		if child.Name == "FirstLayerStuff" or child.Name == "AutoCollect" then
			continue
		end

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

function TycoonRenderer:resetTowerToEmpty()
	self.rebuildToken += 1
	self:clearRenderedUnits()
	self:ensureFloors(0)
	self:clearDrops()
	cleanupUnclaimedTycoonVisuals(self.tycoon)
	self.lastUnits = {}
	table.clear(self.spotCache)
end

function TycoonRenderer:clearRenderedUnits()
	self.rebuildToken += 1
	self:clearHighestDisplayUnit()
	self:clearUnitDropHops()

	for _, entry in self.unitEntries do
		if entry.Model then
			self:destroyUnitModelNow(entry.Model)
		end
	end
	table.clear(self.unitModels)
	table.clear(self.unitEntries)

	for _, pool in self.unitPoolByTier do
		for _, model in pool do
			self:destroyUnitModelNow(model)
		end
	end
	table.clear(self.unitPoolByTier)

	for _, model in self.pendingDestroyModels do
		self:destroyUnitModelNow(model)
	end
	table.clear(self.pendingDestroyModels)
	self.destroyQueueRunning = false
	table.clear(self.unitModelInfo)
	self.lastRenderSignature = nil
	self.renderedFloorCount = 0

	local unitsFolder = self:getUnitsFolder()
	for _, child in unitsFolder:GetChildren() do
		if child:IsA("Model") then
			self:destroyUnitModelNow(child)
		end
	end
end

function TycoonRenderer:getDisplayRoot(): Instance?
	local display = self.tycoon:FindFirstChild("Display")
	if display then
		return display
	end

	local unitSpot = self.tycoon:FindFirstChild("UnitSpot", true)
	return if unitSpot then unitSpot.Parent else nil
end

function TycoonRenderer:getDisplayUnitSpot(): Instance?
	local display = self:getDisplayRoot()
	if not display then
		return nil
	end

	return display:FindFirstChild("UnitSpot", true)
end

function TycoonRenderer:getDisplayUnitSpotCFrame(unitSpot: Instance): CFrame?
	if unitSpot:IsA("BasePart") then
		return unitSpot.CFrame
	end

	if unitSpot:IsA("Model") then
		return unitSpot:GetPivot()
	end

	local spotPart = unitSpot:FindFirstChildWhichIsA("BasePart", true)
	return if spotPart then spotPart.CFrame else nil
end

function TycoonRenderer:clearHighestDisplayUnit()
	if self.highestDisplayModel then
		self.unitModelInfo[self.highestDisplayModel] = nil
		self.highestDisplayModel:Destroy()
		self.highestDisplayModel = nil
	end

	local unitSpot = self:getDisplayUnitSpot()
	if unitSpot then
		for _, child in unitSpot:GetChildren() do
			if
				child:IsA("Model")
				and (child.Name == "HighestTierDisplayUnit" or child:GetAttribute("HighestTierDisplay") == true)
			then
				self.unitModelInfo[child] = nil
				child:Destroy()
			end
		end
	end

	local display = self:getDisplayRoot()
	if display then
		for _, descendant in display:GetDescendants() do
			if
				descendant:IsA("Model")
				and descendant ~= self.highestDisplayModel
				and (
					descendant.Name == "HighestTierDisplayUnit"
					or descendant:GetAttribute("HighestTierDisplay") == true
				)
			then
				self.unitModelInfo[descendant] = nil
				descendant:Destroy()
			end
		end
	end

	self.highestDisplayTier = nil
end

function TycoonRenderer:getHighestUnitTier(units: { { Tier: number } }): number?
	local highestTier: number? = nil
	for _, unit in units do
		if type(unit) ~= "table" then
			continue
		end

		local tier = math.clamp(math.floor(tonumber(unit.Tier) or 0), 1, AnimeDroppers.MaxTier)
		if AnimeDroppers.Tiers[tier] and (not highestTier or tier > highestTier) then
			highestTier = tier
		end
	end

	return highestTier
end

function TycoonRenderer:updateHighestDisplayUnit(units: { { Tier: number } }, forceReplace: boolean?)
	local unitSpot = self:getDisplayUnitSpot()
	if not unitSpot then
		self:clearHighestDisplayUnit()
		warn("[TycoonRenderer] Display.UnitSpot missing for highest unit display:", self.tycoon:GetFullName())
		return
	end

	local spotCFrame = self:getDisplayUnitSpotCFrame(unitSpot)
	if not spotCFrame then
		self:clearHighestDisplayUnit()
		warn("[TycoonRenderer] UnitSpot has no BasePart/Pivot for highest unit display:", unitSpot:GetFullName())
		return
	end

	local highestTier = self:getHighestUnitTier(units)
	if not highestTier then
		self:clearHighestDisplayUnit()
		return
	end

	if
		not forceReplace
		and self.highestDisplayModel
		and self.highestDisplayModel.Parent
		and self.highestDisplayTier == highestTier
	then
		if self.highestDisplayModel.Parent ~= unitSpot then
			self.highestDisplayModel.Parent = unitSpot
		end
		self.highestDisplayModel:PivotTo(spotCFrame)
		return
	end

	self:clearHighestDisplayUnit()

	local template = self:getUnitTemplate(highestTier)
	if not template then
		warn("[TycoonRenderer] Missing highest unit template for tier:", highestTier)
		return
	end

	local displayModel = template:Clone()
	displayModel.Name = "HighestTierDisplayUnit"
	displayModel:SetAttribute("HighestTierDisplay", true)
	displayModel:SetAttribute("UnitTier", highestTier)
	anchorModel(displayModel)
	for _, descendant in displayModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	self:getUnitModelInfo(displayModel)
	self:setUnitModelVisible(displayModel, true)
	displayModel.Parent = unitSpot
	displayModel:PivotTo(spotCFrame)

	self.highestDisplayModel = displayModel
	self.highestDisplayTier = highestTier
end

function TycoonRenderer:scheduleHighestDisplayRefresh()
	local delays = { 0.1, 0.5, 1.5 }
	for _, delayTime in delays do
		task.delay(delayTime, function()
			if self.tycoon.Parent then
				self:updateHighestDisplayUnit(self.lastUnits or {})
			end
		end)
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

function TycoonRenderer:getUnitPoolLimit(): number
	return if self.isOwn then UNIT_POOL_LIMIT_PER_TIER else OTHER_UNIT_POOL_LIMIT_PER_TIER
end

function TycoonRenderer:getUnitSpawnBatchSize(): number
	return if self.isOwn then UNIT_SPAWN_BATCH_SIZE else OTHER_UNIT_SPAWN_BATCH_SIZE
end

function TycoonRenderer:getUnitSpawnBatchDelay(): number
	return if self.isOwn then UNIT_SPAWN_BATCH_DELAY else OTHER_UNIT_SPAWN_BATCH_DELAY
end

function TycoonRenderer:getUnitRenderBatchSize(): number
	return if self.isOwn then UNIT_RENDER_BATCH_SIZE else OTHER_UNIT_RENDER_BATCH_SIZE
end

function TycoonRenderer:getUnitRenderBatchDelay(): number
	return if self.isOwn then UNIT_RENDER_BATCH_DELAY else OTHER_UNIT_RENDER_BATCH_DELAY
end

function TycoonRenderer:destroyUnitModelNow(model: Model?)
	if not model then
		return
	end

	self.unitModelInfo[model] = nil
	if model.Parent then
		model:Destroy()
	end
end

function TycoonRenderer:queueDestroyUnitModel(model: Model?)
	if not model or model:GetAttribute("QueuedDestroy") == true then
		return
	end

	self:clearUnitDropHop(model)
	model:SetAttribute("QueuedDestroy", true)
	self:setUnitModelVisible(model, false)
	self:setUnitModelAssignment(model, nil, tonumber(model:GetAttribute("UnitTier")), true)
	model:PivotTo(UNIT_POOL_CFRAME)
	table.insert(self.pendingDestroyModels, model)

	if self.destroyQueueRunning then
		return
	end

	self.destroyQueueRunning = true
	task.spawn(function()
		while #self.pendingDestroyModels > 0 do
			for _ = 1, UNIT_DESTROY_BATCH_SIZE do
				local queuedModel = table.remove(self.pendingDestroyModels)
				if not queuedModel then
					break
				end

				self:destroyUnitModelNow(queuedModel)
			end

			if #self.pendingDestroyModels > 0 then
				task.wait(UNIT_DESTROY_BATCH_DELAY)
			end
		end

		self.destroyQueueRunning = false
	end)
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

	if #pool >= self:getUnitPoolLimit() then
		self:queueDestroyUnitModel(entry.Model)
		return
	end

	self:clearUnitDropHop(entry.Model)
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
			self:queueDestroyUnitModel(child)
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

	clearTowerDropsForTycoon(self.tycoon)
end

local function findNamedBasePart(root: Instance, targetName: string): BasePart?
	local lowerTarget = string.lower(targetName)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and string.lower(descendant.Name) == lowerTarget then
			return descendant
		end
	end

	return nil
end

function TycoonRenderer:findDropPart(spotPart: BasePart, unitModel: Model?): BasePart?
	if unitModel and unitModel.Parent then
		local unitDropPart = findNamedBasePart(unitModel, "DropPart") or findNamedBasePart(unitModel, "Droppart")
		if unitDropPart then
			return unitDropPart
		end
	end

	local dropPart = spotPart:FindFirstChild("DropPart") or spotPart:FindFirstChild("Droppart")
	if dropPart and dropPart:IsA("BasePart") then
		return dropPart
	end

	local nestedDropPart = findNamedBasePart(spotPart, "DropPart") or findNamedBasePart(spotPart, "Droppart")
	return nestedDropPart or spotPart
end

function TycoonRenderer:getMutationInterval(): number
	local mutationConfig = TycoonConfig.Mutations or {}
	return math.max(tonumber(mutationConfig.Interval) or DEFAULT_MUTATION_INTERVAL, 1)
end

function TycoonRenderer:getGoldMultipliers(): { number }
	local level = math.max(math.floor(tonumber(self.entitlements.GoldenDropsLevel) or 0), 0)
	local multipliers = YenUpgrades.getUnlockedGoldMultipliers(level)
	if #multipliers <= 0 then
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

	if self.entitlements.ShowVFX == false then
		if container.Parent then
			container:Destroy()
		elseif orb.Parent then
			orb:Destroy()
		end

		if self.onPickup then
			self.onPickup(value)
		end

		return
	end

	self:animatePickupOrb(orb, container)

	if self.onPickup then
		self.onPickup(value)
	end
end

function TycoonRenderer:registerManaDrop(
	pickupPart: BasePart,
	dropInstance: Instance,
	value: number,
	velocity: Vector3,
	extra: { [string]: any }?
)
	local entry = extra or {}
	entry.Value = value
	entry.Instance = dropInstance
	entry.FloorY = self:getDropFloorY(pickupPart)

	self.activeOrbs[pickupPart] = entry
	pickupPart.AssemblyLinearVelocity = velocity
end

function TycoonRenderer:showPickupBillboard(position: Vector3, value: number)
	if self.entitlements.ShowManaPopup == false then
		return
	end

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
	setFirstTextLabelText(popup, "+" .. FormatUtil.formatRoundedMana(value))
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
				local container = animation.Container
				if container and container.Parent then
					container:Destroy()
				else
					orb:Destroy()
				end
				continue
			end

			hasAnimations = true
			local alpha = math.clamp((now - animation.StartTime) / PICKUP_ANIMATION_TIME, 0, 1)
			local easedAlpha = 1 - (1 - alpha) ^ 3
			local endPosition = root.Position + Vector3.new(0, 0.5, 0)
			local pulse = math.sin(alpha * math.pi)

			local position =
				quadraticBezier(animation.StartPosition, animation.ControlPosition, endPosition, easedAlpha)
			local rotation = animation.StartCFrame - animation.StartCFrame.Position
			pivotDropContainer(animation.Container, orb, CFrame.new(position) * rotation, animation.PivotOffset)

			local scaleAlpha = (1 - easedAlpha) * (1 + pulse * 0.22)
			for _, partInfo in animation.Parts do
				local part = partInfo.Part
				if not part.Parent then
					continue
				end

				part.Size = partInfo.StartSize:Lerp(partInfo.TargetSize, easedAlpha) * (1 + pulse * 0.22)
				part.Transparency =
					math.clamp(partInfo.StartTransparency + (0.9 - partInfo.StartTransparency) * easedAlpha, 0, 1)
				if scaleAlpha <= 0.02 then
					part.Transparency = 1
				end
			end

			if alpha >= 1 then
				self.pickupAnimations[orb] = nil
				local container = animation.Container
				if container and container.Parent then
					container:Destroy()
				else
					orb:Destroy()
				end
			end
		end

		if not hasAnimations and self.pickupAnimationConnection then
			self.pickupAnimationConnection:Disconnect()
			self.pickupAnimationConnection = nil
		end
	end)
end

function TycoonRenderer:animatePickupOrb(orb: BasePart, container: Instance?)
	local root = self:getLocalRoot()
	if not root then
		if container and container.Parent then
			container:Destroy()
		else
			orb:Destroy()
		end
		return
	end

	local animatedParts = {}
	for _, part in getDropParts(container, orb) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		table.insert(animatedParts, {
			Part = part,
			StartSize = part.Size,
			TargetSize = Vector3.new(
				math.max(part.Size.X * 0.16, 0.08),
				math.max(part.Size.Y * 0.16, 0.08),
				math.max(part.Size.Z * 0.16, 0.08)
			),
			StartTransparency = part.Transparency,
		})
	end

	local startPosition = orb.Position
	self.pickupAnimations[orb] = {
		Container = container or orb,
		Parts = animatedParts,
		StartCFrame = orb.CFrame,
		PivotOffset = if container and container:IsA("Model")
			then orb.CFrame:Inverse() * container:GetPivot()
			else CFrame.identity,
		StartPosition = startPosition,
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

	self.pickupConnection = RunService.Heartbeat:Connect(function(deltaTime)
		local root = self:getLocalRoot()
		local autoCollect = self.entitlements.AutoCollect and self:getAutoCollectPart() or nil

		for orb, entry in self.activeOrbs do
			if not orb.Parent then
				self.activeOrbs[orb] = nil
				continue
			end

			self:limitDropFallSpeed(orb, entry)

			local pickupRangeMultiplier = math.max(tonumber(self.entitlements.PickupRangeMultiplier) or 1, 1)
			local pickedByPlayer = root ~= nil and (root.Position - orb.Position).Magnitude <= 3 * pickupRangeMultiplier
			local pickedByAutoCollect = autoCollect ~= nil and self:isPointInsidePart(autoCollect, orb.Position)
			if pickedByPlayer or pickedByAutoCollect or not self:isInsideDropBounds(orb.Position) then
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
	self:registerManaDrop(pickupPart, dropInstance, value, Vector3.new(math.random(-2, 2), 3, math.random(-2, 2)))

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
	self:registerManaDrop(pickupPart, dropInstance, value, Vector3.new(math.random(-2, 2), 4, math.random(-2, 2)), {
		Mutation = "Gold",
		Multiplier = multiplier,
		Tier = entry.Tier,
	})

	return true
end

function TycoonRenderer:spawnMutatedDrops(count: number): number
	count = math.max(math.floor(tonumber(count) or 0), 0)
	if count <= 0 or not self.isOwn then
		return 0
	end

	local spawned = 0
	for _ = 1, count do
		if self:spawnMutatedDrop(true) then
			spawned += 1
		end
	end

	return spawned
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
				self:playUnitDropHop(entry, unitIndex)
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
	self:clearUnitDropHop(entry.Model)
	entry.Model:PivotTo(spotPart.CFrame)
	entry.DropPart = self:findDropPart(spotPart, entry.Model)
	self:scheduleUnitDrop(entry, unitIndex, os.clock())
	self:setUnitModelVisible(entry.Model, true)
	self:setUnitModelAssignment(entry.Model, unitIndex, entry.Tier, false)

	self.unitEntries[unitIndex] = entry
	self.unitModels[unitIndex] = entry.Model
end

function TycoonRenderer:rebuild(units: { { Tier: number } })
	self.lastUnits = units or {}
	self:updateAutoCollectPad()
	self:updateHighestDisplayUnit(self.lastUnits)

	local sortedUnits = table.clone(self.lastUnits)
	table.sort(sortedUnits, function(left, right)
		if left.Slot and right.Slot and left.Slot ~= right.Slot then
			return left.Slot < right.Slot
		end

		return (left.Tier or 1) > (right.Tier or 1)
	end)

	local renderCapacity = math.max(TycoonConfig.SpotsPerFloor * TycoonConfig.MaxFloors, 1)
	local visibleUnits = {}
	for unitIndex = 1, math.min(#sortedUnits, renderCapacity) do
		visibleUnits[unitIndex] = sortedUnits[unitIndex]
	end
	self.renderedFloorCount = Grid.requiredFloors(#visibleUnits)

	local nextRenderSignature = getUnitSignature(visibleUnits)
	if nextRenderSignature == self.lastRenderSignature then
		self:ensureDropLoop()
		self:scheduleHighestDisplayRefresh()
		return
	end

	self.lastRenderSignature = nextRenderSignature
	self.rebuildToken += 1
	local rebuildToken = self.rebuildToken
	self:scheduleHighestDisplayRefresh()

	self:ensureFloors(#visibleUnits)

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
		if unitIndex > #visibleUnits then
			queueRecycle(self.unitEntries[unitIndex])
			self.unitEntries[unitIndex] = nil
			self.unitModels[unitIndex] = nil
		end
	end

	for unitIndex, unit in visibleUnits do
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
		local renderBatchSize = self:getUnitRenderBatchSize()
		local renderBatchDelay = self:getUnitRenderBatchDelay()
		local spawnBatchSize = self:getUnitSpawnBatchSize()
		local spawnBatchDelay = self:getUnitSpawnBatchDelay()

		local function stepBatch()
			renderOperationsThisBatch += 1
			if renderOperationsThisBatch >= renderBatchSize then
				renderOperationsThisBatch = 0
				task.wait(renderBatchDelay)
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

			self:clearUnitDropHop(unitModel)
			unitModel:PivotTo(spotPart.CFrame)
			if unitModel.Parent ~= unitsFolder then
				unitModel.Parent = unitsFolder
			end
			self:setUnitModelAssignment(unitModel, unitIndex, tier, false)
			self:setUnitModelVisible(unitModel, true)

			self.unitModels[unitIndex] = unitModel

			local dropPart = self:findDropPart(spotPart, unitModel)

			self.unitEntries[unitIndex] = {
				Model = unitModel,
				Tier = tier,
				DropPart = dropPart,
			}
			self:scheduleUnitDrop(self.unitEntries[unitIndex], unitIndex, os.clock())

			renderOperationsThisBatch += 1
			if renderOperationsThisBatch >= spawnBatchSize then
				renderOperationsThisBatch = 0
				task.wait(spawnBatchDelay)
			end
		end
	end)
end

function TycoonRenderer:destroy()
	self:resetTowerToEmpty()
	self:clearUnitDropHops()

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
