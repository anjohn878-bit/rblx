--!strict
-- Shows a 3D model inside a ViewportFrame (used for seed and bird previews).

local Viewport = {}

function Viewport.mount(frame: ViewportFrame, model: Model, lookFrom: Vector3?)
	frame.BackgroundTransparency = 1
	frame.Ambient = Color3.fromRGB(190, 190, 195)
	frame.LightColor = Color3.fromRGB(255, 252, 240)
	frame.LightDirection = Vector3.new(-0.6, -1, -0.5)

	for _, child in frame:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	model.Parent = frame

	local center, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	-- distance at which the model's bounding sphere just fits the frame
	local radius = size.Magnitude / 2
	local distance = radius / math.sin(math.rad(camera.FieldOfView / 2)) * 0.92
	-- birds face -Z, so look from the -Z side to see their faces
	local direction = (lookFrom or Vector3.new(0.55, 0.25, -1)).Unit
	camera.CFrame = CFrame.lookAt(center.Position + direction * distance, center.Position)
	camera.Parent = frame
	frame.CurrentCamera = camera
end

return Viewport
