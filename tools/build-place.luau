--!nocheck
-- Copies the scripts in src/ into Place1.rbxlx and Place1.rbxl.
--
-- Usage (needs Lune, https://lune-org.github.io/docs):
--   lune run tools/build-place
--
-- File naming follows Rojo conventions:
--   *.server.lua -> Script, *.client.lua -> LocalScript, *.lua -> ModuleScript

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local SOURCE_PLACE = "Place1.rbxlx"
local OUTPUTS = {
	{ Path = "Place1.rbxlx", Xml = true },
	{ Path = "Place1.rbxl", Xml = false },
}

local MAPPINGS = {
	{ Source = "src/shared", Parent = { "ReplicatedStorage" }, Name = "Shared" },
	{ Source = "src/server", Parent = { "ServerScriptService" }, Name = "BirdGardenServer" },
	{ Source = "src/client", Parent = { "StarterPlayer", "StarterPlayerScripts" }, Name = "BirdGardenClient" },
}

local SCRIPT_TYPES = {
	{ Suffix = ".server.lua", ClassName = "Script" },
	{ Suffix = ".client.lua", ClassName = "LocalScript" },
	{ Suffix = ".lua", ClassName = "ModuleScript" },
}

local function scriptFromFile(path, fileName)
	for _, scriptType in SCRIPT_TYPES do
		if fileName:sub(-#scriptType.Suffix) == scriptType.Suffix then
			local instance = roblox.Instance.new(scriptType.ClassName)
			instance.Name = fileName:sub(1, -#scriptType.Suffix - 1)
			instance.Source = fs.readFile(path)
			return instance
		end
	end
	return nil
end

local function folderFromDirectory(path, name)
	local folder = roblox.Instance.new("Folder")
	folder.Name = name
	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in entries do
		local entryPath = path .. "/" .. entry
		local child
		if fs.isDir(entryPath) then
			child = folderFromDirectory(entryPath, entry)
		else
			child = scriptFromFile(entryPath, entry)
		end
		if child then
			child.Parent = folder
		end
	end
	return folder
end

local game = roblox.deserializePlace(fs.readFile(SOURCE_PLACE))

for _, mapping in MAPPINGS do
	local parent = game:GetService(mapping.Parent[1])
	for i = 2, #mapping.Parent do
		parent = parent:FindFirstChild(mapping.Parent[i])
		assert(parent, "Missing " .. table.concat(mapping.Parent, "."))
	end
	local existing = parent:FindFirstChild(mapping.Name)
	if existing then
		existing:Destroy()
	end
	folderFromDirectory(mapping.Source, mapping.Name).Parent = parent
	print("Synced " .. mapping.Source .. " -> " .. table.concat(mapping.Parent, ".") .. "." .. mapping.Name)
end

for _, output in OUTPUTS do
	fs.writeFile(output.Path, roblox.serializePlace(game, output.Xml))
	print("Wrote " .. output.Path)
end
