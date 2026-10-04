--[[
	Actors
	Treats real players and bots the same way for ball/match code.
	An actor is either a Player or a bot table: { IsBot = true, Name, Model, Attributes }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)

local ProgressionService = require(script.Parent.ProgressionService)

local Actors = {}

function Actors.IsBot(actor): boolean
	return type(actor) == "table" and actor.IsBot == true
end

function Actors.GetCharacter(actor): Model?
	if Actors.IsBot(actor) then
		return actor.Model
	end
	return (actor :: Player).Character
end

function Actors.GetRoot(actor): BasePart?
	local character = Actors.GetCharacter(actor)
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Actors.GetHumanoid(actor): Humanoid?
	local character = Actors.GetCharacter(actor)
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Actors.IsAlive(actor): boolean
	local humanoid = Actors.GetHumanoid(actor)
	return humanoid ~= nil and humanoid.Health > 0 and Actors.GetRoot(actor) ~= nil
end

function Actors.GetName(actor): string
	if Actors.IsBot(actor) then
		return actor.Name
	end
	return (actor :: Player).DisplayName
end

-- Unique id used in replicated attributes. Players use their UserId, bots a negative id.
function Actors.GetId(actor): number
	if Actors.IsBot(actor) then
		return actor.Id
	end
	return (actor :: Player).UserId
end

-- Raw attribute value (0..99)
function Actors.GetAttribute(actor, name: string): number
	if Actors.IsBot(actor) then
		return actor.Attributes[name] or Config.Attributes.Start
	end
	return ProgressionService.GetAttribute(actor, name)
end

-- Attribute as 0..1
function Actors.Alpha(actor, name: string): number
	return Progression.AttributeAlpha(Actors.GetAttribute(actor, name))
end

return Actors
