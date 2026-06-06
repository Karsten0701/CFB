local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local AnimeDroppers = require(ReplicatedStorage.Shared.Data.AnimeDroppers)
local ButtonPress = require(ReplicatedStorage.Shared.Observers.Button)
local EventUtil = require(ReplicatedStorage.Shared.Features.Events.EventUtil)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Loading = require(ReplicatedStorage.Shared.Performance.Loading)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local RebirthUpgrades = require(ReplicatedStorage.Shared.Data.RebirthUpgrades)
local ShowOther = require(ReplicatedStorage.Shared.Performance.ShowOther)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local DepositVFX = require(script.Parent.Parent.Parent.Features.Tycoon.DepositVFX)
local TycoonRenderer = require(script.Parent.Parent.Parent.Features.Tycoon.TycoonRenderer)
local TycoonUtil = require(ReplicatedStorage.Shared.Features.Tycoon.TycoonUtil)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Knit = require(ReplicatedStorage.Packages.knit)

local TycoonController = Knit.CreateController({
	Name = "TycoonController",
})

local localPlayer = Players.LocalPlayer
local renderers: { [Instance]: any } = {}
local buttonActions: { [BasePart]: { kind: string, amount: number?, buttonName: string } } = {}
local buttonModelsByTycoon: { [Instance]: { Model } } = {}
local buttonDisplayCache: { [Instance]: { [string]: any } } = {}
local buttonInfoCache: { [Instance]: { [string]: any } } = {}
local buttonBillboardCacheByTycoon: { [Instance]: { BillboardGui } } = {}
local buttonBillboardsEnabledByTycoon: { [Instance]: boolean } = {}
local buttonPriceUpdateScheduled: { [Instance]: boolean } = {}
local buyUnitTierCache: { [Instance]: number } = {}
local lastActionAt: { [BasePart]: number } = {}
local wasStandingOnButton: { [BasePart]: boolean } = {}
local standingLoopConnection: RBXScriptConnection? = nil
local actionTycoon: Instance? = nil
local productPromptOpen = false
local activeProductPromptHead: BasePart? = nil
local productPromptToken = 0
local pendingRobuxUnitAmount: number? = nil
local pendingManaPickups: { number } = {}
local manaPickupFlushScheduled = false
local monetizationEntitlements: { [string]: boolean } = {}
local otherTycoonStreamingConnection: RBXScriptConnection? = nil
local lastOtherTycoonStreamAt = 0
local lastGroupRewardDisplayAt = 0
local groupJoinPromptOpen = false
local otherTycoonRefreshToken = 0
local otherTycoonRefreshRunning = false
local lastAppliedEventId: string? = nil
local groupRewardWasOnCooldown = false
local groupRewardReadyNotified = false

local ACTION_COOLDOWN = 1.12
local OTHER_TYCOON_STREAM_INTERVAL = 0.75
local OTHER_TYCOON_VISUAL_REFRESH_INTERVAL = 3
local OTHER_TYCOON_BATCH_SIZE = 1
local OTHER_TYCOON_BATCH_DELAY = 0.08
local BUTTON_PRICE_UPDATE_DELAY = 0.04

local function isLocalProductPromptFinished(firstArg: any): boolean
	if firstArg == localPlayer then
		return true
	end

	if type(firstArg) == "number" then
		return firstArg == localPlayer.UserId
	end

	return false
end

local function resetProductPromptState()
	productPromptOpen = false
	if activeProductPromptHead then
		wasStandingOnButton[activeProductPromptHead] = false
		lastActionAt[activeProductPromptHead] = 0
		activeProductPromptHead = nil
	end
	pendingRobuxUnitAmount = nil
end

local function promptDevProduct(head: BasePart, productId: number)
	if productPromptOpen then
		return
	end

	productPromptOpen = true
	activeProductPromptHead = head
	productPromptToken += 1
	local token = productPromptToken

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(localPlayer, productId)
	end)

	if not ok then
		warn("[TycoonController] Product prompt failed:", err)
		resetProductPromptState()
		return
	end

	task.delay(30, function()
		if productPromptOpen and productPromptToken == token then
			resetProductPromptState()
		end
	end)
end

local function getGamePassKeyFromId(gamePassId: number): string?
	for key, gamePass in Monetization.GamePasses do
		if gamePass.PassId == gamePassId then
			return key
		end
	end

	return nil
end

local function retryManaPickup(TycoonService, amount: number, retryIndex: number)
	task.delay(retryIndex * 0.1, function()
		TycoonService:CollectMana(amount)
			:andThen(function(success, err)
				if not success and err and err ~= "Too fast" and err ~= "Invalid amount" then
					warn("[TycoonController] Mana pickup retry failed:", err)
				end
			end)
			:catch(function(err)
				if err == "Too fast" or err == "Invalid amount" then
					return
				end

				warn("[TycoonController] Mana pickup retry failed:", err)
			end)
	end)
end

local function flushManaPickups(TycoonService)
	manaPickupFlushScheduled = false
	if #pendingManaPickups <= 0 then
		return
	end

	local pickups = pendingManaPickups
	pendingManaPickups = {}

	local total = 0
	for _, amount in pickups do
		total += amount
	end

	TycoonService:CollectMana(total)
		:andThen(function(success, err)
			if success then
				return
			end

			if err and err ~= "Too fast" and err ~= "Invalid amount" then
				warn("[TycoonController] Mana pickup failed:", err)
			end

			for index, amount in pickups do
				retryManaPickup(TycoonService, amount, index)
			end
		end)
		:catch(function(err)
			warn("[TycoonController] Mana pickup failed:", err)
			for index, amount in pickups do
				retryManaPickup(TycoonService, amount, index)
			end
		end)
end

local function queueManaPickup(TycoonService, amount: number)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end

	table.insert(pendingManaPickups, amount)
	if manaPickupFlushScheduled then
		return
	end

	manaPickupFlushScheduled = true
	task.delay(0.05, function()
		flushManaPickups(TycoonService)
	end)
end

local function getButtonModelFromTaggedObject(tycoon: Instance, object: Instance): Model?
	local model = if object:IsA("Model") then object else object:FindFirstAncestorOfClass("Model")
	while model do
		if model.Parent == tycoon then
			return model
		end

		local parent = model.Parent
		if not parent or parent == tycoon then
			break
		end

		model = parent:FindFirstAncestorOfClass("Model")
	end

	return nil
