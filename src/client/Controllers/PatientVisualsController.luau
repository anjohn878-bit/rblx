--[[
	PatientVisualsController
	Builds name/status billboards for patients, Auto Doctors and staff on
	every hospital (purely client-side, driven by model attributes), animates
	the "examining" progress bars, and tells the HUD how many of *your*
	patients are waiting for you.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local AutoDoctors = require(Config:WaitForChild("AutoDoctors"))
local Rarities = require(Config:WaitForChild("Rarities"))
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local PatientVisualsController = {}

local controllers: any = nil
local player = Players.LocalPlayer

type Entry = {
	Model: Model,
	Billboard: BillboardGui,
	Status: TextLabel,
	Bar: Frame?,
	Fill: Frame?,
	Own: boolean,
	IsPatient: boolean,
}

local entries: { [Model]: Entry } = {}

local STATUS_TEXT = {
	Arriving = "🚶 Arriving",
	ToSeat = "🚶 Arriving",
	CheckingIn = "📋 Checking in",
	Waiting = "🪑 Waiting",
	ToExam = "🚶 Going to exam room",
	NeedsDoctor = "❓ Needs a doctor!",
	Examining = "🩺 Being examined",
	BeingDiagnosed = "🩺 With the doctor",
	Treated = "✅ Treated!",
	Leaving = "😊 Feeling better!",
}

local KIND_PREFIX = {
	Emergency = "🚨 ",
	VIP = "👑 ",
	Child = "🧸 ",
}

local function makeBillboard(model: Model, height: number, width: number, offsetY: number): (BillboardGui?, BasePart?)
	local head = model:WaitForChild("Head", 5)
	if not head or not head:IsA("BasePart") then
		return nil, nil
	end
	local billboard = UIKit.New("BillboardGui", {
		Name = "Info",
		Size = UDim2.fromOffset(width, height),
		StudsOffset = Vector3.new(0, offsetY, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = 85,
		ResetOnSpawn = false,
		Parent = head,
	})
	return billboard, head
end

local function updatePatient(entry: Entry)
	local model = entry.Model
	local status = model:GetAttribute("Status") or "Arriving"
	local text = STATUS_TEXT[status] or status
	if status == "NeedsDoctor" then
		text = if entry.Own then "❓ Needs YOU! Press E" else "❓ Waiting for doctor"
		entry.Status.TextColor3 = Theme.Colors.Yellow
	elseif status == "Treated" or status == "Leaving" then
		entry.Status.TextColor3 = Theme.Colors.Money
	else
		entry.Status.TextColor3 = Theme.Colors.White
	end
	entry.Status.Text = text
	if entry.Bar then
		local hasProgress = model:GetAttribute("ProgressDuration") ~= nil and (status == "Examining" or status == "BeingDiagnosed")
		entry.Bar.Visible = hasProgress
	end
end

local function trackPatient(model: Model)
	if entries[model] then
		return
	end
	local billboard = makeBillboard(model, 78, 230, 2.8)
	if not billboard or not model.Parent then
		if billboard then
			billboard:Destroy()
		end
		return
	end
	local rarity = Rarities.ById[model:GetAttribute("Rarity") or "Common"] or Rarities.List[1]
	local kind = model:GetAttribute("Kind") or "Normal"
	local name = UIKit.Label({
		Text = (KIND_PREFIX[kind] or "") .. string.rep("⭐", rarity.Stars) .. (if rarity.Stars > 0 then " " else "") .. tostring(model:GetAttribute("PatientName") or "Patient"),
		TextSize = 20,
		TextColor3 = rarity.Color,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = billboard,
	})
	UIKit.TextStroke(2).Parent = name
	local status = UIKit.Label({
		Text = "",
		TextSize = 17,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 24),
		Parent = billboard,
	})
	UIKit.TextStroke(2).Parent = status
	local bar = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(140, 14),
		BackgroundColor3 = Color3.fromRGB(25, 30, 45),
		Visible = false,
		Parent = billboard,
	}, {
		UIKit.Corner(7),
		UIKit.Stroke(2, Theme.Colors.Stroke),
	})
	local fill = UIKit.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Green,
		Parent = bar,
	}, {
		UIKit.Corner(7),
	})

	local entry: Entry = {
		Model = model,
		Billboard = billboard,
		Status = status,
		Bar = bar,
		Fill = fill,
		Own = model:GetAttribute("OwnerUserId") == player.UserId,
		IsPatient = true,
	}
	entries[model] = entry
	updatePatient(entry)
	model.AttributeChanged:Connect(function()
		updatePatient(entry)
	end)
