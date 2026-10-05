--[[
	DiagnosisService
	Handles the player personally diagnosing patients.

	Flow: ProximityPrompt -> Begin() builds a case on the server and opens the
	client panel -> client sends SubmitDiagnosis(patientId, illnessId) -> the
	server checks the answer and pays. The client never decides correctness
	or rewards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local DoctorLevels = require(Config:WaitForChild("DoctorLevels"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Illnesses = require(script.Parent.Parent.Data.Illnesses)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local DiagnosisService = {}

type Session = {
	Patient: any,
	Sim: any,
	StartedAt: number,
	Difficulty: DoctorLevels.Difficulty,
	DoctorLevel: number,
}

local services: any = nil
local sessions: { [Player]: Session } = {}
local combos: { [Player]: number } = {}
local rng = Random.new()
local limiter = RateLimiter.new(6, 10)
local promptLimiter = RateLimiter.new(2, 4)

local openEvent: RemoteEvent
local closeEvent: RemoteEvent

local TUTORIAL_DIFFICULTY: DoctorLevels.Difficulty = { MinLevel = 1, Symptoms = 2, Choices = 3, Bonus = 1, Label = "Trainee" }

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function closeEnough(player: Player, patient: any, maxDistance: number): boolean
	local root = characterRoot(player)
	if not root then
		return false
	end
	return (root.Position - patient:GetPosition()).Magnitude <= maxDistance
end

local function inTutorial(data: any): boolean
	return not data.TutorialDone and data.PatientsTreated == 0
end

function DiagnosisService.GetCombo(player: Player): number
	return combos[player] or 0
end

function DiagnosisService.EndSession(player: Player, notifyClient: boolean?, reason: string?)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	local patient = session.Patient
	if patient:IsAlive() and patient.LockedBy == player then
		session.Sim:LockPatient(patient, nil)
	end
	if notifyClient then
		closeEvent:FireClient(player, reason or "closed")
	end
end

function DiagnosisService.OnPatientRemoved(patient: any)
	for player, session in sessions do
		if session.Patient == patient then
			sessions[player] = nil
			closeEvent:FireClient(player, "gone")
		end
	end
end

local function buildCase(patient: any, data: any, difficulty: DoctorLevels.Difficulty, level: number)
	local pool = Illnesses.GetRegularPool(data.Rooms)
	if patient.Illness.Category == "Rare" then
		for _, illness in Illnesses.ByCategory.Rare do
			table.insert(pool, illness)
		end
	elseif patient.Illness.Category == "Emergency" and not data.Rooms.EmergencyRoom then
		for _, illness in Illnesses.ByCategory.Emergency do
			table.insert(pool, illness)
		end
	end
	local shown, options = Illnesses.BuildCase(patient.Illness, pool, difficulty.Symptoms, difficulty.Choices, rng)
	patient.Case = {
		Level = level,
		Shown = shown,
		Options = options,
		Removed = {} :: { [string]: boolean },
		Wrong = {} :: { [string]: boolean },
		LabUsed = false,
	}
	patient.Misses = patient.Misses or 0
	patient.UsedHandbook = patient.UsedHandbook or false
end

local function optionList(patient: any)
	local list = {}
	for _, illness in patient.Case.Options do
		table.insert(list, {
			Id = illness.Id,
			Name = illness.Name,
			Emoji = illness.Emoji,
			Removed = patient.Case.Removed[illness.Id] == true,
			Wrong = patient.Case.Wrong[illness.Id] == true,
		})
	end
	return list
end

function DiagnosisService.Begin(player: Player, sim: any, patient: any)
	if not promptLimiter:Check(player) then
		return
	end
	if sim.Player ~= player then
		services.EconomyService.Notify(player, { Style = "Error", Text = "That's another doctor's patient! Head to your own hospital 🏥" })
		return
	end
	if not patient:IsAlive() or patient.State ~= "InExam" then
		return
	end
	if patient.LockedBy and patient.LockedBy ~= player then
		return
	end
	if not closeEnough(player, patient, GameConfig.DiagnoseDistance) then
		return
	end

	local existing = sessions[player]
	if existing and existing.Patient ~= patient then
		DiagnosisService.EndSession(player, false)
	end

	local data = services.DataService.Get(player)
	if not data then
		return
	end
	local level = DoctorLevels.FromTotalXP(data.DoctorXP)
	local difficulty = if inTutorial(data) then TUTORIAL_DIFFICULTY else DoctorLevels.GetDifficulty(level)
	if not patient.Case then
		buildCase(patient, data, difficulty, level)
	end

	sessions[player] = {
		Patient = patient,
		Sim = sim,
		StartedAt = os.clock(),
		Difficulty = difficulty,
		DoctorLevel = level,
	}
	sim:LockPatient(patient, player)

	local estimate, pharmacy = sim:ComputeReward(patient, {
		Misses = patient.Misses,
		UsedHandbook = patient.UsedHandbook,
		Combo = (combos[player] or 0) + 1,
		DoctorLevel = level,
		DifficultyBonus = difficulty.Bonus,
	})

	openEvent:FireClient(player, {
		PatientId = patient.Id,
		Name = patient.Name,
		Rarity = patient.Rarity.Id,
		Kind = patient.Kind,
		Symptoms = patient.Case.Shown,
		Options = optionList(patient),
		HasLab = data.Rooms.Laboratory == true,
		LabUsed = patient.Case.LabUsed,
		Estimate = estimate + pharmacy,
		Misses = patient.Misses,
		UsedHandbook = patient.UsedHandbook,
		Tutorial = inTutorial(data),
		DifficultyLabel = difficulty.Label,
		DoctorLevel = level,
		Combo = combos[player] or 0,
	})
end

local function validSession(player: Player, patientId: any): Session?
	if typeof(patientId) ~= "number" then
		return nil
	end
	local session = sessions[player]
	if not session or session.Patient.Id ~= patientId then
		return nil
	end
	if not session.Patient:IsAlive() or session.Patient.State ~= "InExam" then
		DiagnosisService.EndSession(player, true, "gone")
		return nil
	end
	return session
end

local function submit(player: Player, patientId: any, illnessId: any)
	if not limiter:Check(player) then
		return { Ok = false, Error = "Slow down!" }
	end
	if typeof(illnessId) ~= "string" then
		return { Ok = false, Error = "Bad request" }
	end
	local session = validSession(player, patientId)
	if not session then
		return { Ok = false, Error = "This patient is no longer here." }
	end
	local patient = session.Patient
	if not closeEnough(player, patient, GameConfig.DiagnoseDistance * 2) then
		DiagnosisService.EndSession(player, true, "far")
		return { Ok = false, Error = "You walked away from the patient." }
	end

	local isOption = false
	for _, illness in patient.Case.Options do
		if illness.Id == illnessId then
			isOption = true
			break
		end
	end
	if not isOption or patient.Case.Removed[illnessId] then
		return { Ok = false, Error = "Not a valid choice." }
	end

	local data = services.DataService.Get(player)
	if illnessId ~= patient.Illness.Id then
		patient.Misses += 1
		patient.Case.Wrong[illnessId] = true
		combos[player] = 0
		services.EconomyService.MarkDirty(player)
		return {
			Ok = true,
			Correct = false,
			Misses = patient.Misses,
			Message = "Not quite! Look at the symptoms again 🔍",
		}
	end

	-- Correct!
	local combo = (combos[player] or 0) + 1
	combos[player] = combo
	data.BestCombo = math.max(data.BestCombo, combo)
	local difficulty = session.Difficulty
	local misses = patient.Misses
	local usedHandbook = patient.UsedHandbook
	sessions[player] = nil

	local reward, pharmacy = session.Sim:CompleteTreatment(patient, {
		Misses = misses,
		UsedHandbook = usedHandbook,
		Combo = combo,
		DoctorLevel = session.DoctorLevel,
		DifficultyBonus = difficulty.Bonus,
	})

	local oldLevel = DoctorLevels.FromTotalXP(data.DoctorXP)
	local xp = math.floor(DoctorLevels.BaseXP * patient.Rarity.XP * ((difficulty.Choices - 1) / 2) * (if misses == 0 then 1 else 0.5) + 0.5)
	data.DoctorXP += xp
	local newLevel = DoctorLevels.FromTotalXP(data.DoctorXP)
	if newLevel > oldLevel then
		local newDifficulty = DoctorLevels.GetDifficulty(newLevel)
		services.EconomyService.Effect(player, { Type = "DoctorLevelUp", Level = newLevel, Label = newDifficulty.Label })
		services.EconomyService.Notify(player, {
			Style = "Big",
			Title = "🎉 DOCTOR LEVEL " .. newLevel .. "!",
			Text = string.format("You're now a %s: +%d%% personal income. Harder cases pay more!", newDifficulty.Label, math.floor(DoctorLevels.RewardBonusPerLevel * (newLevel - 1) * 100 + 0.5)),
			Color = Color3.fromRGB(255, 200, 60),
		})
	end
	services.EconomyService.MarkDirty(player)

	return {
		Ok = true,
		Correct = true,
		Reward = reward,
		Pharmacy = pharmacy,
		XP = xp,
		Combo = combo,
		Expert = not usedHandbook and misses == 0,
		LevelUp = if newLevel > oldLevel then newLevel else nil,
	}
end

local function revealHandbook(player: Player, patientId: any)
	if not limiter:Check(player) then
		return nil
	end
	local session = validSession(player, patientId)
	if not session then
		return nil
	end
	local patient = session.Patient
	patient.UsedHandbook = true
	local hints = {}
	for _, illness in patient.Case.Options do
		hints[illness.Id] = illness.Symptoms
	end
	return hints
end

local function useLabTest(player: Player, patientId: any)
	if not limiter:Check(player) then
		return nil
	end
	local session = validSession(player, patientId)
	if not session then
		return nil
	end
	local data = services.DataService.Get(player)
	local patient = session.Patient
	if not data.Rooms.Laboratory or patient.Case.LabUsed then
		return nil
	end
	local candidates = {}
	for _, illness in patient.Case.Options do
		if illness.Id ~= patient.Illness.Id and not patient.Case.Removed[illness.Id] and not patient.Case.Wrong[illness.Id] then
			table.insert(candidates, illness.Id)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local removed = candidates[rng:NextInteger(1, #candidates)]
	patient.Case.Removed[removed] = true
	patient.Case.LabUsed = true
	return removed
end

function DiagnosisService.Init(allServices: any)
	services = allServices
	openEvent = Remotes.Event("OpenDiagnosis")
	closeEvent = Remotes.Event("CloseDiagnosis")

	Remotes.Function("SubmitDiagnosis").OnServerInvoke = submit
	Remotes.Function("RevealHandbook").OnServerInvoke = revealHandbook
	Remotes.Function("UseLabTest").OnServerInvoke = useLabTest
	Remotes.Event("CancelDiagnosis").OnServerEvent:Connect(function(player: Player, patientId: any)
		local session = sessions[player]
		if session and (patientId == nil or session.Patient.Id == patientId) then
			DiagnosisService.EndSession(player, false)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		DiagnosisService.EndSession(player, false)
		combos[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for player, session in sessions do
				if now - session.StartedAt > GameConfig.DiagnosisSessionTimeout then
					DiagnosisService.EndSession(player, true, "timeout")
				end
			end
		end
	end)
end

return DiagnosisService
