--!strict
-- Proximity prompts for the local player's own garden. They are created on the
-- client, so other players never see (or can trigger) your prompts, and the
-- text can follow your selected seed instantly.
--   [E]        plant the selected seed / unlock the next plot
--   [X] (hold) dig up a plant

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes")).get()
local Seeds = require(Shared:WaitForChild("Seeds"))

local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)

local Prompts = {}

local localPlayer = Players.LocalPlayer
local plotPrompts: { [BasePart]: ProximityPrompt } = {}
local digPrompts: { [Instance]: ProximityPrompt } = {}

local function myGarden(): Instance?
	local gardens = workspace:FindFirstChild("Gardens")
	if not gardens then
		return nil
	end
	for _, garden in gardens:GetChildren() do
		if garden:GetAttribute("OwnerUserId") == localPlayer.UserId then
			return garden
		end
	end
	return nil
end

local function newPrompt(
	parent: BasePart,
	name: string,
	key: Enum.KeyCode,
	hold: number,
	distance: number
): ProximityPrompt
	local prompt = Ui.new("ProximityPrompt", {
		Name = name,
		KeyboardKeyCode = key,
		HoldDuration = hold,
		MaxActivationDistance = distance,
		RequiresLineOfSight = false,
		Parent = parent,
	})
	return prompt
end

local function unlockPlot()
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.UnlockPlot:InvokeServer()
		end)
		if ok then
			Toasts.result(result)
		end
	end)
end

local function createPlotPrompt(soil: BasePart, index: number): ProximityPrompt
	local prompt = newPrompt(soil, "PlotPrompt", Enum.KeyCode.E, 0, 13)
	prompt.Triggered:Connect(function()
		if index > State.plots then
			if index == State.plots + 1 and State.nextPlotPrice then
				unlockPlot()
			end
		elseif soil:GetAttribute("HasPlant") == false and State.selected then
			Remotes.PlantSeed:FireServer(index, State.selected)
		end
	end)
	return prompt
end

local function updatePlotPrompt(prompt: ProximityPrompt, soil: BasePart, index: number)
	if index > State.plots then
		local isNext = index == State.plots + 1 and State.nextPlotPrice ~= nil
		prompt.Enabled = isNext
		prompt.ObjectText = "Locked plot"
		prompt.HoldDuration = 0.5
		prompt.ActionText = if State.nextPlotPrice
			then `Unlock for {Format.feathers(State.nextPlotPrice)} feathers`
			else "Locked"
		return
	end
	prompt.HoldDuration = 0
	prompt.ObjectText = "Garden plot"
	local seed = if State.selected then Seeds.get(State.selected) else nil
	prompt.Enabled = soil:GetAttribute("HasPlant") == false and seed ~= nil
	prompt.ActionText = if seed then `Plant {seed.name}` else "Pick a seed"
end

local function createDigPrompt(plant: Model, root: BasePart): ProximityPrompt
	local prompt = newPrompt(root, "DigPrompt", Enum.KeyCode.X, 1.5, 11)
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Triggered:Connect(function()
		local index = plant:GetAttribute("PlotIndex")
		if type(index) == "number" then
			Remotes.DigPlant:FireServer(index)
		end
	end)
	return prompt
end

local function reconcile()
	local garden = myGarden()

	if garden then
		for index = 1, Config.MAX_PLOTS do
			local soil = garden:FindFirstChild("Plot_" .. index)
			if soil and soil:IsA("BasePart") then
				local prompt = plotPrompts[soil]
				if not prompt then
					prompt = createPlotPrompt(soil, index)
					plotPrompts[soil] = prompt
				end
				updatePlotPrompt(prompt, soil, index)
			end
		end
	end
	-- forget prompts for soil that is no longer ours (e.g. we respawned into a new server)
	for soil, prompt in plotPrompts do
		if not garden or not soil:IsDescendantOf(garden) then
			prompt:Destroy()
			plotPrompts[soil] = nil
		end
	end

	for _, plant in CollectionService:GetTagged("Plant") do
		if plant:IsA("Model") and plant:GetAttribute("OwnerUserId") == localPlayer.UserId then
			local root = plant:FindFirstChild("Root")
			if root and root:IsA("BasePart") then
				local prompt = digPrompts[plant]
				if not prompt then
					prompt = createDigPrompt(plant, root)
					digPrompts[plant] = prompt
				end
				local seed = Seeds.get(tostring(plant:GetAttribute("SeedId")))
				prompt.ObjectText = if seed then seed.name else "Plant"
				prompt.ActionText = if plant:GetAttribute("Mature") == true
					then "Dig up (seed is lost!)"
					else "Dig up (seed returned)"
			end
		end
	end
	for plant, prompt in digPrompts do
		if not plant.Parent then
			prompt:Destroy()
			digPrompts[plant] = nil
		end
	end
end

function Prompts.init()
	State.changed:Connect(reconcile)
	State.selectedChanged:Connect(reconcile)
	CollectionService:GetInstanceAddedSignal("Plant"):Connect(function()
		task.defer(reconcile)
	end)
	task.spawn(function()
		while true do
			reconcile()
			task.wait(0.5)
		end
	end)
end

return Prompts
