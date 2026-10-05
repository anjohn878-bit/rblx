--[[
	ClientData
	The local copy of this player's profile, kept in sync by the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local ClientData = {}
ClientData.Changed = Signal.new() -- (profile, previousProfile)

local profile = nil

local function setProfile(newProfile)
	if type(newProfile) ~= "table" then
		return
	end
	local previous = profile
	profile = newProfile
	ClientData.Changed:Fire(newProfile, previous)
end

function ClientData.get()
	return profile
end

-- Calls `callback(profile)` now if loaded, and every time it changes.
function ClientData.observe(callback)
	if profile then
		task.spawn(callback, profile, nil)
	end
	return ClientData.Changed:Connect(callback)
end

function ClientData.init()
	Remotes.ProfileUpdated.OnClientEvent:Connect(setProfile)
	task.spawn(function()
		local initial = Remotes.GetProfile:InvokeServer()
		if not profile then
			setProfile(initial)
		end
	end)
end

return ClientData
