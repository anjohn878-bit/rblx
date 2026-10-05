--[[
	EconomyService
	The only place money changes. Also owns leaderstats and pushes a
	throttled state snapshot to each client whenever their data changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DoctorLevels = require(Shared:WaitForChild("Config"):WaitForChild("DoctorLevels"))
local Economy = require(Shared:WaitForChild("Economy"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local EconomyService = {}

local services: any = nil
local dirty: { [Player]: boolean } = {}
local stateEvent: RemoteEvent
local notifyEvent: RemoteEvent
local effectEvent: RemoteEvent

local function getData(player: Player): any
	return services.DataService.Get(player)
end

function EconomyService.Init(allServices: any)
	services = allServices
	stateEvent = Remotes.Event("StateUpdate")
	notifyEvent = Remotes.Event("Notify")
	effectEvent = Remotes.Event("Effect")

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.15 then
			return
		end
		accumulator = 0
		for player in dirty do
			dirty[player] = nil
			if player.Parent then
				EconomyService.SendState(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

function EconomyService.SetupPlayer(player: Player)
	local data = getData(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = math.floor(data.Money)
	cash.Parent = leaderstats

	local hospital = Instance.new("IntValue")
	hospital.Name = "Hospital"
	hospital.Value = data.HospitalLevel
	hospital.Parent = leaderstats

	local treated = Instance.new("IntValue")
	treated.Name = "Treated"
	treated.Value = data.PatientsTreated
	treated.Parent = leaderstats

	leaderstats.Parent = player
end

function EconomyService.UpdateLeaderstats(player: Player)
	local data = getData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not data or not leaderstats then
		return
	end
	local cash = leaderstats:FindFirstChild("Cash") :: IntValue?
	local hospital = leaderstats:FindFirstChild("Hospital") :: IntValue?
	local treated = leaderstats:FindFirstChild("Treated") :: IntValue?
	if cash then
		cash.Value = math.floor(data.Money)
	end
	if hospital then
		hospital.Value = data.HospitalLevel
	end
	if treated then
		treated.Value = data.PatientsTreated
	end
end

function EconomyService.MarkDirty(player: Player)
	dirty[player] = true
end

function EconomyService.AddMoney(player: Player, amount: number)
	local data = getData(player)
	if not data or amount <= 0 or amount ~= amount then
		return
	end
	amount = math.floor(amount)
	data.Money += amount
	data.LifetimeEarned += amount
	EconomyService.MarkDirty(player)
end

-- Atomically checks and deducts. Never yields.
function EconomyService.TrySpend(player: Player, amount: number): boolean
	local data = getData(player)
	if not data or amount < 0 or amount ~= amount then
		return false
	end
	if data.Money < amount then
		return false
	end
	data.Money -= amount
	EconomyService.MarkDirty(player)
	return true
end

function EconomyService.Snapshot(player: Player): any
	local data = getData(player)
	if not data then
		return nil
	end
	local level, xpInto, xpNeeded = DoctorLevels.FromTotalXP(data.DoctorXP)
	local plot = services.PlotService.GetPlot(player)
	local profile = services.DataService.GetProfile(player)
	return {
		Money = math.floor(data.Money),
		LifetimeEarned = math.floor(data.LifetimeEarned),
		HospitalLevel = data.HospitalLevel,
		Rooms = data.Rooms,
		Doctors = data.Doctors,
		Improvements = data.Improvements,
		DoctorLevel = level,
		DoctorXP = xpInto,
		DoctorXPNeeded = xpNeeded,
		PatientsTreated = data.PatientsTreated,
		ManualTreated = data.ManualTreated,
		AutoTreated = data.AutoTreated,
		BestCombo = data.BestCombo,
		Combo = services.DiagnosisService.GetCombo(player),
		RareTreated = data.RareTreated,
		TutorialDone = data.TutorialDone,
		HospitalValue = Economy.HospitalValue(data),
		PlotIndex = plot and plot.Index or 0,
		PlayTime = data.PlayTime,
		SavingEnabled = profile ~= nil and profile.CanSave,
	}
end

function EconomyService.SendState(player: Player)
	local snapshot = EconomyService.Snapshot(player)
	if snapshot then
		EconomyService.UpdateLeaderstats(player)
		stateEvent:FireClient(player, snapshot)
	end
end

export type Notice = {
	Style: string?, -- "Info" | "Success" | "Error" | "Rare" | "Big"
	Title: string?,
	Text: string?,
	Color: Color3?,
}

function EconomyService.Notify(player: Player, notice: Notice)
	notifyEvent:FireClient(player, notice)
end

function EconomyService.Effect(player: Player, effect: { [string]: any })
	effectEvent:FireClient(player, effect)
end

return EconomyService
