--[[
	Economy
	Pure formulas shared by server (authoritative) and client (display only).
	Every function takes plain data so the client can preview prices with
	exactly the same maths the server uses to validate purchases.
]]

local Config = script.Parent:WaitForChild("Config")
local AutoDoctors = require(Config:WaitForChild("AutoDoctors"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local HospitalLevels = require(Config:WaitForChild("HospitalLevels"))
local Improvements = require(Config:WaitForChild("Improvements"))
local Rooms = require(Config:WaitForChild("Rooms"))

export type EconomyData = {
	HospitalLevel: number,
	Rooms: { [string]: boolean },
	Doctors: { number },
	Improvements: { [string]: number },
}

local Economy = {}

-- Rounds prices to "nice" numbers (2 significant figures above 1,000).
function Economy.NicePrice(value: number): number
	if value < 100 then
		return math.floor(value + 0.5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(value)) - 1)
	return math.floor(value / magnitude + 0.5) * magnitude
end

function Economy.HireCost(doctorsOwned: number): number
	return Economy.NicePrice(AutoDoctors.HireBaseCost * AutoDoctors.HireCostGrowth ^ doctorsOwned)
end

-- Cost to upgrade a doctor that is currently `currentTier`; nil when maxed.
function Economy.DoctorUpgradeCost(currentTier: number): number?
	local nextTier = AutoDoctors.Tiers[currentTier + 1]
	if not nextTier then
		return nil
	end
	return nextTier.UpgradeCost
end

function Economy.ImprovementCost(id: string, currentLevel: number): number?
	local item = Improvements.ById[id]
	if not item or currentLevel >= item.MaxLevel then
		return nil
	end
	return Economy.NicePrice(item.BaseCost * item.Growth ^ currentLevel)
end

function Economy.ImprovementLevel(data: EconomyData, id: string): number
	return (data.Improvements and data.Improvements[id]) or 0
end

function Economy.SpawnInterval(data: EconomyData): number
	local level = HospitalLevels.Get(data.HospitalLevel)
	local marketing = Economy.ImprovementLevel(data, "Marketing")
	local interval = level.SpawnInterval * (1 - Improvements.ById.Marketing.PerLevel) ^ marketing
	if data.Rooms and data.Rooms.ChildrensWard then
		interval *= 0.85
	end
	return math.max(interval, 0.75)
end

function Economy.TreatTime(tier: number, data: EconomyData): number
	local tierInfo = AutoDoctors.Tiers[math.clamp(tier, 1, AutoDoctors.MaxTier)]
	local training = Economy.ImprovementLevel(data, "Training")
	local factor = math.max(1 - Improvements.ById.Training.PerLevel * training, 0.35)
	return tierInfo.TreatTime * factor
end

-- Multiplier applied to every patient payment (manual or automatic).
function Economy.IncomeMultiplier(data: EconomyData): number
	local level = HospitalLevels.Get(data.HospitalLevel)
	local equipment = Economy.ImprovementLevel(data, "Equipment")
	return level.RewardMultiplier * (1 + Improvements.ById.Equipment.PerLevel * equipment)
end

function Economy.PharmacyBonus(data: EconomyData): number
	if data.Rooms and data.Rooms.Pharmacy then
		return GameConfig.PharmacyBonus
	end
	return 0
end

-- Total money invested into the hospital (shown as "Hospital Value").
function Economy.HospitalValue(data: EconomyData): number
	local value = 0
	for levelIndex = 2, data.HospitalLevel do
		value += HospitalLevels.Get(levelIndex).Cost
	end
	for id, owned in data.Rooms or {} do
		local room = Rooms.ById[id]
		if owned and room then
			value += room.Cost
		end
	end
	for index, tier in data.Doctors or {} do
		value += Economy.HireCost(index - 1)
		for t = 2, tier do
			value += AutoDoctors.Tiers[t].UpgradeCost
		end
	end
	for _, item in Improvements.List do
		for lvl = 0, Economy.ImprovementLevel(data, item.Id) - 1 do
			value += Economy.ImprovementCost(item.Id, lvl) or 0
		end
	end
	return value
end

return Economy
