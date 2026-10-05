--[[
	Puts the game scripts from src/ into the Roblox place files.

	Run from the repository root with Lune (https://lune-org.github.io/docs):
		lune run tools/build-place.luau

	It updates Place1.rbxl and Place1.rbxlx in place, replacing any older copy of
	the Build a Dress Store scripts and leaving everything else in the place alone.
	(Rojo users can use default.project.json instead.)
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance

local PLACES = { "Place1.rbxl", "Place1.rbxlx" }

local function classFor(fileName: string): string
	if string.find(fileName, "%.server%.lua$") then
		return "Script"
	elseif string.find(fileName, "%.client%.lua$") then
		return "LocalScript"
	end
	return "ModuleScript"
end

local function scriptFrom(path: string, name: string): any
	local fileName = string.match(path, "[^/]+$") :: string
	local script = Instance.new(classFor(fileName))
	script.Name = name
	script.Source = fs.readFile(path)
	return script
end

-- Turns a folder into instances the same way Rojo does:
-- init.server.lua / init.client.lua / init.lua become the folder's own script.
local function fromDirectory(path: string, name: string): any
	local entries = fs.readDir(path)
	table.sort(entries)

	local node
	for _, initName in { "init.server.lua", "init.client.lua", "init.lua" } do
		if fs.isFile(path .. "/" .. initName) then
			node = scriptFrom(path .. "/" .. initName, name)
		end
	end
	if not node then
		node = Instance.new("Folder")
		node.Name = name
	end

	for _, entry in entries do
		local full = path .. "/" .. entry
		if string.sub(entry, 1, 5) == "init." then
			continue
		elseif fs.isDir(full) then
			fromDirectory(full, entry).Parent = node
		elseif string.find(entry, "%.lua$") then
			local childName = string.gsub(entry, "%..*$", "")
			scriptFrom(full, childName).Parent = node
		end
	end
	return node
end

local function replaceChild(parent: any, child: any)
	local old = parent:FindFirstChild(child.Name)
	if old then
		old:Destroy()
	end
	child.Parent = parent
end

for _, placeFile in PLACES do
	if not fs.isFile(placeFile) then
		print("Skipping " .. placeFile .. " (not found)")
		continue
	end
	local isXml = string.find(placeFile, "%.rbxlx$") ~= nil
	local game = roblox.deserializePlace(fs.readFile(placeFile))

	replaceChild(game:GetService("ReplicatedStorage"), fromDirectory("src/ReplicatedStorage/DressStore", "DressStore"))
	replaceChild(
		game:GetService("ServerScriptService"),
		fromDirectory("src/ServerScriptService/DressStoreServer", "DressStoreServer")
	)

	local starterPlayer = game:GetService("StarterPlayer")
	local playerScripts = starterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
	if not playerScripts then
		playerScripts = Instance.new("StarterPlayerScripts")
		playerScripts.Parent = starterPlayer
	end
	replaceChild(
		playerScripts,
		scriptFrom("src/StarterPlayer/StarterPlayerScripts/DressStoreClient.client.lua", "DressStoreClient")
	)

	fs.writeFile(placeFile, roblox.serializePlace(game, isXml))
	print("Updated " .. placeFile)
end
