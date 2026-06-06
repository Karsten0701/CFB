local Monetization = {}

Monetization.DeveloperProducts = {
	Unit5 = {
		ProductId = 3601244927,
		Price = 9,
		Kind = "Units",
		Amount = 5,
	},
	Unit25 = {
		ProductId = 3601244889,
		Price = 39,
		Kind = "Units",
		Amount = 25,
	},
	Unit100 = {
		ProductId = 3601244855,
		Price = 119,
		Kind = "Units",
		Amount = 100,
	},
	Unit999 = {
		ProductId = 3601244815,
		Price = 699,
		Kind = "Units",
		Amount = 999,
	},
	Unit9999 = {
		ProductId = 3601588290,
		Price = 3999,
		Kind = "Units",
		Amount = 9999,
	},
	SellAll = {
		ProductId = 3601245342,
		Price = 19,
		Kind = "SellAll",
	},
	OpenCapsule = {
		ProductId = 3602659865,
		Price = 39,
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
		Price = 79,
		Kind = "StarterPack",
		Units = {
			{ Tier = 4 },
		},
		Gamepasses = {
			"DoubleYen",
		},
		Yen = 10000,
	},
}

Monetization.GamePasses = {
	DoubleDeposit = {
		PassId = 0, --1862051990,
		Price = 249,
	},
	DoubleMana = {
		PassId = 0, --1862912773,
		Price = 199,
	},
	DoubleYen = {
		PassId = 0, --1860952285,
		Price = 249,
	},
	DoubleDropSpeed = {
		PassId = 0, --1859927580,
		Price = 249,
	},
	AutoCollect = {
		PassId = 0, --1862930826,
		Price = 49,
	},
	AutoDeposit = {
		PassId = 0, --1862972802,
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

return Monetization
