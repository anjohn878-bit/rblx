--[[
	Work as a Doctor - client entry point.
	Initialises every controller (UI is built from code), then starts them.
]]

local Controllers = script.Parent.Controllers

local UIKit = require(script.Parent.UI.UIKit)
local ClientState = require(script.Parent.ClientState)

local controllers = {
	ClientState = ClientState,
	SoundController = require(Controllers.SoundController),
	NotificationController = require(Controllers.NotificationController),
	EffectsController = require(Controllers.EffectsController),
	GuideController = require(Controllers.GuideController),
	HUDController = require(Controllers.HUDController),
	ShopController = require(Controllers.ShopController),
	StatsController = require(Controllers.StatsController),
	DiagnosisController = require(Controllers.DiagnosisController),
	PatientVisualsController = require(Controllers.PatientVisualsController),
	WorldController = require(Controllers.WorldController),
	TutorialController = require(Controllers.TutorialController),
}

local ORDER = {
	"SoundController",
	"NotificationController",
	"EffectsController",
	"GuideController",
	"HUDController",
	"ShopController",
	"StatsController",
	"DiagnosisController",
	"PatientVisualsController",
	"WorldController",
	"TutorialController",
}

UIKit.Init()
UIKit.SetClickSound(function()
	controllers.SoundController.Play("Click")
end)

for _, name in ORDER do
	local controller = (controllers :: any)[name]
	if controller.Init then
		controller.Init(controllers)
	end
end

ClientState.Start()

for _, name in ORDER do
	local controller = (controllers :: any)[name]
	if controller.Start then
		task.spawn(controller.Start)
	end
end
