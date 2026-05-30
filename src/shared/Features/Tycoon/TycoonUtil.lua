local TycoonConfig = require(script.Parent.Parent.Parent.Data.TycoonConfig)

local TycoonUtil = {}

function TycoonUtil.getTycoonsFolder(): Folder?
	local current: Instance = workspace
	for _, childName in TycoonConfig.TycoonsPath do
		local nextChild = current:FindFirstChild(childName)
		if not nextChild then
			return nil
		end
		current = nextChild
	end

	return if current:IsA("Folder") then current else nil
end

function TycoonUtil.getTycoonByName(name: string): Instance?
	local tycoonsFolder = TycoonUtil.getTycoonsFolder()
	if not tycoonsFolder then
		return nil
	end

	return tycoonsFolder:FindFirstChild(name)
end

function TycoonUtil.getPlayerTycoon(player: Player, tycoonName: string): Instance?
	local tycoon = TycoonUtil.getTycoonByName(tycoonName)
	if not tycoon then
		return nil
	end

	if tycoon:GetAttribute("Owner") ~= player.UserId then
		return nil
	end

	return tycoon
end

function TycoonUtil.parseBuyAmount(modelName: string): number?
	local amount = string.match(modelName, "^" .. TycoonConfig.BuyButtonPrefix .. "(%d+)$")
	if amount then
		return tonumber(amount)
	end

	return nil
end

function TycoonUtil.parseRateAmount(modelName: string): number?
	local amount = string.match(modelName, "^" .. TycoonConfig.RateButtonPrefix .. "(%d+)$")
	if amount then
		local parsedAmount = tonumber(amount)
		if parsedAmount == 2 then
			return 10
		end

		return parsedAmount
	end

	return nil
end

local function getPositiveNumberAttribute(instance: Instance, attributeName: string): number?
	local value = instance:GetAttribute(attributeName)
	if type(value) == "number" and value > 0 then
		return value
	end

	return nil
end

local function getPositiveNumberButtonAttribute(buttonModel: Instance, attributeName: string): number?
	local value = getPositiveNumberAttribute(buttonModel, attributeName)
	if value then
		return value
	end

	local head = buttonModel:FindFirstChild("Head", true)
	if head then
		return getPositiveNumberAttribute(head, attributeName)
	end

	return nil
end

local function getBooleanButtonAttribute(buttonModel: Instance, attributeName: string): boolean
	if buttonModel:GetAttribute(attributeName) == true then
		return true
	end

	local head = buttonModel:FindFirstChild("Head", true)
	return head ~= nil and head:GetAttribute(attributeName) == true
end

function TycoonUtil.getBuyAmount(buttonModel: Instance): number?
	return getPositiveNumberButtonAttribute(buttonModel, "UnitBuy")
		or TycoonUtil.parseBuyAmount(buttonModel.Name)
end

function TycoonUtil.getRobuxBuyAmount(buttonModel: Instance): number?
	local nameAmount = tonumber(string.match(buttonModel.Name, "^BuyRobux(%d+)$"))
	if not getBooleanButtonAttribute(buttonModel, "RobuxBuy") and not nameAmount then
		return nil
	end

	return nameAmount
		or getPositiveNumberButtonAttribute(buttonModel, "UnitBuy")
end

function TycoonUtil.getRateAmount(buttonModel: Instance): number?
	return getPositiveNumberButtonAttribute(buttonModel, "RateBuy")
		or getPositiveNumberButtonAttribute(buttonModel, "RateUpgrade")
		or TycoonUtil.parseRateAmount(buttonModel.Name)
end

function TycoonUtil.isDepositButton(buttonModel: Instance): boolean
	local lowerName = string.lower(buttonModel.Name)

	return getBooleanButtonAttribute(buttonModel, "DepositButton")
		or lowerName == "deposit"
		or lowerName == "depositbutton"
		or string.match(lowerName, "^deposit") ~= nil
end

function TycoonUtil.isMergeButton(buttonModel: Instance): boolean
	local lowerName = string.lower(buttonModel.Name)

	return getBooleanButtonAttribute(buttonModel, "MergeButton")
		or lowerName == "merge"
		or lowerName == "mergebutton"
		or lowerName == "mergeunits"
		or string.match(lowerName, "^merge") ~= nil
end

function TycoonUtil.isSellAllButton(buttonModel: Instance): boolean
	local lowerName = string.lower(buttonModel.Name)

	return getBooleanButtonAttribute(buttonModel, "SellAll")
		or getBooleanButtonAttribute(buttonModel, "SellAllButton")
		or lowerName == "sellall"
		or lowerName == "sellallbutton"
end

function TycoonUtil.teleportToSpawn(player: Player, tycoon: Instance)
	local spawnPart = tycoon:FindFirstChild("Spawn")
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
end

function TycoonUtil.isNearButton(player: Player, buttonModel: Instance, maxDistance: number?): boolean
	maxDistance = maxDistance or 12

	local character = player.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local head = buttonModel:FindFirstChild("Head", true)
	if not head or not head:IsA("BasePart") then
		return false
	end

	return (root.Position - head.Position).Magnitude <= maxDistance
end

return TycoonUtil
