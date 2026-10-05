--!strict
-- Deterministic bird motion. A visit is fully described by a few numbers and a
-- start time, so every client can compute exactly where a bird is at any moment
-- (including clients that join mid-visit) with no per-frame network traffic.

local Types = require(script.Parent.Types)
type VisitInfo = Types.VisitInfo

local BirdFlight = {}

export type Sample = {
	position: Vector3,
	look: Vector3, -- unit vector the bird faces
	phase: "arrive" | "perch" | "leave" | "done",
	flap: number, -- 0 = wings folded, 1 = flapping hard
}

local UP = Vector3.new(0, 1, 0)

local function rotateY(v: Vector3, angle: number): Vector3
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(v.X * c + v.Z * s, v.Y, -v.X * s + v.Z * c)
end

local function bezier(p0: Vector3, c: Vector3, p1: Vector3, s: number): Vector3
	local a = 1 - s
	return p0 * (a * a) + c * (2 * a * s) + p1 * (s * s)
end

local function bezierDirection(p0: Vector3, c: Vector3, p1: Vector3, s: number, fallback: Vector3): Vector3
	local d = (c - p0) * (2 * (1 - s)) + (p1 - c) * (2 * s)
	if d.Magnitude < 1e-4 then
		return fallback
	end
	return d.Unit
end

-- Blend two unit directions. A plain Lerp shrinks the vector (and hits zero for
-- opposite directions), which would hand CFrame.lookAt a degenerate input.
local function blend(a: Vector3, b: Vector3, t: number): Vector3
	local v = a:Lerp(b, t)
	if v.Magnitude < 1e-3 then
		return b
	end
	return v.Unit
end

function BirdFlight.duration(visit: VisitInfo): number
	return visit.arrive + visit.stay + visit.leave
end

function BirdFlight.sample(visit: VisitInfo, t: number): Sample
	local perch = visit.perch
	local facing = visit.facing

	if t < visit.arrive then
		-- Swoop in and brake onto the perch.
		local u = math.clamp(t / visit.arrive, 0, 1)
		local s = 1 - (1 - u) * (1 - u)
		local control = perch + (visit.from - perch) * 0.4 + UP * 3.5
		local dir = bezierDirection(visit.from, control, perch, s, facing)
		local turn = math.clamp((u - 0.7) / 0.3, 0, 1)
		return {
			position = bezier(visit.from, control, perch, s),
			look = blend(dir, facing, turn),
			phase = "arrive",
			flap = 1,
		}
	end

	local sinceLanding = t - visit.arrive
	if sinceLanding < visit.stay then
		-- Perched: hop a little and glance around.
		local hop = math.max(0, math.sin(sinceLanding * 3.1 + visit.seed)) ^ 6 * 0.12
		local glance = math.sin(sinceLanding * 0.7 + visit.seed * 1.7) * 0.55
		return {
			position = perch + UP * hop,
			look = rotateY(facing, glance),
			phase = "perch",
			flap = 0,
		}
	end

	local u = math.clamp((sinceLanding - visit.stay) / visit.leave, 0, 1)
	if u >= 1 then
		return { position = visit.to, look = (visit.to - perch).Unit, phase = "done", flap = 1 }
	end
	-- Take off, accelerating away.
	local s = u * u
	local control = perch + UP * 6 + (visit.to - perch) * 0.2
	local dir = bezierDirection(perch, control, visit.to, s, facing)
	local turn = math.clamp(u / 0.2, 0, 1)
	return {
		position = bezier(perch, control, visit.to, s),
		look = blend(facing, dir, turn),
		phase = "leave",
		flap = 1,
	}
end

-- Builds the geometry for a visit: where the bird comes from, which way it
-- faces on the perch, and where it exits to.
function BirdFlight.plan(perch: Vector3, rng: Random)
	local inAngle = rng:NextNumber(0, math.pi * 2)
	local inDir = Vector3.new(math.cos(inAngle), 0, math.sin(inAngle))
	local outAngle = inAngle + math.pi + rng:NextNumber(-1.1, 1.1)
	local outDir = Vector3.new(math.cos(outAngle), 0, math.sin(outAngle))
	local faceAngle = rng:NextNumber(0, math.pi * 2)
	return {
		from = perch + inDir * rng:NextNumber(55, 80) + UP * rng:NextNumber(18, 30),
		to = perch + outDir * rng:NextNumber(60, 90) + UP * rng:NextNumber(22, 38),
		facing = Vector3.new(math.cos(faceAngle), 0, math.sin(faceAngle)),
		seed = rng:NextNumber(0, 100),
	}
end

return BirdFlight