end

local function getButtonHead(buttonModel: Model, taggedObject: Instance?): BasePart?
	if taggedObject and taggedObject:IsA("BasePart") then
		return taggedObject
	end

	local head = buttonModel:FindFirstChild("Head", true)
	return if head and head:IsA("BasePart") then head else nil
end

local function getButtonInfo(buttonModel: Instance)
	local cached = buttonInfoCache[buttonModel]
	if cached then
		return cached
	end

	local info = {
		RobuxBuyAmount = TycoonUtil.getRobuxBuyAmount(buttonModel),
		IsSellAll = TycoonUtil.isSellAllButton(buttonModel),
		IsGroupReward = TycoonUtil.isGroupRewardButton(buttonModel),
		IsBuyMaxUnits = TycoonUtil.isBuyMaxUnitsButton(buttonModel),
		BuyAmount = TycoonUtil.getBuyAmount(buttonModel),
		IsRateMax = TycoonUtil.isRateMaxButton(buttonModel),
		RateAmount = TycoonUtil.getRateAmount(buttonModel),
		IsMerge = TycoonUtil.isMergeButton(buttonModel),
		IsDeposit = TycoonUtil.isDepositButton(buttonModel),
	}
	info.ShouldRegister = info.RobuxBuyAmount ~= nil
		or info.IsSellAll
		or info.IsGroupReward
		or info.IsBuyMaxUnits
		or info.BuyAmount ~= nil
		or info.IsRateMax
		or info.RateAmount ~= nil
		or info.IsMerge
		or info.IsDeposit

	buttonInfoCache[buttonModel] = info
	return info
end

local function getProcesserLabels(tycoon: Instance): (TextLabel?, TextLabel?)
	local processer = tycoon:FindFirstChild("Processer") or tycoon:FindFirstChild("Processor")
	if not processer then
		return nil, nil
	end

	local tel = processer:FindFirstChild("Tel")
	if not tel then
		return nil, nil
	end

	local billboard = tel:FindFirstChild("BillboardGui")
	if not billboard then
		return nil, nil
	end

	local mpLabel = billboard:FindFirstChild("Mana") or billboard:FindFirstChild("MP")
	local rateLabel = billboard:FindFirstChild("RateText")

	return if mpLabel and mpLabel:IsA("TextLabel") then mpLabel else nil,
		if rateLabel and rateLabel:IsA("TextLabel") then rateLabel else nil
end

local function rebuildButtonBillboardCache(tycoon: Instance): { BillboardGui }
	local billboards = {}
	for _, descendant in tycoon:GetDescendants() do
		if not descendant:IsA("BillboardGui") then
			continue
		end

		local buttonModel = descendant:FindFirstAncestorOfClass("Model")
		if buttonModel and buttonModel:IsDescendantOf(tycoon) and getButtonInfo(buttonModel).ShouldRegister then
			table.insert(billboards, descendant)
		end
	end

	buttonBillboardCacheByTycoon[tycoon] = billboards
	return billboards
end

local function getButtonBillboards(tycoon: Instance): { BillboardGui }
	local cached = buttonBillboardCacheByTycoon[tycoon]
	if cached then
		for _, billboard in cached do
			if not billboard.Parent then
				return rebuildButtonBillboardCache(tycoon)
			end
		end

		return cached
	end

	return rebuildButtonBillboardCache(tycoon)
end

local function setButtonBillboardsEnabled(tycoon: Instance, enabled: boolean)
	if buttonBillboardsEnabledByTycoon[tycoon] == enabled then
		return
	end

	buttonBillboardsEnabledByTycoon[tycoon] = enabled
	for _, billboard in getButtonBillboards(tycoon) do
		if billboard.Parent then
			billboard.Enabled = enabled
		end
	end
end

local function getButtonBillboard(buttonModel: Instance): BillboardGui?
	local cached = buttonDisplayCache[buttonModel]
	if cached and cached.Billboard and cached.Billboard.Parent then
		return cached.Billboard
	end
	if cached and cached.BillboardScanned then
		return nil
	end

	local head = buttonModel:FindFirstChild("Head")
	if head then
		local billboard = head:FindFirstChild("BillboardGui")
		if billboard and billboard:IsA("BillboardGui") then
			buttonDisplayCache[buttonModel] = buttonDisplayCache[buttonModel] or {}
			buttonDisplayCache[buttonModel].Billboard = billboard
			buttonDisplayCache[buttonModel].BillboardScanned = true
			return billboard
		end
	end

	local billboard = buttonModel:FindFirstChild("BillboardGui", true)
	if billboard and billboard:IsA("BillboardGui") then
		buttonDisplayCache[buttonModel] = buttonDisplayCache[buttonModel] or {}
		buttonDisplayCache[buttonModel].Billboard = billboard
		buttonDisplayCache[buttonModel].BillboardScanned = true
		return billboard
	end

	buttonDisplayCache[buttonModel] = buttonDisplayCache[buttonModel] or {}
	buttonDisplayCache[buttonModel].BillboardScanned = true
	return nil
end

local function getBillboardTextLabel(billboard: BillboardGui?, labelName: string): TextLabel?
	if not billboard then
		return nil
	end

	local label = billboard:FindFirstChild(labelName)
	return if label and label:IsA("TextLabel") then label else nil
end

local function getButtonAmountLabel(billboard: BillboardGui?): TextLabel?
	return getBillboardTextLabel(billboard, "Amount")
		or getBillboardTextLabel(billboard, "Units")
		or getBillboardTextLabel(billboard, "Rate")
		or getBillboardTextLabel(billboard, "TextLabel")
end

local function getButtonDisplay(buttonModel: Instance)
	local cached = buttonDisplayCache[buttonModel]
	if cached and cached.Billboard and cached.Billboard.Parent then
		return cached
	end
	if cached and cached.DisplayScanned then
		return cached
	end

	local billboard = getButtonBillboard(buttonModel)
	cached = buttonDisplayCache[buttonModel] or {}
	cached.Billboard = billboard
	cached.Amount = getButtonAmountLabel(billboard)
	cached.Price = getBillboardTextLabel(billboard, "Price")
	cached.Rate = getBillboardTextLabel(billboard, "Rate")
	cached.Reward = getBillboardTextLabel(billboard, "Reward")
	cached.Timer = getBillboardTextLabel(billboard, "Group/Timer")
	cached.DisplayScanned = true
	buttonDisplayCache[buttonModel] = cached
	return cached
