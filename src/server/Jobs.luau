-- Hands out parcels at the depot counter and pays players when they hand them over at the door.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Jobs = {}

local ECON = Config.Economy
local rng = Random.new()
local nextJobId = 0
local registry
local parcelFolder: Folder

local function getKind(id: string): Config.PackageKind
	for _, kind in Config.PackageKinds do
		if kind.Id == id then
			return kind
		end
	end
	return Config.PackageKinds[1]
end

local function rollKind(newDriver: boolean): Config.PackageKind
	if newDriver then
		return Config.PackageKinds[1]
	end
	local total = 0
	for _, kind in Config.PackageKinds do
		total += kind.Weight
	end
	local roll = rng:NextNumber(0, total)
	for _, kind in Config.PackageKinds do
		roll -= kind.Weight
		if roll <= 0 then
			return kind
		end
	end
	return Config.PackageKinds[1]
end

function Jobs.loadPackages(player: Player)
	local session = PlayerData.get(player)
	if not session then
		return
	end

	local capacity = PlayerData.capacity(session)
	local free = capacity - #session.Jobs
	if free <= 0 then
		PlayerData.notify(player, "You're fully loaded! Deliver your packages first.", "error")
		return
	end

	local newDriver = session.Data.Deliveries < ECON.NewDriverDeliveries
	local taken = {}
	for _, job in session.Jobs do
		taken[job.AddressId] = true
	end
	local candidates = {}
	for _, address in registry.Addresses do
		if not taken[address.Id] and (not newDriver or address.DepotDistance <= ECON.NewDriverMaxDistance) then
			table.insert(candidates, address)
		end
	end

	local vehicle = Config.getVehicle(session.Data.Equipped) or Config.Vehicles[1]
	local payMultiplier = Config.Ranks[PlayerData.rankIndex(session)].PayMultiplier
	local now = Workspace:GetServerTimeNow()
	local loaded = 0

	for _ = 1, free do
		if #candidates == 0 then
			break
		end
		local address = table.remove(candidates, rng:NextInteger(1, #candidates))
		local kind = rollKind(newDriver)
		local distance = address.DepotDistance
		local ahead = #session.Jobs
		local parTime = (
			ECON.ParBaseSeconds
			+ distance / (vehicle.TopSpeed * ECON.ParSpeedFactor)
			+ ahead * ECON.ParPerExtraPackage
		) * kind.TimeMultiplier
		local reward = math.floor((ECON.BasePay + distance * ECON.PayPerStud) * kind.PayMultiplier * payMultiplier + 0.5)

		nextJobId += 1
		table.insert(session.Jobs, {
			Id = nextJobId,
			AddressId = address.Id,
			Name = address.Name,
			Address = address.Address,
			Position = address.Position,
			Kind = kind.Id,
			Reward = reward,
			Deadline = now + parTime,
			LoadedAt = now,
		})
		loaded += 1
	end

	PlayerData.changed(session)
	if session.Data.Deliveries == 0 and loaded > 0 then
		PlayerData.notify(player, "Follow the beacon to the address, then press E at the door!", "success")
	else
		PlayerData.notify(player, string.format("Loaded %d package%s.", loaded, if loaded == 1 then "" else "s"), "success")
	end
end

-- Leave a parcel on the doorstep for a while so everyone can see the delivery.
local function dropParcel(position: Vector3, kind: Config.PackageKind)
	local parcel = Instance.new("Part")
	parcel.Name = "DeliveredParcel"
	parcel.Size = Vector3.new(1.8, 1.4, 1.8)
	parcel.CFrame = CFrame.new(position - Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	parcel.Color = kind.Color
	parcel.Material = Enum.Material.Cardboard
	parcel.Anchored = true
	parcel.CanCollide = false
	parcel.CanQuery = false
	parcel.Parent = parcelFolder
	Debris:AddItem(parcel, 30)
end

function Jobs.deliver(player: Player, jobId: any)
	if typeof(jobId) ~= "number" then
		return
	end
	local session = PlayerData.get(player)
	if not session then
		return
	end

	local index, job
	for i, candidate in session.Jobs do
		if candidate.Id == jobId then
			index, job = i, candidate
			break
		end
	end
	if not job then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if humanoid.SeatPart then
		PlayerData.notify(player, "Hop out of your vehicle to hand over the package!", "error")
		return
	end
	local offset = root.Position - job.Position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > ECON.DeliverRadius or math.abs(offset.Y) > 12 then
		PlayerData.notify(player, "Walk up to the door to deliver.", "error")
		return
	end

	local now = Workspace:GetServerTimeNow()
	local minimumTime = Config.roadDistance(registry.Depot.Counter, job.Position) / ECON.MaxTravelSpeed
	if now - job.LoadedAt < minimumTime then
		PlayerData.notify(player, "Whoa, that was impossibly fast! Try driving there.", "error")
		return
	end

	table.remove(session.Jobs, index)
	local onTime = now <= job.Deadline
	local bonus = if onTime then math.floor(job.Reward * ECON.FastBonus + 0.5) else 0
	local payout = job.Reward + bonus

	local oldRank = PlayerData.rankIndex(session)
	session.Data.Cash += payout
	session.Data.Earned += payout
	session.Data.Deliveries += 1
	local newRank = PlayerData.rankIndex(session)
	PlayerData.changed(session)

	local kind = getKind(job.Kind)
	dropParcel(job.Position, kind)

	local text = string.format("Delivered to %s! +%s", job.Name or job.Address, Format.money(payout))
	if onTime then
		text ..= string.format(" (incl. %s speed bonus)", Format.money(bonus))
	end
	Remotes.Notify:FireClient(player, text, "delivered", job.Position)

	if newRank > oldRank then
		local rank = Config.Ranks[newRank]
		local unlocked = {}
		for _, vehicle in Config.Vehicles do
			if vehicle.Rank == newRank then
				table.insert(unlocked, vehicle.Name)
			end
		end
		local message = if newRank == 2
			then "You've officially become a Delivery Driver!"
			else "Promoted to " .. rank.Name .. "!"
		if #unlocked > 0 then
			message ..= " Unlocked: " .. table.concat(unlocked, ", ")
		end
		PlayerData.notify(player, message, "rank")
	end
end

function Jobs.init(cityRegistry)
	registry = cityRegistry

	parcelFolder = Instance.new("Folder")
	parcelFolder.Name = "DeliveredParcels"
	parcelFolder.Parent = Workspace

	registry.Depot.LoadPrompt.Triggered:Connect(Jobs.loadPackages)
	Remotes.DeliverPackage.OnServerEvent:Connect(Jobs.deliver)
end

return Jobs
