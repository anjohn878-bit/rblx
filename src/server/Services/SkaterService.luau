--[[
	SkaterService
	Server side of skating:
	  * sets up each character (jump height, skates, no player-player collisions)
	  * relays each client's "I'm skating" state so everyone sees trails and poses
	  * pays snowflakes for distance skated, measured on the server so it can't be faked
	  * keeps players out of rinks they haven't unlocked
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local SkateGear = require(script.Parent.SkateGear)

local SkaterService = {}

local COLLISION_GROUP = "Skaters"

local states = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function refreshRayFilter()
	rayParams.FilterDescendantsInstances = CollectionService:GetTagged("RinkFloor")
end

local function getState(player)
	local state = states[player]
	if not state then
		state = {
			lastPosition = nil,
			lastTime = 0,
			lastRinkId = nil,
			lastIceTime = -math.huge,
			recentRinkId = nil,
			earnings = 0,
			lastLockWarning = 0,
			skateStateChanges = 0,
			skateStateWindow = 0,
		}
		states[player] = state
	end
	return state
end

local function rinkModel(rinkId)
	local map = workspace:FindFirstChild("Map")
	local rinks = map and map:FindFirstChild("Rinks")
	return rinks and rinks:FindFirstChild(rinkId)
end

-- Just outside the rink's entrance, facing the lobby.
function SkaterService.getRinkExit(rinkId)
	local model = rinkModel(rinkId)
	local ice = model and model:FindFirstChild("Ice")
	if not ice then
		return nil
	end
	return ice.CFrame * CFrame.new(0, 4, ice.Size.Z / 2 + 16)
end

-- The rink this player was skating on within the last `window` seconds, if any.
function SkaterService.getRecentRink(player, window)
	local state = states[player]
	if state and state.recentRinkId and os.clock() - state.lastIceTime <= window then
		return state.recentRinkId
	end
	return nil
end

local function setCollisionGroup(character)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = COLLISION_GROUP
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = COLLISION_GROUP
		end
	end)
end

local function applyCharacterStats(player, character)
	local profile = DataService.get(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not profile or not humanoid then
		return
	end
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Formulas.jumpHeight(profile)

	local gear = character:FindFirstChild("SkateGear")
	local tier = profile.SkateTier
	if not gear or gear:GetAttribute("Tier") ~= tier then
		SkateGear.equip(character, Formulas.getSkate(tier))
		local newGear = character:FindFirstChild("SkateGear")
		if newGear then
			newGear:SetAttribute("Tier", tier)
		end
	end
end

local function onCharacterAdded(player, character)
	local state = getState(player)
	state.lastPosition = nil
	state.lastRinkId = nil

	character:SetAttribute("Skating", false)
	setCollisionGroup(character)

	character:WaitForChild("Humanoid", 10)
	if DataService.waitFor(player, 30) and character.Parent then
		applyCharacterStats(player, character)
	end
end

local function onPlayerAdded(player)
	getState(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	-- Body scaling arrives with the avatar, so refit the skates once it has loaded.
	player.CharacterAppearanceLoaded:Connect(function(character)
		local gear = character:FindFirstChild("SkateGear")
		if gear then
			gear:SetAttribute("Tier", nil)
		end
		applyCharacterStats(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onSkateState(player, isSkating)
	if type(isSkating) ~= "boolean" then
		return
	end
	local state = getState(player)
	-- Ignore clients that flip this absurdly often.
	local now = os.clock()
	if now - state.skateStateWindow > 1 then
		state.skateStateWindow = now
		state.skateStateChanges = 0
	end
	state.skateStateChanges += 1
	if state.skateStateChanges > 12 then
		return
	end

	local character = player.Character
	if character then
		character:SetAttribute("Skating", isSkating)
		SkateGear.setTrails(character, isSkating)
	end
end

local function kickOutOfRink(player, character, rinkId)
	local exit = SkaterService.getRinkExit(rinkId)
	if exit then
		character:PivotTo(exit)
	end
	local state = getState(player)
	if os.clock() - state.lastLockWarning > 2 then
		state.lastLockWarning = os.clock()
		local rink = Formulas.getRink(rinkId)
		Remotes.Notify:FireClient(
			player,
			"Unlock " .. (rink and rink.Name or "this rink") .. " at its gate first!",
			"error"
		)
	end
end

local function step()
	local now = os.clock()
	for player, state in states do
		local character = player.Character
		local profile = DataService.get(player)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not profile or not humanoid or not root or humanoid.Health <= 0 then
			state.lastPosition = nil
			continue
		end

		local position = root.Position
		local reach = humanoid.HipHeight + root.Size.Y / 2 + 2.5
		local result = workspace:Raycast(position, Vector3.new(0, -reach, 0), rayParams)
		local rinkId = result and result.Instance:GetAttribute("RinkId")

		if rinkId and not Formulas.isRinkUnlocked(profile, rinkId) then
			kickOutOfRink(player, character, rinkId)
			state.lastPosition = nil
			state.lastRinkId = nil
			continue
		end

		if rinkId then
			state.lastIceTime = now
			state.recentRinkId = rinkId
		end

		-- Pay for distance covered on the same rink since the last sample.
		if rinkId and state.lastPosition and state.lastRinkId == rinkId then
			local delta = position - state.lastPosition
			local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
			local elapsed = now - state.lastTime
			local allowed = Formulas.maxSpeed(profile) * elapsed * 1.4 + 2
			if distance <= allowed then
				state.earnings += distance * Config.Economy.SnowflakesPerStud * Formulas.earnMultiplier(profile, rinkId)
				local whole = math.floor(state.earnings)
				if whole >= 1 then
					state.earnings -= whole
					DataService.addSnowflakes(player, whole)
				end
			end
		end

		state.lastPosition = position
		state.lastTime = now
		state.lastRinkId = rinkId
	end
end

function SkaterService.init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

	refreshRayFilter()
	CollectionService:GetInstanceAddedSignal("RinkFloor"):Connect(refreshRayFilter)
	CollectionService:GetInstanceRemovedSignal("RinkFloor"):Connect(refreshRayFilter)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	Remotes.SkateState.OnServerEvent:Connect(onSkateState)

	-- Upgrades and new skates take effect immediately.
	DataService.ProfileChanged:Connect(function(player)
		if player.Character then
			applyCharacterStats(player, player.Character)
		end
	end)
	DataService.ProfileLoaded:Connect(function(player)
		if player.Character then
			applyCharacterStats(player, player.Character)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Server.SkateTickInterval)
			step()
		end
	end)
end

return SkaterService
