local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local TycoonConfig = require(ReplicatedStorage.Shared.Data.TycoonConfig)
local TycoonUtil = require(ReplicatedStorage.Shared.Features.Tycoon.TycoonUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local TutorialController = Knit.CreateController({
	Name = "TutorialController",
})

local localPlayer = Players.LocalPlayer
local STEP_ORDER = {
	"PickupDrop",
	"DepositMana",
	"BuySecondUnit",
	"PickupDropAgain",
	"DepositManaAgain",
	"UpgradeRate",
	"BuyThirdUnit",
	"MergeUnits",
	"VisitGroupReward",
	"WaitForRebirthReady",
	"Rebirth",
	"OpenUpgrades",
	"UpgradeUnitSpawnTier",
	"Completed",
}

local STEP_INDEX = {}
for index, step in STEP_ORDER do
	STEP_INDEX[step] = index
end

local STEP_TEXT = {
	PickupDrop = "First collect some Mana orbs from your plot!",
	DepositMana = "Deposit your Mana so it can turn into Yen!",
	BuySecondUnit = "Buy a new anime unit!",
	PickupDropAgain = "Collect more Mana orbs!",
	UpgradeRate = "Upgrade your deposit rate!",
	DepositManaAgain = "Deposit your Mana again!",
	BuyThirdUnit = "Buy one more anime unit!",
	MergeUnits = "Merge your units!",
	VisitGroupReward = "Join the group and like the game at the Group Reward button!",
	WaitForRebirthReady = "Tutorial resumes when you can rebirth.",
	Rebirth = "Rebirth your tycoon!",
	OpenUpgrades = "Open the upgrades menu!",
	UpgradeUnitSpawnTier = "Upgrade Unit Spawn Tier!",
	Completed = "Tutorial completed",
}

local currentStep = "PickupDrop"
local CORE_TUTORIAL_COMPLETE_STEP = "WaitForRebirthReady"
local GUIDE_UPDATE_INTERVAL = 0.1
local rewardConnections: { RBXScriptConnection } = {}
local dataConnections: { RBXScriptConnection } = {}
local guideConnection: RBXScriptConnection? = nil
local startAttachment: Attachment? = nil
local endAttachment: Attachment? = nil
local endAnchor: BasePart? = nil
local guideBeam: Beam? = nil
local lastTarget: Instance? = nil
local lastPersistedStep: string? = nil
local secondCollectBaselineMana: number? = nil
local secondCollectBaselineYen: number? = nil
local secondDepositBaselineDeposit: number? = nil
local secondDepositBaselineYen: number? = nil
local tutorialFingerTweens: { [GuiObject]: { Tween: Tween, OriginalPosition: UDim2 } } = {}
local tutorialFingerConnections: { RBXScriptConnection } = {}
local dismissedRebirthButtonFingerStep: string? = nil
local tutorialRewardPresentationActive = false

local COMPLETED_REWARD_THANKS_MESSAGE = "Thanks for completing the tutorial!"

local function getTutorialConfig(): { [string]: any }
	return TycoonConfig.Tutorial or {}
end

local function getAssetsFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return if assets and assets:IsA("Folder") then assets else nil
end

local function getFirstBasePart(instance: Instance?): BasePart?
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getRootPart(): BasePart?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function cloneAttachment(assetName: string, parent: Instance): Attachment
	local assets = getAssetsFolder()
	local template = assets and assets:FindFirstChild(assetName)
	if template and template:IsA("Attachment") then
		local clone = template:Clone()
		clone.Parent = parent
		return clone
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = assetName
	attachment.Parent = parent
	return attachment
end

local function cloneGuideBeam(parent: Instance): Beam
	local assets = getAssetsFolder()
	local assetName = getTutorialConfig().BeamAssetName or "TutorialBeam"
	local template = assets and assets:FindFirstChild(assetName)
	local beamTemplate = if template and template:IsA("Beam") then template else nil
	if not beamTemplate and template then
		local nestedBeam = template:FindFirstChildWhichIsA("Beam", true)
		if nestedBeam then
			beamTemplate = nestedBeam
		end
	end

	local beam = if beamTemplate then beamTemplate:Clone() else Instance.new("Beam")
	beam.Name = "ActiveTutorialBeam"
	if not beamTemplate then
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 229, 72), Color3.fromRGB(47, 255, 106))
		beam.FaceCamera = true
		beam.LightEmission = 0.8
		beam.Width0 = 0.28
		beam.Width1 = 0.18
	end
	beam.Parent = parent
	return beam
end

