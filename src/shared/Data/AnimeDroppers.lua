local TycoonConfig = require(script.Parent.TycoonConfig)

local Tiers = {
	[1] = {
		ModelName = "Luffy",
		DisplayName = "Liffy",
		AnimeGroup = "Pirates",
		IconId = "rbxassetid://95938107469749",
		DropValue = 1,
		RequiredTier1 = 1,
		EstimatedTier1Cost = 5,
		MergeInto = 2,
	},
	[2] = {
		ModelName = "Tanjiro",
		DisplayName = "Tajiro",
		AnimeGroup = "Slayers",
		IconId = "rbxassetid://90326362320371",
		DropValue = 6,
		RequiredTier1 = 3,
		EstimatedTier1Cost = 30,
		MergeInto = 3,
	},
	[3] = {
		ModelName = "Naruto",
		DisplayName = "Noruta",
		AnimeGroup = "Ninja",
		IconId = "rbxassetid://79353333458716",
		DropValue = 28,
		RequiredTier1 = 9,
		EstimatedTier1Cost = 225,
		MergeInto = 4,
	},
	[4] = {
		ModelName = "Zenitsu",
		DisplayName = "Zentisa",
		AnimeGroup = "Slayers",
		IconId = "rbxassetid://109591741677037",
		DropValue = 135,
		RequiredTier1 = 27,
		EstimatedTier1Cost = 1890,
		MergeInto = 5,
	},
	[5] = {
		ModelName = "Zoro",
		DisplayName = "Zaro",
		AnimeGroup = "Pirates",
		IconId = "rbxassetid://81864711669175",
		DropValue = 490,
		RequiredTier1 = 81,
		EstimatedTier1Cost = 16605,
		MergeInto = 6,
	},
	[6] = {
		ModelName = "Denji",
		DisplayName = "Danji",
		AnimeGroup = "Hunters",
		IconId = "rbxassetid://89486841791029",
		DropValue = 2250,
		RequiredTier1 = 243,
		EstimatedTier1Cost = 148230,
		MergeInto = 7,
	},
	[7] = {
		ModelName = "Saitama",
		DisplayName = "Saikama",
		AnimeGroup = "One Punch",
		IconId = "rbxassetid://75376321796564",
		DropValue = 9960,
		RequiredTier1 = 729,
		EstimatedTier1Cost = 1330425,
		MergeInto = 8,
	},
	[8] = {
		ModelName = "Meliodas",
		DisplayName = "Meliados",
		AnimeGroup = "Sins",
		IconId = "rbxassetid://113520628907754",
		DropValue = 45647,
		RequiredTier1 = 2187,
		EstimatedTier1Cost = 11962890,
		MergeInto = 9,
	},
	[9] = {
		ModelName = "Deku",
		DisplayName = "Duke",
		AnimeGroup = "Heroes",
		IconId = "rbxassetid://104188303861136",
		DropValue = 211912,
		RequiredTier1 = 6561,
		EstimatedTier1Cost = 107633205,
		MergeInto = 10,
	},
	[10] = {
		ModelName = "Madara",
		DisplayName = "Midira",
		AnimeGroup = "Ninja",
		IconId = "rbxassetid://85526664824938",
		DropValue = 863604,
		RequiredTier1 = 19683,
		EstimatedTier1Cost = 968600430,
		MergeInto = 11,
	},
	[11] = {
		ModelName = "Megumi",
		DisplayName = "Meguma",
		AnimeGroup = "Sorcerers",
		IconId = "rbxassetid://83965792580462",
		DropValue = 2158760,
		RequiredTier1 = 39366,
		EstimatedTier1Cost = 3874303305,
		MergeInto = 12,
	},
	[12] = {
		ModelName = "Yuji",
		DisplayName = "Juyi",
		AnimeGroup = "Sorcerers",
		IconId = "rbxassetid://80336807101668",
		DropValue = 5288962,
		RequiredTier1 = 78732,
		EstimatedTier1Cost = 15497016390,
		MergeInto = 13,
	},
	[13] = {
		ModelName = "Rimuru",
		DisplayName = "Rumira",
		AnimeGroup = "Isekai",
		IconId = "rbxassetid://114826765552479",
		DropValue = 12693508,
		RequiredTier1 = 157464,
		EstimatedTier1Cost = 61987671900,
		MergeInto = 14,
	},
	[14] = {
		ModelName = "Killua",
		DisplayName = "Kullia",
		AnimeGroup = "Hunters",
		IconId = "rbxassetid://112624919123182",
		DropValue = 29195070,
		RequiredTier1 = 314928,
		EstimatedTier1Cost = 247949900280,
		MergeInto = 15,
	},
	[15] = {
		ModelName = "Sanji",
		DisplayName = "Jansi",
		AnimeGroup = "Pirates",
		IconId = "rbxassetid://77261310168633",
		DropValue = 67148661,
		RequiredTier1 = 629856,
		EstimatedTier1Cost = 991798026480,
		MergeInto = 16,
	},
	[16] = {
		ModelName = "Vegeta",
		DisplayName = "Vageta",
		AnimeGroup = "Saiyans",
		IconId = "rbxassetid://103694110031649",
		DropValue = 154441921,
		RequiredTier1 = 1259712,
		EstimatedTier1Cost = 3.96718895664e12,
		MergeInto = 17,
	},
	[17] = {
		ModelName = "Giyu",
		DisplayName = "Yigu",
		AnimeGroup = "Slayers",
		IconId = "rbxassetid://73644041899341",
		DropValue = 355216308,
		RequiredTier1 = 2519424,
		EstimatedTier1Cost = 1.5868749528e13,
		MergeInto = 18,
	},
	[18] = {
		ModelName = "Makima",
		DisplayName = "Mikama",
		AnimeGroup = "Hunters",
		IconId = "rbxassetid://117136473255872",
		DropValue = 836007723,
		RequiredTier1 = 5038848,
		EstimatedTier1Cost = 6.34749855149e13,
		MergeInto = 19,
	},
	[19] = {
		ModelName = "Mikasa",
		DisplayName = "Makisa",
		AnimeGroup = "Scouts",
		IconId = "rbxassetid://125234501254599",
		DropValue = 1904250223,
		RequiredTier1 = 10077696,
		EstimatedTier1Cost = 2.53899916865e14,
		MergeInto = 20,
	},
	[20] = {
		ModelName = "Gabimaru",
		DisplayName = "Gibamara",
		AnimeGroup = "Shinobi",
		IconId = "rbxassetid://139146857043514",
		DropValue = 4343748518,
		RequiredTier1 = 20155392,
		EstimatedTier1Cost = 1.01559961707e15,
		MergeInto = 21,
	},
	[21] = {
		ModelName = "Ban",
		DisplayName = "Ben",
		AnimeGroup = "Sins",
		IconId = "rbxassetid://70622283643922",
		DropValue = 10018002272,
		RequiredTier1 = 40310784,
		EstimatedTier1Cost = 4.06239836751e15,
		MergeInto = 22,
	},
	[22] = {
		ModelName = "Goku",
		DisplayName = "Guko",
		AnimeGroup = "Saiyans",
		IconId = "rbxassetid://114526172950539",
		DropValue = 24724006816,
		RequiredTier1 = 80621568,
		EstimatedTier1Cost = 1.62495932685e16,
		MergeInto = 23,
	},
	[23] = {
		ModelName = "Kokushibo",
		DisplayName = "Kikoshibo",
		AnimeGroup = "Slayers",
		IconId = "rbxassetid://92544163407156",
		DropValue = 551524910839,
		RequiredTier1 = 161243136,
		EstimatedTier1Cost = 6.49983726709e16,
		MergeInto = 24,
	},
	[24] = {
		ModelName = "Ichigo",
		DisplayName = "Ichagi",
		AnimeGroup = "Soul Reapers",
		IconId = "rbxassetid://79641026591513",
		DropValue = 126269750349,
		RequiredTier1 = 322486272,
		EstimatedTier1Cost = 2.59993489877e17,
		MergeInto = 25,
	},
	[25] = {
		ModelName = "Levi Ackerman",
		DisplayName = "Kaptain Live",
		AnimeGroup = "Scouts",
		IconId = "rbxassetid://123475869659213",
		DropValue = 280360269214,
		RequiredTier1 = 644972544,
		EstimatedTier1Cost = 1.0399739579e18,
		MergeInto = 26,
	},
	-- [26] = {
	-- 	ModelName = "Law",
	-- 	DisplayName = "Lawyer",
	-- 	AnimeGroup = "Pirates",
	-- 	IconId = "rbxassetid://136761379074773",
	-- 	DropValue = 2.28002921425e14,
	-- 	RequiredTier1 = 1289945088,
	-- 	EstimatedTier1Cost = 4.15989582836e18,
	-- 	MergeInto = 27,
	-- },
	-- [27] = {
	-- 	ModelName = "Shoto Todoroki",
	-- 	DisplayName = "Shotoriko",
	-- 	AnimeGroup = "Heroes",
	-- 	IconId = "rbxassetid://100730607428895",
	-- 	DropValue = 7.75209932845e14,
	-- 	RequiredTier1 = 2579890176,
	-- 	EstimatedTier1Cost = 1.6639583307e19,
	-- 	MergeInto = 28,
	-- },
	-- [28] = {
	-- 	ModelName = "Toji Fushiguro",
	-- 	DisplayName = "Tijo",
	-- 	AnimeGroup = "Sorcerers",
	-- 	IconId = "rbxassetid://120378945068145",
	-- 	DropValue = 2.63571377167e15,
	-- 	RequiredTier1 = 5159780352,
	-- 	EstimatedTier1Cost = 6.65583332151e19,
	-- 	MergeInto = 29,
	-- },
	-- [29] = {
	-- 	ModelName = "Asta",
	-- 	DisplayName = "Esta",
	-- 	AnimeGroup = "Magic Knights",
	-- 	IconId = "rbxassetid://74149124589958",
	-- 	DropValue = 8.96142682369e15,
	-- 	RequiredTier1 = 10319560704,
	-- 	EstimatedTier1Cost = 2.66233332835e20,
	-- 	MergeInto = 30,
	-- },
	-- [30] = {
	-- 	ModelName = "Genos",
	-- 	DisplayName = "Gones",
	-- 	AnimeGroup = "One Punch",
	-- 	IconId = "rbxassetid://132398113776714",
	-- 	DropValue = 3.04688512005e16,
	-- 	RequiredTier1 = 20639121408,
	-- 	EstimatedTier1Cost = 1.06493333129e21,
	-- 	MergeInto = 31,
	-- },
	-- [31] = {
	-- 	ModelName = "ChainSawMan",
	-- 	DisplayName = "Chainsaw Woman",
	-- 	AnimeGroup = "Hunters",
	-- 	IconId = "rbxassetid://129496625515571",
	-- 	DropValue = 1.03594094082e17,
	-- 	RequiredTier1 = 41278242816,
	-- 	EstimatedTier1Cost = 4.25973332504e21,
	-- 	MergeInto = 32,
	-- },
	-- [32] = {
	-- 	ModelName = "Itachi Uchiha",
	-- 	DisplayName = "Itai",
	-- 	AnimeGroup = "Ninja",
	-- 	IconId = "rbxassetid://98450967449427",
	-- 	DropValue = 3.52219919878e17,
	-- 	RequiredTier1 = 82556485632,
	-- 	EstimatedTier1Cost = 1.70389333e22,
	-- 	MergeInto = 33,
	-- },
	-- [33] = {
	-- 	ModelName = "Obito Uchiha",
	-- 	DisplayName = "Obita",
	-- 	AnimeGroup = "Ninja",
	-- 	IconId = "rbxassetid://139486061718773",
	-- 	DropValue = 1.19754772759e18,
	-- 	RequiredTier1 = 165112971264,
	-- 	EstimatedTier1Cost = 6.81557331995e22,
	-- 	MergeInto = 34,
	-- },
	-- [34] = {
	-- 	ModelName = "Ken Kaneki",
	-- 	DisplayName = "Kenaka",
	-- 	AnimeGroup = "Ghouls",
	-- 	IconId = "rbxassetid://111401581379139",
	-- 	DropValue = 4.07166227379e18,
	-- 	RequiredTier1 = 330225942528,
	-- 	EstimatedTier1Cost = 2.72622932797e23,
	-- 	MergeInto = 35,
	-- },
	-- [35] = {
	-- 	ModelName = "Sukuna",
	-- 	DisplayName = "Sakuna",
	-- 	AnimeGroup = "Sorcerers",
	-- 	IconId = "rbxassetid://135710906050148",
	-- 	DropValue = 1.38436517309e19,
	-- 	RequiredTier1 = 660451885056,
	-- 	EstimatedTier1Cost = 1.09049173119e24,
	-- 	MergeInto = 36,
	-- },
	-- [36] = {
	-- 	ModelName = "All Might",
	-- 	DisplayName = "Everything Might",
	-- 	AnimeGroup = "Heroes",
	-- 	IconId = "rbxassetid://136515468698054",
	-- 	DropValue = 5.05293288178e19,
	-- 	RequiredTier1 = 1.32090377011e12,
	-- 	EstimatedTier1Cost = 4.36196692474e24,
	-- 	MergeInto = 37,
	-- },
	-- [37] = {
	-- 	ModelName = "Gojo",
	-- 	DisplayName = "Jogo",
	-- 	AnimeGroup = "Sorcerers",
	-- 	IconId = "rbxassetid://127519749510891",
	-- 	DropValue = 1.84432050185e20,
	-- 	RequiredTier1 = 2.64180754022e12,
	-- 	EstimatedTier1Cost = 1.7447867699e25,
	-- 	MergeInto = 38,
	-- },
	-- [38] = {
	-- 	ModelName = "Cha Hae In",
	-- 	DisplayName = "Chahee",
	-- 	AnimeGroup = "Hunters",
	-- 	IconId = "rbxassetid://103653635822079",
	-- 	DropValue = 6.73176983175e20,
	-- 	RequiredTier1 = 5.28361508045e12,
	-- 	EstimatedTier1Cost = 6.97914707959e25,
	-- 	MergeInto = 39,
	-- },
	-- [39] = {
	-- 	ModelName = "Whitebeard",
	-- 	DisplayName = "White Mustache",
	-- 	AnimeGroup = "Pirates",
	-- 	IconId = "rbxassetid://80610034792001",
	-- 	DropValue = 2.45709598859e21,
	-- 	RequiredTier1 = 1.05672301609e13,
	-- 	EstimatedTier1Cost = 2.79165883183e26,
	-- 	MergeInto = 40,
	-- },
	-- [40] = {
	-- 	ModelName = "Sung Jin-woo",
	-- 	DisplayName = "Sing Jun-boo",
	-- 	AnimeGroup = "Hunters",
	-- 	IconId = "rbxassetid://133772096039716",
	-- 	DropValue = 8.96840035834e21,
	-- 	RequiredTier1 = 2.11344603218e13,
	-- 	EstimatedTier1Cost = 1.11666353273e27,
	-- 	MergeInto = 41,
	-- },
	-- [41] = {
	-- 	ModelName = "Escanor",
	-- 	DisplayName = "Esconar",
	-- 	AnimeGroup = "Sins",
	-- 	IconId = "rbxassetid://96543597921925",
	-- 	DropValue = 3.27346613079e22,
	-- 	RequiredTier1 = 4.22689206436e13,
	-- 	EstimatedTier1Cost = 4.46665413093e27,
	-- 	MergeInto = nil,
	-- },
}

