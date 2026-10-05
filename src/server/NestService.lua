-- Breeding. Put two adult birds of the same species in a nest and they keep
-- an egg warm until it hatches into a baby. The baby joins their family,
-- inherits their stars (sometimes one better) and has a much better chance of
-- being shiny if its parents are.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared.Birds)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Pets = require(Shared.Pets)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)
local PlotService = require(script.Parent.PlotService)

local NestService = {}

local rng = Random.new()

------------------------------------------------------------------------------
-- Visuals

local function setEgg(nest, species)
	local egg = nest.Model:FindFirstChild("Egg")
	if egg and egg:GetAttribute("Species") == species then
		return
	end
	if egg then
		egg:Destroy()
	end
	if not species then
		return
	end
	local look = Birds.Get(species).Look
	egg = Instance.new("Part")
	egg.Name = "Egg"
	egg.Size = Vector3.new(1.1, 1.4, 1.1)
	egg.CFrame = nest.CFrame * CFrame.new(0, 1.25, 0)
	egg.Color = look.Belly or look.Body
	egg.Material = look.Material or Enum.Material.SmoothPlastic
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg:SetAttribute("Species", species)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	-- a few speckles in the bird's colours
	for i = 1, 4 do
		local angle = i * 1.9
		local spot = Instance.new("Part")
		spot.Name = "Speckle"
		spot.Shape = Enum.PartType.Ball
		spot.Size = Vector3.new(0.22, 0.22, 0.22)
		spot.CFrame = egg.CFrame * CFrame.new(math.cos(angle) * 0.5, (i - 2.5) * 0.22, math.sin(angle) * 0.5)
		spot.Color = look.Wing or look.Head or look.Body
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanQuery = false
		spot.CanTouch = false
		spot.Parent = egg
	end
	egg.Parent = nest.Model
end

function NestService.UpdateVisuals(player)
	local plot = PlotService.GetPlot(player)
	if not plot then
		return
	end
	local data = DataService.Get(player)
	for index, nest in ipairs(plot.Nests) do
		local entry = data and data.Nests[tostring(index)]
		local base = nest.Base
		base:SetAttribute("Species", entry and entry.Species or "")
		base:SetAttribute("HatchAt", entry and entry.HatchAt or 0)
		base:SetAttribute("Waiting", entry ~= nil and entry.Waiting == true)
		local label = base.NestStatus.Status
		label.Text = entry and ("🥚 " .. Birds.Get(entry.Species).Name .. " egg") or "🪺 Empty nest"
		setEgg(nest, entry and entry.Species)
	end
end

