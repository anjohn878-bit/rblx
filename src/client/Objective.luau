--!strict
-- A single line that tells the player what to do next. This is the "player
-- waits" loop made visible: plant, wait, watch the birds, upgrade.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared:WaitForChild("Birds"))
local Clock = require(Shared:WaitForChild("Clock"))
local Format = require(Shared:WaitForChild("Format"))
local Seeds = require(Shared:WaitForChild("Seeds"))

local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local Objective = {}

local label: TextLabel
local localPlayer = Players.LocalPlayer

-- Looks at the local player's plants: how many are growing / blooming, and how long until the next bloom.
local function scanPlants(): (number, number, string?, number?)
	local growing, blooming = 0, 0
	local soonestName: string? = nil
	local soonest: number? = nil
	local now = Clock.now()
	for _, plant in CollectionService:GetTagged("Plant") do
		if plant:GetAttribute("OwnerUserId") == localPlayer.UserId then
			local plantedAt = plant:GetAttribute("PlantedAt")
			local growTime = plant:GetAttribute("GrowTime")
			local seed = Seeds.get(tostring(plant:GetAttribute("SeedId")))
			if type(plantedAt) == "number" and type(growTime) == "number" and seed then
				local remaining = growTime - (now - plantedAt)
				if remaining > 0 then
					growing += 1
					if not soonest or remaining < soonest then
						soonest, soonestName = remaining, seed.name
					end
				else
					blooming += 1
				end
			end
		end
	end
	return growing, blooming, soonestName, soonest
end

local function compute(): string
	local growing, blooming, soonestName, soonest = scanPlants()
	local seedsLeft = State.totalSeeds()
	local selected = State.selected and Seeds.get(State.selected)

	if growing + blooming == 0 then
		if seedsLeft == 0 then
			return "You're out of seeds! Open the Seed Shop on the left to buy more."
		end
		local name = if selected then selected.name else "seed"
		return `Walk up to a soil plot in your garden and press [E] to plant your {name}.`
	end
	if blooming > 0 and growing > 0 and soonest then
		return `Birds are visiting! Next bloom: {soonestName} in {Format.duration(soonest)}.`
	end
	if blooming > 0 then
		local found, total = State.speciesDiscovered(), #Birds.list
		if seedsLeft > 0 then
			return `Birds are visiting! Plant your spare seeds too. ({found}/{total} species found)`
		end
		return `Birds are visiting! ({found}/{total} species found) Buy better seeds to attract rarer birds.`
	end
	if soonest then
		return `Your {soonestName} is growing - ready in {Format.duration(soonest)}. Better seeds take longer, but attract rarer birds!`
	end
	return ""
end

function Objective.init(gui: ScreenGui)
	label = Ui.label({
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 0.25,
		BackgroundColor3 = Ui.COLORS.bg,
		Font = Ui.FONT_BOLD,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	Ui.corner(12).Parent = label
	Ui.padding(8).Parent = label
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(560, 90), Parent = label })

	task.spawn(function()
		while true do
			local text = compute()
			label.Text = text
			label.Visible = text ~= ""
			task.wait(0.5)
		end
	end)
end

return Objective
