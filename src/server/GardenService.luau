--!strict
-- Hands out garden slots to players and keeps the plots' look in sync with
-- how many the owner has unlocked.

local Players = game:GetService("Players")

local WorldBuilder = require(script.Parent.WorldBuilder)
type Garden = WorldBuilder.Garden

local GardenService = {}

local SOIL_COLOR = Color3.fromRGB(96, 68, 46)
local LOCKED_COLOR = Color3.fromRGB(116, 118, 124)

local world: WorldBuilder.World? = nil
local byPlayer: { [Player]: Garden } = {}

function GardenService.init(builtWorld: WorldBuilder.World)
	world = builtWorld
end

local function setLocked(garden: Garden, index: number, locked: boolean)
	local soil = garden.plots[index]
	soil:SetAttribute("Locked", locked)
	soil.Color = if locked then LOCKED_COLOR else SOIL_COLOR
	soil.Material = if locked then Enum.Material.Slate else Enum.Material.Ground
	garden.lockGuis[index].Enabled = locked
end

local function setSign(garden: Garden, text: string)
	for _, label in garden.signLabels do
		label.Text = text
	end
end

function GardenService.get(player: Player): Garden?
	return byPlayer[player]
end

function GardenService.assign(player: Player): Garden?
	if not world then
		return nil
	end
	for _, garden in world.gardens do
		if garden.owner == nil then
			garden.owner = player
			garden.model:SetAttribute("OwnerUserId", player.UserId)
			setSign(garden, player.DisplayName .. "'s Garden")
			byPlayer[player] = garden
			return garden
		end
	end
	return nil
end

function GardenService.release(player: Player)
	local garden = byPlayer[player]
	if not garden then
		return
	end
	byPlayer[player] = nil
	garden.owner = nil
	garden.model:SetAttribute("OwnerUserId", 0)
	setSign(garden, "Free Garden")
	for index, soil in garden.plots do
		soil:SetAttribute("HasPlant", false)
		setLocked(garden, index, true)
	end
end

function GardenService.refreshPlots(player: Player, unlocked: number)
	local garden = byPlayer[player]
	if not garden then
		return
	end
	for index in garden.plots do
		setLocked(garden, index, index > unlocked)
	end
end

function GardenService.setHasPlant(player: Player, index: number, has: boolean)
	local garden = byPlayer[player]
	if garden then
		garden.plots[index]:SetAttribute("HasPlant", has)
	end
end

-- Where a plant's root sits: the middle of the soil's top surface.
function GardenService.plantCFrame(player: Player, index: number): CFrame?
	local garden = byPlayer[player]
	if not garden then
		return nil
	end
	local soil = garden.plots[index]
	return soil.CFrame * CFrame.new(0, soil.Size.Y / 2, 0)
end

function GardenService.placeCharacter(player: Player)
	local garden = byPlayer[player]
	local character = player.Character
	if not garden or not character or player.Parent ~= Players then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root and character.Parent then
		character:PivotTo(garden.spawnCF)
	end
end

return GardenService
