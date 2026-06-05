local FormatUtil = {}

local COMPACT_THRESHOLD = 100_000_000
local SUFFIXES = {
	{ Value = 1e54, Suffix = "SpDe" },
	{ Value = 1e51, Suffix = "SxDe" },
	{ Value = 1e48, Suffix = "QiDe" },
	{ Value = 1e45, Suffix = "QaDe" },
	{ Value = 1e42, Suffix = "TDe" },
	{ Value = 1e39, Suffix = "DDe" },
	{ Value = 1e36, Suffix = "UDe" },
	{ Value = 1e33, Suffix = "De" },
	{ Value = 1e30, Suffix = "No" },
	{ Value = 1e27, Suffix = "Oc" },
	{ Value = 1e24, Suffix = "Sp" },
	{ Value = 1e21, Suffix = "Sx" },
	{ Value = 1e18, Suffix = "Qi" },
	{ Value = 1e15, Suffix = "Qa" },
	{ Value = 1e12, Suffix = "T" },
	{ Value = 1e9, Suffix = "B" },
	{ Value = 1e6, Suffix = "M" },
}

local function addThousandsSeparators(numberText: string): string
	local formatted = numberText
	while true do
		local nextFormatted, replacements = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = nextFormatted
		if replacements == 0 then
			break
		end
	end

	return formatted
end

local function trimTrailingZeroDecimal(numberText: string): string
	return string.gsub(numberText, "%.0$", "")
end

function FormatUtil.formatNumber(value: number): string
	if value ~= value then
		return "0"
	end

	local absValue = math.abs(value)
	if absValue == math.huge then
		return if value > 0 then "Inf" else "-Inf"
	end

	if absValue >= COMPACT_THRESHOLD then
		for _, suffixInfo in SUFFIXES do
			if absValue >= suffixInfo.Value then
				return trimTrailingZeroDecimal(string.format("%.1f", value / suffixInfo.Value)) .. suffixInfo.Suffix
			end
		end
	end

	if value == math.floor(value) then
		return addThousandsSeparators(tostring(value))
	end

	return addThousandsSeparators(trimTrailingZeroDecimal(string.format("%.1f", value)))
end

function FormatUtil.formatMana(value: number): string
	return FormatUtil.formatNumber(value) .. " Mana"
end

function FormatUtil.formatRoundedInteger(value: number): string
	if type(value) ~= "number" or value ~= value then
		return "0"
	end

	if value == math.huge then
		return "Inf"
	elseif value == -math.huge then
		return "-Inf"
	end

	local rounded = math.floor(value + 0.5)
	if math.abs(rounded) >= COMPACT_THRESHOLD then
		return FormatUtil.formatNumber(rounded)
	end

	return addThousandsSeparators(tostring(rounded))
end

function FormatUtil.formatRoundedMana(value: number): string
	return FormatUtil.formatRoundedInteger(value) .. " Mana"
end

function FormatUtil.formatSeconds(value: number): string
	if type(value) ~= "number" or value ~= value then
		return "0s"
	end

	local rounded = math.floor(value * 100 + 0.5) / 100
	local text = string.format("%.2f", rounded)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text .. "s"
end

function FormatUtil.formatRate(value: number): string
	return FormatUtil.formatNumber(value) .. "/1s"
end

return FormatUtil
