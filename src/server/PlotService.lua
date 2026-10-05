-- Owns the garden plots: assigning them to players, planting, digging up,
-- and growing plants over time. Birds are handed off to BirdService once a
-- plant is in full bloom.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PlantBuilder = require(Shared.PlantBuilder)
local Rarities = require(Shared.Rarities)
local Seeds = require(Shared.Seeds)
local Util = require(Shared.Util)

local BirdService = require(script.Parent.BirdService)
local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)

local PlotService = {}

local plots = {} -- array of plot info tables from WorldBuilder
local playerPlots = {} -- [Player] = plot

local BLOOM_STAGE = 4

local function stageFor(progress)
	if progress >= 1 then
		return BLOOM_STAGE
	elseif progress >= Config.YoungPlantAt then
		return 3
	elseif progress >= Config.SproutAt then
		return 2
	end
	return 1
end

------------------------------------------------------------------------------
-- Prompts

local function clearPrompts(tile)
	for _, child in ipairs(tile:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
end

local function plantActionText(player)
	local profile = DataService.GetProfile(player)
	local seed = profile and profile.SelectedSeed and Seeds.Get(profile.SelectedSeed)
	return seed and ("Plant " .. seed.Name) or "Plant Seed"
end

local function newPrompt(tile, owner, name)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 9
	-- the client hides prompts that belong to other players' gardens
	prompt:SetAttribute("OwnerUserId", owner.UserId)
	prompt:SetAttribute("TileIndex", tile:GetAttribute("TileIndex"))
	return prompt
end

local function setEmptyPrompt(plot, index)
	local tile = plot.Tiles[index]
	local owner = plot.Owner
	clearPrompts(tile)
	if not owner then
		return
	end
	local prompt = newPrompt(tile, owner, "PlantPrompt")
	prompt.ActionText = plantActionText(owner)
	prompt.ObjectText = "Empty Soil"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.Triggered:Connect(function(player)
		if player == owner then
			PlotService.Plant(player, index)
		end
	end)
	prompt.Parent = tile
end

local function setDigPrompt(plot, index)
	local tile = plot.Tiles[index]
	local owner = plot.Owner
	local state = plot.Plants[index]
	clearPrompts(tile)
	if not owner or not state then
		return
	end
	local prompt = newPrompt(tile, owner, "DigPrompt")
	prompt.ActionText = "Dig Up"
	prompt.ObjectText = state.Seed.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 1.2
	prompt.Triggered:Connect(function(player)
		if player == owner then
			PlotService.DigUp(player, index)
		end
	end)
	prompt.Parent = tile
end

------------------------------------------------------------------------------
-- Plant visuals

local function addStatusBillboard(model, seed, topY)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PlantStatus"
	gui.Size = UDim2.fromOffset(160, 52)
	gui.StudsOffsetWorldSpace = Vector3.new(0, topY + 1.4, 0)
	gui.MaxDistance = 40
	gui.LightInfluence = 0

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.45)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = seed.Icon .. " " .. seed.Name
	title.TextColor3 = Rarities.Color(seed.Rarity)
	title.TextStrokeTransparency = 0.3
	title.TextScaled = true
	title.Parent = gui

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Position = UDim2.fromScale(0, 0.45)
	status.Size = UDim2.fromScale(1, 0.32)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.Text = "Growing..."
	status.TextColor3 = Color3.new(1, 1, 1)
	status.TextStrokeTransparency = 0.3
	status.TextScaled = true
	status.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0.15, 0.82)
	bar.Size = UDim2.fromScale(0.7, 0.14)
	bar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	gui.Parent = model.PrimaryPart
	return gui
end

local function rebuildModel(state)
	local hadBird = state.Model and state.Model:GetAttribute("HasBird")
	if state.Model then
		state.Model:Destroy()
	end
	local tile = state.Tile
	local model = PlantBuilder.Build(state.Seed, state.Stage)
	model.Name = "Plant" .. state.TileIndex
	model:SetAttribute("SeedId", state.Seed.Id)
	model:SetAttribute("GrowTime", state.Seed.GrowTime)
	model:SetAttribute("Stage", state.Stage)
	model:SetAttribute("OwnerUserId", state.Owner.UserId)
	model:SetAttribute("HasBird", hadBird == true)
	addStatusBillboard(model, state.Seed, model:GetAttribute("TopY"))
	model:PivotTo(tile.CFrame * CFrame.new(0, tile.Size.Y / 2, 0))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag("BirdGardenPlant")
	model.Parent = state.Plot.PlantsFolder
	state.Model = model
	state.Speed = nil -- make the next growth update refresh the timer attributes
