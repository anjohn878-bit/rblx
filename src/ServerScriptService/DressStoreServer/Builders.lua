-- Builds every item you can buy for your store.
-- Each builder gets (store, model, item) and adds parts to model.
-- Positions are written in plot space with store:at(x, y, z).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DressStore"):WaitForChild("Config"))
local DressModel = require(script.Parent.DressModel)
local Layout = require(script.Parent.Layout)
local Npc = require(script.Parent.Npc)
local Parts = require(script.Parent.Parts)

local FY = Layout.FLOOR_Y
local WALL_H = Layout.WALL_HEIGHT

local C = {
	floor = Color3.fromRGB(250, 236, 240),
	wall = Color3.fromRGB(255, 196, 218),
	trim = Color3.fromRGB(255, 255, 255),
	pink = Color3.fromRGB(255, 105, 180),
	hotPink = Color3.fromRGB(255, 50, 150),
	lilac = Color3.fromRGB(200, 160, 255),
	wood = Color3.fromRGB(170, 115, 80),
	darkWood = Color3.fromRGB(110, 70, 50),
	metal = Color3.fromRGB(205, 205, 215),
	gold = Color3.fromRGB(255, 200, 70),
	glass = Color3.fromRGB(180, 225, 255),
	white = Color3.fromRGB(255, 255, 255),
	dark = Color3.fromRGB(50, 40, 60),
	velvet = Color3.fromRGB(230, 90, 150),
	marble = Color3.fromRGB(245, 245, 250),
}

local Builders = {}

----------------------------------------------------------------------------
-- Shared pieces
----------------------------------------------------------------------------

-- A simple table with four legs. Returns the table top.
local function sewingTable(store, model: Model, x: number, z: number, topColor: Color3): Part
	local top = Parts.new(model, store:at(x, FY + 2.85, z), Vector3.new(3.6, 0.3, 2.4), topColor, Enum.Material.Wood)
	for _, dx in { -1.6, 1.6 } do
		for _, dz in { -1, 1 } do
			Parts.new(model, store:at(x + dx, FY + 1.35, z + dz), Vector3.new(0.25, 2.7, 0.25), C.darkWood, Enum.Material.Wood)
		end
	end
	return top
end

-- A little sewing machine sitting on a table top.
local function sewingMachine(store, model: Model, x: number, z: number, bodyColor: Color3): Part
	local y = FY + 3.0
	Parts.new(model, store:at(x, y + 0.2, z), Vector3.new(1.8, 0.4, 0.9), bodyColor)
	Parts.new(model, store:at(x + 0.65, y + 0.85, z), Vector3.new(0.45, 1.0, 0.7), bodyColor)
	local arm = Parts.new(model, store:at(x - 0.05, y + 1.2, z), Vector3.new(1.6, 0.35, 0.65), bodyColor)
	Parts.new(model, store:at(x - 0.75, y + 0.75, z), Vector3.new(0.08, 0.5, 0.08), C.metal, Enum.Material.Metal)
	Parts.cylinder(model, store:at(x + 0.2, y + 1.55, z), 0.35, 0.3, C.hotPink)
	-- a piece of fabric being sewn
	Parts.new(model, store:at(x - 0.6, y + 0.43, z), Vector3.new(1.4, 0.05, 1.3), C.lilac, Enum.Material.Fabric)
	return arm
end

local function stool(store, model: Model, x: number, z: number)
	Parts.cylinder(model, store:at(x, FY + 1.6, z), 0.3, 1.4, C.pink, Enum.Material.Fabric)
	Parts.cylinder(model, store:at(x, FY + 0.75, z), 1.5, 0.25, C.metal, Enum.Material.Metal)
end

