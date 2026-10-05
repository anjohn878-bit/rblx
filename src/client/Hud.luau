-- The on-screen interface: cash and rank, the current objective with a direction arrow, the
-- list of parcels on board, garage/vehicle buttons, a speedometer, toasts and the rank-up banner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local UI = require(script.Parent.UI)

local Hud = {}

export type Options = {
	onGarage: () -> (),
	onSpawn: () -> (),
	onSelectJob: (number?) -> (),
	getTarget: () -> any,
	getSelectedId: () -> number?,
	isDriving: () -> boolean,
	getSpeed: () -> number,
}

local COLORS = Config.Colors
local ROW_HEIGHT = 48
local MAX_VISIBLE_ROWS = 4
local MAX_TOASTS = 4

local player = Players.LocalPlayer
local options: Options
local gui: ScreenGui
local canvas: Frame -- everything lives in here so it can be scaled down on small screens
local lastViewport = Vector2.zero
local refs: { [string]: any } = {}
local rows: { [number]: { Button: TextButton, Sub: TextLabel, Stroke: UIStroke, Job: any } } = {}
local toastCount = 0
local bannerToken = 0

local function panel(props: { [string]: any }): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or COLORS.Navy
	props.BackgroundTransparency = props.BackgroundTransparency or 0.12
	props.Parent = props.Parent or canvas
	return UI.new("Frame", props, { UI.corner(12) })
end

local function characterPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function timerText(deadline: number?): string
	if not deadline then
		return ""
	end
	local left = deadline - Workspace:GetServerTimeNow()
	if left > 0 then
		return "⏱ " .. Format.clock(left)
	end
	return "no bonus"
end

local function buildStats()
	local stats = panel({ Name = "Stats", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(220, 92) })
	UI.padding(10).Parent = stats
	refs.Cash = UI.label({
		Size = UDim2.new(1, 0, 0, 32),
		Font = Enum.Font.FredokaOne,
		TextSize = 30,
		TextColor3 = COLORS.Money,
		Text = "$0",
		Parent = stats,
	})
	refs.Rank = UI.label({
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Text = "Trainee",
		Parent = stats,
	})
	local bar = UI.new("Frame", {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = COLORS.NavyLight,
		Parent = stats,
	}, { UI.corner(4) })
	refs.RankFill = UI.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.Brand,
		Parent = bar,
	}, { UI.corner(4) })
	refs.RankProgress = UI.label({
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 14),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = COLORS.Muted,
		Parent = stats,
	})
end

local function buildObjective()
	local objective = panel({
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0.38, 0, 0, 56),
	})
	UI.new("UISizeConstraint", { MinSize = Vector2.new(250, 56), MaxSize = Vector2.new(440, 56), Parent = objective })
	refs.Arrow = UI.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 28, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		Font = Enum.Font.GothamBold,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = COLORS.Brand,
		Text = "▲",
		Parent = objective,
	})
	refs.ObjectiveTitle = UI.label({
		Position = UDim2.fromOffset(54, 8),
		Size = UDim2.new(1, -64, 0, 22),
		Font = Enum.Font.FredokaOne,
		TextSize = 19,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Clocking in...",
		Parent = objective,
	})
	refs.ObjectiveSub = UI.label({
		Position = UDim2.fromOffset(54, 31),
		Size = UDim2.new(1, -64, 0, 18),
		TextSize = 14,
		TextColor3 = COLORS.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = objective,
	})
end

local function buildPackages()
	local packages = panel({
		Name = "Packages",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	UI.padding(10).Parent = packages
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = packages })
	refs.PackagesTitle = UI.label({
		Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.FredokaOne,
		TextSize = 18,
		Text = "Packages",
		LayoutOrder = 0,
		Parent = packages,
	})
	refs.PackageList = UI.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = packages,
	}, { UI.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	refs.PackagesEmpty = UI.label({
		Size = UDim2.new(1, 0, 0, 34),
		TextWrapped = true,
		TextSize = 13,
		TextColor3 = COLORS.Muted,
		Text = "No packages yet. Load up at the depot counter!",
		LayoutOrder = 2,
		Parent = packages,
	})
end

local function buildButtons()
	local holder = UI.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(160, 100),
		BackgroundTransparency = 1,
		Parent = canvas,
	}, { UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local keys = UserInputService.KeyboardEnabled
	local garage = UI.button({
		Size = UDim2.new(1, 0, 0, 44),
		Text = if keys then "GARAGE [G]" else "GARAGE",
		BackgroundColor3 = COLORS.NavyLight,
		LayoutOrder = 1,
		Parent = holder,
	})
	garage.Activated:Connect(function()
		options.onGarage()
	end)
	local spawn = UI.button({
		Size = UDim2.new(1, 0, 0, 44),
		Text = if keys then "GET VEHICLE [V]" else "GET VEHICLE",
		BackgroundColor3 = COLORS.Brand,
		LayoutOrder = 2,
		Parent = holder,
	})
	spawn.Activated:Connect(function()
		options.onSpawn()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			options.onGarage()
		elseif input.KeyCode == Enum.KeyCode.V then
			options.onSpawn()
		end
	end)
end

local function buildSpeedometer()
	refs.Speedo = panel({
		Name = "Speedometer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(150, 64),
		Visible = false,
	})
	refs.SpeedValue = UI.label({
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 40),
		Font = Enum.Font.FredokaOne,
		TextSize = 36,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "0",
		Parent = refs.Speedo,
	})
	UI.label({
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 16),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "MPH",
		Parent = refs.Speedo,
	})
