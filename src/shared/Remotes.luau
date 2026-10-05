--[[
	One place that declares every RemoteEvent / RemoteFunction.
	The server creates them the first time this module is required; clients wait for them.

	  Notify          server -> client   (message: string, kind: "info" | "success" | "warn" | "error")
	  DeliveryResult  server -> client   (result: table, see OrderService)
	  OpenGarage      server -> client   (no args)
	  CallVehicle     client -> server   (no args)
	  CancelOrder     client -> server   (no args)
	  GarageRequest   client -> server   (action: "Buy" | "Equip", vehicleId: string) -> { ok, message }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = { "Notify", "DeliveryResult", "OpenGarage", "CallVehicle", "CancelOrder" }
local FUNCTIONS = { "GarageRequest" }

local Remotes = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in EVENTS do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		for _, name in FUNCTIONS do
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
end

local folder = ReplicatedStorage:WaitForChild("Remotes")
for _, name in EVENTS do
	Remotes[name] = folder:WaitForChild(name)
end
for _, name in FUNCTIONS do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
