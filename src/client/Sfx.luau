--!strict
-- Plays a sound recipe from Config/Sounds: every layer, with its delay and a random pitch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))

local Sfx = {}
local rng = Random.new()

function Sfx.play(recipeName: string, at: BasePart | Attachment | nil)
	local recipe = Sounds.Recipes[recipeName]
	if not recipe then
		warn(`[Sfx] unknown recipe {recipeName}`)
		return
	end
	for _, layer in recipe do
		local id = Sounds.Library[layer.sound]
		if not id then
			warn(`[Sfx] recipe {recipeName}: sound {layer.sound} not in library`)
			continue
		end
		task.delay(layer.delay or 0, function()
			local s = Instance.new("Sound")
			s.SoundId = id
			s.Volume = layer.volume or 1
			local pitch = layer.pitch or { 0.95, 1.05 }
			s.PlaybackSpeed = rng:NextNumber(pitch[1], pitch[2])
			s.Parent = at or SoundService
			s:Play()
			s.Ended:Once(function()
				s:Destroy()
			end)
		end)
	end
end

return Sfx
