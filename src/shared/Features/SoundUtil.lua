local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundUtil = {}

local sfxEnabled = true
local sfxVolume = 0.5
local soundsFolder: Folder? = nil
local folderConnections: { RBXScriptConnection } = {}
local soundCache: { [string]: Sound } = {}
local originalVolumes: { [Sound]: number } = {}

local soundAliases = {
	Click = { "Click" },
	Hover = { "Hover" },
	Error = { "Error" },
	Pickup = { "Pickup sound", "Pickup" },
	Robux = { "Buy Robux", "Robux" },
	Deposit = { "Deposit", "DepositMana" },
	Merge = { "Merge", "MergeUnits" },
	TierUnlock = { "TierUnlock", "UnitUnlock", "NewUnit" },
	RewardClaim = { "RewardClaim", "OfflineReward", "GroupReward" },
	TutorialProgress = { "TutorialProgress", "TutorialStep", "RebirthSuccess", "RebirthUpgrade" },
}

local soundAssetIds = {
	Deposit = "rbxassetid://99735583832184",
	Merge = "rbxassetid://84938276696021",
	TierUnlock = "rbxassetid://105446048067940",
	RewardClaim = "rbxassetid://133657980011333",
	TutorialProgress = "rbxassetid://113062463645110",
}

local function clearFolderConnections()
	for _, connection in folderConnections do
		connection:Disconnect()
	end

	table.clear(folderConnections)
end

local function clearSoundCache()
	table.clear(soundCache)
	table.clear(originalVolumes)
end

local function getSoundsFolder(): Folder?
	if soundsFolder and soundsFolder.Parent then
		return soundsFolder
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	if sounds and sounds:IsA("Folder") then
		if soundsFolder ~= sounds then
			clearFolderConnections()
		end

		soundsFolder = sounds
		return sounds
	end

	return nil
end

local function getOriginalVolume(sound: Sound): number
	local originalVolume = originalVolumes[sound]
	if type(originalVolume) == "number" then
		return originalVolume
	end

	originalVolume = sound:GetAttribute("OriginalVolume")
	if type(originalVolume) ~= "number" then
		originalVolume = sound.Volume
		sound:SetAttribute("OriginalVolume", originalVolume)
	end

	originalVolumes[sound] = originalVolume
	return originalVolume
end

local function applyCachedVolumes()
	local folder = getSoundsFolder()
	if not folder then
		return
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Sound") then
			child.Volume = getOriginalVolume(child) * sfxVolume
		end
	end
end

local function rebuildSoundCache()
	clearSoundCache()

	local folder = getSoundsFolder()
	if not folder then
		return
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Sound") then
			soundCache[child.Name] = child
			child.Volume = getOriginalVolume(child) * sfxVolume
		end
	end
end

local bindSoundsFolder

local function findSound(soundKey: string): Sound?
	if not next(soundCache) then
		rebuildSoundCache()
		bindSoundsFolder()
	end

	local aliases = soundAliases[soundKey] or { soundKey }
	for _, soundName in aliases do
		local sound = soundCache[soundName]
		if sound and sound.Parent then
			return sound
		end
	end

	return nil
end

bindSoundsFolder = function()
	local folder = getSoundsFolder()
	if not folder or #folderConnections > 0 then
		return
	end

	table.insert(
		folderConnections,
		folder.ChildAdded:Connect(function(child)
			if child:IsA("Sound") then
				soundCache[child.Name] = child
				child.Volume = getOriginalVolume(child) * sfxVolume
			end
		end)
	)

	table.insert(
		folderConnections,
		folder.ChildRemoved:Connect(function(child)
			if child:IsA("Sound") then
				soundCache[child.Name] = nil
				originalVolumes[child] = nil
			end
		end)
	)
end

function SoundUtil.SetLocalSfxVolume(volume: number)
	if type(volume) ~= "number" or volume ~= volume then
		return
	end

	sfxVolume = math.clamp(volume, 0, 1)
	applyCachedVolumes()
end

function SoundUtil.SetSoundEnabled(enabled: boolean)
	sfxEnabled = enabled == true
end

function SoundUtil.ConfigureFromSettings(settings: any)
	if type(settings) ~= "table" then
		return
	end

	SoundUtil.SetSoundEnabled(settings.Sound ~= false)
	SoundUtil.SetLocalSfxVolume(if type(settings.sfxVolume) == "number" then settings.sfxVolume else 1)
end

function SoundUtil.Play(soundKey: string)
	if not sfxEnabled then
		return
	end

	local template = findSound(soundKey)
	local sound
	if template then
		sound = template:Clone()
	else
		local assetId = soundAssetIds[soundKey]
		if not assetId then
			return
		end

		sound = Instance.new("Sound")
		sound.SoundId = assetId
		sound.Volume = sfxVolume
	end
	sound.Parent = SoundService
	sound:Play()

	local lifetime = if sound.TimeLength > 0 then sound.TimeLength + 0.5 else 5
	Debris:AddItem(sound, lifetime)
end

function SoundUtil.Click()
	SoundUtil.Play("Click")
end

function SoundUtil.Hover()
	SoundUtil.Play("Hover")
end

function SoundUtil.Error()
	SoundUtil.Play("Error")
end

function SoundUtil.Pickup()
	SoundUtil.Play("Pickup")
end

function SoundUtil.Robux()
	SoundUtil.Play("Robux")
end

function SoundUtil.Deposit()
	SoundUtil.Play("Deposit")
end

function SoundUtil.Merge()
	SoundUtil.Play("Merge")
end

function SoundUtil.TierUnlock()
	SoundUtil.Play("TierUnlock")
end

function SoundUtil.RewardClaim()
	SoundUtil.Play("RewardClaim")
end

function SoundUtil.TutorialProgress()
	SoundUtil.Play("TutorialProgress")
end

rebuildSoundCache()
bindSoundsFolder()

return SoundUtil
