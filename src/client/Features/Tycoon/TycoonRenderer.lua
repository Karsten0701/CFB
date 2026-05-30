local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local Grid = require(ReplicatedStorage.Shared.Features.Tycoon.Grid)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)

local TycoonRenderer = {}
TycoonRenderer.__index = TycoonRenderer

local DROP_INTERVAL = 5
local DOUBLE_DROP_SPEED_INTERVAL = 2.5
local MAX_ACTIVE_DROPS = 200
local PICKUP_ANIMATION_TIME = 0.42
local UNIT_SPAWN_BATCH_SIZE = 5
local UNIT_SPAWN_BATCH_DELAY = 0.1

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

local function quadraticBezier(startPosition: Vector3, controlPosition: Vector3, endPosition: Vector3, alpha: number): Vector3
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
	self.dropThreads = {}
	self.rebuildToken = 0
	self.activeOrbs = {}
	self.isOwn = true
	self.entitlements = {}
	self.dropsFolder = nil
	self.pickupConnection = nil
	return self
end

function TycoonRenderer:setIsOwn(isOwn: boolean)
	self.isOwn = isOwn
end

function TycoonRenderer:setEntitlements(entitlements: { [string]: boolean })
	self.entitlements = entitlements or {}
end

function TycoonRenderer:getDropInterval(): number
	return if self.entitlements.DoubleDropSpeed then DOUBLE_DROP_SPEED_INTERVAL else DROP_INTERVAL
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

	for floorIndex = 2, required do
		local floorName = "FloorLayer_" .. floorIndex
		local floor = dropperHolder:FindFirstChild(floorName)
		if not floor then
			floor = template:Clone()
			floor.Name = floorName
			local yOffset = TycoonConfig.FloorYOffset * (floorIndex - 1)
			floor:PivotTo(template:GetPivot() * CFrame.new(0, yOffset, 0))
			floor.Parent = dropperHolder
		end
	end

	for _, child in dropperHolder:GetChildren() do
		local floorIndex = string.match(child.Name, "^FloorLayer_(%d+)$")
		if floorIndex and tonumber(floorIndex) > required then
			child:Destroy()
		end
	end
end

function TycoonRenderer:clearRenderedUnits()
	self.rebuildToken += 1

	for _, entry in self.unitEntries do
		if entry.Thread then
			task.cancel(entry.Thread)
		end

		if entry.Model and entry.Model.Parent then
			entry.Model:Destroy()
		end
	end
	table.clear(self.unitModels)
	table.clear(self.unitEntries)
	table.clear(self.dropThreads)
end

function TycoonRenderer:removeRenderedUnit(unitIndex: number)
	local entry = self.unitEntries[unitIndex]
	if not entry then
		return
	end

	if entry.Thread then
		task.cancel(entry.Thread)
	end

	if entry.Model and entry.Model.Parent then
		entry.Model:Destroy()
	end

	self.unitEntries[unitIndex] = nil
	self.unitModels[unitIndex] = nil
end

function TycoonRenderer:clearDrops()
	for orb in self.activeOrbs do
		if orb and orb.Parent then
			orb:Destroy()
		end
	end
	table.clear(self.activeOrbs)
end

function TycoonRenderer:findDropPart(spotPart: BasePart): BasePart?
	local dropPart = spotPart:FindFirstChild("DropPart")
	if dropPart and dropPart:IsA("BasePart") then
		return dropPart
	end

	return spotPart
end

function TycoonRenderer:pickupOrb(orb: BasePart, value: number)
	if not self.activeOrbs[orb] then
		return
	end

	self.activeOrbs[orb] = nil
	local displayValue = if self.entitlements.DoubleMana then value * 2 else value
	self:showPickupBillboard(orb.Position, displayValue)
	self:animatePickupOrb(orb)

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
	setFirstTextLabelText(popup, "+" .. tostring(value))
	fadeTextLabels(popup, 0)

	if popup:IsA("BillboardGui") then
		popup.Adornee = anchor
	end
	popup.Parent = anchor

	local moveTween = TweenService:Create(anchor, TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, 1.8, 0),
	})
	moveTween:Play()

	task.delay(0.25, function()
		if not anchor.Parent then
			return
		end

		local fadeProgress = Instance.new("NumberValue")
		fadeProgress.Value = 0
		local connection = fadeProgress.Changed:Connect(function(valueNow)
			fadeTextLabels(popup, valueNow)
		end)

		local fadeTween = TweenService:Create(fadeProgress, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Value = 1,
		})
		fadeTween:Play()
		fadeTween.Completed:Connect(function()
			connection:Disconnect()
			fadeProgress:Destroy()
			anchor:Destroy()
		end)
	end)
end

function TycoonRenderer:animatePickupOrb(orb: BasePart)
	local root = self:getLocalRoot()
	if not root then
		orb:Destroy()
		return
	end

	local startPosition = orb.Position
	local startSize = orb.Size
	local controlPosition = startPosition:Lerp(root.Position, 0.45) + Vector3.new(0, math.clamp((root.Position - startPosition).Magnitude * 0.45, 2.5, 7), 0)
	local startTime = os.clock()

	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false

	local connection: RBXScriptConnection?
	connection = RunService.Heartbeat:Connect(function()
		if not orb.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local alpha = math.clamp((os.clock() - startTime) / PICKUP_ANIMATION_TIME, 0, 1)
		local easedAlpha = 1 - (1 - alpha) ^ 3
		local endPosition = root.Position + Vector3.new(0, 0.5, 0)
		local pulse = math.sin(alpha * math.pi)

		orb.Position = quadraticBezier(startPosition, controlPosition, endPosition, easedAlpha)
		orb.Size = startSize:Lerp(Vector3.new(0.12, 0.12, 0.12), easedAlpha) * (1 + pulse * 0.22)
		orb.Transparency = easedAlpha * 0.45

		if alpha >= 1 then
			if connection then
				connection:Disconnect()
			end
			orb:Destroy()
		end
	end)
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

		for orb, value in self.activeOrbs do
			if not orb.Parent then
				self.activeOrbs[orb] = nil
				continue
			end

			if self.entitlements.AutoCollect or (root.Position - orb.Position).Magnitude <= 3 then
				self:pickupOrb(orb, value)
			end
		end
	end)
