--[[
	GameConfig
	Global tuning values shared by server and client.
	Anything economy-related is *read* by the client for display only;
	the server is always the authority.
]]

local GameConfig = {
	GameName = "Work as a Doctor",

	-- Data
	DataStoreName = "WorkAsADoctor_PlayerData_v1",
	AutosaveInterval = 60,
	SessionLockTimeout = 150, -- seconds before another server may take over a stale session

	-- Plots
	PlotCount = 6,
	PlotFrontRadius = 150, -- distance from map centre to the front edge of each plot
	PlotWidth = 140,
	PlotDepth = 170,

	-- Money
	StartingMoney = 0,
	ManualCareBonus = 1.5, -- personally diagnosing pays more than Auto Doctors
	ExpertBonus = 1.25, -- diagnosing without opening the handbook
	ComboStep = 0.1, -- +10% per correct diagnosis in a row
	ComboMax = 10, -- capped at +100%
	WrongAnswerMultipliers = { 1, 0.75, 0.5 }, -- reward after 0 / 1 / 2+ mistakes
	PharmacyBonus = 0.25, -- extra income per patient when the Pharmacy is unlocked
	EmergencyMultiplier = 2,
	ChildMultiplier = 1.2,
	VIPMultiplier = 5,

	-- Patient kinds (chances only apply once the matching room is unlocked)
	EmergencyChance = 0.12,
	ChildChance = 0.2,
	VIPChance = 0.05,

	-- NPCs
	PatientWalkSpeed = 12,
	EmergencyWalkSpeed = 18,
	DoctorWalkSpeed = 14,
	UsePathfinding = true, -- falls back to direct walking when line of sight is clear
	CheckInTime = 1.2,

	-- Diagnosis
	DiagnoseDistance = 22, -- max studs between player and patient (server check)
	DiagnosisSessionTimeout = 120,

	-- Leaderboards
	LeaderboardUpdateInterval = 120,
	LeaderboardSize = 10,
}

return GameConfig
