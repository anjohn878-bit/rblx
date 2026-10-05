local Harness = ...
local Illnesses = Harness.require(Harness.Server.Data.Illnesses)
local DoctorLevels = Harness.require(Harness.Shared.Config.DoctorLevels)
local ok = Harness.ok

local function containsAll(haystack, needles)
	for _, needle in needles do
		if not table.find(haystack, needle) then
			return false
		end
	end
	return true
end

-- Every illness needs a unique symptom set, and enough symptoms.
for i, a in Illnesses.List do
	ok(#a.Symptoms >= 3, a.Id .. " has at least 3 symptoms")
	for j, b in Illnesses.List do
		if i < j then
			ok(not (containsAll(a.Symptoms, b.Symptoms) and containsAll(b.Symptoms, a.Symptoms)), a.Id .. " and " .. b.Id .. " have different symptoms")
		end
	end
end

local allRooms = { Laboratory = true, EmergencyRoom = true, Surgery = true, Specialist = true }
local pools = {
	basic = Illnesses.GetRegularPool({}),
	all = Illnesses.GetRegularPool(allRooms),
}
ok(#pools.basic == 10, "10 basic illnesses")
ok(#pools.all > #pools.basic, "rooms unlock more illnesses")
local rarePool = table.clone(pools.all)
for _, illness in Illnesses.ByCategory.Rare do
	table.insert(rarePool, illness)
end

local rng = Harness.Random.new(1234)
local shortCases, totalCases, badCases = 0, 0, 0
for _, difficulty in DoctorLevels.Difficulties do
	for poolName, pool in { basic = pools.basic, all = pools.all, rare = rarePool } do
		for _, illness in pool do
			for _ = 1, 25 do
				local shown, options = Illnesses.BuildCase(illness, pool, difficulty.Symptoms, difficulty.Choices, rng)
				totalCases += 1
				local correctCount, ambiguous, duplicates = 0, false, false
				local seen = {}
				for _, option in options do
					if seen[option.Id] then
						duplicates = true
					end
					seen[option.Id] = true
					if option.Id == illness.Id then
						correctCount += 1
					elseif containsAll(option.Symptoms, shown) then
						ambiguous = true
					end
				end
				local valid = correctCount == 1 and not ambiguous and not duplicates and containsAll(illness.Symptoms, shown) and #shown >= 2 and #options <= difficulty.Choices
				if not valid then
					badCases += 1
					print("bad case", illness.Id, poolName, difficulty.Choices)
				end
				if #options < difficulty.Choices then
					shortCases += 1
				end
			end
		end
	end
end
ok(badCases == 0, "all generated cases are solvable and unambiguous")
print(string.format("cases: %d, with fewer options than requested: %d", totalCases, shortCases))
ok(shortCases / totalCases < 0.02, "cases almost always get the full option count")
