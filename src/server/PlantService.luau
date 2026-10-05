--!strict
-- Planting, growing and digging up plants. Growth is derived from the planting
-- timestamp, so plants keep growing while the owner is offline.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared:WaitForChild("Clock"))
local Config = require(Shared:WaitForChild("Config"))
local Growth = require(Shared:WaitForChild("Growth"))
local PlantModels = require(Shared:WaitForChild("PlantModels"))
local Remotes = require(Shared:WaitForChild("Remotes")).get()
local Scheduler = require(Shared:WaitForChild("Scheduler"))
local Seeds = require(Shared:WaitForChild("Seeds"))
local Types = require(Shared:WaitForChild("Types"))

local BirdService = require(script.Parent.BirdService)
local DataService = require(script.Parent.DataService)
local GardenService = require(script.Parent.GardenService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local PlantService = {}

type PlantState = {
	player: Player,
	plotIndex: number,
	seed: Types.SeedDef,
	plantedAt: number,
	model: Model,
	root: BasePart,
	mature: boolean,
	lastScale: number,
	slots: { Scheduler.Slot },
}

local states: { [Player]: { [number]: PlantState } } = {}
local plantsFolder: Folder? = nil
local rng = Random.new()

local function notify(player: Player, text: string, color: Color3?)
	local notice: Types.Notice = { kind = "toast", text = text, color = color }
	Remotes.Notify:FireClient(player, notice)
end

local function bloom(state: PlantState, now: number, announce: boolean)
	state.mature = true
	PlantModels.setMature(state.model, true)
	state.slots = {}
	for _ in state.seed.perches do
		table.insert(state.slots, Scheduler.newSlot(now, rng, true))
	end
	if announce then
		notify(
			state.player,
			`Your {state.seed.name} is fully grown! Birds will start visiting soon.`,
			Config.RARITY_COLORS[state.seed.rarity]
		)
	end
end

local function spawnPlant(
	player: Player,
	plotIndex: number,
	seedId: string,
	plantedAt: number,
	announce: boolean
): PlantState?
	local seed = Seeds.get(seedId)
	local cf = GardenService.plantCFrame(player, plotIndex)
	local folder = plantsFolder
	if not seed or not cf or not folder then
		return nil
	end

	local now = Clock.now()
	local progress = Growth.progress(plantedAt, seed.growTime, now)
	local model = PlantModels.build(seedId, cf, false)
	if not model then
		return nil
	end
	model.Name = string.format("Plant_%d_%d", player.UserId, plotIndex)
	model:SetAttribute("SeedId", seedId)
	model:SetAttribute("PlantedAt", plantedAt)
	model:SetAttribute("GrowTime", seed.growTime)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("PlotIndex", plotIndex)
	CollectionService:AddTag(model, "Plant")
	model.Parent = folder

	local scale = Growth.scale(progress)
	if scale < 1 then
		model:ScaleTo(scale)
	end

	local state: PlantState = {
		player = player,
		plotIndex = plotIndex,
		seed = seed,
		plantedAt = plantedAt,
		model = model,
		root = model.PrimaryPart :: BasePart,
		mature = false,
		lastScale = scale,
		slots = {},
	}
	if progress >= 1 then
		bloom(state, now, announce)
	end

	local plants = states[player]
	if not plants then
		plants = {}
		states[player] = plants
	end
	plants[plotIndex] = state
	GardenService.setHasPlant(player, plotIndex, true)
	return state
end

local function updatePlant(state: PlantState, now: number)
	if state.mature then
		BirdService.update(state, now)
		return
	end
	local progress = Growth.progress(state.plantedAt, state.seed.growTime, now)
	local scale = Growth.scale(progress)
	if progress >= 1 then
		state.model:ScaleTo(1)
		state.lastScale = 1
		bloom(state, now, true)
	elseif scale - state.lastScale >= 0.012 then
		state.model:ScaleTo(scale)
		state.lastScale = scale
	end
end

function PlantService.init(world: WorldBuilder.World)
	plantsFolder = world.plantsFolder
	task.spawn(function()
		while true do
			task.wait(Config.TICK)
			local now = Clock.now()
			for _, plants in states do
				for _, state in plants do
					xpcall(updatePlant, function(err)
						warn("[PlantService] update failed: " .. tostring(err))
					end, state, now)
				end
			end
		end
	end)
end

-- Recreates a player's saved plants when they join.
function PlantService.loadPlayer(player: Player, profile: DataService.Profile)
	for key, record in profile.plants do
		local index = tonumber(key)
		if index then
			spawnPlant(player, index, record.seedId, record.plantedAt, false)
		end
	end
end

function PlantService.plant(player: Player, plotIndex: any, seedId: any)
	local profile = DataService.get(player)
	if not profile or not GardenService.get(player) then
		return
	end
	if
		type(plotIndex) ~= "number"
		or plotIndex ~= math.floor(plotIndex)
		or plotIndex < 1
		or plotIndex > Config.MAX_PLOTS
	then
		return
	end
	if plotIndex > profile.plots then
		notify(player, "That plot is still locked.")
		return
	end
	if not Seeds.isValid(seedId) then
		return
	end
	local id = seedId :: string
	local key = tostring(plotIndex)
	if profile.plants[key] then
		notify(player, "Something is already growing there.")
		return
	end
	local count = profile.seeds[id] or 0
	if count < 1 then
		notify(player, "You don't have any of that seed. Visit the Seed Shop!")
		return
	end

	local plantedAt = Clock.now()
	if not spawnPlant(player, plotIndex, id, plantedAt, true) then
		return
	end
	if count > 1 then
		profile.seeds[id] = count - 1
	else
		profile.seeds[id] = nil
	end
	profile.plants[key] = { seedId = id, plantedAt = plantedAt }
	DataService.push(player)
end

-- Digging up a growing plant returns the seed; a grown plant is lost for good.
function PlantService.dig(player: Player, plotIndex: any)
	local profile = DataService.get(player)
	if not profile or type(plotIndex) ~= "number" then
		return
	end
	local plants = states[player]
	local state = if plants then plants[plotIndex] else nil
	if not plants or not state then
		return
	end

	BirdService.cancelHabitat(state)
	state.model:Destroy()
	plants[plotIndex] = nil
	profile.plants[tostring(plotIndex)] = nil
	if not state.mature then
		profile.seeds[state.seed.id] = (profile.seeds[state.seed.id] or 0) + 1
	end
	GardenService.setHasPlant(player, plotIndex, false)
	DataService.push(player)
	if DataService.rescue(player) then
		notify(player, "Here's a free Sunflower seed to get you going again!", Config.RARITY_COLORS.Common)
	end
end

function PlantService.clearPlayer(player: Player)
	local plants = states[player]
	if not plants then
		return
	end
	states[player] = nil
	for _, state in plants do
		BirdService.cancelHabitat(state)
		state.model:Destroy()
	end
end

-- Dev helper: finish every growing plant right now.
function PlantService.growAll(player: Player)
	local profile = DataService.get(player)
	local plants = states[player]
	if not profile or not plants then
		return
	end
	local now = Clock.now()
	for index, state in plants do
		if not state.mature then
			local plantedAt = now - state.seed.growTime
			state.plantedAt = plantedAt
			state.model:SetAttribute("PlantedAt", plantedAt)
			local record = profile.plants[tostring(index)]
			if record then
				record.plantedAt = plantedAt
			end
		end
	end
	DataService.push(player)
end

return PlantService