end

local function getBuyUnitTier(buttonModel: Instance?): number
	if not buttonModel then
		return 1
	end

	local cached = buyUnitTierCache[buttonModel]
	if cached then
		return cached
	end

	local unitTier = buttonModel:GetAttribute("UnitTier") or buttonModel:GetAttribute("BuyTier")
	if type(unitTier) == "number" then
		local tier = math.clamp(math.floor(unitTier), 1, AnimeDroppers.MaxTier)
		buyUnitTierCache[buttonModel] = tier
		return tier
	end

	local head = buttonModel:FindFirstChild("Head", true)
	local headTier = head and (head:GetAttribute("UnitTier") or head:GetAttribute("BuyTier"))
	if type(headTier) == "number" then
		local tier = math.clamp(math.floor(headTier), 1, AnimeDroppers.MaxTier)
		buyUnitTierCache[buttonModel] = tier
		return tier
	end

	buyUnitTierCache[buttonModel] = 1
	return 1
end

local function getBuyUnitText(amount: number, tier: number): string
	local tierData = AnimeDroppers.Tiers[tier] or AnimeDroppers.Tiers[1]
	local displayName = tierData and tierData.DisplayName or "Anime Unit"
	if amount ~= 1 then
		displayName ..= "s"
	end

	return "+" .. FormatUtil.formatNumber(amount) .. " " .. displayName
end

local function getGroupRewardConfig(): { [string]: any }
	return TycoonConfig.GroupReward or {}
end

local function isLocalPlayerInRewardGroup(): boolean
	local groupId = tonumber(getGroupRewardConfig().GroupId) or 0
	if groupId <= 0 then
		return false
	end

	local ok, isInGroup = pcall(function()
		return localPlayer:IsInGroup(groupId)
	end)

	return ok and isInGroup == true
end

local function getGroupRewardAmount(): number
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local config = getGroupRewardConfig()
	local baseYen = tonumber(config.BaseYen) or 500
	local yenPerBaseUnit = tonumber(config.YenPerBaseUnit) or 50
	local baseUnitCount = Pricing.getBaseUnitCount(PlayerDataController:Get("Units") or {})
	local growthMultiplier = tonumber(config.GrowthMultiplier) or 1
	local growthUnitsPerStep = math.max(tonumber(config.GrowthUnitsPerStep) or 1, 1)
	local maxGrowthMultiplier = math.max(tonumber(config.MaxGrowthMultiplier) or math.huge, 1)
	local reward = baseYen + baseUnitCount * yenPerBaseUnit
	local growth = math.min(growthMultiplier ^ (baseUnitCount / growthUnitsPerStep), maxGrowthMultiplier)
	return math.max(math.floor(reward * growth), 0)
end

local function getGroupRewardRemaining(): number
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local cooldown = tonumber(getGroupRewardConfig().Cooldown) or 2 * 60 * 60
	local lastClaimAt = math.max(math.floor(PlayerDataController:Get("LastGroupRewardClaimAt") or 0), 0)
	return math.max(math.floor(cooldown - (os.time() - lastClaimAt)), 0)
end