-- A dress on a mannequin. position is the floor point under the mannequin.
local function mannequin(store, model: Model, x: number, z: number, dress, rotationY: number?, standY: number?)
	local baseY = standY or FY
	Parts.cylinder(model, store:at(x, baseY + 0.15, z), 0.3, 2.2, C.marble, Enum.Material.Marble)
	local length = DressModel.length(dress)
	local neckY = baseY + 0.3 + length + 0.15
	Parts.cylinder(model, store:at(x, baseY + 0.3 + (length + 0.2) / 2, z), length + 0.2, 0.18, C.metal, Enum.Material.Metal)
	Parts.ball(model, store:at(x, neckY + 0.55, z), 0.75, C.marble, Enum.Material.SmoothPlastic)
	Parts.cylinder(model, store:at(x, neckY + 0.12, z), 0.3, 0.22, C.marble)
	local d = DressModel.build(dress, { hanger = false })
	-- the bodice starts half a stud below the pivot, so lift it up to the neck
	d:PivotTo(store:at(x, neckY + 0.45, z, rotationY))
	d.Parent = model
end

----------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------

function Builders.starter(store, model: Model)
	-- Store floor
	Parts.new(
		model,
		store:at(0, FY - 0.2, (Layout.STORE_FRONT_Z + Layout.STORE_BACK_Z) / 2),
		Vector3.new(
			Layout.STORE_MAX_X - Layout.STORE_MIN_X,
			0.4,
			Layout.STORE_BACK_Z - Layout.STORE_FRONT_Z
		),
		C.floor,
		Enum.Material.Marble
	)
	-- Pink checkout area and welcome mat
	Parts.new(model, store:at(0, FY + 0.01, 16), Vector3.new(14, 0.02, 8), Color3.fromRGB(255, 220, 232), Enum.Material.SmoothPlastic)
	Parts.new(model, store:at(0, FY + 0.02, -19), Vector3.new(8, 0.04, 4), C.pink, Enum.Material.Fabric)
	-- Path from the gate to the door
	Parts.new(model, store:at(0, 0.22, -33.5), Vector3.new(8, 0.05, 23), Color3.fromRGB(235, 225, 230), Enum.Material.Slate)

	-- Hand sewing table
	local p = Layout.SEW_TABLE
	local top = sewingTable(store, model, p.X, p.Z, Color3.fromRGB(255, 230, 240))
	sewingMachine(store, model, p.X, p.Z, C.white)
	stool(store, model, p.X, p.Z - 2.3)
	-- fabric rolls next to the table
	for i, color in { C.pink, C.lilac, Color3.fromRGB(255, 214, 79) } do
		Parts.rod(model, store:at(-28.2, FY + 0.45 + (i - 1) * 0.8, 16.5), 2.4, 0.8, color, Enum.Material.Fabric)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SewPrompt"
	prompt.ActionText = "Sew a Dress"
	prompt.ObjectText = "Sewing Table"
	prompt.HoldDuration = Config.Sewing.HAND_HOLD_TIME
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = top
	Parts.billboard(top, Vector3.new(0, 4.2, 0), 7, 1.4, "✂️ Sewing Table", Color3.fromRGB(255, 240, 250), 50)
	store:setSewingTable(top, prompt)
end

