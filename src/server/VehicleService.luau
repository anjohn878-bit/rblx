--[[
	Spawns, parks and cleans up each player's delivery vehicle.

	One vehicle per player. It is parked (anchored) whenever nobody is driving, which keeps
	empty cars from drifting around. Sitting in it unanchors it and hands physics ownership to
	the driver, whose VehicleController script then drives it (see client/VehicleController).

	Vehicles and characters are in separate collision groups that don't collide, so cars can't
	fling players and a parked car never blocks anyone on foot.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VehicleBuilder = require(ReplicatedStorage.Shared.VehicleBuilder)
local PlayerService = require(script.Parent.PlayerService)

local VehicleService = {}

local VEHICLE_TAG = "DeliveryVehicle"
local GROUP_VEHICLES = "Vehicles"
local GROUP_CHARACTERS = "Characters"
local VOID_Y = -60
local RESIT_DELAY = 1.5 -- seconds a seat refuses touch-sitting after the driver gets out

local vehiclesFolder: Folder
local vehicles = {} -- [Player] = { Model, Chassis, Seat, Id }
local lastSummon = {} -- [Player] = os.clock()

-- Collision groups --------------------------------------------------------------------

local function setupCollisionGroups()
	local ok, err = pcall(function()
		for _, name in { GROUP_VEHICLES, GROUP_CHARACTERS } do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(GROUP_VEHICLES, GROUP_CHARACTERS, false)
	end)
	if not ok then
		warn("[DeliveryDriver] Could not set up collision groups: " .. tostring(err))
	end
end

local function putCharacterInGroup(character: Model)
	local function apply(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = GROUP_CHARACTERS
		end
	end
	for _, descendant in character:GetDescendants() do
		apply(descendant)
	end
	character.DescendantAdded:Connect(apply)
end

-- Parking / driving ---------------------------------------------------------------------

local function ejectOccupant(entry, humanoid: Humanoid)
	local weld = entry.Seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	humanoid.Jump = true
end

local function onOccupantChanged(player: Player, entry)
	local humanoid = entry.Seat.Occupant
	if humanoid then
		local occupant = Players:GetPlayerFromCharacter(humanoid.Parent)
		if occupant ~= player then
			ejectOccupant(entry, humanoid) -- it's somebody else's car
			return
		end
		entry.Chassis.Anchored = false
		pcall(function()
			entry.Chassis:SetNetworkOwner(player)
		end)
		entry.Model:SetAttribute("Occupied", true)
	else
		entry.Model:SetAttribute("Occupied", false)
		-- Without this you'd be sat straight back down by touching the seat as you climb out.
		entry.Seat.Disabled = true
		task.delay(RESIT_DELAY, function()
			if entry.Model.Parent then
				entry.Seat.Disabled = false
			end
		end)
		-- Let it roll for a moment, then park it where it stopped.
		task.delay(0.4, function()
			if entry.Model.Parent and not entry.Seat.Occupant then
				entry.Chassis.Anchored = true
			end
		end)
	end
end

local function destroyVehicle(player: Player)
	local entry = vehicles[player]
	if entry then
		vehicles[player] = nil
		entry.Model:Destroy()
	end
end

local function createVehicle(player: Player, vehicleId: string)
	local model = VehicleBuilder.build(vehicleId)
	model.Name = player.Name .. "'s " .. Config.VehicleById[vehicleId].Name
	model:SetAttribute("OwnerUserId", player.UserId)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = GROUP_VEHICLES
		end
	end

	local entry = {
		Model = model,
		Chassis = model.PrimaryPart,
		Seat = model:FindFirstChild("Seat"),
		Id = vehicleId,
	}
	entry.Chassis.Anchored = true
	entry.Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupantChanged(player, entry)
	end)
	CollectionService:AddTag(model, VEHICLE_TAG)
	vehicles[player] = entry
	return entry
end

-- Finding somewhere to put the car -------------------------------------------------------

local function findSpawnCFrame(root: BasePart, entry)
	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatLook.Magnitude < 0.1 then
		flatLook = Vector3.new(0, 0, -1)
	end
	flatLook = flatLook.Unit
	local right = flatLook:Cross(Vector3.yAxis)

	local ignore = { root.Parent, vehiclesFolder }
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignore

	local size = entry.Model:GetExtentsSize()
	local hullHalf = entry.Model:GetAttribute("HullHalfHeight")
	local reach = size.Z / 2 + 6
	local offsets = {
		flatLook * reach,
		right * (size.X / 2 + 8),
		right * -(size.X / 2 + 8),
		flatLook * -reach,
		flatLook * (reach * 2.2),
	}

	for _, offset in offsets do
		local origin = root.Position + offset + Vector3.new(0, 6, 0)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -40, 0), rayParams)
		if hit and hit.Normal.Y > 0.7 then
			local position = hit.Position + Vector3.new(0, hullHalf + 0.05, 0)
			local cframe = CFrame.lookAt(position, position + flatLook)
			-- Anything solid between the wheels' top and the roof means we'd be spawning inside something.
			local boxCFrame = cframe * CFrame.new(0, hullHalf + 2.5, 0)
			local boxSize = Vector3.new(size.X + 1, 3.5, size.Z + 1)
			local blocked = false
			for _, part in Workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams) do
				if part.CanCollide then
					blocked = true
					break
				end
			end
			if not blocked then
				return cframe
			end
		end
	end

	-- Nowhere clear: drop it just ahead of the player and let physics sort it out.
	local position = root.Position + flatLook * reach + Vector3.new(0, 3, 0)
	return CFrame.lookAt(position, position + flatLook)
