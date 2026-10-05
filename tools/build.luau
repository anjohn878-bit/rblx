--[[
	Builds the playable place files from the sources:   lune run tools/build

	  1. Loads the existing place (Place1.rbxlx), so Lighting/Sky/etc. from your Studio session survive.
	  2. Removes the default Baseplate + SpawnLocation (the town has its own ground and spawn).
	  3. Injects src/ as Script / LocalScript / ModuleScript instances (same layout as default.project.json).
	  4. Runs the real WorldBuilder to bake the town into Workspace.Town, so it shows up in Studio's edit view.
	  5. Writes Place1.rbxl (binary) and Place1.rbxlx (XML), then reads both back to check them.

	Safe to run repeatedly: anything it generated on a previous run is replaced.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Env = require("./env")

local ROOT = "."
local PLACE_XML = ROOT .. "/Place1.rbxlx"
local PLACE_BINARY = ROOT .. "/Place1.rbxl"

local function readPlace(path: string)
	return roblox.deserializePlace(fs.readFile(path))
end

local function removeChildren(parent, names: { string })
	for _, name in names do
		local child = parent:FindFirstChild(name)
		while child do
			child:Destroy()
			child = parent:FindFirstChild(name)
		end
	end
end

-- Lune writes script source as <string name="Source">, but Studio has always used <ProtectedString>,
-- and an XML loader that expects ProtectedString could drop sources with the wrong tag. Rewrite them.
local function useProtectedStrings(xml: string): string
	local out = {}
	local position = 1
	local openTag = '<string name="Source">'
	while true do
		local startAt, endAt = string.find(xml, openTag, position, true)
		if not startAt then
			table.insert(out, string.sub(xml, position))
			break
		end
		table.insert(out, string.sub(xml, position, startAt - 1))
		table.insert(out, '<ProtectedString name="Source">')
		local cursor = endAt + 1
		while true do
			if string.sub(xml, cursor, cursor + 8) == "<![CDATA[" then
				local cdataEnd = string.find(xml, "]]>", cursor + 9, true)
				assert(cdataEnd, "unterminated CDATA")
				table.insert(out, string.sub(xml, cursor, cdataEnd + 2))
				cursor = cdataEnd + 3
			elseif string.sub(xml, cursor, cursor + 8) == "</string>" then
				table.insert(out, "</ProtectedString>")
				cursor += 9
				break
			else
				local nextTag = string.find(xml, "<", cursor, true)
				assert(nextTag and nextTag > cursor, "unexpected content inside a Source property")
				table.insert(out, string.sub(xml, cursor, nextTag - 1))
				cursor = nextTag
			end
		end
		position = cursor
	end
	return table.concat(out)
end

Env.installPolyfills({})

print("Reading " .. PLACE_XML)
local dm = readPlace(PLACE_XML)
local workspace = dm:GetService("Workspace")

-- Start from a clean slate: drop what a previous build (or the template) put in Workspace.
removeChildren(workspace, { "Town", "Vehicles", "Baseplate", "SpawnLocation" })

-- No streaming: the whole town is small, and the client UI refers to world positions directly.
workspace.StreamingEnabled = false

print("Injecting scripts")
Env.injectSources(dm, ROOT)

local runtime = Env.new(dm)
local ReplicatedStorage = dm:GetService("ReplicatedStorage")
local Config = runtime:require(ReplicatedStorage.Shared.Config)

-- Same lighting the server applies at startup, so the edit view matches.
local lighting = dm:GetService("Lighting")
for property, value in Config.Lighting do
	lighting[property] = value
end

print("Baking the town (this runs src/server/WorldBuilder.luau)")
local WorldBuilder = runtime:require(dm:GetService("ServerScriptService").Server.WorldBuilder)
local started = os.clock()
local town = WorldBuilder.build(workspace)
local partCount = 0
for _, descendant in town:GetDescendants() do
	if descendant:IsA("BasePart") then
		partCount += 1
	end
end
print(string.format("  built %d parts in %.2fs", partCount, os.clock() - started))

print("Writing " .. PLACE_BINARY)
fs.writeFile(PLACE_BINARY, roblox.serializePlace(dm))
print("Writing " .. PLACE_XML)
fs.writeFile(PLACE_XML, useProtectedStrings(roblox.serializePlace(dm, true)))

-- Verify by reading both files back -------------------------------------------------------

local function verify(path: string)
	local check = readPlace(path)
	local ws = check:GetService("Workspace")
	local problems = {}

	local checkTown = ws:FindFirstChild("Town")
	if not checkTown then
		table.insert(problems, "Workspace.Town missing")
	else
		local houses = checkTown:FindFirstChild("Houses")
		local count = houses and #houses:GetChildren() or 0
		if count ~= #town.Houses:GetChildren() then
			table.insert(problems, string.format("expected %d houses, found %d", #town.Houses:GetChildren(), count))
		end
		local sample = houses and houses:FindFirstChild("House_1")
		if sample then
			local marker = sample:GetAttribute("MarkerPos")
			if typeof(marker) ~= "Vector3" then
				table.insert(problems, "house attributes did not survive saving (MarkerPos is " .. typeof(marker) .. ")")
			end
			local body = sample:FindFirstChild("Body")
			local original = town.Houses.House_1.Body
			if not body or body.CFrame ~= original.CFrame or body.Size ~= original.Size or body.Color ~= original.Color then
				table.insert(problems, "house body CFrame/Size/Color did not survive saving")
			end
		else
			table.insert(problems, "House_1 missing")
		end
		local depot = checkTown:FindFirstChild("Depot")
		if not depot or not depot:FindFirstChild("DispatchAnchor") or not depot.DispatchAnchor:FindFirstChild("Prompt") then
			table.insert(problems, "dispatch prompt missing")
		end
	end

	for _, mapping in Env.MAPPING do
		local container = check:GetService(mapping.service)
		for _, name in mapping.path do
			container = container and container:FindFirstChild(name)
		end
		if not container then
			table.insert(problems, "missing " .. mapping.service .. "." .. table.concat(mapping.path, "."))
		end
	end

	-- Every script must come back byte-for-byte as it is on disk.
	local function compareDirectory(dirPath: string, container)
		for _, entry in fs.readDir(dirPath) do
			local full = dirPath .. "/" .. entry
			if fs.isDir(full) then
				local child = container:FindFirstChild(entry)
				if not child then
					table.insert(problems, "missing folder " .. container.Name .. "." .. entry)
				else
					compareDirectory(full, child)
				end
			else
				local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
				local script = container:FindFirstChild(name)
				if not script then
					table.insert(problems, "missing script " .. container.Name .. "." .. name)
				elseif script.Source ~= fs.readFile(full) then
					table.insert(problems, "script source differs after saving: " .. container.Name .. "." .. name)
				end
			end
		end
	end
	for _, mapping in Env.MAPPING do
		local container = check:GetService(mapping.service)
		for _, name in mapping.path do
			container = container and container:FindFirstChild(name)
		end
		if container then
			compareDirectory(ROOT .. "/" .. mapping.src, container)
		end
	end

	local main = check:GetService("ServerScriptService"):FindFirstChild("Server")
	main = main and main:FindFirstChild("Main")
	if not main or main.ClassName ~= "Script" or #main.Source < 100 then
		table.insert(problems, "server Main script missing or empty")
	end
	local clientMain = check:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	clientMain = clientMain and clientMain:FindFirstChild("Client")
	clientMain = clientMain and clientMain:FindFirstChild("Main")
	if not clientMain or clientMain.ClassName ~= "LocalScript" then
		table.insert(problems, "client Main LocalScript missing")
	end
	if ws.StreamingEnabled then
		table.insert(problems, "StreamingEnabled should be off")
	end
	if ws:FindFirstChild("Baseplate") or ws:FindFirstChild("SpawnLocation") then
		table.insert(problems, "template Baseplate/SpawnLocation still present")
	end

	if #problems > 0 then
		error("verification failed for " .. path .. ":\n  - " .. table.concat(problems, "\n  - "))
	end
	print("  verified " .. path)
end

print("Verifying")
verify(PLACE_BINARY)
verify(PLACE_XML)
print("Done.")
