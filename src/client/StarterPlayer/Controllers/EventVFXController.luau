local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EventUtil = require(ReplicatedStorage.Shared.Features.Events.EventUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local EventVFXController = Knit.CreateController({
	Name = "EventVFXController",
})

local localPlayer = Players.LocalPlayer
local EVENT_VFX_FOLDER = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("EventVFX")

local VFX_CONFIG = {
	SaiyanSurge = {
		AssetName = "saiyan_surge",
		Kind = "CharacterPart",
		Offset = CFrame.new(0, 0, 0),
	},
	InfiniteVoid = {
		AssetName = "domain_expansion",
		Kind = "WorkspaceFolder",
	},
	PirateKingsBounty = {
		AssetName = "pirate_kings_bounty",
		Kind = "CameraPart",
		Offset = CFrame.new(0, 18, -10),
	},
	ChakraOverflow = {
		AssetName = "chakra_overflow",
		Kind = "CharacterAttachment",
	},
	ThunderclapRush = {
		AssetName = "thunderclap_rush",
		Kind = "CharacterAttachment",
	},
	AlchemistCircle = {
		AssetName = "alchemist_circle",
		Kind = "FootModel",
		Offset = CFrame.new(0, -3, 0),
	},
	DragonRadarSurge = {
		AssetName = "dragon_radar_surge",
		Kind = "CharacterAttachment",
	},
	SpiritMarket = {
		AssetName = "spirit_market",
		Kind = "CharacterAttachment",
	},
	CursedEnergyLeak = {
		AssetName = "cursed_energy_leak",
		Kind = "CharacterPart",
		Offset = CFrame.new(0, 0, 0),
	},
}

local function getRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getCharacterRoot(): (Model?, BasePart?)
	local character = localPlayer.Character
	return character, getRootPart(character)
end

local function prepPart(part: BasePart, anchored: boolean)
	part.Anchored = anchored
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function prepPhysics(instance: Instance, anchored: boolean?)
	local shouldAnchor = anchored == true
	if instance:IsA("BasePart") then
		prepPart(instance, shouldAnchor)
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			prepPart(descendant, shouldAnchor)
		end
	end
end

local function weldToRoot(instance: Instance, root: BasePart)
	if instance:IsA("BasePart") then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = instance
		weld.Parent = instance
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
end

local function cloneChildrenInto(source: Instance, parent: Instance): { Instance }
	local clones = {}
	for _, child in source:GetChildren() do
		local clone = child:Clone()
		clone.Parent = parent
		table.insert(clones, clone)
	end

	return clones
end

function EventVFXController:cleanup()
	for _, cleanupItem in self.cleanups do
		if typeof(cleanupItem) == "RBXScriptConnection" then
			cleanupItem:Disconnect()
		elseif typeof(cleanupItem) == "Instance" then
			cleanupItem:Destroy()
		elseif type(cleanupItem) == "function" then
			cleanupItem()
		end
	end

	table.clear(self.cleanups)
	self.activeEventId = nil
	self.activeVFXKey = nil
end

function EventVFXController:addCleanup(cleanupItem: any)
	table.insert(self.cleanups, cleanupItem)
	return cleanupItem
end

function EventVFXController:getAsset(config: { [string]: any }): Instance?
	local asset = EVENT_VFX_FOLDER:FindFirstChild(config.AssetName)
	if not asset then
		warn("[EventVFXController] Missing EventVFX asset:", config.AssetName)
	end

	return asset
end

function EventVFXController:playWorkspaceFolder(asset: Instance): boolean
	local clone = asset:Clone()
	clone.Name = "ActiveEventVFX_" .. asset.Name
	clone.Parent = workspace
	self:addCleanup(clone)
	return true
end

function EventVFXController:playCharacterAttachment(asset: Instance): boolean
	local _character, root = getCharacterRoot()
	if not root then
		return false
	end

	if asset:IsA("Attachment") then
		local clone = asset:Clone()
		clone.Parent = root
		self:addCleanup(clone)
		return true
	end

	for _, clone in cloneChildrenInto(asset, root) do
		self:addCleanup(clone)
	end

	return true
end

function EventVFXController:playCharacterPart(asset: Instance, config: { [string]: any }): boolean
	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	local clone = asset:Clone()
	clone.Name = "ActiveEventVFX_" .. asset.Name
	prepPhysics(clone, false)

	if clone:IsA("BasePart") then
		clone.CFrame = root.CFrame * (config.Offset or CFrame.identity)
	elseif clone:IsA("Model") then
		clone:PivotTo(root.CFrame * (config.Offset or CFrame.identity))
	end

	clone.Parent = character
	weldToRoot(clone, root)
	self:addCleanup(clone)
	return true
end

function EventVFXController:playCameraPart(asset: Instance, config: { [string]: any }): boolean
	local clone = asset:Clone()
	clone.Name = "ActiveEventVFX_" .. asset.Name
	prepPhysics(clone, true)
	clone.Parent = workspace.CurrentCamera or workspace
	self:addCleanup(clone)

	self:addCleanup(RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera or not clone.Parent then
			return
		end

		local cf = camera.CFrame * (config.Offset or CFrame.identity)
		if clone:IsA("BasePart") then
			clone.CFrame = cf
		elseif clone:IsA("Model") then
			clone:PivotTo(cf)
		end
	end))
	return true
