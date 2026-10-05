-- Spawns birds on blooming plants, flies them in, lets the owner befriend
-- them for coins, and flies them away again.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdBuilder = require(Shared.BirdBuilder)
local Birds = require(Shared.Birds)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rarities = require(Shared.Rarities)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)

local BirdService = {}

local rng = Random.new()
local birdsFolder

local function setHasBird(state, value)
	if state.Model then
		state.Model:SetAttribute("HasBird", value)
	end
end

local function addNameTag(model, def, shiny)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BirdTag"
	gui.Size = UDim2.fromOffset(170, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2 * (def.Look.Size or 1) + 0.8, 0)
	gui.MaxDistance = 45
	gui.LightInfluence = 0

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "BirdName"
	nameLabel.Size = UDim2.fromScale(1, 0.58)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Text = (shiny and "✨ Shiny " or "") .. def.Name
	nameLabel.TextColor3 = shiny and Color3.fromRGB(255, 230, 120) or Rarities.Color(def.Rarity)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextScaled = true
	nameLabel.Parent = gui

	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.Position = UDim2.fromScale(0, 0.58)
	info.Size = UDim2.fromScale(1, 0.42)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamBold
	info.Text = def.Rarity
	info.TextColor3 = Color3.new(1, 1, 1)
	info.TextStrokeTransparency = 0.3
	info.TextScaled = true
	info.Parent = gui

	gui.Parent = model.PrimaryPart
end

local function flyAway(bird)
	if bird.Gone then
		return
	end
	bird.Leaving = true
	bird.Gone = true
	if bird.Prompt then
		bird.Prompt:Destroy()
		bird.Prompt = nil
	end

	-- free the plant so the next bird can be scheduled
	local state = bird.State
	if state.Bird == bird then
		state.Bird = nil
		setHasBird(state, false)
		BirdService.ScheduleNext(state, Util.Now())
	end

	local model = bird.Model
	local body = model.PrimaryPart
	if not body or not model.Parent then
		model:Destroy()
		return
	end
	model:SetAttribute("Flying", true)
	model:SetAttribute("LeavesAt", nil)

	local start = body.CFrame.Position
	local angle = rng:NextNumber(0, math.pi * 2)
	local target = start + Vector3.new(math.cos(angle) * 90, 50, math.sin(angle) * 90)
	local facing = CFrame.lookAt(start, Vector3.new(target.X, start.Y, target.Z))
	body.CFrame = facing
	local duration = (target - start).Magnitude / (Config.BirdFlightSpeed * 1.2)
	local tween = TweenService:Create(
		body,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ CFrame = facing + (target - start) }
	)
	tween.Completed:Connect(function()
		model:Destroy()
	end)
	tween:Play()
	Debris:AddItem(model, duration + 3)
end

local function befriend(bird, player)
	if bird.Leaving or not bird.Landed then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	bird.Leaving = true
	if bird.Prompt then
		bird.Prompt:Destroy()
		bird.Prompt = nil
	end

	local def = bird.Def
	local reward = def.Reward * (bird.Shiny and Config.ShinyMultiplier or 1)
	local firstTime = (data.Journal[def.Id] or 0) == 0
	if firstTime then
		reward *= Config.DiscoveryBonusMultiplier
	end
	data.Coins += reward
	data.Journal[def.Id] = (data.Journal[def.Id] or 0) + 1
	if bird.Shiny then
		data.ShinyJournal[def.Id] = (data.ShinyJournal[def.Id] or 0) + 1
	end
	data.TotalBefriended += 1
	DataService.Push(player)

	local body = bird.Model.PrimaryPart
	local position = body.CFrame.Position
	Net.Effect:FireClient(
		player,
		position + Vector3.new(0, 2, 0),
		"+" .. Util.FormatNumber(reward) .. " 🪙",
		Color3.fromRGB(255, 220, 80)
	)
	Net.Effect:FireClient(player, position + Vector3.new(0, 1, 0), "❤", Color3.fromRGB(255, 110, 150))
	if firstTime then
		Net.Notify:FireClient(player, "📖 New bird discovered: " .. def.Name .. "! Discovery bonus!", "Rare")
	end
	if bird.Shiny then
		Net.Notify:FireClient(
			player,
			"✨ You befriended a SHINY " .. def.Name .. "! x" .. Config.ShinyMultiplier .. " coins!",
			"Rare"
		)
	end

	-- a happy little hop, then off it goes
	local hop = TweenService:Create(
		body,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{ CFrame = body.CFrame + Vector3.new(0, 1.2, 0) }
	)
	hop:Play()
	task.delay(0.45, flyAway, bird)
