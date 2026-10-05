--[[
	Colours and fonts shared by every piece of UI, so the whole game looks like one product.
]]

local Theme = {
	-- Surfaces
	Navy = Color3.fromRGB(16, 22, 42),
	NavyLight = Color3.fromRGB(30, 40, 70),
	NavyLighter = Color3.fromRGB(46, 60, 100),

	-- Accents
	Orange = Color3.fromRGB(255, 159, 28),
	OrangeDark = Color3.fromRGB(214, 120, 0),
	Green = Color3.fromRGB(84, 224, 128),
	Red = Color3.fromRGB(255, 92, 100),
	Yellow = Color3.fromRGB(255, 214, 84),
	Blue = Color3.fromRGB(96, 176, 255),

	-- Text
	Text = Color3.fromRGB(244, 247, 255),
	TextDim = Color3.fromRGB(160, 172, 204),

	-- Fonts
	FontBold = Enum.Font.GothamBold,
	FontMedium = Enum.Font.GothamMedium,
	FontRegular = Enum.Font.Gotham,

	-- Toast colours by kind
	Kinds = {
		info = Color3.fromRGB(96, 176, 255),
		success = Color3.fromRGB(84, 224, 128),
		warn = Color3.fromRGB(255, 214, 84),
		error = Color3.fromRGB(255, 92, 100),
	},
}

return Theme
