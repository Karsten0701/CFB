local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)

local WorldLeaderboardRenderer = {}

local nameCache: { [number]: string } = {}
local thumbnailCache: { [number]: string } = {}

local function getLeaderboardsFolder(): Instance?
	local map = workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	return hub and hub:FindFirstChild("Leaderboards")
end

local function getBoardFrame(boardName: string): ScrollingFrame?
	local leaderboards = getLeaderboardsFolder()
	local board = leaderboards and leaderboards:FindFirstChild(boardName)
	local lb = board and board:FindFirstChild("LB")
	local surfaceGui = lb and lb:FindFirstChild("LBSurfaceUI")
	local frame = surfaceGui and surfaceGui:FindFirstChild("ScrollingFrame")
	return if frame and frame:IsA("ScrollingFrame") then frame else nil
end

local function getBoardSurfaceGui(boardName: string): SurfaceGui?
	local leaderboards = getLeaderboardsFolder()
	local board = leaderboards and leaderboards:FindFirstChild(boardName)
	local lb = board and board:FindFirstChild("LB")
	local surfaceGui = lb and lb:FindFirstChild("LBSurfaceUI")
	return if surfaceGui and surfaceGui:IsA("SurfaceGui") then surfaceGui else nil
end

local function ensureBoardFrame(boardName: string): ScrollingFrame?
	local frame = getBoardFrame(boardName)
	if frame then
		return frame
	end

	if boardName == "Rebirth" then
		return nil
	end

	local surfaceGui = getBoardSurfaceGui(boardName)
	local rebirthFrame = getBoardFrame("Rebirth")
	if not surfaceGui or not rebirthFrame then
		return nil
	end

	local clone = rebirthFrame:Clone()
	clone.Parent = surfaceGui
	return clone
end

local function getTemplate(frame: ScrollingFrame): GuiObject?
	local template = frame:FindFirstChild("Template")
	return if template and template:IsA("GuiObject") then template else nil
end

local function ensureTemplate(boardName: string, frame: ScrollingFrame): GuiObject?
	local template = getTemplate(frame)
	if template then
		return template
	end

	if boardName == "Rebirth" then
		return nil
	end

	local rebirthFrame = getBoardFrame("Rebirth")
	local rebirthTemplate = rebirthFrame and getTemplate(rebirthFrame)
	if not rebirthTemplate then
		return nil
	end

	local clone = rebirthTemplate:Clone()
	clone.Name = "Template"
	clone.Parent = frame
	return clone
end

local function getTextLabel(root: Instance, labelName: string): TextLabel?
	local label = root:FindFirstChild(labelName, true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function getProfileImage(root: Instance): (ImageLabel | ImageButton)?
	local image = root:FindFirstChild("ProfilePic", true)
	return if image and (image:IsA("ImageLabel") or image:IsA("ImageButton")) then image else nil
end

local function getPlayerName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end

	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.Name
		return player.Name
	end

	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local playerName = if ok and type(result) == "string" then result else tostring(userId)
	nameCache[userId] = playerName
	return playerName
end

local function getPlayerThumbnail(userId: number): string
	if thumbnailCache[userId] then
		return thumbnailCache[userId]
	end

	local ok, image = pcall(function()
		local content = Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
		return content
	end)

	local thumbnail = if ok and type(image) == "string" then image else ""
	thumbnailCache[userId] = thumbnail
	return thumbnail
end

local function clearEntries(frame: ScrollingFrame)
	for _, child in frame:GetChildren() do
		if child.Name == "Template" then
			continue
		end

		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function formatPlaytime(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	return tostring(days) .. "d " .. tostring(hours) .. "h " .. tostring(minutes) .. "m"
end

local function formatAmount(boardName: string, value: number, suffix: string): string
	value = math.max(math.floor(value), 0)
	if boardName == "Yen" then
		return Pricing.formatYen(value)
	elseif boardName == "Playtime" then
		return formatPlaytime(value)
	end

	return FormatUtil.formatNumber(value) .. " " .. suffix
end

function WorldLeaderboardRenderer.render(boardName: string, entries: { any }, suffix: string)
	local frame = ensureBoardFrame(boardName)
	if not frame then
		return false
	end

	local template = ensureTemplate(boardName, frame)
	if not template then
		return false
	end

	template.Visible = false
	clearEntries(frame)

	for rank, entry in entries do
		local userId = tonumber(entry.UserId)
		local value = tonumber(entry.Value) or 0
		if not userId or userId <= 0 or value < 0 then
			continue
		end

		local row = template:Clone()
		row.Name = string.format("Entry_%03d", rank)
		row.LayoutOrder = rank
		row.Visible = true

		local nameLabel = getTextLabel(row, "Name")
		if nameLabel then
			nameLabel.Text = "@" .. getPlayerName(userId)
		end

		local rankingLabel = getTextLabel(row, "Ranking")
		if rankingLabel then
			rankingLabel.Text = "#" .. tostring(rank) .. " Global"
		end

		local amountLabel = getTextLabel(row, "Amount")
		if amountLabel then
			amountLabel.Text = formatAmount(boardName, value, suffix)
		end

		local profilePic = getProfileImage(row)
		if profilePic then
			profilePic.Image = getPlayerThumbnail(userId)
		end

		row.Parent = frame
	end

	return true
end

return WorldLeaderboardRenderer
