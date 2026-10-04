--[[
	Progression
	Pure functions for levels, titles, reputation tiers and match rewards.
	No Roblox services are used so this can be unit tested outside Studio.
]]

local Config = require(script.Parent.Config)

local Progression = {}

-- Original level titles. A title applies from its level upwards.
Progression.LevelTitles = {
	{ Level = 1, Title = "Fresh Laces" },
	{ Level = 5, Title = "Block Baller" },
	{ Level = 10, Title = "Cage Prospect" },
	{ Level = 15, Title = "Corner Shop Hero" },
	{ Level = 20, Title = "Postcode Star" },
	{ Level = 30, Title = "Concrete King" },
}

-- Reputation tiers, separate from level. Unlocks areas and cosmetics.
Progression.ReputationTiers = {
	{ Name = "Unknown", Min = 0 },
	{ Name = "Local", Min = 100 },
	{ Name = "Regular", Min = 300 },
	{ Name = "Skilled", Min = 700 },
	{ Name = "Star", Min = 1500 },
	{ Name = "Legend", Min = 3000 },
}

Progression.MaxLevel = 50

-- XP needed to go from `level` to `level + 1`.
function Progression.XPToNext(level: number): number
	return math.floor(100 * level ^ 1.35)
end

-- Adds XP to a level/xp pair and returns the new level, the leftover xp and how
-- many levels were gained. Never exceeds MaxLevel.
function Progression.ApplyXP(level: number, xp: number, gained: number): (number, number, number)
	local levelsGained = 0
	xp += math.max(0, gained)
	while level < Progression.MaxLevel and xp >= Progression.XPToNext(level) do
		xp -= Progression.XPToNext(level)
		level += 1
		levelsGained += 1
	end
	if level >= Progression.MaxLevel then
		level = Progression.MaxLevel
		xp = math.min(xp, Progression.XPToNext(level))
	end
	return level, xp, levelsGained
end

function Progression.GetTitle(level: number): string
	local title = Progression.LevelTitles[1].Title
	for _, entry in Progression.LevelTitles do
		if level >= entry.Level then
			title = entry.Title
		end
	end
	return title
end

-- Returns tier index (1-based), tier name, and the reputation needed for the next tier (or nil).
function Progression.GetReputationTier(reputation: number): (number, string, number?)
	local index = 1
	for i, tier in Progression.ReputationTiers do
		if reputation >= tier.Min then
			index = i
		end
	end
	local nextTier = Progression.ReputationTiers[index + 1]
	return index, Progression.ReputationTiers[index].Name, nextTier and nextTier.Min or nil
end

function Progression.TierIndexByName(name: string): number
	for i, tier in Progression.ReputationTiers do
		if tier.Name == name then
			return i
		end
	end
	return 1
end

--[[
	Computes match rewards from a stat line.
	stats = { Goals, Assists, Passes, Tackles, SkillMoves }
	result = "Win" | "Draw" | "Loss"
]]
function Progression.ComputeMatchRewards(stats, result: string)
	local r = Config.Rewards
	local goals = stats.Goals or 0
	local assists = stats.Assists or 0

	local xp = r.XP.Played
		+ goals * r.XP.Goal
		+ assists * r.XP.Assist
		+ math.min(stats.Passes or 0, 40) * r.XP.Pass
		+ math.min(stats.Tackles or 0, 20) * r.XP.Tackle
		+ math.min(stats.SkillMoves or 0, 30) * r.XP.SkillMove
	local kicks = r.Kicks.Played + goals * r.Kicks.Goal + assists * r.Kicks.Assist
	local rep = r.Reputation.Played + goals * r.Reputation.Goal + assists * r.Reputation.Assist

	if result == "Win" then
		xp += r.XP.Win
		kicks += r.Kicks.Win
		rep += r.Reputation.Win
	elseif result == "Draw" then
		xp += r.XP.Draw
		kicks += r.Kicks.Draw
		rep += r.Reputation.Draw
	end

	return {
		XP = math.min(xp, r.XP.CapPerMatch),
		Kicks = math.min(kicks, r.Kicks.CapPerMatch),
		Reputation = rep,
	}
end

-- Attribute value (0..1) used by gameplay formulas.
function Progression.AttributeAlpha(value: number?): number
	local v = value or Config.Attributes.Start
	return math.clamp(v / Config.Attributes.Max, 0, 1)
end

-- Rough skill rating used for team balancing.
function Progression.SkillRating(profile): number
	local stats = profile.Stats
	local played = math.max(stats.Matches, 1)
	local winRate = stats.Wins / played
	local total = 0
	for _, name in Config.Attributes.List do
		total += profile.Attributes[name] or Config.Attributes.Start
	end
	return profile.Level * 2 + winRate * 20 + total / #Config.Attributes.List
end

return Progression
