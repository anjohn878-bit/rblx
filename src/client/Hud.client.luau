-- HUD, order tracker, car shop UI, notifications
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local gui = Instance.new("ScreenGui")
gui.Name = "DeliveryHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent, size, pos, text, textSize)
	local l = Instance.new("TextLabel")
	l.Size, l.Position = size, pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.FredokaOne
	l.TextSize = textSize or 22
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	l.Parent = parent
	return l
end
local function corner(i, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = i
end

-- Objective panel
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(300, 90)
panel.Position = UDim2.new(0.5, -150, 0, 12)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
panel.BackgroundTransparency = 0.25
panel.Parent = gui
corner(panel)
local title = label(panel, UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 6), "Go to Burger Barn for an order!", 18)
title.TextWrapped = true
local timer = label(panel, UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 40), "", 24)
local distLabel = label(panel, UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 66), "", 16)

-- Stats
local stats = label(gui, UDim2.fromOffset(280, 30), UDim2.new(0, 12, 1, -42), "", 22)
stats.TextXAlignment = Enum.TextXAlignment.Left

-- Toast
local toast = label(gui, UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0.25, 0), "", 30)
toast.TextTransparency = 1
toast.TextStrokeTransparency = 1
local toastId = 0
remotes.Notify.OnClientEvent:Connect(function(msg, color)
	toastId += 1
	local id = toastId
	toast.Text = msg
	toast.TextColor3 = color or Color3.new(1, 1, 1)
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.4
	task.delay(3, function()
		if toastId == id then
			toast.TextTransparency = 1
			toast.TextStrokeTransparency = 1
		end
	end)
end)

-- Order tracking
local target: Vector3? = nil
remotes.OrderUpdate.OnClientEvent:Connect(function(info)
	if info.active then
		target = info.target
		title.Text = "Deliver to the GREEN house!"
		timer.Text = ("%ds"):format(math.ceil(info.timeLeft))
		timer.TextColor3 = info.timeLeft > 10 and Color3.new(1, 1, 1) or Color3.fromRGB(255, 90, 90)
	else
		target = nil
		title.Text = "Go to Burger Barn for an order!"
		timer.Text, distLabel.Text = "", ""
	end
end)

RunService.RenderStepped:Connect(function()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if target and root then
		distLabel.Text = ("%d studs away"):format((root.Position - target).Magnitude)
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Cash") then
		stats.Text = ("$%d  |  %s"):format(ls.Cash.Value, ls.Rank.Value)
	end
end)

-- Spawn car button
local carBtn = Instance.new("TextButton")
carBtn.Size = UDim2.fromOffset(150, 44)
carBtn.Position = UDim2.new(1, -162, 1, -56)
carBtn.Text = "Spawn Car"
carBtn.Font = Enum.Font.FredokaOne
carBtn.TextSize = 22
carBtn.TextColor3 = Color3.new(1, 1, 1)
carBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
carBtn.Parent = gui
corner(carBtn)
carBtn.Activated:Connect(function()
	remotes.SpawnCar:FireServer()
end)

-- Shop
local shop = Instance.new("Frame")
shop.Size = UDim2.fromOffset(420, 360)
shop.Position = UDim2.new(0.5, -210, 0.5, -180)
shop.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
shop.Visible = false
shop.Parent = gui
corner(shop, 14)
label(shop, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 6), "CAR SHOP", 28)
local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(32, 32)
close.Position = UDim2.new(1, -40, 0, 8)
close.Text = "X"
close.Font = Enum.Font.FredokaOne
close.TextSize = 20
close.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
close.TextColor3 = Color3.new(1, 1, 1)
close.Parent = shop
corner(close, 8)
close.Activated:Connect(function()
	shop.Visible = false
end)

local list = Instance.new("Frame")
list.Size = UDim2.new(1, -24, 1, -60)
list.Position = UDim2.fromOffset(12, 52)
list.BackgroundTransparency = 1
list.Parent = shop
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

local rows = {}
for _, car in Config.Cars do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 52)
	row.BackgroundColor3 = Color3.fromRGB(45, 45, 56)
	row.Parent = list
	corner(row, 8)
	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(10, 52)
	swatch.BackgroundColor3 = car.color
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	corner(swatch, 5)
	local name = label(row, UDim2.fromOffset(220, 26), UDim2.fromOffset(18, 2), car.name, 20)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local sub = label(row, UDim2.fromOffset(220, 20), UDim2.fromOffset(18, 28), ("Speed %d  Power %d"):format(car.speed, car.torque), 14)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = Color3.fromRGB(190, 190, 200)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(120, 36)
	btn.Position = UDim2.new(1, -128, 0, 8)
	btn.Font = Enum.Font.FredokaOne
	btn.TextSize = 18
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Parent = row
	corner(btn, 8)
	rows[car.id] = btn
	btn.Activated:Connect(function()
		local action = btn:GetAttribute("Action")
		if action then
			remotes.ShopAction:FireServer(action, car.id)
		end
	end)
end

remotes.ShopData.OnClientEvent:Connect(function(owned, equipped, open)
	for _, car in Config.Cars do
		local btn = rows[car.id]
		if equipped == car.id then
			btn.Text, btn.BackgroundColor3 = "Equipped", Color3.fromRGB(90, 90, 100)
			btn:SetAttribute("Action", nil)
		elseif owned[car.id] then
			btn.Text, btn.BackgroundColor3 = "Equip", Color3.fromRGB(60, 120, 220)
			btn:SetAttribute("Action", "equip")
		else
			btn.Text, btn.BackgroundColor3 = "$" .. car.price, Color3.fromRGB(60, 160, 80)
			btn:SetAttribute("Action", "buy")
		end
	end
	if open then
		shop.Visible = true
	end
end)
