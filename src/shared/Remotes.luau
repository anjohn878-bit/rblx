--[[
	Remotes
	Single place that defines every RemoteEvent / RemoteFunction.
	The server creates them (Remotes.Init) and clients wait for them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"StateUpdate", -- S->C: full player state snapshot
	"Notify", -- S->C: toast / banner
	"Effect", -- S->C: visual effect request (money popup, upgrade burst...)
	"OpenDiagnosis", -- S->C: diagnosis case payload
	"CloseDiagnosis", -- S->C: force close the diagnosis panel
	"CancelDiagnosis", -- C->S: player closed the panel
	"TutorialAction", -- C->S: tutorial progress
	"TeleportHome", -- C->S: teleport to my hospital
}

local FUNCTIONS = {
	"GetState", -- C->S: initial state
	"SubmitDiagnosis", -- C->S: (patientId, illnessId) -> result
	"RevealHandbook", -- C->S: (patientId) -> hints
	"UseLabTest", -- C->S: (patientId) -> removed option id
	"Purchase", -- C->S: (kind, arg) -> result
}

local FOLDER_NAME = "Remotes"

local Remotes = {}

function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init must run on the server")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

local function getFolder(): Instance
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