local function formatCountdown(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function promptJoinRewardGroup()
	if groupJoinPromptOpen then
		return
	end

	local groupId = tonumber(getGroupRewardConfig().GroupId) or 0
	if groupId <= 0 then
		return
	end

	groupJoinPromptOpen = true
	task.spawn(function()
		local ok, err = pcall(function()
			GroupService:PromptJoinAsync(groupId)
		end)
		groupJoinPromptOpen = false
		if not ok then
			warn("[TycoonController] Group join prompt failed:", err)
		end
	end)
end

local function mergeEntitlementsWithSettings(
	entitlements: { [string]: boolean },
	settings: { [string]: any }?
): { [string]: boolean }
	local merged = table.clone(entitlements or {})
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local upgrades = PlayerDataController:Get("RebirthUpgrades")
	local moreManaLevel = if type(upgrades) == "table" then upgrades.MoreMana else 0
	local purchasedProducts = PlayerDataController:Get("PurchasedProducts")
	merged.ManaMultiplier = RebirthUpgrades.getManaMultiplier(moreManaLevel)
	if merged.DoubleMana == true or (type(purchasedProducts) == "table" and purchasedProducts.DoubleMana == true) then
		merged.ManaMultiplier *= 2
	end

	if type(settings) == "table" then
		merged.AutoCollect = settings.AutoCollect == true
		merged.AutoDeposit = settings.AutoDeposit == true
		merged.ShowVFX = settings.ShowVFX ~= false
		merged.ShowManaPopup = settings.ShowManaPopup ~= false
	end

	local activeEvent = EventUtil.getActiveEvent()
	if activeEvent then
		merged.ManaMultiplier *= math.max(tonumber(activeEvent.Effects.ManaMultiplier) or 1, 0)
		merged.DropSpeedMultiplier = math.max(tonumber(activeEvent.Effects.DropSpeedMultiplier) or 1, 0.1)
	end

	return merged
end

local function getCurrentUnitSpawnTier(PlayerDataController): number
	local upgrades = PlayerDataController:Get("RebirthUpgrades")
	local unitSpawnTierLevel = if type(upgrades) == "table" then upgrades.UnitSpawnTier else 0
	local eventBonus = math.max(math.floor(EventUtil.getEffectBonus("UnitSpawnTierBonus", 0)), 0)
	return math.clamp(RebirthUpgrades.getUnitSpawnTier(unitSpawnTierLevel) + eventBonus, 1, AnimeDroppers.MaxTier)
end

local function getDepositProcessInterval(): number
	local interval = if monetizationEntitlements.DoubleDeposit then 0.5 else 1
	return interval / math.max(EventUtil.getEffectMultiplier("ProcessSpeedMultiplier", 1), 0.1)
end

function TycoonController:updateProcesserDisplay(tycoon: Instance, depositOverride: number?, rateOverride: number?)
	local mpLabel, rateLabel = getProcesserLabels(tycoon)
	if not mpLabel and not rateLabel then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local deposit = if depositOverride ~= nil then depositOverride else (PlayerDataController:Get("ManaInDeposit") or 0)
	local rate = if rateOverride ~= nil then rateOverride else (PlayerDataController:Get("Rate") or 0)

	if mpLabel then
		mpLabel.Text = FormatUtil.formatMana(math.floor(deposit))
	end

	if rateLabel then
		local intervalText = FormatUtil.formatSeconds(getDepositProcessInterval())
		rateLabel.Text = "Rate: " .. FormatUtil.formatNumber(math.floor(rate)) .. "/" .. intervalText
	end
end

function TycoonController:updateDepositVFX(tycoon: Instance, newDepositValue: number?)
	local entry = renderers[tycoon]
	if not entry or not entry.depositVFX then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local settings = PlayerDataController:Get("Settings")
	entry.depositVFX:setEnabled(settings == nil or settings.ShowVFX ~= false)

	local newDeposit = math.max(math.floor(newDepositValue or 0), 0)
	local previousDeposit = entry.lastObservedDeposit
	entry.lastObservedDeposit = newDeposit

	if previousDeposit == nil then
		entry.depositVFX:setProcessorActive(newDeposit > 0, getDepositProcessInterval())
		return
	end

	entry.depositVFX:setProcessorActive(newDeposit > 0, getDepositProcessInterval())

	if newDeposit > previousDeposit then
		entry.depositVFX:playDeposit(newDeposit - previousDeposit)
	end
end

function TycoonController:setDefaultProcesserDisplay(tycoon: Instance)
	local mpLabel, rateLabel = getProcesserLabels(tycoon)

	if mpLabel then
		mpLabel.Text = FormatUtil.formatMana(0)
	end

	if rateLabel then
		rateLabel.Text = "Rate: 1/s"
	end
end

function TycoonController:applyEntitlementsToOwnTycoon(autoEnableSetting: string?)
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local settings = PlayerDataController:Get("Settings")

	if autoEnableSetting == "AutoCollect" or autoEnableSetting == "AutoDeposit" then
		settings = table.clone(settings or {})
		settings[autoEnableSetting] = true
	end

	for tycoon, entry in renderers do
		if not entry.isOwn then
			continue
		end

		if entry.renderer then
			local autoCollect = settings and settings.AutoCollect == true
			local autoDeposit = settings and settings.AutoDeposit == true
			entry.lastAutoCollect = autoCollect
			entry.lastAutoDeposit = autoDeposit
			entry.renderer:setEntitlements(mergeEntitlementsWithSettings(monetizationEntitlements, settings))
		end

		if entry.depositVFX then
			entry.depositVFX:setEnabled(settings == nil or settings.ShowVFX ~= false)
			local deposit = PlayerDataController:Get("ManaInDeposit") or 0
			entry.depositVFX:setProcessorActive(deposit > 0, getDepositProcessInterval())
		end

		self:updateProcesserDisplay(tycoon)
	end
end

function TycoonController:refreshMonetizationEntitlements(autoEnableSetting: string?, retryCount: number?)
	local MonetizationService = Knit.GetService("MonetizationService")
	MonetizationService:GetEntitlements()
		:andThen(function(entitlements)
			monetizationEntitlements = entitlements or {}
			if autoEnableSetting and monetizationEntitlements[autoEnableSetting] == true then
				local PlayerDataController = Knit.GetController("PlayerDataController")
				PlayerDataController:SetSetting(autoEnableSetting, true)
			elseif autoEnableSetting and (retryCount or 0) < 3 then
				task.delay(0.5, function()
					self:refreshMonetizationEntitlements(autoEnableSetting, (retryCount or 0) + 1)
				end)
			end

			self:applyEntitlementsToOwnTycoon(autoEnableSetting)
		end)
		:catch(function(err)
			warn("[TycoonController] Failed to refresh entitlements:", err)
		end)
end

function TycoonController:updateGroupRewardDisplay(tycoon: Instance)
	local isInGroup = isLocalPlayerInRewardGroup()
	local remaining = getGroupRewardRemaining()
	local reward = getGroupRewardAmount()
	local buttonModels = buttonModelsByTycoon[tycoon] or {}
	local isReady = isInGroup and remaining <= 0

	if isInGroup and remaining > 0 then
		groupRewardWasOnCooldown = true
		groupRewardReadyNotified = false
	elseif isReady and groupRewardWasOnCooldown and not groupRewardReadyNotified then
		groupRewardReadyNotified = true
		groupRewardWasOnCooldown = false
		local MainGuiController = Knit.GetController("MainGuiController")
		MainGuiController:ShowGroupRewardReadyMessage()
	end

	for _, child in buttonModels do
		local info = getButtonInfo(child)
		if not child.Parent or not info.IsGroupReward then
			continue
		end

		local display = getButtonDisplay(child)
		if display.Reward and display.Reward.Parent then
			display.Reward.Text = Pricing.formatYen(reward)
		end

		if display.Timer and display.Timer.Parent then
			if not isInGroup then
				display.Timer.Text = "Join Group!"
			elseif remaining <= 0 then
				display.Timer.Text = "Ready!"
			else
				display.Timer.Text = formatCountdown(remaining)
			end
		end
	end
end

function TycoonController:updateAllDefaultProcesserDisplays()
	local tycoonsFolder = TycoonUtil.getTycoonsFolder()
	if not tycoonsFolder then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local ownName = PlayerDataController:Get("TycoonName")

	for _, tycoon in tycoonsFolder:GetChildren() do
		if tycoon.Name ~= ownName then
			self:setDefaultProcesserDisplay(tycoon)
		end
	end
end

function TycoonController:updateButtonPrices(tycoon: Instance)
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local baseUnitCount = math.max(math.floor(PlayerDataController:Get("TotalUnitsPurchased") or 0), 0)
	local buyUnitTier = getCurrentUnitSpawnTier(PlayerDataController)
	local rateLevel = PlayerDataController:Get("RateLevel") or 0
	local yen = PlayerDataController:Get("Yen") or 0
	local buttonModels = buttonModelsByTycoon[tycoon]
	if not buttonModels then
		return
	end

	self:updateGroupRewardDisplay(tycoon)

	for index = #buttonModels, 1, -1 do
		local child = buttonModels[index]
		if not child.Parent then
			table.remove(buttonModels, index)
			continue
		end

		local info = getButtonInfo(child)

		if info.IsGroupReward then
			continue
		end

		local robuxBuyAmount = info.RobuxBuyAmount
		if robuxBuyAmount then
			local display = getButtonDisplay(child)
			if display.Amount and display.Amount.Parent then
				display.Amount.Text = getBuyUnitText(robuxBuyAmount, buyUnitTier)
			end
			continue
		end

		if info.IsBuyMaxUnits then
			local maxAmount, maxPrice = Pricing.getMaxAffordableUnitPurchase(baseUnitCount, yen)
			local display = getButtonDisplay(child)
			if display.Price and display.Price.Parent then
				local displayPrice = if maxAmount > 0 then maxPrice else Pricing.getUnitBulkPrice(baseUnitCount, 1)
				display.Price.Text = Pricing.formatYen(displayPrice)
			end

			if display.Amount and display.Amount.Parent then
				display.Amount.Text = getBuyUnitText(maxAmount, buyUnitTier)
			end

			continue
		end

		local buyAmount = info.BuyAmount
		if buyAmount then
			local display = getButtonDisplay(child)
			if display.Price and display.Price.Parent then
				display.Price.Text = Pricing.formatYen(Pricing.getUnitBulkPrice(baseUnitCount, buyAmount))
			end

			if display.Amount and display.Amount.Parent then
				display.Amount.Text = getBuyUnitText(buyAmount, buyUnitTier)
			end
		end

		if info.IsRateMax then
			local maxAmount, maxPrice, maxGain = Pricing.getMaxAffordableRateUpgrade(rateLevel, yen)
			local display = getButtonDisplay(child)
			if display.Price and display.Price.Parent then
				local displayPrice = if maxAmount > 0 then maxPrice else Pricing.getRateUpgradePrice(rateLevel, 1)
				display.Price.Text = Pricing.formatYen(displayPrice)
			end

			if display.Rate and display.Rate.Parent then
				display.Rate.Text = "+" .. FormatUtil.formatNumber(maxGain) .. " Rate"
			end

			continue
		end

		local rateAmount = info.RateAmount
		if rateAmount then
			local display = getButtonDisplay(child)
			if display.Price and display.Price.Parent then
				display.Price.Text = Pricing.formatYen(Pricing.getRateUpgradePrice(rateLevel, rateAmount))
			end

			if display.Rate and display.Rate.Parent then
				display.Rate.Text = "+"
					.. FormatUtil.formatNumber(Pricing.getRateGain(rateAmount, rateLevel))
					.. " Rate"
			end
		end
	end
end

function TycoonController:scheduleButtonPriceUpdate(tycoon: Instance)
	if buttonPriceUpdateScheduled[tycoon] then
		return
	end

	buttonPriceUpdateScheduled[tycoon] = true
	task.delay(BUTTON_PRICE_UPDATE_DELAY, function()
		buttonPriceUpdateScheduled[tycoon] = nil
		if tycoon.Parent then
			self:updateButtonPrices(tycoon)
		end
	end)
end

function TycoonController:registerButtonAction(
	head: BasePart,
	action: { kind: string, amount: number?, buttonName: string }
)
	buttonActions[head] = action
end

function TycoonController:performButtonAction(head: BasePart)
	local action = buttonActions[head]
	if not action then
		return
	end

	local now = os.clock()
	if now - (lastActionAt[head] or 0) < ACTION_COOLDOWN then
		return
	end

	lastActionAt[head] = now

	local TycoonService = Knit.GetService("TycoonService")

	if action.kind == "robux_buy" and action.amount then
		local product = Monetization.getUnitProduct(action.amount)
		if product then
			pendingRobuxUnitAmount = action.amount
			promptDevProduct(head, product.ProductId)
		elseif not product then
			warn("[TycoonController] No dev product for robux unit amount:", action.amount)
		end
	elseif action.kind == "sell_all_product" then
		promptDevProduct(head, Monetization.DeveloperProducts.SellAll.ProductId)
	elseif action.kind == "group_reward" then
		local TutorialController = Knit.GetController("TutorialController")
		TutorialController:MarkGroupRewardVisited()

		if not isLocalPlayerInRewardGroup() then
			promptJoinRewardGroup()
			return
		end

		TycoonService:ClaimGroupReward(action.buttonName):andThen(function(success, err, reward)
			if success then
				SoundUtil.RewardClaim()
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowGroupRewardMessage(reward or 0)
				if actionTycoon then
					self:updateGroupRewardDisplay(actionTycoon)
				end
			elseif err == "Not in group" then
				promptJoinRewardGroup()
			elseif err and err ~= "Cooldown" then
				warn("[TycoonController] Group reward failed:", err)
			end
		end)
	elseif action.kind == "buy" and action.amount then
		TycoonService:BuyUnits(action.amount, action.buttonName):andThen(function(success, err)
			if success then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowBoughtUnitsMessage(action.amount)
			elseif err == "Not enough yen" then
				SoundUtil.Error()
			end
		end)
	elseif action.kind == "buy_max" then
		TycoonService:BuyMaxUnits(action.buttonName):andThen(function(success, err, boughtAmount)
			if success then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowBoughtUnitsMessage(boughtAmount or 0)
			elseif err == "Not enough yen" then
				SoundUtil.Error()
			elseif err and err ~= "Not enough yen" then
				warn("[TycoonController] Max buy failed:", err)
			end
		end)
	elseif action.kind == "merge" then
		TycoonService:MergeUnits(action.buttonName):andThen(function(success, err, mergedUnitCount)
			if success then
				SoundUtil.Merge()
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowMergedUnitsMessage(mergedUnitCount or 0)
			end
		end)
	elseif action.kind == "rate" and action.amount then
		TycoonService:UpgradeRate(action.amount, action.buttonName):andThen(function(success, err, boughtAmount, gain)
			if success then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowRateUpgradeMessage(gain or 0, boughtAmount or action.amount)
			elseif err == "Not enough yen" then
				SoundUtil.Error()
			elseif err then
				warn("[TycoonController] Rate upgrade failed:", err)
			end
		end)
	elseif action.kind == "rate_max" then
		TycoonService:UpgradeRateMax(action.buttonName):andThen(function(success, err, amount, gain)
			if success then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowRateUpgradeMessage(gain or 0, amount or 0)
			elseif err == "Not enough yen" then
				SoundUtil.Error()
			elseif err and err ~= "Not enough yen" then
				warn("[TycoonController] Max rate upgrade failed:", err)
			end
		end)
	elseif action.kind == "deposit" then
		TycoonService:DepositMana():andThen(function(success, err, depositedAmount)
			if not success and err and err ~= "Nothing to deposit" then
				warn("[TycoonController] Deposit failed:", err)
			elseif success then
				if (depositedAmount or 0) > 0 then
					SoundUtil.Deposit()
				end
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowDepositMessage(depositedAmount or 0)
			end
		end)
	end
end

function TycoonController:setupButtonActions(tycoon: Instance)
	actionTycoon = tycoon
	local seenButtons: { [Model]: boolean } = {}
	local nextButtonActions: { [BasePart]: { kind: string, amount: number?, buttonName: string } } = {}
	local nextButtonModels: { Model } = {}

	local function registerButtonModel(buttonModel: Model, taggedObject: Instance?)
		if seenButtons[buttonModel] then
			return
		end

		local info = getButtonInfo(buttonModel)
		if not info.ShouldRegister then
			return
		end

		seenButtons[buttonModel] = true

		local head = getButtonHead(buttonModel, taggedObject)
		if not head then
			return
		end

		table.insert(nextButtonModels, buttonModel)
		getButtonDisplay(buttonModel)
		ButtonPress.SetupButton(head)

		if info.IsSellAll then
			nextButtonActions[head] = {
				kind = "sell_all_product",
				buttonName = buttonModel.Name,
			}
			return
		end

		if info.IsGroupReward then
			nextButtonActions[head] = {
				kind = "group_reward",
				buttonName = buttonModel.Name,
			}
			return
		end

		local robuxBuyAmount = info.RobuxBuyAmount
		if robuxBuyAmount then
			nextButtonActions[head] = {
				kind = "robux_buy",
				amount = robuxBuyAmount,
				buttonName = buttonModel.Name,
			}
			return
		end

		if info.IsBuyMaxUnits then
			nextButtonActions[head] = {
				kind = "buy_max",
				buttonName = buttonModel.Name,
			}
			return
		end

		local buyAmount = info.BuyAmount
		if buyAmount then
			nextButtonActions[head] = {
				kind = "buy",
				amount = buyAmount,
				buttonName = buttonModel.Name,
			}
			return
		end

		if info.IsRateMax then
			nextButtonActions[head] = {
				kind = "rate_max",
				buttonName = buttonModel.Name,
			}
			return
		end

		local rateAmount = info.RateAmount
		if rateAmount then
			nextButtonActions[head] = {
				kind = "rate",
				amount = rateAmount,
				buttonName = buttonModel.Name,
			}
			return
		end

		if info.IsMerge then
			nextButtonActions[head] = {
				kind = "merge",
				buttonName = buttonModel.Name,
			}
			return
		end

		if info.IsDeposit then
			nextButtonActions[head] = {
				kind = "deposit",
				buttonName = buttonModel.Name,
			}
		end
	end

	for _, child in tycoon:GetChildren() do
		if child:IsA("Model") then
			registerButtonModel(child, nil)
		end
	end

	for _, descendant in tycoon:GetDescendants() do
		if descendant:IsA("Model") then
			registerButtonModel(descendant, nil)
		end
	end

	for _, taggedObject in CollectionService:GetTagged(TycoonConfig.ButtonTag) do
		if not taggedObject:IsDescendantOf(tycoon) then
			continue
		end

		local buttonModel = getButtonModelFromTaggedObject(tycoon, taggedObject)
		if buttonModel then
			registerButtonModel(buttonModel, taggedObject)
		end
	end

	buttonActions = nextButtonActions
	buttonModelsByTycoon[tycoon] = nextButtonModels
	buttonBillboardCacheByTycoon[tycoon] = nil
	buttonBillboardsEnabledByTycoon[tycoon] = nil

	for head in wasStandingOnButton do
		if not buttonActions[head] then
			wasStandingOnButton[head] = nil
			lastActionAt[head] = nil
		end
	end
end

function TycoonController:startStandingLoop()
	if standingLoopConnection then
		return
	end

	standingLoopConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if actionTycoon and now - lastGroupRewardDisplayAt >= 1 then
			lastGroupRewardDisplayAt = now
			self:updateGroupRewardDisplay(actionTycoon)
		end

		for head in buttonActions do
			local standing = ButtonPress.IsStandingOn(head)
			local action = buttonActions[head]
			local isSellAllProduct = action and action.kind == "sell_all_product"

			if standing and (not isSellAllProduct or not wasStandingOnButton[head]) then
				self:performButtonAction(head)
			end

			wasStandingOnButton[head] = standing
		end
	end)
