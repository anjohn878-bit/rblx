--[[
	KickMath
	Pure functions that turn a kick request into a ball velocity. The server is the
	only caller that applies the result; it lives in Shared so it can be unit
	tested and so the client could predict trajectories later.

	Directions are flattened to the XZ plane. Attribute alphas are 0..1.
]]

local Config = require(script.Parent.Config)

local KickMath = {}

export type Mate = { Position: Vector3, Velocity: Vector3, Id: any }

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end
KickMath.Flat = flat

local function angleBetween(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
end

-- Rotates a flat direction around Y by degrees.
local function rotateY(dir: Vector3, degrees: number): Vector3
	local r = math.rad(degrees)
	local c, s = math.cos(r), math.sin(r)
	return Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
end
KickMath.RotateY = rotateY

function KickMath.EffectiveGravity(gravity: number): number
	return gravity * Config.Ball.GravityScale
end

-- Picks the teammate best matching the aim direction (nil if nobody in the cone).
function KickMath.FindPassTarget(origin: Vector3, dir: Vector3, mates: { Mate }, maxAngle: number, maxRange: number): Mate?
	local best, bestScore = nil, math.huge
	for _, mate in mates do
		local offset = mate.Position - origin
		local dist = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if dist > 3 and dist <= maxRange then
			local angle = angleBetween(dir, flat(offset))
			if angle <= maxAngle then
				local score = angle + dist * 0.15
				if score < bestScore then
					best, bestScore = mate, score
				end
			end
		end
	end
	return best
end

--[[
	params = {
		Kind = "Pass" | "Through" | "Lob" | "Shot",
		Origin = Vector3, Direction = Vector3, Power = 0..1,
		Passing, Shooting = attribute alphas (0..1),
		Mates = { Mate }, GoalCenter = Vector3?, GoalWidth = number?,
		Gravity = workspace gravity, Random = Random,
	}
	Returns: velocity (Vector3), target mate (Mate?)
]]
function KickMath.Compute(params): (Vector3, Mate?)
	local k = Config.Kick
	local rng: Random = params.Random or Random.new()
	local dir = flat(params.Direction)
	local origin = params.Origin
	local power = math.clamp(params.Power or 0.5, 0, 1)
	local passing = math.clamp(params.Passing or 0.5, 0, 1)
	local shooting = math.clamp(params.Shooting or 0.5, 0, 1)
	local g = KickMath.EffectiveGravity(params.Gravity or 196.2)
	local kind = params.Kind

	if kind == "Pass" or kind == "Through" then
		local target = KickMath.FindPassTarget(origin, dir, params.Mates or {}, k.PassAssistAngle, 100)
		local aim
		if target then
			aim = target.Position
			if kind == "Through" then
				local lead = target.Velocity * k.ThroughLeadTime
				aim += Vector3.new(lead.X, 0, lead.Z) + flat(target.Position - origin) * 6
			end
		else
			aim = origin + dir * (if kind == "Through" then 45 else 30)
		end
		local offset = aim - origin
		local dist = Vector3.new(offset.X, 0, offset.Z).Magnitude
		local aimDir = flat(offset)
		local errorDeg = (1 - passing) * 4 * (rng:NextNumber() * 2 - 1)
		aimDir = rotateY(aimDir, errorDeg)
		local speed = math.clamp(dist * 1.3 + 30, k.PassMinSpeed, k.PassMaxSpeed) * (0.92 + 0.08 * passing)
		return aimDir * speed + Vector3.new(0, k.PassLift, 0), target
	elseif kind == "Lob" then
		local target = KickMath.FindPassTarget(origin, dir, params.Mates or {}, k.PassAssistAngle, k.LobMaxRange)
		local aim
		if target then
			aim = target.Position + Vector3.new(target.Velocity.X, 0, target.Velocity.Z) * 0.5
		else
			aim = origin + dir * math.clamp(18 + power * k.LobMaxRange, 18, k.LobMaxRange)
		end
		local offset = aim - origin
		local dist = math.min(Vector3.new(offset.X, 0, offset.Z).Magnitude, k.LobMaxRange)
		local t = k.LobFlightTime
		local aimDir = rotateY(flat(offset), (1 - passing) * 5 * (rng:NextNumber() * 2 - 1))
		local horizontal = dist / t
		local vertical = g * t / 2
		return aimDir * horizontal + Vector3.new(0, vertical, 0), target
	elseif kind == "Shot" then
		local shotDir = dir
		if params.GoalCenter then
			local width = params.GoalWidth or 16
			local goalAim = params.GoalCenter + Vector3.new(0, 0, (rng:NextNumber() * 2 - 1) * (width / 2 - 2))
			local goalDir = flat(goalAim - origin)
			if angleBetween(dir, goalDir) <= k.ShotAssistAngle then
				shotDir = flat(dir:Lerp(goalDir, 0.6))
			end
		end
		local errorDeg = (1 - shooting) * k.ShotMaxErrorDegrees * (0.5 + power * 0.5) * (rng:NextNumber() * 2 - 1)
		shotDir = rotateY(shotDir, errorDeg)
		local speed = (k.ShotMinSpeed + (k.ShotMaxSpeed - k.ShotMinSpeed) * power) * (0.85 + 0.15 * shooting)
		local lift = k.ShotMinLift + (k.ShotMaxLift - k.ShotMinLift) * power
		return shotDir * speed + Vector3.new(0, lift, 0), nil
	end

	error("Unknown kick kind " .. tostring(kind))
end

-- Tackle success chance from attributes (alphas 0..1).
function KickMath.TackleChance(defending: number, dribbling: number): number
	local t = Config.Tackle
	return math.clamp(t.BaseSuccess + (defending - dribbling) * t.AttributeSwing, 0.2, 0.92)
end

-- Chance to cleanly control a hard incoming ball.
function KickMath.FirstTouchChance(ballControl: number, speed: number): number
	local hard = Config.Ball.HardTouchSpeed
	if speed <= hard then
		return 1
	end
	local over = math.clamp((speed - hard) / 50, 0, 1)
	return math.clamp(1 - over * (0.75 - 0.5 * ballControl), 0.25, 1)
end

return KickMath
