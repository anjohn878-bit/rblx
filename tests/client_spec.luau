--[[
	Client tests: boots the real client scripts against a booted server (mock engine), then checks the
	UI reacts to server state and that the buttons really talk to the server.
]]

local roblox = require("@lune/roblox")
local Mocks = require("./mocks")
local Game = require("./game")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local Enum = roblox.Enum

local function find(root, path: string)
	local node = root
	for name in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function click(button)
	button.Activated:Fire()
end

local function toasts(g)
	local list = {}
	for _, toast in find(g.gui, "Toasts"):GetChildren() do
		if toast.Name == "Toast" then
			for _, d in toast:GetDescendants() do
				if d:IsA("TextLabel") then
					table.insert(list, d.Text)
				end
			end
		end
	end
	return list
end

local function hasToast(g, text: string)
	for _, t in toasts(g) do
		if string.find(t, text, 1, true) then
			return true
		end
	end
	return false
end

return function(T)
	T.test("client: boots and builds the whole UI", function()
		local g = Game.bootClient()
		for _, name in { "StatsCard", "Objective", "Buttons", "Speedometer", "OrderCard", "Toasts", "ResultCard", "Waypoint", "Garage", "Splash", "StreakChip" } do
			T.truthy(find(g.gui, name), "missing " .. name)
		end
		T.truthy(find(g.gui, "Buttons.GarageButton"))
		T.truthy(find(g.gui, "Buttons.CallButton"))
		T.eq(#g.ctx.scheduler.errors, 0)
	end)

	T.test("client: every UI widget scales with the screen size", function()
		local g = Game.bootClient()
		local card = find(g.gui, "StatsCard")
		T.near(card:FindFirstChildOfClass("UIScale").Scale, 1, 1e-6, "1280x720 is the design size")

		g.ctx.Camera.ViewportSize = roblox.Vector2.new(640, 360)
		Mocks.current = g.ctx
		require("../tools/env").fireChanged(g.ctx.Camera, "ViewportSize")
		T.near(card:FindFirstChildOfClass("UIScale").Scale, 0.62, 1e-6, "small phones are clamped")

		g.ctx.Camera.ViewportSize = roblox.Vector2.new(2560, 1440)
		require("../tools/env").fireChanged(g.ctx.Camera, "ViewportSize")
		T.near(card:FindFirstChildOfClass("UIScale").Scale, 1.3, 1e-6, "big screens are clamped")
	end)

	-- HUD ---------------------------------------------------------------------------------

	T.test("hud: shows cash, rank and XP progress and follows changes", function()
		local g = Game.bootClient()
		local card = find(g.gui, "StatsCard")
		T.eq(card.Cash.Text, "$0")
		T.eq(card.Rank.Text, "RANK 1  ROOKIE")
		T.eq(card.XP.Text, "0 / 120 XP")
		T.eq(card.XPBar.Fill.Size, roblox.UDim2.fromScale(0, 1))

		Game.giveCash(g, g.player, 1234567, 60)
		g.ctx:flush()
		T.eq(card.Cash.Text, "$1,234,567")
		T.eq(card.XP.Text, "60 / 120 XP")
		T.near(card.XPBar.Fill.Size.X.Scale, 0.5, 1e-6)

		Game.giveCash(g, g.player, 0, 1000)
		g.ctx:flush()
		T.eq(card.Rank.Text, "RANK 4  PRO DRIVER")
		T.eq(card.XP.Text, "1060 / 1600 XP", "shows progress towards the next rank's threshold")
	end)

	T.test("hud: the top rank shows MAX RANK with a full bar", function()
		local g = Game.bootClient()
		Game.giveCash(g, g.player, 0, 99999)
		g.ctx:flush()
		local card = find(g.gui, "StatsCard")
		T.eq(card.XP.Text, "MAX RANK")
		T.eq(card.XPBar.Fill.Size.X.Scale, 1)
	end)

	T.test("hud: the streak chip appears after an on-time delivery", function()
		local g = Game.bootClient()
		local chip = find(g.gui, "StreakChip")
		T.eq(chip.Visible, false)
		Game.takeOrder(g, g.player)
		g.ctx:advance(4)
		Game.deliver(g, g.player)
		T.eq(chip.Visible, true)
		T.truthy(string.find(chip:FindFirstChildOfClass("TextLabel").Text, "STREAK x1", 1, true))
		T.truthy(string.find(chip:FindFirstChildOfClass("TextLabel").Text, "+5%", 1, true))
	end)

	T.test("hud: the objective banner guides each stage of the loop", function()
		local g = Game.bootClient()
		local banner = find(g.gui, "Objective.Text")
		T.truthy(string.find(banner.Text, "DISPATCH counter", 1, true), banner.Text)

		Game.takeOrder(g, g.player)
		T.truthy(string.find(banner.Text, "glowing ring", 1, true), banner.Text)

		g.ctx:advance(4)
		Game.deliver(g, g.player)
		T.truthy(string.find(banner.Text, "Head back to the depot", 1, true), banner.Text)
	end)

	T.test("hud: Garage button opens the garage, the vehicle button calls the vehicle", function()
		local g = Game.bootClient()
		click(find(g.gui, "Buttons.GarageButton"))
		T.eq(find(g.gui, "Garage").Visible, true)
		click(find(g.gui, "Buttons.CallButton"))
		T.truthy(Game.vehicleOf(g, g.player))
		T.eq(#g.ctx.FiredToServer, 1)
		T.eq(g.ctx.FiredToServer[1].Remote, "CallVehicle")
	end)

	T.test("hud: pressing V calls your vehicle, but not while typing in chat or with other keys", function()
		local g = Game.bootClient()
		local input = g.ctx.services.UserInputService.InputBegan
		input:Fire({ KeyCode = Enum.KeyCode.F }, false)
		input:Fire({ KeyCode = Enum.KeyCode.V }, true) -- typing in a text box
		T.falsy(Game.vehicleOf(g, g.player))
		input:Fire({ KeyCode = Enum.KeyCode.V }, false)
		T.truthy(Game.vehicleOf(g, g.player))
	end)

	T.test("hud: the speedometer shows only while driving, in km/h, with a proportional bar", function()
		local g = Game.bootClient()
		local speedo = find(g.gui, "Speedometer")
		g.ctx:frames(1)
		T.eq(speedo.Visible, false)

		Game.takeOrder(g, g.player) -- spawns the vehicle and sits us in it
		local vehicle = Game.vehicleOf(g, g.player)
		vehicle.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, -23)
		g.ctx:frames(1)
		T.eq(speedo.Visible, true)
		T.eq(speedo.Speed.Text, tostring(math.floor(23 * 0.8 + 0.5)))

		Mocks.leaveSeat(g.player.Character.Humanoid)
		g.ctx:frames(1)
		T.eq(speedo.Visible, false)
	end)

	-- Orders --------------------------------------------------------------------------------

	T.test("order card: hidden with no order, filled in when you take one", function()
		local g = Game.bootClient()
		local card = find(g.gui, "OrderCard")
		T.eq(card.Visible, false)

		Game.takeOrder(g, g.player)
		T.eq(card.Visible, true)
		T.eq(card.Address.Text, g.player:GetAttribute("OrderAddress"))
		T.eq(card.Package.Text, string.upper(g.player:GetAttribute("OrderPackage")))
		T.eq(card.Pay.Text, "~" .. g.Economy.formatMoney(g.player:GetAttribute("OrderReward")))
		T.truthy(string.find(card.Distance.Text, tostring(g.player:GetAttribute("OrderDistance")), 1, true))
	end)

	T.test("order card: the countdown ticks, changes colour, then shows lateness", function()
		local g = Game.bootClient()
		local Theme = g.ctx:require("StarterPlayer.StarterPlayerScripts.Client.Theme")
		Game.takeOrder(g, g.player)
		local limit = g.player:GetAttribute("OrderTimeLimit")
		local card = find(g.gui, "OrderCard")

		g.ctx:frames(1)
		T.eq(card.Timer.Text, g.Economy.formatTime(limit))
		T.eq(card.Timer.TextColor3, Theme.Green)
		T.eq(card.TimerCaption.Text, "TIME LEFT")

		g.ctx:advance(10)
		g.ctx:frames(1)
		T.eq(card.Timer.Text, g.Economy.formatTime(limit - 10))

		g.ctx:advance(limit - 10 - limit * 0.1) -- under 15% left
		g.ctx:frames(1)
		T.eq(card.Timer.TextColor3, Theme.Red)

		g.ctx:advance(limit * 0.1 + 5)
		g.ctx:frames(1)
		T.eq(card.Timer.Text, "+" .. g.Economy.formatTime(5))
		T.eq(card.TimerCaption.Text, "LATE - NO BONUS")
		T.eq(card.Timer.TextColor3, Theme.Red)
	end)

	T.test("order card: the Cancel button cancels the order on the server", function()
		local g = Game.bootClient()
		Game.takeOrder(g, g.player)
		click(find(g.gui, "OrderCard.CancelButton"))
		g.ctx:flush()
		T.eq(g.player:GetAttribute("OrderId"), 0)
		T.eq(find(g.gui, "OrderCard").Visible, false)
		T.truthy(hasToast(g, "Order cancelled."))
	end)

	T.test("waypoint: a ring and beacon mark the destination only while an order is active", function()
		local g = Game.bootClient()
		T.falsy(g.ctx.Workspace:FindFirstChild("OrderMarker"))
		Game.takeOrder(g, g.player)
		local marker = g.ctx.Workspace:FindFirstChild("OrderMarker")
		T.truthy(marker)
		local dest = g.player:GetAttribute("OrderDest")
		T.near((marker.Ring.CFrame.Position - dest).Magnitude, 0.4, 1e-3, "ring sits just above the marker position")
		T.eq(marker.Ring.Shape, Enum.PartType.Cylinder)
		-- A cylinder's axis is X: the ring has to be turned so its flat face points up.
		T.near(marker.Ring.CFrame.RightVector.Y, 1, 1e-4)
		T.eq(marker.Ring.Size.Y, g.Config.DeliveryRadius * 2)
		T.truthy(marker.Beacon.Size.Y > 100)
		T.eq(marker.LabelAnchor.BillboardGui.Adornee, marker.LabelAnchor)

		g.ctx:advance(4)
		Game.deliver(g, g.player)
		T.falsy(g.ctx.Workspace:FindFirstChild("OrderMarker"), "removed after delivery")
	end)

	T.test("waypoint: the arrow points at the target relative to where the camera faces", function()
		local g = Game.bootClient()
		local arrow = find(g.gui, "Waypoint.Arrow")
		local caption = find(g.gui, "Waypoint.Caption")
		-- Camera at origin looking down -Z. Put the player far from the depot so the arrow is shown.
		g.ctx:teleport(g.player, Vector3.new(0, 3, 400), 0)
		g.ctx.Camera.CFrame = CFrame.new(0, 10, 400)
		local dispatch = g.world.DispatchPos

		g.ctx:frames(1)
		-- dispatch is at (0, ., -7): straight ahead of a camera looking down -Z from z = 400
		T.near(arrow.Rotation, 0, 0.5, "straight ahead")
		T.truthy(string.find(caption.Text, "DISPATCH DEPOT", 1, true), caption.Text)
		T.truthy(string.find(caption.Text, tostring(math.floor((400 - dispatch.Z) + 0.5)), 1, true), caption.Text)

		-- turn the camera to look down +X: the depot is now on the camera's left
		g.ctx.Camera.CFrame = CFrame.Angles(0, -math.pi / 2, 0) + Vector3.new(0, 10, 400)
		g.ctx:frames(1)
		T.near(arrow.Rotation, -90, 0.5, "to the left")

		-- look down +Z: it's behind us
		g.ctx.Camera.CFrame = CFrame.Angles(0, math.pi, 0) + Vector3.new(0, 10, 400)
		g.ctx:frames(1)
		T.near(math.abs(arrow.Rotation), 180, 0.5, "behind")

		-- look down -X: it's on the right
		g.ctx.Camera.CFrame = CFrame.Angles(0, math.pi / 2, 0) + Vector3.new(0, 10, 400)
		g.ctx:frames(1)
		T.near(arrow.Rotation, 90, 0.5, "to the right")
	end)

	T.test("waypoint: a new player at the spawn pad is pointed at the dispatch counter", function()
		local g = Game.bootClient()
		g.ctx:frames(1)
		T.eq(find(g.gui, "Waypoint").Visible, true, "the spawn pad is 41 studs from the counter, so the arrow must show")
		T.near(find(g.gui, "Waypoint.Arrow").Rotation, 0, 0.5, "the counter is straight ahead (camera looks down -Z)")
	end)

	T.test("waypoint: hidden when you're at the depot, shown (and aimed at the order) when you have one", function()
		local g = Game.bootClient()
		local widget = find(g.gui, "Waypoint")
		g.ctx:teleport(g.player, Vector3.new(0, 3, 10), 0)
		g.ctx:frames(1)
		T.eq(widget.Visible, false, "already at the depot")

		Game.takeOrder(g, g.player)
		g.ctx:frames(1)
		T.eq(widget.Visible, true)
		T.truthy(string.find(find(widget, "Caption").Text, g.player:GetAttribute("OrderAddress"), 1, true))
	end)

	-- Notifications and results ------------------------------------------------------------------

	T.test("toasts: server notices appear, coloured by kind, and fade away", function()
		local g = Game.bootClient()
		local PlayerService = g.ctx:require("ServerScriptService.Server.PlayerService")
		PlayerService.notify(g.player, "Hello driver", "success")
		T.truthy(hasToast(g, "Hello driver"))
		local toast = find(g.gui, "Toasts.Toast")
		local Theme = g.ctx:require("StarterPlayer.StarterPlayerScripts.Client.Theme")
		T.eq(toast:FindFirstChildOfClass("UIStroke").Color, Theme.Kinds.success)

		g.ctx:advance(5)
		T.falsy(hasToast(g, "Hello driver"))
	end)

	T.test("toasts: no more than four on screen; the oldest make way", function()
		local g = Game.bootClient()
		local PlayerService = g.ctx:require("ServerScriptService.Server.PlayerService")
		for i = 1, 7 do
			PlayerService.notify(g.player, "Notice " .. i, "info")
		end
		T.eq(#toasts(g), 4)
		T.falsy(hasToast(g, "Notice 1"))
		T.truthy(hasToast(g, "Notice 7"))
	end)

	T.test("result popup: shows the payout breakdown, then hides itself", function()
		local g = Game.bootClient()
		Game.takeOrder(g, g.player)
		g.ctx:advance(4)
		Game.deliver(g, g.player)

		local r = g.ctx:fired("DeliveryResult")[1].Args[1]
		local popup = find(g.gui, "ResultCard")
		T.eq(popup.Visible, true)
		T.eq(popup.Title.Text, "DELIVERED!")
		T.truthy(string.find(popup.Address.Text, r.Address, 1, true))
		T.eq(utf8.len(popup.Stars.Text), 5)
		T.eq(popup.Total.Text, "+" .. g.Economy.formatMoney(r.Total))
		T.truthy(string.find(popup.XP.Text, "+" .. r.XP .. " XP", 1, true))

		local lines = {}
		for _, row in popup.Lines:GetChildren() do
			if row:IsA("Frame") then
				for _, label in row:GetChildren() do
					if label:IsA("TextLabel") then
						table.insert(lines, label.Text)
					end
				end
			end
		end
		T.truthy(table.find(lines, "Delivery fee"))
		T.truthy(table.find(lines, g.Economy.formatMoney(r.Base)))
		if r.TimeBonus > 0 then
			T.truthy(table.find(lines, "+" .. g.Economy.formatMoney(r.TimeBonus)))
		end

		g.ctx:advance(6)
		T.eq(popup.Visible, false)
	end)

	T.test("result popup: a late delivery is flagged", function()
		local g = Game.bootClient()
		Game.takeOrder(g, g.player)
		g.ctx:advance(g.player:GetAttribute("OrderTimeLimit") + 5)
		Game.deliver(g, g.player)
		local popup = find(g.gui, "ResultCard")
		T.truthy(string.find(popup.Title.Text, "LATE", 1, true), popup.Title.Text)
		T.eq(popup.Total.Text, "+" .. g.Economy.formatMoney(g.ctx:fired("DeliveryResult")[1].Args[1].Base))
	end)

	T.test("result popup: a celebration burst appears at the address and cleans itself up", function()
		local g = Game.bootClient()
		Game.takeOrder(g, g.player)
		g.ctx:advance(4)
		Game.deliver(g, g.player)
		local emitters = 0
		for _, d in g.ctx.Workspace:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		T.eq(emitters, 1)
		T.eq(g.ctx.ParticlesEmitted, 60)
		g.ctx:advance(4)
		emitters = 0
		for _, d in g.ctx.Workspace:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		T.eq(emitters, 0)
	end)

	T.test("result popup: rank-ups are called out", function()
		local g = Game.bootClient()
		Game.giveCash(g, g.player, 0, 115)
		Game.takeOrder(g, g.player)
		g.ctx:advance(4)
		Game.deliver(g, g.player)
		T.truthy(string.find(find(g.gui, "ResultCard.XP").Text, "RANK UP: COURIER", 1, true), find(g.gui, "ResultCard.XP").Text)
	end)

	-- Garage ------------------------------------------------------------------------------------

	local function card(g, id)
		return find(g.gui, "Garage.Window.List." .. id)
	end

	T.test("garage: lists every vehicle with a preview, and opens from the depot prompt", function()
		local g = Game.bootClient()
		local garage = find(g.gui, "Garage")
		T.eq(garage.Visible, false)
		g.world.GaragePrompt.Triggered:Fire(g.player)
		T.eq(garage.Visible, true)
		for _, spec in g.Config.Vehicles do
			local c = card(g, spec.Id)
			T.truthy(c, "no card for " .. spec.Id)
			local viewport = find(c, "Inner.Preview")
			T.eq(viewport.ClassName, "ViewportFrame")
			T.truthy(viewport:FindFirstChildOfClass("Camera"), "preview needs a camera")
			T.truthy(viewport:FindFirstChildOfClass("Model"), "preview needs a model")
		end
	end)

	T.test("garage: card states reflect ownership, cash and rank", function()
		local g = Game.bootClient()
		click(find(g.gui, "Buttons.GarageButton"))

		local scooter = card(g, "Scooter")
		T.eq(find(scooter, "Inner.ActionButton").Text, "EQUIPPED")
		T.eq(find(scooter, "Inner.ActionButton"):GetAttribute("Disabled"), true)
		T.eq(find(scooter, "Inner.Status").Text, "IN USE")

		local hatch = card(g, "Hatchback")
		T.eq(find(hatch, "Inner.ActionButton").Text, "BUY")
		T.eq(find(hatch, "Inner.ActionButton"):GetAttribute("Disabled"), true, "can't afford it yet")
		T.eq(find(hatch, "Inner.Status").Text, g.Economy.formatMoney(g.Config.VehicleById.Hatchback.Price))

		local hyper = card(g, "Hyper")
		T.eq(find(hyper, "Inner.Status").Text, "LOCKED")
		T.truthy(string.find(find(hyper, "Inner.ActionButton").Text, "RANK:", 1, true))

		Game.giveCash(g, g.player, g.Config.VehicleById.Hatchback.Price)
		g.ctx:flush()
		T.eq(find(hatch, "Inner.ActionButton"):GetAttribute("Disabled"), false, "affordable now")
		T.eq(find(hatch, "Inner.ActionButton"):GetAttribute("Action"), "Buy")
	end)

	T.test("garage: buying through the UI buys, equips, swaps your vehicle and updates the cards", function()
		local g = Game.bootClient()
		Game.giveCash(g, g.player, 2000, 200)
		g.ctx:flush()
		click(find(g.gui, "Buttons.GarageButton"))
		click(find(g.gui, "Buttons.CallButton"))
		T.eq(Game.vehicleOf(g, g.player):GetAttribute("VehicleId"), "Scooter")

		g.ctx:advance(1)
		click(find(card(g, "Hatchback"), "Inner.ActionButton"))
		g.ctx:flush()
		T.eq(g.player:GetAttribute("Equipped"), "Hatchback")
		T.eq(Game.vehicleOf(g, g.player):GetAttribute("VehicleId"), "Hatchback")
		T.truthy(hasToast(g, "Bought the City Hatch!"))
		T.eq(find(card(g, "Hatchback"), "Inner.ActionButton").Text, "EQUIPPED")
		T.eq(find(card(g, "Scooter"), "Inner.ActionButton").Text, "EQUIP")
		T.eq(find(g.gui, "Garage.Window.Cash").Text, g.Economy.formatMoney(g.player:GetAttribute("Cash")))

		g.ctx:advance(1)
		click(find(card(g, "Scooter"), "Inner.ActionButton"))
		g.ctx:flush()
		T.eq(g.player:GetAttribute("Equipped"), "Scooter")
		T.truthy(hasToast(g, "Delivery Scooter equipped."))
	end)

	T.test("garage: server refusals show up as error toasts", function()
		local g = Game.bootClient()
		click(find(g.gui, "Buttons.GarageButton"))
		-- force a Buy request the UI would normally prevent
		local button = find(card(g, "Hatchback"), "Inner.ActionButton")
		button:SetAttribute("Disabled", false)
		button:SetAttribute("Action", "Buy")
		click(button)
		T.truthy(hasToast(g, "Not enough cash"))
	end)

	T.test("garage: closes with the X button and by clicking outside, not by clicking inside", function()
		local g = Game.bootClient()
		local garage = find(g.gui, "Garage")
		click(find(g.gui, "Buttons.GarageButton"))
		T.eq(garage.Visible, true)
		click(find(garage, "Window.CloseButton"))
		T.eq(garage.Visible, false)

		click(find(g.gui, "Buttons.GarageButton"))
		click(garage) -- the dimmed backdrop
		T.eq(garage.Visible, false)
		T.eq(find(garage, "Window").Active, true, "the window swallows clicks so they don't reach the backdrop")
	end)

	T.test("garage: previews only spin while it's open", function()
		local g = Game.bootClient()
		local preview = find(card(g, "Hatchback"), "Inner.Preview")
		local model = preview:FindFirstChildOfClass("Model")
		local before = model.PrimaryPart.CFrame
		g.ctx:frames(10)
		T.eq(model.PrimaryPart.CFrame, before, "closed: not animating")
		click(find(g.gui, "Buttons.GarageButton"))
		g.ctx:frames(10)
		T.truthy(model.PrimaryPart.CFrame ~= before, "open: spinning")
	end)

	-- Splash ------------------------------------------------------------------------------------

	T.test("splash: waits for the profile, then closes on click or after a few seconds", function()
		local g = Game.bootClient()
		local splash = find(g.gui, "Splash")
		T.truthy(splash)
		-- Loaded was already true when the client started
		g.ctx:advance(0.1)
		click(splash)
		g.ctx:advance(1)
		T.falsy(find(g.gui, "Splash"), "removed after a click")

		local g2 = Game.bootClient()
		g2.ctx:advance(8)
		T.falsy(find(g2.gui, "Splash"), "auto-closes")
	end)

	T.test("splash: a click before the profile has loaded is ignored", function()
		local g = Game.boot()
		local player = g.ctx:newPlayer("Slow", 1500)
		player:SetAttribute("Loaded", false)
		g.ctx:spawnCharacter(player, Game.SPAWN)
		g.ctx:setupClient(player)
		g.ctx:run("StarterPlayer.StarterPlayerScripts.Client.Main")
		local gui = player.PlayerGui.DeliveryDriver
		local splash = find(gui, "Splash")
		click(splash)
		g.ctx:advance(1)
		T.truthy(find(gui, "Splash"), "still showing")
		player:SetAttribute("Loaded", true)
		g.ctx:flush()
		click(splash)
		g.ctx:advance(1)
		T.falsy(find(gui, "Splash"))
	end)

	-- Vehicle visuals -------------------------------------------------------------------------------

	T.test("visuals: wheels of every vehicle in the world spin, including other players'", function()
		local g = Game.bootClient()
		local bob = Game.join(g, "Bob", 1002)
		g.ctx.players.LocalPlayer = bob
		g.Remotes.CallVehicle:FireServer()
		g.ctx.players.LocalPlayer = g.player
		local bobsCar = Game.vehicleOf(g, bob)
		g.ctx:advance(0.1) -- the client notices the newly tagged vehicle
		bobsCar.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, -30)
		g.ctx:frames(5, 0.1)
		local wheel
		for _, d in bobsCar:GetDescendants() do
			if d:IsA("Motor6D") and d.Name == "Wheel_R" then -- the scooter's rear wheel
				wheel = d
			end
		end
		T.truthy(wheel, "scooter has a rear wheel")
		T.truthy(wheel.Transform ~= CFrame.new(), "wheel should have rotated")
	end)
end
