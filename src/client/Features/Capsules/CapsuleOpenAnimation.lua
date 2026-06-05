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

local function getCapsuleTemplatesFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	local templates = assets:FindFirstChild("CapsuleTemplates")
	return if templates and templates:IsA("Folder") then templates else nil
end

local function getUnitTemplate(tier: number): (Model?, boolean)
	local tierData = AnimeDroppers.Tiers[tier]
	if not tierData then
		return nil, false
	end

	local capsuleTemplates = getCapsuleTemplatesFolder()
	local capsuleTemplate = capsuleTemplates and capsuleTemplates:FindFirstChild(tierData.ModelName)
	if capsuleTemplate and capsuleTemplate:IsA("Model") then
		return capsuleTemplate, true
	end

	local assets = getAnimeAssetsFolder()
	if not assets then
		return nil, false
	end

	local model = assets:FindFirstChild(tierData.ModelName)
	return if model and model:IsA("Model") then model else nil, false
end

local function findSlot(capsule: Instance, name: string): Instance?
	return capsule:FindFirstChild(name, true)
end

local function isHiddenHelperPart(part: BasePart): boolean
	local lowerName = string.lower(part.Name)
	return lowerName == "humanoidrootpart"
		or lowerName == "rootpart"
		or string.find(lowerName, "hitbox") ~= nil
		or string.find(lowerName, "collision") ~= nil
end

local function getCapsuleParts(capsule: Instance): { BasePart }
	local parts = {}
	if capsule:IsA("BasePart") then
		table.insert(parts, capsule)
	end

	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function pivotCapsuleTo(capsule: Instance, assemblyRoot: BasePart, targetCFrame: CFrame)
	if capsule:IsA("Model") then
		local delta = targetCFrame * assemblyRoot.CFrame:Inverse()
		capsule:PivotTo(delta * capsule:GetPivot())
	elseif capsule:IsA("BasePart") then
		local delta = targetCFrame * assemblyRoot.CFrame:Inverse()
		for _, part in getCapsuleParts(capsule) do
			part.CFrame = delta * part.CFrame
		end
	end
end

local function getCameraFacingCFrame(position: Vector3): CFrame
	local camera = Workspace.CurrentCamera
	if camera then
		local lookTarget = Vector3.new(camera.CFrame.Position.X, position.Y, camera.CFrame.Position.Z)
		if (lookTarget - position).Magnitude > 0.001 then
			return CFrame.lookAt(position, lookTarget)
		end
	end

	return CFrame.new(position)
end

local function getModelScale(model: Model): number
	local ok, scale = pcall(function()
		return model:GetScale()
	end)

	return if ok and type(scale) == "number" and scale > 0 then scale else 1
end

local function getScaleForHeight(model: Model, targetHeight: number): number
	local _, size = model:GetBoundingBox()
	if size.Y <= 0.01 then
		return getModelScale(model)
	end

	return getModelScale(model) * (targetHeight / size.Y)
end

function CapsuleOpenAnimation.play(
	capsule: Instance?,
	assemblyRoot: BasePart?,
	rewardTier: number,
	onComplete: (() -> ())?
)
	if not capsule or not capsule.Parent or not assemblyRoot or not assemblyRoot.Parent then
		if onComplete then
			onComplete()
		end
		return
	end

	local config = getConfig()
	local revealStartHeight = tonumber(config.RevealStartHeight) or 1.15
	local revealEndHeight = tonumber(config.RevealEndHeight) or 1.75
	local revealHoldDuration = tonumber(config.RevealHoldDuration) or 0.85

	for _, part in getCapsuleParts(capsule) do
		part.Anchored = true
		part.CanCollide = false
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end

	local baseCFrame = assemblyRoot.CFrame
	local focusPosition = assemblyRoot.Position + Vector3.new(0, 0.55, 0)

	local camera = Workspace.CurrentCamera
	local previousCameraType = if camera then camera.CameraType else Enum.CameraType.Custom
	local previousCameraSubject = if camera then camera.CameraSubject else nil

	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		local cameraPosition = focusPosition + Vector3.new(0, 1.75, 6)
		local tween = TweenService:Create(
			camera,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.lookAt(cameraPosition, focusPosition) }
		)
		tween:Play()
		tween.Completed:Wait()
	end

	local shakeDuration = 1.4
	local shakeStart = os.clock()
	local shakeConnection: RBXScriptConnection? = nil
	shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - shakeStart
		if elapsed >= shakeDuration then
			if shakeConnection then
				shakeConnection:Disconnect()
			end
			assemblyRoot.CFrame = baseCFrame
			return
		end

		local intensity = 1 - (elapsed / shakeDuration)
		local sway = math.sin(elapsed * 9) * 0.1 * intensity
		local wag = math.sin(elapsed * 14) * math.rad(8) * intensity
		pivotCapsuleTo(capsule, assemblyRoot, baseCFrame * CFrame.new(sway, 0, 0) * CFrame.Angles(0, wag * 0.35, wag))
	end)

	task.wait(shakeDuration)
	if shakeConnection then
		shakeConnection:Disconnect()
	end
	pivotCapsuleTo(capsule, assemblyRoot, baseCFrame)

	local top = findSlot(capsule, "Top")
	if top and top:IsA("BasePart") then
		local weldFolder = assemblyRoot:FindFirstChild("CapsuleWelds")
		if weldFolder then
			for _, child in weldFolder:GetChildren() do
				if child:IsA("WeldConstraint") and child.Part1 == top then
					child:Destroy()
				end
			end
		end

		local liftTween = TweenService:Create(
			top,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = top.CFrame * CFrame.new(0, 2.5, 0) }
		)
		liftTween:Play()
		liftTween.Completed:Wait()

		top.Transparency = 1
		top.LocalTransparencyModifier = 1
		top.CanCollide = false
		top.CanTouch = false
		top.CanQuery = false
	end

	local template = getUnitTemplate(rewardTier)
	if template then
		local revealModel = template:Clone()
		revealModel.Name = "CapsuleReveal"
		for _, part in revealModel:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.Massless = false
				if isHiddenHelperPart(part) then
					part.Transparency = 1
					part.LocalTransparencyModifier = 1
				end
			end
		end

		local startScale = getScaleForHeight(revealModel, revealStartHeight)

		pcall(function()
			revealModel:ScaleTo(startScale)
		end)

		local endScale = getScaleForHeight(revealModel, revealEndHeight)
		local revealPosition = focusPosition + Vector3.new(0, 0.2, 0)
		revealModel:PivotTo(getCameraFacingCFrame(revealPosition))
		revealModel.Parent = capsule

		local riseValue = Instance.new("NumberValue")
		riseValue.Value = 0
		riseValue.Parent = revealModel

		local riseTween = TweenService:Create(
			riseValue,
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Value = 1 }
		)

		local riseConnection = riseValue.Changed:Connect(function(value)
			local alpha = math.clamp(value, 0, 1)
			local position = revealPosition + Vector3.new(0, 0.55 * alpha, 0)
			revealModel:PivotTo(getCameraFacingCFrame(position))
			local scale = startScale + (endScale - startScale) * alpha
			pcall(function()
				revealModel:ScaleTo(scale)
			end)
		end)

		riseTween:Play()
		riseTween.Completed:Wait()
		riseConnection:Disconnect()
		riseValue:Destroy()
	end

	task.wait(revealHoldDuration)

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
