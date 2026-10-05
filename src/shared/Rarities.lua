-- Rarity tiers shared by seeds and birds.

local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Rarities.Info = {
	Common = { Rank = 1, Color = Color3.fromRGB(190, 190, 190) },
	Uncommon = { Rank = 2, Color = Color3.fromRGB(95, 205, 95) },
	Rare = { Rank = 3, Color = Color3.fromRGB(70, 150, 255) },
	Epic = { Rank = 4, Color = Color3.fromRGB(175, 95, 255) },
	Legendary = { Rank = 5, Color = Color3.fromRGB(255, 190, 40) },
	Mythic = { Rank = 6, Color = Color3.fromRGB(255, 70, 110) },
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
