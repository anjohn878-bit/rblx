--[[
	AmbientService
	Keeps the Grounds feeling alive: spectators cheering in the stands, locals
	chatting and emoting around the plaza, and walkers moving between points.
	NPCs are server-owned, cheap (no per-frame logic) and never touch match balls.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Catalog = require(Shared.Catalog)

local MapBuilder = require(script.Parent.MapBuilder)
local NPCAnimator = require(script.Parent.NPCAnimator)

local AmbientService = {}

local rng = Random.new()
local SKIN_TONES = {
	Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 134, 94),
	Color3.fromRGB(141, 85, 54), Color3.fromRGB(96, 58, 38),
}

local function randomKit()
	local kit = {}
	for _, category in { "Shirt", "Shorts", "Socks", "Boots" } do
		local options = Catalog.ByCategory[category]
		kit[category] = options[rng:NextInteger(1, #options)].Id
	end
	kit.Headwear = if rng:NextNumber() < 0.4 then "head_cap_black" else "head_none"
	kit.Trail = "trail_none"
	return kit
end

local function spawnNPC(name: string, cframe: CFrame)
	local desc = Instance.new("HumanoidDescription")
	local skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
	desc.TorsoColor, desc.LeftLegColor, desc.RightLegColor = skin, skin, skin
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = name
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	Cosmetics.Apply(model, randomKit(), nil)
	model:PivotTo(cframe)
	model.Parent = MapBuilder.GetRoot().NPCs
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return model, humanoid, NPCAnimator.Attach(model)
end

local EMOTES = { "Cheer", "Wave", "Laugh", "Point", "Dance", "Dance2", "Dance3" }

local function spectator(position: Vector3, lookAt: Vector3)
	local _, _, anim = spawnNPC("Fan", CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
	if not anim then
		return
	end
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(4, 12))
			anim.PlayEmote(if rng:NextNumber() < 0.6 then "Cheer" else "Point", false)
		end
	end)
end

local function hangout(position: Vector3, lookAt: Vector3)
	local _, _, anim = spawnNPC("Local", CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
	if not anim then
		return
	end
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(5, 14))
			anim.PlayEmote(EMOTES[rng:NextInteger(1, #EMOTES)], false)
		end
	end)
end

local function walker(points: { Vector3 })
	local model, humanoid = spawnNPC("Walker", CFrame.new(points[1] + Vector3.new(0, 3, 0)))
	humanoid.WalkSpeed = rng:NextNumber(7, 10)
	task.spawn(function()
		local i = 1
		while model.Parent do
			i = i % #points + 1
			humanoid:MoveTo(points[i])
			humanoid.MoveToFinished:Wait()
			task.wait(rng:NextNumber(1, 5))
		end
	end)
end

function AmbientService.Init() end

function AmbientService.Start()
	local pitch = Config.Pitches[1]
	local c = pitch.Center
	local standZ = c.Z - pitch.Width / 2 - 1
	-- Fans in the stands (rows match MapBuilder stand steps)
	for _ = 1, 8 do
		local row = rng:NextInteger(0, 4)
		local x = c.X + rng:NextNumber(-pitch.Length * 0.35, pitch.Length * 0.35)
		local z = standZ - 6 - row * 3
		local y = 1.4 + row * 2.8 + 3
		spectator(Vector3.new(x, y, z), c)
	end
	-- Locals around the plaza and practice court
	local spots = {
		{ Vector3.new(-30, 3, 58), Vector3.new(-26, 3, 62) },
		{ Vector3.new(-26, 3, 62), Vector3.new(-30, 3, 58) },
		{ Vector3.new(34, 3, 104), Vector3.new(30, 3, 100) },
		{ Config.Hub.PracticeArea + Vector3.new(-26, 3, 8), Config.Hub.PracticeArea },
		{ Config.Hub.Locker + Vector3.new(16, 3, -14), Config.Hub.Locker },
	}
	for _, spot in spots do
		hangout(spot[1], spot[2])
	end
	-- Walkers
	walker({ Vector3.new(-120, 0, 110), Vector3.new(120, 0, 110), Vector3.new(120, 0, -95), Vector3.new(-120, 0, -95) })
	walker({ Vector3.new(80, 0, 70), Vector3.new(-80, 0, 70), Vector3.new(-80, 0, 100) })
	walker({ Vector3.new(150, 0, -60), Vector3.new(150, 0, 60) })
end

return AmbientService
