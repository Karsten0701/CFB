local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DepositVFX = {}
DepositVFX.__index = DepositVFX

local ORB_COUNT = 18
local ORB_SIZE = Vector3.new(1.1, 1.1, 1.1)
local ORB_GATHER_TIME = 0.82
local ORB_BURST_TIME = 0.28
local BEAM_LIFETIME = 0.42
local BEAM_HEIGHT = 1000
local BEAM_THICKNESS = 2.5
local MIN_BEAM_INTERVAL = 0.42
local DEFAULT_PROCESS_INTERVAL = 1

local TRAIL_COLOR_START = Color3.fromRGB(140, 220, 255)
local TRAIL_COLOR_MID = Color3.fromRGB(70, 165, 255)
local TRAIL_COLOR_END = Color3.fromRGB(25, 95, 210)

local templateCache: { [number]: Instance? } = {}

local function getDropTemplate(tier: number): Instance?
	local cached = templateCache[tier]
	if cached and cached.Parent then
		return cached
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local dropsFolder = assets and assets:FindFirstChild("Drops")
	if not dropsFolder then
		return nil
	end

	local template = dropsFolder:FindFirstChild("Tier" .. tier) or dropsFolder:FindFirstChild("Template")
	templateCache[tier] = template
	return template
end

local function prepareVisual(instance: Instance)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = false
		elseif descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		end
	end

	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.Massless = false
	end
end

local function setVisualCFrame(instance: Instance, cframe: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

local function setVisualScale(instance: Instance, scale: number)
	if instance:IsA("Model") then
		pcall(function()
			instance:ScaleTo(scale)
		end)
	elseif instance:IsA("BasePart") then
		instance.Size = ORB_SIZE * scale
	end
end

local function setVisualTransparency(instance: Instance, transparency: number)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = math.max(descendant.Transparency, transparency)
		end
	end

	if instance:IsA("BasePart") then
		instance.Transparency = transparency
	end
end

local function cubicBezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, alpha: number): Vector3
	local inverse = 1 - alpha
	return inverse ^ 3 * p0 + 3 * inverse ^ 2 * alpha * p1 + 3 * inverse * alpha ^ 2 * p2 + alpha ^ 3 * p3
end

local function smoothStep(alpha: number): number
	return alpha * alpha * (3 - 2 * alpha)
end

local function randomUnitVector(): Vector3
	local vector = Vector3.new(math.random(-100, 100) / 100, math.random(-35, 125) / 100, math.random(-100, 100) / 100)

	if vector.Magnitude < 0.1 then
		return Vector3.yAxis
	end

	return vector.Unit
end

local function getOrbAnchorPart(orb: Instance): BasePart?
	if orb:IsA("BasePart") then
		return orb
	end

	if orb:IsA("Model") then
		local primary = orb.PrimaryPart
		if primary and primary:IsA("BasePart") then
			return primary
		end

		return orb:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function attachDepositTrail(orb: Instance)
	local part = getOrbAnchorPart(orb)
	if not part then
		return
	end

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "DepositTrail0"
	attachment0.Position = Vector3.new(0, 0.05, 0.18)
	attachment0.Parent = part

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "DepositTrail1"
	attachment1.Position = Vector3.new(0, -0.05, -0.42)
	attachment1.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = "DepositTrail"
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = 0.5
	trail.MinLength = 0.04
	trail.MaxLength = 28
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0.15
	trail.Texture = ""
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 0.7),
		NumberSequenceKeypoint.new(0.75, 0.28),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.45, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, TRAIL_COLOR_START),
		ColorSequenceKeypoint.new(0.45, TRAIL_COLOR_MID),
		ColorSequenceKeypoint.new(1, TRAIL_COLOR_END),
	})
	trail.Parent = part
end

local function getLocalRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getProcessor(tycoon: Instance): Instance?
	return tycoon:FindFirstChild("Processer") or tycoon:FindFirstChild("Processor")
end

local function getBeamPos(tycoon: Instance): BasePart?
	local processor = getProcessor(tycoon)
	local beamPos = processor and processor:FindFirstChild("BeamPos", true)
	return if beamPos and beamPos:IsA("BasePart") then beamPos else nil
end

local function getProcessorDropTemplate(tycoon: Instance): Instance?
	local processor = getProcessor(tycoon)
	local template = processor and processor:FindFirstChild("Template", true)
	return template
end

