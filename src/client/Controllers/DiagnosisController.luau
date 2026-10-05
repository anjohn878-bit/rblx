--[[
	DiagnosisController
	The big diagnosis panel: patient card + symptoms on the left, possible
	illnesses on the right. Picking an option asks the server, which decides
	if it was right and pays out.

	Extras: 📖 Handbook (shows each illness's symptoms, costs the expert
	bonus), 🧪 Lab Test (removes a wrong answer once, needs the Laboratory)
	and number keys 1-6 to answer quickly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local DiagnosisController = {}
DiagnosisController.Opened = Signal.new()
DiagnosisController.Closed = Signal.new()
DiagnosisController.Diagnosed = Signal.new()

local controllers: any = nil
local player = Players.LocalPlayer

local gui: ScreenGui
local dim: Frame
local panel: Frame
local header: Frame
local headerGradient: UIGradient
local titleLabel: TextLabel
local rarityLabel: TextLabel
local faceLabel: TextLabel
local nameLabel: TextLabel
local tagLabel: TextLabel
local symptomList: Frame
local optionsFrame: ScrollingFrame
local optionsGrid: UIGridLayout
local handbookButton: TextButton
local labButton: TextButton
local rewardLabel: TextLabel
local feedbackLabel: TextLabel
local tipLabel: TextLabel
local resultOverlay: Frame

local current: any = nil -- payload of the open case
local optionButtons: { [string]: TextButton } = {}
local optionOrder: { string } = {}
local hints: { [string]: { string } }? = nil
local busy = false

local KEYCODES = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
}

local function kindFace(kind: string, rarity: string): string
	if kind == "VIP" then
		return "🤩"
	elseif kind == "Emergency" then
		return "😵"
	elseif kind == "Child" then
		return "🧒"
	elseif rarity == "Legendary" or rarity == "Epic" then
		return "🥴"
	end
	return "🤒"
end

local function stars(count: number): string
	return string.rep("⭐", count)
end

local function optionText(option: any): string
	local text = string.format('<font size="22">%s %s</font>', option.Emoji, option.Name)
	if hints and hints[option.Id] then
		local parts = {}
		for _, symptom in hints[option.Id] do
			if current and table.find(current.Symptoms, symptom) then
				table.insert(parts, '<font color="#FFF59D">' .. symptom .. "</font>")
			else
				table.insert(parts, symptom)
			end
		end
		text ..= '\n<font size="13">' .. table.concat(parts, ", ") .. "</font>"
	end
	if option.Wrong then
		text = "❌ " .. text
	end
	return text
end

local function refreshOptions()
	if not current then
		return
	end
	optionsGrid.CellSize = if hints then UDim2.fromOffset(204, 118) else UDim2.fromOffset(204, 74)
	for _, option in current.Options do
		local button = optionButtons[option.Id]
		if button then
			UIKit.SetButtonText(button, optionText(option))
			if option.Removed then
				button.Visible = false
			elseif option.Wrong then
				UIKit.SetButtonColor(button, Theme.Colors.Red)
			end
		end
	end
end

local function missMultiplier(misses: number): number
	local list = GameConfig.WrongAnswerMultipliers
	return list[math.clamp(misses + 1, 1, #list)]
end

local function isExpert(handbook: boolean, misses: number): boolean
	return not handbook and misses == 0
end

-- Display-only estimate; the server computes the real payout.
local function setRewardText()
	if not current then
		return
	end
	local base = current.Estimate
	if current.OpenExpert then
		base /= GameConfig.ExpertBonus
	end
	base /= missMultiplier(current.OpenMisses)
	local expert = isExpert(current.UsedHandbook, current.Misses)
	local estimate = base * missMultiplier(current.Misses) * (if expert then GameConfig.ExpertBonus else 1)
	local text = "💵 Reward ≈ " .. Format.Money(math.floor(estimate + 0.5))
	if expert then
		text ..= string.format("  (+%d%% expert bonus, no handbook)", math.floor((GameConfig.ExpertBonus - 1) * 100 + 0.5))
	elseif current.Misses > 0 then
		text ..= "  (reduced after a mistake)"
	end
	rewardLabel.Text = text
end

function DiagnosisController.IsOpen(): boolean
	return current ~= nil
end

function DiagnosisController.Close(sendCancel: boolean?)
	if not current then
		return
	end
	local patientId = current.PatientId
	current = nil
	hints = nil
	busy = false
	panel.Visible = false
	dim.Visible = false
	resultOverlay.Visible = false
	if sendCancel then
		Remotes.Event("CancelDiagnosis"):FireServer(patientId)
	end
	DiagnosisController.Closed:Fire()
end

local function revealHandbook()
	if not current or hints then
		return
	end
	local patientId = current.PatientId
	local ok, result = pcall(function()
		return Remotes.Function("RevealHandbook"):InvokeServer(patientId)
	end)
	if ok and type(result) == "table" and current and current.PatientId == patientId then
		hints = result
		current.UsedHandbook = true
		UIKit.SetButtonText(handbookButton, "📖 Handbook ON")
		UIKit.SetButtonColor(handbookButton, Theme.Colors.Gray)
		refreshOptions()
		setRewardText()
	end
end

local function useLab()
	if not current or current.LabUsed then
		return
	end
	local patientId = current.PatientId
	local ok, removed = pcall(function()
		return Remotes.Function("UseLabTest"):InvokeServer(patientId)
	end)
	if ok and type(removed) == "string" and current and current.PatientId == patientId then
		current.LabUsed = true
		for _, option in current.Options do
			if option.Id == removed then
				option.Removed = true
			end
		end
		labButton.Visible = false
		controllers.NotificationController.Toast("🧪 Lab results: one wrong answer ruled out!", "Info")
		refreshOptions()
	end
end

local function showSuccess(result: any)
	resultOverlay.Visible = true
	local stamp = resultOverlay:FindFirstChild("Stamp") :: TextLabel
	local money = resultOverlay:FindFirstChild("Money") :: TextLabel
	local details = resultOverlay:FindFirstChild("Details") :: TextLabel
	money.Text = "+" .. Format.Money((result.Reward or 0) + (result.Pharmacy or 0))
	local bits = { "+" .. tostring(result.XP or 0) .. " XP" }
	if result.Combo and result.Combo >= 2 then
		table.insert(bits, "🔥 Combo x" .. result.Combo)
	end
	if result.Expert then
		table.insert(bits, "🎓 Expert bonus!")
	end
	if result.Pharmacy and result.Pharmacy > 0 then
		table.insert(bits, "💊 +" .. Format.Money(result.Pharmacy))
	end
	details.Text = table.concat(bits, "  ·  ")
	stamp.Rotation = -20
	UIKit.PopIn(stamp, 0.4)
	UIKit.Tween(stamp, 0.4, { Rotation = -6 }, Enum.EasingStyle.Back)
	UIKit.PopIn(money, 0.5)
	controllers.EffectsController.Confetti(60)
	controllers.SoundController.Play("Correct")
	task.delay(1.6, function()
		if resultOverlay.Visible then
			DiagnosisController.Close(false)
		end
	end)
end

local function choose(illnessId: string)
	if not current or busy then
		return
	end
	local option
	for _, o in current.Options do
		if o.Id == illnessId then
			option = o
		end
	end
	if not option or option.Removed or option.Wrong then
		return
	end
	busy = true
	local patientId = current.PatientId
	local ok, result = pcall(function()
		return Remotes.Function("SubmitDiagnosis"):InvokeServer(patientId, illnessId)
	end)
	busy = false
	if not current or current.PatientId ~= patientId then
		return
	end
	if not ok or type(result) ~= "table" then
		controllers.NotificationController.Toast("Connection hiccup, try again!", "Error")
		return
	end
	if not result.Ok then
		controllers.NotificationController.Toast(result.Error or "Something went wrong", "Error")
		DiagnosisController.Close(false)
		return
	end
	if result.Correct then
		DiagnosisController.Diagnosed:Fire(result)
		showSuccess(result)
	else
		option.Wrong = true
		current.Misses = result.Misses or (current.Misses + 1)
		local button = optionButtons[illnessId]
		if button then
			UIKit.Shake(button)
		end
		feedbackLabel.Text = "❌ " .. (result.Message or "Not quite! Look at the symptoms again.")
		feedbackLabel.Visible = true
		controllers.SoundController.Play("Wrong")
		refreshOptions()
		setRewardText()
	end
end

local function open(payload: any)
	if type(payload) ~= "table" then
		return
	end
	controllers.ShopController.Close()
	controllers.StatsController.Close()
	current = payload
	current.Misses = current.Misses or 0
	current.OpenMisses = current.Misses
	current.OpenExpert = isExpert(current.UsedHandbook == true, current.Misses)
	hints = nil
	busy = false

	local rarity = Rarities.ById[payload.Rarity] or Rarities.List[1]
	local headerColor = if rarity.Stars >= 2 then rarity.Color else Theme.Colors.Teal
	headerGradient.Color = ColorSequence.new(headerColor, headerColor:Lerp(Color3.new(0, 0, 0), 0.25))
	titleLabel.Text = "🩺 DIAGNOSIS"
	rarityLabel.Text = if rarity.Stars > 0 then stars(rarity.Stars) .. " " .. string.upper(rarity.Name) else ""
	faceLabel.Text = kindFace(payload.Kind, payload.Rarity)
	nameLabel.Text = payload.Name
	local tags = {}
	if payload.Kind == "Emergency" then
		table.insert(tags, "🚨 Emergency (2x pay)")
	elseif payload.Kind == "VIP" then
		table.insert(tags, "👑 VIP (5x pay)")
	elseif payload.Kind == "Child" then
		table.insert(tags, "🧸 Child patient")
	end
	table.insert(tags, payload.DifficultyLabel or "")
	tagLabel.Text = table.concat(tags, "  ·  ")

	for _, child in symptomList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, symptom in payload.Symptoms do
		local pillFrame = UIKit.New("Frame", {
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundColor3 = Color3.fromRGB(255, 236, 236),
			LayoutOrder = index,
			Parent = symptomList,
		}, {
			UIKit.Corner(12),
			UIKit.Stroke(2, Color3.fromRGB(240, 170, 170)),
		})
		UIKit.Label({
			Text = symptom,
			TextSize = 21,
			TextColor3 = Theme.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -20, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			Parent = pillFrame,
		})
	end

	for _, button in optionButtons do
		button:Destroy()
	end
	table.clear(optionButtons)
	table.clear(optionOrder)
	for index, option in payload.Options do
		local button = UIKit.Button({
			Text = "",
			RichText = true,
			Color = Theme.Colors.Blue,
			TextSize = 20,
			LayoutOrder = index,
			Parent = optionsFrame,
			OnClick = function()
				task.spawn(choose, option.Id)
			end,
		})
		local keyHint = UIKit.Label({
			Text = tostring(index),
			TextSize = 14,
			TextColor3 = Color3.fromRGB(220, 235, 255),
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.fromOffset(6, 4),
			ZIndex = 3,
			Parent = button,
		})
		keyHint.Visible = not UserInputService.TouchEnabled
		optionButtons[option.Id] = button
		table.insert(optionOrder, option.Id)
	end

	UIKit.SetButtonText(handbookButton, "📖 Show Handbook")
	UIKit.SetButtonColor(handbookButton, Theme.Colors.Purple)
	labButton.Visible = payload.HasLab and not payload.LabUsed
	feedbackLabel.Visible = false
	resultOverlay.Visible = false
	tipLabel.Visible = payload.Tutorial == true
	refreshOptions()
	setRewardText()

	dim.Visible = true
	panel.Visible = true
	UIKit.PopIn(panel)
	controllers.SoundController.Play("Open")
	DiagnosisController.Opened:Fire(payload)

	if payload.Tutorial or payload.UsedHandbook or (payload.DoctorLevel or 1) <= 1 then
		task.spawn(revealHandbook)
	end
end

function DiagnosisController.Init(all: any)
	controllers = all
	gui = UIKit.New("ScreenGui", {
		Name = "Diagnosis",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = player:WaitForChild("PlayerGui"),
	})
	dim = UIKit.New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Visible = false,
		Parent = gui,
	})

	panel = UIKit.New("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(800, 520),
		BackgroundColor3 = Theme.Colors.Panel,
		Visible = false,
		Parent = gui,
	}, {
		UIKit.Corner(22),
		UIKit.Stroke(4, Theme.Colors.Stroke),
	})
	UIKit.Scaled(panel)

	header = UIKit.New("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = panel,
	}, {
		UIKit.Corner(22),
	})
	headerGradient = UIKit.Gradient(Theme.Colors.Teal, Theme.Colors.TealDark)
	headerGradient.Parent = header
	UIKit.New("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -22),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = header,
	})
	titleLabel = UIKit.Label({
		Text = "🩺 DIAGNOSIS",
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.fromOffset(22, 0),
		Parent = header,
	})
	UIKit.TextStroke(3).Parent = titleLabel
	rarityLabel = UIKit.Label({
		Text = "",
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -74, 0, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		Parent = header,
	})
	UIKit.TextStroke(3).Parent = rarityLabel
	UIKit.Button({
		Text = "✖",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		TextSize = 26,
		Parent = header,
		OnClick = function()
			DiagnosisController.Close(true)
		end,
	})

	-- Left: patient card
	local card = UIKit.New("Frame", {
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.fromOffset(300, 424),
		BackgroundColor3 = Theme.Colors.White,
		Parent = panel,
	}, {
		UIKit.Corner(18),
		UIKit.Stroke(3, Theme.Colors.PanelAlt:Lerp(Theme.Colors.Stroke, 0.25)),
	})
	faceLabel = UIKit.Label({ Text = "🤒", TextSize = 64, Size = UDim2.new(1, 0, 0, 76), Position = UDim2.fromOffset(0, 6), Parent = card })
	nameLabel = UIKit.Label({ Text = "", TextSize = 28, TextColor3 = Theme.Colors.Text, Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 82), Parent = card })
	tagLabel = UIKit.Label({
		Text = "",
		Font = Theme.BodyFont,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextMuted,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 114),
		Parent = card,
	})
	UIKit.Label({ Text = "SYMPTOMS", TextSize = 22, TextColor3 = Theme.Colors.Red, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 140), Parent = card })
	symptomList = UIKit.New("Frame", {
		Position = UDim2.fromOffset(14, 172),
		Size = UDim2.new(1, -28, 1, -182),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		UIKit.List(Enum.FillDirection.Vertical, 8),
	})

	-- Right: options
	local right = UIKit.New("Frame", {
		Position = UDim2.fromOffset(332, 80),
		Size = UDim2.fromOffset(452, 424),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIKit.Label({
		Text = "What's the diagnosis?",
		TextSize = 28,
		TextColor3 = Theme.Colors.Text,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = right,
	})
	optionsFrame = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 270),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = right,
	}, {
		UIKit.Padding(6, 6),
	})
	optionsGrid = UIKit.New("UIGridLayout", {
		CellSize = UDim2.fromOffset(204, 74),
		CellPadding = UDim2.fromOffset(14, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = optionsFrame,
	})

	local tools = UIKit.New("Frame", {
		Position = UDim2.fromOffset(0, 318),
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		Parent = right,
	}, {
		UIKit.List(Enum.FillDirection.Horizontal, 12),
	})
	handbookButton = UIKit.Button({
		Text = "📖 Show Handbook",
		Color = Theme.Colors.Purple,
		Size = UDim2.fromOffset(210, 48),
		TextSize = 20,
		LayoutOrder = 1,
		Parent = tools,
		OnClick = function()
			task.spawn(revealHandbook)
		end,
	})
	labButton = UIKit.Button({
		Text = "🧪 Lab Test",
		Color = Theme.Colors.Teal,
		Size = UDim2.fromOffset(170, 48),
		TextSize = 20,
		LayoutOrder = 2,
		Parent = tools,
		OnClick = function()
			task.spawn(useLab)
		end,
	})
	rewardLabel = UIKit.Label({
		Text = "",
		TextSize = 19,
		TextColor3 = Theme.Colors.GreenDark,
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 380),
		Parent = right,
	})
	feedbackLabel = UIKit.Label({
		Text = "",
		TextSize = 20,
		TextColor3 = Theme.Colors.Red,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 404),
		Visible = false,
		Parent = right,
	})
	tipLabel = UIKit.Label({
		Text = "💡 Find the illness whose symptoms match the patient's! (matching symptoms glow yellow)",
		TextSize = 17,
		TextWrapped = true,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Yellow,
		TextColor3 = Theme.Colors.Text,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromOffset(620, 44),
		Visible = false,
		Parent = panel,
	})
	UIKit.Corner(12).Parent = tipLabel
	UIKit.Stroke(3, Theme.Colors.Stroke).Parent = tipLabel

	-- Success overlay
	resultOverlay = UIKit.New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 10,
		Parent = panel,
	}, {
		UIKit.Corner(22),
	})
	local stamp = UIKit.Label({
		Name = "Stamp",
		Text = "✅ CORRECT DIAGNOSIS!",
		TextSize = 52,
		TextColor3 = Theme.Colors.Green,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(760, 80),
		ZIndex = 11,
		Parent = resultOverlay,
	})
	UIKit.TextStroke(4).Parent = stamp
	local money = UIKit.Label({
		Name = "Money",
		Text = "+$0",
		TextSize = 64,
		TextColor3 = Theme.Colors.Money,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromOffset(500, 80),
		ZIndex = 11,
		Parent = resultOverlay,
	})
	UIKit.TextStroke(4).Parent = money
	UIKit.Label({
		Name = "Details",
		Text = "",
		TextSize = 24,
		TextColor3 = Theme.Colors.Text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromOffset(700, 40),
		ZIndex = 11,
		Parent = resultOverlay,
	})
end

function DiagnosisController.Start()
	Remotes.Event("OpenDiagnosis").OnClientEvent:Connect(open)
	Remotes.Event("CloseDiagnosis").OnClientEvent:Connect(function(reason: any)
		if current and not resultOverlay.Visible then
			if reason == "far" then
				controllers.NotificationController.Toast("You walked away from your patient.", "Info")
			end
			DiagnosisController.Close(false)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not current or resultOverlay.Visible then
			return
		end
		local index = table.find(KEYCODES, input.KeyCode)
		if index and optionOrder[index] then
			task.spawn(choose, optionOrder[index])
		elseif input.KeyCode == Enum.KeyCode.H then
			task.spawn(revealHandbook)
		end
	end)
	player.CharacterAdded:Connect(function()
		DiagnosisController.Close(true)
	end)
end

return DiagnosisController