local function findButtonTarget(tycoon: Instance?, predicate: (Instance) -> boolean): BasePart?
	if not tycoon then
		return nil
	end

	for _, descendant in tycoon:GetDescendants() do
		if not descendant:IsA("Model") or not predicate(descendant) then
			continue
		end

		local head = descendant:FindFirstChild("Head", true)
		if head and head:IsA("BasePart") then
			return head
		end
	end

	return nil
end

local function getOwnTycoon(): Instance?
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local tycoonName = PlayerDataController:Get("TycoonName")
	if type(tycoonName) ~= "string" or tycoonName == "" then
		return nil
	end

	return TycoonUtil.getPlayerTycoon(localPlayer, tycoonName)
end

local function getBuyOneButton(tycoon: Instance?): BasePart?
	return findButtonTarget(tycoon, function(model)
		return TycoonUtil.getBuyAmount(model) == 1
	end) or findButtonTarget(tycoon, function(model)
		return TycoonUtil.getBuyAmount(model) ~= nil
	end)
end

local function getRateButton(tycoon: Instance?): BasePart?
	return findButtonTarget(tycoon, function(model)
		return TycoonUtil.getRateAmount(model) == 1
	end) or findButtonTarget(tycoon, function(model)
		return TycoonUtil.getRateAmount(model) ~= nil
	end)
end

local function getDropTarget(tycoon: Instance?): BasePart?
	if not tycoon then
		return nil
	end

	local dropperHolder = tycoon:FindFirstChild("DropperHolder")
	local dropsFolder = dropperHolder and dropperHolder:FindFirstChild("ManaDrops")
	if dropsFolder then
		for _, child in dropsFolder:GetChildren() do
			local part = getFirstBasePart(child)
			if part then
				return part
			end
		end
	end

	local unitsFolder = dropperHolder and dropperHolder:FindFirstChild("Units")
	if unitsFolder then
		for _, unit in unitsFolder:GetChildren() do
			local dropPart = unit:FindFirstChild("DropPart", true) or unit:FindFirstChild("Droppart", true)
			if dropPart and dropPart:IsA("BasePart") then
				return dropPart
			end
		end
	end

	return getBuyOneButton(tycoon)
end

local function getStepTarget(step: string): BasePart?
	local tycoon = getOwnTycoon()
	if step == "PickupDrop" or step == "PickupDropAgain" then
		return getDropTarget(tycoon)
	elseif step == "DepositMana" or step == "DepositManaAgain" then
		return findButtonTarget(tycoon, TycoonUtil.isDepositButton)
	elseif step == "BuySecondUnit" or step == "BuyThirdUnit" then
		return getBuyOneButton(tycoon)
	elseif step == "UpgradeRate" then
		return getRateButton(tycoon)
	elseif step == "MergeUnits" then
		return findButtonTarget(tycoon, TycoonUtil.isMergeButton) or getBuyOneButton(tycoon)
	elseif step == "VisitGroupReward" then
		return findButtonTarget(tycoon, TycoonUtil.isGroupRewardButton)
	end

	return nil
end

local function ensureGuide(target: BasePart?)
	local root = getRootPart()
	if not root or not target then
		return
	end

	if not endAttachment or endAttachment.Parent ~= root then
		if endAttachment then
			endAttachment:Destroy()
		end
		endAttachment = cloneAttachment("end", root)
	end

	if target ~= lastTarget then
		lastTarget = target
		if startAttachment then
			startAttachment:Destroy()
		end
		if endAnchor then
			endAnchor:Destroy()
			endAnchor = nil
		end
		startAttachment = cloneAttachment("start", target)
	end

	if not guideBeam or not guideBeam.Parent then
		guideBeam = cloneGuideBeam(endAttachment)
	end

	guideBeam.Attachment0 = startAttachment
	guideBeam.Attachment1 = endAttachment
	guideBeam.Enabled = true
end

local function clearGuide()
	if guideConnection then
		guideConnection:Disconnect()
		guideConnection = nil
	end
	if guideBeam then
		guideBeam:Destroy()
		guideBeam = nil
	end
	if startAttachment then
		startAttachment:Destroy()
		startAttachment = nil
	end
	if endAttachment then
		endAttachment:Destroy()
		endAttachment = nil
	end
	if endAnchor then
		endAnchor:Destroy()
		endAnchor = nil
	end
	lastTarget = nil
end

local function clearGuideVisuals()
	if guideBeam then
		guideBeam:Destroy()
		guideBeam = nil
	end
	if startAttachment then
		startAttachment:Destroy()
		startAttachment = nil
	end
	if endAttachment then
		endAttachment:Destroy()
		endAttachment = nil
	end
	if endAnchor then
		endAnchor:Destroy()
		endAnchor = nil
	end
	lastTarget = nil
