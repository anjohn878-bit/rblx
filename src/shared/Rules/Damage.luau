--!strict
-- Pure game rules: plain numbers in, plain numbers out. No Roblox objects,
-- so tests run under Lune without Studio. Config is passed in, never required.
local Damage = {}

export type CombatConfig = {
	BaseDamage: number,
	CritMultiplier: number,
	MaxHealth: number,
	ArmorPerLevel: number,
	MaxArmorReduction: number,
}

function Damage.compute(config: CombatConfig, isCrit: boolean, armorLevel: number): number
	local raw = config.BaseDamage * (if isCrit then config.CritMultiplier else 1)
	local reduction = math.min(math.max(armorLevel, 0) * config.ArmorPerLevel, config.MaxArmorReduction)
	return raw * (1 - reduction)
end

function Damage.applyTo(config: CombatConfig, health: number, amount: number): number
	return math.clamp(health - amount, 0, config.MaxHealth)
end

return Damage
