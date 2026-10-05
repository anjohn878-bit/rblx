-- Breeding: pick two grown-up birds of the same kind, put them in a nest and
-- wait for the egg to hatch. Also lists the families you've started.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared.Birds)
local Config = require(Shared.Config)
local Pets = require(Shared.Pets)
local Rarities = require(Shared.Rarities)
local Util = require(Shared.Util)
local Actions = require(script.Parent.Actions)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local NestWindow = {}

local window, body, headerInfo
local nestRows = {}
local pickGrid, startButton, familyLabel, pickHint
local selected = {}
local targetNest

local function section(order, text)
	return UI.label({
		LayoutOrder = order,
		Text = text,
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Wood,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -8, 0, 24),
		Parent = body,
	})
end

local function selectedSpecies(data)
	local first = selected[1] and data.Pets[selected[1]]
	return first and first.Species
end

local function togglePick(petId)
	local data = Store.Data
	local pet = data and data.Pets[petId]
	if not pet then
		return
	end
	local index = table.find(selected, petId)
	if index then
		table.remove(selected, index)
	elseif selectedSpecies(data) and selectedSpecies(data) ~= pet.Species then
		selected = { petId }
	elseif #selected >= 2 then
		selected[2] = petId
	else
		table.insert(selected, petId)
	end
	NestWindow.Refresh()
end

-- Adult birds that can breed, only kinds you have at least two of.
local function candidates(data, now)
	local bySpecies = {}
	for id, pet in pairs(data.Pets) do
		if not pet.Nest and not Pets.IsBaby(pet, now) then
			bySpecies[pet.Species] = bySpecies[pet.Species] or {}
			table.insert(bySpecies[pet.Species], id)
		end
	end
	local list = {}
	for species, ids in pairs(bySpecies) do
		if #ids >= 2 then
			for _, id in ipairs(ids) do
				table.insert(list, { Id = id, Pet = data.Pets[id], Def = Birds.Get(species) })
			end
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Rarities.Rank(a.Def.Rarity), Rarities.Rank(b.Def.Rarity)
		if ra ~= rb then
			return ra > rb
		elseif a.Pet.Species ~= b.Pet.Species then
			return a.Pet.Species < b.Pet.Species
		elseif (a.Pet.Stars or 1) ~= (b.Pet.Stars or 1) then
			return (a.Pet.Stars or 1) > (b.Pet.Stars or 1)
		end
		return a.Id < b.Id
	end)
	return list
end

local function familySummary(data)
	local families = {}
	local order = {}
	for _, pet in pairs(data.Pets) do
		if pet.Family then
			local family = families[pet.Family]
			if not family then
				family = { Count = 0, Generation = 0, Kinds = {} }
				families[pet.Family] = family
				table.insert(order, pet.Family)
			end
			family.Count += 1
			family.Generation = math.max(family.Generation, pet.Generation or 0)
			family.Kinds[Birds.Get(pet.Species).Name] = true
		end
	end
	if #order == 0 then
		return "No families yet. Hatch an egg to start one!"
	end
	table.sort(order)
	local lines = {}
	for _, name in ipairs(order) do
		local family = families[name]
		local kinds = {}
		for kind in pairs(family.Kinds) do
			table.insert(kinds, kind)
		end
		table.sort(kinds)
		table.insert(
			lines,
			"🏡 The "
				.. name
				.. " family: "
				.. family.Count
				.. " birds ("
				.. table.concat(kinds, ", ")
				.. "), "
				.. (family.Generation + 1)
				.. " generations"
		)
	end
	return table.concat(lines, "\n")
end

local function refreshNests(data, now)
	local busy = 0
	for index, row in ipairs(nestRows) do
		local entry = data.Nests[tostring(index)]
		if entry then
			busy += 1
			local a, b = data.Pets[entry.ParentA], data.Pets[entry.ParentB]
			local parents = (a and a.Name or "?") .. " & " .. (b and b.Name or "?")
			local remaining = entry.HatchAt - now
			local timer = entry.Waiting and "ready! Make room in your aviary"
				or (remaining > 0 and ("hatches in " .. Util.FormatTime(remaining)) or "hatching...")
			row.Label.Text = "Nest "
				.. index
				.. ":  🥚 "
				.. Birds.Get(entry.Species).Name
				.. " egg from "
				.. parents
				.. "  •  "
				.. timer
			row.Cancel.Visible = true
		else
			row.Label.Text = "Nest " .. index .. ":  🪺 empty" .. (targetNest == index and "  (you're here)" or "")
			row.Cancel.Visible = false
		end
	end
	headerInfo.Text = busy .. "/" .. Config.NestCount .. " nests busy"
	return busy
end

