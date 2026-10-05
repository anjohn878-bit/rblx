--[[
	TrickService
	Scores the tricks clients report. The client decides what it *tried* to do;
	the server checks it was actually on ice, that the trick is physically
	possible with the player's stats, and that it isn't being spammed, then
	pays out with style, rink, rebirth and combo multipliers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local SkaterService = require(script.Parent.SkaterService)

local TrickService = {}

local states = {}

local function getState(player)
	local state = states[player]
	if not state then
		state = { lastJump = -math.huge, lastSpin = -math.huge, lastTrick = -math.huge, combo = 0 }
		states[player] = state
	end
	return state
end

local function scoreJump(profile, state, payload, now)
	local rotations = tonumber(payload.rotations)
	if not rotations or rotations ~= rotations then
		return nil
	end
	rotations = math.clamp(math.floor(rotations), 0, Formulas.maxRotations(profile, workspace.Gravity))
	if rotations < 1 or now - state.lastJump < Config.Tricks.MinJumpInterval then
		return nil
	end
	state.lastJump = now

	local jumpType = "Axel"
	if type(payload.jumpType) == "string" and table.find(Config.Tricks.JumpTypes, payload.jumpType) then
		jumpType = payload.jumpType
	end
	local tier = Formulas.jumpTrick(rotations)
	return tier.Prefix .. " " .. jumpType, tier.Points
end

local function scoreSpin(state, now)
	local spin = Config.Tricks.Spin
	if now - state.lastSpin < spin.Duration * 0.9 then
		return nil
	end
	state.lastSpin = now
	return spin.Name, spin.Points
end

local function onTrickLanded(player, payload)
	if type(payload) ~= "table" then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local rinkId = SkaterService.getRecentRink(player, 2.5)
	if not rinkId then
		return
	end

	local state = getState(player)
	local now = os.clock()
	local name, basePoints
	if payload.kind == "Jump" then
		name, basePoints = scoreJump(profile, state, payload, now)
	elseif payload.kind == "Spin" then
		name, basePoints = scoreSpin(state, now)
	end
	if not name then
		return
	end

	if now - state.lastTrick <= Config.Tricks.ComboWindow then
		state.combo += 1
	else
		state.combo = 1
	end
	state.lastTrick = now

	local comboMultiplier = Formulas.comboMultiplier(state.combo)
	local amount =
		math.max(1, math.floor(basePoints * Formulas.trickMultiplier(profile, rinkId) * comboMultiplier + 0.5))
	DataService.addSnowflakes(player, amount)

	local stats = profile.Stats
	stats.TricksLanded += 1
	stats.BestCombo = math.max(stats.BestCombo, state.combo)
	if basePoints >= stats.BestTrickPoints then
		stats.BestTrick = name
		stats.BestTrickPoints = basePoints
	end
	DataService.markChanged(player)

	Remotes.TrickResult:FireClient(player, {
		name = name,
		amount = amount,
		combo = state.combo,
		comboMultiplier = comboMultiplier,
		comboWindow = Config.Tricks.ComboWindow,
	})
end

function TrickService.init()
	Remotes.TrickLanded.OnServerEvent:Connect(onTrickLanded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return TrickService
