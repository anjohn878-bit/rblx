--[[
	RinkGates
	Locked rinks are sealed by invisible walls and a shimmering gate. Once you
	own a rink this opens it up for you only: the walls stop colliding and the
	gate disappears on your screen. The server still checks rink access.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)

local ClientData = require(script.Parent.ClientData)

local RinkGates = {}

local function setLockOpen(lock, open)
	for _, descendant in lock:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Name == "LockWall" then
				descendant.CanCollide = not open
			elseif descendant.Name == "Gate" then
				descendant.Transparency = if open then 1 else 0
			end
		elseif descendant:IsA("ProximityPrompt") or descendant:IsA("SurfaceGui") then
			descendant.Enabled = not open
		end
	end
end

local function refresh(profile)
	local map = workspace:FindFirstChild("Map")
	local rinks = map and map:FindFirstChild("Rinks")
	if not rinks then
		return
	end
	for _, model in rinks:GetChildren() do
		local lock = model:FindFirstChild("Lock")
		local rinkId = model:GetAttribute("RinkId")
		if lock and rinkId then
			setLockOpen(lock, Formulas.isRinkUnlocked(profile, rinkId))
		end
	end
end

function RinkGates.init()
	workspace:WaitForChild("Map"):WaitForChild("Rinks")
	ClientData.observe(refresh)
end

return RinkGates
