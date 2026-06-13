local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionConfig = require(ReplicatedStorage.Shared.Data.PotionConfig)
local Knit = require(ReplicatedStorage.Packages.knit)

local PotionService = Knit.CreateService({
	Name = "PotionService",
	Client = {},
})

local POTION_TYPES = { "Yen", "Mana", "Deposit" }
local TICK_INTERVAL = 1
local MAX_ACTIVE_BOOST_SECONDS = 24 * 60 * 60

local lastTickAt: { [Player]: number } = {}

local function getDurationSeconds(product: { DurationSeconds: number? }?): number
	if type(product) == "table" and type(product.DurationSeconds) == "number" then
		return math.max(math.floor(product.DurationSeconds), 1)
	end

	return PotionConfig.DurationSeconds
end

local function getMultiplier(potionType: string, product: { Multiplier: number? }?): number
	if type(product) == "table" and type(product.Multiplier) == "number" then
		return math.max(product.Multiplier, 1)
	end

	local typeConfig = PotionConfig.getTypeConfig(potionType)
	return if typeConfig then math.max(typeConfig.Multiplier, 1) else PotionConfig.DefaultMultiplier
end

local function snapshotActiveBoosts(activeBoosts: any): { [string]: { RemainingSeconds: number, Multiplier: number } }
	local nextBoosts = {}
	if type(activeBoosts) ~= "table" then
		return nextBoosts
	end

	for potionType, boost in activeBoosts do
		if type(boost) ~= "table" then
			continue
		end

		local remaining = math.clamp(math.floor(tonumber(boost.RemainingSeconds) or 0), 0, MAX_ACTIVE_BOOST_SECONDS)
		if remaining <= 0 then
			continue
		end

		nextBoosts[potionType] = {
			RemainingSeconds = remaining,
			Multiplier = math.max(tonumber(boost.Multiplier) or PotionConfig.DefaultMultiplier, 1),
		}
	end

	return nextBoosts
end

local function setActiveBoosts(PlayerDataService, player: Player, activeBoosts: any)
	PlayerDataService:Set(player, "ActivePotionBoosts", snapshotActiveBoosts(activeBoosts))
end

local function normalizeActiveBoosts(PlayerDataService, player: Player)
	local activeBoosts = PlayerDataService:Get(player, "ActivePotionBoosts")
	setActiveBoosts(PlayerDataService, player, activeBoosts)
end

local function tickPlayerPotions(PlayerDataService, player: Player, elapsedSeconds: number)
	if elapsedSeconds <= 0 then
		return
	end

	local activeBoosts = PlayerDataService:Get(player, "ActivePotionBoosts")
	if type(activeBoosts) ~= "table" then
		return
	end

	local nextBoosts = snapshotActiveBoosts(activeBoosts)
	local changed = false

	for potionType, boost in nextBoosts do
		local remaining = boost.RemainingSeconds
		local nextRemaining = math.max(remaining - elapsedSeconds, 0)
		if nextRemaining <= 0 then
			nextBoosts[potionType] = nil
			changed = true
		elseif nextRemaining ~= remaining then
			nextBoosts[potionType] = {
				RemainingSeconds = nextRemaining,
				Multiplier = boost.Multiplier,
			}
			changed = true
		end
	end

	if changed then
		PlayerDataService:Set(player, "ActivePotionBoosts", nextBoosts)
	end
end

function PotionService:AddPotions(player: Player, potionType: string, amount: number): boolean
	if not table.find(POTION_TYPES, potionType) then
		return false
	end

	local grantAmount = math.max(math.floor(tonumber(amount) or 0), 0)
	if grantAmount <= 0 then
		return false
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local currentAmount = math.max(math.floor(PlayerDataService:Get(player, { "Potions", potionType }) or 0), 0)
	PlayerDataService:Set(player, { "Potions", potionType }, currentAmount + grantAmount)
	return true
end

