local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)

local TopTierRig = {}

local R15_DANCE_ANIMATION_ID = "rbxassetid://507771019"
local R6_DANCE_ANIMATION_ID = "rbxassetid://182435998"
local RIG_SCALE = 2

local currentUserId: number? = nil
local currentHighestTier = 0
local currentTrack: AnimationTrack? = nil

local function getLeaderboardsFolder(): Instance?
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	return hub and hub:FindFirstChild("Leaderboards")
end

local function getRig(): Model?
	local leaderboards = getLeaderboardsFolder()
	local rig = leaderboards and leaderboards:FindFirstChild("Rig")
	return if rig and rig:IsA("Model") then rig else nil
end

local function getHumanoid(rig: Model): Humanoid?
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function applyRigScale(rig: Model)
	pcall(function()
		rig:ScaleTo(RIG_SCALE)
	end)
end

local function getRootPart(rig: Model): BasePart?
	local root = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
	return if root and root:IsA("BasePart") then root else nil
end

local function lockRig(rig: Model)
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Name == "TopTierRigAnchor" then
				continue
			end

			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function ensureRigAnchor(rig: Model, humanoid: Humanoid)
	local root = getRootPart(rig)
	if not root then
		return
	end

	local anchor = rig:FindFirstChild("TopTierRigAnchor")
	if not anchor or not anchor:IsA("BasePart") then
		anchor = Instance.new("Part")
		anchor.Name = "TopTierRigAnchor"
		anchor.Size = Vector3.one
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.Parent = rig
	end
	anchor.CFrame = root.CFrame

	local rootAttachment = root:FindFirstChild("TopTierRigRootAttachment")
	if not rootAttachment or not rootAttachment:IsA("Attachment") then
		rootAttachment = Instance.new("Attachment")
		rootAttachment.Name = "TopTierRigRootAttachment"
		rootAttachment.Parent = root
	end

	local anchorAttachment = anchor:FindFirstChild("TopTierRigAnchorAttachment")
	if not anchorAttachment or not anchorAttachment:IsA("Attachment") then
		anchorAttachment = Instance.new("Attachment")
		anchorAttachment.Name = "TopTierRigAnchorAttachment"
		anchorAttachment.Parent = anchor
	end

	local alignPosition = root:FindFirstChild("TopTierRigAlignPosition")
	if not alignPosition or not alignPosition:IsA("AlignPosition") then
		alignPosition = Instance.new("AlignPosition")
		alignPosition.Name = "TopTierRigAlignPosition"
		alignPosition.Parent = root
	end
	alignPosition.Attachment0 = rootAttachment
	alignPosition.Attachment1 = anchorAttachment
	alignPosition.MaxForce = math.huge
	alignPosition.MaxVelocity = math.huge
	alignPosition.Responsiveness = 200
	alignPosition.RigidityEnabled = true

	local alignOrientation = root:FindFirstChild("TopTierRigAlignOrientation")
	if not alignOrientation or not alignOrientation:IsA("AlignOrientation") then
		alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "TopTierRigAlignOrientation"
		alignOrientation.Parent = root
	end
	alignOrientation.Attachment0 = rootAttachment
	alignOrientation.Attachment1 = anchorAttachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.MaxAngularVelocity = math.huge
	alignOrientation.Responsiveness = 200
	alignOrientation.RigidityEnabled = true

	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	root:SetNetworkOwner(nil)
end

local function getServerTopTierPlayer(PlayerDataService): (Player?, number)
	local bestPlayer: Player? = nil
	local bestTier = 0

	for _, player in Players:GetPlayers() do
		local ok, units = pcall(function()
			PlayerDataService:WaitForData(player)
			return PlayerDataService:GetUnits(player)
		end)

		if not ok then
			continue
		end

		local tier = CapsuleUtil.getHighestUnitTier(units)
		if tier > bestTier then
			bestTier = tier
			bestPlayer = player
		end
	end

	return bestPlayer, bestTier
end

local function stopCurrentTrack()
	if currentTrack then
		currentTrack:Stop(0.15)
		currentTrack:Destroy()
		currentTrack = nil
	end
end

local function playDance(humanoid: Humanoid)
	stopCurrentTrack()

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R6 then R6_DANCE_ANIMATION_ID else R15_DANCE_ANIMATION_ID

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()

	if not ok or not track then
		return
	end

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.15)
	currentTrack = track
end

function TopTierRig.refresh(PlayerDataService)
	local rig = getRig()
	if not rig then
		return
	end

	local humanoid = getHumanoid(rig)
	if not humanoid then
		return
	end
	applyRigScale(rig)
	lockRig(rig)
	ensureRigAnchor(rig, humanoid)

	local player, highestTier = getServerTopTierPlayer(PlayerDataService)
	if not player then
		stopCurrentTrack()
		currentUserId = nil
		currentHighestTier = 0
		return
	end

	if currentUserId == player.UserId and currentHighestTier == highestTier and currentTrack and currentTrack.IsPlaying then
		return
	end

	local pivot = rig:GetPivot()
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)

	if ok and description then
		pcall(function()
			humanoid:ApplyDescription(description)
		end)
		applyRigScale(rig)
		rig:PivotTo(pivot)
		lockRig(rig)
		ensureRigAnchor(rig, humanoid)
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	playDance(humanoid)

	currentUserId = player.UserId
	currentHighestTier = highestTier
end

return TopTierRig
