local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonUtil = require(ReplicatedStorage.Shared.Features.Tycoon.TycoonUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local TeleportFeature = {}

local localPlayer = Players.LocalPlayer
local teleportRefreshToken = 0
local teleportListConnections: { RBXScriptConnection } = {}
local lastTeleportAt = 0

local PRESERVED_SCROLL_CHILDREN = {
	Template = true,
	Start = true,
	End = true,
	UIListLayout = true,
	UIPadding = true,
}

local function isPreservedScrollChild(instance: Instance): boolean
	return PRESERVED_SCROLL_CHILDREN[instance.Name] == true
		or instance:IsA("UIListLayout")
		or instance:IsA("UIPadding")
		or instance:IsA("UIGridLayout")
end

local function getDisplayNameForOwner(ownerUserId: number, tycoonName: string): string
	if ownerUserId == localPlayer.UserId then
		return "Your Plot"
	end

	local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
	if ownerPlayer then
		return ownerPlayer.DisplayName
	end

	return tycoonName
end

local function setPlayerThumbnail(imageLabel: ImageLabel, userId: number)
	if userId <= 0 then
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)

		if ok and imageLabel.Parent then
			imageLabel.Image = content
		end
	end)
end

function TeleportFeature.Install(MainGuiController)
	function MainGuiController:getTeleportFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local frame = mainGui:FindFirstChild("TeleportFrame", true)
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getTeleportOpenButton(): GuiButton?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local button = mainGui:FindFirstChild("TeleportButton")
		if button and button:IsA("GuiButton") then
			return button
		end

		return nil
	end

	function MainGuiController:clearTeleportListConnections()
		for _, connection in teleportListConnections do
			connection:Disconnect()
		end
		table.clear(teleportListConnections)
	end

	function MainGuiController:bindTeleportListSignals()
		self:clearTeleportListConnections()

		local tycoonsFolder = TycoonUtil.getTycoonsFolder()
		if not tycoonsFolder then
			return
		end

		local function queueRefresh()
			self:refreshTeleportList()
		end

		table.insert(teleportListConnections, tycoonsFolder.ChildRemoved:Connect(queueRefresh))
		table.insert(
			teleportListConnections,
			tycoonsFolder.ChildAdded:Connect(function(tycoon: Instance)
				table.insert(
					teleportListConnections,
					tycoon:GetAttributeChangedSignal("Claimed"):Connect(queueRefresh)
				)
				table.insert(
					teleportListConnections,
					tycoon:GetAttributeChangedSignal("Owner"):Connect(queueRefresh)
				)
				queueRefresh()
			end)
		)

		for _, tycoon in tycoonsFolder:GetChildren() do
			table.insert(
				teleportListConnections,
				tycoon:GetAttributeChangedSignal("Claimed"):Connect(queueRefresh)
			)
			table.insert(
				teleportListConnections,
				tycoon:GetAttributeChangedSignal("Owner"):Connect(queueRefresh)
			)
		end

		table.insert(teleportListConnections, Players.PlayerAdded:Connect(queueRefresh))
		table.insert(teleportListConnections, Players.PlayerRemoving:Connect(queueRefresh))
	end

	function MainGuiController:collectClaimedTycoons(): { { Tycoon: Instance, OwnerUserId: number, TycoonName: string } }
		local entries = {}
		local tycoonsFolder = TycoonUtil.getTycoonsFolder()
		if not tycoonsFolder then
			return entries
		end

		for _, tycoon in tycoonsFolder:GetChildren() do
			if tycoon:GetAttribute("Claimed") == true then
				local ownerUserId = math.floor(tonumber(tycoon:GetAttribute("Owner")) or 0)
				if ownerUserId > 0 then
					table.insert(entries, {
						Tycoon = tycoon,
						OwnerUserId = ownerUserId,
						TycoonName = tycoon.Name,
					})
				end
			end
		end

		table.sort(entries, function(left, right)
			local leftOwn = left.OwnerUserId == localPlayer.UserId
			local rightOwn = right.OwnerUserId == localPlayer.UserId
			if leftOwn ~= rightOwn then
				return leftOwn
			end

			return left.TycoonName < right.TycoonName
		end)

		return entries
	end

	function MainGuiController:clearTeleportEntries(scrollFrame: Instance, template: Instance)
		for _, child in scrollFrame:GetChildren() do
			if child ~= template and not isPreservedScrollChild(child) then
				child:Destroy()
			end
		end
	end

	function MainGuiController:refreshTeleportList()
		local frame = self:getTeleportFrame()
		if not frame then
			return
		end

		local scrollFrame = frame:FindFirstChild("ScrollingFrame", true)
		local template = scrollFrame and scrollFrame:FindFirstChild("Template")
		if not scrollFrame or not template or not template:IsA("GuiObject") then
			warn("[MainGuiController] Teleport ScrollingFrame or Template missing")
			return
		end

		template.Visible = false

		teleportRefreshToken += 1
		local refreshToken = teleportRefreshToken

		self:clearTeleportEntries(scrollFrame, template)

		local entries = self:collectClaimedTycoons()
		for layoutOrder, entry in entries do
			if refreshToken ~= teleportRefreshToken then
				return
			end

			local row = template:Clone()
			row.Name = `Plot_{entry.TycoonName}`
			row.Visible = true
			row.LayoutOrder = layoutOrder - 1

			local playerNameLabel = row:FindFirstChild("PlayerName", true)
			if playerNameLabel and playerNameLabel:IsA("TextLabel") then
				playerNameLabel.Text = getDisplayNameForOwner(entry.OwnerUserId, entry.TycoonName)
			end

			local playerImage = row:FindFirstChild("PlayerImage", true)
			if playerImage and playerImage:IsA("ImageLabel") then
				setPlayerThumbnail(playerImage, entry.OwnerUserId)
			end

			local teleportButton = row:FindFirstChild("TeleportButton", true)
			if teleportButton and teleportButton:IsA("GuiButton") then
				local tycoonName = entry.TycoonName
				teleportButton.Activated:Connect(function()
					local now = os.clock()
					if now - lastTeleportAt < 0.75 then
						return
					end
					lastTeleportAt = now

					local TycoonService = Knit.GetService("TycoonService")
					TycoonService:TeleportToTycoon(tycoonName):andThen(function(success, err)
						if success then
							self:hideTeleportUI()
						elseif err then
							warn("[MainGuiController] Teleport failed:", err)
						end
					end)
				end)
			end

			row.Parent = scrollFrame
		end
	end

	function MainGuiController:showTeleportUI()
		local frame = self:getTeleportFrame()
		if not frame then
			return
		end

		self:refreshTeleportList()
		frame.Visible = true
	end

	function MainGuiController:hideTeleportUI()
		local frame = self:getTeleportFrame()
		if frame then
			frame.Visible = false
		end
	end

	function MainGuiController:toggleTeleportUI()
		local frame = self:getTeleportFrame()
		if not frame then
			return
		end

		if frame.Visible then
			self:hideTeleportUI()
		else
			self:showTeleportUI()
		end
	end

	function MainGuiController:setupTeleportFrame()
		local frame = self:getTeleportFrame()
		if not frame then
			return
		end

		frame.Visible = false

		local scrollFrame = frame:FindFirstChild("ScrollingFrame", true)
		local template = scrollFrame and scrollFrame:FindFirstChild("Template")
		if template and template:IsA("GuiObject") then
			template.Visible = false
		end

		local closeButton = frame:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiButton") then
			closeButton.Activated:Connect(function()
				self:hideTeleportUI()
			end)
		end

		local topBarClose = frame:FindFirstChild("TopBar", true)
		if topBarClose then
			local nestedClose = topBarClose:FindFirstChild("CloseButton", true)
			if nestedClose and nestedClose:IsA("GuiButton") then
				nestedClose.Activated:Connect(function()
					self:hideTeleportUI()
				end)
			end
		end

		local openButton = self:getTeleportOpenButton()
		if openButton then
			openButton.Activated:Connect(function()
				self:toggleTeleportUI()
			end)
		end

		self:bindTeleportListSignals()
		self:refreshTeleportList()
	end
end

return TeleportFeature
