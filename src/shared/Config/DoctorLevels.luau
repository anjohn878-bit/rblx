--[[
	DoctorLevels
	The player's personal doctor level. XP comes from diagnosing patients
	yourself. Higher levels give harder (more choices) but better-paying cases.
]]

export type Difficulty = {
	MinLevel: number,
	Symptoms: number,
	Choices: number,
	Bonus: number,
	Label: string,
}

local Difficulties: { Difficulty } = {
	{ MinLevel = 1, Symptoms = 2, Choices = 3, Bonus = 1, Label = "Trainee" },
	{ MinLevel = 3, Symptoms = 3, Choices = 4, Bonus = 1.15, Label = "Junior Doctor" },
	{ MinLevel = 6, Symptoms = 3, Choices = 5, Bonus = 1.3, Label = "Doctor" },
	{ MinLevel = 10, Symptoms = 4, Choices = 6, Bonus = 1.5, Label = "Senior Doctor" },
	{ MinLevel = 20, Symptoms = 4, Choices = 6, Bonus = 1.8, Label = "Chief of Medicine" },
}

local DoctorLevels = {
	MaxLevel = 50,
	BaseXP = 10, -- XP for one correct Common diagnosis (before multipliers)
	RewardBonusPerLevel = 0.05, -- +5% manual income per doctor level
}

function DoctorLevels.XPToNext(level: number): number
	return math.floor(50 * level ^ 1.4)
end

-- Returns level, xpIntoLevel, xpNeededForNext
function DoctorLevels.FromTotalXP(totalXP: number): (number, number, number)
	local level = 1
	local remaining = totalXP
	while level < DoctorLevels.MaxLevel do
		local need = DoctorLevels.XPToNext(level)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return level, 0, 0
end

function DoctorLevels.GetDifficulty(level: number): Difficulty
	local result = Difficulties[1]
	for _, difficulty in Difficulties do
		if level >= difficulty.MinLevel then
			result = difficulty
		end
	end
	return result
end

DoctorLevels.Difficulties = Difficulties

return DoctorLevels
