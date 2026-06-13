local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonNoti = require(script.Parent.ButtonNoti)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local YenUpgradesConfig = require(ReplicatedStorage.Shared.Data.YenUpgrades)
local Knit = require(ReplicatedStorage.Packages.knit)

local YenUpgrades = {}

local yenUpgradeConnections: { RBXScriptConnection } = {}
local yenUpgradeRequestOpen = false
local upgradesNotiDismissed = false

local UPGRADES_NOTI_KEY = "Upgrades"
local UPGRADES_BUTTON_NAME = "UpgradesButton"

local YEN_UPGRADE_KEYS = { "BetterMaxButton", "BetterGoldenDrops", "Pickuprange", "MoreOfflineEarnings" }

local UPGRADE_ROW_NAMES = {
	BetterMaxButton = "BetterMaxButton",
	BetterGoldenDrops = "Better Golden Drops",
	Pickuprange = "Pickuprange",
	MoreOfflineEarnings = "MoreOfflineEarnings",
}

function YenUpgrades.Install(MainGuiController)
	function MainGuiController:connectYenUpgradeGuiActivated(guiObject: GuiObject, callback: () -> ())
		local clickable = self:getClickableGui(guiObject)
		if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
			table.insert(yenUpgradeConnections, clickable.Activated:Connect(callback))
		else
			table.insert(
				yenUpgradeConnections,
				clickable.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						callback()
					end
				end)
			)
		end
	end

	function MainGuiController:clearYenUpgradeConnections()
		for _, connection in yenUpgradeConnections do
			connection:Disconnect()
		end

		table.clear(yenUpgradeConnections)
	end

	function MainGuiController:getYenUpgradesFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local frame = mainGui:FindFirstChild("YenUpgradesFrame") or mainGui:FindFirstChild("YenUpgradeFrame")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getYenUpgradeLevel(upgradeKey: string): number
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local upgrades = PlayerDataController:Get("YenUpgrades")
		if type(upgrades) ~= "table" then
			return 0
		end

		return math.max(math.floor(tonumber(upgrades[upgradeKey]) or 0), 0)
	end

	function MainGuiController:formatYenUpgradePrice(price: number?): string
		if not price then
			return "MAX"
		end

		return "¥" .. FormatUtil.formatNumber(price)
	end

	function MainGuiController:formatMultiplierLabel(multiplier: number): string
		if multiplier % 1 == 0 then
			return tostring(math.floor(multiplier)) .. "x"
		end

		return string.format("%.2f", multiplier):gsub("%.?0+$", "") .. "x"
	end

	function MainGuiController:formatMaxButtonCount(count: number): string
		count = math.max(math.floor(tonumber(count) or 0), 0)
		if count <= 0 then
			return "Locked"
		end

		return FormatUtil.formatNumber(count)
	end

	function MainGuiController:formatMaxButtonCountLabel(count: number): string
		count = math.max(math.floor(tonumber(count) or 0), 0)
		if count <= 0 then
			return "Locked"
		end

		return FormatUtil.formatNumber(count) .. "x"
	end

	function MainGuiController:findYenUpgradeRow(frame: Instance, upgradeKey: string): GuiObject?
		local rowName = UPGRADE_ROW_NAMES[upgradeKey] or upgradeKey
		local row = frame:FindFirstChild(rowName, true)
		if row and row:IsA("GuiObject") then
			return row
		end

		local fallback = frame:FindFirstChild(upgradeKey, true)
		return if fallback and fallback:IsA("GuiObject") then fallback else nil
	end

	function MainGuiController:updateBetterMaxButtonYenUpgrade(row: GuiObject)
		local level = self:getYenUpgradeLevel("BetterMaxButton")
		local currentCount = YenUpgradesConfig.getMaxButtonCount(level)
		local nextCount = YenUpgradesConfig.getNextMaxButtonCount(level)
		local isMaxed = YenUpgradesConfig.isMaxed("BetterMaxButton", level)
		local cost = YenUpgradesConfig.getCost("BetterMaxButton", level)

		self:setNamedText(row, "CurrentUnit", "Max button: " .. self:formatMaxButtonCount(currentCount))
		self:setNamedText(row, "TokenPrice", self:formatYenUpgradePrice(cost))
		self:setNamedText(
			row,
			"BuyButton",
			if isMaxed then "MAX" else "Buy " .. self:formatMaxButtonCountLabel(nextCount)
		)

		local currentTier = row:FindFirstChild("CurrentTier", true)
		local currentText = currentTier and currentTier:FindFirstChild("Multi", true)
		if currentText and currentText:IsA("TextLabel") then
			currentText.Text = self:formatMaxButtonCountLabel(currentCount)
		end

		local nextTier = row:FindFirstChild("nextTier", true)
		local nextText = nextTier and nextTier:FindFirstChild("Multi", true)
		if nextText and nextText:IsA("TextLabel") then
			nextText.Text = if isMaxed then "MAX" else self:formatMaxButtonCountLabel(nextCount)
		end
	end

	function MainGuiController:updateBetterGoldenDropsUpgrade(row: GuiObject)
		local level = self:getYenUpgradeLevel("BetterGoldenDrops")
		local currentMultiplier = YenUpgradesConfig.getCurrentGoldMultiplier(level)
		local nextMultiplier = YenUpgradesConfig.getNextGoldMultiplier(level)
		local isMaxed = YenUpgradesConfig.isMaxed("BetterGoldenDrops", level)
		local cost = YenUpgradesConfig.getCost("BetterGoldenDrops", level)

		self:setNamedText(row, "CurrentUnit", "Current multi: " .. self:formatMultiplierLabel(currentMultiplier))
		self:setNamedText(row, "TokenPrice", self:formatYenUpgradePrice(cost))
		self:setNamedText(
			row,
			"BuyButton",
			if isMaxed then "MAX" else "Buy " .. self:formatMultiplierLabel(nextMultiplier)
		)

		local currentTier = row:FindFirstChild("CurrentTier", true)
		local currentText = currentTier and currentTier:FindFirstChild("Multi", true)
		if currentText and currentText:IsA("TextLabel") then
			currentText.Text = self:formatMultiplierLabel(currentMultiplier)
		end

		local nextTier = row:FindFirstChild("nextTier", true)
		local nextText = nextTier and nextTier:FindFirstChild("Multi", true)
		if nextText and nextText:IsA("TextLabel") then
			nextText.Text = if isMaxed then "MAX" else self:formatMultiplierLabel(nextMultiplier)
		end
	end

	function MainGuiController:updatePickupRangeUpgrade(row: GuiObject)
		local level = self:getYenUpgradeLevel("Pickuprange")
		local currentMultiplier = YenUpgradesConfig.getPickupRangeMultiplier(level)
		local nextMultiplier = YenUpgradesConfig.getNextPickupRangeMultiplier(level)
		local isMaxed = YenUpgradesConfig.isMaxed("Pickuprange", level)
		local cost = YenUpgradesConfig.getCost("Pickuprange", level)

		self:setNamedText(row, "CurrentUnit", "Current multi: " .. self:formatMultiplierLabel(currentMultiplier))
		self:setNamedText(row, "TokenPrice", self:formatYenUpgradePrice(cost))
		self:setNamedText(
			row,
			"BuyButton",
			if isMaxed then "MAX" else "Buy " .. self:formatMultiplierLabel(nextMultiplier)
		)

		local currentTier = row:FindFirstChild("CurrentTier", true)
		local currentText = currentTier and currentTier:FindFirstChild("Multi", true)
		if currentText and currentText:IsA("TextLabel") then
			currentText.Text = self:formatMultiplierLabel(currentMultiplier)
		end

		local nextTier = row:FindFirstChild("nextTier", true)
		local nextText = nextTier and nextTier:FindFirstChild("Multi", true)
		if nextText and nextText:IsA("TextLabel") then
			nextText.Text = if isMaxed then "MAX" else self:formatMultiplierLabel(nextMultiplier)
		end
	end

	function MainGuiController:updateMoreOfflineEarningsUpgrade(row: GuiObject)
		local level = self:getYenUpgradeLevel("MoreOfflineEarnings")
		local currentMultiplier = YenUpgradesConfig.getOfflineEarningsMultiplier(level)
		local nextMultiplier = YenUpgradesConfig.getNextOfflineEarningsMultiplier(level)
		local isMaxed = YenUpgradesConfig.isMaxed("MoreOfflineEarnings", level)
		local cost = YenUpgradesConfig.getCost("MoreOfflineEarnings", level)

		self:setNamedText(row, "CurrentUnit", "Current multi: " .. self:formatMultiplierLabel(currentMultiplier))
		self:setNamedText(row, "TokenPrice", self:formatYenUpgradePrice(cost))
		self:setNamedText(
			row,
			"BuyButton",
			if isMaxed then "MAX" else "Buy " .. self:formatMultiplierLabel(nextMultiplier)
		)

		local currentTier = row:FindFirstChild("CurrentTier", true)
		local currentText = currentTier and currentTier:FindFirstChild("Multi", true)
		if currentText and currentText:IsA("TextLabel") then
			currentText.Text = self:formatMultiplierLabel(currentMultiplier)
		end

		local nextTier = row:FindFirstChild("nextTier", true)
		local nextText = nextTier and nextTier:FindFirstChild("Multi", true)
		if nextText and nextText:IsA("TextLabel") then
			nextText.Text = if isMaxed then "MAX" else self:formatMultiplierLabel(nextMultiplier)
		end
	end

	function MainGuiController:canAffordAnyYenUpgrade(): boolean
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local yen = math.max(math.floor(tonumber(PlayerDataController:Get("Yen")) or 0), 0)

		for _, upgradeKey in YEN_UPGRADE_KEYS do
			local level = self:getYenUpgradeLevel(upgradeKey)
			if YenUpgradesConfig.isMaxed(upgradeKey, level) then
				continue
			end

			local cost = YenUpgradesConfig.getCost(upgradeKey, level)
			if type(cost) == "number" and yen >= cost then
				return true
			end
		end

		return false
	end

	function MainGuiController:shouldShowUpgradesButtonNoti(): boolean
		if not self:canAffordAnyYenUpgrade() then
			upgradesNotiDismissed = false
			return false
		end

		return not upgradesNotiDismissed
	end

	function MainGuiController:updateUpgradesButtonNoti()
		ButtonNoti.update(self, UPGRADES_NOTI_KEY, UPGRADES_BUTTON_NAME, self:shouldShowUpgradesButtonNoti())
	end

	function MainGuiController:updateYenUpgradesFrame(force: boolean?)
		local frame = self:getYenUpgradesFrame()
		if not frame then
			return
		end
		if not force and not frame.Visible then
			self:updateUpgradesButtonNoti()
			return
		end

		local betterMaxButton = self:findYenUpgradeRow(frame, "BetterMaxButton")
		if betterMaxButton then
			self:updateBetterMaxButtonYenUpgrade(betterMaxButton)
		end

		local betterGoldenDrops = self:findYenUpgradeRow(frame, "BetterGoldenDrops")
		if betterGoldenDrops then
			self:updateBetterGoldenDropsUpgrade(betterGoldenDrops)
		end

		local pickupRange = self:findYenUpgradeRow(frame, "Pickuprange")
		if pickupRange then
			self:updatePickupRangeUpgrade(pickupRange)
		end

		local moreOfflineEarnings = self:findYenUpgradeRow(frame, "MoreOfflineEarnings")
		if moreOfflineEarnings then
			self:updateMoreOfflineEarningsUpgrade(moreOfflineEarnings)
		end

		self:updateUpgradesButtonNoti()
	end

	function MainGuiController:buyYenUpgrade(upgradeKey: string, displayName: string)
		if yenUpgradeRequestOpen then
			return
		end

		yenUpgradeRequestOpen = true
		local TycoonService = Knit.GetService("TycoonService")
		TycoonService:BuyYenUpgrade(upgradeKey)
			:andThen(function(success, err)
				yenUpgradeRequestOpen = false
				if success then
					SoundUtil.TutorialProgress()
					self:ShowRebirthUpgradeMessage(displayName)
					self:updateYenUpgradesFrame()
				elseif err == "Not enough yen" then
					self:ShowNotEnoughYenMessage()
				elseif err == "Maxed" then
					self:ShowRebirthUpgradeMaxedMessage()
					self:updateYenUpgradesFrame()
				elseif err then
					warn("[MainGuiController] Yen upgrade failed:", err)
				end
			end)
			:catch(function(err)
				yenUpgradeRequestOpen = false
				warn("[MainGuiController] Yen upgrade failed:", err)
			end)
	end

	function MainGuiController:setupYenUpgradesFrame()
		self:clearYenUpgradeConnections()

		local frame = self:getYenUpgradesFrame()
		if not frame then
			return
		end

		frame.Visible = false
		OpenFrame.SetupFrame(frame)
		self:updateYenUpgradesFrame(true)

		local closeButton = frame:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiObject") then
			self:connectYenUpgradeGuiActivated(closeButton, function()
				OpenFrame.Toggle(frame, false)
			end)
		end

		local upgradeBindings = {
			{ "BetterMaxButton", "Better Max Button" },
			{ "BetterGoldenDrops", "Better Golden Drops" },
			{ "Pickuprange", "Pickup Range" },
			{ "MoreOfflineEarnings", "More Offline Earnings" },
		}

		for _, binding in upgradeBindings do
			local upgradeKey = binding[1]
			local displayName = binding[2]
			local row = self:findYenUpgradeRow(frame, upgradeKey)
			local buyButton = row and row:FindFirstChild("BuyButton", true)
			if buyButton and buyButton:IsA("GuiObject") then
				self:connectYenUpgradeGuiActivated(buyButton, function()
					self:buyYenUpgrade(upgradeKey, displayName)
				end)
			end
		end

		ButtonNoti.hideInitially(self, UPGRADES_BUTTON_NAME)

		local upgradesButton = self:getRightSideButton(UPGRADES_BUTTON_NAME)
		if upgradesButton then
			self:connectYenUpgradeGuiActivated(upgradesButton, function()
				upgradesNotiDismissed = true
				self:updateUpgradesButtonNoti()
				OpenFrame.Toggle(frame)
				self:updateYenUpgradesFrame(true)
			end)
		end

		self:updateUpgradesButtonNoti()
	end
end

return YenUpgrades
