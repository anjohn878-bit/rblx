--[[
	Runs the whole suite:   lune run tests/run
	(from the repository root; exits non-zero on failure.)
]]

local T = require("./harness")

local specs = {
	"economy_spec",
	"world_spec",
	"vehicle_spec",
	"logic_spec",
	"drive_spec",
	"server_spec",
	"client_spec",
	"place_spec",
}

for _, name in specs do
	print("\n== " .. name)
	local register = require("./" .. name)
	register(T)
end

print("\n== results")
T.exit(T.run())