end

local function getHighestUnitTier(units: any): number
	local highest = 0
	if type(units) ~= "table" then
		return highest
	end

	for _, unit in units do
		if type(unit) == "table" then
			highest = math.max(highest, math.floor(tonumber(unit.Tier) or 0))
		end
	end

	return highest
end

local function getStepFromData(PlayerDataController): string
	local tutorial = PlayerDataController:Get("Tutorial")
	local savedStep = if type(tutorial) == "table" and type(tutorial.Step) == "string"
		then tutorial.Step
		else "PickupDrop"
	local index = STEP_INDEX[savedStep] or 1
	local yen = tonumber(PlayerDataController:Get("Yen")) or 0
	local manaInBag = tonumber(PlayerDataController:Get("ManaInBag")) or 0
	local manaInDeposit = tonumber(PlayerDataController:Get("ManaInDeposit")) or 0
	local totalPurchased = math.max(math.floor(tonumber(PlayerDataController:Get("TotalUnitsPurchased")) or 0), 0)
	local units = PlayerDataController:Get("Units") or {}
	local highestTier = getHighestUnitTier(units)
	local rateLevel = math.max(math.floor(tonumber(PlayerDataController:Get("RateLevel")) or 0), 0)
	local rebirths = math.max(math.floor(tonumber(PlayerDataController:Get("Rebirths")) or 0), 0)
	local upgrades = PlayerDataController:Get("RebirthUpgrades")
	local unitSpawnTierLevel = if type(upgrades) == "table"
		then math.max(math.floor(tonumber(upgrades.UnitSpawnTier) or 0), 0)
		else 0
	local requiredRebirthTier = TycoonConfig.Rebirth.FirstRequiredTier or 5
	if type(tutorial) == "table" and tutorial.Completed == true then
		if tutorial.RebirthGuideCompleted == true then
			return "Completed"
		end

		index = math.max(index, STEP_INDEX[CORE_TUTORIAL_COMPLETE_STEP])
	end

	local collectGoal = math.max(math.floor(tonumber(getTutorialConfig().DropCollectGoal) or 5), 1)
	local collectGoal2 = math.max(math.floor(tonumber(getTutorialConfig().DropCollectGoal2) or 10), 1)
	local collectedManaProgress = math.max(manaInBag + manaInDeposit, if yen > 0 then collectGoal else 0)
	local currentMana = manaInBag + manaInDeposit

	if index == STEP_INDEX.PickupDrop and collectedManaProgress >= collectGoal then
		index = STEP_INDEX.DepositMana
	elseif index == STEP_INDEX.DepositMana and (manaInDeposit > 0 or yen > 0) then
		index = STEP_INDEX.BuySecondUnit
	elseif index == STEP_INDEX.BuySecondUnit and totalPurchased >= 1 then
		index = STEP_INDEX.PickupDropAgain
	elseif index == STEP_INDEX.PickupDropAgain then
		if secondCollectBaselineMana == nil then
			secondCollectBaselineMana = currentMana
			secondCollectBaselineYen = yen
		end
		local secondCollectProgress =
			math.max(currentMana - (secondCollectBaselineMana or currentMana), yen - (secondCollectBaselineYen or yen), 0)
		if totalPurchased >= 1 and secondCollectProgress >= collectGoal2 then
			index = STEP_INDEX.DepositManaAgain
		end
	elseif index == STEP_INDEX.DepositManaAgain then
		if secondDepositBaselineDeposit == nil then
			secondDepositBaselineDeposit = manaInDeposit
			secondDepositBaselineYen = yen
		end
		local secondDepositProgress = math.max(
			manaInDeposit - (secondDepositBaselineDeposit or manaInDeposit),
			yen - (secondDepositBaselineYen or yen),
			0
		)
		if secondDepositProgress > 0 then
			index = STEP_INDEX.UpgradeRate
		end
	elseif index == STEP_INDEX.UpgradeRate and rateLevel >= 1 then
		index = STEP_INDEX.BuyThirdUnit
	elseif index == STEP_INDEX.BuyThirdUnit and totalPurchased >= 2 then
		index = STEP_INDEX.MergeUnits
	elseif index == STEP_INDEX.MergeUnits and highestTier >= 2 then
		index = STEP_INDEX.VisitGroupReward
	elseif index == STEP_INDEX.WaitForRebirthReady and highestTier >= requiredRebirthTier then
		index = STEP_INDEX.Rebirth
	elseif index == STEP_INDEX.Rebirth and rebirths >= 1 then
		index = STEP_INDEX.OpenUpgrades
	elseif index == STEP_INDEX.OpenUpgrades and rebirths >= 1 then
		local mainGui = localPlayer.PlayerGui:FindFirstChild("MainGui")
		local upgradesFrame = mainGui and mainGui:FindFirstChild("UpgradesFrame")
		if upgradesFrame and upgradesFrame:IsA("GuiObject") and upgradesFrame.Visible then
			index = STEP_INDEX.UpgradeUnitSpawnTier
		end
	elseif index == STEP_INDEX.UpgradeUnitSpawnTier and rebirths >= 1 and unitSpawnTierLevel >= 1 then
		index = STEP_INDEX.Completed
	end

	return STEP_ORDER[index] or "PickupDrop"