end

function TycoonController:shouldRenderTycoon(tycoon: Instance, isOwn: boolean): boolean
	if isOwn then
		return Loading.shouldLoadTycoon(tycoon, true)
	end

	-- Other tycoon structures are already part of the map. This only gates local unit visuals.
	return Loading.shouldLoadTycoon(tycoon, false)
end

function TycoonController:setupTycoon(tycoon: Instance, isOwn: boolean): boolean
	if renderers[tycoon] then
		setButtonBillboardsEnabled(tycoon, isOwn)
		return true
	end

	if not self:shouldRenderTycoon(tycoon, isOwn) then
		if not isOwn then
			setButtonBillboardsEnabled(tycoon, false)
		end
		return false
	end

	local janitor = Janitor.new()
	local TycoonService = Knit.GetService("TycoonService")

	local onPickup = if isOwn
		then function(value: number)
			queueManaPickup(TycoonService, value)
		end
		else nil

	local renderer = TycoonRenderer.new(tycoon, janitor, onPickup)
	renderer:setIsOwn(isOwn)
	if isOwn then
		local CapsuleController = Knit.GetController("CapsuleController")
		renderer:setOnManaDropSpawned(function(dropPart: BasePart, onResult: (boolean) -> (), isCancelled: () -> boolean)
			CapsuleController:trySpawnCapsuleFromDrop(dropPart, onResult, isCancelled)
		end)
	end
	renderers[tycoon] = {
		renderer = renderer,
		depositVFX = if isOwn then DepositVFX.new(tycoon, janitor) else nil,
		janitor = janitor,
		isOwn = isOwn,
		lastVisualRefreshAt = 0,
		lastAutoCollect = nil,
		lastAutoDeposit = nil,
		lastObservedDeposit = nil,
	}
	setButtonBillboardsEnabled(tycoon, isOwn)

	if isOwn then
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetEntitlements():andThen(function(entitlements)
			monetizationEntitlements = entitlements or {}
			self:applyEntitlementsToOwnTycoon()
		end)

		self:setupButtonActions(tycoon)
		self:updateButtonPrices(tycoon)
		self:updateProcesserDisplay(tycoon)
		self:startStandingLoop()
	end

	Loading.onTycoonLoaded(tycoon)
	return true
