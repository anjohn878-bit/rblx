-- Creates (on the server) or finds (on the client) every remote the game uses.
-- Usage: local Net = require(Shared.Net); Net.Notify:FireClient(player, ...)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "BirdGardenRemotes"

local DEFINITIONS = {
	RemoteEvent = {
		"DataUpdated", -- server -> client: full player state snapshot
		"ShopUpdated", -- server -> client: seed shop stock snapshot
		"Notify", -- server -> client: toast message
		"Effect", -- server -> client: floating text in the world
		"OpenShop", -- server -> client: open the shop window
		"SelectSeed", -- client -> server: choose which seed to plant
		"Teleport", -- client -> server: "Garden" or "Shop"
		"PetEvent", -- server -> client: something happened to a pet (floating text over it)
		"OpenNest", -- server -> client: open the nest window
		"TradeRequest", -- client -> server: ask another player to trade
		"TradeRespond", -- client -> server: accept or decline a trade request
		"TradeUpdate", -- client -> server: change your offer, ready up or cancel
		"TradeIncoming", -- server -> client: someone wants to trade with you
		"TradeState", -- server -> client: the current trade
	},
	RemoteFunction = {
		"GetState", -- client -> server: initial state snapshot
		"GetShop", -- client -> server: initial shop snapshot
		"BuySeed", -- client -> server: buy one seed, returns ok, message
		"PetAction", -- client -> server: equip, sell, breed... returns ok, message
	},
}

local Net = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for className, names in pairs(DEFINITIONS) do
		for _, name in ipairs(names) do
			local remote = folder:FindFirstChild(name)
			if not remote then
				remote = Instance.new(className)
				remote.Name = name
				remote.Parent = folder
			end
			Net[name] = remote
		end
	end
else
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	for _, names in pairs(DEFINITIONS) do
		for _, name in ipairs(names) do
			Net[name] = folder:WaitForChild(name)
		end
	end
end

return Net
