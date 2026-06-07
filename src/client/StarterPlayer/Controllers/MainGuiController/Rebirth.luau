local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local RebirthUpgrades = require(ReplicatedStorage.Shared.Data.RebirthUpgrades)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local Knit = require(ReplicatedStorage.Packages.knit)

local Rebirth = {}

local rebirthConnections: { RBXScriptConnection } = {}
local rebirthRequestOpen = false
local rebirthUpgradeRequestOpen = false
local lastRebirthReadyRequirement: number? = nil

function Rebirth.Install(MainGuiController)
	function MainGuiController:connectRebirthGuiActivated(guiObject: GuiObject, callback: () -> ())
		local clickable = self:getClickableGui(guiObject)
		if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
			table.insert(rebirthConnections, clickable.Activated:Connect(callback))
		else
			table.insert(
				rebirthConnections,
				clickable.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						callback()
					end
				end)
			)
		end
	end

	function MainGuiController:clearRebirthConnections()
		for _, connection in rebirthConnections do
			connection:Disconnect()
		end

		table.clear(rebirthConnections)
	end

	function MainGuiController:getRebirthFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local rebirthFrame = mainGui:FindFirstChild("RebirthFrame")
		return if rebirthFrame and rebirthFrame:IsA("GuiObject") then rebirthFrame else nil
	end

	function MainGuiController:getUpgradesFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local upgradesFrame = mainGui:FindFirstChild("UpgradesFrame")
		return if upgradesFrame and upgradesFrame:IsA("GuiObject") then upgradesFrame else nil
	end

	function MainGuiController:getRebirthRequiredTier(rebirths: number): number
		local rebirthConfig = TycoonConfig.Rebirth
		return math.max(
			math.floor((rebirthConfig.FirstRequiredTier or 15) + rebirths * (rebirthConfig.RequiredTierStep or 5)),
			1
		)
	end

	function MainGuiController:getRebirthYenMultiplier(rebirths: number): number
		local rebirthConfig = TycoonConfig.Rebirth
		return (rebirthConfig.BaseYenMultiplier or 1) + rebirths * (rebirthConfig.YenMultiplierPerRebirth or 0)
	end

	function MainGuiController:formatRebirthMultiplier(multiplier: number): string
		if multiplier % 1 == 0 then
			return tostring(math.floor(multiplier))
		end

		return string.format("%.1f", multiplier)
	end

	function MainGuiController:formatRebirthYenBoostGain(currentMultiplier: number, nextMultiplier: number): string
		local boostGain = math.max(nextMultiplier - currentMultiplier, 0)
		local boostPercent = math.floor(boostGain * 100 + 0.5)
		return "+" .. tostring(boostPercent) .. "% Yen Boost"
	end

	function MainGuiController:getHighestUnitTier(units: any): number
		local highestTier = 0
		if type(units) ~= "table" then
			return highestTier
		end

		for _, unit in units do
			if type(unit) ~= "table" then
				continue
			end

			local tier = math.floor(tonumber(unit.Tier) or 0)
			if AnimeDroppers.Tiers[tier] then
				highestTier = math.max(highestTier, tier)
			end
		end

		return highestTier
	end

	function MainGuiController:isRebirthReady(): (boolean, number)
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local rebirths = math.max(math.floor(PlayerDataController:Get("Rebirths") or 0), 0)
		local requiredTier = self:getRebirthRequiredTier(rebirths)
		return self:getHighestUnitTier(PlayerDataController:Get("Units")) >= requiredTier, requiredTier
	end

	function MainGuiController:syncRebirthReadyState(allowMessage: boolean?)
		local ready, requiredTier = self:isRebirthReady()
		if ready then
			if lastRebirthReadyRequirement ~= requiredTier then
				lastRebirthReadyRequirement = requiredTier
				if allowMessage == true then
					self:ShowRebirthReadyMessage()
				end
			end
		else
			lastRebirthReadyRequirement = nil
		end
	end

	function MainGuiController:getOwnedManaMultiplierBoost(): number
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local purchasedProducts = PlayerDataController:Get("PurchasedProducts")
		local entitlements = self:getSettingsEntitlements()
		local ownsDoubleMana = (type(purchasedProducts) == "table" and purchasedProducts.DoubleMana == true)
			or (type(entitlements) == "table" and entitlements.DoubleMana == true)

		if ownsDoubleMana then
			return 2
		end

		return 1
	end

	function MainGuiController:setNamedText(root: Instance, name: string, text: string)
		local target = root:FindFirstChild(name, true)
		if target and (target:IsA("TextLabel") or target:IsA("TextButton")) then
			target.Text = text
		end
	end

	function MainGuiController:setNamedImage(root: Instance, name: string, imageId: string?, imageColor: Color3?)
		local target = root:FindFirstChild(name, true)
		if target and (target:IsA("ImageLabel") or target:IsA("ImageButton")) then
			target.Image = imageId or ""
			target.ImageColor3 = imageColor or Color3.new(1, 1, 1)
		end
	end

	function MainGuiController:getRightSideButton(buttonName: string): GuiObject?
		local mainGui = self:getMainGui()
		local rightSide = mainGui and mainGui:FindFirstChild("RightSide")
		if not rightSide then
			return nil
		end

		local button = rightSide:FindFirstChild(buttonName, true)
		return if button and button:IsA("GuiObject") then button else nil
	end

	function MainGuiController:updateRebirthFrame(rebirthOverride: number?)
		local frame = self:getRebirthFrame()
		if not frame then
			return
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		local rebirths = math.max(math.floor(rebirthOverride or PlayerDataController:Get("Rebirths") or 0), 0)
		local nextRebirths = rebirths + 1
		local requiredTier = self:getRebirthRequiredTier(rebirths)
		local currentMultiplier = self:getRebirthYenMultiplier(rebirths)
		local nextMultiplier = self:getRebirthYenMultiplier(nextRebirths)

		self:setNamedText(frame, "TierReq", "Reach Tier " .. requiredTier)
		self:setNamedText(frame, "Boost", self:formatRebirthYenBoostGain(currentMultiplier, nextMultiplier))
	end

	function MainGuiController:getUpgradeLevel(upgradeKey: string): number
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local upgrades = PlayerDataController:Get("RebirthUpgrades")
		if type(upgrades) ~= "table" then
			return 0
		end

		return math.max(math.floor(tonumber(upgrades[upgradeKey]) or 0), 0)
	end

	function MainGuiController:formatTokenPrice(price: number?): string
		if not price then
			return "MAX"
		end

		local suffix = if price == 1 then " Token" else " Tokens"
		return FormatUtil.formatNumber(price) .. suffix
	end

	function MainGuiController:formatUpgradePrice(upgradeKey: string, price: number?): string
		if not price then
			return "MAX"
		end

		local config = RebirthUpgrades[upgradeKey]
		if type(config) == "table" and config.kind == "Yen" then
			return "¥" .. FormatUtil.formatNumber(price)
		end

		return self:formatTokenPrice(price)
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

	function MainGuiController:updateUnitSpawnTierUpgrade(row: GuiObject)
		local level = self:getUpgradeLevel("UnitSpawnTier")
		local currentTier = RebirthUpgrades.getUnitSpawnTier(level)
		local nextTier = RebirthUpgrades.getUnitSpawnTier(level + 1)
		local isMaxed = RebirthUpgrades.isMaxed("UnitSpawnTier", level)
		local currentData = AnimeDroppers.Tiers[currentTier] or AnimeDroppers.Tiers[1]
		local nextData = AnimeDroppers.Tiers[nextTier] or currentData
		local cost = RebirthUpgrades.getCost("UnitSpawnTier", level)

		self:setNamedImage(row, "CurrentTier", currentData and currentData.IconId, Color3.new(1, 1, 1))
		self:setNamedImage(
			row,
			"nextTier",
			nextData and nextData.IconId,
			if isMaxed then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
		)
		self:setNamedText(row, "CurrentUnit", "Current unit: " .. (currentData and currentData.DisplayName or "..."))
		self:setNamedText(row, "TokenPrice", self:formatUpgradePrice("UnitSpawnTier", cost))
		self:setNamedText(row, "BuyButton", if isMaxed then "MAX" else "Buy T" .. tostring(nextTier))

		local currentTierLabel = row:FindFirstChild("CurrentTier", true)
		local currentText = currentTierLabel and currentTierLabel:FindFirstChild("Tier", true)
		if currentText and currentText:IsA("TextLabel") then
			currentText.Text = "T" .. tostring(currentTier)
		end

		local nextTierLabel = row:FindFirstChild("nextTier", true)
		local nextText = nextTierLabel and nextTierLabel:FindFirstChild("Tier", true)
		if nextText and nextText:IsA("TextLabel") then
			nextText.Text = if isMaxed then "MAX" else "T" .. tostring(nextTier)
		end
	end

	function MainGuiController:updateMoreManaUpgrade(row: GuiObject)
		local level = self:getUpgradeLevel("MoreMana")
		local ownedBoost = self:getOwnedManaMultiplierBoost()
		local currentMultiplier = RebirthUpgrades.getManaMultiplier(level) * ownedBoost
		local nextMultiplier = RebirthUpgrades.getManaMultiplier(level + 1) * ownedBoost
		local isMaxed = RebirthUpgrades.isMaxed("MoreMana", level)
		local cost = RebirthUpgrades.getCost("MoreMana", level)

		self:setNamedText(
			row,
			"CurrentUnit",
			"Current multi: " .. self:formatRebirthMultiplier(currentMultiplier) .. "x"
		)
		self:setNamedText(row, "TokenPrice", self:formatUpgradePrice("MoreMana", cost))
		self:setNamedText(
			row,
			"BuyButton",
			if isMaxed then "MAX" else "Buy " .. self:formatRebirthMultiplier(nextMultiplier) .. "x"
		)

		local currentTier = row:FindFirstChild("CurrentTier", true)
		local currentText = currentTier and currentTier:FindFirstChild("Multi", true)
		if currentText and currentText:IsA("TextLabel") then
			currentText.Text = self:formatRebirthMultiplier(currentMultiplier) .. "x"
		end

		local nextTier = row:FindFirstChild("nextTier", true)
		local nextText = nextTier and nextTier:FindFirstChild("Multi", true)
		if nextText and nextText:IsA("TextLabel") then
			nextText.Text = if isMaxed then "MAX" else self:formatRebirthMultiplier(nextMultiplier) .. "x"
		end
	end

	function MainGuiController:updateBetterMaxButtonUpgrade(row: GuiObject)
		local level = self:getUpgradeLevel("BetterMaxButton")
		local currentCount = RebirthUpgrades.getMaxButtonCount(level)
		local nextCount = RebirthUpgrades.getNextMaxButtonCount(level)
		local isMaxed = RebirthUpgrades.isMaxed("BetterMaxButton", level)
		local cost = RebirthUpgrades.getCost("BetterMaxButton", level)

		self:setNamedText(row, "CurrentUnit", "Max button: " .. self:formatMaxButtonCount(currentCount))
		self:setNamedText(row, "TokenPrice", self:formatUpgradePrice("BetterMaxButton", cost))
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

	function MainGuiController:updateUpgradesFrame()
		local frame = self:getUpgradesFrame()
		if not frame then
			return
		end

		local unitSpawnTier = frame:FindFirstChild("UnitSpawnTier", true)
		if unitSpawnTier and unitSpawnTier:IsA("GuiObject") then
			self:updateUnitSpawnTierUpgrade(unitSpawnTier)
		end

		local moreMana = frame:FindFirstChild("MoreMana", true)
		if moreMana and moreMana:IsA("GuiObject") then
			self:updateMoreManaUpgrade(moreMana)
		end

		local betterMaxButton = frame:FindFirstChild("BetterMaxButton", true)
		if betterMaxButton and betterMaxButton:IsA("GuiObject") then
			self:updateBetterMaxButtonUpgrade(betterMaxButton)
		end
	end

	function MainGuiController:buyRebirthUpgrade(upgradeKey: string, displayName: string)
		if rebirthUpgradeRequestOpen then
			return
		end

		rebirthUpgradeRequestOpen = true
		local TycoonService = Knit.GetService("TycoonService")
		TycoonService:BuyRebirthUpgrade(upgradeKey)
			:andThen(function(success, err)
				rebirthUpgradeRequestOpen = false
				if success then
					SoundUtil.TutorialProgress()
					self:ShowRebirthUpgradeMessage(displayName)
					self:updateUpgradesFrame()
				elseif err == "Not enough tokens" then
					self:ShowNotEnoughRebirthTokensMessage()
				elseif err == "Not enough yen" then
					self:ShowNotEnoughYenMessage()
				elseif err == "Maxed" then
					self:ShowRebirthUpgradeMaxedMessage()
					self:updateUpgradesFrame()
				elseif err then
					warn("[MainGuiController] Rebirth upgrade failed:", err)
				end
			end)
			:catch(function(err)
				rebirthUpgradeRequestOpen = false
				warn("[MainGuiController] Rebirth upgrade failed:", err)
			end)
	end

	function MainGuiController:setupRebirthFrame()
		self:clearRebirthConnections()

		local frame = self:getRebirthFrame()
		if not frame then
			return
		end

		OpenFrame.SetupFrame(frame)
		self:updateRebirthFrame()

		local topBar = frame:FindFirstChild("TopBar")
		local closeButton = topBar and topBar:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiObject") then
			self:connectRebirthGuiActivated(closeButton, function()
				OpenFrame.Toggle(frame)
			end)
		end

		local acceptButton = frame:FindFirstChild("AcceptButton", true)
		if acceptButton and acceptButton:IsA("GuiObject") then
			self:connectRebirthGuiActivated(acceptButton, function()
				if rebirthRequestOpen then
					return
				end

				rebirthRequestOpen = true
				local TycoonService = Knit.GetService("TycoonService")
				TycoonService:Rebirth()
					:andThen(function(success, err, rebirths, tokenReward)
						rebirthRequestOpen = false
						if success then
							SoundUtil.TutorialProgress()
							local TycoonController = Knit.GetController("TycoonController")
							local CapsuleController = Knit.GetController("CapsuleController")
							CapsuleController:ClearCapsules()
							TycoonController:ClearOwnDrops()
							self:ShowRebirthMessage(rebirths or 0, tokenReward or 0)
							self:updateRebirthFrame(rebirths)
							OpenFrame.Toggle(frame, false)
						elseif err == "Required tier missing" then
							self:ShowMissingRebirthTierMessage()
						elseif err then
							warn("[MainGuiController] Rebirth failed:", err)
						end
					end)
					:catch(function(err)
						rebirthRequestOpen = false
						warn("[MainGuiController] Rebirth failed:", err)
					end)
			end)
		end

		local upgradesButton = frame:FindFirstChild("Upgrades", true)
		if upgradesButton and upgradesButton:IsA("GuiObject") then
			self:connectRebirthGuiActivated(upgradesButton, function()
				local upgradesFrame = self:getUpgradesFrame()
				if upgradesFrame then
					self:updateUpgradesFrame()
					self:setCurrencyDisplayMode("RebirthTokens")
					OpenFrame.Toggle(upgradesFrame, true)
				end
			end)
		end

		local rebirthButton = self:getRightSideButton("RebirthButton")
		if rebirthButton then
			self:connectRebirthGuiActivated(rebirthButton, function()
				self:updateRebirthFrame()
				OpenFrame.Toggle(frame)
			end)
		end
	end

	function MainGuiController:setupUpgradesFrame()
		local frame = self:getUpgradesFrame()
		if not frame then
			return
		end

		frame.Visible = false
		OpenFrame.SetupFrame(frame)
		self:updateUpgradesFrame()
		table.insert(
			rebirthConnections,
			frame:GetPropertyChangedSignal("Visible"):Connect(function()
				self:setCurrencyDisplayMode(if frame.Visible then "RebirthTokens" else "Yen")
			end)
		)

		local closeButton = frame:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiObject") then
			self:connectRebirthGuiActivated(closeButton, function()
				self:setCurrencyDisplayMode("Yen")
				OpenFrame.Toggle(frame, false)
			end)
		end

		local unitSpawnTier = frame:FindFirstChild("UnitSpawnTier", true)
		local unitBuyButton = unitSpawnTier and unitSpawnTier:FindFirstChild("BuyButton", true)
		if unitBuyButton and unitBuyButton:IsA("GuiObject") then
			self:connectRebirthGuiActivated(unitBuyButton, function()
				self:buyRebirthUpgrade("UnitSpawnTier", "Unit Spawn Tier")
			end)
		end

		local moreMana = frame:FindFirstChild("MoreMana", true)
		local moreManaBuyButton = moreMana and moreMana:FindFirstChild("BuyButton", true)
		if moreManaBuyButton and moreManaBuyButton:IsA("GuiObject") then
			self:connectRebirthGuiActivated(moreManaBuyButton, function()
				self:buyRebirthUpgrade("MoreMana", "More Mana")
			end)
		end

		local betterMaxButton = frame:FindFirstChild("BetterMaxButton", true)
		local betterMaxBuyButton = betterMaxButton and betterMaxButton:FindFirstChild("BuyButton", true)
		if betterMaxBuyButton and betterMaxBuyButton:IsA("GuiObject") then
			self:connectRebirthGuiActivated(betterMaxBuyButton, function()
				self:buyRebirthUpgrade("BetterMaxButton", "Better Max Button")
			end)
		end
	end
end

return Rebirth
