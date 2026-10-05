--!nocheck
-- Procedural models: geometry sanity checks that stand in for "looking at it".

return function(H)
	local passed, failed = 0, {}
	local function check(name, cond, detail)
		if cond then
			passed += 1
		else
			table.insert(failed, name .. (detail ~= nil and (" -- " .. tostring(detail)) or ""))
		end
	end
	local function section(t)
		print("\n== " .. t)
	end

	local world = H.newWorld({})
	local Seeds = world.requireShared("Seeds")
	local Birds = world.requireShared("Birds")
	local PlantModels = world.requireShared("PlantModels")
	local BirdModel = world.requireShared("BirdModel")
	local CFrame, Vector3 = world.CFrame, world.Vector3

	local function bounds(part)
		local s, c = part.Size, part.CFrame
		local lo, hi
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local p = c * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)
					lo = lo and Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z)) or p
					hi = hi and Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z)) or p
				end
			end
		end
		return lo, hi
	end
	local function isBlob(part)
		return part:FindFirstChildOfClass("SpecialMesh") ~= nil
	end

	-- height of the visible surface of `part` above the horizontal position (x, z), or nil if not above it
	local function surfaceHeight(part, x, z)
		local lo, hi = bounds(part)
		if x < lo.X - 0.01 or x > hi.X + 0.01 or z < lo.Z - 0.01 or z > hi.Z + 0.01 then
			return nil
		end
		if isBlob(part) then
			local cx, cy, cz = (lo.X + hi.X) / 2, (lo.Y + hi.Y) / 2, (lo.Z + hi.Z) / 2
			local hx, hy, hz = (hi.X - lo.X) / 2, (hi.Y - lo.Y) / 2, (hi.Z - lo.Z) / 2
			local k = 1 - ((x - cx) / hx) ^ 2 - ((z - cz) / hz) ^ 2
			if k < 0 then
				return nil
			end
			return cy + hy * math.sqrt(k)
		end
		return hi.Y
	end

	----------------------------------------------------------------------------
	section("Plants")
	----------------------------------------------------------------------------
	for _, seed in Seeds.list do
		local model = PlantModels.build(seed.id, CFrame.new(), false)
		check(seed.id .. " builds", model ~= nil)
		check(seed.id .. " has a root", model.PrimaryPart ~= nil and model.PrimaryPart.Name == "Root")
		local parts, buds, blooms, fx = 0, 0, 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				check(seed.id .. " parts are anchored and non-colliding", d.Anchored == true and d.CanCollide == false)
				if d:GetAttribute("Bud") then
					buds += 1
				end
				if d:GetAttribute("Bloom") then
					blooms += 1
				end
			end
			if d:GetAttribute("BloomFX") then
				fx += 1
			end
		end
		check(seed.id .. " part count is reasonable", parts >= 8 and parts <= 120, parts)
		check(seed.id .. " has a bloomed look", blooms >= 3, blooms)
		check(seed.id .. " has bloom effects", fx >= 1)
		check(seed.id .. " starts unbloomed", model:GetAttribute("Mature") == false)

		-- while growing: bloom parts hidden, bud parts shown, effects off
		local growingOk = true
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Bloom") and d.Transparency ~= 1 then
				growingOk = false
			end
			if d:IsA("BasePart") and d:GetAttribute("Bud") and d.Transparency ~= 0 then
				growingOk = false
			end
			if d:GetAttribute("BloomFX") and d.Enabled ~= false then
				growingOk = false
			end
		end
		check(seed.id .. " growing look hides blooms", growingOk)

		PlantModels.setMature(model, true)
		local matureOk = true
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Bloom") and d.Transparency ~= 0 then
				matureOk = false
			end
			if d:IsA("BasePart") and d:GetAttribute("Bud") and d.Transparency ~= 1 then
				matureOk = false
			end
			if d:GetAttribute("BloomFX") and d.Enabled ~= true then
				matureOk = false
			end
		end
		check(seed.id .. " mature look shows blooms", matureOk)

		-- footprint: neighbours are 13 studs apart, so a plant should stay inside ~14
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		local maxY = 0
		for _, d in model:GetDescendants() do
			if
				d:IsA("BasePart")
				and d.Name ~= "Root"
				and d.Transparency ~= 1
				and d.Name ~= "FXAnchor"
				and d.Name ~= "Shard"
			then
				local lo, hi = bounds(d)
				minX, maxX = math.min(minX, lo.X), math.max(maxX, hi.X)
				minZ, maxZ = math.min(minZ, lo.Z), math.max(maxZ, hi.Z)
				maxY = math.max(maxY, hi.Y)
			end
		end
		print(
			string.format(
				"  %-18s %3d parts, footprint %.1f x %.1f, height %.1f (label at %.1f)",
				seed.name,
				parts,
				maxX - minX,
				maxZ - minZ,
				maxY,
				seed.labelHeight
			)
		)
		check(
			seed.id .. " fits its plot (<= 14 wide)",
			maxX - minX <= 14.2 and maxZ - minZ <= 14.2,
			`{maxX - minX} x {maxZ - minZ}`
		)
		check(
			seed.id .. " label sits at the top of the plant",
			math.abs(maxY - seed.labelHeight) <= 1.2,
			`{maxY} vs {seed.labelHeight}`
		)

		-- every perch must rest on a visible surface of the mature plant
		for i, perch in seed.perches do
			local x, y, z = perch[1], perch[2], perch[3]
			local best
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency ~= 1 and d.Name ~= "Root" then
					local h = surfaceHeight(d, x, z)
					if h and (not best or math.abs(h - y) < math.abs(best - y)) then
						best = h
					end
				end
			end
			check(
				`{seed.id} perch {i} rests on the plant`,
				best ~= nil and math.abs(best - y) <= 0.7,
				`perch y={y}, nearest surface={best}`
			)
		end
		-- perches must not collide with each other (birds are up to ~2.4 studs wide)
		for i = 1, #seed.perches do
			for j = i + 1, #seed.perches do
				local a = Vector3.new(table.unpack(seed.perches[i]))
				local b = Vector3.new(table.unpack(seed.perches[j]))
				check(`{seed.id} perches {i}/{j} are apart`, (a - b).Magnitude >= 3, (a - b).Magnitude)
			end
		end
	end
	check("unknown seed id builds nothing", PlantModels.build("nonsense", CFrame.new(), true) == nil)

	----------------------------------------------------------------------------
	section("Birds")
	----------------------------------------------------------------------------
	local partTotal = 0
	for _, def in Birds.list do
		local rig = BirdModel.build(def)
		check(def.id .. " has two wings", #rig.wings == 2)
		check(
			def.id .. " has a root and a model",
			rig.model.PrimaryPart ~= nil and rig.model.PrimaryPart.Name == "Root"
		)
		check(def.id .. " parts and rest poses line up", #rig.parts == #rig.rest)
		partTotal += #rig.parts

		local lowest, highest = math.huge, -math.huge
		for _, part in rig.parts do
			if part.Name ~= "Root" then
				local lo, hi = bounds(part)
				lowest, highest = math.min(lowest, lo.Y), math.max(highest, hi.Y)
			end
		end
		check(def.id .. " stands on its feet", math.abs(lowest) < 0.06 * def.scale + 0.02, lowest)
		-- a peacock's raised tail fan stands well above its body
		local maxHeight = if Birds.hasTrait(def, "FanTail") then 3.6 else 2.6
		check(
			def.id .. " is roughly the advertised height",
			highest <= maxHeight * def.scale and highest >= 1.5 * def.scale,
			`{highest} (scale {def.scale})`
		)

		-- posing moves the whole bird and flaps the wings
		local target = CFrame.new(10, 5, -3)
		BirdModel.pose(rig, target, 0)
		local body = rig.model.Body
		local expectedBody = target * Vector3.new(0, 0.8 * def.scale, 0.05 * def.scale)
		check(
			def.id .. " follows the pose",
			(body.CFrame.Position - expectedBody).Magnitude < 0.01,
			(body.CFrame.Position - expectedBody).Magnitude
		)
		local folded = rig.model.WingR.CFrame.Position
		BirdModel.pose(rig, target, 1.6)
		local raised = rig.model.WingR.CFrame.Position
		check(
			def.id .. " wing moves when flapping",
			(folded - raised).Magnitude > 0.2 * def.scale,
			(folded - raised).Magnitude
		)
		local mirrorL, mirrorR = rig.model.WingL.CFrame.Position, rig.model.WingR.CFrame.Position
		check(def.id .. " wings mirror each other", math.abs(mirrorL.Y - mirrorR.Y) < 0.01)
		check(def.id .. " has a sensible wing-beat", rig.flapRate > 5 and rig.flapRate < 80, rig.flapRate)

		local sil = BirdModel.build(def, true)
		local dark = true
		for _, part in sil.parts do
			if part.Name ~= "Root" and (part.Color.R > 0.2 or part.Color.G > 0.2) then
				dark = false
			end
		end
		check(def.id .. " silhouette is all dark", dark)
		local fx = 0
		for _, d in sil.model:GetDescendants() do
			if d.ClassName == "PointLight" or d.ClassName == "ParticleEmitter" then
				fx += 1
			end
		end
		check(def.id .. " silhouette has no effects", fx == 0)
	end
	print(string.format("  18 species, %d parts in total (avg %.0f)", partTotal, partTotal / 18))
	local phoenix = BirdModel.build(Birds.get("phoenix"))
	local hasFire, hasLight = false, false
	for _, d in phoenix.model:GetDescendants() do
		if d.ClassName == "ParticleEmitter" then
			hasFire = true
		end
		if d.ClassName == "PointLight" then
			hasLight = true
		end
	end
	check("phoenix burns and glows", hasFire and hasLight)
	local peacock = BirdModel.build(Birds.get("peacock"))
	local feathers = 0
	for _, part in peacock.parts do
		if part.Name == "Feather" then
			feathers += 1
		end
	end
	check("peacock has its fan", feathers == 9, feathers)
	check(
		"hummingbird beats faster than a macaw",
		BirdModel.build(Birds.get("hummingbird")).flapRate > BirdModel.build(Birds.get("macaw")).flapRate * 2
	)

	print(string.format("\n%d checks passed, %d failed", passed, #failed))
	for _, f in failed do
		print("  FAIL: " .. f)
	end
	return #failed == 0
end