function Builders.register(store, model: Model)
	local p = Layout.REGISTER
	Parts.new(model, store:at(p.X, FY + 1.7, p.Z), Vector3.new(10, 3.4, 2.5), C.white, Enum.Material.SmoothPlastic)
	Parts.new(model, store:at(p.X, FY + 3.55, p.Z), Vector3.new(10.4, 0.3, 2.9), C.pink, Enum.Material.Marble)
	-- pink stripe on the front of the counter
	Parts.new(model, store:at(p.X, FY + 1.7, p.Z - 1.27), Vector3.new(10, 0.6, 0.05), C.hotPink, Enum.Material.SmoothPlastic)
	local sign = Parts.new(model, store:at(p.X, FY + 2.6, p.Z - 1.3), Vector3.new(5, 0.9, 0.05), C.white)
	Parts.surfaceText(sign, Enum.NormalId.Front, "CHECKOUT", { color = C.hotPink, pixelsPerStud = 60 })

	-- The cash register
	local x = p.X + 2.6
	local base = Parts.new(model, store:at(x, FY + 4.0, p.Z), Vector3.new(1.8, 0.6, 1.4), C.dark)
	Parts.new(model, store:at(x, FY + 4.33, p.Z - 0.35), Vector3.new(1.4, 0.08, 0.6), Color3.fromRGB(120, 120, 130))
	local screen = Parts.new(model, store:at(x, FY + 4.85, p.Z + 0.3), Vector3.new(1.3, 0.8, 0.12), Color3.fromRGB(110, 255, 160), Enum.Material.Neon)
	screen.CFrame = screen.CFrame * CFrame.Angles(math.rad(-15), 0, 0)
	-- a little bag stand and flowers
	Parts.new(model, store:at(p.X - 3, FY + 4.1, p.Z), Vector3.new(0.6, 0.8, 0.9), C.pink)
	Parts.cylinder(model, store:at(p.X - 1.5, FY + 4.0, p.Z), 0.6, 0.5, C.white)
	Parts.ball(model, store:at(p.X - 1.5, FY + 4.6, p.Z), 0.7, Color3.fromRGB(255, 130, 170))

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CheckoutPrompt"
	prompt.ActionText = "Ring Up Shopper"
	prompt.ObjectText = "Cash Register"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	store:setRegister(base, prompt)
end

function Builders.rack(store, model: Model, item)
	local info = item.rack
	local dress = Config.DressById[info.dress]
	local side = info.side
	local x = side * Layout.RACK_X
	local z = info.z
	local railY = FY + Layout.RACK_RAIL_HEIGHT

	-- Coloured wall panel behind the rack
	local panel = Parts.new(model, store:at(side * 29.2, FY + 4, z), Vector3.new(0.3, 8, 8.8), dress.color, Enum.Material.SmoothPlastic)
	panel.Transparency = 0.15
	Parts.new(model, store:at(side * 29.1, FY + 8.1, z), Vector3.new(0.4, 0.3, 9.2), C.gold, Enum.Material.Metal)

	-- Chrome rack frame
	for _, dz in { -4.2, 4.2 } do
		Parts.cylinder(model, store:at(x, FY + railY / 2 - FY / 2, z + dz), railY - FY, 0.22, C.metal, Enum.Material.Metal)
		Parts.new(model, store:at(x, FY + 0.1, z + dz), Vector3.new(2.2, 0.2, 0.35), C.metal, Enum.Material.Metal)
	end
	Parts.rod(model, store:at(x, railY, z), 8.8, 0.2, C.metal, Enum.Material.Metal)

	-- Name and stock above the rack
	local topper = Parts.new(model, store:at(x, railY + 0.9, z), Vector3.new(0.3, 1.2, 3.5), dress.color)
	topper.CanCollide = false
	local _, label = Parts.billboard(topper, Vector3.new(0, 1.9, 0), 6.5, 2.2, dress.name, C.white, 60)

	local slots = {}
	for _, offset in Layout.RACK_SLOT_OFFSETS do
		table.insert(slots, {
			cf = store:at(x, railY, z + offset),
			browse = Vector3.new(side * Layout.AISLE_X, 0, z + offset),
			lookAt = Vector3.new(x, 0, z + offset),
			model = nil,
			reserved = false,
		})
	end
	store:addRack({ dress = dress, side = side, slots = slots, label = label })
end

function Builders.machine(store, model: Model, item)
	local x = item.machine.x
	local z = Layout.MACHINE_Z
	sewingTable(store, model, x, z, Color3.fromRGB(255, 205, 225))
	sewingMachine(store, model, x, z, Color3.fromRGB(255, 150, 200))
	local light = Parts.ball(model, store:at(x + 0.65, FY + 4.55, z), 0.35, Color3.fromRGB(255, 120, 190), Enum.Material.Neon)
	Parts.billboard(light, Vector3.new(0, 1.6, 0), 6, 1.1, "⚙️ Auto Sewing", Color3.fromRGB(255, 240, 250), 45)
	store:addMachine(item.machine.interval, light)
