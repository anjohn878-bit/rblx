-- Client-only markers for the player's deliveries: a glowing beacon you can see across town, a
-- ring on the doorstep, and the "Deliver Package" prompt. Everything here is created locally,
-- so other players never see your markers, and it works with streaming because it only needs
-- positions from the server, not the houses themselves.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = require(script.Parent.UI)

local Waypoints = {}

export type Target = {
	JobId: number?,
	Title: string,
	Position: Vector3,
	Color: Color3,
	Deadline: number?,
}

type Marker = {
	Ring: BasePart,
	Beacon: BasePart,
	Label: TextLabel,
	Billboard: BillboardGui,
	Prompt: ProximityPrompt?,
}

local DEPOT_MARKER_DISTANCE = 40

local player = Players.LocalPlayer
local folder = Instance.new("Folder")
folder.Name = "DeliveryMarkers"
folder.Parent = Workspace

local markers: { [number]: Marker } = {}
local depotMarker: Marker? = nil
local jobs = {}
local depotPosition: Vector3? = nil
local selectedJobId: number? = nil
local seated = false

local function kindColor(kindId: string): Color3
	for _, kind in Config.PackageKinds do
		if kind.Id == kindId then
			return kind.Color
		end
	end
	return Config.Colors.Brand
end

local function jobTitle(job): string
	return job.Name or job.Address
end

local function makeMarker(position: Vector3, color: Color3, title: string): Marker
	local ground = position - Vector3.new(0, 2.9, 0)
	local ring = UI.new("Part", {
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 6, 6),
		CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = folder,
	})
	local beacon = UI.new("Part", {
		Name = "Beacon",
		Size = Vector3.new(1.2, 300, 1.2),
		CFrame = CFrame.new(ground + Vector3.new(0, 150, 0)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = folder,
	})
	local label = UI.label({
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Text = title,
	})
	local billboard = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(220, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 9, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 100000,
		Adornee = ring,
		Parent = ring,
	}, { label })
	return { Ring = ring, Beacon = beacon, Label = label, Billboard = billboard, Prompt = nil }
end

local function destroyMarker(marker: Marker)
	marker.Ring:Destroy()
	marker.Beacon:Destroy()
end

local function addPrompt(marker: Marker, job)
	local attachment = Instance.new("Attachment")
	attachment.Parent = marker.Ring
	attachment.WorldPosition = job.Position
	local prompt = UI.new("ProximityPrompt", {
		ActionText = "Deliver Package",
		ObjectText = jobTitle(job),
		HoldDuration = 0.25,
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
		Enabled = not seated,
		Parent = attachment,
	})
	prompt.Triggered:Connect(function()
		Remotes.DeliverPackage:FireServer(job.Id)
	end)
	marker.Prompt = prompt
end

local function characterPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The job the HUD arrow points at: the one the player picked, otherwise the nearest.
local function currentJob()
	if selectedJobId then
		for _, job in jobs do
			if job.Id == selectedJobId then
				return job
			end
		end
		selectedJobId = nil
	end
	local origin = characterPosition()
	local best, bestDistance = nil, math.huge
	for _, job in jobs do
		local distance = if origin then flatDistance(origin, job.Position) else 0
		if distance < bestDistance then
			best, bestDistance = job, distance
		end
	end
	return best
end

function Waypoints.getTarget(): Target?
	local job = currentJob()
	if job then
		return {
			JobId = job.Id,
			Title = jobTitle(job),
			Position = job.Position,
			Color = kindColor(job.Kind),
			Deadline = job.Deadline,
		}
	end
	if depotPosition then
		return { Title = "the depot counter", Position = depotPosition, Color = Config.Colors.Brand }
	end
	return nil
end

function Waypoints.select(jobId: number?)
	selectedJobId = jobId
end

function Waypoints.selectedId(): number?
	local job = currentJob()
	return job and job.Id
end

function Waypoints.update(state)
	jobs = state.Jobs
	depotPosition = state.Depot

	local alive = {}
	for _, job in jobs do
		alive[job.Id] = true
		if not markers[job.Id] then
			local marker = makeMarker(job.Position, kindColor(job.Kind), jobTitle(job))
			addPrompt(marker, job)
			markers[job.Id] = marker
		end
	end
	for id, marker in markers do
		if not alive[id] then
			destroyMarker(marker)
			markers[id] = nil
		end
	end

	if #jobs == 0 and depotPosition and not depotMarker then
		depotMarker = makeMarker(depotPosition, Config.Colors.Brand, "Load packages here")
	elseif #jobs > 0 and depotMarker then
		destroyMarker(depotMarker)
		depotMarker = nil
	end
end

-- Called every frame: emphasise the current target and refresh distance labels.
function Waypoints.tick()
	local origin = characterPosition()
	local target = currentJob()
	for id, marker in markers do
		local isTarget = target ~= nil and target.Id == id
		marker.Beacon.Transparency = if isTarget then 0.45 else 0.82
		marker.Billboard.Enabled = isTarget
		if isTarget and origin then
			marker.Label.Text = string.format("%s\n%s", jobTitle(target), Format.distance(flatDistance(origin, target.Position)))
		end
	end
	if depotMarker then
		local near = origin ~= nil and depotPosition ~= nil and flatDistance(origin, depotPosition) < DEPOT_MARKER_DISTANCE
		depotMarker.Beacon.Transparency = if near then 1 else 0.45
		depotMarker.Ring.Transparency = if near then 1 else 0.35
		depotMarker.Billboard.Enabled = not near
	end
end

local function setSeated(value: boolean)
	seated = value
	for _, marker in markers do
		if marker.Prompt then
			marker.Prompt.Enabled = not value
		end
	end
end

-- A burst of sparkles and a ping when a parcel is handed over.
function Waypoints.celebrate(position: Vector3?)
	local sound = UI.new("Sound", {
		SoundId = "rbxasset://sounds/electronicpingshort.wav",
		Volume = 0.6,
		Parent = SoundService,
	})
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 3)
	if typeof(position) ~= "Vector3" then
		return
	end
	local holder = UI.new("Part", {
		Size = Vector3.one,
		Position = position,
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = folder,
	})
	local emitter = UI.new("ParticleEmitter", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Config.Colors.Brand),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 230, 120)),
			ColorSequenceKeypoint.new(1, Config.Colors.Money),
		}),
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(18, 30),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -40, 0),
		Rate = 0,
		LightEmission = 0.6,
		Parent = holder,
	})
	emitter:Emit(45)
	Debris:AddItem(holder, 3)
end

function Waypoints.init()
	local function onCharacter(character: Model)
		setSeated(false)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Seated:Connect(function(active)
			setSeated(active)
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return Waypoints
