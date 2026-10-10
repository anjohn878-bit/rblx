-- Run in Studio via MCP. Put sound packs under ServerStorage.SoundPacks.
-- Prints a catalog for library/sound/catalog.json (names/tags are then refined by Claude).
local HttpService = game:GetService("HttpService")
local packs = game:GetService("ServerStorage"):FindFirstChild("SoundPacks")
assert(packs, "Create ServerStorage.SoundPacks and drop sound packs in it")

local out = {}
for _, s in packs:GetDescendants() do
	if s:IsA("Sound") and s.SoundId ~= "" then
		table.insert(out, {
			name = s.Name,
			id = s.SoundId,
			path = s:GetFullName(),
			length = s.TimeLength,
			volume = s.Volume,
		})
	end
end
local json = HttpService:JSONEncode(out)
print("BEGIN_JSON")
for i = 1, #json, 3000 do
	print(string.sub(json, i, i + 2999))
end
print("END_JSON", #out, "sounds")
