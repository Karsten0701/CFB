local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormatUtil = require(ReplicatedStorage.Shared.Features.Tycoon.FormatUtil)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local Knit = require(ReplicatedStorage.Packages.knit)

local MainGuiController = Knit.CreateController({
	Name = "MainGuiController",
})

local localPlayer = Players.LocalPlayer
local COUNTER_ANIMATION_TIME = 0.5
local COUNTER_ANIMATION_STEPS = 50
local DOUBLE_YEN_PRODUCT = Monetization.DeveloperProducts.DoubleYen

local displayedValues = {
	ManaBag = 0,
	YenShow = 0,
}

local doubleYenClickConnection: RBXScriptConnection? = nil
local doubleYenPromptOpen = false

local animationTokens = {
	ManaBag = 0,
	YenShow = 0,
}

function MainGuiController:getAmountLabel(containerName: string): TextLabel?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	local container = mainGui:FindFirstChild(containerName)
	if not container then
		return nil
	end

	local amount = container:FindFirstChild("Amount")
	return if amount and amount:IsA("TextLabel") then amount else nil
end

function MainGuiController:getMainGui(): Instance?
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	return playerGui:FindFirstChild("MainGui")
end

function MainGuiController:getDoubleYenOfferRootFromDescendant(mainGui: Instance, descendant: Instance): GuiObject?
	local current = descendant
	while current and current.Parent and current.Parent ~= mainGui do
		if current.Parent.Name == "RightSide" and current:IsA("GuiObject") then
			return current
		end

		current = current.Parent
	end

	return if current and current:IsA("GuiObject") and current ~= mainGui then current else nil
end

function MainGuiController:isDoubleYenCandidate(instance: Instance): boolean
	if
		instance:GetAttribute("ProductId") == DOUBLE_YEN_PRODUCT.ProductId
		or instance:GetAttribute("DevProductId") == DOUBLE_YEN_PRODUCT.ProductId
	then
		return true
	end

	local normalizedName = string.lower(string.gsub(instance.Name, "%s+", ""))
	if normalizedName == "doubleyen" or normalizedName == "2xyen" or normalizedName == "yen2x" then
		return true
	end

	if instance.Name == "Amount" and instance:IsA("TextLabel") then
		local normalizedText = string.lower(string.gsub(instance.Text, "%s+", ""))
		return string.find(normalizedText, "2xyen", 1, true) ~= nil
	end

	return false
end

function MainGuiController:getDoubleYenOffer(): GuiObject?
	local mainGui = self:getMainGui()
	if not mainGui then
		return nil
	end

	for _, descendant in mainGui:GetDescendants() do
		if self:isDoubleYenCandidate(descendant) then
			local root = self:getDoubleYenOfferRootFromDescendant(mainGui, descendant)
			if root then
				return root
			end
		end
	end

	local rightSide = mainGui:FindFirstChild("RightSide")
	if rightSide then
		for _, descendant in rightSide:GetDescendants() do
			if descendant.Name == "Amount" and descendant:IsA("TextLabel") then
				local root = self:getDoubleYenOfferRootFromDescendant(mainGui, descendant)
				if root then
					return root
				end
			end
		end
	end

	return nil
end

function MainGuiController:getClickableGui(root: GuiObject): GuiObject
	if root:IsA("TextButton") or root:IsA("ImageButton") then
		return root
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
			return descendant
		end
	end

	return root
end

