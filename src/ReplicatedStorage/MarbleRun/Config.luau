-- Shared tuning values for Build a Marble Run.

local Config = {}

-- Grid / plot layout
Config.CELL = 8 -- studs per grid cell (horizontal)
Config.LEVEL_HEIGHT = 1 -- studs per height level
Config.GRID = 12 -- plot is GRID x GRID cells
Config.MAX_LEVEL = 60
Config.MIN_LEVEL = 0
Config.MAX_PIECES = 200

-- The start tower sits in cell (0, 0) of every plot and launches marbles into cell (1, 0).
Config.START_CELL = Vector2.new(0, 0)
Config.START_LEVEL = 40
Config.START_ROT = 3 -- rotation index whose forward direction is +X

-- Plot origins (corner of the plot, at ground level). Plots are axis aligned.
Config.PLOT_ORIGINS = {
	Vector3.new(-168, 0, -130),
	Vector3.new(-48, 0, -130),
	Vector3.new(72, 0, -130),
	Vector3.new(-168, 0, 34),
	Vector3.new(-48, 0, 34),
	Vector3.new(72, 0, 34),
}

-- Track geometry
Config.TRACK_WIDTH = 4
Config.FLOOR_THICKNESS = 0.4
Config.RAIL_HEIGHT = 1.8
Config.RAIL_THICKNESS = 0.3

-- Marble
Config.MARBLE_SIZE = 1.6
Config.MARBLE_MAX_SPEED = 70
Config.MARBLE_TIMEOUT = 120 -- seconds
Config.MARBLE_STUCK_TIME = 4 -- seconds below MARBLE_STUCK_SPEED before it counts as stuck
Config.MARBLE_STUCK_SPEED = 0.4
Config.BOOST_SPEED = 55

-- Economy
Config.START_COINS = 150
Config.REWARD_BASE = 10
Config.REWARD_PER_PIECE = 3
Config.REWARD_PER_SECOND = 2
Config.CHIME_BONUS = 1

Config.DATASTORE_NAME = "BuildAMarbleRun_v1"

return Config
