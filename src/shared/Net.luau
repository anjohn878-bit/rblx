--!strict
-- The ONE place every player<->server message is named. Server creates them,
-- client waits for them. Never create a RemoteEvent anywhere else.
local Net = {}

Net.Events = {
	"RequestUpgrade", -- client -> server
	"StateChanged", -- server -> client
}

Net.Functions = {} :: { string }

local FOLDER = "Net"

function Net.init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	for _, name in Net.Events do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in Net.Functions do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function find(name: string): Instance
	assert(table.find(Net.Events, name) or table.find(Net.Functions, name), `Unknown net name {name}`)
	local folder = game:GetService("ReplicatedStorage"):WaitForChild(FOLDER)
	return folder:WaitForChild(name)
end

function Net.event(name: string): RemoteEvent
	return find(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return find(name) :: RemoteFunction
end

return Net
