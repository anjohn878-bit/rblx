--[[
	Illnesses
	Server-only illness database. Kid-friendly and non-graphic on purpose.

	Category decides when an illness can appear:
	  Basic       always
	  Lab         Laboratory unlocked
	  Emergency   Emergency Room unlocked
	  Surgery     Surgery Room unlocked
	  Specialist  Specialist Room unlocked
	  Rare        only for Rare / Epic / Legendary patients (fun, fictional)

	Add a new illness by adding an entry below; symptoms must use the keys of
	the SYMPTOMS table so identical symptoms compare equal.
]]

local SYMPTOMS = {
	Sneezing = "🤧 Sneezing",
	RunnyNose = "💧 Runny nose",
	SoreThroat = "😣 Sore throat",
	Cough = "😷 Coughing",
	Fever = "🌡️ Fever",
	Headache = "🤕 Headache",
	Tired = "😴 Tiredness",
	Aches = "💪 Body aches",
	Throbbing = "💥 Throbbing head",
	LightSensitive = "🔦 Bright lights hurt",
	Grumpy = "😠 Grumpy mood",
	TummyPain = "🤢 Tummy pain",
	Queasy = "🥴 Feeling queasy",
	NotHungry = "🍽️ Not hungry",
	Bloated = "🎈 Bloated tummy",
	Chills = "🥶 Chills",
	Sweating = "💦 Sweating",
	FlushedFace = "😳 Flushed face",
	EarPain = "👂 Ear pain",
	Muffled = "🔇 Muffled hearing",
	Dizzy = "💫 Dizziness",
	SwollenAnkle = "🦶 Swollen ankle",
	Limping = "🚶 Limping",
	AnklePain = "😖 Ankle pain",
	ItchyEyes = "👀 Itchy eyes",
	WateryEyes = "😢 Watery eyes",
	ItchySkin = "🐜 Itchy skin",
	ScratchyThroat = "🌵 Scratchy throat",
	HardSwallow = "😬 Hard to swallow",
	Hoarse = "🗣️ Croaky voice",
	RedSkin = "🔴 Red skin",
	HotSkin = "🔥 Skin feels hot",
	Peeling = "🧻 Peeling skin",
	Thirsty = "🥤 Very thirsty",
	RedSpots = "🔴 Red spots",
	ItchySpots = "🐞 Itchy spots",
	Weak = "😩 Feeling weak",
	SwollenGlands = "🎯 Swollen neck glands",
	PinkEyes = "🌸 Pink eyes",
	StickyEyelids = "🍯 Sticky eyelids",
	Wheezing = "🌬️ Wheezing",
	ShortBreath = "😤 Short of breath",
	TightChest = "🧱 Tight chest",
	PaleSkin = "🤍 Pale skin",
	ColdHands = "🧊 Cold hands",
	ArmPain = "🦾 Arm pain",
	SwollenArm = "🎈 Swollen arm",
	CantMoveArm = "🚫 Can't move arm",
	HeadBump = "🥚 Bump on the head",
	Confused = "❓ Confused",
	Sleepy = "😪 Very sleepy",
	Hives = "🟣 Hives",
	Swelling = "🐡 Puffy face",
	LowerRightPain = "👉 Sharp pain low on the right",
	KneePain = "🦵 Knee pain",
	SwollenKnee = "🍉 Swollen knee",
	WobblyKnee = "🍮 Wobbly knee",
	CantJump = "⛔ Can't jump",
	TummyRattles = "🧩 Tummy rattles",
	Embarrassed = "🙈 Embarrassed",
	MissingToy = "🧸 Missing toy piece",
	CantSleep = "🌙 Can't sleep",
	Yawning = "🥱 Yawning all day",
	TiredEyes = "🐼 Dark circles",
	SpinningRoom = "🌀 Room spinning",
	WobblyWalk = "〰️ Wobbly walking",
	RingingEars = "🔔 Ringing ears",
	ShakyHands = "🤲 Shaky hands",
	Forgetful = "🧠 Forgetful",
	-- Rare / fictional
	Giggling = "😂 Can't stop giggling",
	RosyCheeks = "🌹 Rosy cheeks",
	Hiccups = "😯 Hiccups",
	RainbowSpots = "🌈 Rainbow spots",
	Sparkly = "✨ Sparkly skin",
	Humming = "🎵 Humming songs",
	Glitter = "💎 Sneezing glitter",
	ShinyHair = "💇 Super shiny hair",
	Beeping = "🤖 Beeping voice",
	StiffArms = "🦿 Robot arms",
	Binary = "💾 Talks in numbers",
	Bubbles = "🧼 Burping bubbles",
	Floaty = "🎈 Floaty feeling",
	Bendy = "🍝 Noodle-bendy knees",
	Dancing = "🕺 Can't stop dancing",
	GlowShoes = "👟 Glowing shoes",
	GlowSkin = "🌟 Glowing skin",
	DaySleepy = "🌜 Sleepy in daytime",
	BlockySpots = "🟪 Blocky spots",
	Laggy = "🐌 Laggy movement",
	Squares = "🔲 Sees everything in squares",
	Purring = "🐱 Purring",
	Whiskers = "〽️ Twitchy nose",
	Meowing = "🐾 Says meow",
}

