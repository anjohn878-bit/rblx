--[[
	Shared test setup: a fresh DataModel with the game's scripts injected exactly like the real place,
	plus a runtime to require them.
]]

local roblox = require("@lune/roblox")
local Env = require("../tools/env")

local Fixture = {}

local REPO_ROOT = "."

function Fixture.setRepoRoot(path: string)
	REPO_ROOT = path
end

-- signals: see Env.installPolyfills
function Fixture.new(options)
	Env.installPolyfills(options and options.signals)
	local dm = roblox.Instance.new("DataModel")
	-- Studio's real services exist implicitly; make sure the ones we inject into are present.
	Env.injectSources(dm, REPO_ROOT)
	local runtime = Env.new(dm, options)

	local function module(path: string)
		local instance = dm
		for part in string.gmatch(path, "[^%.]+") do
			instance = instance:FindFirstChild(part) or instance:GetService(part)
		end
		return instance
	end

	return {
		DataModel = dm,
		Runtime = runtime,
		Workspace = dm:GetService("Workspace"),
		-- Fixture:require("ReplicatedStorage.Shared.Config")
		require = function(_, path: string)
			return runtime:require(module(path))
		end,
		find = function(_, path: string)
			return module(path)
		end,
	}
end

return Fixture
