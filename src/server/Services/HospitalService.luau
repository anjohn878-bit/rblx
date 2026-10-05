--[[
	HospitalService
	Creates / destroys the HospitalSim for each player and ticks every
	simulation from a single Heartbeat connection.
]]

local RunService = game:GetService("RunService")

local HospitalSim = require(script.Parent.Parent.Classes.HospitalSim)

local HospitalService = {}

local services: any = nil
local sims: { [Player]: any } = {}

function HospitalService.Init(allServices: any)
	services = allServices
	RunService.Heartbeat:Connect(function(dt)
		for _, sim in sims do
			local ok, err = pcall(sim.Update, sim, dt)
			if not ok then
				warn("[HospitalService] Update error: " .. tostring(err))
			end
		end
	end)
end

function HospitalService.Start(player: Player, plot: any, data: any): any
	local sim = HospitalSim.new(services, plot, player, data)
	sims[player] = sim
	return sim
end

function HospitalService.Stop(player: Player)
	local sim = sims[player]
	if sim then
		sims[player] = nil
		sim:Destroy()
	end
end

function HospitalService.Get(player: Player): any
	return sims[player]
end

-- Rebuilds the building after an upgrade / room purchase.
function HospitalService.Rebuild(player: Player)
	local sim = sims[player]
	if sim then
		sim:Rebuild(false)
	end
end

return HospitalService
