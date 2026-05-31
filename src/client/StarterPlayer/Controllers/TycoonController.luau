local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local ButtonPress = require(ReplicatedStorage.Shared.Observers.Button)
local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Loading = require(ReplicatedStorage.Shared.Performance.Loading)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local ShowOther = require(ReplicatedStorage.Shared.Performance.ShowOther)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
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
local lastActionAt: { [BasePart]: number } = {}
local wasStandingOnButton: { [BasePart]: boolean } = {}
local standingLoopConnection: RBXScriptConnection? = nil
local actionTycoon: Instance? = nil
local lastActionScanAt = 0
local productPromptOpen = false
local activeProductPromptHead: BasePart? = nil
local productPromptToken = 0
local pendingRobuxUnitAmount: number? = nil
local monetizationEntitlements: { [string]: boolean } = {}
local otherTycoonStreamingConnection: RBXScriptConnection? = nil
local lastOtherTycoonStreamAt = 0

local ACTION_COOLDOWN = 1.12
local OTHER_TYCOON_STREAM_INTERVAL = 0.75
local OTHER_TYCOON_VISUAL_REFRESH_INTERVAL = 3

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

local function shouldRegisterButtonModel(buttonModel: Model): boolean
	return TycoonUtil.getRobuxBuyAmount(buttonModel) ~= nil
		or TycoonUtil.isSellAllButton(buttonModel)
		or TycoonUtil.getBuyAmount(buttonModel) ~= nil
		or TycoonUtil.getRateAmount(buttonModel) ~= nil
		or TycoonUtil.isMergeButton(buttonModel)
		or TycoonUtil.isDepositButton(buttonModel)
end

local function getProcesserLabels(tycoon: Instance): (TextLabel?, TextLabel?)
	local processer = tycoon:FindFirstChild("Processer")
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

local function getButtonBillboard(buttonModel: Instance): BillboardGui?
	local head = buttonModel:FindFirstChild("Head")
	if head then
		local billboard = head:FindFirstChild("BillboardGui")
		if billboard and billboard:IsA("BillboardGui") then
			return billboard
		end
	end

	local billboard = buttonModel:FindFirstChild("BillboardGui", true)
	return if billboard and billboard:IsA("BillboardGui") then billboard else nil
end

local function getBillboardTextLabel(billboard: BillboardGui?, labelName: string): TextLabel?
	if not billboard then
		return nil
	end

	local label = billboard:FindFirstChild(labelName)
	return if label and label:IsA("TextLabel") then label else nil
end

