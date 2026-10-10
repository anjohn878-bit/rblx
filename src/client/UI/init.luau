--!strict
-- Mounts generated screens. Generated/<Screen>.luau comes from specs/ui/*.json.
local Players = game:GetService("Players")

local UI = {}

function UI.mount(screenName: string): (ScreenGui, { [string]: GuiObject })
	local build = require(script.Generated:FindFirstChild(screenName) :: ModuleScript) :: any
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local camera = workspace.CurrentCamera
	return build(playerGui, camera.ViewportSize.Y)
end

return UI
