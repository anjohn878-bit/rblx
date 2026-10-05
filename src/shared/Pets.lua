-- Rules for pet birds, shared by the server (authority) and the client (UI).
--
-- A pet is a plain table saved in the player's data:
--   Species     bird id from Birds.lua
--   Name        first name, e.g. "Pip"
--   Family      family surname once it has bred or was born into a family
--   Stars       1-5, how talented it is (better perks, worth more)
--   Shiny       sparkly variant
--   Generation  0 for wild birds, parents' generation + 1 for babies
--   Parents     "Pip & Kiwi" for babies
--   GrowsUpAt   unix time a baby becomes an adult (nil for adults)
--   Equipped    roaming your garden and giving its perk
--   Favorite    protected from selling and trading
--   Nest        nest number while it is sitting on an egg

local Birds = require(script.Parent.Birds)
local Config = require(script.Parent.Config)
local Rarities = require(script.Parent.Rarities)

local Pets = {}

-- Each bird species gives one of these perks while it roams your garden.
-- Bonus = PerPoint * pet points, up to Max.
Pets.Perks = {
	Growth = {
		Icon = "🌱",
		Name = "Green Thumb",
		Description = "plants grow faster",
		PerPoint = 0.03,
		Max = 1.5,
	},
	Attraction = {
		Icon = "🐦",
		Name = "Social",
		Description = "birds visit more often",
		PerPoint = 0.03,
		Max = 1,
	},
	Luck = {
		Icon = "🍀",
		Name = "Lucky",
		Description = "rarer and shinier visitors",
		PerPoint = 0.03,
		Max = 1.5,
	},
	Coins = {
		Icon = "🪙",
		Name = "Haggler",
		Description = "birds sell for more",
		PerPoint = 0.04,
		Max = 2,
	},
	SeedFinder = {
		Icon = "🎒",
		Name = "Seed Finder",
		Description = "chance each minute to find a seed",
		PerPoint = 0.07,
		Max = 0.9,
	},
}
Pets.PerkOrder = { "Growth", "Attraction", "Luck", "Coins", "SeedFinder" }

Pets.StarMultipliers = { 0.8, 1, 1.25, 1.6, 2 }
Pets.MaxStars = #Pets.StarMultipliers
local SHINY_POINTS = 1.5
local BABY_POINTS = 0.5
local BABY_VALUE = 0.6
Pets.BabyScale = 0.6

Pets.FirstNames = {
	"Pip",
	"Kiwi",
	"Sunny",
	"Peaches",
	"Mango",
	"Biscuit",
	"Pebble",
	"Clover",
	"Maple",
	"Nugget",
	"Willow",
	"Tweety",
	"Juniper",
	"Hazel",
	"Poppy",
	"Sprout",
	"Basil",
	"Ziggy",
	"Coco",
	"Skye",
	"Fig",
	"Olive",
	"Rusty",
	"Dot",
	"Echo",
	"Breeze",
	"Ember",
	"Luna",
	"Mochi",
	"Sorbet",
	"Taffy",
	"Wren",
}

Pets.FamilyNames = {
	"Featherby",
	"Songwood",
	"Pipwing",
	"Hollowtree",
	"Sunbeak",
	"Mossnest",
	"Bramblesong",
	"Dewdrop",
	"Thistledown",
	"Puddlefoot",
	"Skylark",
	"Twigsworth",
	"Honeyfeather",
	"Acornhill",
	"Cloudhop",
	"Berrybright",
}

function Pets.Def(pet)
	return Birds.Get(pet.Species)
end

function Pets.IsBaby(pet, now)
	return pet.GrowsUpAt ~= nil and now < pet.GrowsUpAt
end

function Pets.DisplayName(pet)
	if pet.Family then
		return pet.Name .. " " .. pet.Family
	end
	return pet.Name
end

function Pets.StarText(stars)
	return string.rep("⭐", math.clamp(stars or 1, 1, Pets.MaxStars))
end

-- How strong this pet's perk is.
function Pets.Points(pet, now)
	local def = Pets.Def(pet)
	if not def then
		return 0
	end
	local points = Rarities.Info[def.Rarity].PetPoints * Pets.StarMultipliers[pet.Stars or 1]
	if pet.Shiny then
		points *= SHINY_POINTS
	end
	if Pets.IsBaby(pet, now) then
		points *= BABY_POINTS
	end
	return points
