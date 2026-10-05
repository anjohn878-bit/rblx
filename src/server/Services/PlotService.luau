--[[
	PlotService
	Owns the hospital plots: builds each plot's base, hands plots out to
	joining players and frees them when they leave.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Build = require(script.Parent.Parent.Util.Build)
local WorldBuilder = require(script.Parent.WorldBuilder)

export type Plot = {
	Index: number,
	CFrame: CFrame,
	Folder: Folder,
	Patients: Folder,
	Doctors: Folder,
	SignLabel: TextLabel,
	Owner: Player?,
}

local PlotService = {}

local plots: { Plot } = {}
local byPlayer: { [Player]: Plot } = {}

local PLOT_TOP = 0.4

local function buildBase(folder: Folder, origin: CFrame, index: number): TextLabel
	local base = Build.Model(folder, "Base")
	local width, depth = GameConfig.PlotWidth, GameConfig.PlotDepth
	Build.Part(base, {
		Name = "Lawn",
		Size = Vector3.new(width, PLOT_TOP + 1, depth),
		CFrame = origin * CFrame.new(0, (PLOT_TOP - 1) / 2, depth / 2),
		Color = Color3.fromRGB(118, 196, 88),
		Material = Enum.Material.Grass,
	})
	-- Low hedge around the sides and back
	local hedge = Color3.fromRGB(60, 140, 60)
	Build.Part(base, { Size = Vector3.new(1.5, 2.5, depth), CFrame = origin * CFrame.new(-width / 2 + 0.75, PLOT_TOP + 1.25, depth / 2), Color = hedge, Material = Enum.Material.Grass })
	Build.Part(base, { Size = Vector3.new(1.5, 2.5, depth), CFrame = origin * CFrame.new(width / 2 - 0.75, PLOT_TOP + 1.25, depth / 2), Color = hedge, Material = Enum.Material.Grass })
	Build.Part(base, { Size = Vector3.new(width, 2.5, 1.5), CFrame = origin * CFrame.new(0, PLOT_TOP + 1.25, depth - 0.75), Color = hedge, Material = Enum.Material.Grass })

	-- Owner sign at the front-right corner
	local signCF = origin * CFrame.new(width / 2 - 16, PLOT_TOP, 1.5)
	for _, x in { -4.5, 4.5 } do
		Build.Part(base, { Size = Vector3.new(0.5, 7, 0.5), CFrame = signCF * CFrame.new(x, 3.5, 0), Color = Color3.fromRGB(80, 80, 90), Material = Enum.Material.Metal })
	end
	local board = Build.Part(base, {
		Name = "OwnerSign",
		Size = Vector3.new(10, 3.5, 0.4),
		CFrame = signCF * CFrame.new(0, 6, 0),
		Color = Color3.fromRGB(40, 120, 200),
	})
	local label = Build.SurfaceText(board, "🏥 Plot " .. index .. "\nAvailable", {
		Face = Enum.NormalId.Front,
		TextColor = Color3.new(1, 1, 1),
		StrokeColor = Color3.fromRGB(20, 40, 80),
	})
	return label
end

function PlotService.Init()
	local plotsFolder = Build.Folder(workspace, "Plots")
	for index, cf in WorldBuilder.GetPlotCFrames() do
		local folder = Build.Folder(plotsFolder, "Plot" .. index)
		folder:SetAttribute("PlotIndex", index)
		folder:SetAttribute("OwnerUserId", 0)
		local label = buildBase(folder, cf, index)
		local plot: Plot = {
			Index = index,
			CFrame = cf,
			Folder = folder,
			Patients = Build.Folder(folder, "Patients"),
			Doctors = Build.Folder(folder, "Doctors"),
			SignLabel = label,
			Owner = nil,
		}
		table.insert(plots, plot)
	end
end

function PlotService.Assign(player: Player): Plot?
	if byPlayer[player] then
		return byPlayer[player]
	end
	for _, plot in plots do
		if plot.Owner == nil then
			plot.Owner = player
			byPlayer[player] = plot
			plot.Folder:SetAttribute("OwnerUserId", player.UserId)
			plot.Folder:SetAttribute("OwnerName", player.DisplayName)
			plot.SignLabel.Text = "🏥 Dr. " .. player.DisplayName .. "'s Hospital"
			return plot
		end
	end
	return nil
end

function PlotService.Release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil
	plot.Owner = nil
	plot.Folder:SetAttribute("OwnerUserId", 0)
	plot.Folder:SetAttribute("OwnerName", nil)
	plot.SignLabel.Text = "🏥 Plot " .. plot.Index .. "\nAvailable"
end

function PlotService.GetPlot(player: Player): Plot?
	return byPlayer[player]
end

function PlotService.GetPlots(): { Plot }
	return plots
end

return PlotService
