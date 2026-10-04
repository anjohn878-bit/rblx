--[[
	UIController
	Builds the whole interface into one ScreenGui and manages which full-screen
	panel is open (only one at a time). While a panel is open
	ClientState.MenuOpen is true, which unlocks the mouse in matches.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.Parent.ClientState)
local HUD = require(script.Parent.HUD)
local MatchHUD = require(script.Parent.MatchHUD)
local LockerPanel = require(script.Parent.LockerPanel)
local ProfilePanel = require(script.Parent.ProfilePanel)
local SettingsPanel = require(script.Parent.SettingsPanel)
local ResultsPanel = require(script.Parent.ResultsPanel)

local UIController = {}

local player = Players.LocalPlayer
local panels = {
	Locker = LockerPanel,
	Profile = ProfilePanel,
	Settings = SettingsPanel,
	Results = ResultsPanel,
}
local openPanel: string? = nil

function UIController.Close()
	if openPanel then
		panels[openPanel].Close()
		openPanel = nil
	end
	ClientState.MenuOpen = false
end

function UIController.Open(name: string)
	if name == "Play" then
		UIController.Close()
		if player:GetAttribute("QueuedPitch") then
			Remotes.Get("RequestQueue"):FireServer(false)
		else
			Remotes.Get("RequestQueue"):FireServer(true)
		end
		return
	end
	if openPanel == name then
		UIController.Close()
		return
	end
	-- Locker/Profile/Settings are hub-only; results can show anywhere.
	if name ~= "Results" and player:GetAttribute("MatchId") then
		return
	end
	UIController.Close()
	local panel = panels[name]
	if panel then
		openPanel = name
		ClientState.MenuOpen = true
		panel.Open()
	end
end

function UIController.ToggleMenu()
	if openPanel then
		UIController.Close()
	else
		UIController.Open("Profile")
	end
end

function UIController.Init() end

function UIController.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ConcreteKingsUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	HUD.Create(gui, UIController.Open)
	MatchHUD.Create(gui)
	LockerPanel.Create(gui, UIController.Close)
	ProfilePanel.Create(gui, UIController.Close)
	SettingsPanel.Create(gui, UIController.Close)
	ResultsPanel.Create(gui, UIController.Close)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt:GetAttribute("OpensUI") then
			UIController.Open(prompt:GetAttribute("OpensUI"))
		end
	end)

	Remotes.Get("MatchEvent").OnClientEvent:Connect(function(kind, payload)
		if kind == "MatchFound" then
			UIController.Close()
		elseif kind == "Results" then
			task.delay(1.2, function()
				UIController.Close()
				openPanel = "Results"
				ClientState.MenuOpen = true
				ResultsPanel.Show(payload)
			end)
		end
	end)
end

return UIController
