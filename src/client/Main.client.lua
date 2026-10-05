-- Grow a Bird Garden: client entry point. Builds the UI and wires it to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local AviaryWindow = require(script.Parent.AviaryWindow)
local Hud = require(script.Parent.Hud)
local JournalWindow = require(script.Parent.JournalWindow)
local NestWindow = require(script.Parent.NestWindow)
local Notifications = require(script.Parent.Notifications)
local PetRenderer = require(script.Parent.PetRenderer)
local SeedBag = require(script.Parent.SeedBag)
local ShopWindow = require(script.Parent.ShopWindow)
local Store = require(script.Parent.Store)
local TradeWindow = require(script.Parent.TradeWindow)
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

-- Everything is laid out for screens at least 560px tall; on smaller screens
-- (phones) the whole interface is scaled down to fit.
local DESIGN_HEIGHT = 560
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Parent = screenGui
local rootScale = Instance.new("UIScale")
rootScale.Parent = root
local function fitToScreen()
	-- (pcall: the offline test harness has no layout engine)
	local ok, size = pcall(function()
		return screenGui.AbsoluteSize
	end)
	local height = ok and size.Y or 0
	local scale = height > 0 and math.clamp(height / DESIGN_HEIGHT, 0.6, 1) or 1
	rootScale.Scale = scale
	-- the frame is scaled down, so make it bigger to still cover the screen
	root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end
fitToScreen()
screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)

Notifications.Init(root)
ShopWindow.Init(root)
JournalWindow.Init(root)
TradeWindow.Init(root)
NestWindow.Init(root)

local windows = { ShopWindow, JournalWindow, AviaryWindow, NestWindow, TradeWindow }

-- Only one window at a time.
local function show(target, ...)
	for _, window in ipairs(windows) do
		if window ~= target then
			window.Close()
		end
	end
	target.Open(...)
end

local function toggle(target)
	if target.IsOpen() then
		target.Close()
	else
		show(target)
	end
end

local function openShop()
	show(ShopWindow)
end

local function openNests(nestIndex)
	show(NestWindow, nestIndex)
end

AviaryWindow.Init(root, { OpenNests = openNests })

Hud.Init(root, {
	OnSeeds = function()
		toggle(ShopWindow)
	end,
	OnGarden = function()
		Net.Teleport:FireServer("Garden")
	end,
	OnJournal = function()
		toggle(JournalWindow)
	end,
	OnBirds = function()
		toggle(AviaryWindow)
	end,
	OnTrade = function()
		toggle(TradeWindow)
	end,
})
SeedBag.Init(root, openShop)
WorldFx.Init()
PetRenderer.Init()

Net.DataUpdated.OnClientEvent:Connect(Store.SetData)
Net.ShopUpdated.OnClientEvent:Connect(Store.SetShop)
Net.Notify.OnClientEvent:Connect(Notifications.Show)
Net.OpenShop.OnClientEvent:Connect(openShop)
Net.OpenNest.OnClientEvent:Connect(openNests)
Net.TradeState.OnClientEvent:Connect(function(trade)
	local wasActive = Store.Trade ~= nil and Store.Trade.Active == true
	Store.SetTrade(trade)
	-- open the window when a trade starts; after that, hiding it is the player's choice
	if type(trade) == "table" and trade.Active and not wasActive then
		show(TradeWindow)
	end
end)
Net.TradeIncoming.OnClientEvent:Connect(Store.AddTradeRequest)
Net.PetEvent.OnClientEvent:Connect(function(markerName, text, color)
	local position = PetRenderer.GetPosition(markerName)
	if position then
		WorldFx.ShowFloatingText(position, text, color)
	end
end)

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