end

local function getGuiButton(root: Instance?, name: string): GuiButton?
	local button = root and root:FindFirstChild(name, true)
	return if button and button:IsA("GuiButton") then button else nil
end

local function getTutorialStepFrame(): GuiObject?
	local config = getTutorialConfig()
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	local frame = playerGui and playerGui:FindFirstChild(config.StepFrameName or "TutorialStepFrame", true)
	return if frame and frame:IsA("GuiObject") then frame else nil
end

local function getTutorialRewardFrame(): GuiObject?
	local config = getTutorialConfig()
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	local frame = playerGui and playerGui:FindFirstChild(config.RewardFrameName or "TutorialReward", true)
	return if frame and frame:IsA("GuiObject") then frame else nil
end

local function getTextLabelByNames(root: Instance?, names: { string }): TextLabel?
	if not root then
		return nil
	end

	for _, name in names do
		local label = root:FindFirstChild(name, true)
		if label and label:IsA("TextLabel") then
			return label
		end
	end

	return nil
end

local function getMainGui(): ScreenGui?
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	local mainGui = playerGui and playerGui:FindFirstChild("MainGui")
	return if mainGui and mainGui:IsA("ScreenGui") then mainGui else nil
end

local function getGuiObjectByPath(root: Instance?, path: { string }): GuiObject?
	local current = root
	for _, name in path do
		current = current and (current:FindFirstChild(name) or current:FindFirstChild(name, true))
		if not current then
			return nil
		end
	end

	return if current and current:IsA("GuiObject") then current else nil
end

local function getTutorialFingerByPath(path: { string }): GuiObject?
	return getGuiObjectByPath(getMainGui(), path)
end

local function getRebirthFrame(): GuiObject?
	local mainGui = getMainGui()
	local frame = mainGui and mainGui:FindFirstChild("RebirthFrame")
	return if frame and frame:IsA("GuiObject") then frame else nil
end

local function getUpgradesFrame(): GuiObject?
	local mainGui = getMainGui()
	local frame = mainGui and mainGui:FindFirstChild("UpgradesFrame")
	return if frame and frame:IsA("GuiObject") then frame else nil
end

local function getRebirthButton(): GuiObject?
	return getGuiObjectByPath(getMainGui(), { "RightSide", "RebirthButton" })
end

local function setTutorialFingerActive(finger: GuiObject?, active: boolean, offset: UDim2)
	if not finger then
		return
	end

	local activeTween = tutorialFingerTweens[finger]
	if not active then
		if activeTween then
			activeTween.Tween:Cancel()
			finger.Position = activeTween.OriginalPosition
			tutorialFingerTweens[finger] = nil
		end
		finger.Visible = false
		return
	end

	finger.Visible = true
	if activeTween then
		return
	end

	local originalPosition = finger.Position
	local tween = TweenService:Create(
		finger,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = originalPosition + offset }
	)
	tutorialFingerTweens[finger] = {
		Tween = tween,
		OriginalPosition = originalPosition,
	}
	tween:Play()
end

local function clearTutorialFingers()
	for finger, data in tutorialFingerTweens do
		data.Tween:Cancel()
		if finger and finger.Parent then
			finger.Position = data.OriginalPosition
			finger.Visible = false
		end
	end

	table.clear(tutorialFingerTweens)

	for _, connection in tutorialFingerConnections do
		connection:Disconnect()
	end
	table.clear(tutorialFingerConnections)
	dismissedRebirthButtonFingerStep = nil
end

local connectRebirthTutorialFingerDismiss

