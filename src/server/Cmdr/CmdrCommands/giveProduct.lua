return {
	Name = "giveProduct",
	Aliases = { "giveproduct", "grantproduct" },
	Description = "Grant a developer product reward to a player (units, 2x Yen, sell all, etc.).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "player", Description = "Target player" },
		{ Type = "productKey", Name = "productKey", Description = "Product key from Monetization config" },
	},
}