end

function TycoonController:rebuildTycoon(tycoon: Instance, units: { { Tier: number } })
	local entry = renderers[tycoon]
	if not entry then
		return
	end

	entry.renderer:rebuild(units)
end

function TycoonController:GetOwnRenderer(): any?
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local tycoonName = PlayerDataController:Get("TycoonName")
	if type(tycoonName) ~= "string" or tycoonName == "" then
		return nil
	end

	local tycoon = TycoonUtil.getPlayerTycoon(localPlayer, tycoonName)
	if not tycoon then
		return nil
	end

	local entry = renderers[tycoon]
	return if entry then entry.renderer else nil
end

function TycoonController:ClearOwnDrops()
	table.clear(pendingManaPickups)
	manaPickupFlushScheduled = false

	for _, entry in renderers do
		if entry.isOwn and entry.renderer then
			entry.renderer:clearDrops()
		end
	end
end

function TycoonController:setupOwnTycoon(): boolean
	local PlayerDataController = Knit.GetController("PlayerDataController")

	local tycoonName = PlayerDataController:Get("TycoonName")
	if not tycoonName or tycoonName == "" then
		return false
	end

	local tycoon = TycoonUtil.getTycoonByName(tycoonName)
	if not tycoon then
		return false
	end

	if not self:setupTycoon(tycoon, true) or not renderers[tycoon] then
		return false
	end

	local units = PlayerDataController:Get("Units") or {}
	self:rebuildTycoon(tycoon, units)

	local janitor = renderers[tycoon].janitor
	local currentDeposit = math.max(math.floor(PlayerDataController:Get("ManaInDeposit") or 0), 0)
	renderers[tycoon].lastObservedDeposit = currentDeposit
	if renderers[tycoon].depositVFX then
		local settings = PlayerDataController:Get("Settings")
		renderers[tycoon].depositVFX:setEnabled(settings == nil or settings.ShowVFX ~= false)
		renderers[tycoon].depositVFX:setProcessorActive(currentDeposit > 0, getDepositProcessInterval())
	end

	PlayerDataController:Observe("Units", function(newUnits)
		self:rebuildTycoon(tycoon, newUnits or {})
		self:scheduleButtonPriceUpdate(tycoon)
	end, janitor)

	PlayerDataController:Observe("RateLevel", function()
		self:scheduleButtonPriceUpdate(tycoon)
	end, janitor)

	PlayerDataController:Observe("Yen", function()
		self:scheduleButtonPriceUpdate(tycoon)
	end, janitor)

	PlayerDataController:Observe("TotalUnitsPurchased", function()
		self:scheduleButtonPriceUpdate(tycoon)
	end, janitor)

	PlayerDataController:Observe({ "RebirthUpgrades", "UnitSpawnTier" }, function()
		table.clear(buyUnitTierCache)
		self:scheduleButtonPriceUpdate(tycoon)
		self:rebuildTycoon(tycoon, PlayerDataController:Get("Units") or {})
	end, janitor)

	PlayerDataController:Observe({ "RebirthUpgrades", "MoreMana" }, function()
		self:applyEntitlementsToOwnTycoon()
	end, janitor)

	PlayerDataController:Observe({ "PurchasedProducts", "DoubleMana" }, function()
		self:applyEntitlementsToOwnTycoon()
	end, janitor)

	PlayerDataController:Observe("LastGroupRewardClaimAt", function()
		self:updateGroupRewardDisplay(tycoon)
	end, janitor)

	PlayerDataController:Observe("ManaInDeposit", function(newDeposit)
		self:updateDepositVFX(tycoon, newDeposit)
		self:updateProcesserDisplay(tycoon)
	end, janitor)

	PlayerDataController:Observe("Rate", function()
		self:scheduleButtonPriceUpdate(tycoon)
		self:updateProcesserDisplay(tycoon)
	end, janitor)

	PlayerDataController:Observe("Settings", function(settings)
		local entry = renderers[tycoon]
		if entry and entry.renderer then
			local autoCollect = settings and settings.AutoCollect == true
			local autoDeposit = settings and settings.AutoDeposit == true
			entry.lastAutoCollect = autoCollect
			entry.lastAutoDeposit = autoDeposit
			entry.renderer:setEntitlements(mergeEntitlementsWithSettings(monetizationEntitlements, settings))
		end

		if entry and entry.depositVFX then
			entry.depositVFX:setEnabled(settings == nil or settings.ShowVFX ~= false)
			local deposit = PlayerDataController:Get("ManaInDeposit") or 0
			entry.depositVFX:setProcessorActive(deposit > 0, getDepositProcessInterval())
		end
	end, janitor)

	return true
