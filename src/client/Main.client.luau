--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local UI = require(script.Parent:WaitForChild("UI"))

local hud, refs = UI.mount("HUD")
local shop = UI.mount("ShopMenu")
shop.Enabled = false

local amount = refs["HUD.Coins.Amount"] :: TextLabel
local upgrade = refs["HUD.Upgrade"] :: TextButton
local shopButton = refs["HUD.Shop"] :: TextButton

upgrade.Activated:Connect(function()
	Net.event("RequestUpgrade"):FireServer()
end)
shopButton.Activated:Connect(function()
	shop.Enabled = not shop.Enabled
end)

Net.event("StateChanged").OnClientEvent:Connect(function(coins: number, level: number)
	amount.Text = string.format("%d", coins)
	print(`[Client] coins={coins} level={level}`)
end)

print("[Client] ready", hud.Name)