end

local function updateDoctor(entry: Entry)
	local model = entry.Model
	local tierInfo = AutoDoctors.Tiers[model:GetAttribute("Tier") or 1] or AutoDoctors.Tiers[1]
	local status = model:GetAttribute("Status")
	entry.Status.Text = if status == "Examining" then "🩺 Examining..." else "💤 Ready for patients"
	entry.Status.TextColor3 = if status == "Examining" then Theme.Colors.Money else Theme.Colors.White
	local nameLabel = entry.Billboard:FindFirstChild("DoctorName") :: TextLabel?
	if nameLabel then
		nameLabel.Text = (if tierInfo.Robot then "🤖 " else "🥼 ") .. tierInfo.Name
		nameLabel.TextColor3 = tierInfo.Accent
	end
end

local function trackDoctor(model: Model)
	if entries[model] then
		return
	end
	local billboard = makeBillboard(model, 50, 230, 2.6)
	if not billboard then
		return
	end
	local name = UIKit.Label({
		Name = "DoctorName",
		Text = "",
		TextSize = 19,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = billboard,
	})
	UIKit.TextStroke(2).Parent = name
	local status = UIKit.Label({
		Text = "",
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 24),
		Parent = billboard,
	})
	UIKit.TextStroke(2).Parent = status
	local entry: Entry = {
		Model = model,
		Billboard = billboard,
		Status = status,
		Bar = nil,
		Fill = nil,
		Own = model:GetAttribute("OwnerUserId") == player.UserId,
		IsPatient = false,
	}
	entries[model] = entry
	updateDoctor(entry)
	model.AttributeChanged:Connect(function()
		updateDoctor(entry)
	end)
end

local function trackStaff(model: Model)
	local billboard = makeBillboard(model, 26, 200, 2.4)
	if not billboard then
		return
	end
	billboard.MaxDistance = 50
	local label = UIKit.Label({
		Text = tostring(model:GetAttribute("StaffName") or "Staff"),
		TextSize = 17,
		TextColor3 = Color3.fromRGB(255, 200, 230),
		Size = UDim2.fromScale(1, 1),
		Parent = billboard,
	})
	UIKit.TextStroke(2).Parent = label
end

local function untrack(model: Instance)
	local entry = entries[model :: Model]
	if entry then
		entries[model :: Model] = nil
		entry.Billboard:Destroy()
	end
end

local function listen(tag: string, callback: (Model) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		if instance:IsA("Model") then
			task.spawn(callback, instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack)
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("Model") then
			task.spawn(callback, instance)
		end
	end
end

function PatientVisualsController.Init(all: any)
	controllers = all
end

-- Returns your patients that are lying in an exam room waiting for you.
function PatientVisualsController.GetWaitingForMe(): { Model }
	local result = {}
	for model, entry in entries do
		if entry.IsPatient and entry.Own and model:GetAttribute("Status") == "NeedsDoctor" then
			table.insert(result, model)
		end
	end
	return result
end

function PatientVisualsController.GetMyPatients(): { Model }
	local result = {}
	for model, entry in entries do
		if entry.IsPatient and entry.Own then
			table.insert(result, model)
		end
	end
	return result
end

function PatientVisualsController.Start()
	listen("Patient", trackPatient)
	listen("AutoDoctor", trackDoctor)
	listen("Staff", trackStaff)

	-- Progress bars
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for model, entry in entries do
			if entry.Bar and entry.Bar.Visible and entry.Fill then
				local duration = model:GetAttribute("ProgressDuration")
				local start = model:GetAttribute("ProgressStart")
				if typeof(duration) == "number" and typeof(start) == "number" and duration > 0 then
					local fraction
					if model:GetAttribute("ProgressPaused") then
						fraction = model:GetAttribute("ProgressFrozen") or 0
					else
						fraction = (now - start) / duration
					end
					entry.Fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
				end
			end
		end
	end)

	-- "Patients need you" alert
	task.spawn(function()
		while true do
			task.wait(0.5)
			local waiting = PatientVisualsController.GetWaitingForMe()
			local nearest: Model? = nil
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local best = math.huge
				for _, model in waiting do
					local distance = (model:GetPivot().Position - root.Position).Magnitude
					if distance < best then
						best = distance
						nearest = model
					end
				end
			end
			controllers.HUDController.SetNeedsYou(#waiting, nearest)
		end
	end)
end

return PatientVisualsController
