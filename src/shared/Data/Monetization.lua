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
	SellAll = {
		ProductId = 3601245342,
		Price = 19,
		Kind = "SellAll",
	},
}

Monetization.GamePasses = {
	DoubleDeposit = {
		PassId = 1862051990,
		Price = 249,
	},
	DoubleManaPower = {
		PassId = 1862912773,
		Price = 199,
	},
	DoubleYen = {
		PassId = 1860952285,
		Price = 249,
	},
	AutoCollect = {
		PassId = 1862930826,
		Price = 99,
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

return Monetization