function TycoonController:updateProcesserDisplay(tycoon: Instance)
	local mpLabel, rateLabel = getProcesserLabels(tycoon)
	if not mpLabel and not rateLabel then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local deposit = PlayerDataController:Get("ManaInDeposit") or 0
	local rate = PlayerDataController:Get("Rate") or 0

	if mpLabel then
		mpLabel.Text = FormatUtil.formatMana(math.floor(deposit))
	end

	if rateLabel then
		local intervalText = if monetizationEntitlements.DoubleDeposit then "0.5s" else "1s"
		rateLabel.Text = "Rate: " .. FormatUtil.formatNumber(math.floor(rate)) .. "/" .. intervalText
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
	local baseUnitCount = Pricing.getBaseUnitCount(PlayerDataController:Get("Units") or {})
	local rateLevel = PlayerDataController:Get("RateLevel") or 0

	for _, child in tycoon:GetChildren() do
		if TycoonUtil.getRobuxBuyAmount(child) then
			continue
		end

		local buyAmount = TycoonUtil.getBuyAmount(child)
		if buyAmount then
			local billboard = getButtonBillboard(child)
			local priceLabel = getBillboardTextLabel(billboard, "Price")
			if priceLabel then
				priceLabel.Text = Pricing.formatYen(Pricing.getUnitBulkPrice(baseUnitCount, buyAmount))
			end
		end

		local rateAmount = TycoonUtil.getRateAmount(child)
		if rateAmount then
			local billboard = getButtonBillboard(child)
			local priceLabel = getBillboardTextLabel(billboard, "Price")
			if priceLabel then
				priceLabel.Text = Pricing.formatYen(Pricing.getRateUpgradePrice(rateLevel, rateAmount))
			end

			local rateLabel = getBillboardTextLabel(billboard, "Rate")
			if rateLabel then
				rateLabel.Text = "+" .. FormatUtil.formatNumber(Pricing.getRateGain(rateAmount, rateLevel)) .. " Rate"
			end
		end
	end
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
	elseif action.kind == "buy" and action.amount then
		TycoonService:BuyUnits(action.amount, action.buttonName):andThen(function(success, err)
			if not success and err then
				warn("[TycoonController] Buy failed:", err)
			elseif success then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowBoughtUnitsMessage(action.amount)
			end
		end)
	elseif action.kind == "merge" then
		TycoonService:MergeUnits(action.buttonName):andThen(function(success, err, mergedUnitCount)
			if not success and err and err ~= "Nothing to merge" then
				warn("[TycoonController] Merge failed:", err)
			elseif success then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowMergedUnitsMessage(mergedUnitCount or 0)
			end
		end)
	elseif action.kind == "rate" and action.amount then
		TycoonService:UpgradeRate(action.amount, action.buttonName):andThen(function(success, err)
			if not success and err then
				warn("[TycoonController] Rate upgrade failed:", err)
			end
		end)
	elseif action.kind == "deposit" then
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local depositAmount = PlayerDataController:Get("ManaInBag") or 0
		TycoonService:DepositMana():andThen(function(success, err)
			if not success and err and err ~= "Nothing to deposit" then
				warn("[TycoonController] Deposit failed:", err)
			elseif success then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowDepositMessage(depositAmount)
			end
		end)
	end
end

