local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Knit = require(ReplicatedStorage.Packages.knit)

local MusicController = Knit.CreateController({
	Name = "MusicController",
})

local TRACK_IDS = {
	"rbxassetid://129476757453334",
	"rbxassetid://135611896826290",
	"rbxassetid://120469074916720",
	"rbxassetid://106929764807887",
}

local BASE_VOLUME = 0.2

local musicSound: Sound? = nil
local currentTrackIndex = 0
local musicEnabled = true
local musicVolume = 1

local function getMusicSound(): Sound
	if musicSound and musicSound.Parent then
		return musicSound
	end

	local sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	sound.Looped = false
	sound.Volume = BASE_VOLUME
	sound:SetAttribute("OriginalVolume", BASE_VOLUME)
	sound.Parent = SoundService
	musicSound = sound
	return sound
end

local function applyVolume()
	local sound = getMusicSound()
	sound.Volume = if musicEnabled then BASE_VOLUME * musicVolume else 0
end

local function playNextTrack()
	local sound = getMusicSound()
	currentTrackIndex = (currentTrackIndex % #TRACK_IDS) + 1
	sound.SoundId = TRACK_IDS[currentTrackIndex]
	applyVolume()
	sound:Play()
end

function MusicController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local sound = getMusicSound()

	sound.Ended:Connect(function()
		playNextTrack()
	end)

	PlayerDataController:WaitForData()
	PlayerDataController:Observe("Settings", function(settings)
		if type(settings) == "table" then
			musicEnabled = settings.Music ~= false
			musicVolume = math.clamp(tonumber(settings.musicVolume) or 1, 0, 1)
		else
			musicEnabled = true
			musicVolume = 1
		end

		applyVolume()
		if musicEnabled and not sound.IsPlaying then
			playNextTrack()
		elseif not musicEnabled and sound.IsPlaying then
			sound:Pause()
		end
	end)

	if musicEnabled and not sound.IsPlaying then
		playNextTrack()
	end
end

return MusicController
