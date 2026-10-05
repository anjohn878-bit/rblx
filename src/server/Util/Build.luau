--[[
	Build
	Small helpers for creating anchored world geometry from code.
	Everything in the map is generated at runtime, so no models/assets are
	needed in the place file.
]]

export type PartProps = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CastShadow: boolean?,
	Shape: Enum.PartType?,
	Group: string?, -- collision group
}

local Build = {}

local function applyCommon(part: BasePart, props: PartProps)
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color or Color3.new(1, 1, 1)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	part.CanTouch = false
	if props.Group then
		part.CollisionGroup = props.Group
	end
	if props.Name then
		part.Name = props.Name
	end
end

function Build.Part(parent: Instance, props: PartProps): Part
	local part = Instance.new("Part")
	if props.Shape then
		part.Shape = props.Shape
	end
	applyCommon(part, props)
	part.Parent = parent
	return part
end

function Build.Wedge(parent: Instance, props: PartProps): WedgePart
	local part = Instance.new("WedgePart")
	applyCommon(part, props)
	part.Parent = parent
	return part
end

-- Vertical cylinder standing on `baseCFrame` (its centre at the bottom face).
function Build.Cylinder(parent: Instance, baseCFrame: CFrame, height: number, diameter: number, props: { [string]: any }?): Part
	local p = props or {}
	return Build.Part(parent, {
		Name = p.Name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = baseCFrame * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = p.Color,
		Material = p.Material,
		Transparency = p.Transparency,
		CanCollide = p.CanCollide,
		CastShadow = p.CastShadow,
		Group = p.Group,
	})
end

function Build.Ball(parent: Instance, center: CFrame, diameter: number, props: { [string]: any }?): Part
	local p = props or {}
	return Build.Part(parent, {
		Name = p.Name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = center,
		Color = p.Color,
		Material = p.Material,
		Transparency = p.Transparency,
		CanCollide = p.CanCollide,
		CastShadow = p.CastShadow,
		Group = p.Group,
	})
end

function Build.Model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Build.Folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

export type TextOptions = {
	Face: Enum.NormalId?,
	TextColor: Color3?,
	Background: Color3?,
	BackgroundTransparency: number?,
	Font: Enum.Font?,
	PixelsPerStud: number?,
	StrokeColor: Color3?,
	RichText: boolean?,
	Name: string?,
}

-- Puts a scaled TextLabel on one face of a part.
function Build.SurfaceText(part: BasePart, text: string, options: TextOptions?): TextLabel
	local opts: TextOptions = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = opts.Name or "SurfaceText"
	gui.Face = opts.Face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 30
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = opts.Background or Color3.new(1, 1, 1)
	label.BackgroundTransparency = if opts.BackgroundTransparency == nil then 1 else opts.BackgroundTransparency
	label.Text = text
	label.TextScaled = true
	label.RichText = opts.RichText or false
	label.Font = opts.Font or Enum.Font.FredokaOne
	label.TextColor3 = opts.TextColor or Color3.new(1, 1, 1)
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label

	if opts.StrokeColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = opts.StrokeColor
		stroke.Thickness = 2
		stroke.Parent = label
	end

	gui.Parent = part
	return label
end

return Build
