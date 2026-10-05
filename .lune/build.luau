--[[
	Builds the playable place files from the source in src/.

	    lune run build

	1. Loads Place1.rbxlx (so anything else you've set up in Studio is kept).
	2. Replaces the game's scripts with the contents of src/, using the same
	   layout as default.project.json (Rojo naming: *.server.luau -> Script,
	   *.client.luau -> LocalScript, *.luau -> ModuleScript, folders -> Folder).
	3. Rebuilds Workspace.Map with WorldBuilder so the map can be seen and
	   edited in Studio.
	4. Writes Place1.rbxlx and Place1.rbxl.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local SOURCE_PLACE = "Place1.rbxlx"
local OUTPUTS = {
	{ path = "Place1.rbxlx", xml = true },
	{ path = "Place1.rbxl", xml = false },
}

local Instance = roblox.Instance
local game = roblox.deserializePlace(fs.readFile(SOURCE_PLACE))
local workspace = game:GetService("Workspace")

-- Scripts -----------------------------------------------------------------------

local function scriptClassFor(fileName)
	local patterns = {
		{ "%.server%.luau$", "Script" },
		{ "%.client%.luau$", "LocalScript" },
		{ "%.luau$", "ModuleScript" },
	}
	for _, pattern in patterns do
		if string.find(fileName, pattern[1]) then
			return pattern[2], (string.gsub(fileName, pattern[1], ""))
		end
	end
	return nil
end

local scriptCount = 0

local function buildFolder(path, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in entries do
		local fullPath = path .. "/" .. entry
		if fs.isDir(fullPath) then
			buildFolder(fullPath, entry).Parent = folder
		else
			local className, instanceName = scriptClassFor(entry)
			if className then
				local script = Instance.new(className)
				script.Name = instanceName
				script.Source = fs.readFile(fullPath)
				script.Parent = folder
				scriptCount += 1
			end
		end
	end
	return folder
end

local function applyProjectNode(node, instance)
	for key, child in node do
		if string.sub(key, 1, 1) == "$" then
			continue
		end
		if child["$path"] then
			local existing = instance:FindFirstChild(key)
			if existing then
				existing:Destroy()
			end
			buildFolder(child["$path"], key).Parent = instance
		else
			local target = if instance == game then game:GetService(key) else instance:FindFirstChild(key)
			assert(target, "Couldn't find " .. key .. " in the place")
			applyProjectNode(child, target)
		end
	end
end

local project = serde.decode("json", fs.readFile("default.project.json"))
applyProjectNode(project.tree, game)

-- Map -----------------------------------------------------------------------------

-- WorldBuilder is ordinary game code; give it the Roblox globals it expects.
local environment = {
	game = game,
	workspace = workspace,
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	Font = roblox.Font,
}

local function loadModule(path)
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = environment })
	return chunk()
end

local existingMap = workspace:FindFirstChild("Map")
if existingMap then
	existingMap:Destroy()
end

local Config = loadModule("src/shared/Config.luau")
local WorldBuilder = loadModule("src/server/Services/WorldBuilder.luau")
local map = WorldBuilder.build(Config)

-- The map is small enough to send to everyone up front, which keeps rink gates simple.
workspace.StreamingEnabled = false

-- Output ----------------------------------------------------------------------------

for _, output in OUTPUTS do
	fs.writeFile(output.path, roblox.serializePlace(game, output.xml))
end

print(string.format("Built %d scripts and a map of %d instances.", scriptCount, #map:GetDescendants()))
for _, output in OUTPUTS do
	print("  wrote " .. output.path)
end
