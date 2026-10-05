--[[
	A player's saved progress, plus the rules for changing it. Plain tables only (no engine calls),
	so every rule here is unit-tested outside Roblox.

	Saved fields:   Cash, XP, Deliveries, TotalEarned, BestStreak, Owned (set of vehicle ids), Equipped
	Session fields: Streak, Temporary (true when the save failed to load, so we must not overwrite it)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)

local Profile = {}

local SAVED_FIELDS = { "Cash", "XP", "Deliveries", "TotalEarned", "BestStreak", "Owned", "Equipped" }

function Profile.new()
	return {
		Cash = Config.StartingCash,
		XP = 0,
		Deliveries = 0,
		TotalEarned = 0,
		BestStreak = 0,
		Owned = { [Config.DefaultVehicle] = true },
		Equipped = Config.DefaultVehicle,
		Streak = 0,
		Temporary = false,
	}
end

local function validNumber(value, fallback: number, minimum: number): number
	if type(value) == "number" and value == value and value >= minimum and value < 1e15 then
		return value
	end
	return fallback
end

-- Turns whatever came out of the DataStore (maybe nil, maybe from an older version) into a valid profile.
function Profile.fromSaved(data)
	local profile = Profile.new()
	if type(data) ~= "table" then
		return profile
	end

	profile.Cash = math.floor(validNumber(data.Cash, profile.Cash, 0))
	profile.XP = math.floor(validNumber(data.XP, profile.XP, 0))
	profile.Deliveries = math.floor(validNumber(data.Deliveries, 0, 0))
	profile.TotalEarned = math.floor(validNumber(data.TotalEarned, 0, 0))
	profile.BestStreak = math.floor(validNumber(data.BestStreak, 0, 0))

	if type(data.Owned) == "table" then
		for id, owned in data.Owned do
			if owned == true and Config.VehicleById[id] then
				profile.Owned[id] = true
			end
		end
	end
	if type(data.Equipped) == "string" and profile.Owned[data.Equipped] then
		profile.Equipped = data.Equipped
	end
	return profile
end

-- Only the fields worth keeping; session state stays out of the DataStore.
function Profile.toSaved(profile)
	local saved = {}
	for _, field in SAVED_FIELDS do
		saved[field] = profile[field]
	end
	saved.Owned = table.clone(profile.Owned)
	return saved
end

-- Vehicles ------------------------------------------------------------------------

function Profile.owns(profile, vehicleId: string): boolean
	return profile.Owned[vehicleId] == true
end

function Profile.rankIndex(profile): number
	return Economy.rankIndexForXp(profile.XP)
end

-- Returns ok, reason
function Profile.canBuy(profile, vehicleId: string): (boolean, string?)
	local spec = Config.VehicleById[vehicleId]
	if not spec then
		return false, "Unknown vehicle"
	end
	if Profile.owns(profile, vehicleId) then
		return false, "You already own this vehicle"
	end
	local rank = Profile.rankIndex(profile)
	if rank < spec.RankRequired then
		return false, "Requires rank " .. Config.Ranks[spec.RankRequired].Name
	end
	if profile.Cash < spec.Price then
		return false, "Not enough cash"
	end
	return true, nil
end

function Profile.buy(profile, vehicleId: string): (boolean, string?)
	local ok, reason = Profile.canBuy(profile, vehicleId)
	if not ok then
		return false, reason
	end
	local spec = Config.VehicleById[vehicleId]
	profile.Cash -= spec.Price
	profile.Owned[vehicleId] = true
	profile.Equipped = vehicleId
	return true, nil
end

function Profile.equip(profile, vehicleId: string): (boolean, string?)
	if not Config.VehicleById[vehicleId] then
		return false, "Unknown vehicle"
	end
	if not Profile.owns(profile, vehicleId) then
		return false, "You don't own this vehicle"
	end
	profile.Equipped = vehicleId
	return true, nil
end

-- Progress ------------------------------------------------------------------------

-- Adds earnings/XP and reports whether that ranked the player up.
function Profile.award(profile, cash: number, xp: number)
	local oldRank = Economy.rankIndexForXp(profile.XP)
	profile.Cash += cash
	profile.TotalEarned += cash
	profile.XP += xp
	local newRank = Economy.rankIndexForXp(profile.XP)
	return {
		RankedUp = newRank > oldRank,
		OldRank = oldRank,
		NewRank = newRank,
	}
end

-- Called after every finished order. onTime=false breaks the streak.
function Profile.recordDelivery(profile, onTime: boolean)
	profile.Deliveries += 1
	if onTime then
		profile.Streak += 1
		profile.BestStreak = math.max(profile.BestStreak, profile.Streak)
	else
		profile.Streak = 0
	end
end

function Profile.breakStreak(profile)
	profile.Streak = 0
end

return Profile
