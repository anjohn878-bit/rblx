-- Where everything sits inside a plot. All positions are in plot space:
-- X = left/right, Z = front/back (negative Z is the street side), Y = up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("DressStore"):WaitForChild("Config"))

local Layout = {}

Layout.PLOT_SIZE = 90
Layout.FLOOR_Y = Config.FLOOR_Y

-- Store building footprint
Layout.STORE_MIN_X = -30
Layout.STORE_MAX_X = 30
Layout.STORE_FRONT_Z = -22
Layout.STORE_BACK_Z = 24
Layout.WALL_HEIGHT = 14
Layout.DOOR_HALF_WIDTH = 5
Layout.DOOR_HEIGHT = 10

-- Where a player appears on their plot
Layout.PLAYER_SPAWN = Vector3.new(0, 3, -40)

-- Shopper walking route
Layout.CUSTOMER_SPAWN_X = 38 -- shoppers appear on the sidewalk left or right of the plot
Layout.CUSTOMER_SPAWN_Z = -50
Layout.STREET = Vector3.new(0, 0, -48) -- on the sidewalk in front of the gate
Layout.INSIDE = Vector3.new(0, 0, -16) -- just inside the front door
Layout.AISLE_X = 22.5 -- side aisles run along the racks
Layout.BACK_AISLE_Z = 12.5
Layout.CHECKOUT = Vector3.new(0, 0, 15.5) -- first spot in the line, facing the register
Layout.QUEUE_SPACING = 3.3 -- the rest of the line goes off to the left along the back aisle
Layout.MAX_QUEUE = 9

-- Furniture
Layout.REGISTER = Vector3.new(0, 0, 19)
Layout.SEW_TABLE = Vector3.new(-25.5, 0, 20)
Layout.MACHINE_Z = 20
Layout.RACK_X = 27
Layout.RACK_RAIL_HEIGHT = 5.25
Layout.RACK_SLOT_OFFSETS = { -3, -1, 1, 3 }

-- Buy buttons in the front yard (filled in order)
Layout.PAD_SLOTS = {}
for _, z in { -29.5, -36.5 } do
	for _, x in { -10, 10, -18, 18, -26, 26 } do
		table.insert(Layout.PAD_SLOTS, Vector3.new(x, 0, z))
	end
end

function Layout.queueSpot(index: number): Vector3
	if index <= 1 then
		return Layout.CHECKOUT
	end
	return Vector3.new(-Layout.QUEUE_SPACING * (index - 1), 0, Layout.BACK_AISLE_Z)
end

return Layout