end

local function seatPlayer(entry, humanoid: Humanoid, root: BasePart)
	entry.Seat.Disabled = false
	local ok = pcall(function()
		entry.Seat:Sit(humanoid)
	end)
	if not ok then
		-- Touching an enabled seat sits you in it.
		root.CFrame = entry.Seat.CFrame * CFrame.new(0, 2, 0)
	end
end

-- Public API ---------------------------------------------------------------------------------

function VehicleService.hasVehicle(player: Player): boolean
	return vehicles[player] ~= nil
end

-- Brings the player's equipped vehicle to them and sits them in it. Returns ok, message.
function VehicleService.summon(player: Player, ignoreCooldown: boolean?): (boolean, string?)
	local now = os.clock()
	if not ignoreCooldown and lastSummon[player] and now - lastSummon[player] < Config.SummonCooldown then
		return false, "Give it a moment..."
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 then
		return false, "You can't do that right now."
	end
	local profile = PlayerService.get(player)
	if not profile then
		return false, "Still loading your profile..."
	end

	local entry = vehicles[player]
	if entry and entry.Model.Parent and humanoid.SeatPart == entry.Seat then
		return true, nil -- already driving it
	end

	lastSummon[player] = now
	if entry and (entry.Id ~= profile.Equipped or not entry.Model.Parent) then
		destroyVehicle(player)
		entry = nil
	end
	if not entry then
		entry = createVehicle(player, profile.Equipped)
	end

	entry.Chassis.Anchored = true
	entry.Model:PivotTo(findSpawnCFrame(root, entry))
	if not entry.Model.Parent then
		entry.Model.Parent = vehiclesFolder
	end
	seatPlayer(entry, humanoid, root)
	return true, nil
end

-- After the equipped vehicle changed: swap the spawned one for the new model.
function VehicleService.swapEquipped(player: Player)
	if vehicles[player] then
		destroyVehicle(player)
		VehicleService.summon(player, true)
	end
end

-- Makes sure the player has a vehicle in the world (used when they take an order).
function VehicleService.ensureVehicle(player: Player)
	if not vehicles[player] then
		VehicleService.summon(player, true)
	end
end

function VehicleService.start()
	vehiclesFolder = Workspace:FindFirstChild("Vehicles")
	if not vehiclesFolder then
		vehiclesFolder = Instance.new("Folder")
		vehiclesFolder.Name = "Vehicles"
		vehiclesFolder.Parent = Workspace
	end

	setupCollisionGroups()

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(putCharacterInGroup)
		if player.Character then
			putCharacterInGroup(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		destroyVehicle(player)
		lastSummon[player] = nil
	end)

	Remotes.CallVehicle.OnServerEvent:Connect(function(player)
		local ok, message = VehicleService.summon(player)
		if not ok and message then
			PlayerService.notify(player, message, "warn")
		end
	end)

	-- Anything that somehow ends up under the map is brought back.
	task.spawn(function()
		while true do
			task.wait(2)
			for player, entry in vehicles do
				if entry.Chassis.Position.Y < VOID_Y then
					destroyVehicle(player)
					PlayerService.notify(player, "Your vehicle fell off the map. Press V to call it again.", "warn")
				end
			end
		end
	end)
end

return VehicleService
