-- Run in Studio (edit mode) via MCP, then take a screenshot with the MCP screenshot tool.
-- A burst lasts < 1s, so a plain screenshot is a coin flip. Instead: emit, wait the
-- exact phase time, freeze every emitter (TimeScale = 0), screenshot, repeat.
-- Set EFFECT_PATH and PHASE before running. Phases to check: start, middle, end.
local EFFECT_PATH = "ReplicatedStorage.VFX.Fireball" -- Model/Part/Attachment holding the effect
local PHASE = 0.15 -- seconds after emit (e.g. 0.05 start, 0.3 middle, 0.8 end)

local function resolve(path: string): Instance
	local cur: Instance = game
	for part in string.gmatch(path, "[^%.]+") do
		cur = cur:FindFirstChild(part) or game:GetService(part)
	end
	return cur
end

local old = workspace:FindFirstChild("_VFXPreview")
if old then
	old:Destroy()
end
local cam = workspace.CurrentCamera
local anchor = Instance.new("Part")
anchor.Name = "_VFXPreview"
anchor.Anchored, anchor.CanCollide, anchor.Transparency = true, false, 1
anchor.Size = Vector3.one
anchor.CFrame = cam.CFrame * CFrame.new(0, 0, -14)
anchor.Parent = workspace

local effect = resolve(EFFECT_PATH):Clone()
if effect:IsA("PVInstance") then
	effect:PivotTo(anchor.CFrame)
end
effect.Parent = anchor

local emitters = {}
for _, d in anchor:GetDescendants() do
	if d:IsA("ParticleEmitter") then
		d.TimeScale = 1
		table.insert(emitters, d)
	end
end
for _, e in emitters do
	local burst = e:GetAttribute("EmitCount") or math.max(1, math.floor(e.Rate * 0.1))
	e:Emit(burst)
end
task.wait(PHASE)
for _, e in emitters do
	e.TimeScale = 0
end
print(
	`[phase-freeze] {#emitters} emitters frozen at t={PHASE}s - take the screenshot now; delete workspace._VFXPreview after`
)
