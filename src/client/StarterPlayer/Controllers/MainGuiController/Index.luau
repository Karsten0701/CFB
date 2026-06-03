local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local TycoonUtil = require(ReplicatedStorage.Shared.Features.Tycoon.TycoonUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local Index = {}

local localPlayer = Players.LocalPlayer
local INDEX_UNLOCKED_COLOR = Color3.fromRGB(255, 255, 255)
local INDEX_LOCKED_COLOR = Color3.fromRGB(0, 0, 0)
local INDEX_TOUCH_DISCOVERY_INTERVAL = 0.5

local indexConnections: { RBXScriptConnection } = {}
local indexTouchLoopConnection: RBXScriptConnection? = nil
local indexTouchPart: BasePart? = nil
local indexTouchPartConnections: { RBXScriptConnection } = {}
local indexTouchedParts: { [BasePart]: boolean } = {}
local indexTouching = false
local indexClosedByButton = false
local indexWarnedMissingFrame = false
local indexWarnedMissingTouchPart = false

function Index.Install(MainGuiController)

function MainGuiController:getIndexFrame(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local frame = mainGui:FindFirstChild("IndexFrame")
	if frame and frame:IsA("GuiObject") then
		return frame
	end

	if not indexWarnedMissingFrame then
		indexWarnedMissingFrame = true
		warn("[MainGuiController] MainGui.IndexFrame not found; Index touch cannot open the UI.")
	end

	return nil
end

function MainGuiController:getIndexTemplate(): GuiObject?
	local frame = self:getIndexFrame()
	local scrollingFrame = frame and frame:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return nil
	end

	local template = scrollingFrame:FindFirstChild("Template")
	if template and template:IsA("GuiObject") then
		template.Visible = false
		return template
	end

	return nil
end

function MainGuiController:getConfiguredUnitIcon(tierData: any): string
	local iconId = tierData and (tierData.IconId or tierData.IconID or tierData.IconAssetId)
	if type(iconId) == "number" and iconId > 0 then
		return "rbxassetid://" .. tostring(iconId)
	elseif type(iconId) == "string" and iconId ~= "" and iconId ~= "rbxassetid://0" then
		if tonumber(iconId) then
			return "rbxassetid://" .. iconId
		end

		return iconId
	end

	local current: Instance = ReplicatedStorage
	for _, childName in TycoonConfig.AssetsPath do
		local nextChild = current:FindFirstChild(childName)
		if not nextChild then
			return ""
		end
		current = nextChild
	end

	local model = current:FindFirstChild(tierData.ModelName)
	if not model then
		return ""
	end

	for _, attributeName in { "IconId", "IconID", "IconAssetId" } do
		local attributeIcon = model:GetAttribute(attributeName)
		if type(attributeIcon) == "number" and attributeIcon > 0 then
			return "rbxassetid://" .. tostring(attributeIcon)
		elseif type(attributeIcon) == "string" and attributeIcon ~= "" then
			return if tonumber(attributeIcon) then "rbxassetid://" .. attributeIcon else attributeIcon
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Decal") or descendant:IsA("Texture") then
			if descendant.Texture ~= "" then
				return descendant.Texture
			end
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			if descendant.Image ~= "" then
				return descendant.Image
			end
		end
	end

	return ""
end

function MainGuiController:isAnimeDropperUnlocked(unlockedDroppers: any, tier: number): boolean
	if type(unlockedDroppers) ~= "table" then
		return tier == 1
	end

	return unlockedDroppers[tier] == true or unlockedDroppers[tostring(tier)] == true
end

function MainGuiController:clearIndexConnections()
	for _, connection in indexConnections do
		connection:Disconnect()
	end

	table.clear(indexConnections)
end

function MainGuiController:connectIndexGuiActivated(guiObject: GuiObject, callback: () -> ())
	local clickable = self:getClickableGui(guiObject)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		table.insert(indexConnections, clickable.Activated:Connect(callback))
	else
		table.insert(
			indexConnections,
			clickable.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					callback()
				end
			end)
		)
	end
end

function MainGuiController:refreshIndexFrame()
	local frame = self:getIndexFrame()
	if not frame then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local unlockedDroppers = PlayerDataController:Get("UnlockedAnimeDroppers")

	for _, child in frame:GetDescendants() do
		if not child:IsA("GuiObject") or child:GetAttribute("IndexUnitClone") ~= true then
			continue
		end

		local tier = math.floor(tonumber(child:GetAttribute("Tier")) or 0)
		local unlocked = self:isAnimeDropperUnlocked(unlockedDroppers, tier)
		local tierData = AnimeDroppers.Tiers[tier]
		local nameLabel = child:FindFirstChild("Name", true)
		if nameLabel and (nameLabel:IsA("TextLabel") or nameLabel:IsA("TextButton")) then
			nameLabel.Text = if unlocked and tierData
				then tierData.DisplayName or tierData.ModelName or ("Unit " .. tostring(tier))
				else "???"
		end

		local icon = child:FindFirstChild("Icon", true)
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			icon.ImageColor3 = if unlocked then INDEX_UNLOCKED_COLOR else INDEX_LOCKED_COLOR
		end
	end
end

function MainGuiController:buildIndexFrame()
	local frame = self:getIndexFrame()
	local template = self:getIndexTemplate()
	if not frame or not template then
		return
	end

	local scrollingFrame = template.Parent
	if not scrollingFrame then
		return
	end

	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("IndexUnitClone") == true then
			child:Destroy()
		end
	end

	for tier = 1, AnimeDroppers.MaxTier do
		local tierData = AnimeDroppers.Tiers[tier]
		if not tierData then
			continue
		end

		local item = template:Clone()
		item.Name = "Unit" .. tostring(tier)
		item.LayoutOrder = tier
		item.Visible = true
		item:SetAttribute("IndexUnitClone", true)
		item:SetAttribute("Tier", tier)

		local nameLabel = item:FindFirstChild("Name", true)
		if nameLabel and (nameLabel:IsA("TextLabel") or nameLabel:IsA("TextButton")) then
			nameLabel.Text = tierData.DisplayName or tierData.ModelName or ("Unit " .. tostring(tier))
		end

		local icon = item:FindFirstChild("Icon", true)
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			local configuredIcon = self:getConfiguredUnitIcon(tierData)
			if configuredIcon ~= "" then
				icon.Image = configuredIcon
			end
		end

		item.Parent = scrollingFrame
	end

	self:refreshIndexFrame()
end

function MainGuiController:setIndexFrameOpen(open: boolean)
	local frame = self:getIndexFrame()
	if not frame then
		return
	end

	OpenFrame.SetupFrame(frame)
	OpenFrame.Toggle(frame, open)
end

function MainGuiController:getOwnIndexTouchPart(): BasePart?
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local tycoonName = PlayerDataController:Get("TycoonName")

	local tycoon = if tycoonName and tycoonName ~= "" then TycoonUtil.getTycoonByName(tycoonName) else nil
	if not tycoon then
		local tycoonsFolder = TycoonUtil.getTycoonsFolder()
		if tycoonsFolder then
			for _, candidate in tycoonsFolder:GetChildren() do
				if candidate:GetAttribute("Owner") == localPlayer.UserId then
					tycoon = candidate
					break
				end
			end
		end
	end

	if not tycoon then
		return nil
	end

	local indexModel = tycoon:FindFirstChild("Index", true)
	local touchPart = indexModel and indexModel:FindFirstChild("TouchPart", true)
	if touchPart and touchPart:IsA("BasePart") then
		return touchPart
	end

	local fallbackTouchPart = tycoon:FindFirstChild("TouchPart", true)
	if fallbackTouchPart and fallbackTouchPart:IsA("BasePart") and fallbackTouchPart:FindFirstAncestor("Index") then
		return fallbackTouchPart
	end

	if not indexWarnedMissingTouchPart then
		indexWarnedMissingTouchPart = true
		warn("[MainGuiController] Own tycoon Index.TouchPart not found yet.")
	end

	return nil
end

function MainGuiController:isLocalCharacterPart(part: BasePart): boolean
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then
		return false
	end

	return Players:GetPlayerFromCharacter(character) == localPlayer
end

function MainGuiController:updateIndexTouchState(touching: boolean)
	if touching == indexTouching then
		local frame = self:getIndexFrame()
		if touching and not indexClosedByButton and frame and not frame.Visible then
			self:refreshIndexFrame()
			self:setIndexFrameOpen(true)
		end

		return
	end

	indexTouching = touching
	if touching then
		if not indexClosedByButton then
			self:refreshIndexFrame()
			self:setIndexFrameOpen(true)
		end
	else
		indexClosedByButton = false
		self:setIndexFrameOpen(false)
	end
end

function MainGuiController:hasCurrentIndexTouch(): boolean
	for part in indexTouchedParts do
		if part.Parent and self:isLocalCharacterPart(part) then
			return true
		end

		indexTouchedParts[part] = nil
	end

	local touchPart = indexTouchPart
	if not touchPart or not touchPart.Parent then
		return false
	end

	for _, part in touchPart:GetTouchingParts() do
		if part:IsA("BasePart") and self:isLocalCharacterPart(part) then
			indexTouchedParts[part] = true
			return true
		end
	end

	return false
end

function MainGuiController:clearIndexTouchPartConnections()
	for _, connection in indexTouchPartConnections do
		connection:Disconnect()
	end

	table.clear(indexTouchPartConnections)
	table.clear(indexTouchedParts)
	indexTouchPart = nil
	self:updateIndexTouchState(false)
end

function MainGuiController:bindIndexTouchPart(touchPart: BasePart)
	if indexTouchPart == touchPart then
		return
	end

	self:clearIndexTouchPartConnections()
	indexTouchPart = touchPart
	indexWarnedMissingTouchPart = false

	pcall(function()
		touchPart.CanTouch = true
	end)

	table.insert(
		indexTouchPartConnections,
		touchPart.Touched:Connect(function(hit)
			if not hit:IsA("BasePart") or not self:isLocalCharacterPart(hit) then
				return
			end

			indexTouchedParts[hit] = true
			self:updateIndexTouchState(true)
		end)
	)

	table.insert(
		indexTouchPartConnections,
		touchPart.TouchEnded:Connect(function(hit)
			if hit:IsA("BasePart") then
				indexTouchedParts[hit] = nil
			end

			task.defer(function()
				self:updateIndexTouchState(self:hasCurrentIndexTouch())
			end)
		end)
	)

	table.insert(
		indexTouchPartConnections,
		touchPart.Destroying:Connect(function()
			self:clearIndexTouchPartConnections()
		end)
	)

	self:updateIndexTouchState(self:hasCurrentIndexTouch())
end

function MainGuiController:startIndexTouchLoop()
	if indexTouchLoopConnection then
		return
	end

	local elapsed = 0
	indexTouchLoopConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < INDEX_TOUCH_DISCOVERY_INTERVAL then
			return
		end
		elapsed = 0

		local touchPart = self:getOwnIndexTouchPart()
		if touchPart then
			self:bindIndexTouchPart(touchPart)
		elseif indexTouchPart then
			self:clearIndexTouchPartConnections()
		end
	end)
end

function MainGuiController:setupIndexFrame()
	self:clearIndexConnections()

	local frame = self:getIndexFrame()
	if not frame then
		return
	end

	frame.Visible = false
	OpenFrame.SetupFrame(frame)
	self:buildIndexFrame()

	local topBar = frame:FindFirstChild("TopBar")
	local closeButton = topBar and topBar:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiObject") then
		self:connectIndexGuiActivated(closeButton, function()
			if indexTouching then
				indexClosedByButton = true
			end

			self:setIndexFrameOpen(false)
		end)
	end

	self:startIndexTouchLoop()
	if indexTouching and not indexClosedByButton then
		self:setIndexFrameOpen(true)
	end
end


end

return Index
