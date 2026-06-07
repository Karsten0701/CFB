local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)

local TopTierRig = {}

local R15_DANCE_ANIMATION_IDS = {
	"rbxassetid://507771019",
	"rbxassetid://507776043",
	"rbxassetid://507777268",
}
local R6_DANCE_ANIMATION_IDS = {
	"rbxassetid://182435998",
	"rbxassetid://182436842",
	"rbxassetid://182436935",
}
local RIG_SCALE = 1
local DANCE_RESTART_DELAY = 0.35

local currentUserId: number? = nil
local currentHighestTier = 0
local currentTrack: AnimationTrack? = nil

local function getLeaderboardsFolder(): Instance?
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	return hub and hub:FindFirstChild("Leaderboards")
end

local function getRig(): Model?
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local rig = hub and hub:FindFirstChild("Rig")
	if not rig then
		local leaderboards = getLeaderboardsFolder()
		rig = leaderboards and leaderboards:FindFirstChild("Rig")
	end

	return if rig and rig:IsA("Model") then rig else nil
end

local function getUsernameLabel(): TextLabel?
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local middle = hub and hub:FindFirstChild("Middle2")
	local bb = middle and middle:FindFirstChild("BB")
	local billboard = bb and bb:FindFirstChild("BillboardGui")
	local username = billboard and billboard:FindFirstChild("Username", true)
	return if username and username:IsA("TextLabel") then username else nil
end

local function getHumanoid(rig: Model): Humanoid?
	return rig:FindFirstChildOfClass("Humanoid")
end

local function normalizeRigScale(rig: Model)
	pcall(function()
		rig:ScaleTo(RIG_SCALE)
	end)
end

local function getRootPart(rig: Model): BasePart?
	local root = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
	return if root and root:IsA("BasePart") then root else nil
end

local function lockRig(rig: Model)
	local root = getRootPart(rig)
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == root
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function cleanupOldRigAnchor(rig: Model)
	local root = getRootPart(rig)
	if root then
		for _, child in root:GetChildren() do
			if
				child.Name == "TopTierRigRootAttachment"
				or child.Name == "TopTierRigAlignPosition"
				or child.Name == "TopTierRigAlignOrientation"
			then
				child:Destroy()
			end
		end
	end

	local anchor = rig:FindFirstChild("TopTierRigAnchor")
	if anchor then
		anchor:Destroy()
	end
end

local function setupStaticRig(rig: Model, humanoid: Humanoid)
	cleanupOldRigAnchor(rig)
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	local root = getRootPart(rig)
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		root.Anchored = true
	end

	lockRig(rig)
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

	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end

	local animationIds = if humanoid.RigType == Enum.HumanoidRigType.R6
		then R6_DANCE_ANIMATION_IDS
		else R15_DANCE_ANIMATION_IDS

	for _, animationId in animationIds do
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId

		local ok, trackOrError = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		animation:Destroy()

		if not ok or not trackOrError then
			continue
		end

		local track = trackOrError
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action4
		track:Play(0.1, 1, 1)
		track:AdjustWeight(1, 0)
		track:AdjustSpeed(1)

		currentTrack = track
		return
	end
end

local function startDanceForRig(rig: Model)
	local humanoid = getHumanoid(rig)
	if not humanoid then
		return
	end

	setupStaticRig(rig, humanoid)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	playDance(humanoid)
end

local function startDanceAfterReload(rig: Model, userId: number)
	startDanceForRig(rig)
	task.delay(DANCE_RESTART_DELAY, function()
		if not rig.Parent or rig:GetAttribute("TopTierUserId") ~= userId then
			return
		end

		startDanceForRig(rig)
	end)
end

local function setUsername(player: Player?)
	local label = getUsernameLabel()
	if not label then
		return
	end

	label.Text = if player then "@" .. player.Name else "@..."
end

local function applyPlayerDescription(rig: Model, humanoid: Humanoid, player: Player): boolean
	local ok, descriptionOrError = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)

	if not ok or not descriptionOrError then
		return false
	end

	local pivot = rig:GetPivot()
	local applied, applyError = pcall(function()
		humanoid:ApplyDescriptionReset(descriptionOrError)
	end)

	if not applied then
		applied, applyError = pcall(function()
			humanoid:ApplyDescription(descriptionOrError)
		end)
	end

	if not applied then
		return false
	end

	normalizeRigScale(rig)
	rig:PivotTo(pivot)
	rig:SetAttribute("TopTierUserId", player.UserId)
	return true
end

function TopTierRig.refresh(PlayerDataService)
	local rig = getRig()
	if not rig then
		setUsername(nil)
		return
	end

	local humanoid = getHumanoid(rig)
	if not humanoid then
		setUsername(nil)
		return
	end

	local player, highestTier = getServerTopTierPlayer(PlayerDataService)
	if not player then
		stopCurrentTrack()
		currentUserId = nil
		currentHighestTier = 0
		rig:SetAttribute("TopTierUserId", nil)
		setUsername(nil)
		setupStaticRig(rig, humanoid)
		return
	end
	setUsername(player)

	if
		currentUserId == player.UserId
		and currentHighestTier == highestTier
		and rig:GetAttribute("TopTierUserId") == player.UserId
		and currentTrack
		and currentTrack.IsPlaying
	then
		startDanceForRig(rig)
		return
	end

	if not applyPlayerDescription(rig, humanoid, player) then
		currentUserId = nil
		currentHighestTier = 0
		setupStaticRig(rig, humanoid)
		return
	end

	startDanceAfterReload(rig, player.UserId)

	currentUserId = player.UserId
	currentHighestTier = highestTier
end

return TopTierRig
