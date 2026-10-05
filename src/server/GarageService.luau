--[[
	The vehicle shop: buying and equipping vehicles. The client's garage UI calls
	GarageRequest:InvokeServer(action, vehicleId); every rule is checked here (Profile does the
	actual work), never trusted from the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local OrderService = require(script.Parent.OrderService)
local PlayerService = require(script.Parent.PlayerService)
local Profile = require(script.Parent.Profile)
local VehicleService = require(script.Parent.VehicleService)

local GarageService = {}

local REQUEST_COOLDOWN = 0.3
local lastRequest = {} -- [Player] = os.clock()

local function reply(ok: boolean, message: string)
	return { ok = ok, message = message }
end

-- Pure-ish handler (also called directly by tests). Returns { ok, message }.
function GarageService.handle(player: Player, action, vehicleId)
	if type(action) ~= "string" or type(vehicleId) ~= "string" then
		return reply(false, "Bad request")
	end
	local spec = Config.VehicleById[vehicleId]
	if not spec then
		return reply(false, "Unknown vehicle")
	end
	local profile = PlayerService.get(player)
	if not profile then
		return reply(false, "Still loading your profile...")
	end

	-- Switching vehicles mid-delivery would let people dodge the time limit set for the old one.
	local busy = OrderService.hasOrder(player)
	local previous = profile.Equipped

	if action == "Buy" then
		local ok, reason = Profile.buy(profile, vehicleId)
		if not ok then
			return reply(false, reason or "Can't buy that")
		end
		if busy then
			profile.Equipped = previous
		end
		PlayerService.sync(player)
		if profile.Equipped ~= previous then
			VehicleService.swapEquipped(player)
		end
		if busy then
			return reply(true, "Bought the " .. spec.Name .. "! Finish your delivery to switch to it.")
		end
		return reply(true, "Bought the " .. spec.Name .. "!")
	elseif action == "Equip" then
		if busy and vehicleId ~= previous then
			return reply(false, "Finish your current delivery before switching vehicles.")
		end
		local ok, reason = Profile.equip(profile, vehicleId)
		if not ok then
			return reply(false, reason or "Can't equip that")
		end
		PlayerService.sync(player)
		if profile.Equipped ~= previous then
			VehicleService.swapEquipped(player)
		end
		return reply(true, spec.Name .. " equipped.")
	end

	return reply(false, "Unknown action")
end

function GarageService.start(world)
	Remotes.GarageRequest.OnServerInvoke = function(player, action, vehicleId)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < REQUEST_COOLDOWN then
			return reply(false, "Slow down!")
		end
		lastRequest[player] = now
		return GarageService.handle(player, action, vehicleId)
	end

	world.GaragePrompt.Triggered:Connect(function(player)
		Remotes.OpenGarage:FireClient(player)
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return GarageService
