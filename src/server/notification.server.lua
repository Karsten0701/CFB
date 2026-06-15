-- ServerScriptService/EventHandler.server.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local FOLLOW_ID = 3987783169536557725
local END_TIMESTAMP = 1781971200

local remote = ReplicatedStorage:FindFirstChild("EventFollowPrompt")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "EventFollowPrompt"
	remote.Parent = ReplicatedStorage
end

local debounce = {}

local function formatTime(secondsLeft)
	secondsLeft = math.max(0, secondsLeft)

	local days = math.floor(secondsLeft / 86400)
	secondsLeft %= 86400

	local hours = math.floor(secondsLeft / 3600)
	secondsLeft %= 3600

	local minutes = math.floor(secondsLeft / 60)
	local seconds = secondsLeft % 60

	return string.format("%dd %dh %dm %ds", days, hours, minutes, seconds)
end

local function setupEvent(eventModel)
	local touchPart = eventModel:FindFirstChild("TouchPart", true)
	local countdown = eventModel:FindFirstChild("CountdownTimer", true)

	if not touchPart or not countdown then
		warn("Missing TouchPart or CountdownTimer in:", eventModel.Name)
		return
	end

	touchPart.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		if debounce[player] then
			return
		end
		debounce[player] = true

		remote:FireClient(player, FOLLOW_ID)

		task.delay(4, function()
			debounce[player] = nil
		end)
	end)

	task.spawn(function()
		while eventModel.Parent do
			local now = os.time()
			local left = END_TIMESTAMP - now

			countdown.Text = formatTime(left)

			task.wait(1)
		end
	end)
end

for _, obj in ipairs(workspace:GetChildren()) do
	if obj.Name:match("^Event%d+$") then
		setupEvent(obj)
	end
end
