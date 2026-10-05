--[[
	Rooms
	Special hospital areas that are bought once and give a permanent benefit.
	Location "Lobby" rooms are built into the lobby; "Back" rooms are built
	into the back wing (in this order) once the hospital is big enough.
]]

export type Room = {
	Id: string,
	Name: string,
	Emoji: string,
	Cost: number,
	RequiredLevel: number,
	Location: string,
	Benefit: string,
	Color: Color3,
}

local Rooms: { Room } = {
	{
		Id = "Pharmacy",
		Name = "Pharmacy",
		Emoji = "💊",
		Cost = 750,
		RequiredLevel = 2,
		Location = "Lobby",
		Benefit = "Treated patients buy medicine on the way out: +25% income from every patient.",
		Color = Color3.fromRGB(80, 200, 120),
	},
	{
		Id = "Laboratory",
		Name = "Laboratory",
		Emoji = "🧪",
		Cost = 3500,
		RequiredLevel = 3,
		Location = "Back",
		Benefit = "Unlocks harder, better-paying illnesses and the Lab Test button (removes a wrong answer).",
		Color = Color3.fromRGB(90, 160, 255),
	},
	{
		Id = "ChildrensWard",
		Name = "Children's Ward",
		Emoji = "🧸",
		Cost = 12000,
		RequiredLevel = 4,
		Location = "Back",
		Benefit = "Kids start visiting (1.2x pay) and patients arrive 15% faster.",
		Color = Color3.fromRGB(255, 150, 200),
	},
	{
		Id = "EmergencyRoom",
		Name = "Emergency Room",
		Emoji = "🚨",
		Cost = 20000,
		RequiredLevel = 4,
		Location = "Back",
		Benefit = "Emergency patients rush in, skip the queue and pay 2x.",
		Color = Color3.fromRGB(240, 70, 70),
	},
	{
		Id = "Surgery",
		Name = "Surgery Room",
		Emoji = "🔪",
		Cost = 60000,
		RequiredLevel = 5,
		Location = "Back",
		Benefit = "Unlocks surgery cases: the highest-paying regular illnesses.",
		Color = Color3.fromRGB(70, 200, 200),
	},
	{
		Id = "Specialist",
		Name = "Specialist Room",
		Emoji = "🧠",
		Cost = 200000,
		RequiredLevel = 6,
		Location = "Back",
		Benefit = "Unlocks specialist illnesses and makes rare patients 50% more common.",
		Color = Color3.fromRGB(170, 110, 255),
	},
	{
		Id = "VIP",
		Name = "VIP Treatment Room",
		Emoji = "👑",
		Cost = 750000,
		RequiredLevel = 7,
		Location = "Back",
		Benefit = "Celebrity VIP patients visit and pay 5x.",
		Color = Color3.fromRGB(255, 200, 40),
	},
}

local byId: { [string]: Room } = {}
for _, room in Rooms do
	byId[room.Id] = room
end

return {
	List = Rooms,
	ById = byId,
}
