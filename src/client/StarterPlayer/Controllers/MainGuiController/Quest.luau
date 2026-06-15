local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonNoti = require(script.Parent.ButtonNoti)
local OpenFrame = require(ReplicatedStorage.Shared.Observers.OpenFrame)
local QuestConfig = require(ReplicatedStorage.Shared.Data.QuestConfig)
local QuestUtil = require(ReplicatedStorage.Shared.Features.Quests.QuestUtil)
local SoundUtil = require(ReplicatedStorage.Shared.Features.SoundUtil)
local Knit = require(ReplicatedStorage.Packages.knit)

local Quest = {}

local questConnections: { RBXScriptConnection } = {}
local questRequestOpen = false
local activeCategory = "Hourly"
local timerRunning = false
local QUEST_NOTI_KEY = "Quests"
local QUEST_BUTTON_NAME = "QuestsButton"

local playtimeBaselineAtSessionStart = 0
local playtimeSessionStartedAt = 0

local CATEGORY_FRAMES = { "Hourly", "Daily", "Weekly" }

local acknowledgedQuestPeriods: { [string]: string } = {
	Hourly = "",
	Daily = "",
	Weekly = "",
}
local dismissedClaimableQuestKeys: { [string]: boolean }? = nil

local function getCategoryPeriodId(quests: any, category: string): string
	if type(quests) ~= "table" then
		return ""
	end

	local categoryData = quests[category]
	if type(categoryData) ~= "table" then
		return ""
	end

	return tostring(categoryData.PeriodId or "")
end

local function hasUnseenQuestPeriods(quests: any): boolean
	for _, category in CATEGORY_FRAMES do
		local periodId = getCategoryPeriodId(quests, category)
		if periodId ~= "" and periodId ~= acknowledgedQuestPeriods[category] then
			return true
		end
	end

	return false
end

local function getClaimableQuestKeys(quests: any): { [string]: boolean }
	local keys = {}
	if type(quests) ~= "table" then
		return keys
	end

	for _, category in CATEGORY_FRAMES do
		local categoryData = quests[category]
		if type(categoryData) ~= "table" or type(categoryData.Slots) ~= "table" then
			continue
		end

		for slotIndex, slot in categoryData.Slots do
			if type(slot) ~= "table" or slot.Claimed == true then
				continue
			end

			local progress = math.max(math.floor(tonumber(slot.Progress) or 0), 0)
			if QuestUtil.isQuestComplete(slot.Type, slot.Target, progress) then
				keys[category .. ":" .. tostring(slotIndex)] = true
			end
		end
	end

	return keys
end

local function hasNewClaimableQuests(quests: any): boolean
	local claimableKeys = getClaimableQuestKeys(quests)
	if dismissedClaimableQuestKeys == nil then
		return next(claimableKeys) ~= nil
	end

	for key in claimableKeys do
		if dismissedClaimableQuestKeys[key] ~= true then
			return true
		end
	end

	return false
end

local function acknowledgeQuestPeriods(quests: any)
	for _, category in CATEGORY_FRAMES do
		acknowledgedQuestPeriods[category] = getCategoryPeriodId(quests, category)
	end
	dismissedClaimableQuestKeys = getClaimableQuestKeys(quests)
end

local function shouldShowQuestNoti(quests: any): boolean
	if hasUnseenQuestPeriods(quests) then
		dismissedClaimableQuestKeys = nil
		return true
	end

	return hasNewClaimableQuests(quests)
end

local function syncPlaytimeSessionBaseline()
	local PlayerDataController = Knit.GetController("PlayerDataController")
	playtimeBaselineAtSessionStart = math.max(math.floor(tonumber(PlayerDataController:Get("PlaytimeSeconds")) or 0), 0)
	playtimeSessionStartedAt = os.time()
end

local function getEstimatedPlaytimeSeconds(): number
	return playtimeBaselineAtSessionStart + math.max(os.time() - playtimeSessionStartedAt, 0)
end