end

-- How fast a player's plants grow (Green Thumb pets make them faster).
local function growthSpeed(player)
	return math.max(Config.GrowthSpeed, 0.001) * (1 + PetService.GetPerks(player).Growth)
end

-- Adds growth since the last update and moves the plant to its current
-- stage. Returns true if it just bloomed.
local function updateGrowth(state, now, speed)
	state.Grown = math.min(state.Seed.GrowTime, state.Grown + math.max(0, now - state.LastUpdate) * speed)
	state.LastUpdate = now
	state.Saved.Grown = state.Grown
	state.Saved.SavedAt = math.floor(now)

	local stage = stageFor(state.Grown / state.Seed.GrowTime)
	local bloomed = false
	if stage ~= state.Stage then
		bloomed = state.Stage ~= 0 and state.Stage < BLOOM_STAGE and stage == BLOOM_STAGE
		state.Stage = stage
		rebuildModel(state)
	end
	if state.Speed ~= speed then
		-- the client works out the countdown from these
		state.Speed = speed
		state.Model:SetAttribute("Grown", state.Grown)
		state.Model:SetAttribute("GrownAt", now)
		state.Model:SetAttribute("Speed", speed)
	end
	return bloomed
end

local function createPlant(plot, index, saved, grown, now)
	local state = {
		Seed = Seeds.Get(saved.Seed),
		Saved = saved, -- the entry in the player's data, kept up to date
		Grown = grown,
		LastUpdate = now,
		Stage = 0,
		Owner = plot.Owner,
		Plot = plot,
		TileIndex = index,
		Tile = plot.Tiles[index],
	}
	plot.Plants[index] = state
	updateGrowth(state, now, growthSpeed(plot.Owner))
	setDigPrompt(plot, index)
	return state
end

local function removePlant(plot, index)
	local state = plot.Plants[index]
	if not state then
		return
	end
	BirdService.RemoveBird(state)
	if state.Model then
		state.Model:Destroy()
	end
	plot.Plants[index] = nil
end

------------------------------------------------------------------------------
-- Public API

function PlotService.Init(worldPlots)
	plots = worldPlots
	for _, plot in ipairs(plots) do
		plot.Owner = nil
		plot.Plants = {}
		local folder = Instance.new("Folder")
		folder.Name = "Plants"
		folder.Parent = plot.Model
		plot.PlantsFolder = folder
	end
end

function PlotService.GetPlot(player)
	return playerPlots[player]
end

function PlotService.Assign(player)
	for _, plot in ipairs(plots) do
		if not plot.Owner then
			plot.Owner = player
			playerPlots[player] = plot
			plot.SignLabel.Text = player.DisplayName .. "'s Garden"
			player:SetAttribute("PlotId", plot.Id)
			for index in pairs(plot.Tiles) do
				setEmptyPrompt(plot, index)
			end
			return plot
		end
	end
	return nil
end

function PlotService.Release(player)
	local plot = playerPlots[player]
	if not plot then
		return
	end
	for index in pairs(plot.Tiles) do
		removePlant(plot, index)
		clearPrompts(plot.Tiles[index])
	end
	plot.Owner = nil
	plot.SignLabel.Text = "Empty Garden"
	playerPlots[player] = nil
end

