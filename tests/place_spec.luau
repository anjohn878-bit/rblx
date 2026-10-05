--[[
	Checks the committed place files and project config, so the game you open in Studio is guaranteed
	to be the game the source describes:

	  * Place1.rbxl / Place1.rbxlx contain every script, byte-for-byte identical to src/
	  * the baked town is there, with its attributes, prompts and spawn
	  * default.project.json (Rojo) maps the same folders as the build tool
	  * every script compiles
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Env = require("../tools/env")

local ROOT = "."

local function scriptFiles(dirPath: string, relative: string, out)
	local entries = fs.readDir(dirPath)
	table.sort(entries)
	for _, entry in entries do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			scriptFiles(full, relative .. "/" .. entry, out)
		elseif entry:match("%.luau$") then
			table.insert(out, { path = full, relative = relative .. "/" .. entry })
		end
	end
	return out
end

local function find(root, parts)
	local node = root
	for _, name in parts do
		node = node and node:FindFirstChild(name)
	end
	return node
end

return function(T)
	T.test("every source file compiles as Luau", function()
		for _, mapping in Env.MAPPING do
			for _, file in scriptFiles(ROOT .. "/" .. mapping.src, mapping.src, {}) do
				local ok, err = pcall(luau.compile, fs.readFile(file.path))
				T.truthy(ok, file.relative .. ": " .. tostring(err))
			end
		end
	end)

	T.test("source files follow the naming convention (.server / .client / plain module)", function()
		local servers, clients = 0, 0
		for _, mapping in Env.MAPPING do
			for _, file in scriptFiles(ROOT .. "/" .. mapping.src, mapping.src, {}) do
				if file.relative:match("%.server%.luau$") then
					servers += 1
					T.truthy(mapping.service == "ServerScriptService", file.relative .. " is a Script outside ServerScriptService")
				elseif file.relative:match("%.client%.luau$") then
					clients += 1
					T.truthy(mapping.service == "StarterPlayer", file.relative .. " is a LocalScript outside StarterPlayer")
				end
			end
		end
		T.eq(servers, 1, "exactly one server entry point")
		T.eq(clients, 1, "exactly one client entry point")
	end)

	T.test("default.project.json maps the same folders as the build tool", function()
		local project = require("@lune/serde").decode("json", fs.readFile(ROOT .. "/default.project.json"))
		local tree = project.tree
		local function pathOf(node, parts)
			for _, name in parts do
				node = node and node[name]
			end
			return node and node["$path"]
		end
		for _, mapping in Env.MAPPING do
			local parts = { mapping.service }
			for _, name in mapping.path do
				table.insert(parts, name)
			end
			T.eq(pathOf(tree, parts), mapping.src, "project path for " .. table.concat(parts, "."))
		end
		T.eq(tree.Workspace["$properties"].StreamingEnabled, false)
	end)

	for _, file in { "Place1.rbxl", "Place1.rbxlx" } do
		local place = roblox.deserializePlace(fs.readFile(ROOT .. "/" .. file))
		local ws = place:GetService("Workspace")

		T.test(file .. ": every script is present and identical to src/ (rebuild with `lune run tools/build` if this fails)", function()
			local checked = 0
			local function compare(dirPath: string, container, label: string)
				for _, entry in fs.readDir(dirPath) do
					local full = dirPath .. "/" .. entry
					if fs.isDir(full) then
						local child = container:FindFirstChild(entry)
						T.truthy(child, label .. "." .. entry .. " is missing from " .. file)
						compare(full, child, label .. "." .. entry)
					elseif entry:match("%.luau$") then
						local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
						local instance = container:FindFirstChild(name)
						T.truthy(instance, label .. "." .. name .. " is missing from " .. file)
						T.eq(instance.Source, fs.readFile(full), label .. "." .. name .. " is out of date in " .. file)
						local expectedClass = entry:match("%.server%.luau$") and "Script"
							or (entry:match("%.client%.luau$") and "LocalScript" or "ModuleScript")
						T.eq(instance.ClassName, expectedClass, label .. "." .. name)
						checked += 1
					end
				end
			end
			for _, mapping in Env.MAPPING do
				local container = place:GetService(mapping.service)
				for _, name in mapping.path do
					container = container:FindFirstChild(name)
					T.truthy(container, mapping.service .. "." .. name .. " missing from " .. file)
				end
				compare(ROOT .. "/" .. mapping.src, container, mapping.service)
			end
			T.truthy(checked >= 20, "only found " .. checked .. " scripts")
		end)

		T.test(file .. ": the town is baked in with its houses, prompts and spawn", function()
			local town = ws:FindFirstChild("Town")
			T.truthy(town, "Workspace.Town missing")
			T.eq(#town.Houses:GetChildren(), 144)
			local house = town.Houses.House_1
			T.eq(typeof(house:GetAttribute("MarkerPos")), "Vector3")
			T.eq(typeof(house:GetAttribute("Address")), "string")
			T.eq(typeof(house:GetAttribute("HouseId")), "number")
			T.eq(typeof(town:GetAttribute("DispatchPos")), "Vector3")
			T.eq(town.Depot.DispatchAnchor.Prompt.ClassName, "ProximityPrompt")
			T.eq(town.Depot.DispatchAnchor.Prompt.ActionText, "Take Order")
			T.eq(town.Depot.GarageAnchor.Prompt.ClassName, "ProximityPrompt")
			T.eq(town.Depot.Spawn.ClassName, "SpawnLocation")
			-- ground and roads survive with real geometry (not collapsed at the origin)
			T.eq(town.Ground.Size.X, 966 + 240)
			T.eq(town.Roads.RoadEW_0.CFrame.Position.Z, -465)
			T.eq(town.Roads.RoadEW_5.CFrame.Position.Z, 465)
			T.truthy(house.Body.CFrame.Position ~= roblox.Vector3.zero)
			T.eq(house.Body.Material, roblox.Enum.Material.Brick)
		end)

		T.test(file .. ": signs and plaques keep their text", function()
			local plaque = ws.Town.Houses.House_1.NumberPlaque
			local label = plaque:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
			T.eq(label.Text, tostring(ws.Town.Houses.House_1:GetAttribute("Number")))
			local sign = ws.Town.Depot.DepotSign:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
			T.eq(sign.Text, "SWIFT DROP DEPOT")
		end)

		T.test(file .. ": template baseplate/spawn are gone and streaming is off", function()
			T.falsy(ws:FindFirstChild("Baseplate"))
			T.falsy(ws:FindFirstChild("SpawnLocation"))
			T.eq(ws.StreamingEnabled, false)
			T.truthy(find(place:GetService("Lighting"), { "Sky" }), "template Sky kept")
			T.truthy(ws:FindFirstChildOfClass("Terrain"), "terrain kept")
		end)
	end

	T.test("the binary and XML places describe the same game", function()
		local function summary(file)
			local place = roblox.deserializePlace(fs.readFile(ROOT .. "/" .. file))
			local parts, scripts = 0, 0
			for _, d in place:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				elseif d:IsA("LuaSourceContainer") then
					scripts += 1
				end
			end
			return parts, scripts
		end
		local binaryParts, binaryScripts = summary("Place1.rbxl")
		local xmlParts, xmlScripts = summary("Place1.rbxlx")
		T.eq(binaryParts, xmlParts)
		T.eq(binaryScripts, xmlScripts)
	end)
end
