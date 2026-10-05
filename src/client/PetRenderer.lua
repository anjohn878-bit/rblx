-- Draws everyone's pet birds. The server publishes a marker for every pet
-- that is out in a garden (or sitting on a nest); each client builds the
-- model locally and makes it hop around, peck, flutter up onto blooming
-- plants and, for babies, tag along behind their parents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdBuilder = require(Shared.BirdBuilder)
local Birds = require(Shared.Birds)
local Pets = require(Shared.Pets)
local Rarities = require(Shared.Rarities)

local PetRenderer = {}

local HOP_SPEED = 5 -- studs per second
local HOP_RATE = 2.6 -- hops per second
local HOP_HEIGHT = 0.55
local FLY_SPEED = 14
local TURN_SPEED = 8

local rng = Random.new()
local markers
local container
local pets = {} -- [markerName] = state
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

------------------------------------------------------------------------------
-- Garden helpers

local function plotFor(plotId)
	local root = workspace:FindFirstChild("BirdGarden")
	local plots = root and root:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. tostring(plotId))
end

local function groundHeight(plot, position)
	rayParams.FilterDescendantsInstances = { plot }
	local result = workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), rayParams)
	if result then
		return result.Position.Y
	end
	local ground = plot:FindFirstChild("Ground")
	return ground and (ground.CFrame.Position.Y + ground.Size.Y / 2) or position.Y
end

local function randomPoint(plot)
	local ground = plot:FindFirstChild("Ground")
	if not ground then
		return nil
	end
	local half = ground.Size / 2
	local offset =
		Vector3.new(rng:NextNumber(-half.X + 2.5, half.X - 2.5), 0, rng:NextNumber(-half.Z + 2.5, half.Z - 2.5))
	local point = ground.CFrame:PointToWorldSpace(offset)
	return Vector3.new(point.X, groundHeight(plot, point), point.Z)
end