end

function Builders.walls(store, model: Model)
	local minX, maxX = Layout.STORE_MIN_X, Layout.STORE_MAX_X
	local front, back = Layout.STORE_FRONT_Z, Layout.STORE_BACK_Z
	local width = maxX - minX
	local depth = back - front
	local midZ = (front + back) / 2
	local y = FY + WALL_H / 2

	-- Back and side walls
	Parts.new(model, store:at(0, y, back - 0.5), Vector3.new(width, WALL_H, 1), C.wall)
	Parts.new(model, store:at(minX + 0.5, y, midZ), Vector3.new(1, WALL_H, depth), C.wall)
	Parts.new(model, store:at(maxX - 0.5, y, midZ), Vector3.new(1, WALL_H, depth), C.wall)

	-- Front wall with a big window on each side of the door
	local door = Layout.DOOR_HALF_WIDTH
	local segment = (width / 2) - door
	for _, side in { -1, 1 } do
		local cx = side * (door + segment / 2)
		Parts.new(model, store:at(cx, FY + 1, front + 0.5), Vector3.new(segment, 2, 1), C.wall)
		Parts.new(model, store:at(cx, FY + 11.5, front + 0.5), Vector3.new(segment, 5, 1), C.wall)
		local glass = Parts.new(model, store:at(cx, FY + 5.5, front + 0.5), Vector3.new(segment - 1, 7, 0.3), C.glass, Enum.Material.Glass)
		glass.Transparency = 0.65
		-- window frame
		Parts.new(model, store:at(side * door + side * 0.25, FY + 5.5, front + 0.5), Vector3.new(0.5, 7, 1.1), C.trim)
		Parts.new(model, store:at(side * (width / 2) - side * 0.75, FY + 5.5, front + 0.5), Vector3.new(0.5, 7, 1.1), C.trim)
		Parts.new(model, store:at(cx, FY + 2.05, front + 0.4), Vector3.new(segment, 0.3, 1.4), C.trim)
	end
	-- Above the door
	Parts.new(model, store:at(0, FY + Layout.DOOR_HEIGHT + (WALL_H - Layout.DOOR_HEIGHT) / 2, front + 0.5), Vector3.new(door * 2, WALL_H - Layout.DOOR_HEIGHT, 1), C.wall)

	-- White trim along the top
	Parts.new(model, store:at(0, FY + WALL_H + 0.25, front + 0.5), Vector3.new(width + 1, 0.5, 1.6), C.trim)
	Parts.new(model, store:at(0, FY + WALL_H + 0.25, back - 0.5), Vector3.new(width + 1, 0.5, 1.6), C.trim)
	Parts.new(model, store:at(minX + 0.5, FY + WALL_H + 0.25, midZ), Vector3.new(1.6, 0.5, depth), C.trim)
	Parts.new(model, store:at(maxX - 0.5, FY + WALL_H + 0.25, midZ), Vector3.new(1.6, 0.5, depth), C.trim)

	-- Striped awning over the door
	local stripes = 6
	local stripeWidth = (door * 2 + 2) / stripes
	for i = 1, stripes do
		local sx = -door - 1 + stripeWidth * (i - 0.5)
		local stripe = Parts.new(
			model,
			store:at(sx, FY + Layout.DOOR_HEIGHT - 0.2, front - 1.3) * CFrame.Angles(math.rad(-25), 0, 0),
			Vector3.new(stripeWidth, 0.15, 3),
			if i % 2 == 0 then C.white else C.pink,
			Enum.Material.Fabric
		)
		stripe.CanCollide = false
	end
end

