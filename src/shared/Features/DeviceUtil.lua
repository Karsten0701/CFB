local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local DeviceUtil = {}

function DeviceUtil.isTouchEnabled(): boolean
	return UserInputService.TouchEnabled
end

function DeviceUtil.isMobileLayout(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end

	if not UserInputService.KeyboardEnabled or not UserInputService.MouseEnabled then
		return true
	end

	local camera = workspace.CurrentCamera
	local viewportSize = if camera then camera.ViewportSize else Vector2.zero
	return math.min(viewportSize.X, viewportSize.Y) <= 900
end

function DeviceUtil.getStandingCheckInterval(): number
	if DeviceUtil.isMobileLayout() then
		return 0.05
	end

	return 0.1
end

function DeviceUtil.getPickupCheckInterval(): number
	if DeviceUtil.isMobileLayout() then
		return 0.03
	end

	return 0.05
end

function DeviceUtil.getLocalCharacterRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	if character.PrimaryPart and character.PrimaryPart:IsA("BasePart") then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart", true)
end

function DeviceUtil.getButtonStandingPadding(): (number, number, number)
	if DeviceUtil.isMobileLayout() then
		return 1.85, 10.5, -1.25
	end

	return 0.75, 6.5, -0.15
end

function DeviceUtil.getPickupRangeMultiplier(): number
	if DeviceUtil.isMobileLayout() then
		return 1.5
	end

	return 1
end

function DeviceUtil.isRootStandingOnButton(root: BasePart?, head: BasePart): boolean
	if not root or not head.Parent then
		return false
	end

	local rootPosition = root.Position
	local headPosition = head.Position
	local offsetX = rootPosition.X - headPosition.X
	local offsetZ = rootPosition.Z - headPosition.Z
	local radius = math.max(head.Size.X, head.Size.Y, head.Size.Z) * 0.5
	local horizontalPadding, maxVertical, minVertical = DeviceUtil.getButtonStandingPadding()
	local allowedRadius = radius + horizontalPadding
	local verticalOffset = rootPosition.Y - headPosition.Y

	return offsetX * offsetX + offsetZ * offsetZ <= allowedRadius * allowedRadius
		and verticalOffset >= minVertical
		and verticalOffset <= maxVertical
end

function DeviceUtil.collectPickupSamplePositions(root: BasePart): { Vector3 }
	local positions = { root.Position }

	if not DeviceUtil.isMobileLayout() then
		return positions
	end

	local character = root.Parent
	table.insert(positions, root.Position - Vector3.new(0, root.Size.Y * 0.45 + 1.2, 0))

	if not character then
		return positions
	end

	for _, partName in { "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg", "LowerTorso" } do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			table.insert(positions, part.Position)
		end
	end

	return positions
end

function DeviceUtil.isWithinPickupRange(root: BasePart?, orbPosition: Vector3, range: number): boolean
	if not root then
		return false
	end

	local rangeSquared = range * range
	for _, samplePosition in DeviceUtil.collectPickupSamplePositions(root) do
		local offset = samplePosition - orbPosition
		if offset:Dot(offset) <= rangeSquared then
			return true
		end
	end

	return false
end

return DeviceUtil
