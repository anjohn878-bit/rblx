-- Helpers for building things out of parts.

local Parts = {}

local UP_CYLINDER = CFrame.Angles(0, 0, math.rad(90))

function Parts.new(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

-- A cylinder standing upright. cf is the centre of the cylinder.
function Parts.cylinder(
	parent: Instance,
	cf: CFrame,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Parts.new(
		parent,
		cf * UP_CYLINDER,
		Vector3.new(height, diameter, diameter),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- A cylinder lying along the part's Z axis (for rails and rods).
function Parts.rod(
	parent: Instance,
	cf: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Parts.new(
		parent,
		cf * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(length, diameter, diameter),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

function Parts.ball(parent: Instance, cf: CFrame, diameter: number, color: Color3, material: Enum.Material?): Part
	return Parts.new(parent, cf, Vector3.new(diameter, diameter, diameter), color, material, Enum.PartType.Ball)
end

-- Turn off collisions for decorations people should walk through.
function Parts.noCollide(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

export type TextOptions = {
	color: Color3?,
	stroke: Color3?,
	font: Enum.Font?,
	background: Color3?,
	pixelsPerStud: number?,
}

-- Writes text on one face of a part. Returns the TextLabel so it can be changed later.
function Parts.surfaceText(part: BasePart, face: Enum.NormalId, text: string, options: TextOptions?): TextLabel
	local opts: TextOptions = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.pixelsPerStud or 40
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if opts.background then 0 else 1
	label.BackgroundColor3 = opts.background or Color3.new(1, 1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = opts.font or Enum.Font.FredokaOne
	label.TextColor3 = opts.color or Color3.new(1, 1, 1)
	label.TextStrokeColor3 = opts.stroke or Color3.fromRGB(120, 20, 80)
	label.TextStrokeTransparency = if opts.stroke == nil then 1 else 0
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label
	return label
end

-- A floating label that always faces the camera. Size is in studs.
function Parts.billboard(
	adornee: BasePart,
	offset: Vector3,
	width: number,
	height: number,
	text: string,
	color: Color3?,
	maxDistance: number?
): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 80
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(90, 20, 70)
	label.Parent = gui
	return gui, label
end

function Parts.light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	return light
end

return Parts
