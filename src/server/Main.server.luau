--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Movement = require(Shared.Config.Movement)
local EconomyConfig = require(Shared.Config.Economy)
local Economy = require(Shared.Rules.Economy)

Net.init()
workspace.Gravity = Movement.Gravity

type PlayerState = { coins: number, level: number }
local states: { [Player]: PlayerState } = {}

local function applyMovement(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.UseJumpPower = false
	humanoid.WalkSpeed = Movement.WalkSpeed
	humanoid.JumpHeight = Movement.JumpHeight
	humanoid.MaxSlopeAngle = Movement.MaxSlopeAngle
end

Players.PlayerAdded:Connect(function(player)
	states[player] = { coins = EconomyConfig.StartingCoins, level = 0 }
	player.CharacterAdded:Connect(applyMovement)
	if player.Character then
		applyMovement(player.Character)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

Net.event("RequestUpgrade").OnServerEvent:Connect(function(player)
	local state = states[player]
	if not state then
		return
	end
	local cost = Economy.upgradeCost(EconomyConfig, state.level)
	if cost and state.coins >= cost then
		state.coins -= cost
		state.level += 1
	end
	Net.event("StateChanged"):FireClient(player, state.coins, state.level)
end)

print("[Server] ready")
