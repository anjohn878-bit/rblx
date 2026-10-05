--[[
	Rough economy pacing simulation (not a unit test). Models an active
	player who buys whatever is affordable, and prints when each hospital
	level is reached. Useful when tuning HospitalLevels / AutoDoctors.
]]
local Harness = ...
local Config = Harness.Shared.Config
local Economy = Harness.require(Harness.Shared.Economy)
local HospitalLevels = Harness.require(Config.HospitalLevels)
local AutoDoctors = Harness.require(Config.AutoDoctors)
local Rooms = Harness.require(Config.Rooms)
local Improvements = Harness.require(Config.Improvements)
local GameConfig = Harness.require(Config.GameConfig)
local Illnesses = Harness.require(Harness.Server.Data.Illnesses)
local Format = Harness.require(Harness.Shared.Util.Format)

local data = { HospitalLevel = 1, Rooms = {}, Doctors = {}, Improvements = {}, Money = 0 }
local AVG_RARITY = 1.48
local PLAYER_SECONDS_PER_PATIENT = 10
local PLAYER_ACTIVITY = 0.7
local TURNOVER = 6

local function avgBase()
	local pool = Illnesses.GetRegularPool(data.Rooms)
	local total = 0
	for _, illness in pool do
		total += illness.Reward
	end
	local base = total / #pool
	local kind = 1
	if data.Rooms.EmergencyRoom then
		kind += GameConfig.EmergencyChance * (GameConfig.EmergencyMultiplier - 1)
	end
	if data.Rooms.VIP then
		kind += GameConfig.VIPChance * (GameConfig.VIPMultiplier - 1)
	end
	return base * kind
end

local function tryBuy(): boolean
	local level = HospitalLevels.Get(data.HospitalLevel)
	local nextLevel = HospitalLevels.GetNext(data.HospitalLevel)
	local options = {}
	if nextLevel then
		table.insert(options, { Cost = nextLevel.Cost, Priority = 0, Apply = function()
			data.HospitalLevel += 1
		end })
	end
	for _, room in Rooms.List do
		if not data.Rooms[room.Id] and data.HospitalLevel >= room.RequiredLevel then
			table.insert(options, { Cost = room.Cost, Priority = 1, Apply = function()
				data.Rooms[room.Id] = true
			end })
		end
	end
	if #data.Doctors < level.ExamRooms then
		table.insert(options, { Cost = Economy.HireCost(#data.Doctors), Priority = 1, Apply = function()
			table.insert(data.Doctors, 1)
		end })
	end
	for slot, tier in data.Doctors do
		local nextTier = AutoDoctors.Tiers[tier + 1]
		if nextTier and data.HospitalLevel >= nextTier.RequiredLevel then
			table.insert(options, { Cost = nextTier.UpgradeCost, Priority = 2, Apply = function()
				data.Doctors[slot] += 1
			end })
		end
	end
	for _, item in Improvements.List do
		local cost = Economy.ImprovementCost(item.Id, Economy.ImprovementLevel(data, item.Id))
		if cost then
			table.insert(options, { Cost = cost, Priority = 2, Apply = function()
				data.Improvements[item.Id] = Economy.ImprovementLevel(data, item.Id) + 1
			end })
		end
	end
	table.sort(options, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority < b.Priority
		end
		return a.Cost < b.Cost
	end)
	for _, option in options do
		if option.Cost <= data.Money then
			data.Money -= option.Cost
			option.Apply()
			return true
		end
	end
	return false
end

local t = 0
local reachedAt = { [1] = 0 }
while data.HospitalLevel < HospitalLevels.MaxLevel and t < 6 * 3600 do
	local level = HospitalLevels.Get(data.HospitalLevel)
	local arrivals = 1 / Economy.SpawnInterval(data)
	local doctorRate = 0
	for _, tier in data.Doctors do
		doctorRate += 1 / (Economy.TreatTime(tier, data) + TURNOVER)
	end
	local freeRooms = level.ExamRooms - #data.Doctors
	local playerRate = if freeRooms > 0 then PLAYER_ACTIVITY / PLAYER_SECONDS_PER_PATIENT else PLAYER_ACTIVITY / (PLAYER_SECONDS_PER_PATIENT * 2)
	local autoShare = math.min(doctorRate, arrivals)
	local manualShare = math.min(playerRate, math.max(arrivals - autoShare, 0) + 0.02)
	local base = avgBase() * Economy.IncomeMultiplier(data) * AVG_RARITY * (1 + Economy.PharmacyBonus(data))
	local manualMult = GameConfig.ManualCareBonus * 1.25 * 1.1
	data.Money += (autoShare * base + manualShare * base * manualMult)
	while tryBuy() do
		if data.HospitalLevel > #reachedAt then
			reachedAt[data.HospitalLevel] = t
		end
	end
	t += 1
end

for level, at in reachedAt do
	print(string.format("Lv %d %-26s reached at %s", level, HospitalLevels.Get(level).Name, Format.Time(at)))
end