local function getQuestSlotProgress(category: string, slot: any): number
	if type(slot) ~= "table" then
		return 0
	end

	if slot.Type == "Playtime" then
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local quests = PlayerDataController:Get("Quests")
		local categoryData = if type(quests) == "table" then quests[category] else nil
		local baselines = if type(categoryData) == "table" and type(categoryData.Baselines) == "table"
			then categoryData.Baselines
			else {}

		return QuestUtil.computeProgress(slot.Type, slot.Target, {
			PlaytimeSeconds = getEstimatedPlaytimeSeconds(),
		}, baselines)
	end

	return math.max(math.floor(tonumber(slot.Progress) or 0), 0)
end

function Quest.Install(MainGuiController)
	function MainGuiController:areQuestsUnlocked(): boolean
		local PlayerDataController = Knit.GetController("PlayerDataController")
		return math.max(math.floor(tonumber(PlayerDataController:Get("Rebirths")) or 0), 0) >= 1
	end

	function MainGuiController:connectQuestGuiActivated(guiObject: GuiObject, callback: () -> ())
		local clickable = self:getClickableGui(guiObject)
		if clickable:IsA("TextButton") or clickable:IsA("ImageButton") then
			table.insert(questConnections, clickable.Activated:Connect(callback))
		else
			table.insert(
				questConnections,
				clickable.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						callback()
					end
				end)
			)
		end
	end

	function MainGuiController:clearQuestConnections()
		for _, connection in questConnections do
			connection:Disconnect()
		end

		table.clear(questConnections)
	end

	function MainGuiController:getQuestsFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local frame = mainGui:FindFirstChild("QuestsFrame")
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:getQuestCategoryFrame(frame: Instance, category: string): GuiObject?
		local categoryFrame = frame:FindFirstChild(category, true)
		return if categoryFrame and categoryFrame:IsA("GuiObject") then categoryFrame else nil
	end

	function MainGuiController:updateQuestsButtonNoti()
		if not self:areQuestsUnlocked() then
			ButtonNoti.update(self, QUEST_NOTI_KEY, QUEST_BUTTON_NAME, false)
			return
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		local quests = PlayerDataController:Get("Quests")
		ButtonNoti.update(self, QUEST_NOTI_KEY, QUEST_BUTTON_NAME, shouldShowQuestNoti(quests))
	end

	function MainGuiController:updateQuestsAccess()
		local unlocked = self:areQuestsUnlocked()
		local questsButton = self:getRightSideButton(QUEST_BUTTON_NAME)
		if questsButton then
			questsButton.Visible = true
			local lockedFrame = questsButton:FindFirstChild("Locked", true)
			if lockedFrame and lockedFrame:IsA("GuiObject") then
				lockedFrame.Visible = not unlocked
			end
		end

		local frame = self:getQuestsFrame()
		if frame and not unlocked then
			frame.Visible = false
		end

		if not unlocked then
			ButtonNoti.update(self, QUEST_NOTI_KEY, QUEST_BUTTON_NAME, false)
		end
	end

	function MainGuiController:getQuestRewardContext()
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local units = PlayerDataController:Get("Units") or {}
		local rebirths = PlayerDataController:Get("Rebirths") or 0

		return QuestUtil.getRewardContext(units, QuestUtil.estimateYenMultiplier(rebirths))
	end

	function MainGuiController:setQuestClaimButtonText(claimButton: Instance, text: string)
		if claimButton:IsA("TextButton") or claimButton:IsA("TextLabel") then
			claimButton.Text = text
			return
		end

		local label = claimButton:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = text
		end
	end

	function MainGuiController:setQuestCompletedFrame(row: GuiObject, visible: boolean)
		local completedFrame = row:FindFirstChild("CompletedFrame", true)
		if completedFrame and completedFrame:IsA("GuiObject") then
			completedFrame.Visible = visible
		end
	end

	function MainGuiController:updateQuestRow(row: GuiObject, slotIndex: number, category: string, slot: any, rewardContext: { [string]: any })
		if type(slot) ~= "table" then
			self:setNamedText(row, "Title", "Quest " .. tostring(slotIndex))
			self:setNamedText(row, "QuestLabel", "Loading...")
			self:setNamedText(row, "Reward", "")
			self:setQuestCompletedFrame(row, false)
			self:setQuestClaimButtonText(row:FindFirstChild("ClaimButton", true) or row, "Claim")
			return
		end

		local progress = getQuestSlotProgress(category, slot)
		local isComplete = QuestUtil.isQuestComplete(slot.Type, slot.Target, progress)
		local claimed = slot.Claimed == true

		self:setNamedText(row, "Title", "Quest " .. tostring(slotIndex))
		self:setNamedText(row, "QuestLabel", QuestUtil.formatQuestDescription(slot.Type, slot.Target, progress))
		self:setNamedText(
			row,
			"Reward",
			QuestUtil.formatRewardText(slot.Reward, rewardContext, category)
		)
		self:setQuestCompletedFrame(row, claimed)

		local claimButton = row:FindFirstChild("ClaimButton", true)
		if claimButton and claimButton:IsA("GuiObject") then
			claimButton.Visible = not claimed
			if claimed then
				self:setQuestClaimButtonText(claimButton, "Claimed")
			elseif isComplete then
				self:setQuestClaimButtonText(claimButton, "Claim")
			else
				self:setQuestClaimButtonText(claimButton, "Claim")
			end
		end
	end

	function MainGuiController:updateQuestCategoryTimers(frame: GuiObject)
		for _, category in CATEGORY_FRAMES do
			local categoryFrame = self:getQuestCategoryFrame(frame, category)
			if not categoryFrame then
				continue
			end

			local timerLabel = categoryFrame:FindFirstChild("Timer", true)
			if timerLabel and timerLabel:IsA("TextLabel") then
				timerLabel.Text = QuestUtil.formatTimeUntilReset(category)
			end
		end
	end

	function MainGuiController:setActiveQuestCategory(frame: GuiObject, category: string)
		activeCategory = category

		for _, categoryName in CATEGORY_FRAMES do
			local categoryFrame = self:getQuestCategoryFrame(frame, categoryName)
			if categoryFrame and categoryFrame:IsA("GuiObject") then
				categoryFrame.Visible = categoryName == category
			end
		end

		local categories = frame:FindFirstChild("Categories", true)
		if categories then
			for _, child in categories:GetChildren() do
				if child:IsA("GuiObject") and child.Name == "Hourly" or child.Name == "Daily" or child.Name == "Weekly" then
					-- keep buttons visible; optional highlight via transparency could go here
				end
			end
		end
	end

	function MainGuiController:updateQuestsFrame(force: boolean?)
		self:updateQuestsAccess()
		if not self:areQuestsUnlocked() then
			return
		end

		local frame = self:getQuestsFrame()
		if not frame then
			return
		end
		if not force and not frame.Visible then
			self:updateQuestsButtonNoti()
			return
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		local quests = PlayerDataController:Get("Quests")
		local rewardContext = self:getQuestRewardContext()

		for _, category in CATEGORY_FRAMES do
			local categoryFrame = self:getQuestCategoryFrame(frame, category)
			if not categoryFrame then
				continue
			end

			local slots = if type(quests) == "table" and type(quests[category]) == "table"
				then quests[category].Slots
				else nil

			for slotIndex = 1, QuestConfig.QuestCount do
				local row = categoryFrame:FindFirstChild("Quest" .. tostring(slotIndex), true)
				if row and row:IsA("GuiObject") then
					local slot = if type(slots) == "table" then slots[slotIndex] else nil
					self:updateQuestRow(row, slotIndex, category, slot, rewardContext)
				end
			end
		end

		self:setActiveQuestCategory(frame, activeCategory)
		self:updateQuestCategoryTimers(frame)
		self:updateQuestsButtonNoti()
	end

	function MainGuiController:buyQuestClaim(category: string, slotIndex: number)
		if questRequestOpen or not self:areQuestsUnlocked() then
			return
		end

		questRequestOpen = true
		local QuestService = Knit.GetService("QuestService")
		QuestService:ClaimQuest(category, slotIndex)
			:andThen(function(success, err, rewardText)
				questRequestOpen = false
				if success then
					SoundUtil.TutorialProgress()
					if type(rewardText) == "string" and rewardText ~= "" then
						self:ShowQuestRewardMessage(rewardText)
					end
					self:updateQuestsFrame()
				elseif err == "Not complete" then
					self:updateQuestsFrame()
				elseif err == "Already claimed" then
					self:updateQuestsFrame()
				elseif err then
					warn("[MainGuiController] Quest claim failed:", err)
				end
			end)
			:catch(function(err)
				questRequestOpen = false
				warn("[MainGuiController] Quest claim failed:", err)
			end)
	end

	function MainGuiController:startQuestTimerLoop()
		if timerRunning then
			return
		end

		timerRunning = true
		task.spawn(function()
			while timerRunning do
				local frame = self:getQuestsFrame()
				if frame and frame.Visible and self:areQuestsUnlocked() then
					self:updateQuestCategoryTimers(frame)
					self:updateQuestsFrame()
				end
				task.wait(1)
			end
		end)
	end

	function MainGuiController:setupQuestsFrame()
		self:clearQuestConnections()

		local frame = self:getQuestsFrame()
		if not frame then
			return
		end

		frame.Visible = false
		OpenFrame.SetupFrame(frame)
		self:updateQuestsAccess()

		activeCategory = "Hourly"
		self:setActiveQuestCategory(frame, activeCategory)
		self:updateQuestsFrame(true)
		self:startQuestTimerLoop()

		local closeButton = frame:FindFirstChild("CloseButton", true)
		if closeButton and closeButton:IsA("GuiObject") then
			self:connectQuestGuiActivated(closeButton, function()
				OpenFrame.Toggle(frame, false)
			end)
		end

		local categories = frame:FindFirstChild("Categories", true)
		if categories then
			for _, category in CATEGORY_FRAMES do
				local tabButton = categories:FindFirstChild(category, true)
				if tabButton and tabButton:IsA("GuiObject") then
					self:connectQuestGuiActivated(tabButton, function()
						self:setActiveQuestCategory(frame, category)
						self:updateQuestsFrame()
					end)
				end
			end
		end

		for _, category in CATEGORY_FRAMES do
			local categoryFrame = self:getQuestCategoryFrame(frame, category)
			if not categoryFrame then
				continue
			end

			for slotIndex = 1, QuestConfig.QuestCount do
				local row = categoryFrame:FindFirstChild("Quest" .. tostring(slotIndex), true)
				local claimButton = row and row:FindFirstChild("ClaimButton", true)
				if claimButton and claimButton:IsA("GuiObject") then
					self:connectQuestGuiActivated(claimButton, function()
						local PlayerDataController = Knit.GetController("PlayerDataController")
						local quests = PlayerDataController:Get("Quests")
						local slots = if type(quests) == "table" and type(quests[category]) == "table"
							then quests[category].Slots
							else nil
						local slot = if type(slots) == "table" then slots[slotIndex] else nil
						if type(slot) == "table" and slot.Claimed == true then
							return
						end

						local progress = if type(slot) == "table" then getQuestSlotProgress(category, slot) else 0
						if type(slot) ~= "table"
							or not QuestUtil.isQuestComplete(slot.Type, slot.Target, progress)
						then
							return
						end

						self:buyQuestClaim(category, slotIndex)
					end)
				end
			end
		end

		ButtonNoti.hideInitially(self, QUEST_BUTTON_NAME)

		local questsButton = self:getRightSideButton(QUEST_BUTTON_NAME)
		if questsButton then
			self:updateQuestsAccess()
			self:connectQuestGuiActivated(questsButton, function()
				if not self:areQuestsUnlocked() then
					return
				end

				local PlayerDataController = Knit.GetController("PlayerDataController")
				acknowledgeQuestPeriods(PlayerDataController:Get("Quests"))
				local QuestService = Knit.GetService("QuestService")
				QuestService:LogQuestOpened():catch(function(err)
					warn("[MainGuiController] Quest open analytics failed:", err)
				end)
				OpenFrame.Toggle(frame)
				self:updateQuestsFrame(true)
				self:updateQuestsButtonNoti()
			end)
		end

		self:updateQuestsButtonNoti()

		task.spawn(function()
			local PlayerDataController = Knit.GetController("PlayerDataController")
			PlayerDataController:WaitForData()
			syncPlaytimeSessionBaseline()
			table.insert(questConnections, PlayerDataController:Observe("PlaytimeSeconds", function()
				syncPlaytimeSessionBaseline()
			end))
		end)
	end
end

return Quest
