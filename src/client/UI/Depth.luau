--!strict
-- The "depth stack" every panel/button gets: blue-shifted drop shadow, top-lift
-- gradient, one outline thickness everywhere, rounded corners.
-- Scale formula MUST match tools/ui/uikit.py ui_scale().
--
-- Structure (children always draw above their parent, so layers are siblings):
--   Node (transparent, laid out by its parent; TextButton for buttons)
--     _Shadow  ZIndex 1, shifted down
--     _Face    ZIndex 2, gradient + stroke
--     _Text    ZIndex 3 (buttons/panels with text)
--     Content  ZIndex 3, padding + list layout + real children
local Depth = {}

local REF_HEIGHT, MIN_SCALE, MAX_SCALE = 1080, 0.55, 1.25

function Depth.scale(viewportHeight: number): number
	return math.clamp(viewportHeight / REF_HEIGHT, MIN_SCALE, MAX_SCALE)
end

export type Theme = {
	stroke: number,
	strokeColor: Color3,
	corner: number,
	shadowOffset: number,
	shadowTint: Color3,
	lift: number,
	text: Color3,
	textStroke: Color3,
	font: Enum.Font,
}

local function layer(name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	return f
end

function Depth.with(theme: Theme)
	local api = {}

	function api.styleText(label: TextLabel | TextButton, s: number)
		label.Font = theme.font
		label.TextColor3 = theme.text
		label.TextStrokeTransparency = 1
		label.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Thickness = math.max(1, math.floor(2 * s + 0.5))
		stroke.Color = theme.textStroke
		stroke.Parent = label
	end

	-- Adds shadow/face layers to `node`; returns the Content frame children go into.
	function api.apply(node: GuiObject, base: Color3, s: number): Frame
		node.BackgroundTransparency = 1
		local radius = UDim.new(0, math.floor(theme.corner * s + 0.5))

		local shadow = layer("_Shadow", 1)
		shadow.BackgroundColor3 = base:Lerp(theme.shadowTint, 0.75)
		shadow.Position = UDim2.fromOffset(0, math.max(1, math.floor(theme.shadowOffset * s + 0.5)))
		local sc = Instance.new("UICorner")
		sc.CornerRadius = radius
		sc.Parent = shadow
		shadow.Parent = node

		local face = layer("_Face", 2)
		face.BackgroundColor3 = Color3.new(1, 1, 1)
		local fc = Instance.new("UICorner")
		fc.CornerRadius = radius
		fc.Parent = face
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = math.max(1, math.floor(theme.stroke * s + 0.5))
		stroke.Color = theme.strokeColor
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = face
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), theme.lift), base)
		gradient.Rotation = 90
		gradient.Parent = face
		face.Parent = node

		local content = layer("Content", 3)
		content.BackgroundTransparency = 1
		content.Parent = node
		return content
	end

	function api.text(
		node: GuiObject,
		text: string,
		size: number,
		align: Enum.TextXAlignment,
		s: number
	): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = "_Text"
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 3
		label.Text = text
		label.TextSize = math.floor(size * s + 0.5)
		label.TextXAlignment = align
		api.styleText(label, s)
		label.Parent = node
		return label
	end

	function api.aspect(obj: GuiObject, ratio: number)
		local c = Instance.new("UIAspectRatioConstraint")
		c.AspectRatio = ratio
		c.DominantAxis = Enum.DominantAxis.Width
		c.Parent = obj
	end

	function api.pad(obj: GuiObject, px: number)
		local p = Instance.new("UIPadding")
		local u = UDim.new(0, px)
		p.PaddingTop, p.PaddingBottom, p.PaddingLeft, p.PaddingRight = u, u, u, u
		p.Parent = obj
	end

	function api.list(obj: GuiObject, dir: string, gap: number, align: string)
		local l = Instance.new("UIListLayout")
		l.FillDirection = if dir == "x" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		l.Padding = UDim.new(0, gap)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		local centerX = dir == "y" or align == "center"
		local centerY = dir == "x" or align == "center"
		l.HorizontalAlignment = if centerX
			then Enum.HorizontalAlignment.Center
			else Enum.HorizontalAlignment.Left
		l.VerticalAlignment = if centerY then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top
		l.Parent = obj
	end

	return api
end

return Depth