end

function TycoonRenderer:spawnManaDrop(dropPart: BasePart, value: number)
	if not self.isOwn then
		return
	end

	local activeDropCount = 0
	for orb in self.activeOrbs do
		if orb.Parent then
			activeDropCount += 1
		else
			self.activeOrbs[orb] = nil
		end
	end

	if activeDropCount >= MAX_ACTIVE_DROPS then
		return
	end

	self:ensurePickupLoop()

	local dropsFolder = self:getDropsFolder()

	local sphere = Instance.new("Part")
	sphere.Name = "ManaDrop"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(1, 1, 1)
	sphere.Material = Enum.Material.Neon
	sphere.Color = Color3.fromRGB(120, 80, 255)
	sphere.Anchored = false
	sphere.CanCollide = true
	sphere.CanQuery = true
	sphere.CanTouch = true
	sphere.CFrame = dropPart.CFrame + Vector3.new(0, 1.5, 0)
	sphere.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.35, 0.15)
	sphere:SetAttribute("DropValue", value)
	sphere:SetAttribute("Value", value)
	sphere.Parent = dropsFolder
	sphere.AssemblyLinearVelocity = Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))

	self.activeOrbs[sphere] = value
end

function TycoonRenderer:startDropLoop(unitModel: Model, dropPart: BasePart, tier: number)
	if not self.isOwn then
		return nil
	end

	local tierData = AnimeDroppers.Tiers[tier]
	if not tierData then
		return nil
	end

	local thread = task.spawn(function()
		while unitModel.Parent do
			self:spawnManaDrop(dropPart, tierData.DropValue or 1)
			task.wait(self:getDropInterval())
		end
	end)

	table.insert(self.dropThreads, thread)
	return thread
end

function TycoonRenderer:getSpotForUnitIndex(dropperHolder: Instance, unitIndex: number): BasePart?
	local floorIndex, spotIndex = Grid.getFloorAndSpot(unitIndex)
	local floorModel = getFloorModel(dropperHolder, floorIndex)
	if not floorModel then
		return nil
	end

	return getSpotPart(floorModel, spotIndex)
end

function TycoonRenderer:moveRenderedUnit(unitIndex: number, entry, spotPart: BasePart)
	if entry.Thread then
		task.cancel(entry.Thread)
		entry.Thread = nil
	end

	entry.Model:PivotTo(spotPart.CFrame)

	local dropPart = self:findDropPart(spotPart)
	if dropPart then
		entry.Thread = self:startDropLoop(entry.Model, dropPart, entry.Tier)
	end

	self.unitEntries[unitIndex] = entry
	self.unitModels[unitIndex] = entry.Model
end

function TycoonRenderer:rebuild(units: { { Tier: number } })
	self.rebuildToken += 1
	local rebuildToken = self.rebuildToken

	local sortedUnits = table.clone(units)
	table.sort(sortedUnits, function(left, right)
		return (left.Tier or 1) > (right.Tier or 1)
	end)

	self:ensureFloors(#sortedUnits)

	local dropperHolder = self:getDropperHolder()
	if not dropperHolder then
		return
	end

	local unitsFolder = self:getUnitsFolder()
	local unitsToSpawn = {}
	local reusableByTier = {}

	for unitIndex in self.unitEntries do
		if unitIndex > #sortedUnits then
			self:removeRenderedUnit(unitIndex)
		end
	end

	for unitIndex, unit in sortedUnits do
		local existingEntry = self.unitEntries[unitIndex]
		if existingEntry and existingEntry.Tier == unit.Tier and existingEntry.Model and existingEntry.Model.Parent then
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
				self:moveRenderedUnit(spawnInfo.Index, reusableEntry, spotPart)
				continue
			end
		end

		table.insert(finalUnitsToSpawn, spawnInfo)
	end

	for _, entries in reusableByTier do
		for _, entry in entries do
			if entry.Thread then
				task.cancel(entry.Thread)
			end

			if entry.Model and entry.Model.Parent then
				entry.Model:Destroy()
			end
		end
	end

	task.spawn(function()
		local spawnedThisBatch = 0

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

			local template = getUnitModel(tier)
			if not template then
				continue
			end

			local unitModel = template:Clone()
			unitModel.Name = template.Name .. "_" .. unitIndex
			unitModel:PivotTo(spotPart.CFrame)
			anchorModel(unitModel)
			addOverhead(unitModel, template.Name, tier)
			unitModel.Parent = unitsFolder

			self.unitModels[unitIndex] = unitModel

			local dropPart = self:findDropPart(spotPart)
			local dropThread = nil
			if dropPart then
				dropThread = self:startDropLoop(unitModel, dropPart, tier)
			end

			self.unitEntries[unitIndex] = {
				Model = unitModel,
				Tier = tier,
				Thread = dropThread,
			}

			spawnedThisBatch += 1
			if spawnedThisBatch >= UNIT_SPAWN_BATCH_SIZE then
				spawnedThisBatch = 0
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
end

return TycoonRenderer
