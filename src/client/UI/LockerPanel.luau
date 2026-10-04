--[[
	LockerPanel
	Customization + shop in one: browse every category, preview the item on a live
	copy of your character, then buy (server-validated) and equip.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.UIKit)

local T = UIKit.Theme
local new = UIKit.new

local LockerPanel = {}

local player = Players.LocalPlayer
local frame: Frame
local refs = {}
local category = "Shirt"
local selectedId: string? = nil
local preview: Model? = nil
local previewEquipped = {}
local spinConnection: RBXScriptConnection? = nil
local busy = false

local function tierAllows(item, profile): boolean
	if not item.RequiredTier then
		return true
	end
	local index = Progression.GetReputationTier(profile.Reputation)
	return index >= Progression.TierIndexByName(item.RequiredTier)
end

local function rebuildPreview()
	local viewport = refs.Viewport :: ViewportFrame
	if preview then
		preview:Destroy()
		preview = nil
	end
	local character = player.Character
	if not character then
		return
	end
	character.Archivable = true
	local clone = character:Clone()
	if not clone then
		return
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	clone:PivotTo(CFrame.new(0, 0, 0))
	Cosmetics.Apply(clone, previewEquipped, nil)
	clone.Parent = refs.WorldModel
	preview = clone

	local cam = viewport.CurrentCamera or Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.5, -13), Vector3.new(0, 0, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam
end

local function updateActionBar()
	local profile = ClientState.Profile
	local item = selectedId and Catalog.Get(selectedId)
	if not profile or not item then
		refs.ItemName.Text = "Select an item"
		refs.ItemInfo.Text = ""
		refs.Action.Visible = false
		return
	end
	refs.ItemName.Text = item.Name
	refs.Action.Visible = true
	local owned = profile.Inventory[item.Id] == true
	local equipped = profile.Equipped[item.Category] == item.Id
	if equipped then
		refs.ItemInfo.Text = "Equipped"
		refs.Action.Text = "EQUIPPED"
		refs.Action.BackgroundColor3 = T.PanelLight
	elseif owned then
		refs.ItemInfo.Text = "Owned"
		refs.Action.Text = "EQUIP"
		refs.Action.BackgroundColor3 = T.Accent
		refs.Action.TextColor3 = T.AccentDark
	elseif not tierAllows(item, profile) then
		refs.ItemInfo.Text = "Unlocks at reputation: " .. item.RequiredTier
		refs.Action.Text = "LOCKED"
		refs.Action.BackgroundColor3 = T.PanelLight
		refs.Action.TextColor3 = T.Muted
	else
		refs.ItemInfo.Text = string.format("◆ %s %s", UIKit.FormatNumber(item.Price), Config.CurrencyName)
		local affordable = profile.Kicks >= item.Price
		refs.Action.Text = if affordable then "BUY" else "NEED MORE KICKS"
		refs.Action.BackgroundColor3 = if affordable then T.Gold else T.PanelLight
		refs.Action.TextColor3 = if affordable then T.AccentDark else T.Muted
	end
	if equipped then
		refs.Action.TextColor3 = T.Muted
	end
end

local function populateGrid()
	local grid = refs.Grid :: ScrollingFrame
	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local profile = ClientState.Profile
	for i, item in Catalog.ByCategory[category] do
		local owned = profile and profile.Inventory[item.Id]
		local isEquipped = profile and profile.Equipped[item.Category] == item.Id
		local locked = profile and not owned and not tierAllows(item, profile)
		local tile = UIKit.Button({
			Text = "",
			LayoutOrder = i,
			BackgroundColor3 = if selectedId == item.Id then T.Stroke else T.PanelLight,
			Parent = grid,
		}, function()
			selectedId = item.Id
			previewEquipped[item.Category] = item.Id
			rebuildPreview()
			populateGrid()
			updateActionBar()
		end)
		new("Frame", {
			Size = UDim2.new(1, -20, 0, 54),
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = item.Color,
			Parent = tile,
		}, { UIKit.Corner(8) })
		UIKit.Label({
			Size = UDim2.new(1, -12, 0, 30),
			Position = UDim2.fromOffset(6, 66),
			Text = item.Name,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = T.Bold,
			TextSize = 12,
			Parent = tile,
		})
		UIKit.Label({
			Size = UDim2.new(1, -12, 0, 16),
			Position = UDim2.fromOffset(6, 98),
			Text = if isEquipped then "EQUIPPED" elseif owned then "OWNED" elseif locked then ("🔒 " .. item.RequiredTier) else ("◆ " .. UIKit.FormatNumber(item.Price)),
			TextColor3 = if isEquipped then T.Accent elseif owned then T.Muted elseif locked then T.Danger else T.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = T.Heavy,
			TextSize = 12,
			Parent = tile,
		})
	end
end

local function selectCategory(name: string)
	category = name
	selectedId = nil
	for catName, tab in refs.Tabs do
		tab.BackgroundColor3 = if catName == name then T.Accent else T.PanelLight
		tab.TextColor3 = if catName == name then T.AccentDark else T.Text
	end
	populateGrid()
	updateActionBar()
end

local function onAction()
	if busy or not selectedId then
		return
	end
	local profile = ClientState.Profile
	local item = Catalog.Get(selectedId)
	if not profile or not item then
		return
	end
	busy = true
	local remoteName = if profile.Inventory[item.Id] then "EquipItem" else "PurchaseItem"
	local ok, result, message = pcall(function()
		return Remotes.Get(remoteName):InvokeServer(item.Id)
	end)
	busy = false
	refs.Status.Text = if ok then (message or "") else "Something went wrong"
	refs.Status.TextColor3 = if ok and result then T.Accent else T.Danger
	-- Buying immediately equips for a smoother flow
	if ok and result and remoteName == "PurchaseItem" then
		pcall(function()
			Remotes.Get("EquipItem"):InvokeServer(item.Id)
		end)
	end
end

function LockerPanel.Create(gui: ScreenGui, close: () -> ())
	frame = UIKit.Panel({
		Name = "Locker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(860, 540),
		Visible = false,
		Parent = gui,
	})
	new("UISizeConstraint", { MaxSize = Vector2.new(860, 540), Parent = frame })
	UIKit.Label({
		Size = UDim2.new(1, -40, 0, 40),
		Position = UDim2.fromOffset(20, 12),
		Text = "THE LOCKER",
		Font = T.Heavy,
		TextSize = 28,
		Parent = frame,
	})
	UIKit.Button({
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -52, 0, 12),
		Text = "✕",
		Parent = frame,
	}, close)

	-- Preview
	local previewBox = new("Frame", {
		Size = UDim2.new(0, 260, 1, -80),
		Position = UDim2.fromOffset(20, 64),
		BackgroundColor3 = T.Bg,
		Parent = frame,
	}, { UIKit.Corner(12) })
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(40, 46, 30), Color3.fromRGB(14, 15, 19)),
		Rotation = 90,
		Parent = previewBox,
	})
	local viewport = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(180, 180, 190),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = previewBox,
	})
	refs.Viewport = viewport
	refs.WorldModel = new("WorldModel", { Parent = viewport })

	-- Category tabs
	local tabs = new("Frame", {
		Size = UDim2.new(1, -320, 0, 36),
		Position = UDim2.fromOffset(300, 64),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { UIKit.List(Enum.FillDirection.Horizontal, 6) })
	refs.Tabs = {}
	for i, cat in Catalog.Categories do
		refs.Tabs[cat] = UIKit.Button({
			Size = UDim2.fromOffset(84, 36),
			Text = string.upper(cat),
			TextSize = 13,
			LayoutOrder = i,
			Parent = tabs,
		}, function()
			selectCategory(cat)
		end)
	end

	local grid = new("ScrollingFrame", {
		Size = UDim2.new(1, -320, 1, -200),
		Position = UDim2.fromOffset(300, 110),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(120, 120), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.Grid = grid

	-- Action bar
	local bar = new("Frame", {
		Size = UDim2.new(1, -320, 0, 70),
		Position = UDim2.new(0, 300, 1, -84),
		BackgroundColor3 = T.Bg,
		Parent = frame,
	}, { UIKit.Corner(12) })
	refs.ItemName = UIKit.Label({ Size = UDim2.new(1, -220, 0, 24), Position = UDim2.fromOffset(14, 8), Font = T.Heavy, TextSize = 18, Text = "", Parent = bar })
	refs.ItemInfo = UIKit.Label({ Size = UDim2.new(1, -220, 0, 18), Position = UDim2.fromOffset(14, 32), TextColor3 = T.Gold, Font = T.Bold, TextSize = 14, Text = "", Parent = bar })
	refs.Status = UIKit.Label({ Size = UDim2.new(1, -220, 0, 14), Position = UDim2.fromOffset(14, 50), TextColor3 = T.Muted, Font = T.Medium, TextSize = 12, Text = "", Parent = bar })
	refs.Action = UIKit.Button({
		Size = UDim2.fromOffset(190, 46),
		Position = UDim2.new(1, -202, 0.5, -23),
		Text = "BUY",
		TextSize = 16,
		Parent = bar,
	}, onAction)

	ClientState.Changed:Connect(function()
		if frame.Visible then
			populateGrid()
			updateActionBar()
		end
	end)
end

function LockerPanel.Open()
	local profile = ClientState.Profile
	previewEquipped = profile and table.clone(profile.Equipped) or Catalog.DefaultEquipped()
	frame.Visible = true
	refs.Status.Text = ""
	selectCategory(category)
	rebuildPreview()
	if not spinConnection then
		local angle = 0
		spinConnection = RunService.RenderStepped:Connect(function(dt)
			if preview and preview.Parent then
				angle += dt * 0.6
				preview:PivotTo(CFrame.Angles(0, angle, 0))
			end
		end)
	end
end

function LockerPanel.Close()
	frame.Visible = false
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
	if preview then
		preview:Destroy()
		preview = nil
	end
end

return LockerPanel
