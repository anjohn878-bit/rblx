--[[
	HospitalSim
	The live simulation of one player's hospital:
	  * spawns patients (rate, capacity, rarity, illness)
	  * walks them reception -> waiting room -> exam room -> exit
	  * hands patients to Auto Doctors or waits for the player
	  * pays the owner when a patient is treated (server-authoritative)
	  * rebuilds the building after upgrades without losing patients
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local AutoDoctors = require(Config:WaitForChild("AutoDoctors"))
local DoctorLevels = require(Config:WaitForChild("DoctorLevels"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local HospitalLevels = require(Config:WaitForChild("HospitalLevels"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Economy = require(Shared:WaitForChild("Economy"))

local Illnesses = require(script.Parent.Parent.Data.Illnesses)
local PatientNames = require(script.Parent.Parent.Data.PatientNames)
local HospitalBuilder = require(script.Parent.Parent.Services.HospitalBuilder)
local Patient = require(script.Parent.Patient)
local AutoDoctor = require(script.Parent.AutoDoctor)

local SKINS = {
	Color3.fromRGB(255, 224, 196),
	Color3.fromRGB(241, 194, 158),
	Color3.fromRGB(224, 172, 128),
	Color3.fromRGB(198, 140, 100),
	Color3.fromRGB(160, 110, 75),
	Color3.fromRGB(120, 80, 55),
	Color3.fromRGB(90, 60, 42),
}
local SHIRTS = {
	Color3.fromRGB(230, 80, 80),
	Color3.fromRGB(80, 150, 230),
	Color3.fromRGB(90, 200, 120),
	Color3.fromRGB(250, 200, 70),
	Color3.fromRGB(170, 110, 220),
	Color3.fromRGB(255, 150, 70),
	Color3.fromRGB(70, 200, 200),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(60, 60, 70),
	Color3.fromRGB(255, 130, 180),
}
local PANTS = {
	Color3.fromRGB(50, 70, 120),
	Color3.fromRGB(40, 40, 50),
	Color3.fromRGB(110, 80, 60),
	Color3.fromRGB(90, 100, 110),
	Color3.fromRGB(60, 110, 70),
	Color3.fromRGB(150, 140, 120),
}
local HAIR = {
	Color3.fromRGB(40, 30, 25),
	Color3.fromRGB(90, 60, 35),
	Color3.fromRGB(180, 130, 70),
	Color3.fromRGB(230, 200, 120),
	Color3.fromRGB(170, 60, 40),
	Color3.fromRGB(30, 30, 30),
	Color3.fromRGB(200, 200, 205),
}
local HAIR_STYLES = { "Short", "Short", "Long", "Spiky", "Bun", "Cap", "Bald" }

local HospitalSim = {}
HospitalSim.__index = HospitalSim

export type Plot = {
	Index: number,
	CFrame: CFrame,
	Folder: Folder,
	Patients: Folder,
	Doctors: Folder,
}

function HospitalSim.new(services: any, plot: Plot, player: Player, data: any)
	local self = setmetatable({}, HospitalSim)
	self.Services = services
	self.Plot = plot
	self.Player = player
	self.Data = data
	self.Rng = Random.new()
	self.Patients = {} :: { [number]: any }
	self.ActiveCount = 0
	self.SeatOwner = {} :: { [number]: any }
	self.Rooms = {} :: { [number]: { Index: number, Patient: any, Doctor: any } }
	self.SpawnTimer = 0
	self.DispatchTimer = 0
	self.CheckTimer = 0
	self.NextId = 0
	self.TotalSpawned = 0
	self.Layout = nil :: HospitalBuilder.Layout?
	self.Destroyed = false
	self:Rebuild(true)
	return self
end

-- Building ---------------------------------------------------------------------

function HospitalSim:Rebuild(initial: boolean?)
	local data = self.Data
	self.Layout = HospitalBuilder.Build(self.Plot.Folder, self.Plot.CFrame, data, self.Player.DisplayName)
	local level = HospitalLevels.Get(data.HospitalLevel)
	for i = 1, level.ExamRooms do
		self.Rooms[i] = self.Rooms[i] or { Index = i, Patient = nil, Doctor = nil }
	end

	-- Put every patient back somewhere valid in the new building.
	for _, patient in self.Patients do
		self:_relocate(patient)
	end
	self:SyncDoctors()

	if not initial then
		self:_moveCharactersOutOfWalls()
	end
end

function HospitalSim:_relocate(patient: any)
	local layout = self.Layout
	local state = patient.State
	if state == "Leaving" then
		self:Despawn(patient)
	elseif state == "ToExam" or state == "InExam" then
		local room = layout.ExamRooms[patient.RoomIndex]
		if not room then
			self:Despawn(patient)
			return
		end
		if state == "ToExam" then
			self:_arrivedInRoom(patient)
		else
			patient.Agent:LieAt(room.BedTop)
		end
	else
		local seat = patient.SeatIndex and layout.Seats[patient.SeatIndex]
		if seat then
			patient.Agent:SitAt(seat.Top)
			if patient.State ~= "Waiting" and patient.WaitingSince ~= -1 then
				patient.WaitingSince = os.clock()
			end
			patient:SetState("Waiting")
		else
			self:Despawn(patient)
		end
	end
end

local function insideBounds(cf: CFrame, size: Vector3, point: Vector3): boolean
	local localPoint = cf:PointToObjectSpace(point)
	return math.abs(localPoint.X) <= size.X / 2 + 2 and math.abs(localPoint.Y) <= size.Y / 2 + 4 and math.abs(localPoint.Z) <= size.Z / 2 + 2
end

function HospitalSim:_moveCharactersOutOfWalls()
	local layout = self.Layout
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and root and insideBounds(layout.BoundsCFrame, layout.BoundsSize, root.Position) then
			if player == self.Player then
				character:PivotTo(layout.PlayerSpawn)
			else
				character:PivotTo(layout.LawnSpawn)
			end
		end
	end
end

function HospitalSim:TeleportOwnerHome()
	local character = self.Player.Character
	if character and self.Layout then
		character:PivotTo(self.Layout.PlayerSpawn)
	end
end

function HospitalSim:GetTreatTime(tier: number): number
	return Economy.TreatTime(tier, self.Data)
end

-- Doctors --------------------------------------------------------------------------

function HospitalSim:SyncDoctors()
	local level = HospitalLevels.Get(self.Data.HospitalLevel)
	for index, room in self.Rooms do
		local tier = self.Data.Doctors[index]
		if tier and index <= level.ExamRooms then
			if room.Doctor then
				room.Doctor:SetTier(tier)
				room.Doctor:Place()
			else
				room.Doctor = AutoDoctor.new(self, index, math.clamp(tier, 1, AutoDoctors.MaxTier))
			end
			local patient = room.Patient
			if patient and patient.State == "InExam" and room.Doctor.Patient ~= patient then
				room.Doctor:Start(patient)
			end
		elseif room.Doctor then
			room.Doctor:Destroy()
			room.Doctor = nil
		end
	end
end

-- Patient generation -----------------------------------------------------------------

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

function HospitalSim:_rollRarity(): Rarities.Rarity
	local boost = if self.Data.Rooms.Specialist then 1.5 else 1
	local total = 0
	for _, rarity in Rarities.List do
		total += rarity.Weight * (if rarity.Stars >= 2 then boost else 1)
	end
	local roll = self.Rng:NextNumber() * total
	for _, rarity in Rarities.List do
		roll -= rarity.Weight * (if rarity.Stars >= 2 then boost else 1)
		if roll <= 0 then
			return rarity
		end
	end
	return Rarities.List[1]
end

function HospitalSim:_rollKind(): string
	local rooms = self.Data.Rooms
	local rng = self.Rng
	if rooms.VIP and rng:NextNumber() < GameConfig.VIPChance then
		return "VIP"
	end
	if rooms.EmergencyRoom and rng:NextNumber() < GameConfig.EmergencyChance then
		return "Emergency"
	end
	if rooms.ChildrensWard and rng:NextNumber() < GameConfig.ChildChance then
		return "Child"
	end
	return "Normal"
end

function HospitalSim:_makeSpec(tutorial: boolean): Patient.Spec
	local rng = self.Rng
	self.NextId += 1
	local rarity, kind, illness
	if tutorial then
		rarity = Rarities.ById.Common
		kind = "Normal"
		illness = Illnesses.ById.Cold
	else
		rarity = self:_rollRarity()
		kind = self:_rollKind()
		if rarity.RareIllnessChance > 0 and rng:NextNumber() < rarity.RareIllnessChance then
			illness = pick(rng, Illnesses.ByCategory.Rare)
		elseif kind == "Emergency" then
			illness = pick(rng, Illnesses.ByCategory.Emergency)
		else
			illness = pick(rng, Illnesses.GetRegularPool(self.Data.Rooms))
		end
	end

	local kindMultiplier = 1
	if kind == "Emergency" then
		kindMultiplier = GameConfig.EmergencyMultiplier
	elseif kind == "Child" then
		kindMultiplier = GameConfig.ChildMultiplier
	elseif kind == "VIP" then
		kindMultiplier = GameConfig.VIPMultiplier
	end

	local appearance = {
		Skin = pick(rng, SKINS),
		Shirt = pick(rng, SHIRTS),
		Pants = pick(rng, PANTS),
		Hair = pick(rng, HAIR),
		HairStyle = pick(rng, HAIR_STYLES),
		HatColor = pick(rng, SHIRTS),
		Sleeves = rng:NextNumber() < 0.5,
		Scale = if kind == "Child" then 0.72 else 1,
	}
	if kind == "VIP" then
		appearance.Shirt = Color3.fromRGB(255, 205, 60)
		appearance.Pants = Color3.fromRGB(30, 30, 35)
		appearance.HairStyle = "TopHat"
		appearance.Sleeves = true
	elseif rarity.Id == "Legendary" then
		appearance.Shirt = Color3.fromRGB(255, 215, 90)
		appearance.Sleeves = true
	end

	local name = if kind == "VIP" then PatientNames.RandomVIP(rng) else PatientNames.Random(rng)
	if tutorial then
		name = "Alex P."
	end

	return {
		Id = self.NextId,
		Name = name,
		Rarity = rarity,
		Kind = kind,
		Illness = illness,
		BaseReward = illness.Reward * kindMultiplier,
		Appearance = appearance,
	}
end

function HospitalSim:_inTutorial(): boolean
	return not self.Data.TutorialDone and self.Data.PatientsTreated == 0
end

function HospitalSim:_freeSeat(): number?
	for index = 1, #self.Layout.Seats do
		if not self.SeatOwner[index] then
			return index
		end
	end
	return nil
end

function HospitalSim:SpawnPatient(): boolean
	local seat = self:_freeSeat()
	if not seat then
		return false
	end
	local tutorial = self:_inTutorial()
	local spec = self:_makeSpec(tutorial)
	local patient = Patient.new(spec, self.Player.UserId)
	patient.SeatIndex = seat
	self.SeatOwner[seat] = patient
	self.Patients[patient.Id] = patient
	self.ActiveCount += 1
	self.TotalSpawned += 1

	local nodes = self.Layout.Nodes
	if spec.Kind == "Emergency" then
		patient.Agent.Humanoid.WalkSpeed = GameConfig.EmergencyWalkSpeed
	else
		patient.Agent.Humanoid.WalkSpeed = GameConfig.PatientWalkSpeed
	end

	if tutorial then
		-- First ever patient: start inside so the player can treat them within seconds.
		patient:Spawn(self.Plot.Patients, nodes.Inside, nodes.LobbyBack - nodes.Inside)
		patient:SetState("ToSeat", "Arriving")
		self:_walkToSeat(patient, {})
		return true
	end

	patient:Spawn(self.Plot.Patients, nodes.Spawn, nodes.Outside - nodes.Spawn)
	patient:SetState("Arriving")

	if spec.Rarity.Announce then
		self.Services.EconomyService.Notify(self.Player, {
			Style = "Rare",
			Title = string.format("⭐ %s PATIENT! ⭐", string.upper(spec.Rarity.Name)),
			Text = string.format("%s just arrived. Diagnose them yourself for a huge bonus!", spec.Name),
			Color = spec.Rarity.Color,
		})
	elseif spec.Kind == "VIP" then
		self.Services.EconomyService.Notify(self.Player, {
			Style = "Rare",
			Title = "👑 VIP PATIENT! 👑",
			Text = spec.Name .. " is visiting your hospital!",
			Color = Color3.fromRGB(255, 205, 60),
		})
	elseif spec.Kind == "Emergency" then
		self.Services.EconomyService.Notify(self.Player, {
			Style = "Info",
			Text = "🚨 Emergency! " .. spec.Name .. " is rushing in (2x pay).",
		})
	end

	local route = { nodes.Outside, nodes.Door, nodes.Inside }
	if spec.Kind == "Emergency" then
		patient.WaitingSince = -1 -- skips reception and jumps the queue
		patient.Agent:Walk(route, function()
			patient:SetState("ToSeat", "Arriving")
			self:_walkToSeat(patient, {})
		end)
	else
		table.insert(route, nodes.Reception)
		patient.Agent:Walk(route, function()
			patient:SetState("CheckingIn")
			patient.Agent:Face(self.Layout.Looks.Reception)
			task.delay(GameConfig.CheckInTime, function()
				if patient:IsAlive() and patient.State == "CheckingIn" then
					self:_walkToSeat(patient, { self.Layout.Nodes.AfterReception })
				end
			end)
		end)
	end
	return true
end

function HospitalSim:_walkToSeat(patient: any, prefix: { Vector3 })
	local seat = self.Layout.Seats[patient.SeatIndex]
	if not seat then
		self:Despawn(patient)
		return
	end
	if patient.State ~= "Arriving" then
		patient:SetState("ToSeat", "Arriving")
	end
	local route = table.clone(prefix)
	table.insert(route, seat.Lane)
	table.insert(route, seat.Aisle)
	patient.Agent:Walk(route, function()
		local currentSeat = self.Layout.Seats[patient.SeatIndex]
		if currentSeat then
			patient.Agent:SitAt(currentSeat.Top)
		end
		if patient.WaitingSince ~= -1 then
			patient.WaitingSince = os.clock()
		end
		patient:SetState("Waiting")
	end)
end

-- Dispatch ---------------------------------------------------------------------------

function HospitalSim:_dispatch()
	local level = HospitalLevels.Get(self.Data.HospitalLevel)
	local freeRooms = {}
	for index = 1, level.ExamRooms do
		local room = self.Rooms[index]
		if room and not room.Patient then
			table.insert(freeRooms, room)
		end
	end
	if #freeRooms == 0 then
		return
	end
	-- Staffed rooms first so automation keeps flowing.
	table.sort(freeRooms, function(a, b)
		local aStaffed = a.Doctor ~= nil
		local bStaffed = b.Doctor ~= nil
		if aStaffed ~= bStaffed then
			return aStaffed
		end
		return a.Index < b.Index
	end)

	-- Seated patients first (oldest first), then patients still walking to a
	-- seat, so nobody sits down only to stand straight back up.
	local waiting = {}
	for _, patient in self.Patients do
		if patient.State == "Waiting" or patient.State == "ToSeat" then
			table.insert(waiting, patient)
		end
	end
	if #waiting == 0 then
		return
	end
	local function sortKey(patient: any): number
		if patient.WaitingSince == -1 then
			return -1
		elseif patient.State == "Waiting" then
			return patient.WaitingSince
		end
		return 1e9 + patient.StateSince
	end
	table.sort(waiting, function(a, b)
		return sortKey(a) < sortKey(b)
	end)

	for k = 1, math.min(#freeRooms, #waiting) do
		self:_sendToRoom(waiting[k], freeRooms[k])
	end
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function HospitalSim:_sendToRoom(patient: any, room: any)
	local nodes = self.Layout.Nodes
	local wasSeated = patient.State == "Waiting"
	room.Patient = patient
	patient.RoomIndex = room.Index
	local seat = patient.SeatIndex and self.Layout.Seats[patient.SeatIndex]
	if patient.SeatIndex then
		self.SeatOwner[patient.SeatIndex] = nil
		patient.SeatIndex = nil
	end
	patient:SetState("ToExam")
	local exam = self.Layout.ExamRooms[room.Index]
	local route = {}
	if wasSeated and seat then
		table.insert(route, seat.Aisle)
		table.insert(route, seat.Lane)
		patient.Agent:StandAt(seat.Aisle, seat.Aisle - seat.Top.Position)
	else
		-- Was walking from reception to a seat.
		if flatDistance(patient:GetPosition(), nodes.Reception) < 5 then
			table.insert(route, nodes.AfterReception)
		end
		if seat then
			table.insert(route, seat.Lane)
		end
	end
	table.insert(route, nodes.LobbyBack)
	table.insert(route, exam.Front)
	table.insert(route, exam.Entry)
	table.insert(route, exam.BedSide)
	patient.Agent:Walk(route, function()
		self:_arrivedInRoom(patient)
	end)
end

function HospitalSim:_arrivedInRoom(patient: any)
	local room = self.Rooms[patient.RoomIndex]
	local exam = self.Layout.ExamRooms[patient.RoomIndex]
	if not room or not exam then
		self:Despawn(patient)
		return
	end
	patient.Agent:LieAt(exam.BedTop)
	patient:SetState("InExam", "NeedsDoctor")

	if not patient.Prompt then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DiagnosePrompt"
		prompt.ActionText = "Diagnose"
		prompt.ObjectText = patient.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OwnerUserId", self.Player.UserId)
		prompt.Parent = patient.Agent.Root
		prompt.Triggered:Connect(function(player: Player)
			self.Services.DiagnosisService.Begin(player, self, patient)
		end)
		patient.Prompt = prompt
	end

	if room.Doctor then
		room.Doctor:Start(patient)
	end
end

-- Treatment & payment ------------------------------------------------------------------

export type ManualInfo = {
	Misses: number,
	UsedHandbook: boolean,
	Combo: number,
	DoctorLevel: number,
	DifficultyBonus: number,
}

-- Server-side reward maths. `manual` is nil for Auto Doctor treatments.
function HospitalSim:ComputeReward(patient: any, manual: ManualInfo?): (number, number)
	local data = self.Data
	local reward = patient.BaseReward * Economy.IncomeMultiplier(data) * patient.Rarity.Multiplier
	if manual then
		local missIndex = math.clamp(manual.Misses + 1, 1, #GameConfig.WrongAnswerMultipliers)
		reward *= GameConfig.ManualCareBonus
		reward *= 1 + DoctorLevels.RewardBonusPerLevel * (manual.DoctorLevel - 1)
		reward *= manual.DifficultyBonus
		reward *= 1 + GameConfig.ComboStep * math.min(manual.Combo, GameConfig.ComboMax)
		reward *= GameConfig.WrongAnswerMultipliers[missIndex]
		if not manual.UsedHandbook and manual.Misses == 0 then
			reward *= GameConfig.ExpertBonus
		end
	end
	local pharmacy = math.floor(reward * Economy.PharmacyBonus(data) + 0.5)
	return math.max(1, math.floor(reward + 0.5)), pharmacy
end

function HospitalSim:CompleteTreatment(patient: any, manual: ManualInfo?): (number, number)
	if patient.State ~= "InExam" then
		return 0, 0
	end
	local reward, pharmacy = self:ComputeReward(patient, manual)
	local economy = self.Services.EconomyService
	local data = self.Data

	economy.AddMoney(self.Player, reward + pharmacy)
	data.PatientsTreated += 1
	if manual then
		data.ManualTreated += 1
	else
		data.AutoTreated += 1
	end
	if patient.Rarity.Stars >= 2 then
		data.RareTreated[patient.Rarity.Id] = (data.RareTreated[patient.Rarity.Id] or 0) + 1
	end
	economy.MarkDirty(self.Player)

	economy.Effect(self.Player, {
		Type = "Treated",
		Position = patient:GetPosition() + Vector3.new(0, 3, 0),
		Amount = reward,
		Pharmacy = pharmacy,
		Manual = manual ~= nil,
		Rarity = patient.Rarity.Id,
	})

	-- Free the room straight away so the next patient can walk in.
	local roomIndex = patient.RoomIndex
	local room = roomIndex and self.Rooms[roomIndex]
	if room and room.Patient == patient then
		room.Patient = nil
		if room.Doctor and room.Doctor.Patient == patient then
			room.Doctor:Finish()
		end
	end
	patient.RoomIndex = nil
	patient.LockedBy = nil
	patient:RemovePrompt()
	patient:ClearProgress()
	patient:SetState("Leaving", "Treated")
	self.ActiveCount -= 1

	task.delay(0.9, function()
		if not patient:IsAlive() or self.Destroyed then
			return
		end
		local exam = roomIndex and self.Layout.ExamRooms[roomIndex]
		local nodes = self.Layout.Nodes
		local route = {}
		if exam then
			patient.Agent:StandAt(exam.BedSide, exam.Entry - exam.BedSide)
			table.insert(route, exam.Entry)
			table.insert(route, exam.Front)
		end
		table.insert(route, nodes.ExitTop)
		table.insert(route, nodes.ExitMid)
		if nodes.Pharmacy then
			table.insert(route, nodes.Pharmacy)
			table.insert(route, nodes.ExitMid)
		end
		table.insert(route, nodes.ExitBottom)
		table.insert(route, nodes.Door)
		table.insert(route, nodes.ExitOutside)
		table.insert(route, nodes.Despawn)
		patient:SetStatus("Leaving")
		patient.Agent:Walk(route, function()
			self:Despawn(patient)
		end)
	end)
	return reward, pharmacy
end

function HospitalSim:Despawn(patient: any)
	if not self.Patients[patient.Id] then
		return
	end
	self.Patients[patient.Id] = nil
	if patient.State ~= "Leaving" then
		self.ActiveCount -= 1
	end
	if patient.SeatIndex and self.SeatOwner[patient.SeatIndex] == patient then
		self.SeatOwner[patient.SeatIndex] = nil
	end
	local room = patient.RoomIndex and self.Rooms[patient.RoomIndex]
	if room and room.Patient == patient then
		room.Patient = nil
		if room.Doctor and room.Doctor.Patient == patient then
			room.Doctor:Finish()
		end
	end
	self.Services.DiagnosisService.OnPatientRemoved(patient)
	patient:Destroy()
end

function HospitalSim:GetPatient(id: number): any
	return self.Patients[id]
end

-- Called by DiagnosisService when the player opens/closes a patient.
function HospitalSim:LockPatient(patient: any, player: Player?)
	patient.LockedBy = player
	local room = patient.RoomIndex and self.Rooms[patient.RoomIndex]
	local doctor = room and room.Doctor
	if player then
		patient:SetStatus("BeingDiagnosed")
		if doctor and doctor.Patient == patient then
			doctor:Pause()
		end
	elseif patient.State == "InExam" then
		if doctor and doctor.Patient == patient then
			doctor:Resume()
		else
			patient:SetStatus("NeedsDoctor")
		end
	end
end

-- Main loop -----------------------------------------------------------------------------

function HospitalSim:Update(dt: number)
	if self.Destroyed or not self.Layout then
		return
	end
	local level = HospitalLevels.Get(self.Data.HospitalLevel)

	-- Spawning
	local capacity = level.Capacity
	if self:_inTutorial() then
		capacity = 1
	end
	local interval = Economy.SpawnInterval(self.Data)
	if self.TotalSpawned == 0 then
		self.SpawnTimer = interval
	end
	self.SpawnTimer += dt
	if self.SpawnTimer >= interval then
		if self.ActiveCount < capacity and self:SpawnPatient() then
			self.SpawnTimer = 0
		else
			self.SpawnTimer = interval
		end
	end

	-- Send waiting patients to free exam rooms
	self.DispatchTimer += dt
	if self.DispatchTimer >= 0.25 then
		self.DispatchTimer = 0
		self:_dispatch()
	end

	-- Auto Doctors
	for _, room in self.Rooms do
		if room.Doctor then
			room.Doctor:Update(dt)
		end
	end

	-- Safety net: remove broken / lost NPCs so the loop can never jam.
	self.CheckTimer += dt
	if self.CheckTimer >= 1 then
		self.CheckTimer = 0
		local now = os.clock()
		for _, patient in self.Patients do
			local broken = not patient:IsAlive() or patient:GetPosition().Y < -50
			local stale = patient.State == "Leaving" and now - patient.StateSince > 60
			local stuckMoving = (patient.State == "Arriving" or patient.State == "ToSeat" or patient.State == "ToExam") and now - patient.StateSince > 45
			if broken or stale then
				self:Despawn(patient)
			elseif stuckMoving then
				self:_relocate(patient)
			end
		end
	end
end

function HospitalSim:Destroy()
	self.Destroyed = true
	for _, patient in self.Patients do
		self.Services.DiagnosisService.OnPatientRemoved(patient)
		patient:Destroy()
	end
	table.clear(self.Patients)
	for _, room in self.Rooms do
		if room.Doctor then
			room.Doctor:Destroy()
			room.Doctor = nil
		end
	end
	local hospital = self.Plot.Folder:FindFirstChild("Hospital")
	if hospital then
		hospital:Destroy()
	end
	for _, folder in { self.Plot.Patients, self.Plot.Doctors } do
		for _, child in folder:GetChildren() do
			CollectionService:RemoveTag(child, "Patient")
			child:Destroy()
		end
	end
end

return HospitalSim
