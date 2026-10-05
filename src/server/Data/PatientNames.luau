--[[
	PatientNames
	Random first names + last initials for patients.
]]

local FIRST = {
	"Alex", "Sam", "Jordan", "Taylor", "Riley", "Casey", "Jamie", "Morgan", "Charlie", "Avery",
	"Quinn", "Max", "Leo", "Mia", "Zoe", "Noah", "Emma", "Liam", "Olivia", "Ava",
	"Ethan", "Lily", "Lucas", "Chloe", "Mason", "Ella", "Oscar", "Ruby", "Finn", "Ivy",
	"Kai", "Nora", "Theo", "Luna", "Eli", "Maya", "Jack", "Grace", "Owen", "Hazel",
	"Milo", "Aria", "Felix", "Isla", "Hugo", "Ada", "Leon", "Mila", "Ezra", "Rosa",
	"Omar", "Priya", "Kenji", "Amara", "Diego", "Sofia", "Yusuf", "Lena", "Ravi", "Nia",
}

local VIP = {
	"Captain Sparkle", "DJ Blox", "Sir Bricksworth", "Lady Neon", "Pro Gamer Zed",
	"Rockstar Ricky", "Duchess Pixel", "Mayor Builderman", "Chef Noob", "Astronaut Ava",
}

local LETTERS = "ABCDEFGHIJKLMNOPRSTVW"

local PatientNames = {}

function PatientNames.Random(rng: Random): string
	local first = FIRST[rng:NextInteger(1, #FIRST)]
	local index = rng:NextInteger(1, #LETTERS)
	return first .. " " .. LETTERS:sub(index, index) .. "."
end

function PatientNames.RandomVIP(rng: Random): string
	return VIP[rng:NextInteger(1, #VIP)]
end

return PatientNames