end

function TycoonController:setupOtherTycoons()
	if otherTycoonStreamingConnection then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:updateAllDefaultProcesserDisplays()

	otherTycoonStreamingConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastOtherTycoonStreamAt < OTHER_TYCOON_STREAM_INTERVAL then
			return
		end

		lastOtherTycoonStreamAt = now
		self:refreshOtherTycoons(false)
	end)

	local lastShowOtherTycoons: boolean? = nil
	PlayerDataController:Observe("Settings", function(settings)
		local showOtherTycoons = ShowOther.shouldRenderOthers(settings)
		if showOtherTycoons == lastShowOtherTycoons then
			return
		end

		lastShowOtherTycoons = showOtherTycoons
		self:refreshOtherTycoons(true)
	end, PlayerDataController:NewJanitor())

	self:refreshOtherTycoons(true)
end

function TycoonController:refreshOtherTycoons(forceRestart: boolean?)
	local tycoonsFolder = TycoonUtil.getTycoonsFolder()
	if not tycoonsFolder then
		return
	end

	if forceRestart then
		otherTycoonRefreshToken += 1
	elseif otherTycoonRefreshRunning then
		return
	end

	otherTycoonRefreshRunning = true
	local refreshToken = otherTycoonRefreshToken
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local ownName = PlayerDataController:Get("TycoonName")
	local TycoonService = Knit.GetService("TycoonService")
	local tycoons = tycoonsFolder:GetChildren()

	local function shouldShowOtherTycoons(): boolean
		return ShowOther.shouldRenderOthers(PlayerDataController:Get("Settings"))
	end

	local function isRefreshCurrent(): boolean
		return refreshToken == otherTycoonRefreshToken
	end

	task.spawn(function()
		local processedThisBatch = 0

		local function stepBatch()
			processedThisBatch += 1
			if processedThisBatch >= OTHER_TYCOON_BATCH_SIZE then
				processedThisBatch = 0
				task.wait(OTHER_TYCOON_BATCH_DELAY)
			end
		end

		for _, tycoon in tycoons do
			if not isRefreshCurrent() then
				return
			end

			if tycoon.Name == ownName then
				continue
			end

			local shouldShowOthers = shouldShowOtherTycoons()
			setButtonBillboardsEnabled(tycoon, false)

			local entry = renderers[tycoon]
			local isClaimed = tycoon:GetAttribute("Claimed") == true
			local shouldLoad = shouldShowOthers and isClaimed and not entry
			local shouldUnload = entry and not entry.isOwn and (not shouldShowOthers or not isClaimed)

			if shouldUnload then
				entry.renderer:destroy()
				entry.janitor:Destroy()
				renderers[tycoon] = nil
				buttonBillboardCacheByTycoon[tycoon] = nil
				buttonBillboardsEnabledByTycoon[tycoon] = nil
				buttonPriceUpdateScheduled[tycoon] = nil
				self:setDefaultProcesserDisplay(tycoon)
				stepBatch()
			elseif shouldLoad then
				if self:setupTycoon(tycoon, false) then
					local requestedTycoon = tycoon
					TycoonService:GetTycoonVisualData(tycoon.Name)
						:andThen(function(success, payload)
							local currentEntry = renderers[requestedTycoon]
							if
								not success
								or not currentEntry
								or currentEntry.isOwn
								or not isRefreshCurrent()
								or not shouldShowOtherTycoons()
							then
								return
							end

							currentEntry.lastVisualRefreshAt = os.clock()
							self:updateProcesserDisplay(requestedTycoon, payload.ManaInDeposit or 0, payload.Rate or 0)
							self:rebuildTycoon(requestedTycoon, payload.Units or {})
						end)
						:catch(function(err)
							warn("[TycoonController] Failed to load tycoon visuals:", err)
						end)
				end

				stepBatch()
			elseif entry and not entry.isOwn and shouldShowOthers then
				local now = os.clock()
				if now - (entry.lastVisualRefreshAt or 0) >= OTHER_TYCOON_VISUAL_REFRESH_INTERVAL then
					entry.lastVisualRefreshAt = now
					local requestedTycoon = tycoon
					TycoonService:GetTycoonVisualData(tycoon.Name)
						:andThen(function(success, payload)
							local currentEntry = renderers[requestedTycoon]
							if
								not success
								or not currentEntry
								or currentEntry.isOwn
								or not isRefreshCurrent()
								or not shouldShowOtherTycoons()
							then
								return
							end

							currentEntry.lastVisualRefreshAt = os.clock()
							self:updateProcesserDisplay(requestedTycoon, payload.ManaInDeposit or 0, payload.Rate or 0)
							self:rebuildTycoon(requestedTycoon, payload.Units or {})
						end)
						:catch(function(err)
							warn("[TycoonController] Failed to refresh tycoon visuals:", err)
						end)

					stepBatch()
				end
			end
		end

		if isRefreshCurrent() then
			otherTycoonRefreshRunning = false
		end
	end)
