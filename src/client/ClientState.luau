--[[
	ClientState
	Holds the latest state snapshot sent by the server. This is display data
	only; the server owns the real values.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local ClientState = {}
ClientState.State = nil :: any
ClientState.Changed = Signal.new()

local function set(state: any)
	if type(state) ~= "table" then
		return
	end
	local old = ClientState.State
	ClientState.State = state
	ClientState.Changed:Fire(state, old)
end

function ClientState.Start()
	Remotes.Event("StateUpdate").OnClientEvent:Connect(set)
	task.spawn(function()
		local getState = Remotes.Function("GetState")
		while not ClientState.State do
			local ok, state = pcall(function()
				return getState:InvokeServer()
			end)
			if ok and state and not ClientState.State then
				set(state)
			end
			if not ClientState.State then
				task.wait(1)
			end
		end
	end)
end

function ClientState.Get(): any
	return ClientState.State
end

-- Yields until the first snapshot arrives.
function ClientState.Wait(): any
	while not ClientState.State do
		task.wait(0.1)
	end
	return ClientState.State
end

return ClientState