function PlotService.LoadPlants(player)
	local plot = playerPlots[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return
	end
	local now = Util.Now()
	local speed = growthSpeed(player)
	for key, saved in pairs(data.Plants) do
		local index = tonumber(key)
		if index and plot.Tiles[index] and Seeds.Get(saved.Seed) then
			-- plants keep growing while you're away
			local grown
			if tonumber(saved.Grown) then
				grown = saved.Grown + math.max(0, now - (tonumber(saved.SavedAt) or now)) * speed
			else
				-- saves from before pets existed stored when the seed was planted
				grown = math.max(0, now - (tonumber(saved.PlantedAt) or now)) * math.max(Config.GrowthSpeed, 0.001)
				saved.PlantedAt = nil
			end
			createPlant(plot, index, saved, grown, now)
		else
			data.Plants[key] = nil
		end
	end
	PlotService.UpdatePlantPrompts(player)
end

-- Refreshes "Plant <seed>" on every empty tile after the selection changes.
function PlotService.UpdatePlantPrompts(player)
	local plot = playerPlots[player]
	if not plot then
		return
	end
	local text = plantActionText(player)
	for index, tile in pairs(plot.Tiles) do
		if not plot.Plants[index] then
			local prompt = tile:FindFirstChild("PlantPrompt")
			if prompt then
				prompt.ActionText = text
			end
		end
	end
end

function PlotService.Plant(player, index)
	local plot = playerPlots[player]
	local profile = DataService.GetProfile(player)
	if not plot or not profile or plot.Plants[index] or not plot.Tiles[index] then
		return
	end
	local seedId = DataService.EnsureSelection(player)
	if not seedId then
		Net.Notify:FireClient(player, "You don't have any seeds! Buy some at the Seed Shop. 🌱", "Error")
		return
	end

	local data = profile.Data
	data.Seeds[seedId] -= 1
	if data.Seeds[seedId] <= 0 then
		data.Seeds[seedId] = nil
	end
	local now = Util.Now()
	local saved = { Seed = seedId, Grown = 0, SavedAt = math.floor(now) }
	data.Plants[tostring(index)] = saved
	local state = createPlant(plot, index, saved, 0, now)

	DataService.EnsureSelection(player)
	PlotService.UpdatePlantPrompts(player)
	DataService.Push(player)
	Net.Effect:FireClient(
		player,
		state.Tile.CFrame.Position + Vector3.new(0, 3, 0),
		"🌱 Planted!",
		Color3.fromRGB(150, 255, 120)
	)
end

function PlotService.DigUp(player, index)
	local plot = playerPlots[player]
	local data = DataService.Get(player)
	local state = plot and plot.Plants[index]
	if not state or not data then
		return
	end
	removePlant(plot, index)
	data.Plants[tostring(index)] = nil
	setEmptyPrompt(plot, index)
	Net.Notify:FireClient(player, "You dug up your " .. state.Seed.Name .. ".", "Info")
	PlotService.EnsureNotStuck(player)
	DataService.Push(player)
end

-- Gives a free seed if the player has no seeds, no plants and can't afford any.
function PlotService.EnsureNotStuck(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	for _, count in pairs(data.Seeds) do
		if count > 0 then
			return
		end
	end
	if next(data.Plants) ~= nil then
		return
	end
	local cheapest = Seeds.List[1]
	if data.Coins >= cheapest.Price then
		return
	end
	data.Seeds[cheapest.Id] = 1
	DataService.EnsureSelection(player)
	PlotService.UpdatePlantPrompts(player)
	Net.Notify:FireClient(
		player,
		"Polly gave you a free " .. cheapest.Name .. " seed. Plant it to attract birds!",
		"Success"
	)
end

function PlotService.TeleportToPlot(player)
	local plot = playerPlots[player]
	local character = player.Character
	if plot and character and character.PrimaryPart then
		character:PivotTo(plot.SpawnCFrame)
	end
end

function PlotService.Tick(now)
	for player, plot in pairs(playerPlots) do
		local speed = growthSpeed(player)
		for _, state in pairs(plot.Plants) do
			if updateGrowth(state, now, speed) then
				BirdService.ScheduleFirst(state, now)
				Net.Notify:FireClient(
					player,
					state.Seed.Icon .. " Your " .. state.Seed.Name .. " is blooming! Birds will start visiting.",
					"Success"
				)
				Net.Effect:FireClient(
					player,
					state.Model.PrimaryPart.CFrame.Position + Vector3.new(0, state.Model:GetAttribute("TopY") + 1, 0),
					"✨ Bloomed!",
					Rarities.Color(state.Seed.Rarity)
				)
			end
			if state.Stage == BLOOM_STAGE then
				BirdService.UpdatePlant(state, now)
			end
		end
	end
end

return PlotService
