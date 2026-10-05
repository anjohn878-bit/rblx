--[[
	NotificationController
	Small toasts (stacked under the HUD) and big centre banners for exciting
	moments (rare patients, upgrades, level ups).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local NotificationController = {}

local controllers: any = nil
local toastHolder: Frame
local bannerHolder: Frame
local bannerQueue = {}
local bannerBusy = false

local STYLE_COLORS = {
	Info = Theme.Colors.Blue,
	Success = Theme.Colors.Green,
	Error = Theme.Colors.Red,
	Rare = Theme.Colors.Purple,
	Big = Theme.Colors.Yellow,
}

function NotificationController.Init(all: any)
	controllers = all
	local gui = UIKit.New("ScreenGui", {
		Name = "Notifications",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	toastHolder = UIKit.New("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 168),
		Size = UDim2.fromOffset(520, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UIKit.List(Enum.FillDirection.Vertical, 6),
	})
	UIKit.Scaled(toastHolder)

	bannerHolder = UIKit.New("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(640, 150),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.Scaled(bannerHolder)
end

function NotificationController.Toast(text: string, style: string?)
	local color = STYLE_COLORS[style or "Info"] or Theme.Colors.Blue
	local toast = UIKit.New("Frame", {
		Size = UDim2.fromOffset(500, 44),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.05,
		LayoutOrder = math.floor(os.clock() * 100),
		Parent = toastHolder,
	}, {
		UIKit.Corner(12),
		UIKit.Stroke(3, color),
	})
	local label = UIKit.Label({
		Text = text,
		TextSize = 19,
		TextWrapped = true,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Parent = toast,
	})
	-- Grow for long text
	if #text > 52 then
		toast.Size = UDim2.fromOffset(500, 66)
	end
	UIKit.PopIn(toast, 0.25)

	local children = {}
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	if #children > 4 then
		table.sort(children, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		children[1]:Destroy()
	end

	task.delay(4, function()
		if toast.Parent then
			UIKit.Tween(toast, 0.3, { BackgroundTransparency = 1 })
			UIKit.Tween(label, 0.3, { TextTransparency = 1 })
			local stroke = toast:FindFirstChildOfClass("UIStroke")
			if stroke then
				UIKit.Tween(stroke, 0.3, { Transparency = 1 })
			end
			task.wait(0.35)
			toast:Destroy()
		end
	end)
end

local function showNextBanner()
	if bannerBusy or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local notice = table.remove(bannerQueue, 1)
	local color = notice.Color or STYLE_COLORS[notice.Style or "Big"] or Theme.Colors.Yellow

	local frame = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 130),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = bannerHolder,
	}, {
		UIKit.Corner(22),
		UIKit.Stroke(5, color),
	})
	local title = UIKit.Label({
		Text = notice.Title or "",
		TextSize = 44,
		TextColor3 = color,
		Size = UDim2.new(1, -20, 0, 60),
		Position = UDim2.fromOffset(10, 8),
		Parent = frame,
	})
	UIKit.TextStroke(3).Parent = title
	UIKit.Label({
		Text = notice.Text or "",
		TextSize = 21,
		TextWrapped = true,
		Size = UDim2.new(1, -40, 0, 54),
		Position = UDim2.fromOffset(20, 66),
		Parent = frame,
	})
	UIKit.PopIn(frame, 0.45)
	if notice.Style == "Rare" then
		controllers.SoundController.Play("Rare")
	end

	task.delay(3.2, function()
		UIKit.Tween(frame, 0.35, { Position = UDim2.fromScale(0.5, -0.6) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.4)
		frame:Destroy()
		bannerBusy = false
		showNextBanner()
	end)
end

function NotificationController.Banner(notice: { [string]: any })
	table.insert(bannerQueue, notice)
	if #bannerQueue > 3 then
		table.remove(bannerQueue, 1)
	end
	showNextBanner()
end

function NotificationController.Start()
	Remotes.Event("Notify").OnClientEvent:Connect(function(notice: any)
		if type(notice) ~= "table" then
			return
		end
		if notice.Style == "Rare" or notice.Style == "Big" then
			NotificationController.Banner(notice)
		else
			NotificationController.Toast(notice.Text or notice.Title or "", notice.Style)
		end
	end)
end

return NotificationController
