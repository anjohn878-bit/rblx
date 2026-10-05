--[[
	NPCAgent
	Wraps an NPC model with movement + animation + posing helpers shared by
	patients and Auto Doctors.
]]

local NPCAnimator = require(script.Parent.NPCAnimator)
local NPCMover = require(script.Parent.NPCMover)

local NPCAgent = {}
NPCAgent.__index = NPCAgent

export type NPCAgent = typeof(setmetatable(
	{} :: {
		Model: Model,
		Humanoid: Humanoid,
		Root: BasePart,
		RootHeight: number,
		Scale: number,
		Animator: any,
		MoveToken: NPCMover.Token?,
		Alive: boolean,
	},
	NPCAgent
))

function NPCAgent.new(model: Model, scale: number?): NPCAgent
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local s = scale or 1
	local self = setmetatable({
		Model = model,
		Humanoid = humanoid,
		Root = root,
		RootHeight = 3 * s,
		Scale = s,
		Animator = nil,
		MoveToken = nil,
		Alive = true,
	}, NPCAgent)

	-- NPCs must never die, fall over or swim.
	for _, state in
		{
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.Dead,
			Enum.HumanoidStateType.Seated,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end
	return self
end

-- Call once the model is parented into the workspace.
function NPCAgent.Activate(self: NPCAgent)
	pcall(function()
		self.Root:SetNetworkOwner(nil)
	end)
	self.Animator = NPCAnimator.new(self.Humanoid)
end

function NPCAgent.CancelMove(self: NPCAgent)
	if self.MoveToken then
		self.MoveToken.Cancelled = true
		self.MoveToken = nil
	end
end

function NPCAgent.Freeze(self: NPCAgent, cf: CFrame, mode: string)
	self:CancelMove()
	self.Root.Anchored = true
	self.Model:PivotTo(cf)
	if self.Animator then
		self.Animator:SetMode(mode)
	end
end

function NPCAgent.Unfreeze(self: NPCAgent)
	if self.Animator then
		self.Animator:SetMode("Stand")
	end
	if self.Root.Anchored then
		self.Root.Anchored = false
		pcall(function()
			self.Root:SetNetworkOwner(nil)
		end)
	end
end

-- Standing position on the floor at `floorPoint`, facing `lookDirection`.
function NPCAgent.StandCFrame(self: NPCAgent, floorPoint: Vector3, lookDirection: Vector3?): CFrame
	local position = floorPoint + Vector3.new(0, self.RootHeight, 0)
	local dir = lookDirection and Vector3.new(lookDirection.X, 0, lookDirection.Z)
	if dir and dir.Magnitude > 0.01 then
		return CFrame.lookAt(position, position + dir.Unit)
	end
	return CFrame.new(position) * self.Root.CFrame.Rotation
end

function NPCAgent.StandAt(self: NPCAgent, floorPoint: Vector3, lookDirection: Vector3?)
	self:CancelMove()
	self.Root.Anchored = true
	self.Model:PivotTo(self:StandCFrame(floorPoint, lookDirection))
	self:Unfreeze()
end

-- Standing still but anchored (cheap for idle NPCs).
function NPCAgent.HoldAt(self: NPCAgent, floorPoint: Vector3, lookDirection: Vector3?)
	self:Freeze(self:StandCFrame(floorPoint, lookDirection), "Stand")
end

function NPCAgent.SitAt(self: NPCAgent, seatTop: CFrame)
	-- Hips rest on the seat; the R6 root sits ~1.5 studs above it.
	self:Freeze(seatTop * CFrame.new(0, 1.45 * self.Scale, 0.15 * self.Scale), "Sit")
end

-- `bedTop` is the mattress surface with LookVector pointing at the pillow.
function NPCAgent.LieAt(self: NPCAgent, bedTop: CFrame)
	local position = bedTop.Position + Vector3.new(0, 0.55 * self.Scale, 0) + bedTop.LookVector * (0.4 * self.Scale)
	local cf = CFrame.fromMatrix(position, -bedTop.RightVector, bedTop.LookVector)
	self:Freeze(cf, "Lie")
end

function NPCAgent.Face(self: NPCAgent, direction: Vector3)
	local dir = Vector3.new(direction.X, 0, direction.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	local position = self.Root.Position
	local cf = CFrame.lookAt(position, position + dir.Unit)
	if self.Root.Anchored then
		self.Model:PivotTo(cf)
	else
		self.Root.CFrame = cf
	end
end

-- Walk through floor points; calls `onArrive` only if the walk completed.
function NPCAgent.Walk(self: NPCAgent, points: { Vector3 }, onArrive: (() -> ())?)
	self:CancelMove()
	self:Unfreeze()
	local token = NPCMover.NewToken()
	self.MoveToken = token
	task.spawn(function()
		local completed = NPCMover.Walk(self, points, token)
		if completed and not token.Cancelled and self.Alive then
			if self.MoveToken == token then
				self.MoveToken = nil
			end
			if onArrive then
				onArrive()
			end
		end
	end)
end

function NPCAgent.Teleport(self: NPCAgent, floorPoint: Vector3)
	NPCMover.Teleport(self, floorPoint)
end

function NPCAgent.Destroy(self: NPCAgent)
	self.Alive = false
	self:CancelMove()
	if self.Animator then
		self.Animator:Destroy()
	end
	self.Model:Destroy()
end

return NPCAgent