function NestWindow.Refresh()
	if not window or not window.Visible then
		return
	end
	local data = Store.Data
	if not data then
		return
	end
	local now = Store.Now()
	local busy = refreshNests(data, now)

	-- candidates
	for i = #selected, 1, -1 do
		local pet = data.Pets[selected[i]]
		if not pet or pet.Nest or Pets.IsBaby(pet, now) then
			table.remove(selected, i)
		end
	end
	for _, child in ipairs(pickGrid:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local list = candidates(data, now)
	for order, entry in ipairs(list) do
		local isSelected = table.find(selected, entry.Id) ~= nil
		local button = UI.button({
			LayoutOrder = order,
			Text = "",
			BackgroundColor3 = isSelected and Color3.fromRGB(210, 245, 190) or UI.Colors.Panel,
			Parent = pickGrid,
		}, function()
			togglePick(entry.Id)
		end)
		UI.stroke(isSelected and UI.Colors.Green or Rarities.Color(entry.Def.Rarity), isSelected and 4 or 2).Parent =
			button
		UI.label({
			Text = (entry.Pet.Shiny and "✨" or "") .. entry.Pet.Name .. " " .. Pets.StarText(entry.Pet.Stars),
			Font = UI.TitleFont,
			TextColor3 = Rarities.Color(entry.Def.Rarity),
			TextStrokeTransparency = 0.7,
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 22),
			Parent = button,
		})
		UI.label({
			Text = entry.Def.Name .. (entry.Pet.Equipped and "  •  out" or ""),
			TextColor3 = UI.Colors.SubText,
			Position = UDim2.fromOffset(6, 28),
			Size = UDim2.new(1, -12, 0, 16),
			Parent = button,
		})
	end
	pickHint.Text = #list == 0
			and "You need two grown-up birds of the same kind. Befriend more birds, or wait for babies to grow up!"
		or "Babies get their parents' stars (sometimes one more ⭐). Shiny parents often have shiny babies!"

	local species = selectedSpecies(data)
	if #selected == 2 and species then
		startButton.Text = "🥚 Start a nest  (hatches in " .. Util.FormatTime(Pets.BreedTime(species)) .. ")"
		startButton.BackgroundColor3 = busy < Config.NestCount and UI.Colors.Green or UI.Colors.Grey
	else
		startButton.Text = "Pick two birds of the same kind"
		startButton.BackgroundColor3 = UI.Colors.Grey
	end

	familyLabel.Text = familySummary(data)
end

function NestWindow.Init(screenGui)
	window, body, headerInfo = UI.window(screenGui, "🥚 Nests & Families", function()
		NestWindow.Close()
	end)
	UI.new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = body,
	})
	UI.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = body })

	section(1, "Your nests")
	for index = 1, Config.NestCount do
		local row = UI.new("Frame", {
			LayoutOrder = 1 + index,
			Size = UDim2.new(1, -8, 0, 40),
			BackgroundColor3 = UI.Colors.PanelDark,
			Parent = body,
		}, { UI.corner(10) })
		local label = UI.label({
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -110, 1, -8),
			Parent = row,
		})
		-- cancelling throws the egg away, so it needs a second tap
		local cancel = UI.confirmButton({
			BackgroundColor3 = UI.Colors.Red,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(90, 30),
			Parent = row,
		}, function()
			return "Cancel"
		end, function()
			Actions.Pet("CancelNest", index)
		end, function()
			return "Lose egg?"
		end)
		nestRows[index] = { Label = label, Cancel = cancel }
	end

	section(10, "Pick two birds of the same kind")
	pickHint = UI.label({
		LayoutOrder = 11,
		TextWrapped = true,
		TextColor3 = UI.Colors.SubText,
		Size = UDim2.new(1, -8, 0, 32),
		Parent = body,
	})
	pickGrid = UI.new("Frame", {
		LayoutOrder = 12,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = body,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(160, 50),
			CellPadding = UDim2.fromOffset(6, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	startButton = UI.button({
		LayoutOrder = 13,
		Size = UDim2.new(1, -8, 0, 44),
		Parent = body,
	}, function()
		if #selected == 2 and Actions.Pet("Breed", selected[1], selected[2], targetNest) then
			selected = {}
			NestWindow.Refresh()
		end
	end)

	section(20, "Families")
	familyLabel = UI.label({
		LayoutOrder = 21,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})

	Store.Changed:Connect(function(what)
		if what == "Data" then
			NestWindow.Refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			-- only the nest timers change every second (rebuilding the
			-- bird buttons here would eat clicks)
			local data = Store.Data
			if window.Visible and data then
				refreshNests(data, Store.Now())
			end
		end
	end)
end

-- nestIndex: the nest the player walked up to (or nil from the aviary)
function NestWindow.Open(nestIndex)
	targetNest = tonumber(nestIndex)
	window.Visible = true
	UI.pop(window)
	NestWindow.Refresh()
end

function NestWindow.Close()
	window.Visible = false
end

function NestWindow.IsOpen()
	return window.Visible
end

return NestWindow