local function updateRebirthTutorialFingers()
	if #tutorialFingerConnections <= 0 then
		connectRebirthTutorialFingerDismiss()
	end

	local isTutorialActive = currentStep ~= "Completed"
	local rebirthFrame = getRebirthFrame()
	local upgradesFrame = getUpgradesFrame()
	local rebirthFrameVisible = rebirthFrame and rebirthFrame.Visible == true
	local upgradesFrameVisible = upgradesFrame and upgradesFrame.Visible == true

	local rebirthButtonFinger = getTutorialFingerByPath({ "RightSide", "RebirthButton", "TutorialFinger" })
	local acceptButtonFinger = getTutorialFingerByPath({ "RebirthFrame", "AcceptButton", "TutorialFinger" })
	local upgradesButtonFinger = getTutorialFingerByPath({ "RebirthFrame", "Upgrades", "TutorialFinger" })
	local unitSpawnTierBuyFinger =
		getTutorialFingerByPath({ "UpgradesFrame", "UnitSpawnTier", "BuyButton", "TutorialFinger" })

	local shouldShowRebirthButton = isTutorialActive
		and (currentStep == "Rebirth" or currentStep == "OpenUpgrades")
		and not rebirthFrameVisible
		and dismissedRebirthButtonFingerStep ~= currentStep

	setTutorialFingerActive(rebirthButtonFinger, shouldShowRebirthButton, UDim2.fromOffset(14, 0))
	setTutorialFingerActive(
		acceptButtonFinger,
		isTutorialActive and currentStep == "Rebirth" and rebirthFrameVisible,
		UDim2.fromOffset(0, -12)
	)
	setTutorialFingerActive(
		upgradesButtonFinger,
		isTutorialActive and currentStep == "OpenUpgrades" and rebirthFrameVisible,
		UDim2.fromOffset(0, -10)
	)
	setTutorialFingerActive(
		unitSpawnTierBuyFinger,
		isTutorialActive and currentStep == "UpgradeUnitSpawnTier" and upgradesFrameVisible,
		UDim2.fromOffset(0, -10)
	)
end

function connectRebirthTutorialFingerDismiss()
	for _, connection in tutorialFingerConnections do
		connection:Disconnect()
	end
	table.clear(tutorialFingerConnections)

	local rebirthButton = getRebirthButton()
	if not rebirthButton then
		return
	end

	local clickable = if rebirthButton:IsA("GuiButton") then rebirthButton else rebirthButton:FindFirstChildWhichIsA("GuiButton", true)
	if not clickable then
		return
	end

	table.insert(
		tutorialFingerConnections,
		clickable.Activated:Connect(function()
			if currentStep == "Rebirth" or currentStep == "OpenUpgrades" then
				dismissedRebirthButtonFingerStep = currentStep
				updateRebirthTutorialFingers()
			end
		end)
	)
end

local function getProgressStepText(frame: Instance?): TextLabel?
	local progress = frame and frame:FindFirstChild("Progress", true)
	if progress then
		local stepText = progress:FindFirstChild("StepText", true)
		if stepText and stepText:IsA("TextLabel") then
			return stepText
		end
	end

	return getTextLabelByNames(frame, { "StepText", "ProgressText" })
end

local function getDescriptionStepText(frame: Instance?, playerGui: Instance): TextLabel?
	if frame then
		local tutorialSteps = frame:FindFirstChild("TutorialSteps", true)
		if tutorialSteps then
			local stepText = tutorialSteps:FindFirstChild("StepText", true)
			if stepText and stepText:IsA("TextLabel") then
				return stepText
			end
		end
	end

	return getTextLabelByNames(frame or playerGui, {
		"Description",
		"Desc",
		"Objective",
		"TutorialObjective",
		"Instruction",
		"Task",
		"StepText",
	})
end

