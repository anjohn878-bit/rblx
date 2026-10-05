-- Shows a 3D model inside a ViewportFrame (used for shop and journal pictures).

local Viewport = {}

-- direction: where the camera sits relative to the model's centre
function Viewport.Show(frame, model, direction)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Ambient = Color3.fromRGB(170, 170, 170)
	frame.LightColor = Color3.fromRGB(255, 250, 235)
	frame.LightDirection = Vector3.new(-1, -1.5, -1)

	model.Parent = frame
	local boxCf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 0.95
	local center = boxCf.Position
	camera.CFrame = CFrame.lookAt(center + direction.Unit * distance, center)
	return camera
end

return Viewport
