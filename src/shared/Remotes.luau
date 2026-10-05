-- Creates the remotes on the server and waits for them on the client, so both sides can simply
-- `require` this module and index remotes by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"StateChanged", -- server -> client: full player state snapshot
	"Notify", -- server -> client: (text, kind)
	"OpenShop", -- server -> client: open the garage window
	"SpawnVehicle", -- client -> server
	"DeliverPackage", -- client -> server: (jobId)
}

local FUNCTIONS = {
	"GetState", -- client -> server: returns the state snapshot once data has loaded
	"BuyVehicle", -- client -> server: (vehicleId) -> (ok, message)
	"EquipVehicle", -- client -> server: (vehicleId) -> (ok, message)
}

local folder: Instance
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
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

local Remotes = {
	StateChanged = folder:WaitForChild("StateChanged") :: RemoteEvent,
	Notify = folder:WaitForChild("Notify") :: RemoteEvent,
	OpenShop = folder:WaitForChild("OpenShop") :: RemoteEvent,
	SpawnVehicle = folder:WaitForChild("SpawnVehicle") :: RemoteEvent,
	DeliverPackage = folder:WaitForChild("DeliverPackage") :: RemoteEvent,
	GetState = folder:WaitForChild("GetState") :: RemoteFunction,
	BuyVehicle = folder:WaitForChild("BuyVehicle") :: RemoteFunction,
	EquipVehicle = folder:WaitForChild("EquipVehicle") :: RemoteFunction,
}

return Remotes
