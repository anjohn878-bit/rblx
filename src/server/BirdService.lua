-- Spawns birds on blooming plants and flies them in. When the owner
-- befriends one it joins their aviary as a pet (see PetService); birds
-- nobody befriends fly away again.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdBuilder = require(Shared.BirdBuilder)
local Birds = require(Shared.Birds)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Pets = require(Shared.Pets)
local Rarities = require(Shared.Rarities)
local Util = require(Shared.Util)

local PetService = require(script.Parent.PetService)

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
	local def = bird.Def
	local pet, petId, coins, firstTime, refusal, replaced = PetService.Befriend(player, def, bird.Shiny)
	if refusal == "Full" then
		-- special birds wait on their perch while the player makes room
		Net.Notify:FireClient(
			player,
			"🐦 Your aviary is full! Sell spares or trade in 🐦 Birds to make room for this "
				.. (bird.Shiny and "✨ Shiny " or "")
				.. def.Name
				.. ".",
			"Error"
		)
		return
	end
	if not pet then
		return
	end
	bird.Leaving = true
	if bird.Prompt then
		bird.Prompt:Destroy()
		bird.Prompt = nil
	end

	local model = bird.Model
	local body = model.PrimaryPart
	local position = body.CFrame.Position
	Net.Effect:FireClient(player, position + Vector3.new(0, 1, 0), "❤", Color3.fromRGB(255, 110, 150))
	if coins > 0 then
		Net.Effect:FireClient(
			player,
			position + Vector3.new(0, 2.5, 0),
			"+" .. Util.FormatNumber(coins) .. " 🪙",
			Color3.fromRGB(255, 220, 80)
		)
	end

	local title = (bird.Shiny and "✨ Shiny " or "") .. def.Name
	if firstTime then
		Net.Notify:FireClient(player, "📖 New bird discovered: " .. def.Name .. "! Discovery bonus coins!", "Rare")
	end
	if petId then
		Net.Effect:FireClient(
			player,
			position + Vector3.new(0, 2, 0),
			pet.Name
				.. " "
				.. Pets.StarText(pet.Stars)
				.. "  •  worth 🪙 "
				.. Util.FormatNumber(Pets.BaseValue(pet, Util.Now())),
			bird.Shiny and Color3.fromRGB(255, 230, 120) or Rarities.Color(def.Rarity)
		)
		if replaced then
			Net.Notify:FireClient(
				player,
				"🔁 " .. pet.Name .. " the " .. def.Name .. " took " .. replaced.Name .. "'s spot in your garden.",
				"Info"
			)
		end
		if bird.Shiny or Rarities.Rank(def.Rarity) >= Rarities.Rank("Rare") or pet.Stars >= 3 then
			Net.Notify:FireClient(
				player,
				"🐦 " .. pet.Name .. " the " .. title .. " " .. Pets.StarText(pet.Stars) .. " joined your aviary!",
				"Rare"
			)
		end
		if pet.Equipped then
			-- it stays as a pet: the client draws it hopping down from this spot
			local marker = PetService.FindMarker(player, petId)
			if marker then
				marker:SetAttribute("SpawnAt", position)
				-- only clients drawing it right now need the starting spot
				task.delay(3, function()
					if marker.Parent then
						marker:SetAttribute("SpawnAt", nil)
					end
				end)
			end
			bird.Gone = true
			local state = bird.State
			if state.Bird == bird then
				state.Bird = nil
				setHasBird(state, false)
				BirdService.ScheduleNext(state, Util.Now())
			end
			model:Destroy()
		else
			-- no room to roam: it flies off to the aviary
			Net.Effect:FireClient(
				player,
				position + Vector3.new(0, 3.2, 0),
				"🏠 Off to your aviary",
				Color3.fromRGB(200, 230, 255)
			)
			task.delay(0.3, flyAway, bird)
		end
	else
		Net.Notify:FireClient(
			player,
			"Your aviary is full, so " .. title .. " was sold for " .. Util.FormatNumber(coins) .. " coins.",
			"Info"
		)
		task.delay(0.3, flyAway, bird)
	end
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

	-- the Lucky perk tilts the odds toward rarer and shiny birds
	local luck = PetService.GetPerks(state.Owner).Luck
	local weights = {}
	for _, entry in ipairs(state.Seed.Birds) do
		local rank = Rarities.Rank(Birds.Get(entry.Id).Rarity)
		table.insert(weights, { Id = entry.Id, Weight = entry.Weight * (1 + luck * (rank - 1)) })
	end
	local def = Birds.Get(Util.WeightedPick(weights, rng).Id)
	local shiny = rng:NextNumber() < Config.ShinyChance * (1 + luck)
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
	local attraction = PetService.GetPerks(state.Owner).Attraction
	state.NextBirdAt = now + rng:NextNumber(range[1], range[2]) / (1 + attraction)
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
