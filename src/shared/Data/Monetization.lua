local Monetization = {}

Monetization.DeveloperProducts = {
	Unit25 = {
		ProductId = 3601244927,
		Price = 7,
		Kind = "Units",
		Amount = 25,
	},
	Unit100 = {
		ProductId = 3601244889,
		Price = 19,
		Kind = "Units",
		Amount = 100,
	},
	Unit999 = {
		ProductId = 3601244855,
		Price = 79,
		Kind = "Units",
		Amount = 999,
	},
	Unit9999 = {
		ProductId = 3601244815,
		Price = 399,
		Kind = "Units",
		Amount = 9999,
	},
	-- Unit9999 = {
	-- 	ProductId = 3601588290,
	-- 	Price = 3999,
	-- 	Kind = "Units",
	-- 	Amount = 9999,
	-- },
	SellAll = {
		ProductId = 3601245342,
		Price = 19,
		Kind = "SellAll",
	},
	OpenCapsule = {
		ProductId = 3602659865,
		Price = 19,
		Kind = "OpenCapsule",
	},
	DoubleYen = {
		ProductId = 3601297598,
		Price = 5,
		Kind = "OneTimeEntitlement",
		EntitlementKey = "DoubleYen",
		DisplayName = "2x Yen",
	},
	StarterPack = {
		ProductId = 3602430060,
		Price = 39,
		Kind = "StarterPack",
		Units = {
			{ Tier = 4 },
		},
		Gamepasses = {
			"DoubleYen",
		},
		Yen = 100_000,
	},
	Offline5xReward = {
		ProductId = 3603441135,
		Price = 39,
		Kind = "Offline5xReward",
		Multiplier = 5,
	},
	GamepassBundle = {
		ProductId = 3603782477,
		Price = 549,
		Kind = "GamepassBundle",
		Amount = 1, -- each gamepass
	},

	--Potions

	PotionBundle = {
		ProductId = 3603781710,
		Price = 199,
		Kind = "PotionBundle",
		Amount = 10,
	},
	PotionYen = {
		ProductId = 3603781776,
		Price = 19,
		Kind = "PotionYen",
		PotionType = "Yen",
		Amount = 1,
		DurationSeconds = 15 * 60,
		Multiplier = 2,
	},
	PotionMana = {
		ProductId = 3603781798,
		Price = 19,
		Kind = "PotionMana",
		PotionType = "Mana",
		Amount = 1,
		DurationSeconds = 15 * 60,
		Multiplier = 2,
	},
	PotionDeposit = {
		ProductId = 3603781826,
		Price = 19,
		Kind = "PotionDeposit",
		PotionType = "Deposit",
		Amount = 1,
		DurationSeconds = 15 * 60,
		Multiplier = 2,
	},

	-- Gifts
	GiftPotionBundle = {
		ProductId = 3603664579,
		Price = 199,
		Kind = "GiftPotionBundle",
		Amount = 10, -- each potion
	},
	GiftAutoDeposit = {
		ProductId = 3603664479,
		Price = 79,
		Kind = "GiftAutoDeposit",
	},
	GiftAutoCollect = {
		ProductId = 3603664439,
		Price = 39,
		Kind = "GiftAutoCollect",
	},
	GiftDoubleYen = {
		ProductId = 3603664288,
		Price = 149,
		Kind = "GiftDoubleYen",
	},
	GiftDoubleDropSpeed = {
		ProductId = 3603664361,
		Price = 179,
		Kind = "GiftDoubleDropSpeed",
	},
	GiftDoubleMana = {
		ProductId = 3603664318,
		Price = 149,
		Kind = "GiftDoubleMana",
	},
	GiftDoubleDeposit = {
		ProductId = 3603664396,
		Price = 99,
		Kind = "GiftDoubleDeposit",
	},
	GiftStarterPack = {
		ProductId = 3603664256,
		Price = 39,
		Kind = "GiftStarterPack",
	},
	GiftGamepassBundle = {
		ProductId = 3603782504,
		Price = 549,
		Kind = "GiftGamepassBundle",
		Amount = 1, -- each gamepass
	},
}

Monetization.GamePasses = {
	DoubleDeposit = {
		PassId = 1862051990,
		Price = 99,
	},
	DoubleMana = {
		PassId = 1862912773,
		Price = 149,
	},
	DoubleYen = {
		PassId = 1860952285,
		Price = 149,
	},
	DoubleDropSpeed = {
		PassId = 1859927580,
		Price = 179,
	},
	AutoCollect = {
		PassId = 1862930826,
		Price = 39,
	},
	AutoDeposit = {
		PassId = 1862972802,
		Price = 79,
	},
}

Monetization.ProductsById = {}
for key, product in Monetization.DeveloperProducts do
	product.Key = key
	Monetization.ProductsById[product.ProductId] = product
end

function Monetization.getUnitProduct(amount: number)
	for _, product in Monetization.DeveloperProducts do
		if product.Kind == "Units" and product.Amount == amount then
			return product
		end
	end

	return nil
end

Monetization.ShopItems = {
	AutoCollect = { GamePass = "AutoCollect", Gift = "GiftAutoCollect" },
	AutoDeposit = { GamePass = "AutoDeposit", Gift = "GiftAutoDeposit" },
	DoubleCoins = { GamePass = "DoubleYen", Gift = "GiftDoubleYen" },
	DoubleYen = { GamePass = "DoubleYen", Gift = "GiftDoubleYen" },
	DoubleDepoSpeed = { GamePass = "DoubleDeposit", Gift = "GiftDoubleDeposit" },
	DoubleDeposit = { GamePass = "DoubleDeposit", Gift = "GiftDoubleDeposit" },
	DoubleDropSpeed = { GamePass = "DoubleDropSpeed", Gift = "GiftDoubleDropSpeed" },
	DoubleMana = { GamePass = "DoubleMana", Gift = "GiftDoubleMana" },
	StarterPack = { Product = "StarterPack", Gift = "GiftStarterPack" },
	PotionBundle = { Product = "PotionBundle", Gift = "GiftPotionBundle" },
	GamepassBundle = { Product = "GamepassBundle", Gift = "GiftGamepassBundle" },
}

Monetization.GiftTargets = {
	GiftAutoCollect = { Type = "GamePass", Key = "AutoCollect" },
	GiftAutoDeposit = { Type = "GamePass", Key = "AutoDeposit" },
	GiftDoubleYen = { Type = "GamePass", Key = "DoubleYen" },
	GiftDoubleDropSpeed = { Type = "GamePass", Key = "DoubleDropSpeed" },
	GiftDoubleMana = { Type = "GamePass", Key = "DoubleMana" },
	GiftDoubleDeposit = { Type = "GamePass", Key = "DoubleDeposit" },
	GiftStarterPack = { Type = "Product", Key = "StarterPack" },
	GiftPotionBundle = { Type = "PotionBundle" },
	GiftGamepassBundle = { Type = "GamepassBundle" },
}

Monetization.GiftProductByKey = {}
for key, product in Monetization.DeveloperProducts do
	if string.sub(key, 1, 4) == "Gift" then
		Monetization.GiftProductByKey[key] = product
	end
end

function Monetization.getGiftProductKeyFromKind(kind: string): string?
	for key, product in Monetization.DeveloperProducts do
		if product.Kind == kind then
			return key
		end
	end

	return nil
end

function Monetization.getAllGamePassKeys(): { string }
	local keys = {}
	for key in Monetization.GamePasses do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

return Monetization
