--[[
	Remotes
	Declares every network endpoint in one place. The server creates them,
	the client waits for them. Usage: Remotes.Get("Kick")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- Client -> Server events
local EVENTS = {
	"RequestQueue", -- (join: boolean)
	"Kick", -- (kind: string, direction: Vector3, power: number)
	"Tackle", -- ()
	"SkillMove", -- ()
	"UpdateSettings", -- (settings table)
	-- Server -> Client events
	"ProfileUpdated", -- (profile table)
	"MatchEvent", -- (kind: string, payload: table)
	"Notify", -- (text: string, kind: string?)
	"BallEvent", -- (kind: string, payload) for sounds/effects
}

-- Client -> Server requests with a reply
local FUNCTIONS = {
	"GetProfile",
	"PurchaseItem", -- (itemId) -> ok, message
	"EquipItem", -- (itemId) -> ok, message
	"SpendAttribute", -- (attributeName) -> ok, message
}

local FOLDER_NAME = "Remotes"

local folder: Folder

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not existing then
			existing = Instance.new("Folder")
			existing.Name = FOLDER_NAME
			existing.Parent = ReplicatedStorage
		end
		folder = existing :: Folder
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	return folder
end

-- Server: create all remotes. Safe to call more than once.
function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init is server only")
	local f = getFolder()
	for _, name in EVENTS do
		if not f:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = f
		end
	end
	for _, name in FUNCTIONS do
		if not f:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = f
		end
	end
end

function Remotes.Get(name: string): any
	local f = getFolder()
	if RunService:IsServer() then
		local r = f:FindFirstChild(name)
		assert(r, "Unknown remote " .. name)
		return r
	end
	return f:WaitForChild(name)
end

return Remotes
