local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonPressVFX = {}

local templateAttachment: Attachment? = nil

local function getTemplateAttachment(): Attachment?
	if templateAttachment and templateAttachment.Parent then
		return templateAttachment
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local buttonPress = assets and assets:FindFirstChild("ButtonPress")
	if not buttonPress then
		return nil
	end

	local main = buttonPress:FindFirstChild("Main", true)
	if not main or not main:IsA("Attachment") then
		return nil
	end

	templateAttachment = main
	return templateAttachment
end

local function getMaxLifetime(attachment: Attachment): number
	local maxLifetime = 1
	for _, descendant in attachment:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			maxLifetime = math.max(maxLifetime, descendant.Lifetime.Max)
		end
	end

	return maxLifetime
end

function ButtonPressVFX.play(head: BasePart, color: Color3)
	local template = getTemplateAttachment()
	if not template then
		return
	end

	local attachment = template:Clone()
	attachment.Parent = head
	attachment.Position = Vector3.new(0, head.Size.Y * 0.15, 0)
	attachment.Orientation = Vector3.new(0, 0, 0)

	local maxLifetime = getMaxLifetime(attachment)
	for _, descendant in attachment:GetDescendants() do
		if not descendant:IsA("ParticleEmitter") then
			continue
		end

		descendant.Color = ColorSequence.new(color)

		local emitCount = descendant:GetAttribute("EmitCount")
		if type(emitCount) == "number" and emitCount > 0 then
			descendant:Emit(emitCount)
		else
			descendant:Emit(1)
		end
	end

	task.delay(maxLifetime + 0.1, function()
		if attachment.Parent then
			attachment:Destroy()
		end
	end)
end

return ButtonPressVFX