local function getThanksMessageLabel(frame: Instance?): TextLabel?
	if not frame then
		return nil
	end

	local label = frame:FindFirstChild("ThanksMessage", true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function setThanksMessage(text: string)
	local frame = getTutorialRewardFrame()
	local label = getThanksMessageLabel(frame)
	if label then
		label.Text = text
	end
end

local function dismissTutorialRewardPresentation()
	tutorialRewardPresentationActive = false
	local frame = getTutorialRewardFrame()
	if frame then
		frame.Visible = false
	end
end

local function formatRewardMinutes(seconds: number): string
	local minutes = math.max((tonumber(seconds) or 0) / 60, 0)
	if math.abs(minutes - math.floor(minutes)) < 0.01 then
		return tostring(math.floor(minutes))
	end

	return string.format("%.1f", minutes)
end

local function updateTutorialRewardAmountText()
	local frame = getTutorialRewardFrame()
	if not frame then
		return
	end

	local config = getTutorialConfig()
	local rewardSeconds = math.max(math.floor(tonumber(config.RewardSeconds) or 15 * 60), 1)
	local rewardText = formatRewardMinutes(rewardSeconds) .. " minute 2x BOOST!"
	local amountLabel = frame:FindFirstChild("text1", true)
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = rewardText
	end
end

local function getCurrentUnitCount(): number
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local units = PlayerDataController:Get("Units")
	return if type(units) == "table" then #units else 0
end

local function getStepProgress(step: string): (number, number, string?)
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local yen = tonumber(PlayerDataController:Get("Yen")) or 0
	local manaInBag = tonumber(PlayerDataController:Get("ManaInBag")) or 0
	local manaInDeposit = tonumber(PlayerDataController:Get("ManaInDeposit")) or 0
	local totalPurchased = math.max(math.floor(tonumber(PlayerDataController:Get("TotalUnitsPurchased")) or 0), 0)
	local highestTier = getHighestUnitTier(PlayerDataController:Get("Units") or {})
	local rateLevel = math.max(math.floor(tonumber(PlayerDataController:Get("RateLevel")) or 0), 0)
	local rebirths = math.max(math.floor(tonumber(PlayerDataController:Get("Rebirths")) or 0), 0)
	local upgrades = PlayerDataController:Get("RebirthUpgrades")
	local unitSpawnTierLevel = if type(upgrades) == "table"
		then math.max(math.floor(tonumber(upgrades.UnitSpawnTier) or 0), 0)
		else 0
	local collectGoal = math.max(math.floor(tonumber(getTutorialConfig().DropCollectGoal) or 5), 1)
	local collectGoal2 = math.max(math.floor(tonumber(getTutorialConfig().DropCollectGoal2) or 10), 1)

	if step == "PickupDrop" then
		local current = math.max(manaInBag + manaInDeposit, if yen > 0 then collectGoal else 0)
		return math.min(math.floor(current), collectGoal), collectGoal, "Mana"
	elseif step == "DepositMana" then
		return if manaInDeposit > 0 or yen > 0 then 1 else 0, 1, "Deposit"
	elseif step == "BuySecondUnit" then
		if totalPurchased >= 1 then
			return 1, 1, "Units"
		end
		local cost = Pricing.getUnitBulkPrice(0, 1)
		return math.min(math.floor(yen), cost), cost, "Yen"
	elseif step == "PickupDropAgain" then
		local currentMana = manaInBag + manaInDeposit
		local current = math.max(
			currentMana - (secondCollectBaselineMana or currentMana),
			yen - (secondCollectBaselineYen or yen),
			0
		)
		return math.min(math.floor(current), collectGoal2), collectGoal2, "Mana"
	elseif step == "UpgradeRate" then
		return math.min(rateLevel, 1), 1, "Rate"
	elseif step == "DepositManaAgain" then
		local current = math.max(
			manaInDeposit - (secondDepositBaselineDeposit or manaInDeposit),
			yen - (secondDepositBaselineYen or yen),
			0
		)
		return if current > 0 then 1 else 0, 1, "Deposit"
	elseif step == "BuyThirdUnit" then
		if totalPurchased >= 2 then
			return 1, 1, "Units"
		end
		local cost = Pricing.getUnitBulkPrice(totalPurchased, 1)
		return math.min(math.floor(yen), cost), cost, "Yen"
	elseif step == "MergeUnits" then
		return if highestTier >= 2 then 1 else 0, 1, "Merge"
	elseif step == "VisitGroupReward" then
		return 0, 1, "Group"
	elseif step == "WaitForRebirthReady" then
		local requiredTier = TycoonConfig.Rebirth.FirstRequiredTier or 5
		return math.min(highestTier, requiredTier), requiredTier, "Tier"
	elseif step == "Rebirth" then
		return math.min(rebirths, 1), 1, "Rebirth"
	elseif step == "OpenUpgrades" then
		local mainGui = localPlayer.PlayerGui:FindFirstChild("MainGui")
		local upgradesFrame = mainGui and mainGui:FindFirstChild("UpgradesFrame")
		return if upgradesFrame and upgradesFrame:IsA("GuiObject") and upgradesFrame.Visible then 1 else 0, 1, "Open"
	elseif step == "UpgradeUnitSpawnTier" then
		return math.min(unitSpawnTierLevel, 1), 1, "Upgrade"
	elseif step == "Completed" then
		return 1, 1, "Done"
	end

	return 0, 0, nil
end

local function formatProgressValue(value: number): string
	if value >= 1000 then
		return Pricing.formatYen(value)
	end

	return tostring(math.floor(value))
end

function TutorialController:GetStep(): string
	return currentStep
end

function TutorialController:GetObjectiveText(): string
	return STEP_TEXT[currentStep] or ""
end

function TutorialController:MarkGroupRewardVisited()
	if currentStep == "VisitGroupReward" then
		self:setStep("WaitForRebirthReady")
	end
end

function TutorialController:isActive(): boolean
	return currentStep ~= "Completed"
end

function TutorialController:shouldTrack(): boolean
	return currentStep ~= "Completed"
end

function TutorialController:isRebirthContinuationWaiting(): boolean
	if currentStep ~= CORE_TUTORIAL_COMPLETE_STEP then
		return false
	end

	local PlayerDataController = Knit.GetController("PlayerDataController")
	local requiredTier = TycoonConfig.Rebirth.FirstRequiredTier or 5
	return getHighestUnitTier(PlayerDataController:Get("Units") or {}) < requiredTier
end

function TutorialController:canClaimTutorialReward(): boolean
	local PlayerDataController = Knit.GetController("PlayerDataController")
	local tutorial = PlayerDataController:Get("Tutorial")
	return type(tutorial) == "table"
		and tutorial.Completed == true
		and tutorial.RewardClaimed ~= true
end

function TutorialController:presentTutorialReward()
	local frame = getTutorialRewardFrame()
	if not frame then
		return
	end

	tutorialRewardPresentationActive = true
	setThanksMessage(COMPLETED_REWARD_THANKS_MESSAGE)
	updateTutorialRewardAmountText()
	frame.Visible = true
end

function TutorialController:claimAndPresentTutorialReward()
	local TycoonService = Knit.GetService("TycoonService")
	TycoonService:ClaimTutorialReward()
		:andThen(function(success)
			if success then
				self:presentTutorialReward()
			end
		end)
		:catch(function(err)
			warn("[TutorialController] ClaimTutorialReward failed:", err)
		end)
end

function TutorialController:updateTutorialRewardUi()
	if tutorialRewardPresentationActive then
		return
	end

	local frame = getTutorialRewardFrame()
	if frame then
		frame.Visible = false
	end
end

function TutorialController:updateOptionalProgressUi()
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local frame = getTutorialStepFrame()
	if frame then
		frame.Visible = self:isActive() and not self:isRebirthContinuationWaiting()
	end

	local objectiveText = self:GetObjectiveText()
	local descriptionLabel = getDescriptionStepText(frame, playerGui)
	if descriptionLabel then
		descriptionLabel.Text = objectiveText
	end

	local progressLabel = getProgressStepText(frame or playerGui)
	if progressLabel then
		local current, target, suffix = getStepProgress(currentStep)
		local suffixText = if suffix and suffix ~= "" then " " .. suffix else ""
		progressLabel.Text = formatProgressValue(current) .. "/" .. formatProgressValue(target) .. suffixText
	end

	self:updateTutorialRewardUi()
end

function TutorialController:persistStep(step: string)
	if step == lastPersistedStep then
		return
	end
	lastPersistedStep = step

	local TycoonService = Knit.GetService("TycoonService")
	if step == "Completed" then
		TycoonService:UpdateTutorialStep(step):catch(function(err)
			warn("[TutorialController] UpdateTutorialStep failed:", err)
		end)
	elseif step == CORE_TUTORIAL_COMPLETE_STEP then
		TycoonService:UpdateTutorialStep(step)
			:andThen(function()
				return TycoonService:CompleteTutorial()
			end)
			:andThen(function(success)
				if success then
					self:claimAndPresentTutorialReward()
				end
			end)
			:catch(function(err)
				warn("[TutorialController] CompleteTutorial failed:", err)
			end)
	else
		TycoonService:UpdateTutorialStep(step):catch(function(err)
			warn("[TutorialController] UpdateTutorialStep failed:", err)
		end)
	end
end

function TutorialController:setStep(step: string)
	if currentStep == step then
		return
	end

	local previousStep = currentStep
	local previousIndex = STEP_INDEX[previousStep]
	local nextIndex = STEP_INDEX[step]
	currentStep = step
	dismissedRebirthButtonFingerStep = nil
	if previousIndex and nextIndex and nextIndex > previousIndex then
		SoundUtil.TutorialProgress()
	end

	if step == "PickupDropAgain" then
		local PlayerDataController = Knit.GetController("PlayerDataController")
		secondCollectBaselineMana = (tonumber(PlayerDataController:Get("ManaInBag")) or 0)
			+ (tonumber(PlayerDataController:Get("ManaInDeposit")) or 0)
		secondCollectBaselineYen = tonumber(PlayerDataController:Get("Yen")) or 0
	elseif step ~= "PickupDropAgain" then
		secondCollectBaselineMana = nil
		secondCollectBaselineYen = nil
	end
	if step == "DepositManaAgain" then
		local PlayerDataController = Knit.GetController("PlayerDataController")
		secondDepositBaselineDeposit = tonumber(PlayerDataController:Get("ManaInDeposit")) or 0
		secondDepositBaselineYen = tonumber(PlayerDataController:Get("Yen")) or 0
	elseif step ~= "DepositManaAgain" then
		secondDepositBaselineDeposit = nil
		secondDepositBaselineYen = nil
	end
	self:updateOptionalProgressUi()
	updateRebirthTutorialFingers()
	self:persistStep(step)

	if step == "Completed" then
		clearGuide()
		clearTutorialFingers()
	end
end

function TutorialController:evaluateProgress()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	self:setStep(getStepFromData(PlayerDataController))
	self:updateOptionalProgressUi()
end

function TutorialController:startGuideLoop()
	if guideConnection then
		return
	end

	local elapsed = 0
	guideConnection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed < GUIDE_UPDATE_INTERVAL then
			return
		end
		elapsed = 0

		if not self:shouldTrack() then
			clearGuide()
			clearTutorialFingers()
			if guideConnection then
				guideConnection:Disconnect()
				guideConnection = nil
			end
			return
		end

		updateRebirthTutorialFingers()

		if currentStep == "WaitForRebirthReady" then
			clearGuideVisuals()
			return
		end

		local target = getStepTarget(currentStep)
		if target then
			ensureGuide(target)
		else
			clearGuideVisuals()
		end
	end)
