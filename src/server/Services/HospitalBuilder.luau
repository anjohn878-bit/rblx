--[[
	HospitalBuilder
	Procedurally builds a player's hospital for its current level and rooms,
	and returns a "layout" describing every point NPCs need (seats, beds,
	routes...). Called again after every upgrade, so each level visibly
	changes the building.

	Plot-local coordinates (origin = front-centre of the plot):
	  +X right, +Y up, +Z away from the road (deeper into the plot)

	  z = 0 ........ plot front edge (road side)
	  z = 16 ....... hospital front wall (main entrance at x = 0)
	  z 16..46 ..... lobby: reception (left), pharmacy (left back), waiting (right)
	  z 46..54 ..... main corridor
	  z 54..72 ..... exam rooms row
	  z 72..80 ..... back corridor          (only when special rooms exist)
	  z 80..100 .... special rooms row      (only when special rooms exist)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local HospitalLevels = require(Config:WaitForChild("HospitalLevels"))
local Rooms = require(Config:WaitForChild("Rooms"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))

local Build = require(script.Parent.Parent.Util.Build)
local Collision = require(script.Parent.Parent.Util.Collision)
local RigBuilder = require(script.Parent.Parent.NPC.RigBuilder)

local PLOT_TOP = 0.4
local FLOOR = 0.6
local ROOM_W = 12
local EXAM_D = 18
local LOBBY_D = 30
local CORRIDOR_D = 8
local BACK_D = 20
local BACK_ROOM_W = 20
local Z_FRONT = 16
local INTERIOR_H = 10
local DOOR_W = 12
local ROOM_DOOR_W = 6

local HospitalBuilder = {}

export type Seat = { Top: CFrame, Aisle: Vector3, Lane: Vector3 }
export type ExamRoom = {
	Index: number,
	Front: Vector3,
	Entry: Vector3,
	BedSide: Vector3,
	BedTop: CFrame,
	DoctorIdle: Vector3,
	DoctorIdleLook: Vector3,
	DoctorWork: Vector3,
	DoctorWorkLook: Vector3,
	Center: Vector3,
}
export type Layout = {
	Nodes: { [string]: Vector3 },
	Looks: { [string]: Vector3 },
	Seats: { Seat },
	ExamRooms: { ExamRoom },
	RoomCenters: { [string]: Vector3 },
	PlayerSpawn: CFrame,
	LawnSpawn: CFrame,
	BoundsCFrame: CFrame,
	BoundsSize: Vector3,
	Center: Vector3,
}

type Ctx = {
	Model: Model,
	Origin: CFrame,
	Style: HospitalLevels.Style,
	Level: HospitalLevels.Level,
}

-- Local helpers -------------------------------------------------------------

local function L(ctx: Ctx, x: number, y: number, z: number): CFrame
	return ctx.Origin * CFrame.new(x, y, z)
end

local function P(ctx: Ctx, x: number, y: number, z: number): Vector3
	return ctx.Origin:PointToWorldSpace(Vector3.new(x, y, z))
end

local function D(ctx: Ctx, x: number, z: number): Vector3
	return ctx.Origin:VectorToWorldSpace(Vector3.new(x, 0, z))
end

-- Local CFrame at (x,y,z) looking along local direction (dx, dz).
local function F(ctx: Ctx, x: number, y: number, z: number, dx: number, dz: number): CFrame
	local at = Vector3.new(x, y, z)
	return ctx.Origin * CFrame.lookAt(at, at + Vector3.new(dx, 0, dz))
end

type BoxOpts = {
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	Group: string?,
	Name: string?,
	CastShadow: boolean?,
}

local function box(ctx: Ctx, parent: Instance, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, color: Color3, opts: BoxOpts?): Part
	local o: BoxOpts = opts or {}
	return Build.Part(parent, {
		Name = o.Name,
		Size = Vector3.new(math.max(math.abs(x1 - x0), 0.05), math.max(math.abs(y1 - y0), 0.05), math.max(math.abs(z1 - z0), 0.05)),
		CFrame = L(ctx, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Color = color,
		Material = o.Material,
		Transparency = o.Transparency,
		CanCollide = o.CanCollide,
		Group = o.Group,
		CastShadow = o.CastShadow,
	})
end

local function furniture(ctx: Ctx, parent: Instance, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, color: Color3, material: Enum.Material?): Part
	return box(ctx, parent, x0, y0, z0, x1, y1, z1, color, { Group = Collision.Furniture, Material = material })
end

type Door = { Center: number, Width: number, Height: number }

-- Wall running along X at depth z, with optional door openings.
local function wallX(ctx: Ctx, parent: Instance, z: number, x0: number, x1: number, y0: number, y1: number, thickness: number, color: Color3, material: Enum.Material?, doors: { Door }?)
	local list = table.clone(doors or {})
	table.sort(list, function(a, b)
		return a.Center < b.Center
	end)
	local cursor = x0
	local t = thickness / 2
	for _, door in list do
		local left = door.Center - door.Width / 2
		local right = door.Center + door.Width / 2
		if left > cursor then
			box(ctx, parent, cursor, y0, z - t, left, y1, z + t, color, { Material = material })
		end
		if y0 + door.Height < y1 then
			box(ctx, parent, left, y0 + door.Height, z - t, right, y1, z + t, color, { Material = material })
		end
		cursor = right
	end
	if cursor < x1 then
		box(ctx, parent, cursor, y0, z - t, x1, y1, z + t, color, { Material = material })
	end
end

-- Wall running along Z at x.
local function wallZ(ctx: Ctx, parent: Instance, x: number, z0: number, z1: number, y0: number, y1: number, thickness: number, color: Color3, material: Enum.Material?)
	local t = thickness / 2
	box(ctx, parent, x - t, y0, z0, x + t, y1, z1, color, { Material = material })
end

local function sign(_ctx: Ctx, parent: Instance, cf: CFrame, width: number, height: number, text: string, background: Color3, textColor: Color3?): Part
	local part = Build.Part(parent, {
		Name = "Sign",
		Size = Vector3.new(width, height, 0.25),
		CFrame = cf,
		Color = background,
		CanCollide = false,
	})
	Build.SurfaceText(part, text, { TextColor = textColor or Color3.new(1, 1, 1), StrokeColor = Color3.fromRGB(30, 30, 40), RichText = true })
	return part
end

local function plant(ctx: Ctx, parent: Instance, x: number, z: number, scale: number?)
	local s = scale or 1
	Build.Cylinder(parent, L(ctx, x, FLOOR, z), 1.6 * s, 1.6 * s, { Color = Color3.fromRGB(190, 110, 70), Group = Collision.Furniture })
	Build.Ball(parent, L(ctx, x, FLOOR + 1.6 * s + 1.1 * s, z), 2.6 * s, { Color = Color3.fromRGB(70, 170, 80), Material = Enum.Material.Grass, CanCollide = false })
end

local function tree(ctx: Ctx, parent: Instance, x: number, z: number, scale: number?)
	local s = scale or 1
	Build.Cylinder(parent, L(ctx, x, PLOT_TOP, z), 6 * s, 1.4 * s, { Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood })
	Build.Ball(parent, L(ctx, x, PLOT_TOP + 7.5 * s, z), 7 * s, { Color = Color3.fromRGB(60, 160, 70), Material = Enum.Material.Grass, CanCollide = false })
	Build.Ball(parent, L(ctx, x + 1.2 * s, PLOT_TOP + 9.5 * s, z - 0.6 * s), 5 * s, { Color = Color3.fromRGB(80, 180, 85), Material = Enum.Material.Grass, CanCollide = false })
end

local function staff(ctx: Ctx, parent: Instance, name: string, x: number, z: number, dx: number, dz: number, uniform: Color3)
	local skins = { Color3.fromRGB(255, 220, 190), Color3.fromRGB(200, 150, 110), Color3.fromRGB(130, 90, 60) }
	local model = RigBuilder.CreateStaff(name, uniform, skins[math.random(1, #skins)], Color3.fromRGB(60, 40, 30))
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	model:PivotTo(F(ctx, x, FLOOR + 3, z, dx, dz))
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.EvaluateStateMachine = false
	model.Parent = parent
	CollectionService:AddTag(model, "Staff")
	model:SetAttribute("StaffName", name)
end

-- Builds a simple parked ambulance (decor).
local function ambulance(ctx: Ctx, parent: Instance, x: number, z: number, dx: number, dz: number)
	local model = Build.Model(parent, "Ambulance")
	local base = F(ctx, x, PLOT_TOP, z, dx, dz)
	local function part(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
		Build.Part(model, { Size = size, CFrame = base * offset, Color = color, Material = material, Shape = shape })
	end
	part(Vector3.new(7, 6, 11), CFrame.new(0, 4, 1.5), Color3.fromRGB(250, 250, 250))
	part(Vector3.new(7, 4, 5), CFrame.new(0, 3, -6.5), Color3.fromRGB(250, 250, 250))
	part(Vector3.new(6.6, 2, 0.2), CFrame.new(0, 4, -9.05), Color3.fromRGB(150, 210, 255), Enum.Material.Glass)
	part(Vector3.new(7.1, 0.8, 16.2), CFrame.new(0, 3, -1), Color3.fromRGB(220, 50, 50))
	part(Vector3.new(1.2, 3, 0.2), CFrame.new(0, 4.6, 7.05), Color3.fromRGB(220, 50, 50))
	part(Vector3.new(3, 1, 0.2), CFrame.new(0, 4.6, 7.06), Color3.fromRGB(220, 50, 50))
	part(Vector3.new(1.5, 0.6, 1), CFrame.new(-1.6, 7.3, -2), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	part(Vector3.new(1.5, 0.6, 1), CFrame.new(1.6, 7.3, -2), Color3.fromRGB(40, 120, 255), Enum.Material.Neon)
	for _, wheel in { { -3.5, -5 }, { 3.5, -5 }, { -3.5, 5 }, { 3.5, 5 } } do
		part(Vector3.new(1, 3, 3), CFrame.new(wheel[1], 1.5, wheel[2]), Color3.fromRGB(30, 30, 30), nil, Enum.PartType.Cylinder)
	end
end

-- Special room furniture ------------------------------------------------------

local FURNISH: { [string]: (ctx: Ctx, parent: Instance, x0: number, z0: number, x1: number, z1: number, color: Color3) -> () } = {}

FURNISH.Laboratory = function(ctx, parent, x0, z0, x1, z1, _color)
	local cx = (x0 + x1) / 2
	furniture(ctx, parent, x0 + 1, FLOOR, z1 - 4, x1 - 1, FLOOR + 3, z1 - 1.5, Color3.fromRGB(240, 244, 248))
	furniture(ctx, parent, cx - 4, FLOOR, z0 + 7, cx + 4, FLOOR + 3, z0 + 9.5, Color3.fromRGB(240, 244, 248))
	local beakers = { Color3.fromRGB(80, 220, 120), Color3.fromRGB(80, 160, 255), Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 200, 60) }
	for i, c in beakers do
		Build.Cylinder(parent, L(ctx, x0 + 2 + i * 3, FLOOR + 3, z1 - 2.7), 1.4, 0.8, { Color = c, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false })
		Build.Cylinder(parent, L(ctx, cx - 3 + i * 1.5, FLOOR + 3, z0 + 8.2), 1, 0.6, { Color = c, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false })
	end
	-- Microscope
	furniture(ctx, parent, cx + 2, FLOOR + 3, z0 + 7.8, cx + 2.8, FLOOR + 5, z0 + 8.8, Color3.fromRGB(60, 60, 70))
	-- Fridge
	furniture(ctx, parent, x1 - 3.5, FLOOR, z0 + 1.5, x1 - 1, FLOOR + 7, z0 + 4, Color3.fromRGB(220, 230, 240), Enum.Material.Metal)
end

FURNISH.ChildrensWard = function(ctx, parent, x0, z0, x1, z1, _color)
	local bedColors = { Color3.fromRGB(255, 170, 200), Color3.fromRGB(150, 210, 255), Color3.fromRGB(255, 220, 120) }
	for i, c in bedColors do
		local bx = x0 + 1 + (i - 1) * 6
		furniture(ctx, parent, bx, FLOOR, z1 - 6, bx + 4, FLOOR + 1.6, z1 - 1, c)
		furniture(ctx, parent, bx + 0.5, FLOOR + 1.6, z1 - 2.2, bx + 3.5, FLOOR + 2, z1 - 1.2, Color3.new(1, 1, 1))
	end
	-- Rug + toy blocks
	box(ctx, parent, x0 + 4, FLOOR, z0 + 4, x1 - 4, FLOOR + 0.06, z0 + 9, Color3.fromRGB(120, 200, 255))
	local toyColors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 200, 80), Color3.fromRGB(80, 120, 255), Color3.fromRGB(255, 200, 40) }
	for i, c in toyColors do
		furniture(ctx, parent, x0 + 5 + i * 1.6, FLOOR, z0 + 6, x0 + 6.2 + i * 1.6, FLOOR + 1.2, z0 + 7.2, c)
	end
	-- Balloons
	for i, c in toyColors do
		Build.Ball(parent, L(ctx, x1 - 2 - i * 0.9, FLOOR + 7 + (i % 2), z0 + 2), 1.2, { Color = c, CanCollide = false })
	end
end

FURNISH.EmergencyRoom = function(ctx, parent, x0, z0, x1, z1, _color)
	local cx = (x0 + x1) / 2
	box(ctx, parent, cx - 4, FLOOR, z0 + 7, cx + 4, FLOOR + 0.06, z0 + 9, Color3.fromRGB(230, 50, 50))
	box(ctx, parent, cx - 1, FLOOR, z0 + 4, cx + 1, FLOOR + 0.06, z0 + 12, Color3.fromRGB(230, 50, 50))
	-- Stretchers
	for i = 0, 1 do
		local sx = x0 + 2 + i * 11
		furniture(ctx, parent, sx, FLOOR, z1 - 6, sx + 5, FLOOR + 2.4, z1 - 1.5, Color3.fromRGB(235, 235, 240))
		-- Heart monitor
		local monitor = furniture(ctx, parent, sx + 5.3, FLOOR + 3, z1 - 1.6, sx + 7, FLOOR + 5, z1 - 1.2, Color3.fromRGB(30, 30, 40))
		Build.SurfaceText(monitor, "♥ 72", { Face = Enum.NormalId.Front, TextColor = Color3.fromRGB(80, 255, 120) })
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 60)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = box(ctx, parent, cx - 0.5, FLOOR + INTERIOR_H - 1, (z0 + z1) / 2 - 0.5, cx + 0.5, FLOOR + INTERIOR_H - 0.5, (z0 + z1) / 2 + 0.5, Color3.fromRGB(255, 60, 60), { Material = Enum.Material.Neon, CanCollide = false })
end

FURNISH.Surgery = function(ctx, parent, x0, z0, x1, z1, _color)
	local cx = (x0 + x1) / 2
	local cz = (z0 + z1) / 2
	furniture(ctx, parent, cx - 3, FLOOR, cz - 1.5, cx + 3, FLOOR + 3, cz + 1.5, Color3.fromRGB(70, 200, 200))
	local lamp = Build.Cylinder(parent, L(ctx, cx, FLOOR + INTERIOR_H - 2.6, cz), 0.6, 4, { Color = Color3.fromRGB(240, 240, 250), Material = Enum.Material.Neon, CanCollide = false })
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Left
	spot.Range = 14
	spot.Brightness = 2
	spot.Angle = 70
	spot.Parent = lamp
	furniture(ctx, parent, x0 + 1.5, FLOOR, z1 - 3, x0 + 4, FLOOR + 5, z1 - 1, Color3.fromRGB(40, 40, 50))
	furniture(ctx, parent, x1 - 4, FLOOR, z0 + 1.5, x1 - 1.5, FLOOR + 3, z0 + 4, Color3.fromRGB(200, 205, 215), Enum.Material.Metal)
end

FURNISH.Specialist = function(ctx, parent, x0, z0, x1, z1, color)
	local cx = (x0 + x1) / 2
	local cz = (z0 + z1) / 2 + 2
	-- Scanner ring + sliding bed
	local ring = Build.Part(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 8, 8),
		CFrame = L(ctx, cx + 2, FLOOR + 4, cz),
		Color = Color3.fromRGB(240, 240, 248),
		Group = Collision.Furniture,
	})
	ring.Name = "Scanner"
	Build.Part(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.1, 4.4, 4.4),
		CFrame = L(ctx, cx + 2, FLOOR + 4, cz),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	furniture(ctx, parent, cx - 6, FLOOR, cz - 1.2, cx + 2, FLOOR + 2.6, cz + 1.2, Color3.fromRGB(230, 230, 240))
	furniture(ctx, parent, x0 + 1.5, FLOOR, z0 + 2, x0 + 6, FLOOR + 2.8, z0 + 4.5, Color3.fromRGB(110, 80, 160))
end

FURNISH.VIP = function(ctx, parent, x0, z0, x1, z1, _color)
	local cx = (x0 + x1) / 2
	box(ctx, parent, x0 + 1, FLOOR, z0 + 1, x1 - 1, FLOOR + 0.06, z1 - 1, Color3.fromRGB(170, 30, 50), { Material = Enum.Material.Fabric })
	furniture(ctx, parent, cx - 3.5, FLOOR, z1 - 7, cx + 3.5, FLOOR + 2.2, z1 - 1, Color3.fromRGB(255, 205, 60), Enum.Material.Foil)
	furniture(ctx, parent, cx - 3, FLOOR + 2.2, z1 - 6.5, cx + 3, FLOOR + 2.8, z1 - 1.5, Color3.fromRGB(250, 245, 235), Enum.Material.Fabric)
	furniture(ctx, parent, x0 + 1.5, FLOOR, z0 + 2, x0 + 7, FLOOR + 2, z0 + 4.5, Color3.fromRGB(120, 30, 50), Enum.Material.Fabric)
	local chandelier = Build.Ball(parent, L(ctx, cx, FLOOR + INTERIOR_H - 2, (z0 + z1) / 2), 1.8, { Color = Color3.fromRGB(255, 230, 150), Material = Enum.Material.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 140)
	light.Range = 16
	light.Parent = chandelier
	plant(ctx, parent, x1 - 2.5, z0 + 3)
end

-- Main build -----------------------------------------------------------------

export type BuildData = {
	HospitalLevel: number,
	Rooms: { [string]: boolean },
}

function HospitalBuilder.Build(plotFolder: Folder, origin: CFrame, data: BuildData, ownerName: string): Layout
	local old = plotFolder:FindFirstChild("Hospital")
	if old then
		old:Destroy()
	end

	local level = HospitalLevels.Get(data.HospitalLevel)
	local style = level.Style
	local model = Instance.new("Model")
	model.Name = "Hospital"
	local ctx: Ctx = { Model = model, Origin = origin, Style = style, Level = level }

	local W = level.Width
	local hw = W / 2
	local H = style.WallHeight
	local E = level.ExamRooms
	local EW = E * ROOM_W

	local zF = Z_FRONT
	local zL1 = zF + LOBBY_D -- 46
	local zEF = zL1 + CORRIDOR_D -- 54
	local zEB = zEF + EXAM_D -- 72

	local backRooms = {}
	for _, room in Rooms.List do
		if room.Location == "Back" and room.RequiredLevel <= level.Level then
			table.insert(backRooms, room)
		end
	end
	local hasBack = #backRooms > 0
	local zC2 = zEB + CORRIDOR_D -- 80
	local zB = if hasBack then zC2 + BACK_D else zEB

	local structure = Build.Model(model, "Structure")
	local interior = Build.Model(model, "Interior")
	local roofGroup = Build.Model(model, "RoofGroup")
	local exterior = Build.Model(model, "Exterior")

	local layout: Layout = {
		Nodes = {},
		Looks = {},
		Seats = {},
		ExamRooms = {},
		RoomCenters = {},
		PlayerSpawn = CFrame.new(),
		LawnSpawn = CFrame.new(),
		BoundsCFrame = CFrame.new(),
		BoundsSize = Vector3.zero,
		Center = Vector3.zero,
	}

	-- Floor --------------------------------------------------------------
	box(ctx, structure, -hw, PLOT_TOP, zF, hw, FLOOR, zB, style.Floor, { Material = style.FloorMaterial, Name = "Floor" })
	-- Corridor runner
	box(ctx, interior, -hw + 1, FLOOR, zL1 + 1, hw - 1, FLOOR + 0.04, zEF - 1, style.Trim:Lerp(Color3.new(1, 1, 1), 0.65), { CanCollide = false })
	-- Welcome mat
	box(ctx, interior, -5, FLOOR, zF + 0.6, 5, FLOOR + 0.04, zF + 4, style.Accent, { CanCollide = false })

	-- Exterior walls -----------------------------------------------------
	local wallColor = style.Wall
	local wallMat = style.WallMaterial
	wallX(ctx, structure, zF, -hw - 0.5, hw + 0.5, PLOT_TOP, FLOOR + H, 1, wallColor, wallMat, { { Center = 0, Width = DOOR_W, Height = 10 } })
	wallX(ctx, structure, zB, -hw - 0.5, hw + 0.5, PLOT_TOP, FLOOR + H, 1, wallColor, wallMat)
	wallZ(ctx, structure, -hw, zF, zB, PLOT_TOP, FLOOR + H, 1, wallColor, wallMat)
	wallZ(ctx, structure, hw, zF, zB, PLOT_TOP, FLOOR + H, 1, wallColor, wallMat)

	-- Base trim stripe and top trim
	local trim = style.Trim
	box(ctx, exterior, -hw - 0.7, PLOT_TOP, zF - 0.7, -DOOR_W / 2, PLOT_TOP + 1.2, zF - 0.5, trim, { CanCollide = false })
	box(ctx, exterior, DOOR_W / 2, PLOT_TOP, zF - 0.7, hw + 0.7, PLOT_TOP + 1.2, zF - 0.5, trim, { CanCollide = false })
	box(ctx, roofGroup, -hw - 0.8, FLOOR + H - 1.2, zF - 0.8, hw + 0.8, FLOOR + H, zF - 0.5, trim, { CanCollide = false })

	-- Door frame + canopy
	box(ctx, exterior, -DOOR_W / 2 - 1, FLOOR + 10, zF - 4, DOOR_W / 2 + 1, FLOOR + 10.6, zF - 0.5, trim)
	for _, x in { -DOOR_W / 2 - 0.5, DOOR_W / 2 + 0.5 } do
		box(ctx, exterior, x - 0.35, PLOT_TOP, zF - 3.8, x + 0.35, FLOOR + 10, zF - 3.1, trim)
	end
	-- Open sliding glass doors (decor, pushed aside)
	for _, side in { -1, 1 } do
		box(ctx, exterior, side * (DOOR_W / 2 - 0.2), FLOOR, zF - 0.2, side * (DOOR_W / 2 + 2.8), FLOOR + 9.5, zF - 0.6, Color3.fromRGB(170, 220, 255), { Material = Enum.Material.Glass, Transparency = 0.5, CanCollide = false })
	end

	-- Windows
	if style.Windows then
		local function windowRow(fromX: number, toX: number)
			local x = fromX + 2
			while x + 4 <= toX - 1 do
				box(ctx, exterior, x, FLOOR + 3.5, zF - 0.62, x + 4, FLOOR + 8.5, zF - 0.52, Color3.fromRGB(150, 205, 255), { Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false })
				x += 6
			end
		end
		windowRow(-hw, -DOOR_W / 2 - 1)
		windowRow(DOOR_W / 2 + 1, hw)
		local z = zF + 4
		while z + 4 <= zB - 2 do
			for _, side in { -1, 1 } do
				local x = side * (hw + 0.57)
				box(ctx, exterior, x - 0.05, FLOOR + 3.5, z, x + 0.05, FLOOR + 8.5, z + 4, Color3.fromRGB(150, 205, 255), { Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false })
			end
			z += 7
		end
	end

	-- Roof ----------------------------------------------------------------
	box(ctx, roofGroup, -hw - 1, FLOOR + H, zF - 1, hw + 1, FLOOR + H + 1, zB + 1, style.Roof, { Name = "Roof" })
	box(ctx, roofGroup, -hw - 1.2, FLOOR + H + 1, zF - 1.2, hw + 1.2, FLOOR + H + 1.6, zF - 0.6, trim, { CanCollide = false })

	-- Big front sign with the owner's name
	local signWidth = math.min(W - 6, 46)
	local signPart = Build.Part(roofGroup, {
		Name = "HospitalSign",
		Size = Vector3.new(signWidth, 4.2, 0.6),
		CFrame = L(ctx, 0, FLOOR + H + 3.4, zF - 0.4),
		Color = Color3.fromRGB(255, 255, 255),
	})
	Build.SurfaceText(signPart, string.format('<font color="#E53935">✚</font> Dr. %s\'s %s', ownerName, level.Name), {
		TextColor = Color3.fromRGB(40, 60, 90),
		RichText = true,
	})
	-- Red cross emblem above the door
	box(ctx, exterior, -0.6, FLOOR + 10.9, zF - 0.75, 0.6, FLOOR + 13.1, zF - 0.55, style.Accent, { Material = Enum.Material.Neon, CanCollide = false })
	box(ctx, exterior, -1.7, FLOOR + 11.4, zF - 0.75, 1.7, FLOOR + 12.6, zF - 0.55, style.Accent, { Material = Enum.Material.Neon, CanCollide = false })

	-- Towers (decorative upper floors) for big hospitals
	if style.Towers > 0 then
		local towerXs = if style.Towers == 1 then { 0 } elseif style.Towers == 2 then { -hw / 2, hw / 2 } else { -hw / 2, 0, hw / 2 }
		for i, tx in towerXs do
			local th = 12 + (if i == math.ceil(#towerXs / 2) then 8 else 0)
			local tw = math.min(18, W / (#towerXs + 1))
			local base = FLOOR + H + 1
			box(ctx, roofGroup, tx - tw / 2, base, zF + 6, tx + tw / 2, base + th, zF + 20, wallColor, { Material = wallMat })
			local y = base + 2
			while y + 3 <= base + th - 1 do
				box(ctx, roofGroup, tx - tw / 2 + 1, y, zF + 5.9, tx + tw / 2 - 1, y + 2.4, zF + 5.8, Color3.fromRGB(150, 205, 255), { Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false })
				y += 4
			end
			box(ctx, roofGroup, tx - tw / 2 - 0.4, base + th, zF + 5.6, tx + tw / 2 + 0.4, base + th + 0.8, zF + 20.4, trim)
		end
	end
	if style.Helipad then
		local hz = (zF + zB) / 2 + 8
		Build.Cylinder(roofGroup, L(ctx, 0, FLOOR + H + 1, hz), 0.3, 18, { Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Asphalt })
		box(ctx, roofGroup, -3, FLOOR + H + 1.3, hz - 4, -1.8, FLOOR + H + 1.35, hz + 4, Color3.new(1, 1, 1), { CanCollide = false })
		box(ctx, roofGroup, 1.8, FLOOR + H + 1.3, hz - 4, 3, FLOOR + H + 1.35, hz + 4, Color3.new(1, 1, 1), { CanCollide = false })
		box(ctx, roofGroup, -1.8, FLOOR + H + 1.3, hz - 0.6, 1.8, FLOOR + H + 1.35, hz + 0.6, Color3.new(1, 1, 1), { CanCollide = false })
	end
	if style.Beacon then
		local by = FLOOR + H + 1 + 20 + 1
		local beacon = box(ctx, roofGroup, -0.8, by, zF + 12.2, 0.8, by + 7, zF + 13.8, style.Accent, { Material = Enum.Material.Neon, CanCollide = false })
		box(ctx, roofGroup, -2.8, by + 2.2, zF + 12.2, 2.8, by + 3.8, zF + 13.8, style.Accent, { Material = Enum.Material.Neon, CanCollide = false })
		local glow = Instance.new("PointLight")
		glow.Color = style.Accent
		glow.Range = 40
		glow.Brightness = 3
		glow.Parent = beacon
	end
	if style.Gold then
		local gold = Color3.fromRGB(255, 200, 50)
		local gy0, gy1 = FLOOR + H + 1, FLOOR + H + 1.8
		local goldOpts = { Material = Enum.Material.Foil, CanCollide = false }
		box(ctx, roofGroup, -hw - 1.3, gy0, zB, hw + 1.3, gy1, zB + 1.3, gold, goldOpts)
		box(ctx, roofGroup, -hw - 1.3, gy0, zF - 1.3, -hw, gy1, zB + 1.3, gold, goldOpts)
		box(ctx, roofGroup, hw, gy0, zF - 1.3, hw + 1.3, gy1, zB + 1.3, gold, goldOpts)
	end

	-- Lobby: reception ------------------------------------------------------
	local receptionX = -14
	furniture(ctx, interior, receptionX - 5, FLOOR, zF + 6.75, receptionX + 5, FLOOR + 3.2, zF + 9.25, trim)
	furniture(ctx, interior, receptionX - 5.3, FLOOR + 3.2, zF + 6.5, receptionX + 5.3, FLOOR + 3.5, zF + 9.5, Color3.fromRGB(250, 250, 250))
	furniture(ctx, interior, receptionX + 1, FLOOR + 3.5, zF + 8.3, receptionX + 3, FLOOR + 5, zF + 8.6, Color3.fromRGB(30, 30, 40))
	sign(ctx, interior, F(ctx, receptionX, FLOOR + 8, zF + 9, 0, -1), 8, 1.6, "📋 RECEPTION", style.Trim)
	staff(ctx, interior, "Nurse Nina", receptionX, zF + 11, 0, -1, Color3.fromRGB(255, 140, 180))
	layout.Nodes.Reception = P(ctx, receptionX + 1, FLOOR, zF + 4.6)
	layout.Looks.Reception = D(ctx, 0, 1)

	-- Waiting room ------------------------------------------------------------
	local seatRows = {}
	local rz = zF + 8
	while rz <= zL1 - 3 do
		table.insert(seatRows, rz)
		rz += 6
	end
	local seatCols = {}
	local sx = 6
	while sx <= hw - 3 do
		table.insert(seatCols, sx)
		sx += 3
	end
	local capacity = level.Capacity
	local rowsNeeded = math.min(#seatRows, math.ceil(capacity / math.max(#seatCols, 1)))
	local chairColor = style.Trim:Lerp(Color3.fromRGB(40, 40, 60), 0.25)
	for r = 1, rowsNeeded do
		local z = seatRows[r]
		-- bench frame under the whole row
		furniture(ctx, interior, seatCols[1] - 1, FLOOR, z - 0.7, seatCols[#seatCols] + 1, FLOOR + 1.15, z + 0.7, Color3.fromRGB(120, 120, 130), Enum.Material.Metal)
		for _, x in seatCols do
			furniture(ctx, interior, x - 1.1, FLOOR + 1.15, z - 0.8, x + 1.1, FLOOR + 1.55, z + 0.8, chairColor)
			furniture(ctx, interior, x - 1.1, FLOOR + 1.55, z + 0.55, x + 1.1, FLOOR + 3.7, z + 0.85, chairColor)
			if #layout.Seats < capacity then
				table.insert(layout.Seats, {
					Top = F(ctx, x, FLOOR + 1.55, z, 0, -1),
					Aisle = P(ctx, x, FLOOR, z - 2.7),
					Lane = P(ctx, 3, FLOOR, z - 2.7),
				})
			end
		end
	end
	-- TV on the front wall above the waiting room
	local tvX = math.max(hw / 2 + 2, 12)
	local tv = furniture(ctx, interior, tvX - 3.5, FLOOR + 6.5, zF + 0.5, tvX + 3.5, FLOOR + 10.5, zF + 0.8, Color3.fromRGB(20, 20, 25))
	Build.SurfaceText(tv, "📺 Dr. TV\nWash your hands! 🧼", { Face = Enum.NormalId.Back, TextColor = Color3.fromRGB(120, 230, 255), Background = Color3.fromRGB(10, 20, 40), BackgroundTransparency = 0 })
	plant(ctx, interior, hw - 2.2, zF + 2.2)
	plant(ctx, interior, -hw + 2.2, zF + 2.2)
	plant(ctx, interior, hw - 2.2, zL1 - 1)

	-- Pharmacy ------------------------------------------------------------------
	local pharmacyRoom = Rooms.ById.Pharmacy
	if level.Level >= pharmacyRoom.RequiredLevel then
		local px = -14
		local pz = zF + 22 -- counter z (38)
		layout.RoomCenters.Pharmacy = P(ctx, px, FLOOR + 3, pz)
		if data.Rooms.Pharmacy then
			furniture(ctx, interior, px - 5, FLOOR, pz - 1.25, px + 5, FLOOR + 3.2, pz + 1.25, pharmacyRoom.Color)
			furniture(ctx, interior, px - 5.3, FLOOR + 3.2, pz - 1.5, px + 5.3, FLOOR + 3.5, pz + 1.5, Color3.fromRGB(250, 250, 250))
			furniture(ctx, interior, px - 5, FLOOR, pz + 4.6, px + 5, FLOOR + 7, pz + 6, Color3.fromRGB(240, 240, 240))
			local medColors = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 160, 255), Color3.fromRGB(255, 210, 60), Color3.fromRGB(120, 220, 120) }
			for shelf = 0, 2 do
				for i = 0, 6 do
					local c = medColors[(i + shelf) % #medColors + 1]
					box(ctx, interior, px - 4.5 + i * 1.35, FLOOR + 1 + shelf * 2, pz + 4.3, px - 3.7 + i * 1.35, FLOOR + 2.2 + shelf * 2, pz + 4.6, c, { CanCollide = false })
				end
			end
			sign(ctx, interior, F(ctx, px, FLOOR + 8.5, pz + 1, 0, -1), 8, 1.6, "💊 PHARMACY", pharmacyRoom.Color)
			staff(ctx, interior, "Pharmacist Pat", px, pz + 3, 0, -1, Color3.fromRGB(240, 240, 240))
			layout.Nodes.Pharmacy = P(ctx, px, FLOOR, pz - 3.4)
			layout.Looks.Pharmacy = D(ctx, 0, 1)
		else
			box(ctx, interior, px - 5, FLOOR, pz - 1.5, px + 5, FLOOR + 0.05, pz + 6, Color3.fromRGB(90, 90, 100), { CanCollide = false })
			sign(ctx, interior, F(ctx, px, FLOOR + 3.5, pz, 0, -1), 9, 3, string.format("🔒 PHARMACY\n%s · Shop", Format.Money(pharmacyRoom.Cost)), Color3.fromRGB(70, 70, 80))
			furniture(ctx, interior, px - 0.2, FLOOR, pz + 0.05, px + 0.2, FLOOR + 2, pz + 0.35, Color3.fromRGB(70, 70, 80))
		end
	end

	-- Exam rooms --------------------------------------------------------------
	local ex0 = -EW / 2
	local examFloor = Color3.fromRGB(214, 244, 236)
	local partition = style.Wall:Lerp(Color3.fromRGB(200, 210, 220), 0.35)
	for i = 1, E do
		local x0 = ex0 + (i - 1) * ROOM_W
		local x1 = x0 + ROOM_W
		local cx = x0 + ROOM_W / 2
		local roomModel = Build.Model(interior, "ExamRoom" .. i)

		wallX(ctx, roomModel, zEF, x0, x1, FLOOR, FLOOR + INTERIOR_H, 0.6, partition, nil, { { Center = cx, Width = ROOM_DOOR_W, Height = 8 } })
		if i == 1 then
			wallZ(ctx, roomModel, x0, zEF, zEB, FLOOR, FLOOR + INTERIOR_H, 0.6, partition)
		end
		wallZ(ctx, roomModel, x1, zEF, zEB, FLOOR, FLOOR + INTERIOR_H, 0.6, partition)
		if hasBack then
			wallX(ctx, roomModel, zEB, x0, x1, FLOOR, FLOOR + INTERIOR_H, 0.6, partition)
		end
		box(ctx, roomModel, x0 + 0.4, FLOOR, zEF + 0.4, x1 - 0.4, FLOOR + 0.04, zEB - 0.4, examFloor, { CanCollide = false })

		-- Bed (head/pillow at the left)
		furniture(ctx, roomModel, cx - 5, FLOOR, zEB - 4.8, cx + 2, FLOOR + 1.9, zEB - 1.3, Color3.fromRGB(225, 228, 235), Enum.Material.Metal)
		furniture(ctx, roomModel, cx - 4.8, FLOOR + 1.9, zEB - 4.6, cx + 1.8, FLOOR + 2.4, zEB - 1.5, Color3.fromRGB(170, 215, 255))
		furniture(ctx, roomModel, cx - 4.7, FLOOR + 2.4, zEB - 4.3, cx - 3.3, FLOOR + 2.8, zEB - 1.8, Color3.new(1, 1, 1))
		-- Doctor's desk + monitor
		furniture(ctx, roomModel, cx + 3.8, FLOOR, zEF + 6, cx + 5.6, FLOOR + 2.6, zEF + 10, Color3.fromRGB(180, 140, 100), Enum.Material.Wood)
		local monitor = furniture(ctx, roomModel, cx + 4.6, FLOOR + 2.6, zEF + 7.2, cx + 4.9, FLOOR + 4.2, zEF + 8.8, Color3.fromRGB(30, 30, 40))
		Build.SurfaceText(monitor, "🩺", { Face = Enum.NormalId.Left, Background = Color3.fromRGB(30, 80, 120), BackgroundTransparency = 0 })
		-- Cabinet
		furniture(ctx, roomModel, x0 + 0.6, FLOOR, zEF + 0.8, x0 + 2.2, FLOOR + 4, zEF + 3.6, Color3.fromRGB(245, 245, 250))
		-- Door sign (faces the corridor)
		sign(ctx, roomModel, F(ctx, cx, FLOOR + 9, zEF - 0.45, 0, -1), 5, 1.3, "EXAM " .. i, style.Trim)

		local exam: ExamRoom = {
			Index = i,
			Front = P(ctx, cx, FLOOR, zL1 + 4),
			Entry = P(ctx, cx, FLOOR, zEF + 2.5),
			BedSide = P(ctx, cx - 3.5, FLOOR, zEB - 6.6),
			BedTop = F(ctx, cx - 1.5, FLOOR + 2.4, zEB - 3, -1, 0),
			DoctorIdle = P(ctx, cx + 2.4, FLOOR, zEF + 8),
			DoctorIdleLook = D(ctx, 1, 0),
			DoctorWork = P(ctx, cx - 1.2, FLOOR, zEB - 6.3),
			DoctorWorkLook = D(ctx, 0, 1),
			Center = P(ctx, cx, FLOOR + 3, (zEF + zEB) / 2),
		}
		layout.ExamRooms[i] = exam
	end

	-- Back wing: special rooms -------------------------------------------------
	if hasBack then
		local BW = #backRooms * BACK_ROOM_W
		local bx0 = -BW / 2
		for j, room in backRooms do
			local x0 = bx0 + (j - 1) * BACK_ROOM_W
			local x1 = x0 + BACK_ROOM_W
			local cx = x0 + BACK_ROOM_W / 2
			local roomModel = Build.Model(interior, room.Id)
			wallX(ctx, roomModel, zC2, x0, x1, FLOOR, FLOOR + INTERIOR_H, 0.6, partition, nil, { { Center = cx, Width = ROOM_DOOR_W, Height = 8 } })
			if j == 1 then
				wallZ(ctx, roomModel, x0, zC2, zB, FLOOR, FLOOR + INTERIOR_H, 0.6, partition)
			end
			wallZ(ctx, roomModel, x1, zC2, zB, FLOOR, FLOOR + INTERIOR_H, 0.6, partition)
			layout.RoomCenters[room.Id] = P(ctx, cx, FLOOR + 3, (zC2 + zB) / 2)

			if data.Rooms[room.Id] then
				box(ctx, roomModel, x0 + 0.4, FLOOR, zC2 + 0.4, x1 - 0.4, FLOOR + 0.04, zB - 0.4, room.Color:Lerp(Color3.new(1, 1, 1), 0.7), { CanCollide = false })
				local furnish = FURNISH[room.Id]
				if furnish then
					furnish(ctx, roomModel, x0, zC2, x1, zB, room.Color)
				end
				sign(ctx, roomModel, F(ctx, cx, FLOOR + 9, zC2 - 0.45, 0, -1), 10, 1.4, room.Emoji .. " " .. string.upper(room.Name), room.Color)
			else
				box(ctx, roomModel, x0 + 0.4, FLOOR, zC2 + 0.4, x1 - 0.4, FLOOR + 0.04, zB - 0.4, Color3.fromRGB(110, 110, 120), { CanCollide = false })
				sign(ctx, roomModel, F(ctx, cx, FLOOR + 4, (zC2 + zB) / 2, 0, -1), 12, 4, string.format("🔒 %s %s\nUnlock in Shop · %s", room.Emoji, room.Name, Format.Money(room.Cost)), Color3.fromRGB(60, 60, 70))
				for _, cone in { { x0 + 3, zC2 + 3 }, { x1 - 3, zC2 + 3 }, { x0 + 3, zB - 3 }, { x1 - 3, zB - 3 } } do
					Build.Cylinder(roomModel, L(ctx, cone[1], FLOOR, cone[2]), 1.6, 0.9, { Color = Color3.fromRGB(255, 140, 30), Group = Collision.Furniture })
				end
			end
		end
	end

	-- Outside: path, lawn, bus stop -------------------------------------------
	box(ctx, exterior, -5, PLOT_TOP, 0, 5, PLOT_TOP + 0.08, zF - 0.5, Color3.fromRGB(200, 200, 195), { Material = Enum.Material.Concrete, CanCollide = false })
	box(ctx, exterior, -hw, PLOT_TOP, 2, hw, PLOT_TOP + 0.06, 6, Color3.fromRGB(200, 200, 195), { Material = Enum.Material.Concrete, CanCollide = false })
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			Build.Ball(exterior, L(ctx, side * (8 + k * 3), PLOT_TOP + 1, zF - 2), 2.6, { Color = Color3.fromRGB(70, 160, 70), Material = Enum.Material.Grass, CanCollide = false })
		end
	end
	local plotHalf = 70
	-- Bus stop where patients arrive
	local busX = -plotHalf + 8
	furniture(ctx, exterior, busX - 3, PLOT_TOP, 7.5, busX + 3, PLOT_TOP + 1.4, 8.5, Color3.fromRGB(90, 140, 220))
	box(ctx, exterior, busX - 3.5, PLOT_TOP + 6, 6.5, busX + 3.5, PLOT_TOP + 6.4, 9.5, Color3.fromRGB(90, 140, 220), { CanCollide = false })
	for _, px in { busX - 3.2, busX + 3.2 } do
		box(ctx, exterior, px - 0.15, PLOT_TOP, 8.7, px + 0.15, PLOT_TOP + 6, 9, Color3.fromRGB(80, 80, 90), { CanCollide = false })
	end
	sign(ctx, exterior, F(ctx, busX, PLOT_TOP + 7.4, 8, 0, -1), 6, 1.4, "🚏 PATIENTS", Color3.fromRGB(90, 140, 220))

	if style.Parking then
		tree(ctx, exterior, -plotHalf + 6, zB + 6, 0.9)
		tree(ctx, exterior, plotHalf - 6, zB + 6, 0.9)
		box(ctx, exterior, -24, PLOT_TOP, zB + 4, 24, PLOT_TOP + 0.06, zB + 26, Color3.fromRGB(70, 70, 75), { Material = Enum.Material.Asphalt, CanCollide = false })
		for k = 0, 4 do
			local lx = -20 + k * 10
			box(ctx, exterior, lx - 0.2, PLOT_TOP + 0.06, zB + 6, lx + 0.2, PLOT_TOP + 0.09, zB + 16, Color3.new(1, 1, 1), { CanCollide = false })
		end
		ambulance(ctx, exterior, -15, zB + 12, 0, 1)
		if level.Level >= 5 then
			ambulance(ctx, exterior, 5, zB + 12, 0, 1)
		end
	else
		tree(ctx, exterior, -plotHalf + 8, 40, 1)
		tree(ctx, exterior, plotHalf - 8, 40, 1)
	end
	tree(ctx, exterior, plotHalf - 6, 20, 0.8)

	-- Navigation nodes ------------------------------------------------------------
	layout.Nodes.Spawn = P(ctx, busX, PLOT_TOP, 4)
	layout.Nodes.Outside = P(ctx, 0, PLOT_TOP, 6)
	layout.Nodes.Door = P(ctx, 0, FLOOR, zF)
	layout.Nodes.Inside = P(ctx, 0, FLOOR, zF + 4)
	layout.Nodes.AfterReception = P(ctx, 1, FLOOR, zF + 5)
	layout.Nodes.LobbyBack = P(ctx, 2, FLOOR, zL1 - 1.5)
	layout.Nodes.ExitTop = P(ctx, -5, FLOOR, zL1 + 1)
	layout.Nodes.ExitMid = P(ctx, -5, FLOOR, zF + 18)
	layout.Nodes.ExitBottom = P(ctx, -4, FLOOR, zF + 3)
	layout.Nodes.ExitOutside = P(ctx, 4, PLOT_TOP, 4)
	layout.Nodes.Despawn = P(ctx, plotHalf - 6, PLOT_TOP, 3)

	layout.PlayerSpawn = L(ctx, 0, FLOOR + 3.5, zF + 9) * CFrame.Angles(0, math.pi, 0)
	layout.LawnSpawn = L(ctx, 14, PLOT_TOP + 3.5, 8)
	layout.BoundsCFrame = L(ctx, 0, (PLOT_TOP + FLOOR + H) / 2, (zF + zB) / 2)
	layout.BoundsSize = Vector3.new(W + 2, FLOOR + H - PLOT_TOP + 2, zB - zF + 2)
	layout.Center = P(ctx, 0, FLOOR + 3, (zF + zB) / 2)

	-- Invisible bounds used by clients to hide the roof while inside.
	local bounds = Build.Part(model, {
		Name = "Bounds",
		Size = layout.BoundsSize,
		CFrame = layout.BoundsCFrame,
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	bounds.CanQuery = false

	for _, descendant in roofGroup:GetDescendants() do
		if descendant:IsA("BasePart") then
			CollectionService:AddTag(descendant, "HospitalRoof")
		end
	end

	model:SetAttribute("Level", level.Level)
	model.PrimaryPart = bounds
	model.Parent = plotFolder
	return layout
end

return HospitalBuilder
