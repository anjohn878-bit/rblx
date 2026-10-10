-- Run in Studio via MCP. Put free VFX packs (toolbox) under ServerStorage.VFXPacks first.
-- Every ParticleEmitter / Beam / Trail becomes a classified building block, copied
-- into ServerStorage.VFXLibrary/<class>/<id>, and a JSON index is printed.
-- The library is built from other creators' textures: keep it in YOUR place, don't redistribute.
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local packs = ServerStorage:FindFirstChild("VFXPacks")
assert(packs, "Create ServerStorage.VFXPacks and drop the packs in it")
local library = ServerStorage:FindFirstChild("VFXLibrary") or Instance.new("Folder")
library.Name = "VFXLibrary"
library.Parent = ServerStorage

local KEYWORDS = {
	fire = { "fire", "flame", "burn", "ember", "blaze" },
	smoke = { "smoke", "dust", "fog", "cloud", "mist" },
	spark = { "spark", "glint", "star", "twinkle", "sparkle" },
	glow = { "glow", "orb", "aura", "light", "bloom", "flare" },
	shockwave = { "shock", "wave", "ring", "nova", "pulse", "impact" },
	slash = { "slash", "swing", "arc", "cut", "crescent" },
	electric = { "lightning", "electric", "bolt", "zap", "thunder" },
	water = { "water", "splash", "bubble", "drip", "wave" },
	debris = { "debris", "rock", "shard", "chunk", "pebble" },
}

local function classify(inst: Instance): string
	local hay = string.lower(inst:GetFullName() .. " " .. tostring((inst :: any).Texture or ""))
	for class, words in KEYWORDS do
		for _, w in words do
			if string.find(hay, w, 1, true) then
				return class
			end
		end
	end
	if inst:IsA("Beam") then
		return "beam"
	elseif inst:IsA("Trail") then
		return "trail"
	end
	local e = inst :: ParticleEmitter
	if e.Speed.Max < 2 and e.Lifetime.Max > 1 then
		return "glow"
	end
	return "misc"
end

local function seqToTable(seq: any)
	local out = {}
	for _, k in seq.Keypoints do
		local v = k.Value
		if typeof(v) == "Color3" then
			v = v:ToHex()
		end
		table.insert(out, { k.Time, v })
	end
	return out
end

local index = {}
local count = 0
for _, inst in packs:GetDescendants() do
	if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
		count += 1
		local class = classify(inst)
		local folder = library:FindFirstChild(class) or Instance.new("Folder")
		folder.Name = class
		folder.Parent = library
		local id = string.format("%s_%03d", class, count)
		local block = inst:Clone()
		block.Name = id
		block:SetAttribute("SourcePath", inst:GetFullName())
		block.Parent = folder
		local entry: { [string]: any } =
			{ id = id, class = class, kind = inst.ClassName, source = inst:GetFullName() }
		entry.texture = (inst :: any).Texture
		if inst:IsA("ParticleEmitter") then
			entry.lifetime = { inst.Lifetime.Min, inst.Lifetime.Max }
			entry.speed = { inst.Speed.Min, inst.Speed.Max }
			entry.rate = inst.Rate
			entry.size = seqToTable(inst.Size)
			entry.color = seqToTable(inst.Color)
			entry.lightEmission = inst.LightEmission
		end
		table.insert(index, entry)
	end
end

local json = HttpService:JSONEncode(index)
print("BEGIN_JSON")
for i = 1, #json, 3000 do
	print(string.sub(json, i, i + 2999))
end
print("END_JSON", count, "blocks")
