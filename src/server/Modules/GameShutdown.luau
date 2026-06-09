local Players = game:GetService("Players")

local GameShutdown = {}

local shuttingDown = false
local listeners: { () -> () } = {}

function GameShutdown.isShuttingDown(): boolean
	return shuttingDown
end

function GameShutdown.onRequested(callback: () -> ())
	table.insert(listeners, callback)
	if shuttingDown then
		pcall(callback)
	end
end

function GameShutdown.request(_reason: string?)
	if shuttingDown then
		return
	end

	shuttingDown = true
	for _, callback in listeners do
		pcall(callback)
	end
end

function GameShutdown.init()
	game:BindToClose(function()
		GameShutdown.request("BindToClose")
	end)

	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if #Players:GetPlayers() <= 0 then
				GameShutdown.request("LastPlayerRemoved")
			end
		end)
	end)
end

return GameShutdown