end

local function buildToastsAndBanner()
	refs.Toasts = UI.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.new(0.5, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = canvas,
	}, {
		UI.new("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local banner = UI.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(0.8, 0, 0, 116),
		BackgroundColor3 = COLORS.Brand,
		Visible = false,
		Parent = canvas,
	}, {
		UI.corner(16),
		UI.stroke(COLORS.White, 3),
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(540, 116) }),
	})
	refs.Banner = banner
	refs.BannerScale = UI.new("UIScale", { Scale = 1, Parent = banner })
	refs.BannerTitle = UI.label({
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 48),
		Font = Enum.Font.FredokaOne,
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Parent = banner,
	})
	refs.BannerText = UI.label({
		Position = UDim2.fromOffset(16, 60),
		Size = UDim2.new(1, -32, 0, 44),
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = banner,
	})
end

function Hud.toast(text: string, kind: string?)
	local accent = ({
		success = COLORS.Money,
		delivered = COLORS.Money,
		error = COLORS.Danger,
		rank = COLORS.Brand,
	})[kind or ""] or COLORS.Muted

	toastCount += 1
	local toast = UI.new("Frame", {
		Size = UDim2.new(),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = COLORS.Navy,
		BackgroundTransparency = 0.08,
		LayoutOrder = toastCount,
		Parent = refs.Toasts,
	}, { UI.corner(10), UI.padding(10) })
	local stroke = UI.stroke(accent, 2)
	stroke.Parent = toast
	local label = UI.label({
		Size = UDim2.new(),
		AutomaticSize = Enum.AutomaticSize.XY,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = text,
		Parent = toast,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge), Parent = label })

	local existing = {}
	for _, child in refs.Toasts:GetChildren() do
		if child:IsA("Frame") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #existing - MAX_TOASTS do
		existing[i]:Destroy()
	end

	task.delay(4, function()
		if not toast.Parent then
			return
		end
		local info = TweenInfo.new(0.4)
		TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		task.wait(0.45)
		toast:Destroy()
	end)
end