export type Illness = {
	Id: string,
	Name: string,
	Emoji: string,
	Category: string,
	Reward: number,
	Symptoms: { string },
}

local S = SYMPTOMS

local LIST: { Illness } = {
	-- Basic -----------------------------------------------------------------
	{ Id = "Cold", Name = "Common Cold", Emoji = "🤧", Category = "Basic", Reward = 25, Symptoms = { S.Sneezing, S.RunnyNose, S.SoreThroat, S.Cough } },
	{ Id = "Flu", Name = "Flu", Emoji = "🤒", Category = "Basic", Reward = 40, Symptoms = { S.Fever, S.Headache, S.Tired, S.Aches } },
	{ Id = "Headache", Name = "Headache", Emoji = "🤕", Category = "Basic", Reward = 20, Symptoms = { S.Throbbing, S.LightSensitive, S.Grumpy } },
	{ Id = "StomachAche", Name = "Stomach Ache", Emoji = "🤢", Category = "Basic", Reward = 30, Symptoms = { S.TummyPain, S.Queasy, S.NotHungry, S.Bloated } },
	{ Id = "Fever", Name = "Fever", Emoji = "🌡️", Category = "Basic", Reward = 35, Symptoms = { S.Fever, S.Chills, S.Sweating, S.FlushedFace } },
	{ Id = "Earache", Name = "Earache", Emoji = "👂", Category = "Basic", Reward = 30, Symptoms = { S.EarPain, S.Muffled, S.Dizzy } },
	{ Id = "Sprain", Name = "Sprained Ankle", Emoji = "🦶", Category = "Basic", Reward = 60, Symptoms = { S.SwollenAnkle, S.Limping, S.AnklePain } },
	{ Id = "Allergies", Name = "Allergies", Emoji = "🌼", Category = "Basic", Reward = 35, Symptoms = { S.ItchyEyes, S.Sneezing, S.WateryEyes, S.ItchySkin } },
	{ Id = "SoreThroat", Name = "Sore Throat", Emoji = "😣", Category = "Basic", Reward = 25, Symptoms = { S.ScratchyThroat, S.HardSwallow, S.Hoarse } },
	{ Id = "Sunburn", Name = "Sunburn", Emoji = "☀️", Category = "Basic", Reward = 30, Symptoms = { S.RedSkin, S.HotSkin, S.Peeling, S.Thirsty } },

	-- Laboratory -------------------------------------------------------------
	{ Id = "Chickenpox", Name = "Chickenpox", Emoji = "🐔", Category = "Lab", Reward = 70, Symptoms = { S.ItchySpots, S.RedSpots, S.Fever, S.Tired } },
	{ Id = "FoodPoisoning", Name = "Food Poisoning", Emoji = "🍤", Category = "Lab", Reward = 75, Symptoms = { S.TummyPain, S.Queasy, S.Fever, S.Weak } },
	{ Id = "Strep", Name = "Strep Throat", Emoji = "🦠", Category = "Lab", Reward = 80, Symptoms = { S.ScratchyThroat, S.Fever, S.SwollenGlands, S.HardSwallow } },
	{ Id = "PinkEye", Name = "Pink Eye", Emoji = "🌸", Category = "Lab", Reward = 65, Symptoms = { S.PinkEyes, S.ItchyEyes, S.StickyEyelids, S.WateryEyes } },
	{ Id = "Asthma", Name = "Asthma", Emoji = "🌬️", Category = "Lab", Reward = 85, Symptoms = { S.Wheezing, S.ShortBreath, S.TightChest, S.Cough } },
	{ Id = "Anemia", Name = "Anemia", Emoji = "🩸", Category = "Lab", Reward = 70, Symptoms = { S.PaleSkin, S.Tired, S.ColdHands, S.Dizzy } },

	-- Emergency --------------------------------------------------------------
	{ Id = "BrokenArm", Name = "Broken Arm", Emoji = "🦴", Category = "Emergency", Reward = 110, Symptoms = { S.ArmPain, S.SwollenArm, S.CantMoveArm } },
	{ Id = "Concussion", Name = "Concussion", Emoji = "💫", Category = "Emergency", Reward = 125, Symptoms = { S.HeadBump, S.Dizzy, S.Confused, S.Sleepy } },
	{ Id = "AllergicReaction", Name = "Allergic Reaction", Emoji = "🐝", Category = "Emergency", Reward = 115, Symptoms = { S.Hives, S.Swelling, S.ItchySkin, S.ShortBreath } },
	{ Id = "Heatstroke", Name = "Heatstroke", Emoji = "🥵", Category = "Emergency", Reward = 105, Symptoms = { S.HotSkin, S.Dizzy, S.RedSkin, S.Confused } },

	-- Surgery ----------------------------------------------------------------
	{ Id = "Appendicitis", Name = "Appendicitis", Emoji = "🩺", Category = "Surgery", Reward = 170, Symptoms = { S.LowerRightPain, S.Fever, S.NotHungry, S.Queasy } },
	{ Id = "KneeInjury", Name = "Torn Knee Ligament", Emoji = "🦵", Category = "Surgery", Reward = 155, Symptoms = { S.KneePain, S.SwollenKnee, S.WobblyKnee, S.CantJump } },
	{ Id = "SwallowedToy", Name = "Swallowed a Toy", Emoji = "🧱", Category = "Surgery", Reward = 165, Symptoms = { S.TummyRattles, S.TummyPain, S.Embarrassed, S.MissingToy } },

	-- Specialist -------------------------------------------------------------
	{ Id = "Insomnia", Name = "Insomnia", Emoji = "🌙", Category = "Specialist", Reward = 230, Symptoms = { S.CantSleep, S.Yawning, S.Grumpy, S.TiredEyes } },
	{ Id = "Vertigo", Name = "Vertigo", Emoji = "🌀", Category = "Specialist", Reward = 250, Symptoms = { S.SpinningRoom, S.Dizzy, S.WobblyWalk, S.Queasy } },
	{ Id = "Tinnitus", Name = "Tinnitus", Emoji = "🔔", Category = "Specialist", Reward = 220, Symptoms = { S.RingingEars, S.CantSleep, S.Muffled } },
	{ Id = "NerveTwitch", Name = "Nervous Twitch", Emoji = "⚡", Category = "Specialist", Reward = 240, Symptoms = { S.ShakyHands, S.Forgetful, S.Tired, S.Grumpy } },

	-- Rare (fictional & fun) ------------------------------------------------
	{ Id = "GiggleFever", Name = "Giggle Fever", Emoji = "😂", Category = "Rare", Reward = 110, Symptoms = { S.Giggling, S.RosyCheeks, S.Fever, S.Hiccups } },
	{ Id = "RainbowRash", Name = "Rainbow Rash", Emoji = "🌈", Category = "Rare", Reward = 120, Symptoms = { S.RainbowSpots, S.ItchySkin, S.Sparkly, S.Humming } },
	{ Id = "SparklePox", Name = "Sparkle Pox", Emoji = "✨", Category = "Rare", Reward = 130, Symptoms = { S.Glitter, S.Sparkly, S.ShinyHair, S.ItchySpots } },
	{ Id = "RobotVoice", Name = "Robot Voice", Emoji = "🤖", Category = "Rare", Reward = 140, Symptoms = { S.Beeping, S.StiffArms, S.Binary } },
	{ Id = "BubbleBelly", Name = "Bubble Belly", Emoji = "🧼", Category = "Rare", Reward = 115, Symptoms = { S.Bubbles, S.Floaty, S.Bloated, S.Hiccups } },
	{ Id = "NoodleLegs", Name = "Noodle Legs", Emoji = "🍝", Category = "Rare", Reward = 125, Symptoms = { S.Bendy, S.WobblyWalk, S.Dizzy } },
	{ Id = "DiscoFever", Name = "Disco Fever", Emoji = "🕺", Category = "Rare", Reward = 150, Symptoms = { S.Dancing, S.GlowShoes, S.Fever, S.Humming } },
	{ Id = "MoonSickness", Name = "Moon Sickness", Emoji = "🌙", Category = "Rare", Reward = 160, Symptoms = { S.GlowSkin, S.DaySleepy, S.Floaty, S.PaleSkin } },
	{ Id = "PixelPox", Name = "Pixel Pox", Emoji = "🟪", Category = "Rare", Reward = 175, Symptoms = { S.BlockySpots, S.Laggy, S.Squares, S.ItchySkin } },
	{ Id = "KittyCough", Name = "Kitty Cough", Emoji = "🐱", Category = "Rare", Reward = 135, Symptoms = { S.Purring, S.Whiskers, S.Meowing, S.Cough } },
}

