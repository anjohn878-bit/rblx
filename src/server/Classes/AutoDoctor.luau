--[[
	AutoDoctor
	A hired doctor that staffs one exam room. When a patient lies down in
	its room the doctor walks to the bed, examines for `TreatTime` seconds
	(shown as a progress bar), treats the patient (the hospital gets paid)
	and walks back to the desk.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local AutoDoctors = require(Config:WaitForChild("AutoDoctors"))

local NPCAgent = require(script.Parent.Parent.NPC.NPCAgent)
local RigBuilder = require(script.Parent.Parent.NPC.RigBuilder)

local SKINS = {
	Color3.fromRGB(255, 220, 190),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(200, 150, 110),
	Color3.fromRGB(160, 110, 75),
	Color3.fromRGB(110, 75, 50),
}

local AutoDoctor = {}
AutoDoctor.__index = AutoDoctor

function AutoDoctor.new(sim: any, roomIndex: number, tier: number)
	local self = setmetatable({}, AutoDoctor)
	self.Sim = sim
	self.RoomIndex = roomIndex
	self.Tier = tier
	self.Skin = SKINS[math.random(1, #SKINS)]
	self.Patient = nil :: any
	self.Elapsed = 0
	self.Duration = 0
	self.Paused = false
	self.Agent = nil :: any
	self:_build()
	return self
end

function AutoDoctor:_build()
	if self.Agent then
		self.Agent:Destroy()
	end
	local tierInfo = AutoDoctors.Tiers[self.Tier]
	local model = RigBuilder.CreateDoctor("AutoDoctor_" .. self.RoomIndex, {
		Coat = tierInfo.Coat,
		Scrubs = tierInfo.Scrubs,
		Accent = tierInfo.Accent,
		Robot = tierInfo.Robot,
		Glasses = self.Tier >= 3,
	}, self.Skin)
	model:SetAttribute("DoctorName", tierInfo.Name)
	model:SetAttribute("Tier", self.Tier)
	model:SetAttribute("Room", self.RoomIndex)
	model:SetAttribute("OwnerUserId", self.Sim.Player.UserId)
	model:SetAttribute("Status", "Idle")
	self.Agent = NPCAgent.new(model)
	self.Agent.Humanoid.WalkSpeed = 14

	local room = self.Sim.Layout.ExamRooms[self.RoomIndex]
	if self.Patient then
		model:PivotTo(self.Agent:StandCFrame(room.DoctorWork, room.DoctorWorkLook))
	else
		model:PivotTo(self.Agent:StandCFrame(room.DoctorIdle, room.DoctorIdleLook))
	end
	model.Parent = self.Sim.Plot.Doctors
	self.Agent:Activate()
	CollectionService:AddTag(model, "AutoDoctor")
	self:Place()
end

function AutoDoctor:SetTier(tier: number)
	if tier == self.Tier then
		return
	end
	self.Tier = tier
	self:_build()
	if self.Patient then
		-- New tier = new speed; keep the progress fraction.
		local fraction = if self.Duration > 0 then self.Elapsed / self.Duration else 0
		self.Duration = self.Sim:GetTreatTime(self.Tier)
		self.Elapsed = fraction * self.Duration
		self.Patient:SetProgress(self.Elapsed, self.Duration, self.Paused)
	end
end

-- Snap to the right spot for the current state (after rebuilds).
function AutoDoctor:Place()
	local room = self.Sim.Layout.ExamRooms[self.RoomIndex]
	if not room then
		return
	end
	if self.Patient then
		self.Agent:HoldAt(room.DoctorWork, room.DoctorWorkLook)
	else
		self.Agent:HoldAt(room.DoctorIdle, room.DoctorIdleLook)
	end
end

function AutoDoctor:Start(patient: any)
	if self.Patient == patient then
		return
	end
	self.Patient = patient
	self.Elapsed = 0
	self.Duration = self.Sim:GetTreatTime(self.Tier)
	self.Paused = patient.LockedBy ~= nil
	if not self.Paused then
		patient:SetStatus("Examining")
	end
	patient:SetProgress(0, self.Duration, self.Paused)
	self.Agent.Model:SetAttribute("Status", "Examining")

	local room = self.Sim.Layout.ExamRooms[self.RoomIndex]
	self.Agent:Walk({ room.DoctorWork }, function()
		self.Agent:HoldAt(room.DoctorWork, room.DoctorWorkLook)
	end)
end

function AutoDoctor:Pause()
	if self.Patient and not self.Paused then
		self.Paused = true
		self.Patient:SetProgress(self.Elapsed, self.Duration, true)
	end
end

function AutoDoctor:Resume()
	if self.Patient and self.Paused then
		self.Paused = false
		self.Patient:SetStatus("Examining")
		self.Patient:SetProgress(self.Elapsed, self.Duration, false)
	end
end

function AutoDoctor:Update(dt: number)
	local patient = self.Patient
	if not patient or self.Paused then
		return
	end
	if not patient:IsAlive() or patient.State ~= "InExam" then
		self:Finish()
		return
	end
	self.Elapsed += dt
	if self.Elapsed >= self.Duration then
		self.Sim:CompleteTreatment(patient, nil)
	end
end

-- Called by the hospital when the patient in this room has been treated.
function AutoDoctor:Finish()
	if not self.Patient then
		return
	end
	self.Patient = nil
	self.Elapsed = 0
	self.Paused = false
	self.Agent.Model:SetAttribute("Status", "Idle")
	local room = self.Sim.Layout.ExamRooms[self.RoomIndex]
	if room then
		self.Agent:Walk({ room.DoctorIdle }, function()
			self.Agent:HoldAt(room.DoctorIdle, room.DoctorIdleLook)
		end)
	end
end

function AutoDoctor:Destroy()
	if self.Agent then
		self.Agent:Destroy()
	end
end

return AutoDoctor
