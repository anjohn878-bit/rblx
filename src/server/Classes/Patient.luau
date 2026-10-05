--[[
	Patient
	One NPC patient. Holds its illness, rarity, reward and current state.
	Visual state is published through model attributes so every client can
	render billboards / progress bars locally.

	States: Arriving -> CheckingIn -> ToSeat -> Waiting -> ToExam -> InExam -> Leaving
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarities = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Rarities"))

local NPCAgent = require(script.Parent.Parent.NPC.NPCAgent)
local RigBuilder = require(script.Parent.Parent.NPC.RigBuilder)

export type Spec = {
	Id: number,
	Name: string,
	Rarity: Rarities.Rarity,
	Kind: string,
	Illness: any,
	BaseReward: number,
	Appearance: RigBuilder.Appearance,
}

local Patient = {}
Patient.__index = Patient

function Patient.new(spec: Spec, ownerUserId: number)
	local self = setmetatable({}, Patient)
	self.Id = spec.Id
	self.Name = spec.Name
	self.Rarity = spec.Rarity
	self.Kind = spec.Kind
	self.Illness = spec.Illness
	self.BaseReward = spec.BaseReward
	self.State = "Arriving"
	self.SeatIndex = nil :: number?
	self.RoomIndex = nil :: number?
	self.LockedBy = nil :: Player?
	self.Case = nil :: any
	self.Prompt = nil :: ProximityPrompt?
	self.SpawnedAt = os.clock()
	self.StateSince = os.clock()
	self.WaitingSince = 0

	local model = RigBuilder.CreateCharacter("Patient_" .. spec.Id, spec.Appearance)
	model:SetAttribute("PatientId", spec.Id)
	model:SetAttribute("PatientName", spec.Name)
	model:SetAttribute("Rarity", spec.Rarity.Id)
	model:SetAttribute("Kind", spec.Kind)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("Status", "Arriving")

	local torso = model:FindFirstChild("Torso") :: BasePart
	if spec.Rarity.Stars >= 2 then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "RarityParticles"
		sparkles.Color = ColorSequence.new(spec.Rarity.Color)
		sparkles.LightEmission = 1
		sparkles.Rate = 6 + spec.Rarity.Stars * 4
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(1, 2.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkles.Parent = torso
		local light = Instance.new("PointLight")
		light.Color = spec.Rarity.Color
		light.Range = 6 + spec.Rarity.Stars * 2
		light.Brightness = 1.5
		light.Parent = torso
	end

	self.Agent = NPCAgent.new(model, spec.Appearance.Scale)
	self.Model = model
	CollectionService:AddTag(model, "Patient")
	return self
end

function Patient:Spawn(parent: Instance, floorPoint: Vector3, look: Vector3?)
	self.Model:PivotTo(self.Agent:StandCFrame(floorPoint, look))
	self.Model.Parent = parent
	self.Agent:Activate()
end

function Patient:SetState(state: string, status: string?)
	self.State = state
	self.StateSince = os.clock()
	self.Model:SetAttribute("Status", status or state)
end

function Patient:SetStatus(status: string)
	self.Model:SetAttribute("Status", status)
end

-- Progress bar shown above the patient on every client.
function Patient:SetProgress(elapsed: number, duration: number, paused: boolean)
	local model = self.Model
	model:SetAttribute("ProgressDuration", duration)
	model:SetAttribute("ProgressStart", workspace:GetServerTimeNow() - elapsed)
	model:SetAttribute("ProgressPaused", paused)
	model:SetAttribute("ProgressFrozen", if duration > 0 then elapsed / duration else 0)
end

function Patient:ClearProgress()
	self.Model:SetAttribute("ProgressDuration", nil)
	self.Model:SetAttribute("ProgressStart", nil)
	self.Model:SetAttribute("ProgressPaused", nil)
	self.Model:SetAttribute("ProgressFrozen", nil)
end

function Patient:RemovePrompt()
	if self.Prompt then
		self.Prompt:Destroy()
		self.Prompt = nil
	end
end

function Patient:IsAlive(): boolean
	return self.Agent.Alive and self.Model.Parent ~= nil
end

function Patient:GetPosition(): Vector3
	return self.Agent.Root.Position
end

function Patient:Destroy()
	self:RemovePrompt()
	self.Agent:Destroy()
end

return Patient
