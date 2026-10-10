--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

Net.event("StateChanged").OnClientEvent:Connect(function(coins: number, level: number)
	print(`[Client] coins={coins} level={level}`)
end)

print("[Client] ready")
