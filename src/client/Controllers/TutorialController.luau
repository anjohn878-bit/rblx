--[[
	TutorialController
	First-time guide: "Patients are arriving! Diagnose them to earn money."
	Walks the player through their first patient, then points at the shop.
	Can be skipped at any time.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local TutorialController = {}

local controllers: any = nil
local coach: Frame
local coachText: TextLabel
local nextButton: TextButton
local shopArrow: TextLabel
local finished = false
local nextPressed = false

local function say(text: string, showNext: boolean?)
	coachText.Text = text
	nextButton.Visible = showNext == true
	nextPressed = false
	if not coach.Visible then
		coach.Visible = true
	end
	UIKit.PopIn(coach, 0.3)
end

local function finish(action: string)
	if finished then
		return
	end
	finished = true
	coach.Visible = false
	shopArrow.Visible = false
	controllers.GuideController.Clear()
	Remotes.Event("TutorialAction"):FireServer(action)
end

-- Polls `predicate` until it is true, the tutorial ends, or `timeout` passes.
local function waitUntil(predicate: () -> boolean, timeout: number?): boolean
	local started = os.clock()
	while not finished do
		if predicate() then
			return true
		end
		if timeout and os.clock() - started > timeout then
			return false
		end
		task.wait(0.2)
	end
	return false
end

local function myPatient(): Model?
	local patients = controllers.PatientVisualsController.GetMyPatients()
	return patients[1]
end

local function run()
	local interact = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "tap the Diagnose button" else "press [E]"

	controllers.NotificationController.Banner({
		Style = "Big",
		Title = "👋 Welcome, Doctor!",
		Text = "Patients are arriving! Diagnose them to earn money.",
		Color = Theme.Colors.Teal,
	})
	say("🏥 This is YOUR hospital! Patients are arriving. Diagnose them to earn 💵 money.")
	task.wait(4)

	-- Step: follow the first patient
	waitUntil(function()
		return myPatient() ~= nil
	end, 20)
	local first = myPatient()
	if first then
		controllers.GuideController.PointTo(first)
	end
	say("🚶 Here comes your first patient! Normally patients check in at reception, but this one is heading straight to your Exam Room.")

	while not finished do
		-- Step: patient is ready in the exam room
		waitUntil(function()
			return #controllers.PatientVisualsController.GetWaitingForMe() > 0 or controllers.DiagnosisController.IsOpen()
		end, 90)
		if finished then
			return
		end
		local waiting = controllers.PatientVisualsController.GetWaitingForMe()[1]
		if waiting then
			controllers.GuideController.PointTo(waiting)
		end
		say(string.format("🩺 Your patient is lying in Exam Room 1. Follow the glowing trail and %s next to them!", interact))

		-- Step: diagnosis panel
		waitUntil(function()
			return controllers.DiagnosisController.IsOpen()
		end)
		if finished then
			return
		end
		controllers.GuideController.Clear()
		say("🔍 Read the SYMPTOMS, then pick the illness that matches. The handbook shows each illness's symptoms!")

		local diagnosed = false
		local connection = controllers.DiagnosisController.Diagnosed:Connect(function()
			diagnosed = true
		end)
		waitUntil(function()
			return diagnosed or not controllers.DiagnosisController.IsOpen()
		end)
		connection:Disconnect()
		if diagnosed then
			break
		end
	end
	if finished then
		return
	end

	task.wait(1.8)
	say("🎉 Amazing! You earned money! Every patient you treat pays you. Rare ⭐ patients pay much more!")
	task.wait(4.5)

	-- Step: the shop
	shopArrow.Visible = true
	say("🛒 Open the SHOP to spend your money on upgrades!")
	local opened = false
	local shopConnection = controllers.ShopController.Opened:Connect(function()
		opened = true
	end)
	waitUntil(function()
		return opened
	end, 40)
	shopConnection:Disconnect()
	shopArrow.Visible = false
	if finished then
		return
	end

	say("⬆️ Upgrade your hospital for more exam rooms and patients. 🤖 Hire Auto Doctors to treat patients for you. Keep growing your hospital!", true)
	waitUntil(function()
		return nextPressed
	end, 30)
	finish("Complete")
end

function TutorialController.Init(all: any)
	controllers = all
	local gui = UIKit.New("ScreenGui", {
		Name = "Tutorial",
		ResetOnSpawn = false,
		DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	coach = UIKit.New("Frame", {
		Name = "Coach",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84),
		Size = UDim2.fromOffset(660, 104),
		BackgroundColor3 = Theme.Colors.Panel,
		Visible = false,
		Parent = gui,
	}, {
		UIKit.Corner(18),
		UIKit.Stroke(4, Theme.Colors.Teal),
	})
	UIKit.Scaled(coach)
	UIKit.Label({
		Text = "👩",
		TextSize = 54,
		Size = UDim2.fromOffset(80, 104),
		Parent = coach,
	})
	UIKit.Label({
		Text = "Nurse Nina",
		TextSize = 16,
		TextColor3 = Theme.Colors.TealDark,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(200, 20),
		Position = UDim2.fromOffset(84, 6),
		Parent = coach,
	})
	coachText = UIKit.Label({
		Text = "",
		TextSize = 19,
		TextColor3 = Theme.Colors.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -230, 1, -32),
		Position = UDim2.fromOffset(84, 26),
		Parent = coach,
	})
	nextButton = UIKit.Button({
		Text = "Let's go! ➜",
		Color = Theme.Colors.Green,
		Size = UDim2.fromOffset(130, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, -10),
		TextSize = 19,
		Parent = coach,
		OnClick = function()
			nextPressed = true
		end,
	})
	nextButton.Visible = false
	local skip = UIKit.New("TextButton", {
		Text = "Skip tutorial",
		Font = Theme.BodyFont,
		TextSize = 13,
		TextColor3 = Theme.Colors.TextMuted,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -4),
		Size = UDim2.fromOffset(110, 20),
		Parent = coach,
	})
	skip.Activated:Connect(function()
		finish("Skip")
	end)

	shopArrow = UIKit.Label({
		Text = "⬅ OPEN SHOP!",
		TextSize = 30,
		TextColor3 = Theme.Colors.Yellow,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 104, 0.5, -112),
		Size = UDim2.fromOffset(220, 50),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = gui,
	})
	UIKit.TextStroke(3).Parent = shopArrow
	UIKit.Scaled(shopArrow)
end

function TutorialController.Start()
	task.spawn(function()
		local state = controllers.ClientState.Wait()
		if state.TutorialDone or state.PatientsTreated > 0 then
			finished = true
			return
		end
		-- Gentle bob on the shop arrow
		task.spawn(function()
			while not finished do
				if shopArrow.Visible then
					UIKit.Tween(shopArrow, 0.4, { Position = UDim2.new(0, 116, 0.5, -112) })
					task.wait(0.4)
					UIKit.Tween(shopArrow, 0.4, { Position = UDim2.new(0, 104, 0.5, -112) })
				end
				task.wait(0.4)
			end
		end)
		run()
	end)
end

return TutorialController