function MainGuiController:updateDoubleYenOffer()
	local offer = self:getDoubleYenOffer()
	if not offer then
		return
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local purchased = PlayerDataController:Get({ "PurchasedProducts", "DoubleYen" }) == true
	if purchased then
		offer.Visible = false
		if doubleYenClickConnection then
			doubleYenClickConnection:Disconnect()
			doubleYenClickConnection = nil
		end
		return
	end

	offer.Visible = true
	local amount = offer:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		amount.Text = "2x Yen"
	end

	if doubleYenClickConnection then
		return
	end

	local clickable = self:getClickableGui(offer)
	if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
		doubleYenClickConnection = clickable.Activated:Connect(function()
			if doubleYenPromptOpen then
				return
			end

			doubleYenPromptOpen = true
			MarketplaceService:PromptProductPurchase(localPlayer, DOUBLE_YEN_PRODUCT.ProductId)
		end)
	else
		doubleYenClickConnection = clickable.InputBegan:Connect(function(input)
			if doubleYenPromptOpen or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			doubleYenPromptOpen = true
			MarketplaceService:PromptProductPurchase(localPlayer, DOUBLE_YEN_PRODUCT.ProductId)
		end)
	end
end

function MainGuiController:formatCounter(counterName: string, value: number): string
	if counterName == "ManaBag" then
		return FormatUtil.formatNumber(value) .. " Mana"
	elseif counterName == "YenShow" then
		return Pricing.formatYen(value)
	end

	return FormatUtil.formatNumber(value)
end

function MainGuiController:setCounterText(counterName: string, value: number)
	local label = self:getAmountLabel(counterName)
	if label then
		label.Text = self:formatCounter(counterName, value)
	end
end

function MainGuiController:animateCounter(counterName: string, targetValue: number)
	targetValue = math.max(math.floor(targetValue), 0)

	local startValue = displayedValues[counterName] or 0
	if startValue == targetValue then
		self:setCounterText(counterName, targetValue)
		return
	end

	animationTokens[counterName] = (animationTokens[counterName] or 0) + 1
	local token = animationTokens[counterName]
	local stepDuration = COUNTER_ANIMATION_TIME / COUNTER_ANIMATION_STEPS

	task.spawn(function()
		for step = 1, COUNTER_ANIMATION_STEPS do
			if animationTokens[counterName] ~= token then
				return
			end

			local alpha = step / COUNTER_ANIMATION_STEPS
			local easedAlpha = 1 - (1 - alpha) ^ 3
			local value = math.floor(startValue + (targetValue - startValue) * easedAlpha + 0.5)

			displayedValues[counterName] = value
			self:setCounterText(counterName, value)

			if step < COUNTER_ANIMATION_STEPS then
				task.wait(stepDuration)
			end
		end

		if animationTokens[counterName] == token then
			displayedValues[counterName] = targetValue
			self:setCounterText(counterName, targetValue)
		end
	end)
end

function MainGuiController:updateManaBag()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:animateCounter("ManaBag", PlayerDataController:Get("ManaInBag") or 0)
end

function MainGuiController:updateYenShow()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:animateCounter("YenShow", PlayerDataController:Get("Yen") or 0)
end

function MainGuiController:updateAll(instant: boolean?)
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local mana = math.max(math.floor(PlayerDataController:Get("ManaInBag") or 0), 0)
	local yen = math.max(math.floor(PlayerDataController:Get("Yen") or 0), 0)

	if instant then
		animationTokens.ManaBag += 1
		animationTokens.YenShow += 1
		displayedValues.ManaBag = mana
		displayedValues.YenShow = yen
		self:setCounterText("ManaBag", mana)
		self:setCounterText("YenShow", yen)
		self:updateDoubleYenOffer()
		return
	end

	self:animateCounter("ManaBag", mana)
	self:animateCounter("YenShow", yen)
	self:updateDoubleYenOffer()
end

function MainGuiController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(player)
		if player == localPlayer then
			doubleYenPromptOpen = false
			self:updateDoubleYenOffer()
		end
	end)

	task.spawn(function()
		PlayerDataController:WaitForData()
		self:updateAll()

		PlayerDataController:Observe("ManaInBag", function()
			self:updateManaBag()
		end)

		PlayerDataController:Observe("Yen", function()
			self:updateYenShow()
		end)

		PlayerDataController:Observe({ "PurchasedProducts", "DoubleYen" }, function()
			self:updateDoubleYenOffer()
		end)
	end)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "MainGui" then
			task.defer(function()
				self:updateAll(true)
			end)
		end
	end)
end

return MainGuiController