function TycoonController:setupButtonActions(tycoon: Instance)
	actionTycoon = tycoon
	local seenButtons: { [Model]: boolean } = {}
	local nextButtonActions: { [BasePart]: { kind: string, amount: number?, buttonName: string } } = {}

	local function registerButtonModel(buttonModel: Model, taggedObject: Instance?)
		if seenButtons[buttonModel] or not shouldRegisterButtonModel(buttonModel) then
			return
		end

		seenButtons[buttonModel] = true

		local head = getButtonHead(buttonModel, taggedObject)
		if not head then
			return
		end

		ButtonPress.SetupButton(head)

		if TycoonUtil.isSellAllButton(buttonModel) then
			nextButtonActions[head] = {
				kind = "sell_all_product",
				buttonName = buttonModel.Name,
			}
			return
		end

		local robuxBuyAmount = TycoonUtil.getRobuxBuyAmount(buttonModel)
		if robuxBuyAmount then
			nextButtonActions[head] = {
				kind = "robux_buy",
				amount = robuxBuyAmount,
				buttonName = buttonModel.Name,
			}
			return
		end

		local buyAmount = TycoonUtil.getBuyAmount(buttonModel)
		if buyAmount then
			nextButtonActions[head] = {
				kind = "buy",
				amount = buyAmount,
				buttonName = buttonModel.Name,
			}
			return
		end

		local rateAmount = TycoonUtil.getRateAmount(buttonModel)
		if rateAmount then
			nextButtonActions[head] = {
				kind = "rate",
				amount = rateAmount,
				buttonName = buttonModel.Name,
			}
			return
		end

		if TycoonUtil.isMergeButton(buttonModel) then
			nextButtonActions[head] = {
				kind = "merge",
				buttonName = buttonModel.Name,
			}
			return
		end

		if TycoonUtil.isDepositButton(buttonModel) then
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
		if actionTycoon and now - lastActionScanAt >= 1 then
			lastActionScanAt = now
			self:setupButtonActions(actionTycoon)
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
		return true
	end

	if not self:shouldRenderTycoon(tycoon, isOwn) then
		return false
	end

	local janitor = Janitor.new()
	local TycoonService = Knit.GetService("TycoonService")

	local onPickup = if isOwn
		then function(value: number)
			TycoonService:CollectMana(value)
		end
		else nil

	local renderer = TycoonRenderer.new(tycoon, janitor, onPickup)
	renderer:setIsOwn(isOwn)
	renderers[tycoon] = {
		renderer = renderer,
		janitor = janitor,
		isOwn = isOwn,
		lastVisualRefreshAt = 0,
	}

	if isOwn then
		local MonetizationService = Knit.GetService("MonetizationService")
		MonetizationService:GetEntitlements():andThen(function(entitlements)
			monetizationEntitlements = entitlements or {}
			renderer:setEntitlements(monetizationEntitlements)
			self:updateProcesserDisplay(tycoon)
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

	PlayerDataController:Observe("Units", function(newUnits)
		self:rebuildTycoon(tycoon, newUnits or {})
		self:updateButtonPrices(tycoon)
	end, janitor)

	PlayerDataController:Observe("RateLevel", function()
		self:updateButtonPrices(tycoon)
	end, janitor)

	PlayerDataController:Observe("ManaInDeposit", function()
		self:updateProcesserDisplay(tycoon)
	end, janitor)

	PlayerDataController:Observe("Rate", function()
		self:updateButtonPrices(tycoon)
		self:updateProcesserDisplay(tycoon)
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
		self:refreshOtherTycoons()
	end)

	PlayerDataController:Observe("Settings", function()
		self:updateAllDefaultProcesserDisplays()
		self:refreshOtherTycoons()
	end, PlayerDataController:NewJanitor())

	self:refreshOtherTycoons()
end

function TycoonController:refreshOtherTycoons()
	local tycoonsFolder = TycoonUtil.getTycoonsFolder()
	if not tycoonsFolder then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local ownName = PlayerDataController:Get("TycoonName")
	local settings = PlayerDataController:Get("Settings")
	local shouldShowOthers = ShowOther.shouldRenderOthers(settings)
	local TycoonService = Knit.GetService("TycoonService")

	for _, tycoon in tycoonsFolder:GetChildren() do
		if tycoon.Name == ownName then
			continue
		end

		self:setDefaultProcesserDisplay(tycoon)

		local entry = renderers[tycoon]
		local shouldLoad = shouldShowOthers and tycoon:GetAttribute("Claimed") == true and not entry
		local shouldUnload = entry
			and not entry.isOwn
			and (not shouldShowOthers or tycoon:GetAttribute("Claimed") ~= true)

		if shouldUnload then
			entry.renderer:destroy()
			entry.janitor:Destroy()
			renderers[tycoon] = nil
		elseif shouldLoad then
			if self:setupTycoon(tycoon, false) then
				TycoonService:GetTycoonVisualData(tycoon.Name)
					:andThen(function(success, payload)
						local currentEntry = renderers[tycoon]
						if not success or not currentEntry or currentEntry.isOwn then
							return
						end

						currentEntry.lastVisualRefreshAt = os.clock()
						self:rebuildTycoon(tycoon, payload.Units or {})
					end)
					:catch(function(err)
						warn("[TycoonController] Failed to load tycoon visuals:", err)
					end)
			end
		elseif entry and not entry.isOwn and shouldShowOthers then
			local now = os.clock()
			if now - (entry.lastVisualRefreshAt or 0) >= OTHER_TYCOON_VISUAL_REFRESH_INTERVAL then
				entry.lastVisualRefreshAt = now
				TycoonService:GetTycoonVisualData(tycoon.Name)
					:andThen(function(success, payload)
						local currentEntry = renderers[tycoon]
						if not success or not currentEntry or currentEntry.isOwn then
							return
						end

						currentEntry.lastVisualRefreshAt = os.clock()
						self:rebuildTycoon(tycoon, payload.Units or {})
					end)
					:catch(function(err)
						warn("[TycoonController] Failed to refresh tycoon visuals:", err)
					end)
			end
		end
	end
end

function TycoonController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local initialized = false

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(firstArg, _productId, wasPurchased)
		if isLocalProductPromptFinished(firstArg) then
			if wasPurchased == true and pendingRobuxUnitAmount then
				local MainGuiController = Knit.GetController("MainGuiController")
				MainGuiController:ShowRobuxUnitsMessage(pendingRobuxUnitAmount)
			end

			resetProductPromptState()
		end
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
end

return TycoonController
