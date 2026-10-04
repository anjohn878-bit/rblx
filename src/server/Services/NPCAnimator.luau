--[[
	NPCAnimator
	Minimal server-side animator for bots and ambient NPCs (they have no Animate
	LocalScript). Uses Roblox's default R15 animation set and emote animations,
	so no custom assets are required.
]]

local NPCAnimator = {}

NPCAnimator.Ids = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://913402848",
	Run = "rbxassetid://913376220",
	Wave = "rbxassetid://507770239",
	Point = "rbxassetid://507770453",
	Dance = "rbxassetid://507771019",
	Dance2 = "rbxassetid://507776043",
	Dance3 = "rbxassetid://507777268",
	Laugh = "rbxassetid://507770818",
	Cheer = "rbxassetid://507770677",
}

local animationCache: { [string]: Animation } = {}

local function getAnimation(name: string): Animation
	local anim = animationCache[name]
	if not anim then
		anim = Instance.new("Animation")
		anim.AnimationId = NPCAnimator.Ids[name]
		animationCache[name] = anim
	end
	return anim
end

-- Attaches locomotion animations. Returns a controller with :PlayEmote(name, looped).
function NPCAnimator.Attach(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local tracks = {}
	local function track(name: string, priority: Enum.AnimationPriority): AnimationTrack?
		if tracks[name] then
			return tracks[name]
		end
		local ok, t = pcall(function()
			return (animator :: Animator):LoadAnimation(getAnimation(name))
		end)
		if ok and t then
			t.Priority = priority
			tracks[name] = t
			return t
		end
		return nil
	end

	local current: string? = nil
	local emoteTrack: AnimationTrack? = nil

	local function setLocomotion(name: string)
		if current == name then
			return
		end
		if current and tracks[current] then
			tracks[current]:Stop(0.2)
		end
		current = name
		local t = track(name, Enum.AnimationPriority.Core)
		if t then
			t.Looped = true
			t:Play(0.2)
		end
	end

	setLocomotion("Idle")
	humanoid.Running:Connect(function(speed)
		if speed > 17.5 then
			setLocomotion("Run")
		elseif speed > 0.75 then
			setLocomotion("Walk")
		else
			setLocomotion("Idle")
		end
		if speed > 0.75 and emoteTrack then
			emoteTrack:Stop(0.2)
			emoteTrack = nil
		end
	end)

	local controller = {}
	function controller.PlayEmote(name: string, looped: boolean?)
		if emoteTrack then
			emoteTrack:Stop(0.2)
		end
		local t = track(name, Enum.AnimationPriority.Action)
		if t then
			t.Looped = looped == true
			t:Play(0.2)
			emoteTrack = t
		end
	end
	function controller.StopEmote()
		if emoteTrack then
			emoteTrack:Stop(0.2)
			emoteTrack = nil
		end
	end
	return controller
end

return NPCAnimator
