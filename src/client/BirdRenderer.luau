--!strict
-- Draws every bird visit. The server only sends a tiny description of each
-- visit; this module animates the bird locally from BirdFlight, so birds are
-- perfectly smooth and cost nothing in network traffic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdFlight = require(Shared:WaitForChild("BirdFlight"))
local BirdModel = require(Shared:WaitForChild("BirdModel"))
local Birds = require(Shared:WaitForChild("Birds"))
local Clock = require(Shared:WaitForChild("Clock"))
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Ui = require(script.Parent.Ui)

local BirdRenderer = {}

type Active = {
	info: Types.VisitInfo,
	rig: BirdModel.Rig,
	duration: number,
	attached: boolean,
	flap: number,
	wingPhase: number,
	nameGui: BillboardGui,
}

local CULL_DISTANCE = 260 -- birds further than this aren't drawn at all

local active: { [number]: Active } = {}
local folder: Folder

local function destroy(id: number)
	local bird = active[id]
	if bird then
		active[id] = nil
		bird.rig.model:Destroy()
	end
end

function BirdRenderer.add(info: Types.VisitInfo)
	if active[info.id] then
		return
	end
	local def = Birds.get(info.birdId)
	if not def then
		return
	end
	local duration = BirdFlight.duration(info)
	if Clock.now() - info.startTime >= duration then
		return -- this visit is already over
	end

	local rig = BirdModel.build(def)
	local color = Config.RARITY_COLORS[def.rarity]
	local gui = Ui.new("BillboardGui", {
		Name = "NameTag",
		Size = UDim2.fromOffset(150, 26),
		StudsOffsetWorldSpace = Vector3.new(0, rig.height + 1.1, 0),
		MaxDistance = 55,
		LightInfluence = 0,
		Adornee = rig.model.PrimaryPart,
		Parent = rig.model.PrimaryPart,
	})
	Ui.label({
		Size = UDim2.fromScale(1, 1),
		Text = def.name,
		Font = Ui.FONT,
		TextSize = 17,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.25,
		Parent = gui,
	})

	active[info.id] = {
		info = info,
		rig = rig,
		duration = duration,
		attached = false,
		flap = 1,
		wingPhase = info.seed,
		nameGui = gui,
	}
end

function BirdRenderer.remove(id: number)
	destroy(id)
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local now = Clock.now()

	for id, bird in active do
		local t = now - bird.info.startTime
		if t >= bird.duration then
			destroy(id)
		else
			local sample = BirdFlight.sample(bird.info, t)
			if (sample.position - cameraPosition).Magnitude > CULL_DISTANCE then
				if bird.attached then
					bird.attached = false
					bird.rig.model.Parent = nil
				end
			else
				-- ease the wings between folded (perched) and beating (flying)
				bird.flap += (sample.flap - bird.flap) * math.min(1, dt * 10)
				bird.wingPhase += dt * bird.rig.flapRate
				local angle = bird.flap * (1.25 + 0.95 * math.sin(bird.wingPhase))

				local look = sample.look
				if math.abs(look.Y) > 0.98 then
					look = Vector3.new(look.X + 0.05, look.Y, look.Z)
				end
				BirdModel.pose(bird.rig, CFrame.lookAt(sample.position, sample.position + look), angle)

				bird.nameGui.Enabled = sample.phase ~= "leave"
				if not bird.attached then
					bird.attached = true
					bird.rig.model.Parent = folder
				end
			end
		end
	end
end

function BirdRenderer.init(initialVisits: { Types.VisitInfo })
	folder = Ui.new("Folder", { Name = "ClientBirds", Parent = workspace })
	for _, info in initialVisits do
		BirdRenderer.add(info)
	end
	RunService.RenderStepped:Connect(step)
end

return BirdRenderer
