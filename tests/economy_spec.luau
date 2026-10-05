local Harness = ...
local Config = Harness.Shared.Config
local Economy = Harness.require(Harness.Shared.Economy)
local HospitalLevels = Harness.require(Config.HospitalLevels)
local DoctorLevels = Harness.require(Config.DoctorLevels)
local AutoDoctors = Harness.require(Config.AutoDoctors)
local Rooms = Harness.require(Config.Rooms)
local eq, ok = Harness.eq, Harness.ok

-- Level table sanity
for i, level in HospitalLevels.Levels do
	eq(level.Level, i, "level index " .. i)
	ok(level.ExamRooms * 12 + 16 <= level.Width, "exam rooms fit in width at level " .. i)
	ok(level.Capacity >= level.ExamRooms, "capacity >= exam rooms at level " .. i)
	if i > 1 then
		local prev = HospitalLevels.Levels[i - 1]
		ok(level.Cost > prev.Cost, "cost increases at level " .. i)
		ok(level.RewardMultiplier > prev.RewardMultiplier, "reward mult increases at level " .. i)
		ok(level.SpawnInterval < prev.SpawnInterval, "spawn gets faster at level " .. i)
		ok(level.Capacity > prev.Capacity, "capacity grows at level " .. i)
	end
end
eq(HospitalLevels.Levels[2].Cost, 500, "level 2 costs $500")
eq(HospitalLevels.Levels[1].Capacity, 3, "level 1 capacity 3")
eq(HospitalLevels.Levels[2].Capacity, 6, "level 2 capacity 6")
eq(HospitalLevels.Levels[3].Capacity, 10, "level 3 capacity 10")
eq(HospitalLevels.Levels[4].Capacity, 15, "level 4 capacity 15")

-- Back-wing rooms fit inside the building for every level
for _, level in HospitalLevels.Levels do
	local count = 0
	for _, room in Rooms.List do
		if room.Location == "Back" and room.RequiredLevel <= level.Level then
			count += 1
		end
	end
	ok(count * 20 <= level.Width - 16, "back rooms fit at level " .. level.Level)
end

-- Prices
eq(Economy.HireCost(0), 1000, "first doctor costs $1,000")
ok(Economy.HireCost(1) > Economy.HireCost(0), "hire cost grows")
eq(Economy.DoctorUpgradeCost(1), 5000, "Auto Doctor II costs $5,000")
eq(Economy.DoctorUpgradeCost(2), 20000, "Auto Doctor III costs $20,000")
eq(Economy.DoctorUpgradeCost(AutoDoctors.MaxTier), nil, "no upgrade past max tier")
eq(Economy.ImprovementCost("Marketing", 0), 250, "marketing lv1")
eq(Economy.ImprovementCost("Marketing", 10), nil, "marketing maxed")
eq(Economy.NicePrice(1234), 1200, "NicePrice(1234)")
eq(Economy.NicePrice(98765), 99000, "NicePrice(98765)")

local data = { HospitalLevel = 1, Rooms = {}, Doctors = {}, Improvements = {} }
eq(Economy.HospitalValue(data), 0, "fresh hospital value")
eq(Economy.SpawnInterval(data), 7, "base spawn interval")
eq(Economy.IncomeMultiplier(data), 1, "base income multiplier")
eq(Economy.TreatTime(1, data), 15, "tier 1 treat time")
local upgraded = { HospitalLevel = 3, Rooms = { Pharmacy = true }, Doctors = { 2, 1 }, Improvements = { Marketing = 2, Equipment = 3, Training = 1 } }
ok(Economy.SpawnInterval(upgraded) < 5, "marketing speeds up spawning")
ok(math.abs(Economy.IncomeMultiplier(upgraded) - 2.25 * 1.3) < 1e-9, "equipment adds 10%/level")
ok(math.abs(Economy.TreatTime(2, upgraded) - 10 * 0.94) < 1e-9, "training speeds doctors")
eq(Economy.PharmacyBonus(upgraded), 0.25, "pharmacy bonus")
eq(Economy.HospitalValue(upgraded), 500 + 2000 + 750 + 1000 + 5000 + 1600 + 250 + 480 + 400 + 680 + 1200 + 1500, "hospital value sums purchases")

-- Doctor levels
local level, into, need = DoctorLevels.FromTotalXP(0)
eq(level, 1, "xp 0 -> level 1")
eq(into, 0, "xp 0 into")
eq(need, 50, "level 1 needs 50xp")
level = DoctorLevels.FromTotalXP(50)
eq(level, 2, "xp 50 -> level 2")
eq(DoctorLevels.GetDifficulty(1).Choices, 3, "level 1 has 3 choices")
eq(DoctorLevels.GetDifficulty(1).Symptoms, 2, "level 1 shows 2 symptoms")
eq(DoctorLevels.GetDifficulty(12).Choices, 6, "level 12 has 6 choices")
