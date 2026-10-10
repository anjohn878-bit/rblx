--!strict
-- Sound recipes: layered combos of already-uploaded library sounds (no new uploads;
-- the Open Cloud audio upload quota is small). Fill `Library` from library/sound/catalog.json.
export type Layer = { sound: string, volume: number?, pitch: { number }?, delay: number? }

return {
	Library = {
		-- boom = "rbxassetid://...",
	} :: { [string]: string },

	Recipes = {
		-- Explosion = { { sound = "boom" }, { sound = "debris", volume = 0.5, delay = 0.05 } },
	} :: { [string]: { Layer } },
}