function Builders.sign(store, model: Model)
	local front = Layout.STORE_FRONT_Z
	local board = Parts.new(model, store:at(0, FY + 12.3, front - 0.25), Vector3.new(22, 3.4, 0.4), C.hotPink)
	local name = if store.owner then store.owner.DisplayName .. "'s" else "The"
	Parts.surfaceText(board, Enum.NormalId.Front, name .. " Dress Store", {
		color = C.white,
		stroke = Color3.fromRGB(150, 0, 90),
		pixelsPerStud = 40,
	})
	-- glowing border
	for _, dy in { -1.8, 1.8 } do
		Parts.new(model, store:at(0, FY + 12.3 + dy, front - 0.5), Vector3.new(22.4, 0.2, 0.2), C.white, Enum.Material.Neon)
	end
	for _, dx in { -11.1, 11.1 } do
		Parts.new(model, store:at(dx, FY + 12.3, front - 0.5), Vector3.new(0.2, 3.8, 0.2), C.white, Enum.Material.Neon)
	end
	Parts.light(board, Color3.fromRGB(255, 150, 210), 18, 1.2)

	-- "OPEN" sign in the window
	local open = Parts.new(model, store:at(9.5, FY + 6.5, front + 1.2), Vector3.new(3.6, 1.4, 0.1), C.dark)
	Parts.surfaceText(open, Enum.NormalId.Front, "OPEN", { color = Color3.fromRGB(255, 80, 170), pixelsPerStud = 60 })
	Parts.noCollide(model)
	board.CanCollide = true
end

function Builders.window(store, model: Model)
	local displays = {
		{ x = -21.5, dress = "Party" },
		{ x = -12.5, dress = "Evening" },
		{ x = 12.5, dress = "Ball" },
		{ x = 21.5, dress = "Wedding" },
	}
	for _, display in displays do
		mannequin(store, model, display.x, -19.4, Config.DressById[display.dress])
	end
	for _, side in { -1, 1 } do
		local lamp = Parts.new(model, store:at(side * 17, FY + 9.5, -19.5), Vector3.new(1, 0.3, 1), C.white, Enum.Material.Neon)
		Parts.light(lamp, Color3.fromRGB(255, 230, 240), 14, 1.3)
	end
end

function Builders.fitting(store, model: Model)
	local back = Layout.STORE_BACK_Z - 1
	local front = 17
	local depth = back - front
	local midZ = (front + back) / 2
	local height = 9
	local curtainColors = { Color3.fromRGB(150, 60, 200), C.hotPink }
	local booths = { 16.6, 24.6 }

	for _, x in { 12.6, 20.6, 28.4 } do
		Parts.new(model, store:at(x, FY + height / 2, midZ), Vector3.new(0.4, height, depth), C.white)
	end
	-- header with the sign
	local header = Parts.new(model, store:at(20.5, FY + height + 0.6, front), Vector3.new(16.2, 1.2, 0.4), C.lilac)
	Parts.surfaceText(header, Enum.NormalId.Front, "Fitting Rooms", { color = C.white, stroke = Color3.fromRGB(110, 40, 150) })

	for i, x in booths do
		-- curtain rod and curtain
		Parts.rod(model, store:at(x, FY + 8.4, front + 0.1) * CFrame.Angles(0, math.rad(90), 0), 7.6, 0.12, C.gold, Enum.Material.Metal)
		local curtain = Parts.new(model, store:at(x + 1.1, FY + 4.3, front + 0.15), Vector3.new(5.2, 8, 0.2), curtainColors[i], Enum.Material.Fabric)
		curtain.CanCollide = false
		-- mirror on the back wall
		local mirror = Parts.new(model, store:at(x, FY + 4.5, back - 0.15), Vector3.new(3, 6, 0.1), Color3.fromRGB(220, 235, 245), Enum.Material.Glass)
		mirror.Reflectance = 0.5
		Parts.new(model, store:at(x, FY + 4.5, back - 0.1), Vector3.new(3.4, 6.4, 0.05), C.gold, Enum.Material.Metal)
		-- a little stool
		Parts.cylinder(model, store:at(x - 1.8, FY + 0.9, back - 1.5), 0.3, 1.2, C.pink, Enum.Material.Fabric)
		Parts.cylinder(model, store:at(x - 1.8, FY + 0.4, back - 1.5), 0.8, 0.25, C.metal, Enum.Material.Metal)
	end
