-- Sends a pet action to the server and shows the result as a toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Notifications = require(script.Parent.Notifications)

local Actions = {}

local busy = false

-- Actions.Pet("Equip", petId) -> success
function Actions.Pet(action, ...)
	if busy then
		return false
	end
	busy = true
	local ok, success, message = pcall(Net.PetAction.InvokeServer, Net.PetAction, action, ...)
	busy = false
	if not ok then
		Notifications.Show("Something went wrong. Try again!", "Error")
		return false
	end
	if type(message) == "string" and message ~= "" then
		Notifications.Show(message, success and "Success" or "Error")
	end
	return success == true
end

return Actions