local CATEGORY_ROOM = {
	Basic = nil,
	Lab = "Laboratory",
	Emergency = "EmergencyRoom",
	Surgery = "Surgery",
	Specialist = "Specialist",
}

local byId: { [string]: Illness } = {}
local byCategory: { [string]: { Illness } } = {}
for _, illness in LIST do
	byId[illness.Id] = illness
	byCategory[illness.Category] = byCategory[illness.Category] or {}
	table.insert(byCategory[illness.Category], illness)
end

local Illnesses = {
	List = LIST,
	ById = byId,
	ByCategory = byCategory,
	Symptoms = SYMPTOMS,
}

-- Regular (non-rare) illnesses the hospital can currently see.
function Illnesses.GetRegularPool(rooms: { [string]: boolean }): { Illness }
	local pool = {}
	for _, illness in LIST do
		if illness.Category ~= "Rare" then
			local requiredRoom = CATEGORY_ROOM[illness.Category]
			if requiredRoom == nil or rooms[requiredRoom] then
				table.insert(pool, illness)
			end
		end
	end
	return pool
end

function Illnesses.Get(id: string): Illness?
	return byId[id]
end

local function containsAll(haystack: { string }, needles: { string }): boolean
	for _, needle in needles do
		if not table.find(haystack, needle) then
			return false
		end
	end
	return true