end

function Builders.cashier(store, model: Model)
	store:setCashier()
	-- Loading the character can take a moment, so do it in the background
	local session = store.session
	task.spawn(function()
		local character = Npc.create("Cashier", C.hotPink)
		if store.session ~= session then
			character.model:Destroy()
			return
		end
		local p = Layout.REGISTER
		character.model:PivotTo(store:at(p.X - 1, FY + character.groundOffset, p.Z + 2.6))
		character.root.Anchored = true
		character.model.Parent = model
		Npc.setBubble(character, "💁 Cashier")
	end)
end

function Builders.roof(store, model: Model)
	local minX, maxX = Layout.STORE_MIN_X, Layout.STORE_MAX_X
	local front, back = Layout.STORE_FRONT_Z, Layout.STORE_BACK_Z
	local midZ = (front + back) / 2
	local roofY = FY + WALL_H + 0.5
	Parts.new(model, store:at(0, roofY + 0.5, midZ), Vector3.new(maxX - minX + 2, 1, back - front + 2), C.white)
	Parts.new(model, store:at(0, roofY + 1.2, midZ), Vector3.new(maxX - minX - 6, 0.4, back - front - 6), C.pink)
	-- ceiling lights
	for _, x in { -18, 0, 18 } do
		for _, z in { -10, 6 } do
			local panel = Parts.new(model, store:at(x, FY + WALL_H - 0.15, z), Vector3.new(5, 0.2, 1.4), Color3.fromRGB(255, 250, 240), Enum.Material.Neon)
			panel.CanCollide = false
			Parts.light(panel, Color3.fromRGB(255, 240, 230), 28, 1.1)
		end
	end
end

function Builders.lights(store, model: Model)
	local ceiling = FY + WALL_H
	for _, spot in { { -12, -6 }, { 12, -6 }, { -12, 6 }, { 12, 6 }, { 0, 0 } } do
		local x, z = spot[1], spot[2]
		Parts.cylinder(model, store:at(x, ceiling - 1, z), 2, 0.12, C.gold, Enum.Material.Metal)
		Parts.cylinder(model, store:at(x, ceiling - 2.1, z), 0.25, 3.2, C.gold, Enum.Material.Metal)
		local crystal = Parts.ball(model, store:at(x, ceiling - 2.6, z), 1.1, Color3.fromRGB(255, 240, 255), Enum.Material.Glass)
		crystal.Transparency = 0.2
		Parts.light(crystal, Color3.fromRGB(255, 220, 240), 22, 1.4)
		for i = 0, 5 do
			local angle = i * math.pi / 3
			Parts.ball(
				model,
				store:at(x + math.cos(angle) * 1.45, ceiling - 2.55, z + math.sin(angle) * 1.45),
				0.4,
				Color3.fromRGB(230, 230, 255),
				Enum.Material.Glass
			)
		end
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = Color3.fromRGB(255, 220, 250)
		sparkle.Parent = crystal
	end
	Parts.noCollide(model)
end

