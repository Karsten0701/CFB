local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local ButtonPress = require(ReplicatedStorage.Shared.Observers.Button)
local Culling = require(ReplicatedStorage.Shared.Performance.Culling)
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
local monetizationEntitlements: { [string]: boolean } = {}

local ACTION_COOLDOWN = 1.12

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
	local deposit = PlayerDataController:Get("ManaPowerInDeposit") or 0
	local rate = PlayerDataController:Get("Rate") or 0

	if mpLabel then
		mpLabel.Text = FormatUtil.formatManaPower(math.floor(deposit))
	end

	if rateLabel then
		local intervalText = if monetizationEntitlements.DoubleDeposit then "0.5s" else "1s"
		rateLabel.Text = FormatUtil.formatNumber(math.floor(rate)) .. "/" .. intervalText
	end
end

function TycoonController:updateButtonPrices(tycoon: Instance)
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local totalPurchased = PlayerDataController:Get("TotalUnitsPurchased") or 0
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
				priceLabel.Text = Pricing.formatYen(Pricing.getUnitBulkPrice(totalPurchased, buyAmount))
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

function TycoonController:registerButtonAction(head: BasePart, action: { kind: string, amount: number?, buttonName: string })
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
		if product and not productPromptOpen then
			productPromptOpen = true
			MarketplaceService:PromptProductPurchase(localPlayer, product.ProductId)
		elseif not product then
			warn("[TycoonController] No dev product for robux unit amount:", action.amount)
		end
	elseif action.kind == "sell_all_product" then
		if not productPromptOpen then
			productPromptOpen = true
			MarketplaceService:PromptProductPurchase(localPlayer, Monetization.DeveloperProducts.SellAll.ProductId)
		end
	elseif action.kind == "buy" and action.amount then
		TycoonService:BuyUnits(action.amount, action.buttonName):andThen(function(success, err)
			if not success and err then
				warn("[TycoonController] Buy failed:", err)
			end
		end)
	elseif action.kind == "merge" then
		TycoonService:MergeUnits(action.buttonName):andThen(function(success, err)
			if not success and err and err ~= "Nothing to merge" then
				warn("[TycoonController] Merge failed:", err)
			end
		end)
	elseif action.kind == "rate" and action.amount then
		TycoonService:UpgradeRate(action.amount, action.buttonName):andThen(function(success, err)
			if not success and err then
				warn("[TycoonController] Rate upgrade failed:", err)
			end
		end)
	elseif action.kind == "deposit" then
		TycoonService:DepositManaPower():andThen(function(success, err)
			if not success and err and err ~= "Nothing to deposit" then
				warn("[TycoonController] Deposit failed:", err)
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

		local robuxBuyAmount = TycoonUtil.getRobuxBuyAmount(buttonModel)
		if robuxBuyAmount then
			nextButtonActions[head] = {
				kind = "robux_buy",
				amount = robuxBuyAmount,
				buttonName = buttonModel.Name,
			}
			return
		end

		if TycoonUtil.isSellAllButton(buttonModel) then
			nextButtonActions[head] = {
				kind = "sell_all_product",
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
			local isProductPrompt = action and (action.kind == "robux_buy" or action.kind == "sell_all_product")

			if standing and (not isProductPrompt or not wasStandingOnButton[head]) then
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

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local settings = PlayerDataController:Get("Settings")
	if not ShowOther.shouldRenderOthers(settings) then
		return false
	end

	local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	local spawnPart = tycoon:FindFirstChild("Spawn")
	if root and spawnPart and spawnPart:IsA("BasePart") then
		local distance = (root.Position - spawnPart.Position).Magnitude
		if not Culling.shouldRenderAtDistance(distance, false) then
			return false
		end
	end

	return Loading.shouldLoadTycoon(tycoon, false)
end

function TycoonController:setupTycoon(tycoon: Instance, isOwn: boolean)
	if renderers[tycoon] then
		return
	end

	if not self:shouldRenderTycoon(tycoon, isOwn) then
		return
	end

	local janitor = Janitor.new()
	local TycoonService = Knit.GetService("TycoonService")

	local onPickup = if isOwn
		then function(value: number)
			TycoonService:CollectManaPower(value)
		end
		else nil

	local renderer = TycoonRenderer.new(tycoon, janitor, onPickup)
	renderer:setIsOwn(isOwn)
	renderers[tycoon] = {
		renderer = renderer,
		janitor = janitor,
		isOwn = isOwn,
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
end

function TycoonController:rebuildTycoon(tycoon: Instance, units: { { Tier: number } })
	local entry = renderers[tycoon]
	if not entry then
		return
	end

	entry.renderer:rebuild(units)
end

function TycoonController:setupOwnTycoon()
	local PlayerDataController = Knit.GetController("PlayerDataController")

	local tycoonName = PlayerDataController:Get("TycoonName")
	if not tycoonName or tycoonName == "" then
		return
	end

	local tycoon = TycoonUtil.getTycoonByName(tycoonName)
	if not tycoon then
		return
	end

	self:setupTycoon(tycoon, true)

	local units = PlayerDataController:Get("Units") or {}
	self:rebuildTycoon(tycoon, units)

	local janitor = renderers[tycoon].janitor

	PlayerDataController:Observe("Units", function(newUnits)
		self:rebuildTycoon(tycoon, newUnits or {})
	end, janitor)

	PlayerDataController:Observe("TotalUnitsPurchased", function()
		self:updateButtonPrices(tycoon)
	end, janitor)

	PlayerDataController:Observe("RateLevel", function()
		self:updateButtonPrices(tycoon)
	end, janitor)

	PlayerDataController:Observe("ManaPowerInDeposit", function()
		self:updateProcesserDisplay(tycoon)
	end, janitor)

	PlayerDataController:Observe("Rate", function()
		self:updateButtonPrices(tycoon)
		self:updateProcesserDisplay(tycoon)
	end, janitor)
end

function TycoonController:setupOtherTycoons()
	local tycoonsFolder = TycoonUtil.getTycoonsFolder()
	if not tycoonsFolder then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local ownName = PlayerDataController:Get("TycoonName")

	for _, tycoon in tycoonsFolder:GetChildren() do
		if tycoon.Name == ownName then
			continue
		end

		if tycoon:GetAttribute("Claimed") == true then
			self:setupTycoon(tycoon, false)
		end
	end

	PlayerDataController:Observe("Settings", function()
		self:refreshOtherTycoons()
	end, PlayerDataController:NewJanitor())
end

function TycoonController:refreshOtherTycoons()
	local tycoonsFolder = TycoonUtil.getTycoonsFolder()
	if not tycoonsFolder then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local ownName = PlayerDataController:Get("TycoonName")

	for _, tycoon in tycoonsFolder:GetChildren() do
		if tycoon.Name == ownName then
			continue
		end

		local shouldRender = tycoon:GetAttribute("Claimed") == true and self:shouldRenderTycoon(tycoon, false)
		local entry = renderers[tycoon]

		if shouldRender and not entry then
			self:setupTycoon(tycoon, false)
		elseif not shouldRender and entry and not entry.isOwn then
			entry.renderer:destroy()
			entry.janitor:Destroy()
			renderers[tycoon] = nil
		end
	end
end

function TycoonController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local initialized = false

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(player)
		if player == localPlayer then
			productPromptOpen = false
		end
	end)

	local function init()
		if initialized then
			return
		end

		local tycoonName = PlayerDataController:Get("TycoonName")
		if not tycoonName or tycoonName == "" then
			return
		end

		initialized = true
		self:setupOwnTycoon()
		self:setupOtherTycoons()
	end

	task.spawn(function()
		PlayerDataController:WaitForData()
		init()

		if not initialized then
			PlayerDataController:Observe("TycoonName", function(name)
				if name and name ~= "" then
					init()
				end
			end)
		end
	end)
end

return TycoonController