local function randomPerch(plot)
	local plants = plot:FindFirstChild("Plants")
	if not plants then
		return nil
	end
	local options = {}
	for _, plant in ipairs(plants:GetChildren()) do
		local root = plant.PrimaryPart
		local perch = root and root:FindFirstChild("Perch")
		if perch and plant:GetAttribute("Stage") == 4 and not plant:GetAttribute("HasBird") then
			table.insert(options, root.CFrame * perch.Position)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[rng:NextInteger(1, #options)]
end

local function nestSeat(plot, marker)
	local nest = plot:FindFirstChild("Nest" .. tostring(marker:GetAttribute("NestIndex")))
	local base = nest and nest:FindFirstChild("NestBase")
	if not base then
		return nil
	end
	-- the two parents sit on opposite sides of the egg
	local side = 1
	for name, other in pairs(pets) do
		if
			other.Marker ~= marker
			and other.Marker:GetAttribute("Mode") == "Nest"
			and other.Marker:GetAttribute("NestIndex") == marker:GetAttribute("NestIndex")
			and other.Marker:GetAttribute("OwnerUserId") == marker:GetAttribute("OwnerUserId")
			and name < marker.Name
		then
			side = -1
		end
	end
	local center = base.CFrame.Position
	return center + Vector3.new(side * 1.6, 0.75, 0), center
end

------------------------------------------------------------------------------
-- Models

local function yawToward(direction)
	return math.atan2(-direction.X, -direction.Z)
end

local function lerpAngle(a, b, alpha)
	local difference = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + difference * alpha
end

local function addNameTag(model, marker)
	local def = Birds.Get(marker:GetAttribute("Species"))
	local gui = Instance.new("BillboardGui")
	gui.Name = "PetTag"
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.8 * (def.Look.Size or 1), 0)
	gui.MaxDistance = 30
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = (marker:GetAttribute("Baby") and "👶 " or "")
		.. (marker:GetAttribute("DisplayName") or def.Name)
		.. " "
		.. Pets.StarText(marker:GetAttribute("Stars"))
	label.TextColor3 = marker:GetAttribute("Shiny") and Color3.fromRGB(255, 230, 120) or Rarities.Color(def.Rarity)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Parent = gui
	gui.Parent = model.PrimaryPart
end

local function buildModel(state)
	if state.Model then
		state.Model:Destroy()
	end
	local marker = state.Marker
	local def = Birds.Get(marker:GetAttribute("Species"))
	if not def then
		return
	end
	local model = BirdBuilder.Build(def, {
		Shiny = marker:GetAttribute("Shiny"),
		Scale = marker:GetAttribute("Baby") and Pets.BabyScale or 1,
	})
	model.Name = marker.Name
	model:SetAttribute("Flying", false)
	addNameTag(model, marker)
	state.Model = model
	state.StandHeight = model:GetAttribute("StandHeight")
	state.Hover = model:GetAttribute("Hover")
	state.Key = table.concat({
		marker:GetAttribute("Species"),
		tostring(marker:GetAttribute("Shiny")),
		tostring(marker:GetAttribute("Baby")),
		tostring(marker:GetAttribute("Stars")),
		tostring(marker:GetAttribute("DisplayName")),
	}, "|")
	model.Parent = container
	model:AddTag("BirdGardenBird")
end

------------------------------------------------------------------------------
-- Behaviour

local function startIdle(state, now)
	state.Action = "Idle"
	state.ActionEnd = now + rng:NextNumber(1.2, 3.5)
end

local function startHop(state, target)
	state.Action = "Hop"
	state.Target = target
end

local function startFlight(state, target, perchAfter)
	state.Action = "Fly"
	state.From = state.Position
	state.Target = target
	state.FlightTime = 0
	state.FlightDuration = math.max(0.6, (target - state.Position).Magnitude / FLY_SPEED)
	state.PerchAfter = perchAfter
end

local function chooseNext(state, now)
	local marker = state.Marker
	local follow = marker:GetAttribute("Follow")
	local leader = follow ~= "" and pets[follow]
	if leader and leader.Position and leader.Action ~= "Fly" and leader.Action ~= "Perch" then
		-- babies stay close to mum or dad
		local offset = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		local target = leader.Position + offset
		if (target - state.Position).Magnitude > 2.5 then
			startHop(state, Vector3.new(target.X, groundHeight(state.Plot, target), target.Z))
			return
		end
		startIdle(state, now)
		return
	end

	local roll = rng:NextNumber()
	if roll < 0.2 and not marker:GetAttribute("Baby") then
		local perch = randomPerch(state.Plot)
		if perch then
			startFlight(state, perch, true)
			return
		end
	end
	if roll < 0.75 then
		local point = randomPoint(state.Plot)
		if point then
			if (point - state.Position).Magnitude > 16 and not marker:GetAttribute("Baby") then
				startFlight(state, point, false)
			else
				startHop(state, point)
			end
			return
		end
	end
	startIdle(state, now)
end

local function placeModel(state, heightOffset)
	local body = state.Model and state.Model.PrimaryPart
	if body then
		local position = state.Position + Vector3.new(0, state.StandHeight + (heightOffset or 0), 0)
		body.CFrame = CFrame.new(position) * CFrame.Angles(0, state.Yaw, 0)
	end
end

local function faceToward(state, direction, dt)
	if direction.Magnitude > 0.05 then
		state.Yaw = lerpAngle(state.Yaw, yawToward(direction), math.min(1, dt * TURN_SPEED))
	end
end

local function updatePet(state, dt, now)
	local marker = state.Marker
	if not state.Plot or not state.Plot.Parent then
		state.Plot = plotFor(marker:GetAttribute("PlotId"))
		if not state.Plot then
			return
		end
	end
	if not state.Position then
		local spawnAt = marker:GetAttribute("SpawnAt")
		if typeof(spawnAt) == "Vector3" then
			state.Position = spawnAt - Vector3.new(0, state.StandHeight, 0)
			local landing = randomPoint(state.Plot)
			if landing then
				startFlight(state, landing, false)
			end
		else
			state.Position = randomPoint(state.Plot)
			if not state.Position then
				return
			end
			startIdle(state, now)
		end
	end
	local model = state.Model
	if not model then
		return
	end

	if marker:GetAttribute("Mode") == "Nest" then
		local seat, center = nestSeat(state.Plot, marker)
		if seat then
			state.Position = seat
			state.Action = "Nest"
			faceToward(state, center - seat, dt)
			model:SetAttribute("Flying", false)
			placeModel(state, math.sin(now * 2 + seat.X) * 0.04)
			return
		end
	elseif state.Action == "Nest" then
		-- just left the nest
		startIdle(state, now)
	end

	local hoverHeight = 0
	if state.Action == "Idle" then
		model:SetAttribute("Flying", false)
		if now >= state.ActionEnd then
			chooseNext(state, now)
		end
	elseif state.Action == "Hop" then
		model:SetAttribute("Flying", false)
		local toTarget = state.Target - state.Position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		local speed = HOP_SPEED * (marker:GetAttribute("Baby") and 0.8 or 1)
		if flat.Magnitude <= speed * dt then
			state.Position = state.Target
			startIdle(state, now)
		else
			local step = flat.Unit * speed * dt
			local nextPosition = state.Position + step
			state.Position = Vector3.new(nextPosition.X, state.Target.Y, nextPosition.Z)
			faceToward(state, flat, dt)
			state.HopPhase = (state.HopPhase or 0) + dt * HOP_RATE * math.pi
			hoverHeight = math.abs(math.sin(state.HopPhase)) * HOP_HEIGHT
		end
	elseif state.Action == "Fly" then
		model:SetAttribute("Flying", true)
		state.FlightTime += dt
		local alpha = math.min(1, state.FlightTime / state.FlightDuration)
		local eased = alpha * alpha * (3 - 2 * alpha)
		local path = state.Target - state.From
		local arc = math.sin(alpha * math.pi) * math.min(8, 2 + path.Magnitude * 0.3)
		state.Position = state.From + path * eased + Vector3.new(0, arc, 0)
		faceToward(state, Vector3.new(path.X, 0, path.Z), dt)
		if alpha >= 1 then
			state.Position = state.Target
			if state.PerchAfter then
				state.Action = "Perch"
				state.ActionEnd = now + rng:NextNumber(4, 9)
			else
				startIdle(state, now)
			end
		end
	elseif state.Action == "Perch" then
		model:SetAttribute("Flying", false)
		if now >= state.ActionEnd then
			local landing = randomPoint(state.Plot)
			if landing then
				startFlight(state, landing, false)
			else
				startIdle(state, now)
			end
		end
	end
	if state.Hover then
		hoverHeight += 1.2 + math.sin(now * 3) * 0.15
	end
	placeModel(state, hoverHeight)
end

------------------------------------------------------------------------------
-- Markers

local function addMarker(marker)
	if pets[marker.Name] then
		return
	end
	local state = { Marker = marker, Yaw = rng:NextNumber(-math.pi, math.pi) }
	pets[marker.Name] = state
	buildModel(state)
	state.Connection = marker.AttributeChanged:Connect(function(attribute)
		if
			attribute == "Species"
			or attribute == "Shiny"
			or attribute == "Baby"
			or attribute == "Stars"
			or attribute == "DisplayName"
		then
			buildModel(state)
		elseif attribute == "PlotId" then
			state.Plot = nil
			state.Position = nil
		end
	end)
end

local function removePet(name)
	local state = pets[name]
	if not state then
		return
	end
	pets[name] = nil
	if state.Connection then
		state.Connection:Disconnect()
	end
	if state.Model then
		state.Model:Destroy()
	end
end

local function removeMarker(marker)
	local state = pets[marker.Name]
	if state and state.Marker == marker then
		removePet(marker.Name)
	end
end

-- World position above a pet's head (for floating text), if it's drawn.
function PetRenderer.GetPosition(markerName)
	local state = pets[markerName]
	if state and state.Position and state.Model then
		return state.Position + Vector3.new(0, state.StandHeight + 2, 0)
	end
	return nil
end

function PetRenderer.Init()
	container = Instance.new("Folder")
	container.Name = "BirdGardenPetModels"
	container.Parent = workspace

	markers = ReplicatedStorage:WaitForChild("BirdGardenPets")
	for _, marker in ipairs(markers:GetChildren()) do
		addMarker(marker)
	end
	markers.ChildAdded:Connect(addMarker)
	markers.ChildRemoved:Connect(removeMarker)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		dt = math.min(dt, 0.1)
		for name, state in pairs(pets) do
			-- markers can disappear between ChildRemoved and the next frame
			local alive, parent = pcall(function()
				return state.Marker.Parent
			end)
			if not alive or parent ~= markers then
				removePet(name)
				continue
			end
			local ok, err = pcall(updatePet, state, dt, now)
			if not ok then
				if not state.Warned then
					state.Warned = true
					warn("[BirdGarden] Pet update failed:", err)
				end
				state.Action = "Idle"
				state.ActionEnd = now + 1
			end
		end
	end)
end

return PetRenderer
