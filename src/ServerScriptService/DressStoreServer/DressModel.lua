-- Builds a little dress out of parts. The model's pivot is the top of the dress
-- (the hanger hook), and the dress hangs straight down from it.
-- The dress is wide along Z and thin along X.

local Parts = require(script.Parent.Parts)

local DressModel = {}

local METAL = Color3.fromRGB(200, 200, 210)

export type Options = {
	scale: number?,
	hanger: boolean?, -- draw the coat hanger (default true)
	material: Enum.Material?, -- override the fabric
	color: Color3?, -- override the dress colour
}

function DressModel.build(dress, options: Options?): Model
	local opts: Options = options or {}
	local s = opts.scale or 1
	local color = opts.color or dress.color
	local material = opts.material or dress.material or Enum.Material.Fabric
	local showHanger = opts.hanger ~= false

	local model = Instance.new("Model")
	model.Name = dress.name

	local root = Parts.new(model, CFrame.new(), Vector3.new(0.2, 0.2, 0.2) * s, color)
	root.Name = "Root"
	root.Transparency = 1
	model.PrimaryPart = root

	if showHanger then
		Parts.new(model, CFrame.new(0, -0.2 * s, 0), Vector3.new(0.08, 0.4, 0.08) * s, METAL, Enum.Material.Metal)
		Parts.new(model, CFrame.new(0, -0.45 * s, 0), Vector3.new(0.1, 0.1, 1.3) * s, METAL, Enum.Material.Metal)
	end

	local firstTier = dress.tiers[1]
	local bodiceWidth = firstTier[2] * 0.9

	-- Bodice (top of the dress) and two thin straps
	Parts.new(model, CFrame.new(0, -1.0 * s, 0), Vector3.new(0.55, 1.0, bodiceWidth) * s, color, material)
	for _, side in { -1, 1 } do
		Parts.new(
			model,
			CFrame.new(0, -0.55 * s, side * bodiceWidth * 0.32 * s),
			Vector3.new(0.5, 0.25, 0.12) * s,
			color,
			material
		)
	end

	-- Belt / sash
	Parts.cylinder(model, CFrame.new(0, -1.55 * s, 0), 0.14 * s, firstTier[2] * 0.85 * s, dress.accent, material)

	-- Skirt made of tiers that get wider towards the bottom
	local y = -1.62
	local lowest: Part? = nil
	for _, tier in dress.tiers do
		local height, diameter = tier[1], tier[2]
		lowest = Parts.cylinder(model, CFrame.new(0, (y - height / 2) * s, 0), height * s, diameter * s, color, material)
		y -= height
	end

	-- A ribbon trim around the hem
	local lastTier = dress.tiers[#dress.tiers]
	Parts.cylinder(model, CFrame.new(0, (y + 0.06) * s, 0), 0.12 * s, (lastTier[2] + 0.04) * s, dress.accent, material)

	if dress.sparkles and lowest then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = dress.sparkles
		sparkles.Parent = lowest
	end

	Parts.noCollide(model)
	return model
end

-- How far below the pivot the hem of the dress is (in studs, at scale 1).
function DressModel.length(dress): number
	local y = 1.62
	for _, tier in dress.tiers do
		y += tier[1]
	end
	return y
end

return DressModel
