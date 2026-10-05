--[[
	SoundController
	Plays UI / feedback sounds locally.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))

local SoundController = {}

local sounds: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

function SoundController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "DoctorSounds"
	folder.Parent = SoundService
	for name, def in SoundDefs do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = def.Id
		sound.Volume = def.Volume
		sound.PlaybackSpeed = def.Speed
		sound.Parent = folder
		sounds[name] = sound
	end
end

function SoundController.Play(name: string, pitch: number?)
	local sound = sounds[name]
	if not sound then
		return
	end
	-- Avoid stacking the exact same sound many times in one frame.
	local now = os.clock()
	if lastPlayed[name] and now - lastPlayed[name] < 0.05 then
		return
	end
	lastPlayed[name] = now
	if pitch then
		local clone = sound:Clone()
		clone.PlaybackSpeed = sound.PlaybackSpeed * pitch
		clone.Parent = sound.Parent
		clone:Play()
		clone.Ended:Once(function()
			clone:Destroy()
		end)
		task.delay(5, function()
			if clone.Parent then
				clone:Destroy()
			end
		end)
	else
		SoundService:PlayLocalSound(sound)
	end
end

return SoundController
