-- Spawns each player's delivery vehicle, keeps strangers out of it, and runs the garage shop.
--
-- Vehicles are "arcade" style: one invisible chassis part carries a LinearVelocity (forward
-- speed, no sideways slip) and an AngularVelocity (steering and staying upright). The driver's
-- client sets both every frame (see client/Driving.luau); while parked the server's values of
-- zero hold the vehicle still.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CityBuilder = require(script.Parent.CityBuilder)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VehicleModels = require(ReplicatedStorage.Shared.VehicleModels)
local PlayerData = require(script.Parent.PlayerData)

local Vehicles = {}

local CHASSIS_MASS = 40
local DRIVER_MASS_ALLOWANCE = 15
local ROAD_TOP = 0.05
local SPAWN_LIFT = 0.4

local registry
local folder: Folder
local active: { [Player]: Model } = {}

local function setOwner(part: BasePart, player: Player?)
	-- Fails harmlessly if the part was destroyed or anchored in the meantime.
	pcall(part.SetNetworkOwner, part, player)
end

local function getHumanoid(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

-- Put a character down beside the vehicle's driver door.
local function placeBeside(model: Model, character: Model)
	local chassis = model.PrimaryPart
	local seat = model:FindFirstChild("DriverSeat") :: BasePart?
	if not chassis or not seat then
		return
	end
	local halfWidth = model:GetExtentsSize().X / 2
	local seatOffset = chassis.CFrame:PointToObjectSpace(seat.Position)
	local spot = chassis.CFrame * CFrame.new(-(halfWidth + 2.5), 0, seatOffset.Z)
	local look = chassis.CFrame.LookVector
	character:PivotTo(CFrame.lookAt(spot.Position + Vector3.new(0, 2, 0), spot.Position + Vector3.new(look.X, 2, look.Z)))
end

local function addNameplate(chassis: BasePart, height: number, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(220, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.5, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	gui.Parent = chassis
end

-- Turn a freshly built (anchored, local-space) model into a drivable vehicle owned by `owner`.
local function rig(model: Model, info: Config.VehicleInfo, owner: Player)
	local chassis = model.PrimaryPart :: BasePart
	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = Config.CollisionGroups.Vehicles
			if part ~= chassis then
				part.Massless = true
				-- Near-frictionless contacts: the constraints do the driving, not the tyres.
				part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = chassis
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end

	local volume = chassis.Size.X * chassis.Size.Y * chassis.Size.Z
	chassis.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(CHASSIS_MASS / volume, 0.01, 100), 0, 0, 100, 1)
	chassis.RootPriority = 127

	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = chassis

	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.new(0, 0, -1) -- forward
	drive.SecondaryTangentAxis = Vector3.new(1, 0, 0) -- sideways (held at zero: no drifting)
	drive.PlaneVelocity = Vector2.zero
	drive.MaxForce = (CHASSIS_MASS + DRIVER_MASS_ALLOWANCE) * 160
	drive.Parent = chassis

	local steer = Instance.new("AngularVelocity")
	steer.Name = "Steer"
	steer.Attachment0 = attachment
	steer.RelativeTo = Enum.ActuatorRelativeTo.World
	steer.AngularVelocity = Vector3.zero
	steer.MaxTorque = 60000
	steer.Parent = chassis

	-- Only the Drive prompt (or spawning) seats you, so walking through a car never grabs you.
	seat.CanTouch = false
	seat:SetAttribute("DeliveryVehicle", true)
	seat:SetAttribute("TopSpeed", info.TopSpeed)
	seat:SetAttribute("Acceleration", info.Acceleration)
	seat:SetAttribute("TurnRate", info.TurnRate)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model.Name = owner.Name .. "_" .. info.Id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local extents = model:GetExtentsSize()
	addNameplate(chassis, extents.Y, owner.DisplayName .. "'s " .. info.Name)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = info.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = math.max(10, extents.X / 2 + 6)
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Parent = seat

	prompt.Triggered:Connect(function(player)
		if player ~= owner then
			PlayerData.notify(player, "That's " .. owner.DisplayName .. "'s vehicle.", "error")
			return
		end
		local humanoid = getHumanoid(player)
		if humanoid and not seat.Occupant then
			seat:Sit(humanoid)
		end
	end)

	local driver: Humanoid? = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		if humanoid then
			local rider = Players:GetPlayerFromCharacter(humanoid.Parent)
			if rider ~= owner then
				local weld = seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
				task.defer(placeBeside, model, humanoid.Parent :: Model)
				if rider then
					PlayerData.notify(rider, "That's " .. owner.DisplayName .. "'s vehicle.", "error")
				end
				return
			end
			driver = humanoid
			prompt.Enabled = false
			setOwner(chassis, owner)
		else
			prompt.Enabled = true
			setOwner(chassis, nil)
			local leaving = driver
			driver = nil
			if leaving and leaving.Parent and leaving.Health > 0 then
				task.defer(placeBeside, model, leaving.Parent :: Model)
			end
		end
	end)
end

-- Is there room for a vehicle of `size` at `cf` (ground-level pivot)?
local function isClear(cf: CFrame, size: Vector3): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local parts = Workspace:GetPartBoundsInBox(cf * CFrame.new(0, size.Y / 2, 0), size + Vector3.new(2, 0, 2), params)
	return #parts == 0
end

local function nearestRoadLine(value: number): number
	local k = math.floor((value + Config.City.Extent) / Config.City.CellSize + 0.5)
	return CityBuilder.roadLine(math.clamp(k, 0, Config.City.BlocksPerSide))
end

-- Pick a spot in the right-hand lane of the road closest to `position`.
local function roadSpot(position: Vector3, size: Vector3): CFrame?
	local extent = Config.City.Extent
	local lane = Config.City.LaneOffset
	local lineX = nearestRoadLine(position.X)
	local lineZ = nearestRoadLine(position.Z)
	local base, step, facing
	if math.abs(position.X - lineX) <= math.abs(position.Z - lineZ) then
		-- North-south road. The east lane heads north, the west lane heads south.
		local side = if position.X >= lineX then 1 else -1
		base = Vector3.new(lineX + side * lane, ROAD_TOP + SPAWN_LIFT, math.clamp(position.Z, -extent, extent))
		step = Vector3.new(0, 0, 1)
		facing = Vector3.new(0, 0, -side)
	else
		-- East-west road. The south lane heads east, the north lane heads west.
		local side = if position.Z >= lineZ then 1 else -1
		base = Vector3.new(math.clamp(position.X, -extent, extent), ROAD_TOP + SPAWN_LIFT, lineZ + side * lane)
		step = Vector3.new(1, 0, 0)
		facing = Vector3.new(side, 0, 0)
	end
	for i = 0, 8 do
		for _, direction in { 1, -1 } do
			local spot = base + step * direction * i * (size.Z + 4)
			local cf = CFrame.lookAt(spot, spot + facing)
			if isClear(cf, size) then
				return cf
			end
		end
	end
	return nil
end

local function findSpawn(position: Vector3, size: Vector3): CFrame?
	local bounds = registry.Depot.Bounds
	local inDepot = position.X > bounds.Min.X
		and position.X < bounds.Max.X
		and position.Z > bounds.Min.Z
		and position.Z < bounds.Max.Z
	if inDepot then
		for _, spot in registry.Depot.ParkingSpots do
			local cf = spot + Vector3.new(0, SPAWN_LIFT, 0)
			if isClear(cf, size) then
				return cf
			end
		end
	end
	return roadSpot(position, size)
end

function Vehicles.despawn(player: Player)
	local model = active[player]
	active[player] = nil
	if model then
		model:Destroy()
	end
end

function Vehicles.spawn(player: Player)
	local session = PlayerData.get(player)
	if not session then
		return
	end
	local humanoid, root = getHumanoid(player)
	if not humanoid or not root then
		return
	end
	if os.clock() - session.LastSpawn < Config.VehicleSpawnCooldown then
		PlayerData.notify(player, "Your vehicle is on its way, hang on a second.", "error")
		return
	end
	session.LastSpawn = os.clock()

	local info = Config.getVehicle(session.Data.Equipped) or Config.Vehicles[1]
	if humanoid.SeatPart then
		humanoid.Sit = false
	end
	Vehicles.despawn(player)

	local model = VehicleModels.build(info.Id)
	local size = model:GetExtentsSize()
	local cf = findSpawn(root.Position, size)
	if not cf then
		model:Destroy()
		PlayerData.notify(player, "No room to park here. Try somewhere else.", "error")
		return
	end

	rig(model, info, player)
	model:PivotTo(cf)
	model.Parent = folder
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	local chassis = model.PrimaryPart :: BasePart
	setOwner(chassis, nil)

	active[player] = model
	chassis.AncestryChanged:Connect(function()
		-- Fell off the world or was otherwise destroyed.
		if active[player] == model and not chassis:IsDescendantOf(Workspace) then
			Vehicles.despawn(player)
		end
	end)

	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat
	local character = player.Character :: Model
	character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	seat:Sit(humanoid)
end

local function buy(player: Player, id: any): (boolean, string)
	local session = PlayerData.get(player)
	local info = if typeof(id) == "string" then Config.getVehicle(id) else nil
	if not session or not info then
		return false, "Unknown vehicle."
	end
	if session.Data.Owned[info.Id] then
		return false, "You already own this."
	end
	if PlayerData.rankIndex(session) < info.Rank then
		return false, "Reach " .. Config.Ranks[info.Rank].Name .. " rank first."
	end
	if session.Data.Cash < info.Price then
		return false, "You need " .. Format.money(info.Price - session.Data.Cash) .. " more."
	end
	session.Data.Cash -= info.Price
	session.Data.Owned[info.Id] = true
	session.Data.Equipped = info.Id
	PlayerData.changed(session)
	PlayerData.notify(player, "You bought the " .. info.Name .. "!", "success")
	return true, "Purchased"
end

local function equip(player: Player, id: any): (boolean, string)
	local session = PlayerData.get(player)
	if not session or typeof(id) ~= "string" or not session.Data.Owned[id] then
		return false, "You don't own that vehicle."
	end
	session.Data.Equipped = id
	PlayerData.changed(session)
	return true, "Equipped"
end

function Vehicles.init(cityRegistry)
	registry = cityRegistry

	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = Workspace

	registry.Depot.SpawnPrompt.Triggered:Connect(Vehicles.spawn)
	registry.Depot.ShopPrompt.Triggered:Connect(function(player)
		Remotes.OpenShop:FireClient(player)
	end)
	Remotes.SpawnVehicle.OnServerEvent:Connect(Vehicles.spawn)
	Remotes.BuyVehicle.OnServerInvoke = buy
	Remotes.EquipVehicle.OnServerInvoke = equip

	Players.PlayerRemoving:Connect(Vehicles.despawn)
end

return Vehicles
