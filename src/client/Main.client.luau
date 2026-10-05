--[[
	Ice Skating Simulator - client entry point.
]]

local Controllers = script.Parent:WaitForChild("Controllers")

local ClientData = require(Controllers.ClientData)
local SkateController = require(Controllers.SkateController)
local SkatePoser = require(Controllers.SkatePoser)
local Effects = require(Controllers.Effects)
local HUD = require(Controllers.HUD)
local ShopUI = require(Controllers.ShopUI)
local RinkGates = require(Controllers.RinkGates)

ClientData.init()
SkateController.init()
SkatePoser.init()
Effects.init()
HUD.init({
	onShop = ShopUI.toggleShop,
	onRebirth = ShopUI.toggleRebirth,
})
ShopUI.init()
RinkGates.init()
