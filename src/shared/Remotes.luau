--!strict
-- All remote events/functions are created by the server at startup and looked
-- up by name here, so the place file needs no pre-built RemoteEvent instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENT_NAMES = {
	"StateUpdate", -- server -> client: Snapshot
	"StockUpdate", -- server -> client: StockInfo
	"BirdVisit", -- server -> client: VisitInfo
	"BirdCancel", -- server -> client: visit id
	"Notify", -- server -> client: Notice
	"PlantSeed", -- client -> server: plotIndex, seedId
	"DigPlant", -- client -> server: plotIndex
	"Dev", -- client -> server: action (Studio only)
}

local FUNCTION_NAMES = {
	"Init", -- client -> server: returns { state, stock, visits }
	"BuySeed", -- client -> server: seedId, amount -> Result
	"UnlockPlot", -- client -> server -> Result
}

export type Remotes = {
	StateUpdate: RemoteEvent,
	StockUpdate: RemoteEvent,
	BirdVisit: RemoteEvent,
	BirdCancel: RemoteEvent,
	Notify: RemoteEvent,
	PlantSeed: RemoteEvent,
	DigPlant: RemoteEvent,
	Dev: RemoteEvent,
	Init: RemoteFunction,
	BuySeed: RemoteFunction,
	UnlockPlot: RemoteFunction,
}

local cached: Remotes? = nil

local function get(): Remotes
	if cached then
		return cached
	end

	local isServer = RunService:IsServer()
	local folder: Instance
	if isServer then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing then
			folder = existing
		else
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes")
	end

	local map: { [string]: Instance } = {}
	local function resolve(name: string, create: () -> Instance)
		if isServer then
			local found = folder:FindFirstChild(name)
			local inst: Instance = found or create()
			if not found then
				inst.Name = name
				inst.Parent = folder
			end
			map[name] = inst
		else
			map[name] = folder:WaitForChild(name)
		end
	end
	for _, name in EVENT_NAMES do
		resolve(name, function()
			return Instance.new("RemoteEvent")
		end)
	end
	for _, name in FUNCTION_NAMES do
		resolve(name, function()
			return Instance.new("RemoteFunction")
		end)
	end

	local remotes = (map :: any) :: Remotes
	cached = remotes
	return remotes
end

return { get = get }
