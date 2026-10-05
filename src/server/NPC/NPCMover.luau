--[[
	NPCMover
	Walks a humanoid through a list of floor-level waypoints.

	* If the straight line to the next waypoint is clear it walks directly
	  (cheap and smooth).
	* If something is in the way it asks PathfindingService for a route.
	* If the NPC makes no progress for too long it is gently teleported to
	  the target so the hospital simulation can never jam.
	* Every walk carries a cancel token so the simulation can interrupt it
	  (e.g. when the hospital is rebuilt after an upgrade).
]]

local PathfindingService = game:GetService("PathfindingService")

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

export type Token = { Cancelled: boolean }

export type Walker = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	RootHeight: number,
}

local NPCMover = {}

local ARRIVE_DISTANCE = 1.4
local POLL = 0.1

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.CollisionGroup = "NPC"
rayParams.RespectCanCollide = true

function NPCMover.NewToken(): Token
	return { Cancelled = false }
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return (flat(a) - flat(b)).Magnitude
end

local function teleport(walker: Walker, target: Vector3)
	local root = walker.Root
	local from = root.Position
	local destination = Vector3.new(target.X, target.Y + walker.RootHeight, target.Z)
	local direction = flat(destination - from)
	local cf
	if direction.Magnitude > 0.05 then
		cf = CFrame.lookAt(destination, destination + direction.Unit)
	else
		cf = CFrame.new(destination) * root.CFrame.Rotation
	end
	walker.Model:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
end

-- Moves straight towards `target`, returns false if cancelled.
local function moveDirect(walker: Walker, target: Vector3, token: Token): boolean
	local humanoid = walker.Humanoid
	local root = walker.Root
	local distance = flatDistance(root.Position, target)
	if distance <= ARRIVE_DISTANCE then
		return true
	end
	local speed = math.max(humanoid.WalkSpeed, 1)
	local timeout = distance / speed * 1.8 + 2
	local started = os.clock()
	local lastIssue = started
	local lastProgressAt = started
	local bestDistance = distance

	humanoid:MoveTo(target)
	while true do
		task.wait(POLL)
		if token.Cancelled then
			return false
		end
		if not root.Parent or not humanoid.Parent then
			return false
		end
		local now = os.clock()
		local current = flatDistance(root.Position, target)
		if current <= ARRIVE_DISTANCE then
			return true
		end
		if current < bestDistance - 0.3 then
			bestDistance = current
			lastProgressAt = now
		end
		-- Humanoid:MoveTo gives up after 8 seconds; re-issue it regularly.
		if now - lastIssue > 4 then
			humanoid:MoveTo(target)
			lastIssue = now
		end
		if now - started > timeout or now - lastProgressAt > 2.5 then
			teleport(walker, target)
			return true
		end
	end
end

local function lineIsClear(walker: Walker, target: Vector3): boolean
	local origin = walker.Root.Position
	local goal = Vector3.new(target.X, origin.Y, target.Z)
	local direction = goal - origin
	if direction.Magnitude < 0.1 then
		return true
	end
	rayParams.FilterDescendantsInstances = { walker.Model }
	local result = workspace:Raycast(origin, direction, rayParams)
	return result == nil
end

local function moveWithPathfinding(walker: Walker, target: Vector3, token: Token): boolean
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.5,
		AgentHeight = 5,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 6,
	})
	local ok = pcall(function()
		path:ComputeAsync(walker.Root.Position, target)
	end)
	if token.Cancelled then
		return false
	end
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return moveDirect(walker, target, token)
	end
	local waypoints = path:GetWaypoints()
	for index = 2, #waypoints do
		if not moveDirect(walker, waypoints[index].Position, token) then
			return false
		end
	end
	return moveDirect(walker, target, token)
end

-- Walks through every point in order. Returns true when the whole route
-- finished, false when it was cancelled.
function NPCMover.Walk(walker: Walker, points: { Vector3 }, token: Token): boolean
	for _, point in points do
		if token.Cancelled then
			return false
		end
		local okStep
		if GameConfig.UsePathfinding and not lineIsClear(walker, point) then
			okStep = moveWithPathfinding(walker, point, token)
		else
			okStep = moveDirect(walker, point, token)
		end
		if not okStep then
			return false
		end
	end
	return not token.Cancelled
end

NPCMover.Teleport = teleport

return NPCMover
