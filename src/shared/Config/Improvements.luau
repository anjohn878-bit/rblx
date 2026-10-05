--[[
	Improvements
	Cheap repeatable upgrades so there is always a "next thing" to save for.
]]

export type Improvement = {
	Id: string,
	Name: string,
	Emoji: string,
	Description: string,
	MaxLevel: number,
	BaseCost: number,
	Growth: number,
	PerLevel: number,
}

local List: { Improvement } = {
	{
		Id = "Marketing",
		Name = "Marketing Campaign",
		Emoji = "📣",
		Description = "Patients arrive 7% faster per level.",
		MaxLevel = 10,
		BaseCost = 250,
		Growth = 1.9,
		PerLevel = 0.07,
	},
	{
		Id = "Equipment",
		Name = "Better Equipment",
		Emoji = "🔬",
		Description = "+10% money from every patient per level.",
		MaxLevel = 15,
		BaseCost = 400,
		Growth = 1.7,
		PerLevel = 0.1,
	},
	{
		Id = "Training",
		Name = "Doctor Training",
		Emoji = "🎓",
		Description = "Auto Doctors work 6% faster per level.",
		MaxLevel = 10,
		BaseCost = 1500,
		Growth = 2,
		PerLevel = 0.06,
	},
}

local byId: { [string]: Improvement } = {}
for _, item in List do
	byId[item.Id] = item
end

return {
	List = List,
	ById = byId,
}
