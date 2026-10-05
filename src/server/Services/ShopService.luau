--[[
	ShopService
	Every purchase goes through here. The client only says *what* it wants;
	the server checks requirements, price and money, then applies it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local AutoDoctors = require(Config:WaitForChild("AutoDoctors"))
local HospitalLevels = require(Config:WaitForChild("HospitalLevels"))
local Improvements = require(Config:WaitForChild("Improvements"))
local Rooms = require(Config:WaitForChild("Rooms"))
local Economy = require(Shared:WaitForChild("Economy"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))

local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local ShopService = {}

local services: any = nil
local limiter = RateLimiter.new(4, 8)

type Result = { Ok: boolean, Message: string }

local function fail(message: string): Result
	return { Ok = false, Message = message }
end

local function notEnough(data: any, cost: number): Result
	return fail(string.format("You need %s more 💵", Format.Money(cost - data.Money)))
end

local function buyHospitalLevel(player: Player, data: any): Result
	local nextLevel = HospitalLevels.GetNext(data.HospitalLevel)
	if not nextLevel then
		return fail("Your hospital is already max level! 🏆")
	end
	if not services.EconomyService.TrySpend(player, nextLevel.Cost) then
		return notEnough(data, nextLevel.Cost)
	end
	data.HospitalLevel = nextLevel.Level
	services.HospitalService.Rebuild(player)
	local sim = services.HospitalService.Get(player)
	services.EconomyService.Effect(player, {
		Type = "HospitalUpgraded",
		Level = nextLevel.Level,
		Name = nextLevel.Name,
		Position = sim and sim.Layout.Center or nil,
	})
	services.EconomyService.Notify(player, {
		Style = "Big",
		Title = "🏥 HOSPITAL UPGRADED!",
		Text = string.format("Welcome to your %s! %d exam rooms, %d patients at once.", nextLevel.Name, nextLevel.ExamRooms, nextLevel.Capacity),
		Color = nextLevel.Style.Accent,
	})
	return { Ok = true, Message = "Upgraded to " .. nextLevel.Name .. "!" }
end

local function buyRoom(player: Player, data: any, roomId: any): Result
	if typeof(roomId) ~= "string" then
		return fail("Unknown room")
	end
	local room = Rooms.ById[roomId]
	if not room then
		return fail("Unknown room")
	end
	if data.Rooms[roomId] then
		return fail("You already own the " .. room.Name)
	end
	if data.HospitalLevel < room.RequiredLevel then
		return fail(string.format("Requires Hospital Level %d", room.RequiredLevel))
	end
	if not services.EconomyService.TrySpend(player, room.Cost) then
		return notEnough(data, room.Cost)
	end
	data.Rooms[roomId] = true
	services.HospitalService.Rebuild(player)
	local sim = services.HospitalService.Get(player)
	services.EconomyService.Effect(player, {
		Type = "RoomUnlocked",
		Room = roomId,
		Position = sim and sim.Layout.RoomCenters[roomId] or nil,
	})
	services.EconomyService.Notify(player, {
		Style = "Big",
		Title = room.Emoji .. " " .. string.upper(room.Name) .. " UNLOCKED!",
		Text = room.Benefit,
		Color = room.Color,
	})
	return { Ok = true, Message = room.Name .. " unlocked!" }
end

local function hireDoctor(player: Player, data: any): Result
	local level = HospitalLevels.Get(data.HospitalLevel)
	local owned = #data.Doctors
	if owned >= level.ExamRooms then
		return fail("Every exam room has a doctor. Upgrade your hospital for more rooms!")
	end
	local cost = Economy.HireCost(owned)
	if not services.EconomyService.TrySpend(player, cost) then
		return notEnough(data, cost)
	end
	table.insert(data.Doctors, 1)
	local sim = services.HospitalService.Get(player)
	if sim then
		sim:SyncDoctors()
	end
	local room = sim and sim.Layout.ExamRooms[#data.Doctors]
	services.EconomyService.Effect(player, {
		Type = "DoctorHired",
		Room = #data.Doctors,
		Position = room and room.Center or nil,
	})
	services.EconomyService.Notify(player, {
		Style = "Success",
		Text = string.format("🤖 %s hired for Exam Room %d!", AutoDoctors.Tiers[1].Name, #data.Doctors),
	})
	return { Ok = true, Message = "Doctor hired!" }
end

local function upgradeDoctor(player: Player, data: any, slot: any): Result
	if typeof(slot) ~= "number" or slot ~= math.floor(slot) then
		return fail("Unknown doctor")
	end
	local tier = data.Doctors[slot]
	if not tier then
		return fail("Unknown doctor")
	end
	local nextTier = AutoDoctors.Tiers[tier + 1]
	if not nextTier then
		return fail("This doctor is already max level!")
	end
	if data.HospitalLevel < nextTier.RequiredLevel then
		return fail(string.format("Requires Hospital Level %d", nextTier.RequiredLevel))
	end
	if not services.EconomyService.TrySpend(player, nextTier.UpgradeCost) then
		return notEnough(data, nextTier.UpgradeCost)
	end
	data.Doctors[slot] = tier + 1
	local sim = services.HospitalService.Get(player)
	if sim then
		sim:SyncDoctors()
	end
	local room = sim and sim.Layout.ExamRooms[slot]
	services.EconomyService.Effect(player, {
		Type = "DoctorHired",
		Room = slot,
		Position = room and room.Center or nil,
	})
	services.EconomyService.Notify(player, {
		Style = "Success",
		Text = string.format("⬆️ Room %d doctor is now %s (%ss per patient)!", slot, nextTier.Name, tostring(nextTier.TreatTime)),
	})
	return { Ok = true, Message = "Doctor upgraded!" }
end

local function buyImprovement(player: Player, data: any, id: any): Result
	if typeof(id) ~= "string" or not Improvements.ById[id] then
		return fail("Unknown upgrade")
	end
	local item = Improvements.ById[id]
	local current = Economy.ImprovementLevel(data, id)
	local cost = Economy.ImprovementCost(id, current)
	if not cost then
		return fail(item.Name .. " is maxed out!")
	end
	if not services.EconomyService.TrySpend(player, cost) then
		return notEnough(data, cost)
	end
	data.Improvements[id] = current + 1
	services.EconomyService.Effect(player, { Type = "Improvement", Id = id })
	services.EconomyService.Notify(player, {
		Style = "Success",
		Text = string.format("%s %s is now level %d!", item.Emoji, item.Name, current + 1),
	})
	return { Ok = true, Message = item.Name .. " upgraded!" }
end

local function purchase(player: Player, kind: any, arg: any): Result
	if not limiter:Check(player) then
		return fail("Slow down!")
	end
	if typeof(kind) ~= "string" then
		return fail("Bad request")
	end
	local data = services.DataService.Get(player)
	if not data then
		return fail("Your data is still loading...")
	end
	local result
	if kind == "HospitalLevel" then
		result = buyHospitalLevel(player, data)
	elseif kind == "Room" then
		result = buyRoom(player, data, arg)
	elseif kind == "HireDoctor" then
		result = hireDoctor(player, data)
	elseif kind == "UpgradeDoctor" then
		result = upgradeDoctor(player, data, arg)
	elseif kind == "Improvement" then
		result = buyImprovement(player, data, arg)
	else
		result = fail("Unknown purchase")
	end
	services.EconomyService.MarkDirty(player)
	return result
end

function ShopService.Init(allServices: any)
	services = allServices
	Remotes.Function("Purchase").OnServerInvoke = purchase
end

return ShopService
