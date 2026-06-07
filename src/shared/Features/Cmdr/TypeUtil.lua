local TypeUtil = {}

function TypeUtil.filterAutocomplete(items: { string }, text: string?): { string }
	text = string.lower(text or "")
	if text == "" then
		return items
	end

	local matches = {}
	for _, item in ipairs(items) do
		if string.find(string.lower(item), text, 1, true) then
			table.insert(matches, item)
		end
	end

	return matches
end

return TypeUtil