local function getVfxFolder(tycoon: Instance, janitor: any): Folder
	local folder = tycoon:FindFirstChild("DepositVFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DepositVFX"
		folder.Parent = tycoon
		if janitor then
			janitor:Add(folder)
		end
	end

	return folder :: Folder
end

function DepositVFX.new(tycoon: Instance, janitor: any)
	local self = setmetatable({}, DepositVFX)
	self.tycoon = tycoon
	self.janitor = janitor
	self.folder = getVfxFolder(tycoon, janitor)
	self.processorDropTemplate = getProcessorDropTemplate(tycoon)
	self.activeOrbs = 0
	self.lastBeamAt = 0
	self.beamLoopToken = 0
	self.beamLoopActive = false
	self.beamInterval = DEFAULT_PROCESS_INTERVAL
	self.enabled = true
	return self
end

function DepositVFX:setEnabled(enabled: boolean)
	self.enabled = enabled

	if enabled then
		return
	end

	self:setProcessorActive(false)
	for _, child in self.folder:GetChildren() do
		child:Destroy()
	end
	self.activeOrbs = 0
end

function DepositVFX:createOrb(): Instance
	if not self.processorDropTemplate or not self.processorDropTemplate.Parent then
		self.processorDropTemplate = getProcessorDropTemplate(self.tycoon)
	end

	local template = if self.processorDropTemplate and self.processorDropTemplate.Parent
		then self.processorDropTemplate
		else getDropTemplate(1)
	local orb = if template then template:Clone() else Instance.new("Part")
	orb.Name = "DepositOrb"

	if orb:IsA("BasePart") then
		orb.Shape = Enum.PartType.Ball
		orb.Size = ORB_SIZE
		orb.Material = Enum.Material.Neon
		orb.Color = Color3.fromRGB(40, 125, 255)
	end

	prepareVisual(orb)
	setVisualScale(orb, 0.75 + math.random() * 0.25)
	orb.Parent = self.folder
	attachDepositTrail(orb)
	return orb
end

function DepositVFX:playDeposit(amount: number)
	if not self.enabled or type(amount) ~= "number" or amount <= 0 or self.activeOrbs > 0 then
		return
	end

	local root = getLocalRoot()
	local beamPos = getBeamPos(self.tycoon)
	if not root or not beamPos then
		return
	end

	local startPosition = root.Position + Vector3.new(0, 2.9, 0)
	local endPosition = beamPos.Position + Vector3.new(0, 2, 0)
	self.activeOrbs += ORB_COUNT

	for index = 1, ORB_COUNT do
		local orb = self:createOrb()
		local startOffset = randomUnitVector() * math.random(2, 5)
		local orbStart = startPosition + startOffset
		local controlA = startPosition + randomUnitVector() * math.random(7, 12) + Vector3.new(0, math.random(2, 6), 0)
		local controlB = startPosition:Lerp(endPosition, 0.65)
			+ randomUnitVector() * math.random(4, 9)
			+ Vector3.new(0, math.random(2, 6), 0)
		local startTime = os.clock() + (index - 1) * 0.012

		setVisualCFrame(orb, CFrame.new(orbStart))

		task.spawn(function()
			while orb.Parent do
				local alpha = math.clamp((os.clock() - startTime) / ORB_GATHER_TIME, 0, 1)
				if alpha > 0 then
					local eased = smoothStep(alpha)
					local position = cubicBezier(orbStart, controlA, controlB, endPosition, eased)
					setVisualCFrame(orb, CFrame.new(position))
				end

				if alpha >= 1 then
					break
				end

				RunService.Heartbeat:Wait()
			end

			if orb.Parent then
				local burstStart = endPosition
				local burstEnd = burstStart + randomUnitVector() * math.random(3, 7)
				local burstStartedAt = os.clock()

				while orb.Parent do
					local alpha = math.clamp((os.clock() - burstStartedAt) / ORB_BURST_TIME, 0, 1)
					local eased = 1 - (1 - alpha) ^ 2
					setVisualCFrame(orb, CFrame.new(burstStart:Lerp(burstEnd, eased)))
					setVisualScale(orb, 0.75 * (1 - eased))
					setVisualTransparency(orb, eased)

					if alpha >= 1 then
						break
					end

					RunService.Heartbeat:Wait()
				end

				if orb.Parent then
					orb:Destroy()
				end
			end

			self.activeOrbs = math.max(self.activeOrbs - 1, 0)
		end)
	end

	task.delay(0.28, function()
		self:pulseBeam(true)
	end)
end

function DepositVFX:setProcessorActive(isActive: boolean, interval: number?)
	self.beamInterval = math.max(interval or DEFAULT_PROCESS_INTERVAL, MIN_BEAM_INTERVAL)

	if not isActive or not self.enabled then
		if self.beamLoopActive then
			self.beamLoopToken += 1
			self.beamLoopActive = false
		end
		return
	end

	if self.beamLoopActive then
		return
	end

	self.beamLoopActive = true
	self.beamLoopToken += 1
	local token = self.beamLoopToken

	task.spawn(function()
		while self.beamLoopActive and self.beamLoopToken == token and self.folder.Parent do
			self:pulseBeam(true)
			task.wait(self.beamInterval)
		end
	end)
end

function DepositVFX:pulseBeam(force: boolean?)
	if not self.enabled then
		return
	end

	local now = os.clock()
	if not force and now - self.lastBeamAt < MIN_BEAM_INTERVAL then
		return
	end

	local beamPos = getBeamPos(self.tycoon)
	if not beamPos then
		return
	end

	self.lastBeamAt = now

	local beam = Instance.new("Part")
	beam.Name = "DepositBeamPulse"
	beam.Shape = Enum.PartType.Cylinder
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(45, 111, 255)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false
	beam.Transparency = 0
	beam.CastShadow = false
	beam.Size = Vector3.new(0.25, BEAM_THICKNESS, BEAM_THICKNESS)
	beam.Parent = self.folder

	local baseCFrame = beamPos.CFrame
	local startedAt = os.clock()
	local connection: RBXScriptConnection?
	connection = RunService.Heartbeat:Connect(function()
		if not beam.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local alpha = math.clamp((os.clock() - startedAt) / BEAM_LIFETIME, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		local height = 0.25 + (BEAM_HEIGHT - 0.25) * eased
		beam.Size = Vector3.new(height, BEAM_THICKNESS, BEAM_THICKNESS)
		beam.CFrame = baseCFrame * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		beam.Transparency = 0.1 + alpha * 0.85

		if alpha >= 1 then
			if connection then
				connection:Disconnect()
			end
			beam:Destroy()
		end
	end)
end

return DepositVFX