function PotionService:AddPotionsFromBundle(player: Player, amountPerType: number): boolean
	local grantAmount = math.max(math.floor(tonumber(amountPerType) or 0), 0)
	if grantAmount <= 0 then
		return false
	end

	for _, potionType in POTION_TYPES do
		self:AddPotions(player, potionType, grantAmount)
	end

	return true
end

function PotionService:UsePotion(player: Player, potionType: string): (boolean, string?)
	if not table.find(POTION_TYPES, potionType) then
		return false, "invalid_potion_type"
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local owned = math.max(math.floor(PlayerDataService:Get(player, { "Potions", potionType }) or 0), 0)
	if owned <= 0 then
		return false, "no_potions"
	end

	local typeConfig = PotionConfig.getTypeConfig(potionType)
	if not typeConfig then
		return false, "invalid_potion_type"
	end

	PlayerDataService:Set(player, { "Potions", potionType }, owned - 1)

	local activeBoosts = snapshotActiveBoosts(PlayerDataService:Get(player, "ActivePotionBoosts"))
	local currentBoost = activeBoosts[potionType]
	local remaining = if currentBoost then currentBoost.RemainingSeconds else 0

	activeBoosts[potionType] = {
		RemainingSeconds = math.min(remaining + PotionConfig.DurationSeconds, MAX_ACTIVE_BOOST_SECONDS),
		Multiplier = typeConfig.Multiplier,
	}
	PlayerDataService:Set(player, "ActivePotionBoosts", activeBoosts)
	lastTickAt[player] = os.clock()
	return true, nil
end

function PotionService:GetPotionMultiplier(player: Player, effectKey: string): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)
	normalizeActiveBoosts(PlayerDataService, player)

	local activeBoosts = PlayerDataService:Get(player, "ActivePotionBoosts")
	if type(activeBoosts) ~= "table" then
		return 1
	end

	local multiplier = 1
	for potionType, boost in activeBoosts do
		if type(boost) ~= "table" then
			continue
		end

		local remaining = math.max(math.floor(tonumber(boost.RemainingSeconds) or 0), 0)
		if remaining <= 0 then
			continue
		end

		local typeConfig = PotionConfig.getTypeConfig(potionType)
		if typeConfig and typeConfig.EffectKey == effectKey then
			multiplier *= math.max(tonumber(boost.Multiplier) or typeConfig.Multiplier or 2, 1)
		end
	end

	return multiplier
end

function PotionService:GetActiveBoostRemaining(player: Player, potionType: string): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:WaitForData(player)

	local activeBoosts = PlayerDataService:Get(player, "ActivePotionBoosts")
	if type(activeBoosts) ~= "table" then
		return 0
	end

	local boost = activeBoosts[potionType]
	if type(boost) ~= "table" then
		return 0
	end

	return math.max(math.floor(tonumber(boost.RemainingSeconds) or 0), 0)
end

function PotionService.Client:UsePotion(player: Player, potionType: string)
	return self.Server:UsePotion(player, potionType)
end

function PotionService:KnitStart()
	local PlayerDataService = Knit.GetService("PlayerDataService")

	Players.PlayerAdded:Connect(function(player)
		PlayerDataService:WaitForData(player)
		normalizeActiveBoosts(PlayerDataService, player)
		lastTickAt[player] = os.clock()
	end)

	Players.PlayerRemoving:Connect(function(player)
		local lastTick = lastTickAt[player]
		if lastTick then
			local elapsed = math.max(math.floor(os.clock() - lastTick), 0)
			if elapsed > 0 then
				tickPlayerPotions(PlayerDataService, player, elapsed)
			end
		end
		lastTickAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_INTERVAL)

			for _, player in Players:GetPlayers() do
				PlayerDataService:WaitForData(player)
				tickPlayerPotions(PlayerDataService, player, TICK_INTERVAL)
				lastTickAt[player] = os.clock()
			end
		end
	end)
end

return PotionService
