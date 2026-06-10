local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
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

local CATEGORY_FRAMES = { "Hourly", "Daily", "Weekly" }

function Quest.Install(MainGuiController)
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

	function MainGuiController:getQuestRewardTier()
		local PlayerDataController = Knit.GetController("PlayerDataController")
		local units = PlayerDataController:Get("Units") or {}
		return CapsuleUtil.getHighestUnitTier(units)
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

	function MainGuiController:updateQuestRow(row: GuiObject, slotIndex: number, category: string, slot: any, highestTier: number)
		if type(slot) ~= "table" then
			self:setNamedText(row, "Title", "Quest " .. tostring(slotIndex))
			self:setNamedText(row, "QuestLabel", "Loading...")
			self:setNamedText(row, "Reward", "")
			self:setQuestCompletedFrame(row, false)
			self:setQuestClaimButtonText(row:FindFirstChild("ClaimButton", true) or row, "Claim")
			return
		end

		local progress = math.max(math.floor(tonumber(slot.Progress) or 0), 0)
		local isComplete = QuestUtil.isQuestComplete(slot.Type, slot.Target, progress)
		local claimed = slot.Claimed == true

		self:setNamedText(row, "Title", "Quest " .. tostring(slotIndex))
		self:setNamedText(row, "QuestLabel", QuestUtil.formatQuestDescription(slot.Type, slot.Target, progress))
		self:setNamedText(
			row,
			"Reward",
			QuestUtil.formatRewardText(slot.Reward, highestTier, category)
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

	function MainGuiController:updateQuestsFrame()
		local frame = self:getQuestsFrame()
		if not frame then
			return
		end

		local PlayerDataController = Knit.GetController("PlayerDataController")
		local quests = PlayerDataController:Get("Quests")
		local highestTier = self:getQuestRewardTier()

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
					self:updateQuestRow(row, slotIndex, category, slot, highestTier)
				end
			end
		end

		self:setActiveQuestCategory(frame, activeCategory)
		self:updateQuestCategoryTimers(frame)
	end

	function MainGuiController:buyQuestClaim(category: string, slotIndex: number)
		if questRequestOpen then
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
				if frame then
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
		activeCategory = "Hourly"
		self:setActiveQuestCategory(frame, activeCategory)
		self:updateQuestsFrame()
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

						local progress = if type(slot) == "table"
							then math.max(math.floor(tonumber(slot.Progress) or 0), 0)
							else 0
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

		local questsButton = self:getRightSideButton("QuestsButton")
		if questsButton then
			self:connectQuestGuiActivated(questsButton, function()
				self:updateQuestsFrame()
				OpenFrame.Toggle(frame)
			end)
		end
	end
end

return Quest