end

function EventVFXController:playFootModel(asset: Instance, config: { [string]: any }): boolean
	local clone = asset:Clone()
	clone.Name = "ActiveEventVFX_" .. asset.Name
	prepPhysics(clone, true)
	clone.Parent = workspace
	self:addCleanup(clone)

	self:addCleanup(RunService.RenderStepped:Connect(function()
		local _character, root = getCharacterRoot()
		if not root or not clone.Parent then
			return
		end

		local cf = root.CFrame * (config.Offset or CFrame.new(0, -3, 0))
		if clone:IsA("Model") then
			clone:PivotTo(cf)
		elseif clone:IsA("BasePart") then
			clone.CFrame = cf
		end
	end))
	return true
end

function EventVFXController:playEvent(activeEvent: any): boolean
	local vfxKey = activeEvent and activeEvent.VFXKey
	local config = vfxKey and VFX_CONFIG[vfxKey]
	if not config then
		return false
	end

	local asset = self:getAsset(config)
	if not asset then
		return false
	end

	if config.Kind == "WorkspaceFolder" then
		return self:playWorkspaceFolder(asset)
	elseif config.Kind == "CharacterAttachment" then
		return self:playCharacterAttachment(asset)
	elseif config.Kind == "CharacterPart" then
		return self:playCharacterPart(asset, config)
	elseif config.Kind == "CameraPart" then
		return self:playCameraPart(asset, config)
	elseif config.Kind == "FootModel" then
		return self:playFootModel(asset, config)
	end

	return false
end

function EventVFXController:refresh(force: boolean?)
	local activeEvent = EventUtil.getActiveEvent()
	local eventId = if activeEvent then activeEvent.Id else nil
	local vfxKey = if activeEvent then activeEvent.VFXKey else nil
	local showVFX = self.showVFX ~= false
	local shouldPlay = activeEvent ~= nil and showVFX

	if not force and self.activeEventId == eventId and self.activeVFXKey == vfxKey and self.isPlaying == shouldPlay then
		return
	end

	self:cleanup()
	self.isPlaying = shouldPlay

	if not shouldPlay or not activeEvent then
		return
	end

	if self:playEvent(activeEvent) then
		self.activeEventId = eventId
		self.activeVFXKey = vfxKey
	else
		self.isPlaying = false
	end
end

function EventVFXController:KnitStart()
	self.cleanups = {}
	self.activeEventId = nil
	self.activeVFXKey = nil
	self.isPlaying = false
	self.showVFX = true

	local PlayerDataController = Knit.GetController("PlayerDataController")

	task.spawn(function()
		PlayerDataController:WaitForData()
		PlayerDataController:ObserveSettings(function(settings)
			self.showVFX = settings == nil or settings.ShowVFX ~= false
			self:refresh()
		end)
	end)

	localPlayer.CharacterAdded:Connect(function()
		local character = localPlayer.Character
		if character then
			character:WaitForChild("HumanoidRootPart", 5)
		end
		task.wait(0.1)
		self:refresh(true)
	end)

	task.spawn(function()
		while true do
			self:refresh()
			task.wait(1)
		end
	end)

	local AdminService = Knit.GetService("AdminService")
	AdminService.StateChanged:Connect(function()
		self:refresh(true)
	end)
end

return EventVFXController
