local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleUtil = require(ReplicatedStorage.Shared.Features.Capsules.CapsuleUtil)
local Monetization = require(ReplicatedStorage.Shared.Data.Monetization)
local Pricing = require(ReplicatedStorage.Shared.Features.Tycoon.Pricing)

local OPEN_CAPSULE_PRODUCT = Monetization.DeveloperProducts.OpenCapsule

local CapsuleFeature = {}

function CapsuleFeature.Install(MainGuiController)
	function MainGuiController:getOpenCapsuleFrame(): GuiObject?
		local mainGui = self:getMainGui()
		if not mainGui then
			return nil
		end

		local frame = mainGui:FindFirstChild("OpenCapsuleFrame", true)
		return if frame and frame:IsA("GuiObject") then frame else nil
	end

	function MainGuiController:hideOpenCapsuleUI()
		local frame = self:getOpenCapsuleFrame()
		if frame then
			frame.Visible = false
		end
		self.activeCapsuleId = nil
	end

	function MainGuiController:showOpenCapsuleUI(
		capsuleId: string,
		_previewTiers: { number },
		openPrice: number,
		highestTier: number
	)
		local frame = self:getOpenCapsuleFrame()
		if not frame then
			warn("[MainGuiController] OpenCapsuleFrame not found")
			return
		end

		self.activeCapsuleId = capsuleId
		local displayEntries = CapsuleUtil.getPreviewDisplayEntries(highestTier)

		local unitsFrame = frame:FindFirstChild("Units", true)
		if unitsFrame then
			for index = 1, 3 do
				local label = unitsFrame:FindFirstChild(`Unit{index}`)
				local entry = displayEntries[index]
				if label and label:IsA("TextLabel") and entry then
					label.Text = `{entry.DisplayName} [{CapsuleUtil.formatChancePercent(entry.Chance)}]`
					label.Visible = true
				elseif label and label:IsA("TextLabel") then
					label.Visible = false
				end
			end
		end

		local openButton = frame:FindFirstChild("Open", true)
		if openButton then
			local priceLabel = openButton:FindFirstChild("Price", true)
			if priceLabel and priceLabel:IsA("TextLabel") then
				priceLabel.Text = Pricing.formatYen(openPrice)
			end
		end

		local robuxButton = frame:FindFirstChild("OpenRobux", true)
		if robuxButton then
			local priceLabel = robuxButton:FindFirstChild("Price", true)
			if priceLabel and priceLabel:IsA("TextLabel") then
				priceLabel.Text = `{OPEN_CAPSULE_PRODUCT.Price or 49} Robux`
			end
		end

		frame.Visible = true
	end

	function MainGuiController:setupOpenCapsuleFrame()
		local frame = self:getOpenCapsuleFrame()
		if not frame then
			return
		end

		frame.Visible = false
		self.activeCapsuleId = nil

		local function bindOpenButton(buttonName: string, opener: (string) -> ())
			local button = frame:FindFirstChild(buttonName, true)
			if not button or not button:IsA("GuiButton") then
				return
			end

			button.Activated:Connect(function()
				local capsuleId = self.activeCapsuleId
				if type(capsuleId) ~= "string" or capsuleId == "" then
					return
				end

				opener(capsuleId)
			end)
		end

		local Knit = require(ReplicatedStorage.Packages.knit)
		bindOpenButton("Open", function(capsuleId: string)
			Knit.GetController("CapsuleController"):openWithYen(capsuleId)
		end)
		bindOpenButton("OpenRobux", function(capsuleId: string)
			Knit.GetController("CapsuleController"):openWithRobux(capsuleId)
		end)
		bindOpenButton("Delete", function(capsuleId: string)
			Knit.GetController("CapsuleController"):dropCapsule(capsuleId)
		end)
	end
end

return CapsuleFeature
