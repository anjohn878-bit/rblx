--[[
	The arcade driving model, as pure maths (Vector3 in, Vector3 out) so it can be unit-tested.

	Rather than simulate wheels and suspension, the driver's client owns the car's physics and, every
	frame, sets its velocity from throttle/steering input and keeps it upright:

	  * Forward speed accelerates toward throttle * MaxSpeed (braking is stronger than accelerating).
	  * Sideways slide decays at rate Grip, which gives a little drift when you turn hard.
	  * Steering needs some forward speed, and eases off as you go faster (so top speed isn't twitchy).
	  * Angular velocity = yaw from steering + a correction that rolls the car back upright, so it
	    can never flip no matter what it hits. Y velocity is left alone, so gravity and collisions work.

	Conventions: the car faces its LookVector (-Z locally). Positive angular velocity about +Y turns
	left, so steering right (steer > 0) is negative yaw.
]]

local DriveModel = {}

DriveModel.COAST_DECEL = 0.45 -- fraction of Accel used to slow down with no throttle
DriveModel.BRAKE_MULT = 2.2 -- braking is this many times stronger than accelerating
DriveModel.REVERSE_FRACTION = 0.4 -- reverse top speed as a fraction of MaxSpeed
DriveModel.STEER_FULL_SPEED = 10 -- studs/s of forward speed at which steering is fully effective
DriveModel.TURN_FALLOFF = 0.45 -- how much steering is reduced at top speed
DriveModel.LEVEL_RATE = 8 -- how hard the car rights itself (1/s)
DriveModel.RECOVER_UP_Y = 0.3 -- if the car's up vector is flatter than this it is badly flipped

local function approach(value: number, target: number, maxDelta: number): number
	if value < target then
		return math.min(value + maxDelta, target)
	end
	return math.max(value - maxDelta, target)
end

-- stats: { MaxSpeed, Accel, Turn, Grip }
-- Returns newLinearVelocity, newAngularVelocity.
function DriveModel.step(velocity: Vector3, look: Vector3, up: Vector3, throttle: number, steer: number, stats, dt: number): (Vector3, Vector3)
	local leveling = up:Cross(Vector3.yAxis) * DriveModel.LEVEL_RATE

	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 1e-3 then
		return velocity, leveling -- pointing straight up/down: only try to right the car
	end
	local forward = flatLook.Unit
	local right = forward:Cross(Vector3.yAxis)

	local forwardSpeed = velocity:Dot(forward)
	local sideSpeed = velocity:Dot(right)

	-- Longitudinal: accelerate, brake, or coast.
	local target
	if throttle > 0 then
		target = throttle * stats.MaxSpeed
	elseif throttle < 0 then
		target = throttle * stats.MaxSpeed * DriveModel.REVERSE_FRACTION
	else
		target = 0
	end

	local rate
	if throttle == 0 then
		rate = stats.Accel * DriveModel.COAST_DECEL
	elseif (throttle > 0 and forwardSpeed >= 0) or (throttle < 0 and forwardSpeed <= 0) then
		rate = stats.Accel * math.abs(throttle)
	else
		rate = stats.Accel * DriveModel.BRAKE_MULT
	end
	forwardSpeed = approach(forwardSpeed, target, rate * dt)

	-- Lateral grip.
	sideSpeed *= math.exp(-stats.Grip * dt)

	-- Steering.
	local authority = math.clamp(math.abs(forwardSpeed) / DriveModel.STEER_FULL_SPEED, 0, 1)
	local speedFraction = math.clamp(math.abs(forwardSpeed) / stats.MaxSpeed, 0, 1)
	local turnRate = stats.Turn * (1 - DriveModel.TURN_FALLOFF * speedFraction) * authority
	local direction = forwardSpeed >= 0 and 1 or -1 -- steering inverts when reversing
	local yaw = -steer * turnRate * direction

	local newVelocity = forward * forwardSpeed + right * sideSpeed + Vector3.new(0, velocity.Y, 0)
	return newVelocity, Vector3.new(0, yaw, 0) + leveling
end

-- True when the car is so tilted that rolling back upright would take too long.
function DriveModel.needsRecovery(up: Vector3): boolean
	return up.Y < DriveModel.RECOVER_UP_Y
end

-- Where to put a badly flipped car: same spot, a little higher, facing the way its nose was pointing.
function DriveModel.recoveryCFrame(position: Vector3, look: Vector3): CFrame
	local yaw = 0
	if look.X ~= 0 or look.Z ~= 0 then
		yaw = math.atan2(-look.X, -look.Z)
	end
	return CFrame.new(position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, yaw, 0)
end

return DriveModel
