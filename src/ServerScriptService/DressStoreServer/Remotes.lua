-- RemoteEvents used to talk to the players' screens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("DressStore")

local folder = shared:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = shared
end

local function remote(name: string): RemoteEvent
	local existing = (folder :: Folder):FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = folder
	return event
end

local Remotes = {
	Notify = remote("Notify"), -- server -> one player: (text, kind)
	Popup = remote("Popup"), -- server -> everyone: (position, text, kind, ownerUserId)
	Rebirth = remote("Rebirth"), -- player -> server
	GoHome = remote("GoHome"), -- player -> server
}

-- kind: "info" | "success" | "error" | "money"
function Remotes.notify(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

function Remotes.popup(position: Vector3, text: string, kind: string?, ownerUserId: number?)
	Remotes.Popup:FireAllClients(position, text, kind or "money", ownerUserId or 0)
end

return Remotes
