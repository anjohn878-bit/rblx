--[[
	Rarities
	Rolled for every patient. Rare+ patients glow, are announced, may carry a
	quirky "rare illness" and pay a lot more.
]]

export type Rarity = {
	Id: string,
	Name: string,
	Weight: number,
	Multiplier: number,
	XP: number,
	Color: Color3,
	Stars: number,
	RareIllnessChance: number,
	Announce: boolean,
}

local List: { Rarity } = {
	{
		Id = "Common",
		Name = "Common",
		Weight = 62,
		Multiplier = 1,
		XP = 1,
		Color = Color3.fromRGB(235, 235, 235),
		Stars = 0,
		RareIllnessChance = 0,
		Announce = false,
	},
	{
		Id = "Uncommon",
		Name = "Uncommon",
		Weight = 25,
		Multiplier = 1.5,
		XP = 1.5,
		Color = Color3.fromRGB(100, 220, 110),
		Stars = 1,
		RareIllnessChance = 0,
		Announce = false,
	},
	{
		Id = "Rare",
		Name = "Rare",
		Weight = 9,
		Multiplier = 2.5,
		XP = 3,
		Color = Color3.fromRGB(70, 160, 255),
		Stars = 2,
		RareIllnessChance = 0.4,
		Announce = true,
	},
	{
		Id = "Epic",
		Name = "Epic",
		Weight = 3.2,
		Multiplier = 5,
		XP = 6,
		Color = Color3.fromRGB(190, 90, 255),
		Stars = 3,
		RareIllnessChance = 0.7,
		Announce = true,
	},
	{
		Id = "Legendary",
		Name = "Legendary",
		Weight = 0.8,
		Multiplier = 12,
		XP = 15,
		Color = Color3.fromRGB(255, 196, 40),
		Stars = 4,
		RareIllnessChance = 1,
		Announce = true,
	},
}

local byId: { [string]: Rarity } = {}
for _, rarity in List do
	byId[rarity.Id] = rarity
end

return {
	List = List,
	ById = byId,
}
