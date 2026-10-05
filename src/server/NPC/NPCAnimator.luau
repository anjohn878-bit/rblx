--[[
	NPCAnimator
	Plays the default Roblox R6 idle / walk / sit animations on an NPC from the
	server (they replicate to every client automatically).
]]

local ANIMATIONS = {
	Idle = "rbxassetid://180435571",
	Walk = "rbxassetid://180426354",
	Sit = "rbxassetid://178130996",
}

local NPCAnimator = {}
NPCAnimator.__index = NPCAnimator

local animationObjects: { [string]: Animation } = {}
for key, id in ANIMATIONS do
	local animation = Instance.new("Animation")
	animation.Name = key
	animation.AnimationId = id
	animationObjects[key] = animation
end

local function load(animator: Animator, key: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local ok, track = pcall(function()
		return animator:LoadAnimation(animationObjects[key])
	end)
	if ok and track then
		track.Priority = priority
		track.Looped = looped
		return track
	end
	return nil
end

function NPCAnimator.new(humanoid: Humanoid)
	local self = setmetatable({}, NPCAnimator)
	self.Humanoid = humanoid
	self.Connections = {} :: { RBXScriptConnection }
	self.Mode = "Stand"

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	self.Animator = animator :: Animator

	self.Idle = load(self.Animator, "Idle", Enum.AnimationPriority.Idle, true)
	self.Walk = load(self.Animator, "Walk", Enum.AnimationPriority.Movement, true)
	self.Sit = load(self.Animator, "Sit", Enum.AnimationPriority.Action, true)

	if self.Idle then
		self.Idle:Play(0.2)
	end

	table.insert(
		self.Connections,
		humanoid.Running:Connect(function(speed: number)
			self:_onRunning(speed)
		end)
	)
	return self
end

function NPCAnimator:_onRunning(speed: number)
	if self.Mode ~= "Stand" or not self.Walk then
		return
	end
	if speed > 0.5 then
		if not self.Walk.IsPlaying then
			self.Walk:Play(0.15)
		end
		self.Walk:AdjustSpeed(math.clamp(speed / 14, 0.6, 1.6))
	elseif self.Walk.IsPlaying then
		self.Walk:Stop(0.2)
	end
end

function NPCAnimator:SetMode(mode: string)
	if self.Mode == mode then
		return
	end
	self.Mode = mode
	if self.Walk and self.Walk.IsPlaying then
		self.Walk:Stop(0.1)
	end
	if mode == "Sit" then
		if self.Sit then
			self.Sit:Play(0.2)
		end
		if self.Idle then
			self.Idle:Stop(0.2)
		end
	elseif mode == "Lie" then
		if self.Sit then
			self.Sit:Stop(0.1)
		end
		if self.Idle then
			self.Idle:Stop(0.1)
		end
	else
		if self.Sit then
			self.Sit:Stop(0.2)
		end
		if self.Idle and not self.Idle.IsPlaying then
			self.Idle:Play(0.2)
		end
	end
end

function NPCAnimator:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

return NPCAnimator
