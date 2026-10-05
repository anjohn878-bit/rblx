--!strict
-- Small helpers so the interface can be built in code without a wall of boilerplate.

local Ui = {}

Ui.COLORS = {
	bg = Color3.fromRGB(28, 48, 40),
	panel = Color3.fromRGB(42, 70, 58),
	panelLight = Color3.fromRGB(58, 94, 78),
	row = Color3.fromRGB(36, 60, 50),
	text = Color3.fromRGB(246, 250, 242),
	muted = Color3.fromRGB(176, 202, 186),
	gold = Color3.fromRGB(255, 208, 82),
	good = Color3.fromRGB(104, 208, 116),
	bad = Color3.fromRGB(236, 96, 96),
	disabled = Color3.fromRGB(86, 100, 92),
}

Ui.FONT = Enum.Font.FredokaOne
Ui.FONT_BODY = Enum.Font.GothamMedium
Ui.FONT_BOLD = Enum.Font.GothamBold

-- Instance.new + properties + children in one call. `Parent` is applied last.
function Ui.new(className: string, props: { [string]: any }?, children: any?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children :: { Instance } do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- (these return `any` so they can be mixed freely in a children list)
function Ui.corner(radius: number): any
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Ui.stroke(color: Color3, thickness: number, transparency: number?): any
	return Ui.new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.padding(px: number): any
	return Ui.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function Ui.label(props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Ui.FONT_BODY,
		TextColor3 = Ui.COLORS.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = "",
	}
	for k, v in props do
		merged[k] = v
	end
	return Ui.new("TextLabel", merged)
end

function Ui.button(props: { [string]: any }): TextButton
	local merged: { [string]: any } = {
		AutoButtonColor = true,
		BackgroundColor3 = Ui.COLORS.panelLight,
		Font = Ui.FONT,
		TextColor3 = Ui.COLORS.text,
		TextSize = 18,
		Text = "",
	}
	for k, v in props do
		merged[k] = v
	end
	local button = Ui.new("TextButton", merged)
	Ui.corner(10).Parent = button
	return button
end

-- Dims and disables a button (and restores it) based on `enabled`.
function Ui.setEnabled(button: TextButton, enabled: boolean, enabledColor: Color3)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then enabledColor else Ui.COLORS.disabled
	button.TextTransparency = if enabled then 0 else 0.4
end

return Ui
