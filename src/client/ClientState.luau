--[[
	ClientState
	Local cache of the player's profile (read-only copy sent by the server) and
	shared UI flags. Controllers listen to ClientState.Changed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ClientState = {}

ClientState.Profile = nil
ClientState.MenuOpen = false -- any full-screen panel open (unlocks the mouse)
ClientState.Stamina = 100
ClientState.Charge = 0 -- shot charge 0..1, -1 when not charging

local changed = Instance.new("BindableEvent")
ClientState.Changed = changed.Event

function ClientState.SetProfile(profile)
	if type(profile) ~= "table" then
		return
	end
	ClientState.Profile = profile
	changed:Fire(profile)
end

function ClientState.Init()
	Remotes.Get("ProfileUpdated").OnClientEvent:Connect(ClientState.SetProfile)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Remotes.Get("GetProfile"):InvokeServer()
		end)
		if ok and profile and not ClientState.Profile then
			ClientState.SetProfile(profile)
		end
	end)
end

function ClientState.GetAttribute(name: string): number
	local p = ClientState.Profile
	return (p and p.Attributes and p.Attributes[name]) or 50
end

return ClientState