function Builders.sofas(store, model: Model)
	for _, side in { -1, 1 } do
		local x = side * 11
		-- two seats per sofa so friends can sit together
		for _, dz in { -1.5, 1.5 } do
			local seat = Instance.new("Seat")
			seat.Anchored = true
			seat.Size = Vector3.new(2.6, 1.1, 2.4)
			seat.CFrame = store:at(x, FY + 0.95, dz, if side < 0 then -math.pi / 2 else math.pi / 2)
			seat.Color = C.velvet
			seat.Material = Enum.Material.Fabric
			seat.TopSurface = Enum.SurfaceType.Smooth
			seat.BottomSurface = Enum.SurfaceType.Smooth
			seat.Parent = model
		end
		Parts.new(model, store:at(x, FY + 0.2, 0), Vector3.new(2.8, 0.4, 6.4), C.darkWood, Enum.Material.Wood)
		Parts.new(model, store:at(x + side * 1.4, FY + 2, 0), Vector3.new(0.8, 2.6, 6.4), C.velvet, Enum.Material.Fabric)
		for _, dz in { -3.4, 3.4 } do
			Parts.new(model, store:at(x + side * 0.1, FY + 1.5, dz), Vector3.new(3, 1.6, 0.6), C.velvet, Enum.Material.Fabric)
		end
		-- cushion
		Parts.new(model, store:at(x + side * 0.85, FY + 2.1, -1.5), Vector3.new(0.4, 1, 1), C.white, Enum.Material.Fabric)
	end
	-- a round rug in front of each sofa
	for _, side in { -1, 1 } do
		local rug = Parts.cylinder(model, store:at(side * 7.8, FY + 0.02, 0), 0.04, 5, C.lilac, Enum.Material.Fabric)
		rug.CanCollide = false
	end
end

function Builders.handbags(store, model: Model)
	local back = Layout.STORE_BACK_Z - 1
	local bagColors = { C.hotPink, C.gold, C.dark, Color3.fromRGB(150, 60, 200), C.white, Color3.fromRGB(255, 140, 110) }
	for row, y in { FY + 5.8, FY + 7.8 } do
		Parts.new(model, store:at(0, y, back - 0.45), Vector3.new(9, 0.25, 0.9), C.white)
		for i = 1, 4 do
			local x = -3.6 + (i - 1) * 2.4
			local color = bagColors[((row * 4 + i) % #bagColors) + 1]
			Parts.new(model, store:at(x, y + 0.5, back - 0.45), Vector3.new(1.1, 0.75, 0.45), color, Enum.Material.Leather)
			Parts.new(model, store:at(x - 0.35, y + 1.05, back - 0.45), Vector3.new(0.08, 0.4, 0.08), color, Enum.Material.Leather)
			Parts.new(model, store:at(x + 0.35, y + 1.05, back - 0.45), Vector3.new(0.08, 0.4, 0.08), color, Enum.Material.Leather)
			Parts.new(model, store:at(x, y + 1.25, back - 0.45), Vector3.new(0.78, 0.08, 0.08), color, Enum.Material.Leather)
		end
	end
	local plaque = Parts.new(model, store:at(0, FY + 9.6, back - 0.1), Vector3.new(7, 1.1, 0.1), C.gold, Enum.Material.Metal)
	Parts.surfaceText(plaque, Enum.NormalId.Front, "DESIGNER", { color = C.dark, pixelsPerStud = 60 })
	Parts.noCollide(model)
end

function Builders.runway(store, model: Model)
	local length = 18
	local cz = -1
	Parts.new(model, store:at(0, FY + 0.5, cz), Vector3.new(6, 1, length), C.marble, Enum.Material.Marble)
	for _, side in { -1, 1 } do
		Parts.new(model, store:at(side * 3.05, FY + 0.95, cz), Vector3.new(0.15, 0.15, length), C.hotPink, Enum.Material.Neon)
	end
	-- steps at the front
	Parts.new(model, store:at(0, FY + 0.25, cz - length / 2 - 0.6), Vector3.new(4, 0.5, 1.2), C.marble, Enum.Material.Marble)
	-- backdrop
	local backdrop = Parts.new(model, store:at(0, FY + 4.5, cz + length / 2 + 0.25), Vector3.new(7, 8, 0.5), C.hotPink)
	Parts.surfaceText(backdrop, Enum.NormalId.Front, "FASHION\nWEEK", { color = C.white, stroke = Color3.fromRGB(150, 0, 90) })
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 200, 240)
	sparkles.Parent = backdrop
	-- models on the runway
	mannequin(store, model, 0, cz - 4, Config.DressById.Ball, 0, FY + 1)
	mannequin(store, model, 0, cz + 3, Config.DressById.Party, 0, FY + 1)
	for _, z in { cz - 6, cz + 5 } do
		local lamp = Parts.new(model, store:at(0, FY + 1.05, z), Vector3.new(0.6, 0.1, 0.6), C.white, Enum.Material.Neon)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Top
		light.Angle = 60
		light.Range = 14
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 220, 240)
		light.Parent = lamp
	end