end

local function shareCount(a: { string }, b: { string }): number
	local count = 0
	for _, value in a do
		if table.find(b, value) then
			count += 1
		end
	end
	return count
end

local function shuffle<T>(list: { T }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

--[[
	Builds a solvable diagnosis case:
	  * picks `symptomCount` of the illness's symptoms to show
	  * picks distractor illnesses that do NOT contain every shown symptom,
	    preferring ones that share a symptom (so it is not trivially easy)
]]
function Illnesses.BuildCase(illness: Illness, distractorPool: { Illness }, symptomCount: number, choiceCount: number, rng: Random)
	local shown = table.clone(illness.Symptoms)
	shuffle(shown, rng)
	while #shown > math.max(symptomCount, 1) do
		table.remove(shown)
	end

	local similar, others = {}, {}
	for _, candidate in distractorPool do
		if candidate.Id ~= illness.Id and not containsAll(candidate.Symptoms, shown) then
			if shareCount(candidate.Symptoms, illness.Symptoms) > 0 then
				table.insert(similar, candidate)
			else
				table.insert(others, candidate)
			end
		end
	end
	shuffle(similar, rng)
	shuffle(others, rng)

	local options = { illness }
	-- Mix: up to half of the distractors are "similar", the rest random.
	local wantSimilar = math.ceil((choiceCount - 1) / 2)
	for _, candidate in similar do
		if #options - 1 >= wantSimilar then
			break
		end
		table.insert(options, candidate)
	end
	for _, list in { others, similar } do
		for _, candidate in list do
			if #options >= choiceCount then
				break
			end
			if not table.find(options, candidate) then
				table.insert(options, candidate)
			end
		end
	end
	shuffle(options, rng)
	return shown, options
end

return Illnesses
