-- Tiny helpers for building interface instances in code.

local UI = {}

-- UI.new("TextLabel", { Text = "Hi", Parent = frame }, { UI.corner(8) })
function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UI.corner(radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function UI.stroke(color: Color3, thickness: number?, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(pixels: number): UIPadding
	local unit = UDim.new(0, pixels)
	return UI.new("UIPadding", { PaddingLeft = unit, PaddingRight = unit, PaddingTop = unit, PaddingBottom = unit })
end

function UI.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UI.new("TextLabel", defaults)
end

function UI.button(props: { [string]: any }): TextButton
	local defaults: { [string]: any } = {
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 18,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UI.new("TextButton", defaults, { UI.corner(10) })
end

return UI
