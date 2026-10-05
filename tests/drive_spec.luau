local roblox = require("@lune/roblox")
local Fixture = require("./fixture")
local Mocks = require("./mocks")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local DT = 1 / 60
local UP = Vector3.yAxis
local LOOK = Vector3.new(0, 0, -1) -- facing -Z, as built

return function(T)
	local fx = Fixture.new()
	local Config = fx:require("ReplicatedStorage.Shared.Config")
	local DriveModel = fx:require("StarterPlayer.StarterPlayerScripts.Client.DriveModel")

	local stats = { MaxSpeed = 60, Accel = 40, Turn = 2.5, Grip = 5 }

	-- Runs the model for `seconds`, rotating the car by the yaw it asks for. Returns final velocity + facing.
	local function simulate(seconds, throttle, steer, startVelocity, startLook, s)
		steer = steer or 0
		local velocity = startVelocity or Vector3.zero
		local look = startLook or LOOK
		for _ = 1, math.floor(seconds / DT) do
			local newVelocity, angular = DriveModel.step(velocity, look, UP, throttle, steer, s or stats, DT)
			velocity = newVelocity
			-- rotate the look vector about +Y by angular.Y * dt (same as the physics engine would)
			local angle = angular.Y * DT
			local c, sn = math.cos(angle), math.sin(angle)
			look = Vector3.new(look.X * c + look.Z * sn, 0, -look.X * sn + look.Z * c)
		end
		return velocity, look
	end

	T.test("full throttle accelerates to top speed and no further", function()
		local v = simulate(0.5, 1)
		T.near(v.Magnitude, stats.Accel * 0.5, 0.5, "accelerates at Accel")
		v = simulate(5, 1)
		T.near(v.Magnitude, stats.MaxSpeed, 1e-6)
		T.truthy(v.Z < 0, "moves along the facing direction (-Z)")
	end)

	T.test("no throttle coasts to a stop", function()
		local v = simulate(6, 0, 0, Vector3.new(0, 0, -stats.MaxSpeed))
		T.near(v.Magnitude, 0, 1e-6)
	end)

	T.test("braking is stronger than coasting", function()
		local start = Vector3.new(0, 0, -50)
		local coast = simulate(0.5, 0, 0, start)
		local brake = simulate(0.5, -1, 0, start)
		T.truthy(brake.Magnitude < coast.Magnitude)
	end)

	T.test("holding reverse after stopping drives backwards, slower than forwards", function()
		local v = simulate(8, -1)
		T.truthy(v.Z > 0, "moves backwards")
		T.near(v.Magnitude, stats.MaxSpeed * DriveModel.REVERSE_FRACTION, 1e-6)
	end)

	T.test("gravity and vertical motion are left to the physics engine", function()
		local v = DriveModel.step(Vector3.new(0, -37, -10), LOOK, UP, 1, 0, stats, DT)
		T.near(v.Y, -37, 1e-9)
	end)

	T.test("steering right turns clockwise (negative yaw), left turns anticlockwise", function()
		local moving = Vector3.new(0, 0, -40)
		local _, right = DriveModel.step(moving, LOOK, UP, 1, 1, stats, DT)
		local _, left = DriveModel.step(moving, LOOK, UP, 1, -1, stats, DT)
		T.truthy(right.Y < 0, "right = " .. right.Y)
		T.truthy(left.Y > 0, "left = " .. left.Y)
		T.near(right.Y, -left.Y, 1e-9)
	end)

	T.test("driving with the wheel right actually ends up pointing to the right (+X)", function()
		local _, look = simulate(1.5, 1, 1)
		T.truthy(look.X > 0.3, "look.X = " .. look.X)
		local _, lookLeft = simulate(1.5, 1, -1)
		T.truthy(lookLeft.X < -0.3)
	end)

	T.test("you can't steer a stationary car, and steering inverts in reverse", function()
		local _, still = DriveModel.step(Vector3.zero, LOOK, UP, 0, 1, stats, DT)
		T.near(still.Y, 0, 1e-9)
		local _, forward = DriveModel.step(Vector3.new(0, 0, -30), LOOK, UP, 0, 1, stats, DT)
		local _, backward = DriveModel.step(Vector3.new(0, 0, 30), LOOK, UP, 0, 1, stats, DT)
		T.truthy(forward.Y < 0 and backward.Y > 0)
	end)

	T.test("steering eases off at speed", function()
		local _, slow = DriveModel.step(Vector3.new(0, 0, -15), LOOK, UP, 1, 1, stats, DT)
		local _, fast = DriveModel.step(Vector3.new(0, 0, -stats.MaxSpeed), LOOK, UP, 1, 1, stats, DT)
		T.truthy(math.abs(fast.Y) < math.abs(slow.Y))
	end)

	T.test("sideways slide is killed at the Grip rate", function()
		local slide = Vector3.new(30, 0, 0) -- pure sideways
		local v = DriveModel.step(slide, LOOK, UP, 0, 0, stats, 0.2)
		T.near(v.X, 30 * math.exp(-stats.Grip * 0.2), 1e-6)
		-- grippier cars shed it faster
		local grippy = DriveModel.step(slide, LOOK, UP, 0, 0, { MaxSpeed = 60, Accel = 40, Turn = 2.5, Grip = 12 }, 0.2)
		T.truthy(math.abs(grippy.X) < math.abs(v.X))
	end)

	T.test("the car levels itself: a tilted car is rolled back toward upright", function()
		-- tilt the car 40 degrees about its forward axis
		local tilted = CFrame.Angles(0, 0, math.rad(40))
		local up = tilted.UpVector
		local startAngle = math.acos(up:Dot(UP))
		T.near(math.deg(startAngle), 40, 0.01)
		for _ = 1, 30 do
			local _, angular = DriveModel.step(Vector3.zero, LOOK, up, 0, 0, stats, DT)
			-- rotate `up` by angular * dt (Rodrigues)
			local w = angular * DT
			local angle = w.Magnitude
			if angle > 0 then
				local axis = w.Unit
				up = up * math.cos(angle) + axis:Cross(up) * math.sin(angle) + axis * axis:Dot(up) * (1 - math.cos(angle))
			end
		end
		local endAngle = math.acos(math.clamp(up:Dot(UP), -1, 1))
		T.truthy(endAngle < startAngle * 0.6, "tilt went from " .. math.deg(startAngle) .. " to " .. math.deg(endAngle) .. " degrees")
	end)

	T.test("an upright car gets no levelling torque", function()
		local _, angular = DriveModel.step(Vector3.new(0, 0, -20), LOOK, UP, 0, 0, stats, DT)
		T.near(angular.X, 0, 1e-9)
		T.near(angular.Z, 0, 1e-9)
	end)

	T.test("a car pointing straight up or down only levels", function()
		local v, angular = DriveModel.step(Vector3.new(1, 2, 3), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), 1, 1, stats, DT)
		T.eq(v, Vector3.new(1, 2, 3))
		T.truthy(angular.Magnitude > 0)
	end)

	T.test("recovery: flipped cars are detected and reset to face the same way", function()
		T.falsy(DriveModel.needsRecovery(UP))
		T.falsy(DriveModel.needsRecovery(Vector3.new(0, 0.7, 0.7)))
		T.truthy(DriveModel.needsRecovery(Vector3.new(0, 0.1, 1)))
		T.truthy(DriveModel.needsRecovery(Vector3.new(0, -1, 0)))
		local facing = Vector3.new(0.6, 0, -0.8)
		local cf = DriveModel.recoveryCFrame(Vector3.new(10, 5, 20), facing)
		T.near(cf.UpVector.Y, 1, 1e-6)
		T.near(cf.LookVector.X, 0.6, 1e-6)
		T.near(cf.LookVector.Z, -0.8, 1e-6)
		T.near(cf.Position.Y, 8, 1e-6, "lifted a little so it lands clear of the ground")
	end)

	T.test("every vehicle can take a street corner at half speed and top speed stays sane", function()
		for _, spec in Config.Vehicles do
			local half = spec.MaxSpeed / 2
			local _, angularHalf = DriveModel.step(Vector3.new(0, 0, -half), LOOK, UP, 0, 1, spec, DT)
			local radiusHalf = half / math.abs(angularHalf.Y)
			T.truthy(radiusHalf < 45, spec.Id .. " turning radius at half speed is " .. radiusHalf)
			local _, angularFull = DriveModel.step(Vector3.new(0, 0, -spec.MaxSpeed), LOOK, UP, 1, 1, spec, DT)
			local radiusFull = spec.MaxSpeed / math.abs(angularFull.Y)
			T.truthy(radiusFull < 110, spec.Id .. " turning radius at top speed is " .. radiusFull)
			T.truthy(radiusFull > radiusHalf, "slower is tighter")
			-- reaches 0 -> 90% of top speed in a reasonable time
			local v = simulate(4, 1, 0, nil, nil, spec)
			T.truthy(v.Magnitude > spec.MaxSpeed * 0.6, spec.Id .. " too slow to accelerate")
		end
	end)

	-- Controller + wheel visuals use real instances and the fake engine --------------------------

	local function drivingWorld()
		local ctx = Mocks.new()
		local player = ctx:newPlayer("Driver", 7)
		ctx.players.LocalPlayer = player
		local character = ctx:spawnCharacter(player, Vector3.new(0, 3, 0))
		local VehicleBuilder = ctx:require("ReplicatedStorage.Shared.VehicleBuilder")
		local model = VehicleBuilder.build("Hatchback")
		model:SetAttribute("OwnerUserId", 7)
		Mocks.setPart(model.PrimaryPart, CFrame.new(0, 1, 0))
		model.Parent = ctx.Workspace
		local humanoid = character.Humanoid
		return ctx, player, model, humanoid
	end

	T.test("controller: drives your own vehicle from the seat's throttle and steering", function()
		local ctx, _, model, humanoid = drivingWorld()
		local Controller = ctx:require("StarterPlayer.StarterPlayerScripts.Client.VehicleController")
		model.PrimaryPart.Anchored = false
		model.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
		Mocks.sit(model.Seat, humanoid)
		model.Seat.ThrottleFloat = 1
		model.Seat.SteerFloat = 0

		for _ = 1, 60 do
			Controller.step(DT)
		end
		local v = model.PrimaryPart.AssemblyLinearVelocity
		T.truthy(-v.Z > 10, "should be moving forward, velocity = " .. tostring(v))
		T.near(model.PrimaryPart.AssemblyAngularVelocity.Y, 0, 1e-6)
	end)

	T.test("controller: ignores parked (anchored) vehicles and other people's vehicles", function()
		local ctx, _, model, humanoid = drivingWorld()
		local Controller = ctx:require("StarterPlayer.StarterPlayerScripts.Client.VehicleController")
		model.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
		Mocks.sit(model.Seat, humanoid)
		model.Seat.ThrottleFloat = 1

		model.PrimaryPart.Anchored = true
		Controller.step(DT)
		T.eq(model.PrimaryPart.AssemblyLinearVelocity, Vector3.zero, "anchored")

		model.PrimaryPart.Anchored = false
		model:SetAttribute("OwnerUserId", 999)
		Controller.step(DT)
		T.eq(model.PrimaryPart.AssemblyLinearVelocity, Vector3.zero, "someone else's car")

		model:SetAttribute("OwnerUserId", 7)
		humanoid = Mocks.leaveSeat(humanoid)
		Controller.step(DT)
		T.eq(model.PrimaryPart.AssemblyLinearVelocity, Vector3.zero, "not seated")
	end)

	T.test("controller: a flipped car is put back on its wheels", function()
		local ctx, _, model, humanoid = drivingWorld()
		local Controller = ctx:require("StarterPlayer.StarterPlayerScripts.Client.VehicleController")
		model.PrimaryPart.Anchored = false
		model.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, -30)
		Mocks.sit(model.Seat, humanoid)
		model.PrimaryPart.CFrame = CFrame.new(5, 2, 5) * CFrame.Angles(0, 0, math.rad(180)) -- upside down
		Controller.step(DT)
		T.near(model.PrimaryPart.CFrame.UpVector.Y, 1, 1e-4)
		T.eq(model.PrimaryPart.AssemblyLinearVelocity, Vector3.zero)
	end)

	T.test("visuals: wheels roll with the vehicle's speed and front wheels steer", function()
		local ctx, _, model = drivingWorld()
		local Visuals = ctx:require("StarterPlayer.StarterPlayerScripts.Client.VehicleVisuals")
		Visuals.track(model)

		model.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, -20) -- driving forward
		model.Seat.SteerFloat = 1
		Visuals.update(0.1)

		local front, rear
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") and d.Name == "Wheel_FL" then
				front = d
			elseif d:IsA("Motor6D") and d.Name == "Wheel_RL" then
				rear = d
			end
		end
		-- forward motion = negative rotation about X (mod 2pi); radius 1.3 -> 20 * 0.1 / 1.3 rad
		local expected = (-(20 * 0.1) / 1.3) % (math.pi * 2)
		local rx = select(1, rear.Transform:ToEulerAnglesXYZ())
		local rearAngle = rx % (math.pi * 2)
		T.near(rearAngle, expected % (math.pi * 2), 1e-3, "rear wheel roll")

		-- the front wheel's axle swings toward +/-Z when steering (rear axle stays along X)
		T.near(front.Transform.RightVector.Z, math.sin(0.45), 1e-3, "front wheel should yaw by the steering angle")
		T.near(rear.Transform.RightVector.Z, 0, 1e-6)
	end)
end