local BalanceSettings = {
	TargetUnlockMinutes = {
		[2] = 1,
		[3] = 3,
		[4] = 5,
		[5] = 6,
		[6] = 10,
		[7] = 17,
		[8] = 31,
		[9] = 62,
		[10] = 126,
	},
	DropValueBase = 1,
	ThreeMergeDropValueGrowth = 4.5,
	TwoMergeDropValueGrowth = 2.8,
	LategameDropValueGrowth = 2.8,
	EndgameDropValueGrowth = 2.8,
}

local MergeSettings = {
	DefaultMergeRatio = 3,
	FromTier = 10,
	FromTierMergeRatio = 2,
}

local function getMergeRatio(tier: number): number
	tier = math.max(math.floor(tonumber(tier) or 1), 1)
	if tier >= (MergeSettings.FromTier or 10) then
		return MergeSettings.FromTierMergeRatio or 2
	end
	return MergeSettings.DefaultMergeRatio or 3
end

local function getRequiredTier1(tier: number): number
	tier = math.max(math.floor(tonumber(tier) or 1), 1)
	local required = 1
	for previousTier = 1, tier - 1 do
		required *= getMergeRatio(previousTier)
	end

	return required
end

local function getDropValueGrowth(tier: number): number
	if tier >= 36 then
		return BalanceSettings.EndgameDropValueGrowth or 2.8
	end

	if tier >= 26 then
		return BalanceSettings.LategameDropValueGrowth or 2.8
	end

	if tier >= (MergeSettings.FromTier or 10) + 1 then
		return BalanceSettings.TwoMergeDropValueGrowth or 2.8
	end

	return BalanceSettings.ThreeMergeDropValueGrowth or 4.5
end

local function getDropValue(tier: number): number
	tier = math.max(math.floor(tonumber(tier) or 1), 1)
	local tierData = Tiers[tier]
	return math.max(tonumber(tierData and tierData.DropValue) or BalanceSettings.DropValueBase or 1, 1)
end

for tier, tierData in Tiers do
	local requiredTier1 = getRequiredTier1(tier)
	local unitPriceBase = tonumber(TycoonConfig.UnitPriceBase) or 5
	local unitPriceIncrement = tonumber(TycoonConfig.UnitPriceIncrement) or 5

	tierData.RequiredTier1 = requiredTier1
	tierData.EstimatedTier1Cost =
		math.floor(requiredTier1 * unitPriceBase + unitPriceIncrement * requiredTier1 * (requiredTier1 - 1) / 2)
end

return {
	Tiers = Tiers,
	MaxTier = #Tiers,
	BalanceSettings = BalanceSettings,
	MergeSettings = MergeSettings,
	getMergeRatio = getMergeRatio,
	getRequiredTier1 = getRequiredTier1,
	getDropValueGrowth = getDropValueGrowth,
	getDropValue = getDropValue,
}
