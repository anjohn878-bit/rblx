--[[
	Remotes
	Single place that defines every RemoteEvent/RemoteFunction. The server
	creates them; the client waits for them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"ProfileUpdated", -- server -> client: full profile snapshot
	"Notify", -- server -> client: (message, kind)
	"SkateState", -- client -> server: (isSkating)
	"TrickLanded", -- client -> server: { kind, rotations?, jumpType? }
	"TrickResult", -- server -> client: { name, amount, combo, comboMultiplier }
	"CollectiblePicked", -- server -> client: (position, amount)
	"Rebirthed", -- server -> client: (rebirths)
}

local FUNCTIONS = {
	"GetProfile", -- client -> server: returns the profile once loaded
	"Purchase", -- client -> server: (kind, id) -> (ok, message)
}

local Remotes = {}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

for _, name in EVENTS do
	Remotes[name] = folder:WaitForChild(name)
end
for _, name in FUNCTIONS do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
