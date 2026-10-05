--[[
	Read-only view of the state the server publishes as attributes on the local Player
	(see server/PlayerService and server/OrderService for the full list).
]]

local Players = game:GetService("Players")

local State = {}

local player = Players.LocalPlayer

function State.get(name: string, default: any?): any
	local value = player:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

-- Calls callback(value) now and again whenever the attribute changes.
function State.watch(name: string, callback: (any) -> ()): RBXScriptConnection
	callback(player:GetAttribute(name))
	return player:GetAttributeChangedSignal(name):Connect(function()
		callback(player:GetAttribute(name))
	end)
end

function State.owns(vehicleId: string): boolean
	local owned = State.get("Owned", "")
	return string.find(owned, "," .. vehicleId .. ",", 1, true) ~= nil
end

return State
