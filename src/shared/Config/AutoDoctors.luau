--[[
	AutoDoctors
	Hired doctors staff one exam room each (doctor N works in exam room N),
	so the number of doctors is capped by the hospital's exam rooms.

	Tier 1 is bought with the "Hire" button (price grows with every doctor
	you already own). Higher tiers are upgrades for a single doctor.
]]

export type Tier = {
	Tier: number,
	Name: string,
	Short: string,
	TreatTime: number,
	UpgradeCost: number, -- cost to upgrade *into* this tier (unused for tier 1)
	RequiredLevel: number,
	Coat: Color3,
	Scrubs: Color3,
	Accent: Color3,
	Robot: boolean,
}

local Tiers: { Tier } = {
	{
		Tier = 1,
		Name = "Auto Doctor I",
		Short = "I",
		TreatTime = 15,
		UpgradeCost = 0,
		RequiredLevel = 1,
		Coat = Color3.fromRGB(245, 245, 245),
		Scrubs = Color3.fromRGB(110, 200, 130),
		Accent = Color3.fromRGB(110, 200, 130),
		Robot = false,
	},
	{
		Tier = 2,
		Name = "Auto Doctor II",
		Short = "II",
		TreatTime = 10,
		UpgradeCost = 5000,
		RequiredLevel = 2,
		Coat = Color3.fromRGB(245, 245, 245),
		Scrubs = Color3.fromRGB(80, 150, 240),
		Accent = Color3.fromRGB(80, 150, 240),
		Robot = false,
	},
	{
		Tier = 3,
		Name = "Auto Doctor III",
		Short = "III",
		TreatTime = 6,
		UpgradeCost = 20000,
		RequiredLevel = 3,
		Coat = Color3.fromRGB(245, 245, 245),
		Scrubs = Color3.fromRGB(150, 90, 230),
		Accent = Color3.fromRGB(150, 90, 230),
		Robot = false,
	},
	{
		Tier = 4,
		Name = "Specialist Doctor",
		Short = "IV",
		TreatTime = 4,
		UpgradeCost = 75000,
		RequiredLevel = 4,
		Coat = Color3.fromRGB(60, 190, 190),
		Scrubs = Color3.fromRGB(30, 60, 90),
		Accent = Color3.fromRGB(255, 200, 60),
		Robot = false,
	},
	{
		Tier = 5,
		Name = "Robo-Doc 3000",
		Short = "V",
		TreatTime = 2.5,
		UpgradeCost = 300000,
		RequiredLevel = 6,
		Coat = Color3.fromRGB(170, 180, 195),
		Scrubs = Color3.fromRGB(70, 80, 100),
		Accent = Color3.fromRGB(0, 230, 255),
		Robot = true,
	},
}

return {
	Tiers = Tiers,
	MaxTier = #Tiers,
	HireBaseCost = 1000,
	HireCostGrowth = 1.6,
}
