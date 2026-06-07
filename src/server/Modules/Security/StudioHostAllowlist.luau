--[[
	Server-only: **single source of truth** for Cmdr admin UserIds.

	Used to set `BananaBombCmdrAdmin` on players and to verify Cmdr `BeforeRun` on the server.
	No gameplay bypasses — grants go through Cmdr commands only.

	**Security:** Do not `require` this from `ReplicatedStorage` shared scripts or the client. Exploiters
	cannot flip these flags from Lua; only server code paths that already receive the real `Player`
	instance may call `isAdminPlayer`. Never trust a userId sent in a remote payload for admin checks.
]]

local RunService = game:GetService("RunService")

if not RunService:IsServer() then
	error("[StudioHostAllowlist] This module must only run on the server.")
end

--- Edit this list only; all admin checks derive from it.
local ADMIN_USER_IDS: { number } = {
	441724376,
	689277747,
}

local ALLOW: { [number]: boolean } = {}
for _, uid in ipairs(ADMIN_USER_IDS) do
	if typeof(uid) == "number" and uid > 0 then
		ALLOW[uid] = true
	end
end

local StudioHostAllowlist = {}

function StudioHostAllowlist.getAdminUserIds(): { number }
	local out: { number } = {}
	for i, uid in ipairs(ADMIN_USER_IDS) do
		out[i] = uid
	end
	return out
end

function StudioHostAllowlist.isAdminUserId(userId: number): boolean
	return ALLOW[userId] == true
end

function StudioHostAllowlist.isAdminPlayer(player: Player?): boolean
	if not (player and player:IsA("Player")) then
		return false
	end
	return ALLOW[player.UserId] == true
end

--- Legacy names (same behavior as `isAdmin*`).
StudioHostAllowlist.isHostUserId = StudioHostAllowlist.isAdminUserId
StudioHostAllowlist.isHostPlayer = StudioHostAllowlist.isAdminPlayer

return StudioHostAllowlist