end

local function land(bird)
	local model = bird.Model
	local owner = bird.State.Owner
	bird.Landed = true
	bird.LeavesAt = Util.Now() + Config.BirdStayTime
	model:SetAttribute("Flying", false)
	model:SetAttribute("LeavesAt", bird.LeavesAt)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BefriendPrompt"
	prompt.ActionText = "Befriend"
	prompt.ObjectText = (bird.Shiny and "✨ Shiny " or "") .. bird.Def.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerUserId", owner.UserId)
	prompt.Triggered:Connect(function(player)
		if player == owner then
			befriend(bird, player)
		end
	end)
	prompt.Parent = model.PrimaryPart
	bird.Prompt = prompt
end

local function spawnBird(state)
	local plantModel = state.Model
	local perch = plantModel and plantModel.PrimaryPart and plantModel.PrimaryPart:FindFirstChild("Perch")
	if not perch then
		return
	end

	local entry = Util.WeightedPick(state.Seed.Birds, rng)
	local def = Birds.Get(entry.Id)
	local shiny = rng:NextNumber() < Config.ShinyChance
	local model = BirdBuilder.Build(def, { Shiny = shiny })
	model.Name = def.Id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("BirdId", def.Id)
	model:SetAttribute("Shiny", shiny)
	model:SetAttribute("OwnerUserId", state.Owner.UserId)
	model:SetAttribute("Flying", true)
	addNameTag(model, def, shiny)
	model:AddTag("BirdGardenBird")

	-- face the front of the garden, with a little random turn
	local front = -state.Plot.CFrame.LookVector
	local facing = CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0):VectorToWorldSpace(front)
	local perchPosition = plantModel.PrimaryPart.CFrame * perch.Position
	local landPosition = perchPosition + Vector3.new(0, model:GetAttribute("StandHeight"), 0)
	local landCf = CFrame.lookAt(landPosition, landPosition + facing)

	local angle = rng:NextNumber(0, math.pi * 2)
	local startPosition = landPosition + Vector3.new(math.cos(angle) * 70, 40, math.sin(angle) * 70)
	local startCf = CFrame.lookAt(startPosition, Vector3.new(landPosition.X, startPosition.Y, landPosition.Z))
	model:PivotTo(startCf)
	model.Parent = birdsFolder

	local bird = {
		Def = def,
		Model = model,
		Shiny = shiny,
		State = state,
		Landed = false,
		Leaving = false,
	}
	state.Bird = bird
	setHasBird(state, true)

	local duration = (landPosition - startPosition).Magnitude / Config.BirdFlightSpeed
	local tween = TweenService:Create(
		model.PrimaryPart,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ CFrame = landCf }
	)
	bird.Tween = tween
	tween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed and state.Bird == bird and not bird.Gone then
			land(bird)
		end
	end)
	tween:Play()

	if shiny or Rarities.Rank(def.Rarity) >= Rarities.Rank("Rare") then
		Net.Notify:FireClient(
			state.Owner,
			"🐦 A " .. (shiny and "✨ Shiny " or "") .. def.Name .. " is flying to your " .. state.Seed.Name .. "!",
			"Rare"
		)
	end
end

------------------------------------------------------------------------------
-- Public API

function BirdService.Init(folder)
	birdsFolder = folder
end

-- First visit comes quickly after a plant blooms (or loads in already blooming).
function BirdService.ScheduleFirst(state, now)
	state.NextBirdAt = now + rng:NextNumber(3, 8)
end

function BirdService.ScheduleNext(state, now)
	local range = state.Seed.BirdInterval
	state.NextBirdAt = now + rng:NextNumber(range[1], range[2])
end

-- Called every tick for each blooming plant.
function BirdService.UpdatePlant(state, now)
	local bird = state.Bird
	if bird then
		if bird.Landed and not bird.Leaving and now >= bird.LeavesAt then
			flyAway(bird)
		end
		return
	end
	if not state.NextBirdAt then
		BirdService.ScheduleFirst(state, now)
	end
	if now >= state.NextBirdAt then
		spawnBird(state)
		if not state.Bird then
			-- couldn't spawn (no perch yet); try again later
			BirdService.ScheduleNext(state, now)
		end
	end
end

-- Instantly removes any bird on this plant (plant dug up or owner left).
function BirdService.RemoveBird(state)
	local bird = state.Bird
	state.Bird = nil
	state.NextBirdAt = nil
	if bird then
		bird.Gone = true
		bird.Leaving = true
		if bird.Tween then
			bird.Tween:Cancel()
		end
		bird.Model:Destroy()
	end
end

return BirdService