end

-- Coins the pet sells for, before the Haggler perk.
function Pets.BaseValue(pet, now)
	local def = Pets.Def(pet)
	if not def then
		return 0
	end
	local value = def.Reward * Pets.StarMultipliers[pet.Stars or 1]
	if pet.Shiny then
		value *= Config.ShinyMultiplier
	end
	if Pets.IsBaby(pet, now) then
		value *= BABY_VALUE
	end
	return math.max(1, math.floor(value))
end

-- Spares are the birds "Sell spares" may sell. Anything special is kept:
-- birds that are out, nesting, favorites, shiny, in a family, babies or 4+ stars.
function Pets.IsSpare(pet, now)
	return not pet.Equipped
		and not pet.Nest
		and not pet.Favorite
		and not pet.Shiny
		and not pet.Family
		and not Pets.IsBaby(pet, now)
		and (pet.Stars or 1) < 4
end

function Pets.SellPrice(pet, now, perks)
	local bonus = perks and perks.Coins or 0
	return math.floor(Pets.BaseValue(pet, now) * (1 + bonus))
end

-- Adds up the perks of every roaming pet.
-- Returns { Growth = 0.12, Attraction = 0, ... } (0.12 = +12%)
function Pets.ComputePerks(pets, now)
	local points = {}
	for _, perk in ipairs(Pets.PerkOrder) do
		points[perk] = 0
	end
	for _, pet in pairs(pets) do
		if pet.Equipped and not pet.Nest then
			local def = Pets.Def(pet)
			if def and points[def.Perk] then
				points[def.Perk] += Pets.Points(pet, now)
			end
		end
	end
	local perks = {}
	for perk, total in pairs(points) do
		local info = Pets.Perks[perk]
		perks[perk] = math.min(info.Max, total * info.PerPoint)
	end
	return perks
end

-- "+12% plants grow faster"
function Pets.PerkText(perkId, amount)
	local info = Pets.Perks[perkId]
	return string.format("%s +%d%% %s", info.Icon, math.floor(amount * 100 + 0.5), info.Description)
end

-- Text for the perk a single pet gives.
function Pets.PetPerkText(pet, now)
	local def = Pets.Def(pet)
	local info = def and Pets.Perks[def.Perk]
	if not info then
		return ""
	end
	local amount = math.min(info.Max, Pets.Points(pet, now) * info.PerPoint)
	local percent = string.format("%.1f", amount * 100):gsub("%.0$", "")
	return info.Icon .. " +" .. percent .. "%"
end

function Pets.BreedTime(species)
	local def = Birds.Get(species)
	return Rarities.Info[def.Rarity].BreedTime / math.max(Config.GrowthSpeed, 0.001)
end

function Pets.GrowUpTime(species)
	local def = Birds.Get(species)
	return Rarities.Info[def.Rarity].GrowUpTime / math.max(Config.GrowthSpeed, 0.001)
end

function Pets.CountPets(pets)
	local count = 0
	for _ in pairs(pets) do
		count += 1
	end
	return count
end

function Pets.CountEquipped(pets)
	local count = 0
	for _, pet in pairs(pets) do
		if pet.Equipped and not pet.Nest then
			count += 1
		end
	end
	return count
end

-- Sort order for lists: roaming first, then rarest, then most stars.
function Pets.SortKeys(pets)
	local ids = {}
	for id in pairs(pets) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local pa, pb = pets[a], pets[b]
		if (pa.Equipped == true) ~= (pb.Equipped == true) then
			return pa.Equipped == true
		end
		local ra = Rarities.Rank(Pets.Def(pa) and Pets.Def(pa).Rarity)
		local rb = Rarities.Rank(Pets.Def(pb) and Pets.Def(pb).Rarity)
		if ra ~= rb then
			return ra > rb
		end
		if pa.Species ~= pb.Species then
			return pa.Species < pb.Species
		end
		if (pa.Stars or 1) ~= (pb.Stars or 1) then
			return (pa.Stars or 1) > (pb.Stars or 1)
		end
		return a < b
	end)
	return ids
end

return Pets