local function clearPrompts(nest)
	for _, child in ipairs(nest.Base:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
end

-- Called when a player gets a plot.
function NestService.SetupPlot(player)
	local plot = PlotService.GetPlot(player)
	if not plot then
		return
	end
	for index, nest in ipairs(plot.Nests) do
		clearPrompts(nest)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "NestPrompt"
		prompt.ActionText = "Open Nest"
		prompt.ObjectText = "Nest " .. index
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OwnerUserId", player.UserId)
		prompt.Triggered:Connect(function(who)
			if who == player then
				Net.OpenNest:FireClient(player, index)
			end
		end)
		prompt.Parent = nest.Base
	end
	NestService.UpdateVisuals(player)
end

-- Called before a player's plot is released.
function NestService.ClearPlot(player)
	local plot = PlotService.GetPlot(player)
	if not plot then
		return
	end
	for _, nest in ipairs(plot.Nests) do
		clearPrompts(nest)
		setEgg(nest, nil)
		nest.Base:SetAttribute("Species", "")
		nest.Base:SetAttribute("HatchAt", 0)
		nest.Base:SetAttribute("Waiting", false)
		nest.Base.NestStatus.Status.Text = "🪺 Empty nest"
	end
end

------------------------------------------------------------------------------
-- Breeding

local function eggsInProgress(data)
	local count = 0
	for _ in pairs(data.Nests) do
		count += 1
	end
	return count
end

-- Returns ok, message
function NestService.StartBreeding(player, petIdA, petIdB, nestIndex)
	local data = DataService.Get(player)
	if not data or not PlotService.GetPlot(player) then
		return false, "You need a garden to breed birds."
	end
	if type(petIdA) ~= "string" or type(petIdB) ~= "string" or petIdA == petIdB then
		return false, "Pick two different birds."
	end
	local a, b = data.Pets[petIdA], data.Pets[petIdB]
	if not a or not b then
		return false, "Those birds aren't in your aviary."
	end
	if a.Species ~= b.Species then
		return false, "Only two birds of the same kind can raise a family."
	end
	local now = Util.Now()
	for _, pet in ipairs({ a, b }) do
		if Pets.IsBaby(pet, now) then
			return false, pet.Name .. " is still a baby. Wait for it to grow up."
		elseif pet.Nest then
			return false, pet.Name .. " is already sitting on an egg."
		end
	end
	if PetService.IsInTrade(player, petIdA) or PetService.IsInTrade(player, petIdB) then
		return false, "Take those birds out of your trade first."
	end
	if Pets.CountPets(data.Pets) + eggsInProgress(data) >= Config.MaxPets then
		return false, "Your aviary is full. Make room for the baby first."
	end

	if nestIndex ~= nil then
		nestIndex = tonumber(nestIndex)
		if
			not nestIndex
			or nestIndex ~= math.floor(nestIndex)
			or nestIndex < 1
			or nestIndex > Config.NestCount
			or data.Nests[tostring(nestIndex)]
		then
			nestIndex = nil
		end
	end
	if not nestIndex then
		for index = 1, Config.NestCount do
			if not data.Nests[tostring(index)] then
				nestIndex = index
				break
			end
		end
	end
	if not nestIndex then
		return false, "All your nests are busy."
	end

	local hatchAt = now + Pets.BreedTime(a.Species)
	data.Nests[tostring(nestIndex)] = {
		Species = a.Species,
		ParentA = petIdA,
		ParentB = petIdB,
		StartedAt = math.floor(now),
		HatchAt = hatchAt,
		Restore = { A = a.Equipped == true, B = b.Equipped == true },
	}
	a.Equipped, b.Equipped = false, false
	a.Nest, b.Nest = nestIndex, nestIndex
	NestService.UpdateVisuals(player)
	PetService.Refresh(player)
	return true,
		a.Name
			.. " and "
			.. b.Name
			.. " are keeping an egg warm. It hatches in "
			.. Util.FormatTime(hatchAt - now)
			.. "!"
end

local function freeParents(data, entry)
	local restore = entry.Restore or {}
	for _, pair in ipairs({ { entry.ParentA, restore.A }, { entry.ParentB, restore.B } }) do
		local pet = data.Pets[pair[1]]
		if pet then
			pet.Nest = nil
			if pair[2] and Pets.CountEquipped(data.Pets) < Config.MaxEquippedPets then
				pet.Equipped = true
			end
		end
	end
end

function NestService.Cancel(player, nestIndex)
	local data = DataService.Get(player)
	local key = tostring(tonumber(nestIndex) or "")
	local entry = data and data.Nests[key]
	if not entry then
		return false, "That nest is empty."
	end
	data.Nests[key] = nil
	freeParents(data, entry)
	NestService.UpdateVisuals(player)
	PetService.Refresh(player)
	return true, "The parents left the nest. No egg this time."
end

local function rollStars(a, b)
	local stars = math.floor(((a.Stars or 1) + (b.Stars or 1)) / 2 + 0.5)
	if rng:NextNumber() < Config.BredStarUpChance then
		stars += 1
	end
	return math.clamp(stars, 1, Pets.MaxStars)
end

local function hatch(player, data, key, entry, now)
	local a, b = data.Pets[entry.ParentA], data.Pets[entry.ParentB]
	if not a or not b then
		-- a parent went missing; just clear the nest
		data.Nests[key] = nil
		freeParents(data, entry)
		return true
	end
	if Pets.CountPets(data.Pets) >= Config.MaxPets then
		if not entry.Waiting then
			entry.Waiting = true
			Net.Notify:FireClient(
				player,
				"🥚 Your egg is ready, but your aviary is full! Sell or trade a bird to make room.",
				"Error"
			)
			NestService.UpdateVisuals(player)
			DataService.Push(player)
		end
		return false
	end

	local newFamily = false
	local family = a.Family or b.Family
	if not family then
		family = PetService.NewFamilyName(data)
		newFamily = true
	end
	a.Family = a.Family or family
	b.Family = b.Family or family

	local shinyParents = (a.Shiny and 1 or 0) + (b.Shiny and 1 or 0)
	local baby = PetService.NewPet({
		Species = entry.Species,
		Family = family,
		Stars = rollStars(a, b),
		Shiny = rng:NextNumber() < Config.BredShinyChance[shinyParents + 1],
		Generation = math.max(a.Generation or 0, b.Generation or 0) + 1,
		Parents = a.Name .. " & " .. b.Name,
		ParentIds = { entry.ParentA, entry.ParentB },
		GrowsUpAt = now + Pets.GrowUpTime(entry.Species),
	})
	local babyId = PetService.AddPet(data, baby)
	data.Nests[key] = nil
	data.TotalHatched = (data.TotalHatched or 0) + 1
	freeParents(data, entry)
	if Pets.CountEquipped(data.Pets) < Config.MaxEquippedPets then
		baby.Equipped = true
	end

	local def = Birds.Get(entry.Species)
	if newFamily then
		Net.Notify:FireClient(
			player,
			"🏡 " .. a.Name .. " and " .. b.Name .. " started the " .. family .. " family!",
			"Rare"
		)
	end
	Net.Notify:FireClient(
		player,
		"🐣 A baby "
			.. (baby.Shiny and "✨ Shiny " or "")
			.. def.Name
			.. " hatched! Say hi to "
			.. Pets.DisplayName(baby)
			.. " "
			.. Pets.StarText(baby.Stars),
		"Rare"
	)
	local plot = PlotService.GetPlot(player)
	local nest = plot and plot.Nests[tonumber(key)]
	if nest then
		Net.Effect:FireClient(
			player,
			nest.CFrame.Position + Vector3.new(0, 3, 0),
			"🐣 Hatched!",
			Color3.fromRGB(255, 240, 150)
		)
	end
	return true, babyId
end

function NestService.Tick(now)
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService.Get(player)
		if data and next(data.Nests) ~= nil then
			local changed = false
			for key, entry in pairs(data.Nests) do
				if now >= entry.HatchAt and hatch(player, data, key, entry, now) then
					changed = true
				end
			end
			if changed then
				NestService.UpdateVisuals(player)
				PetService.Refresh(player)
			end
		end
	end
end

return NestService
