-- Rarity tiers shared by seeds and birds.

local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- PetPoints: how strong a pet's perk is
-- BreedTime: seconds for an egg to hatch
-- GrowUpTime: seconds for a baby to become an adult
Rarities.Info = {
	Common = { Rank = 1, Color = Color3.fromRGB(190, 190, 190), PetPoints = 1, BreedTime = 120, GrowUpTime = 180 },
	Uncommon = { Rank = 2, Color = Color3.fromRGB(95, 205, 95), PetPoints = 2, BreedTime = 240, GrowUpTime = 300 },
	Rare = { Rank = 3, Color = Color3.fromRGB(70, 150, 255), PetPoints = 3, BreedTime = 480, GrowUpTime = 600 },
	Epic = { Rank = 4, Color = Color3.fromRGB(175, 95, 255), PetPoints = 5, BreedTime = 720, GrowUpTime = 900 },
	Legendary = { Rank = 5, Color = Color3.fromRGB(255, 190, 40), PetPoints = 8, BreedTime = 1200, GrowUpTime = 1500 },
	Mythic = { Rank = 6, Color = Color3.fromRGB(255, 70, 110), PetPoints = 12, BreedTime = 1800, GrowUpTime = 2400 },
}

function Rarities.Color(rarity)
	local info = Rarities.Info[rarity]
	return info and info.Color or Color3.new(1, 1, 1)
end

function Rarities.Rank(rarity)
	local info = Rarities.Info[rarity]
	return info and info.Rank or 0
end

return Rarities
