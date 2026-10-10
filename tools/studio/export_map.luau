-- Run in Studio via MCP. Prints workspace.Map as JSON for tools/map/mapcheck.py.
-- Tags come from CollectionService tags and a comma-separated "MapTags" attribute.
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local root = workspace:FindFirstChild("Map") or workspace
local parts = {}
for _, p in root:GetDescendants() do
	if p:IsA("BasePart") and p.CanCollide and p.Transparency < 1 then
		local tags = CollectionService:GetTags(p)
		local attr = p:GetAttribute("MapTags")
		if typeof(attr) == "string" then
			for t in string.gmatch(attr, "[^,%s]+") do
				table.insert(tags, t)
			end
		end
		if p:IsA("SpawnLocation") then
			table.insert(tags, "spawn")
		end
		local rx, ry, rz = p.CFrame:ToOrientation()
		table.insert(parts, {
			name = p:GetFullName(),
			size = { p.Size.X, p.Size.Y, p.Size.Z },
			pos = { p.Position.X, p.Position.Y, p.Position.Z },
			rot = { math.deg(rx), math.deg(ry), math.deg(rz) },
			tags = tags,
		})
	end
end

local json = HttpService:JSONEncode({ parts = parts })
print("BEGIN_JSON")
for i = 1, #json, 3000 do
	print(string.sub(json, i, i + 2999))
end
print("END_JSON", #parts, "parts")