end

function TutorialController:startProgressTracking()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	for _, connection in dataConnections do
		connection:Disconnect()
	end
	table.clear(dataConnections)

	for _, path in
		{
			"Yen",
			"ManaInBag",
			"ManaInDeposit",
			"TotalUnitsPurchased",
			"Units",
			"RateLevel",
			"Rebirths",
			"RebirthUpgrades",
			"Tutorial",
		}
	do
		table.insert(
			dataConnections,
			PlayerDataController:Observe(path, function()
				self:evaluateProgress()
			end)
		)
	end

	self:evaluateProgress()
	self:startGuideLoop()

	task.spawn(function()
		while self:shouldTrack() do
			self:evaluateProgress()
			task.wait(0.25)
		end
		self:updateOptionalProgressUi()
	end)
end

function TutorialController:connectReward()
	local frame = getTutorialRewardFrame()
	if not frame then
		return
	end

	for _, connection in rewardConnections do
		connection:Disconnect()
	end
	table.clear(rewardConnections)

	local acceptButton = getGuiButton(frame, "Accept")
	if acceptButton then
		table.insert(
			rewardConnections,
			acceptButton.Activated:Connect(function()
				dismissTutorialRewardPresentation()
				self:updateTutorialRewardUi()
			end)
		)
	end

	self:updateTutorialRewardUi()
