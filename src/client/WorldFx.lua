-- Client-side world polish: hides other players' prompts, highlights the soil
-- you're about to plant in, flaps bird wings, updates growth timers and shows
-- floating "+coins" text.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared.Birds)
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local Store = require(script.Parent.Store)

local WorldFx = {}

local localPlayer = Players.LocalPlayer

------------------------------------------------------------------------------
-- Only show prompts for your own garden

local function filterPrompt(prompt)
	local owner = prompt:GetAttribute("OwnerUserId")
	if owner and owner ~= localPlayer.UserId then
		prompt.Enabled = false
	end
end

local function setupPromptFilter()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			filterPrompt(descendant)
		end
	end
	workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			filterPrompt(descendant)
		end
	end)
end

------------------------------------------------------------------------------
-- Highlight the soil tile a prompt belongs to

local function setupTileHighlight()
	local boxes = {}
	local colors = {
		PlantPrompt = Color3.fromRGB(120, 255, 100),
		DigPrompt = Color3.fromRGB(255, 160, 60),
	}
	for name, color in pairs(colors) do
		local box = Instance.new("SelectionBox")
		box.Name = name .. "Highlight"
		box.Color3 = color
		box.SurfaceColor3 = color
		box.SurfaceTransparency = 0.75
		box.LineThickness = 0.08
		box.Parent = workspace.CurrentCamera
		boxes[name] = box
	end

	ProximityPromptService.PromptShown:Connect(function(prompt)
		local box = boxes[prompt.Name]
		if box and prompt:GetAttribute("TileIndex") and prompt.Parent and prompt.Parent:IsA("BasePart") then
			box.Adornee = prompt.Parent
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		local box = boxes[prompt.Name]
		if box and box.Adornee == prompt.Parent then
			box.Adornee = nil
		end
	end)
end

------------------------------------------------------------------------------
-- Bird animation (wings flap, heads look around)

local animated = {} -- [Model] = animation state

local function tryTrack(model)
	if animated[model] then
		return true
	end
	local function joint(partName, jointName)
		local part = model:FindFirstChild(partName)
		return part and part:FindFirstChild(jointName)
	end
	local left, right = joint("LeftWing", "Hinge"), joint("RightWing", "Hinge")
	if not (left and right) then
		return false
	end
	local neck = joint("Head", "Neck")
	animated[model] = {
		Left = left,
		LeftBase = left.C0,
		Right = right,
		RightBase = right.C0,
		Neck = neck,
		NeckBase = neck and neck.C0,
		Phase = math.random() * math.pi * 2,
		Yaw = 0,
		Pitch = 0,
		TargetYaw = 0,
		TargetPitch = 0,
		NextLook = 0,
	}
	return true
end

local function track(model)
	if tryTrack(model) then
		return
	end
	-- parts may still be streaming in
	local connection
	connection = model.DescendantAdded:Connect(function()
		if tryTrack(model) or not model.Parent then
			connection:Disconnect()
		end
	end)
end

local function setupBirdAnimation()
	for _, model in ipairs(CollectionService:GetTagged("BirdGardenBird")) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal("BirdGardenBird"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("BirdGardenBird"):Connect(function(model)
		animated[model] = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for model, anim in pairs(animated) do
			if not model.Parent or not anim.Left.Parent then
				animated[model] = nil
				continue
			end
			local hover = model:GetAttribute("Hover")
			local flying = model:GetAttribute("Flying")
			local raise
			if flying or hover then
				local speed = hover and 45 or 16
				raise = math.rad(30 + 50 * math.sin(t * speed + anim.Phase))
			else
				-- every so often, a quick ruffle of the wings
				local ruffle = math.max(0, math.sin(t * 1.1 + anim.Phase) - 0.96) * 25
				raise = math.rad(ruffle * 40)
			end
			anim.Left.C0 = anim.LeftBase * CFrame.Angles(0, 0, -raise)
			anim.Right.C0 = anim.RightBase * CFrame.Angles(0, 0, raise)

			if anim.Neck and anim.Neck.Parent then
				if t >= anim.NextLook then
					local perched = not flying
					anim.TargetYaw = perched and (math.random() - 0.5) * 1.6 or 0
					anim.TargetPitch = perched and (math.random() - 0.5) * 0.5 or 0
					anim.NextLook = t + 0.5 + math.random() * 2.5
				end
				local blend = math.min(1, dt * 12)
				anim.Yaw += (anim.TargetYaw - anim.Yaw) * blend
				anim.Pitch += (anim.TargetPitch - anim.Pitch) * blend
				anim.Neck.C0 = anim.NeckBase * CFrame.Angles(anim.Pitch, anim.Yaw, 0)
			end
		end
	end)
end

------------------------------------------------------------------------------
-- Growth timers above plants and "leaving in" timers above birds

local function updatePlantLabels(now)
	for _, model in ipairs(CollectionService:GetTagged("BirdGardenPlant")) do
		local root = model.PrimaryPart
		local gui = root and root:FindFirstChild("PlantStatus")
		local status = gui and gui:FindFirstChild("Status")
		local bar = gui and gui:FindFirstChild("Bar")
		local fill = bar and bar:FindFirstChild("Fill")
		if status and fill then
			local stage = model:GetAttribute("Stage") or 1
			if stage >= 4 then
				status.Text = model:GetAttribute("HasBird") and "🐦 A bird is visiting!" or "🌸 Attracting birds"
				bar.Visible = false
			else
				local plantedAt = model:GetAttribute("PlantedAt") or now
				local growTime = model:GetAttribute("GrowTime") or 1
				local remaining = plantedAt + growTime - now
				status.Text = remaining > 0 and ("⏳ " .. Util.FormatTime(remaining)) or "Almost ready..."
				fill.Size = UDim2.fromScale(math.clamp(1 - remaining / growTime, 0, 1), 1)
				bar.Visible = true
			end
		end
	end
end

local function updateBirdLabels(now)
	for _, model in ipairs(CollectionService:GetTagged("BirdGardenBird")) do
		local leavesAt = model:GetAttribute("LeavesAt")
		local def = Birds.Get(model:GetAttribute("BirdId") or "")
		local body = model.PrimaryPart
		local tag = body and body:FindFirstChild("BirdTag")
		local info = tag and tag:FindFirstChild("Info")
		if info and def then
			if leavesAt then
				info.Text = def.Rarity .. "  •  leaves in " .. Util.FormatTime(leavesAt - now)
			else
				info.Text = def.Rarity
			end
		end
	end
end

local function setupLabels()
	task.spawn(function()
		while true do
			local now = Store.Now()
			updatePlantLabels(now)
			updateBirdLabels(now)
			task.wait(0.25)
		end
	end)
end

------------------------------------------------------------------------------
-- Floating text

local function showFloatingText(position, text, color)
	if typeof(position) ~= "Vector3" or type(text) ~= "string" then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "FloatingText"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace.CurrentCamera

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Parent = gui

	local info = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.5)
end

------------------------------------------------------------------------------

function WorldFx.Init()
	setupPromptFilter()
	setupTileHighlight()
	setupBirdAnimation()
	setupLabels()
	Net.Effect.OnClientEvent:Connect(showFloatingText)
end

return WorldFx
