local H = require("./harness")
local Economy = require("../src/shared/Rules/Economy")
local Config = require("../src/shared/Config/Economy")

H.describe("Economy", function()
	H.it("first upgrade costs the base cost", function()
		H.expect(Economy.upgradeCost(Config, 0)).toBe(Config.UpgradeBaseCost)
	end)
	H.it("costs strictly increase", function()
		local last = 0
		for level = 0, Config.MaxUpgradeLevel - 1 do
			local cost = Economy.upgradeCost(Config, level) :: number
			assert(cost > last, `level {level} cost {cost} <= {last}`)
			last = cost
		end
	end)
	H.it("stops at max level", function()
		H.expect(Economy.upgradeCost(Config, Config.MaxUpgradeLevel)).toBe(nil)
		H.expect(Economy.canAfford(Config, math.huge, Config.MaxUpgradeLevel)).toBe(false)
	end)
end)
