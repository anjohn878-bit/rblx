--[[
	Formulas
	Derived stats and prices. The server uses these to validate everything,
	the client uses the same functions to drive movement and draw the UI, so the
	two can never disagree.
]]

local Config = require(script.Parent.Config)

local Formulas = {}

local rinksById = {}
for _, rink in Config.Rinks do
	rinksById[rink.Id] = rink
end

local upgradesById = {}
for _, upgrade in Config.Upgrades do
	upgradesById[upgrade.Id] = upgrade
end

function Formulas.getRink(rinkId)
	return rinksById[rinkId]
end

function Formulas.getUpgrade(upgradeId)
	return upgradesById[upgradeId]
end

function Formulas.getSkate(tier)
	return Config.Skates[math.clamp(tier or 1, 1, #Config.Skates)]
end

function Formulas.upgradeLevel(profile, upgradeId)
	return profile.Upgrades[upgradeId] or 0
end

function Formulas.isRinkUnlocked(profile, rinkId)
	local rink = rinksById[rinkId]
	return rink ~= nil and (rink.Price <= 0 or profile.UnlockedRinks[rinkId] == true)
end

local function speedBonus(profile)
	return 1 + Formulas.upgradeLevel(profile, "Speed") * upgradesById.Speed.PerLevel
end

function Formulas.maxSpeed(profile)
	return Formulas.getSkate(profile.SkateTier).MaxSpeed * speedBonus(profile)
end

function Formulas.acceleration(profile)
	return Formulas.getSkate(profile.SkateTier).Acceleration * speedBonus(profile)
end

function Formulas.jumpHeight(profile)
	return Config.Skating.BaseJumpHeight + Formulas.upgradeLevel(profile, "Jump") * upgradesById.Jump.PerLevel
end

function Formulas.rebirthMultiplier(profile)
	return 1 + profile.Rebirths * Config.Rebirth.MultiplierPerRebirth
end

function Formulas.styleMultiplier(profile)
	return 1 + Formulas.upgradeLevel(profile, "Style") * upgradesById.Style.PerLevel
end

-- Multiplier applied to snowflakes earned by skating and golden snowflakes.
function Formulas.earnMultiplier(profile, rinkId)
	local rink = rinksById[rinkId]
	local rinkMultiplier = if rink then rink.Multiplier else 1
	return Formulas.getSkate(profile.SkateTier).EarnMultiplier * rinkMultiplier * Formulas.rebirthMultiplier(profile)
end

-- Multiplier applied to snowflakes earned from tricks.
function Formulas.trickMultiplier(profile, rinkId)
	return Formulas.earnMultiplier(profile, rinkId) * Formulas.styleMultiplier(profile)
end

-- Returns nil once the upgrade is maxed.
function Formulas.upgradeCost(upgradeId, level)
	local upgrade = upgradesById[upgradeId]
	if not upgrade or level >= upgrade.MaxLevel then
		return nil
	end
	return math.floor(upgrade.BaseCost * upgrade.CostGrowth ^ level)
end

function Formulas.rebirthCost(rebirths)
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ rebirths)
end

function Formulas.airTime(jumpHeight, gravity)
	return 2 * math.sqrt(2 * jumpHeight / gravity)
end

function Formulas.airSpinRate(speed)
	return Config.Tricks.BaseAirSpinRate + speed * Config.Tricks.AirSpinRatePerSpeed
end

function Formulas.countRotations(angle)
	return math.max(0, math.floor(math.abs(angle) / (2 * math.pi) + Config.Tricks.RotationForgiveness))
end

-- The most rotations this player could physically land, used by the server to reject fakes.
function Formulas.maxRotations(profile, gravity)
	local airTime = Formulas.airTime(Formulas.jumpHeight(profile), gravity)
	local fastestSpin = Formulas.airSpinRate(Formulas.maxSpeed(profile) * 1.1)
	local tolerance = 1.15
	return math.min(#Config.Tricks.Rotations, Formulas.countRotations(airTime * fastestSpin * tolerance))
end

function Formulas.jumpTrick(rotations)
	local tiers = Config.Tricks.Rotations
	return tiers[math.clamp(rotations, 1, #tiers)]
end

function Formulas.comboMultiplier(combo)
	local tricks = Config.Tricks
	return math.min(tricks.MaxComboMultiplier, 1 + math.max(0, combo - 1) * tricks.ComboStep)
end

return Formulas
