--[[
	Catalog
	Every cosmetic in the game. All items are built from primitive parts and
	colours, so no external assets are needed. Cosmetics never change gameplay.

	Item fields:
		Id, Name, Category, Price, Color (Color3), Secondary (Color3?), Style (string?),
		RequiredTier (reputation tier name, optional), Default (owned by everyone)
]]

local Catalog = {}

Catalog.Categories = { "Shirt", "Shorts", "Socks", "Boots", "Headwear", "Trail" }

local items = {
	-- Shirts
	{ Id = "shirt_white", Name = "Plain White Tee", Category = "Shirt", Price = 0, Color = Color3.fromRGB(235, 235, 235), Default = true },
	{ Id = "shirt_charcoal", Name = "Charcoal Tee", Category = "Shirt", Price = 120, Color = Color3.fromRGB(52, 54, 60) },
	{ Id = "shirt_royal", Name = "Royal Training Top", Category = "Shirt", Price = 200, Color = Color3.fromRGB(38, 76, 196) },
	{ Id = "shirt_crimson", Name = "Crimson Jersey", Category = "Shirt", Price = 200, Color = Color3.fromRGB(176, 26, 40) },
	{ Id = "shirt_mint", Name = "Mint Hoodie", Category = "Shirt", Price = 350, Color = Color3.fromRGB(140, 230, 190) },
	{ Id = "shirt_sunset", Name = "Sunset Windbreaker", Category = "Shirt", Price = 500, Color = Color3.fromRGB(255, 142, 60) },
	{ Id = "shirt_lilac", Name = "Lilac Drill Top", Category = "Shirt", Price = 450, Color = Color3.fromRGB(176, 150, 255), RequiredTier = "Local" },
	{ Id = "shirt_gold", Name = "Gold Thread Jersey", Category = "Shirt", Price = 2500, Color = Color3.fromRGB(230, 184, 60), RequiredTier = "Star" },

	-- Shorts
	{ Id = "shorts_black", Name = "Black Shorts", Category = "Shorts", Price = 0, Color = Color3.fromRGB(28, 28, 32), Default = true },
	{ Id = "shorts_white", Name = "White Shorts", Category = "Shorts", Price = 100, Color = Color3.fromRGB(240, 240, 240) },
	{ Id = "shorts_navy", Name = "Navy Shorts", Category = "Shorts", Price = 150, Color = Color3.fromRGB(24, 34, 80) },
	{ Id = "shorts_camo", Name = "Olive Cargo", Category = "Shorts", Price = 300, Color = Color3.fromRGB(86, 96, 54) },
	{ Id = "shorts_red", Name = "Track Reds", Category = "Shorts", Price = 300, Color = Color3.fromRGB(190, 30, 40), RequiredTier = "Local" },

	-- Socks
	{ Id = "socks_white", Name = "White Socks", Category = "Socks", Price = 0, Color = Color3.fromRGB(245, 245, 245), Default = true },
	{ Id = "socks_black", Name = "Black Socks", Category = "Socks", Price = 60, Color = Color3.fromRGB(20, 20, 22) },
	{ Id = "socks_teal", Name = "Teal Socks", Category = "Socks", Price = 120, Color = Color3.fromRGB(30, 170, 170) },
	{ Id = "socks_pink", Name = "Hot Pink Socks", Category = "Socks", Price = 180, Color = Color3.fromRGB(255, 80, 170) },

	-- Boots
	{ Id = "boots_black", Name = "Classic Blacks", Category = "Boots", Price = 0, Color = Color3.fromRGB(18, 18, 18), Default = true },
	{ Id = "boots_white", Name = "Cloud Whites", Category = "Boots", Price = 250, Color = Color3.fromRGB(250, 250, 250) },
	{ Id = "boots_volt", Name = "Volt Strikers", Category = "Boots", Price = 400, Color = Color3.fromRGB(205, 255, 64) },
	{ Id = "boots_blaze", Name = "Blaze Runners", Category = "Boots", Price = 400, Color = Color3.fromRGB(255, 90, 40) },
	{ Id = "boots_ice", Name = "Ice Glide", Category = "Boots", Price = 700, Color = Color3.fromRGB(150, 220, 255), RequiredTier = "Regular" },
	{ Id = "boots_gold", Name = "Golden Touch", Category = "Boots", Price = 3000, Color = Color3.fromRGB(240, 196, 70), RequiredTier = "Legend" },

	-- Headwear (built from parts)
	{ Id = "head_none", Name = "Nothing", Category = "Headwear", Price = 0, Color = Color3.new(1, 1, 1), Style = "None", Default = true },
	{ Id = "head_band_white", Name = "White Headband", Category = "Headwear", Price = 80, Color = Color3.fromRGB(240, 240, 240), Style = "Headband" },
	{ Id = "head_band_red", Name = "Red Headband", Category = "Headwear", Price = 80, Color = Color3.fromRGB(200, 30, 40), Style = "Headband" },
	{ Id = "head_cap_black", Name = "Black Cap", Category = "Headwear", Price = 220, Color = Color3.fromRGB(26, 26, 28), Style = "Cap" },
	{ Id = "head_cap_volt", Name = "Volt Cap", Category = "Headwear", Price = 260, Color = Color3.fromRGB(205, 255, 64), Style = "Cap" },
	{ Id = "head_beanie_grey", Name = "Grey Beanie", Category = "Headwear", Price = 200, Color = Color3.fromRGB(120, 124, 130), Style = "Beanie" },
	{ Id = "head_beanie_orange", Name = "Orange Beanie", Category = "Headwear", Price = 240, Color = Color3.fromRGB(255, 120, 30), Style = "Beanie", RequiredTier = "Local" },
	{ Id = "head_crown", Name = "Concrete Crown", Category = "Headwear", Price = 5000, Color = Color3.fromRGB(240, 196, 70), Style = "Crown", RequiredTier = "Legend" },

	-- Trails (character effect)
	{ Id = "trail_none", Name = "No Trail", Category = "Trail", Price = 0, Color = Color3.new(1, 1, 1), Style = "None", Default = true },
	{ Id = "trail_white", Name = "Chalk Dust", Category = "Trail", Price = 400, Color = Color3.fromRGB(255, 255, 255), Style = "Trail" },
	{ Id = "trail_volt", Name = "Volt Streak", Category = "Trail", Price = 800, Color = Color3.fromRGB(205, 255, 64), Secondary = Color3.fromRGB(40, 200, 120), Style = "Trail", RequiredTier = "Regular" },
	{ Id = "trail_fire", Name = "Afterburn", Category = "Trail", Price = 1200, Color = Color3.fromRGB(255, 200, 60), Secondary = Color3.fromRGB(255, 50, 20), Style = "Trail", RequiredTier = "Skilled" },
}

Catalog.Items = {} :: { [string]: any }
Catalog.ByCategory = {} :: { [string]: { any } }

for _, category in Catalog.Categories do
	Catalog.ByCategory[category] = {}
end

for index, item in items do
	item.Order = index
	Catalog.Items[item.Id] = item
	table.insert(Catalog.ByCategory[item.Category], item)
end

function Catalog.Get(id: string)
	return Catalog.Items[id]
end

function Catalog.DefaultEquipped(): { [string]: string }
	local equipped = {}
	for _, category in Catalog.Categories do
		for _, item in Catalog.ByCategory[category] do
			if item.Default then
				equipped[category] = item.Id
				break
			end
		end
	end
	return equipped
end

function Catalog.DefaultInventory(): { [string]: boolean }
	local inventory = {}
	for id, item in Catalog.Items do
		if item.Default then
			inventory[id] = true
		end
	end
	return inventory
end

return Catalog
