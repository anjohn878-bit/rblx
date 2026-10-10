--!strict
local Economy = {}

export type EconomyConfig = {
	StartingCoins: number,
	UpgradeBaseCost: number,
	UpgradeCostGrowth: number,
	MaxUpgradeLevel: number,
}

-- Cost to go from `level` to `level + 1`; nil once maxed.
function Economy.upgradeCost(config: EconomyConfig, level: number): number?
	if level >= config.MaxUpgradeLevel then
		return nil
	end
	return math.floor(config.UpgradeBaseCost * config.UpgradeCostGrowth ^ level + 0.5)
end

function Economy.canAfford(config: EconomyConfig, coins: number, level: number): boolean
	local cost = Economy.upgradeCost(config, level)
	return cost ~= nil and coins >= cost
end

return Economy
