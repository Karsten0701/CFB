-- Patched copy of Cmdr AutoComplete (nil-safe string.find for suggestions).
-- Replaces ReplicatedStorage.CmdrClient.CmdrInterface.AutoComplete on the server at boot.

local Players = game:GetService("Players")
local Player = Players.LocalPlayer

return function(Cmdr)
	local AutoComplete = {
		Items = {},
		ItemOptions = {},
		SelectedItem = 0,
	}

	local Util = Cmdr.Util

	local Gui = Player:WaitForChild("PlayerGui"):WaitForChild("Cmdr"):WaitForChild("Autocomplete")
	local AutoItem = Gui:WaitForChild("TextButton")
	local Title = Gui:WaitForChild("Title")
	local Description = Gui:WaitForChild("Description")
	local Entry = Gui.Parent:WaitForChild("Frame"):WaitForChild("Entry")
	AutoItem.Parent = nil

	local defaultBarThickness = Gui.ScrollBarThickness

	local function SetText(obj, textObj, text, sizeFromContents)
		obj.Visible = text ~= nil
		textObj.Text = text or ""

		if sizeFromContents then
			textObj.Size = UDim2.new(
				0,
				Util.GetTextSize(text or "", textObj, Vector2.new(1000, 1000), 1, 0).X,
				obj.Size.Y.Scale,
				obj.Size.Y.Offset
			)
		end
	end

	local function UpdateContainerSize()
		Gui.Size = UDim2.new(
			0,
			math.max(Title.Field.TextBounds.X + Title.Field.Type.TextBounds.X, Gui.Size.X.Offset),
			0,
			math.min(Gui.UIListLayout.AbsoluteContentSize.Y, Gui.Parent.AbsoluteSize.Y - Gui.AbsolutePosition.Y - 10)
		)
	end

	local function UpdateInfoDisplay(options)
		SetText(Title, Title.Field, options.name, true)
		SetText(
			Title.Field.Type,
			Title.Field.Type,
			options.type and ": " .. options.type:sub(1, 1):upper() .. options.type:sub(2)
		)
		SetText(Description, Description.Label, options.description)

		Description.Label.TextColor3 = options.invalid and Color3.fromRGB(255, 73, 73) or Color3.fromRGB(255, 255, 255)
		Description.Size = UDim2.new(1, 0, 0, 40)

		while not Description.Label.TextFits do
			Description.Size = Description.Size + UDim2.new(0, 0, 0, 2)
			if Description.Size.Y.Offset > 500 then
				break
			end
		end

		task.wait()
		Gui.UIListLayout:ApplyLayout()
		UpdateContainerSize()
		Gui.ScrollBarThickness = defaultBarThickness
	end

	function AutoComplete:Show(items, options)
		options = options or {}

		for _, item in pairs(self.Items) do
			if item.gui then
				item.gui:Destroy()
			end
		end

		self.SelectedItem = 1
		self.Items = items
		self.Prefix = options.prefix or ""
		self.LastItem = options.isLast or false
		self.Command = options.command
		self.Arg = options.arg
		self.NumArgs = options.numArgs
		self.IsPartial = options.isPartial

		local autocompleteWidth = 200
		Gui.ScrollBarThickness = 0

		for i, item in pairs(self.Items) do
			local leftText = tostring(item[1] or "")
			local rightText = tostring(item[2] or "")

			local btn = AutoItem:Clone()
			btn.Name = leftText .. rightText
			btn.BackgroundTransparency = i == self.SelectedItem and 0.5 or 1

			local start, stop = string.find(rightText:lower(), leftText:lower(), 1, true)
			if start == nil then
				start, stop = 1, #rightText
			end

			btn.Typed.Text = string.rep(" ", start - 1) .. leftText
			btn.Suggest.Text = string.sub(rightText, 0, start - 1)
				.. string.rep(" ", #leftText)
				.. string.sub(rightText, stop + 1)

			btn.Parent = Gui
			btn.LayoutOrder = i

			local maxBounds = math.max(btn.Typed.TextBounds.X, btn.Suggest.TextBounds.X) + 20
			if maxBounds > autocompleteWidth then
				autocompleteWidth = maxBounds
			end

			item.gui = btn
		end

		Gui.UIListLayout:ApplyLayout()

		local text = Entry.TextBox.Text
		local words = Util.SplitString(text)
		if text:sub(#text, #text) == " " and not options.at then
			words[#words + 1] = "e"
		end
		table.remove(words, #words)
		local extra = (options.at and options.at or (#table.concat(words, " ") + 1)) * 7

		Gui.Position =
			UDim2.new(0, Entry.TextBox.AbsolutePosition.X - 10 + extra, 0, Entry.TextBox.AbsolutePosition.Y + 30)
		Gui.Size = UDim2.new(0, autocompleteWidth, 0, Gui.UIListLayout.AbsoluteContentSize.Y)
		Gui.Visible = true

		UpdateInfoDisplay(self.Items[1] and self.Items[1].options or options)
	end

	function AutoComplete:GetSelectedItem()
		if Gui.Visible == false then
			return nil
		end

		return AutoComplete.Items[AutoComplete.SelectedItem]
	end

	function AutoComplete:Hide()
		Gui.Visible = false
	end

	function AutoComplete:IsVisible()
		return Gui.Visible
	end

	function AutoComplete:Select(delta)
		if not Gui.Visible then
			return
		end

		self.SelectedItem = self.SelectedItem + delta

		if self.SelectedItem > #self.Items then
			self.SelectedItem = 1
		elseif self.SelectedItem < 1 then
			self.SelectedItem = #self.Items
		end

		for i, item in pairs(self.Items) do
			item.gui.BackgroundTransparency = i == self.SelectedItem and 0.5 or 1
		end

		Gui.CanvasPosition = Vector2.new(
			0,
			math.max(
				0,
				Title.Size.Y.Offset
					+ Description.Size.Y.Offset
					+ self.SelectedItem * AutoItem.Size.Y.Offset
					- Gui.Size.Y.Offset
			)
		)

		if self.Items[self.SelectedItem] and self.Items[self.SelectedItem].options then
			UpdateInfoDisplay(self.Items[self.SelectedItem].options or {})
		end
	end

	Gui.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateContainerSize)

	return AutoComplete
end
