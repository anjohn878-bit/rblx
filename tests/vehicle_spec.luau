local roblox = require("@lune/roblox")
local Fixture = require("./fixture")

local function extents(model)
	local minX, minY, minZ, maxX, maxY, maxZ = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local x0, x1, y0, y1, z0, z1 = nil, nil, nil, nil, nil, nil
			local p, s = d.CFrame.Position, d.Size
			x0, x1, y0, y1, z0, z1 = p.X - s.X / 2, p.X + s.X / 2, p.Y - s.Y / 2, p.Y + s.Y / 2, p.Z - s.Z / 2, p.Z + s.Z / 2
			minX, maxX = math.min(minX, x0), math.max(maxX, x1)
			minY, maxY = math.min(minY, y0), math.max(maxY, y1)
			minZ, maxZ = math.min(minZ, z0), math.max(maxZ, z1)
		end
	end
	return { X = maxX - minX, Y = maxY - minY, Z = maxZ - minZ }
end

local function aabb(part)
	local p, s = part.CFrame.Position, part.Size
	return p.X - s.X / 2, p.X + s.X / 2, p.Y - s.Y / 2, p.Y + s.Y / 2, p.Z - s.Z / 2, p.Z + s.Z / 2
end

return function(T)
	local fx = Fixture.new()
	local Config = fx:require("ReplicatedStorage.Shared.Config")
	local VehicleBuilder = fx:require("ReplicatedStorage.Shared.VehicleBuilder")

	for _, spec in Config.Vehicles do
		local id = spec.Id
		local model = VehicleBuilder.build(id)
		local chassis = model.PrimaryPart
		local hh = model:GetAttribute("HullHalfHeight")

		T.test(id .. ": has a chassis, one VehicleSeat, and carries its stats", function()
			T.eq(model.Name, id)
			T.truthy(chassis and chassis.Name == "Chassis")
			T.eq(chassis.Transparency, 1)
			T.truthy(chassis.CanCollide)
			local seats = 0
			for _, d in model:GetChildren() do
				if d:IsA("VehicleSeat") then
					seats += 1
					T.eq(d.Name, "Seat")
				end
			end
			T.eq(seats, 1)
			T.eq(model:GetAttribute("VehicleId"), id)
			T.eq(model:GetAttribute("MaxSpeed"), spec.MaxSpeed)
			T.eq(model:GetAttribute("Accel"), spec.Accel)
			T.eq(model:GetAttribute("Turn"), spec.Turn)
			T.eq(model:GetAttribute("Grip"), spec.Grip)
			T.truthy(hh and hh > 0)
			T.truthy(model:GetAttribute("WheelRadius") > 0)
		end)

		T.test(id .. ": only the chassis collides, and only the chassis has mass", function()
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d ~= chassis then
					T.falsy(d.CanCollide, d.Name .. " must not collide")
					T.truthy(d.Massless, d.Name .. " must be massless")
					T.falsy(d.Anchored, d.Name .. " must not be anchored")
				end
			end
		end)

		T.test(id .. ": every part is attached to the chassis (weld or wheel joint)", function()
			local connected = { [chassis] = true }
			local changed = true
			local joints = {}
			for _, d in model:GetDescendants() do
				if d:IsA("WeldConstraint") then
					table.insert(joints, { d.Part0, d.Part1 })
				elseif d:IsA("Motor6D") then
					table.insert(joints, { d.Part0, d.Part1 })
				end
			end
			while changed do
				changed = false
				for _, j in joints do
					if connected[j[1]] and not connected[j[2]] then
						connected[j[2]] = true
						changed = true
					elseif connected[j[2]] and not connected[j[1]] then
						connected[j[1]] = true
						changed = true
					end
				end
			end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					T.truthy(connected[d], d.Name .. " is not joined to the chassis")
				end
			end
		end)

		T.test(id .. ": wheels touch the ground plane and nothing hangs below it", function()
			local groundY = -hh
			local wheels = 0
			for _, d in model:GetDescendants() do
				if d:IsA("Motor6D") then
					wheels += 1
					local wheel = d.Part1
					T.eq(wheel.Shape, roblox.Enum.PartType.Cylinder)
					local _, _, minY = aabb(wheel)
					T.near(minY, groundY + 0.02, 0.01, d.Name .. " should rest on the ground")
					T.near(wheel.Size.Y, wheel.Size.Z, 1e-3, d.Name .. " must be round")
					T.near(wheel.Size.Y / 2, d:GetAttribute("Radius"), 1e-3)
					T.near((d.C0.Position - wheel.CFrame.Position).Magnitude, 0, 1e-3, "C0 must place the wheel at its own position")
					T.eq(typeof(d:GetAttribute("Front")), "boolean")
				end
			end
			T.eq(wheels, id == "Scooter" and 2 or 4)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d ~= chassis then
					local _, _, minY = aabb(d)
					T.truthy(minY >= groundY - 0.001, d.Name .. " pokes below the ground (" .. minY .. " < " .. groundY .. ")")
				end
			end
			-- hull bottom is the ground
			local _, _, hullMinY = aabb(chassis)
			T.near(hullMinY, groundY, 1e-3)
		end)

		T.test(id .. ": the driver fits (head room above the seat, seat inside the footprint)", function()
			local seat = model.Seat
			local seatTop = seat.CFrame.Position.Y + seat.Size.Y / 2
			local roof = model:FindFirstChild("Roof")
			if roof then
				local roofBottom = roof.CFrame.Position.Y - roof.Size.Y / 2
				T.truthy(roofBottom - seatTop >= 4.0, "only " .. (roofBottom - seatTop) .. " studs of head room")
			end
			local minX, maxX, _, _, minZ, maxZ = aabb(chassis)
			T.truthy(seat.CFrame.Position.X > minX and seat.CFrame.Position.X < maxX)
			T.truthy(seat.CFrame.Position.Z > minZ and seat.CFrame.Position.Z < maxZ)
			-- seat is above the hull so the rider never sits inside the collision box
			local _, _, _, hullTop = aabb(chassis)
			T.truthy(seatTop > hullTop)
		end)

		T.test(id .. ": front of the vehicle points down -Z (lights at the front, tail lights at the back)", function()
			local head, tail = model:FindFirstChild("Headlight"), model:FindFirstChild("Taillight")
			T.truthy(head and tail)
			T.truthy(head.CFrame.Position.Z < 0 and tail.CFrame.Position.Z > 0)
			-- the seat faces forward, so the first wheel pair (front) is at negative z
			for _, d in model:GetDescendants() do
				if d:IsA("Motor6D") and d:GetAttribute("Front") then
					T.truthy(d.C0.Position.Z < 0, d.Name .. " is flagged Front but sits at the back")
				elseif d:IsA("Motor6D") then
					T.truthy(d.C0.Position.Z > 0, d.Name .. " is flagged rear but sits at the front")
				end
			end
		end)

		T.test(id .. ": model size is plausible for a road vehicle", function()
			local size = extents(model)
			T.truthy(size.Z > size.X, "longer than wide")
			T.truthy(size.Z < Config.World.RoadWidth / 2, "must fit in one lane (" .. size.Z .. ")")
			T.truthy(size.X < Config.World.RoadWidth / 3, "must fit in one lane (width " .. size.X .. ")")
		end)
	end

	T.test("build rejects unknown vehicles", function()
		T.throws(function()
			VehicleBuilder.build("Hovercraft")
		end, "Unknown vehicle")
	end)

	T.test("each build returns a fresh independent model", function()
		local a, b = VehicleBuilder.build("Hatchback"), VehicleBuilder.build("Hatchback")
		T.truthy(a ~= b)
		T.truthy(a.PrimaryPart ~= b.PrimaryPart)
	end)
end