end

function TycoonController:refreshOwnTycoonForEvent()
	self:applyEntitlementsToOwnTycoon()

	for tycoon, entry in renderers do
		if entry.isOwn then
			self:updateButtonPrices(tycoon)
			self:updateProcesserDisplay(tycoon)

			if entry.depositVFX then
				local PlayerDataController = Knit.GetController("PlayerDataController")
				local deposit = PlayerDataController:Get("ManaInDeposit") or 0
				entry.depositVFX:setProcessorActive(deposit > 0, getDepositProcessInterval())
			end
		end
	end
end

function TycoonController:startEventRefreshLoop()
	task.spawn(function()
		local PlayerDataController = Knit.GetController("PlayerDataController")
		PlayerDataController:WaitForData()

		while true do
			local activeEvent = EventUtil.getActiveEvent()
			local eventId = if activeEvent then activeEvent.Id else nil
			if eventId ~= lastAppliedEventId then
				lastAppliedEventId = eventId
				self:refreshOwnTycoonForEvent()
			end

			task.wait(2)
		end
	end)
end

function TycoonController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local initialized = false

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(firstArg, _productId, wasPurchased)
		if isLocalProductPromptFinished(firstArg) then
			if wasPurchased == true and productPromptOpen then
				SoundUtil.Robux()
			end

			if wasPurchased == true and pendingRobuxUnitAmount then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowRobuxUnitsMessage(pendingRobuxUnitAmount)
			end

			resetProductPromptState()
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if player ~= localPlayer or wasPurchased ~= true then
			return
		end

		local gamePassKey = getGamePassKeyFromId(gamePassId)
		local autoEnableSetting = if gamePassKey == "AutoCollect" or gamePassKey == "AutoDeposit"
			then gamePassKey
			else nil

		self:refreshMonetizationEntitlements(autoEnableSetting)
	end)

	local function init()
		if initialized then
			return
		end

		self:updateAllDefaultProcesserDisplays()

		local tycoonName = PlayerDataController:Get("TycoonName")
		if not tycoonName or tycoonName == "" then
			return
		end

		if not self:setupOwnTycoon() then
			return
		end

		initialized = true
		self:setupOtherTycoons()
	end

	task.spawn(function()
		PlayerDataController:WaitForData()
		init()

		PlayerDataController:Observe("TycoonName", function(name)
			if name and name ~= "" then
				init()
			end
		end)

		while not initialized do
			task.wait(0.5)
			init()
		end
	end)

	self:startEventRefreshLoop()
end

return TycoonController
