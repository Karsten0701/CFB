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

local function findSlot(capsule: Instance, name: string): Instance?
	return capsule:FindFirstChild(name, true)
end

function CapsuleOpenAnimation.play(capsule: Instance?, assemblyRoot: BasePart?, rewardTier: number, onComplete: (() -> ())?)
	if not capsule or not capsule.Parent or not assemblyRoot or not assemblyRoot.Parent then
		if onComplete then
			onComplete()
		end
		return
	end

	local config = getConfig()
	local revealStartScale = tonumber(config.UnitScale) or 0.2
	local revealEndScale = tonumber(config.RevealScale) or 0.5

	local legacyPreviewFolder = capsule:FindFirstChild("PreviewUnits", true)
	if legacyPreviewFolder then
		legacyPreviewFolder:Destroy()
	end

	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("Model") and string.match(descendant.Name, "^Preview_") then
			descendant:Destroy()
		end
	end

	for _, descendant in capsule:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local baseCFrame = assemblyRoot.CFrame
	local focusPosition = assemblyRoot.Position + Vector3.new(0, 0.75, 0)

	local camera = Workspace.CurrentCamera
	local previousCameraType = if camera then camera.CameraType else Enum.CameraType.Custom
	local previousCameraSubject = if camera then camera.CameraSubject else nil

	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		local cameraPosition = focusPosition + Vector3.new(0, 2.25, 7)
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
		assemblyRoot.CFrame = baseCFrame * CFrame.new(sway, 0, 0) * CFrame.Angles(0, wag * 0.35, wag)
	end)

	task.wait(shakeDuration)
	if shakeConnection then
		shakeConnection:Disconnect()
	end
	assemblyRoot.CFrame = baseCFrame

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
	end

	local template = getUnitTemplate(rewardTier)
	if template then
		local revealModel = template:Clone()
		revealModel.Name = "CapsuleReveal"
		for _, part in revealModel:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.Massless = true
			end
		end

		pcall(function()
			revealModel:ScaleTo(revealStartScale)
		end)
		revealModel:PivotTo(CFrame.new(focusPosition + Vector3.new(0, 0.35, 0)))
		revealModel.Parent = capsule

		local scaleValue = Instance.new("NumberValue")
		scaleValue.Value = revealStartScale
		scaleValue.Parent = revealModel

		local scaleTween = TweenService:Create(
			scaleValue,
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Value = revealEndScale }
		)

		local scaleConnection = scaleValue.Changed:Connect(function()
			pcall(function()
				revealModel:ScaleTo(scaleValue.Value)
			end)
		end)

		scaleTween:Play()
		scaleTween.Completed:Wait()
		scaleConnection:Disconnect()
		scaleValue:Destroy()
	end

	task.wait(0.3)

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
