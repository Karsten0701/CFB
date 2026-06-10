local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Monetization = require(game:GetService("ReplicatedStorage").Shared.Data.Monetization)
local Knit = require(game:GetService("ReplicatedStorage").Packages.knit)

local Gift = {}

local localPlayer = Players.LocalPlayer

local activeGiftProductKey: string? = nil
local selectedRecipientUserId: number? = nil
local selectedRecipientName: string? = nil
local giftPromptOpen = false
local playerEntryByUserId: { [number]: GuiObject } = {}
local giftFrame: GuiObject? = nil
local giftListFrame: ScrollingFrame? = nil
local giftTemplate: GuiObject? = nil
local giftConfirmButton: GuiObject? = nil
local giftSelectedLabel: TextLabel? = nil
local templateDefaultColor: Color3? = nil

local SELECTED_ATTRIBUTE = "GiftRecipientSelected"
local SELECTED_LABEL_DEFAULT = "Selected: ..."
local SELECTED_COLOR = Color3.fromRGB(70, 130, 230)
local UNSELECTED_COLOR = Color3.fromRGB(45, 45, 45)

local function formatGiftUsername(playerName: string): string
	local trimmed = string.gsub(playerName or "", "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return "@Player"
	end

	if string.sub(trimmed, 1, 1) == "@" then
		return trimmed
	end

	return "@" .. trimmed
end

local function getEntryTextLabel(entry: GuiObject): TextLabel?
	local textLabel = entry:FindFirstChild("text", true)
	if textLabel and textLabel:IsA("TextLabel") then
		return textLabel
	end

	local nameLabel = entry:FindFirstChild("Name", true)
		or entry:FindFirstChild("Username", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		return nameLabel
	end

	return entry:FindFirstChildWhichIsA("TextLabel", true)
end

local function updateSelectedLabel()
	if not giftSelectedLabel then
		return
	end

	if selectedRecipientName and selectedRecipientName ~= "" then
		giftSelectedLabel.Text = "Selected: " .. formatGiftUsername(selectedRecipientName)
	else
		giftSelectedLabel.Text = SELECTED_LABEL_DEFAULT
	end
end

local function applyEntrySelectionVisual(entry: GuiObject, selected: boolean)
	entry:SetAttribute(SELECTED_ATTRIBUTE, selected)

	if entry:IsA("GuiButton") then
		entry.AutoButtonColor = not selected
		if selected then
			entry.BackgroundColor3 = SELECTED_COLOR
		elseif templateDefaultColor then
			entry.BackgroundColor3 = templateDefaultColor
		end
	end
end

local function setSelectedEntry(userId: number?, username: string?)
	selectedRecipientUserId = userId
	selectedRecipientName = username

	for entryUserId, entry in playerEntryByUserId do
		applyEntrySelectionVisual(entry, entryUserId == userId)
	end

	updateSelectedLabel()
end

local function clearPlayerEntries()
	for _, entry in playerEntryByUserId do
		entry:Destroy()
	end
	table.clear(playerEntryByUserId)
	selectedRecipientUserId = nil
	selectedRecipientName = nil
	updateSelectedLabel()
end

local function hideGiftFrame()
	if giftFrame then
		giftFrame.Visible = false
	end
	clearPlayerEntries()
	activeGiftProductKey = nil

	local MonetizationService = Knit.GetService("MonetizationService")
	MonetizationService:CancelGift()
end

local function bindPlayerEntry(MainGuiController, entry: GuiObject, entryData)
	local userId = entryData.UserId
	local username = entryData.Name or entryData.DisplayName or "Player"
	playerEntryByUserId[userId] = entry
	entry:SetAttribute("GiftRecipientUserId", userId)
	entry.Visible = true
	applyEntrySelectionVisual(entry, false)

	local nameLabel = getEntryTextLabel(entry)
	if nameLabel then
		nameLabel.Text = formatGiftUsername(username)
	end

	MainGuiController:connectGuiActivated(entry, function()
		setSelectedEntry(userId, username)
	end)
end

local function populateGiftPlayers(MainGuiController, giftProductKey: string)
	if not giftListFrame or not giftTemplate then
		return
	end

	clearPlayerEntries()

	local MonetizationService = Knit.GetService("MonetizationService")
	MonetizationService:GetGiftEligiblePlayers(giftProductKey)
		:andThen(function(players)
			if activeGiftProductKey ~= giftProductKey then
				return
			end

			for _, entryData in players do
				local entry = giftTemplate:Clone()
				entry.Name = "GiftPlayer_" .. tostring(entryData.UserId)
				entry.Parent = giftListFrame
				bindPlayerEntry(MainGuiController, entry, entryData)
			end
		end)
		:catch(function(err)
			warn("[Gift] Failed to load eligible players:", err)
		end)
end

local function openGiftFlow(MainGuiController, giftProductKey: string)
	local giftProduct = Monetization.DeveloperProducts[giftProductKey]
	if not giftProduct or not giftFrame then
		return
	end

	activeGiftProductKey = giftProductKey
	setSelectedEntry(nil, nil)
	giftFrame.Visible = true
	populateGiftPlayers(MainGuiController, giftProductKey)
end

local function confirmGiftPurchase(MainGuiController)
	if giftPromptOpen or not activeGiftProductKey or not selectedRecipientUserId then
		return
	end

	local giftProduct = Monetization.DeveloperProducts[activeGiftProductKey]
	if not giftProduct then
		return
	end

	giftPromptOpen = true
	local MonetizationService = Knit.GetService("MonetizationService")
	MonetizationService:PrepareGift(selectedRecipientUserId, activeGiftProductKey)
		:andThen(function(prepared: boolean, err: string?)
			if not prepared then
				giftPromptOpen = false
				if err == "recipient_already_owns" then
					populateGiftPlayers(MainGuiController, activeGiftProductKey :: string)
				end
				warn("[Gift] PrepareGift failed:", err)
				return
			end

			local ok, promptErr = pcall(function()
				MarketplaceService:PromptProductPurchase(localPlayer, giftProduct.ProductId)
			end)

			if not ok then
				giftPromptOpen = false
				MonetizationService:CancelGift()
				warn("[Gift] Prompt failed:", promptErr)
			end
		end)
		:catch(function(err)
			giftPromptOpen = false
			warn("[Gift] PrepareGift error:", err)
		end)
end

function Gift.Install(MainGuiController)
	function MainGuiController:getGiftFrame(): GuiObject?
		local shopFrame = self:getShopFrame()
		if not shopFrame then
			return nil
		end

		local frame = shopFrame:FindFirstChild("GiftFrame", true)
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:setupGiftFeature()
		giftFrame = self:getGiftFrame()
		if not giftFrame then
			return
		end

		giftFrame.Visible = false

		giftListFrame = giftFrame:FindFirstChild("ScrollingFrame") :: ScrollingFrame?
		if not giftListFrame or not giftListFrame:IsA("ScrollingFrame") then
			local fallbackList = giftFrame:FindFirstChild("PlayerList", true)
				or giftFrame:FindFirstChild("List", true)
			giftListFrame = if fallbackList and fallbackList:IsA("ScrollingFrame") then fallbackList else nil
		end

		giftTemplate = nil
		if giftListFrame then
			giftTemplate = giftListFrame:FindFirstChild("Template") :: GuiObject?
		end
		if not giftTemplate then
			giftTemplate = giftFrame:FindFirstChild("Template", true) :: GuiObject?
		end

		giftConfirmButton = giftFrame:FindFirstChild("Gift") :: GuiObject?
		if not giftConfirmButton or not giftConfirmButton:IsA("GuiObject") then
			giftConfirmButton = giftFrame:FindFirstChild("User", true) :: GuiObject?
		end

		local selected = giftFrame:FindFirstChild("Selected")
		giftSelectedLabel = if selected and selected:IsA("TextLabel") then selected else nil

		if giftTemplate and giftTemplate:IsA("GuiObject") then
			if giftTemplate:IsA("GuiButton") then
				templateDefaultColor = giftTemplate.BackgroundColor3
			end
			giftTemplate.Visible = false
		end

		updateSelectedLabel()

		local closeButton = giftFrame:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiObject") then
			self:connectGuiActivated(closeButton, function()
				hideGiftFrame()
			end)
		end

		if giftConfirmButton and giftConfirmButton:IsA("GuiObject") then
			self:connectGuiActivated(giftConfirmButton, function()
				confirmGiftPurchase(self)
			end)
		end

		local shopFrame = self:getShopFrame()
		local scrollingFrame = shopFrame and shopFrame:FindFirstChild("ScrollingFrame")
		if not scrollingFrame then
			return
		end

		local function bindGiftButton(itemRoot: GuiObject, giftProductKey: string)
			local giftButton = itemRoot:FindFirstChild("GiftButton", true)
			if not giftButton or not giftButton:IsA("GuiObject") then
				return
			end

			self:connectGuiActivated(giftButton, function()
				openGiftFlow(self, giftProductKey)
			end)
		end

		for itemName, shopItem in Monetization.ShopItems do
			local itemRoot = scrollingFrame:FindFirstChild(itemName)
			if itemRoot and itemRoot:IsA("GuiObject") and type(shopItem.Gift) == "string" then
				bindGiftButton(itemRoot, shopItem.Gift)
			end
		end
	end

	function MainGuiController:onGiftProductPromptFinished()
		giftPromptOpen = false
		hideGiftFrame()
		self:refreshShopFeature()
	end

	function MainGuiController:clearGiftRuntimeCache()
		giftFrame = nil
		giftListFrame = nil
		giftTemplate = nil
		giftConfirmButton = nil
		giftSelectedLabel = nil
		templateDefaultColor = nil
		clearPlayerEntries()
		activeGiftProductKey = nil
		giftPromptOpen = false
	end
end

return Gift
