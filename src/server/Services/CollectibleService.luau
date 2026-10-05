--[[
	CollectibleService
	Scatters golden snowflakes across every rink. Skate through one to grab a
	bonus scaled by that rink's multiplier. Pickups are checked on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local CollectibleService = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local TAG = "GoldenSnowflake"

local container
local active = {} -- [part] = rinkId
local random = Random.new()

local function countOnRink(rinkId)
	local count = 0
	for _, id in active do
		if id == rinkId then
			count += 1
		end
	end
	return count
end

local function spawnOn(rink)
	local map = workspace:FindFirstChild("Map")
	local model = map and map.Rinks:FindFirstChild(rink.Id)
	local ice = model and model:FindFirstChild("Ice")
	if not ice then
		return
	end

	local margin = 14
	local x = random:NextNumber(-0.5, 0.5) * (ice.Size.X - margin * 2)
	local z = random:NextNumber(-0.5, 0.5) * (ice.Size.Z - margin * 2)

	local part = Instance.new("Part")
	part.Name = TAG
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(2, 2, 2)
	part.CFrame = ice.CFrame * CFrame.new(x, 3.2, z)
	part:SetAttribute("RinkId", rink.Id)
	part:AddTag(TAG)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Icon"
	billboard.Size = UDim2.fromScale(4.5, 4.5)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 300
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Flake"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = "❄"
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(150, 90, 0)
	stroke.Parent = label

	local glow = Instance.new("PointLight")
	glow.Color = GOLD
	glow.Range = 12
	glow.Brightness = 1.5
	glow.Parent = part

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(GOLD)
	sparkles.LightEmission = 1
	sparkles.Rate = 6
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(1, 2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.35)
	sparkles.Parent = part

	part.Parent = container
	active[part] = rink.Id
end

local function collect(player, part, rinkId)
	active[part] = nil
	local profile = DataService.get(player)
	local amount = math.floor(Config.Economy.GoldenSnowflakeValue * Formulas.earnMultiplier(profile, rinkId) + 0.5)
	local position = part.Position
	part:Destroy()

	DataService.addSnowflakes(player, amount)
	profile.Stats.GoldenSnowflakes += 1
	DataService.markChanged(player)
	Remotes.CollectiblePicked:FireClient(player, position, amount)
end

local function checkPickups()
	local radius = Config.Economy.CollectRadius
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local profile = DataService.get(player)
		if not root or not profile then
			continue
		end
		for part, rinkId in active do
			if (part.Position - root.Position).Magnitude <= radius and Formulas.isRinkUnlocked(profile, rinkId) then
				collect(player, part, rinkId)
			end
		end
	end
end

function CollectibleService.init()
	container = Instance.new("Folder")
	container.Name = "Collectibles"
	container.Parent = workspace

	for _, rink in Config.Rinks do
		for _ = 1, rink.Collectibles do
			spawnOn(rink)
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.1)
			checkPickups()
		end
	end)

	-- Top rinks back up one at a time.
	task.spawn(function()
		while true do
			task.wait(Config.Economy.GoldenSnowflakeRespawn)
			for _, rink in Config.Rinks do
				if countOnRink(rink.Id) < rink.Collectibles then
					spawnOn(rink)
				end
			end
		end
	end)
end

return CollectibleService
