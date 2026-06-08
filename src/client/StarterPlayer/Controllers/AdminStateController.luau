local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminRuntime = require(ReplicatedStorage.Shared.Features.Admin.AdminRuntime)
local Knit = require(ReplicatedStorage.Packages.knit)

local AdminStateController = Knit.CreateController({
	Name = "AdminStateController",
})

function AdminStateController:KnitStart()
	local AdminService = Knit.GetService("AdminService")
	local MainGuiController = Knit.GetController("MainGuiController")
	local TycoonController = Knit.GetController("TycoonController")

	local function applyAdminState(state: { [string]: any }?)
		if type(state) == "table" then
			AdminRuntime.setReplicatedState(state)
		end
		MainGuiController:updateEventDisplay()
		TycoonController:refreshOwnTycoonForEvent()
	end

	AdminService.StateChanged:Connect(function(state)
		applyAdminState(state)
	end)

	AdminService.AdminBannerReceived:Connect(function(kind: string, senderName: string, data: any)
		MainGuiController:ShowAdminBanner(kind, senderName, data)
	end)

	AdminService:GetPublicState():andThen(function(state)
		applyAdminState(state)
	end)
end

return AdminStateController
