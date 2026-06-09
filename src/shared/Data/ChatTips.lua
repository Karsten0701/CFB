local ChatTips = {}

ChatTips.IntervalSeconds = 180
ChatTips.InitialDelaySeconds = 30
ChatTips.PrefixColor = "#FFD966"
ChatTips.MessageColor = "#D9ECFF"

ChatTips.Tips = {
	"When you are offline you keep earning Yen, so make sure to come back!",
	"Rebirthing resets your progress but gives you upgrades and boosts!",
	"Climb the leaderboards and compete against other players!",
	"Make sure to like the game and join the group for free rewards!",
	"Upgrade your Tycoon and Units to earn yen faster!",
	"Open capsules for powerful Units that speed up your progress!",
	"Check the shop for gamepasses and boosts that multiply your earnings!",
	"Events can give temporary multipliers, so keep an eye on the timer!",
}

local function escapeRichText(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

function ChatTips.formatMessage(message: string): string
	return string.format(
		'<font color="%s"><b>[TIP]</b></font> <font color="%s">%s</font>',
		ChatTips.PrefixColor,
		ChatTips.MessageColor,
		escapeRichText(message)
	)
end

return ChatTips