end

function TutorialController:KnitStart()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	PlayerDataController:WaitForData()

	local tutorial = PlayerDataController:Get("Tutorial")
	local initialStep = getStepFromData(PlayerDataController)
	currentStep = initialStep
	lastPersistedStep = initialStep
	local shouldTrack = currentStep ~= "Completed"

	task.spawn(function()
		local deadline = os.clock() + 20
		while os.clock() < deadline do
			local stepFrame = getTutorialStepFrame()
			local rewardFrame = getTutorialRewardFrame()
			if stepFrame and rewardFrame then
				break
			end
			task.wait(0.25)
		end

		self:connectReward()
		connectRebirthTutorialFingerDismiss()
		if shouldTrack then
			self:evaluateProgress()
		end
		self:updateOptionalProgressUi()
		updateRebirthTutorialFingers()
	end)

	PlayerDataController:Observe("Tutorial", function()
		self:updateTutorialRewardUi()
	end)

	if self:canClaimTutorialReward() then
		self:claimAndPresentTutorialReward()
	end

	if shouldTrack then
		self:startProgressTracking()
	else
		self:updateOptionalProgressUi()
		clearTutorialFingers()
	end

	localPlayer.CharacterAdded:Connect(function()
		clearGuide()
		if currentStep ~= "Completed" then
			self:startGuideLoop()
		end
	end)
end

return TutorialController