function Hud.banner(title: string, text: string)
	bannerToken += 1
	local token = bannerToken
	refs.BannerTitle.Text = title
	refs.BannerText.Text = text
	refs.Banner.Visible = true
	refs.BannerScale.Scale = 0.5
	TweenService:Create(refs.BannerScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(4.5, function()
		if token ~= bannerToken then
			return
		end
		local shrink = TweenService:Create(refs.BannerScale, TweenInfo.new(0.25), { Scale = 0 })
		shrink:Play()
		shrink.Completed:Wait()
		if token == bannerToken then
			refs.Banner.Visible = false
		end
	end)
end

local function rebuildRows(state)
	for _, row in rows do
		row.Button:Destroy()
	end
	table.clear(rows)

	for index, job in state.Jobs do
		local color = Config.PackageKinds[1].Color
		local kindName = "Standard"
		for _, kind in Config.PackageKinds do
			if kind.Id == job.Kind then
				color, kindName = kind.Color, kind.Name
			end
		end
		local button = UI.new("TextButton", {
			Size = UDim2.new(1, -6, 0, ROW_HEIGHT),
			BackgroundColor3 = COLORS.NavyLight,
			AutoButtonColor = true,
			Text = "",
			LayoutOrder = index,
			Parent = refs.PackageList,
		}, { UI.corner(8) })
		local stroke = UI.stroke(COLORS.Brand, 2)
		stroke.Enabled = false
		stroke.Parent = button
		UI.new("Frame", {
			Position = UDim2.fromOffset(6, 8),
			Size = UDim2.new(0, 5, 1, -16),
			BackgroundColor3 = color,
			Parent = button,
		}, { UI.corner(3) })
		UI.label({
			Position = UDim2.fromOffset(18, 5),
			Size = UDim2.new(1, -24, 0, 20),
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = (if kindName ~= "Standard" then "[" .. string.upper(kindName) .. "] " else "") .. (job.Name or job.Address),
			Parent = button,
		})
		local sub = UI.label({
			Position = UDim2.fromOffset(18, 25),
			Size = UDim2.new(1, -24, 0, 16),
			TextSize = 12,
			TextColor3 = COLORS.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = button,
		})
		button.Activated:Connect(function()
			options.onSelectJob(job.Id)
		end)
		rows[job.Id] = { Button = button, Sub = sub, Stroke = stroke, Job = job }
	end

	local visible = math.min(#state.Jobs, MAX_VISIBLE_ROWS)
	refs.PackageList.Size = UDim2.new(1, 0, 0, visible * (ROW_HEIGHT + 6))
	refs.PackagesEmpty.Visible = #state.Jobs == 0
end

function Hud.update(state)
	refs.Cash.Text = Format.money(state.Cash)
	refs.Rank.Text = state.RankName
	refs.Rank.TextColor3 = Config.Ranks[state.RankIndex].Color
	if state.NextRankAt then
		local span = state.NextRankAt - state.RankFloor
		local done = state.Deliveries - state.RankFloor
		refs.RankFill.Size = UDim2.fromScale(math.clamp(done / span, 0, 1), 1)
		refs.RankProgress.Text = string.format("%d / %d deliveries to %s", state.Deliveries, state.NextRankAt, state.NextRankName)
	else
		refs.RankFill.Size = UDim2.fromScale(1, 1)
		refs.RankProgress.Text = string.format("Top rank! %s deliveries", Format.commas(state.Deliveries))
	end
	refs.PackagesTitle.Text = string.format("Packages %d/%d", #state.Jobs, state.Capacity)
	rebuildRows(state)
end

-- Lay the HUD out on a virtual canvas at least 1000x600 and scale it to fit, so phones get
-- a smaller HUD instead of overlapping panels.
local function fitToScreen()
	local camera = Workspace.CurrentCamera
	if not camera or camera.ViewportSize == lastViewport then
		return
	end
	lastViewport = camera.ViewportSize
	local scale = math.clamp(math.min(lastViewport.X / 1000, lastViewport.Y / 600), 0.55, 1)
	refs.Scale.Scale = scale
	canvas.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

-- Per-frame refresh of everything that depends on where the player is.
function Hud.tick(state)
	fitToScreen()
	if not state then
		return
	end
	local origin = characterPosition()
	local target = options.getTarget()
	local driving = options.isDriving()

	if target then
		local distance = if origin then flatDistance(origin, target.Position) else 0
		if #state.Jobs == 0 then
			refs.ObjectiveTitle.Text = "Load packages at the depot"
			refs.ObjectiveSub.Text = if distance > 20
				then Format.distance(distance) .. " away. Follow the orange beacon!"
				else "Press E at the Package Counter"
		else
			refs.ObjectiveTitle.Text = "Deliver to " .. target.Title
			local timer = timerText(target.Deadline)
			if driving and distance < 30 then
				refs.ObjectiveSub.Text = "You're here! Hop out (Space) and walk to the door."
			else
				refs.ObjectiveSub.Text = Format.distance(distance) .. (if timer ~= "" then "  ·  " .. timer else "")
			end
		end
		refs.Arrow.TextColor3 = target.Color

		local camera = Workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			local toTarget = target.Position - camera.CFrame.Position
			local flatTo = Vector3.new(toTarget.X, 0, toTarget.Z)
			if flatLook.Magnitude > 1e-3 and flatTo.Magnitude > 1e-3 then
				flatLook, flatTo = flatLook.Unit, flatTo.Unit
				local angle = math.atan2(flatLook:Cross(flatTo).Y, flatLook:Dot(flatTo))
				refs.Arrow.Rotation = -math.deg(angle)
			end
		end
	end

	local selected = options.getSelectedId()
	for id, row in rows do
		local job = row.Job
		local parts = {}
		if origin then
			table.insert(parts, Format.distance(flatDistance(origin, job.Position)))
		end
		table.insert(parts, Format.money(job.Reward))
		table.insert(parts, timerText(job.Deadline))
		row.Sub.Text = table.concat(parts, "  ·  ")
		row.Stroke.Enabled = id == selected
	end

	refs.Speedo.Visible = driving
	if driving then
		refs.SpeedValue.Text = Format.speed(options.getSpeed())
	end
end

function Hud.init(opts: Options)
	options = opts
	gui = UI.new("ScreenGui", {
		Name = "DeliveryHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	canvas = UI.new("Frame", {
		Name = "Canvas",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	refs.Scale = UI.new("UIScale", { Parent = canvas })
	fitToScreen()
	buildStats()
	buildObjective()
	buildPackages()
	buildButtons()
	buildSpeedometer()
	buildToastsAndBanner()
end

return Hud
