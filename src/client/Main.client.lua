-- Grow a Bird Garden: client entry point. Builds the UI and wires it to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Hud = require(script.Parent.Hud)
local JournalWindow = require(script.Parent.JournalWindow)
local Notifications = require(script.Parent.Notifications)
local SeedBag = require(script.Parent.SeedBag)
local ShopWindow = require(script.Parent.ShopWindow)
local Store = require(script.Parent.Store)
local WorldFx = require(script.Parent.WorldFx)

local player = Players.LocalPlayer

-- seeds live in our own seed bag, so hide the default backpack hotbar
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BirdGardenUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

Notifications.Init(screenGui)
ShopWindow.Init(screenGui)
JournalWindow.Init(screenGui)

local function openShop()
	JournalWindow.Close()
	ShopWindow.Open()
end

local function toggleShop()
	if ShopWindow.IsOpen() then
		ShopWindow.Close()
	else
		openShop()
	end
end

local function toggleJournal()
	if JournalWindow.IsOpen() then
		JournalWindow.Close()
	else
		ShopWindow.Close()
		JournalWindow.Open()
	end
end

Hud.Init(screenGui, {
	OnSeeds = toggleShop,
	OnGarden = function()
		Net.Teleport:FireServer("Garden")
	end,
	OnJournal = toggleJournal,
})
SeedBag.Init(screenGui, openShop)
WorldFx.Init()

Net.DataUpdated.OnClientEvent:Connect(Store.SetData)
Net.ShopUpdated.OnClientEvent:Connect(Store.SetShop)
Net.Notify.OnClientEvent:Connect(Notifications.Show)
Net.OpenShop.OnClientEvent:Connect(openShop)

task.spawn(function()
	local ok, data = pcall(function()
		return Net.GetState:InvokeServer()
	end)
	if ok and data and not Store.Data then
		Store.SetData(data)
	end
end)
task.spawn(function()
	local ok, shop = pcall(function()
		return Net.GetShop:InvokeServer()
	end)
	if ok and shop and not Store.Shop then
		Store.SetShop(shop)
	end
end)