end

function Builders.fountain(store, model: Model)
	local x, z = -36, -31
	local water = Color3.fromRGB(90, 175, 255)
	Parts.cylinder(model, store:at(x, 0.9, z), 1.6, 10, C.marble, Enum.Material.Marble)
	local pool = Parts.cylinder(model, store:at(x, 1.65, z), 0.2, 9, water, Enum.Material.Glass)
	pool.Transparency = 0.25
	Parts.cylinder(model, store:at(x, 3, z), 3, 1, C.marble, Enum.Material.Marble)
	Parts.cylinder(model, store:at(x, 4.6, z), 0.5, 3.6, C.marble, Enum.Material.Marble)
	local topWater = Parts.cylinder(model, store:at(x, 4.85, z), 0.1, 3.2, water, Enum.Material.Glass)
	topWater.Transparency = 0.25
	local spout = Parts.ball(model, store:at(x, 5.3, z), 0.8, C.hotPink, Enum.Material.Marble)

	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	spray.LightEmission = 0.3
	spray.Size = NumberSequence.new(0.35, 0.1)
	spray.Transparency = NumberSequence.new(0.1, 0.8)
	spray.Lifetime = NumberRange.new(0.9, 1.2)
	spray.Rate = 45
	spray.Speed = NumberRange.new(9, 11)
	spray.SpreadAngle = Vector2.new(18, 18)
	spray.Acceleration = Vector3.new(0, -28, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = spout
	Parts.light(spout, Color3.fromRGB(150, 210, 255), 12, 0.8)

	-- flowers around the fountain
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local fx, fz = x + math.cos(angle) * 6, z + math.sin(angle) * 6
		Parts.cylinder(model, store:at(fx, 0.5, fz), 0.6, 1.4, Color3.fromRGB(90, 170, 80), Enum.Material.Grass)
		Parts.ball(model, store:at(fx, 1.0, fz), 0.7, if i % 2 == 0 then C.hotPink else C.white)
	end
end

function Builders.statue(store, model: Model)
	local x, z = 36, -31
	Parts.new(model, store:at(x, 1.5, z), Vector3.new(5, 3, 5), C.marble, Enum.Material.Marble)
	Parts.new(model, store:at(x, 3.1, z), Vector3.new(5.4, 0.2, 5.4), C.gold, Enum.Material.Metal)
	local plaque = Parts.new(model, store:at(x, 1.6, z - 2.55), Vector3.new(4, 1.2, 0.1), C.gold, Enum.Material.Metal)
	Parts.surfaceText(plaque, Enum.NormalId.Front, "Golden Dress Award", { color = C.dark, pixelsPerStud = 50 })

	local dress = Config.DressById.Wedding
	local scale = 2.2
	local golden = DressModel.build(dress, { scale = scale, hanger = false, color = C.gold, material = Enum.Material.Foil })
	local top = 3.2 + DressModel.length(dress) * scale
	golden:PivotTo(store:at(x, top, z))
	golden.Parent = model
	Parts.ball(model, store:at(x, top - 0.2, z), 1.6, C.gold, Enum.Material.Foil)
	local glow = Parts.ball(model, store:at(x, top + 1.8, z), 0.8, Color3.fromRGB(255, 240, 150), Enum.Material.Neon)
	Parts.light(glow, Color3.fromRGB(255, 220, 120), 20, 1.6)
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = C.gold
	sparkles.Parent = glow
end

return Builders
