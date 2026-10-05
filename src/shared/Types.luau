--!strict
-- Shared type definitions. Nothing in here exists at runtime.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type BirdDef = {
	id: string,
	name: string,
	rarity: Rarity,
	value: number, -- feathers paid for every visit
	blurb: string,
	scale: number, -- 1.0 is roughly a robin
	body: Color3,
	belly: Color3,
	wing: Color3,
	beak: Color3,
	accent: Color3,
	traits: { string }, -- Crest, Cap, LongTail, BigBeak, LongBeak, OwlFace, FanTail, Glow, Fire, Hover
}

export type WeightedBird = { id: string, weight: number }

export type SeedDef = {
	id: string,
	name: string,
	rarity: Rarity,
	tier: number,
	price: number, -- feathers
	growTime: number, -- seconds
	blurb: string,
	color: Color3,
	labelHeight: number, -- studs above the soil (at full size) for the timer label
	perches: { { number } }, -- {x, y, z} offsets from the plant root at full size
	birds: { WeightedBird },
	stock: { chance: number, min: number, max: number },
}

export type Snapshot = {
	feathers: number,
	seeds: { [string]: number },
	birds: { [string]: number }, -- species id -> number of visits
	plots: number, -- unlocked plots
	nextPlotPrice: number?, -- nil once every plot is unlocked
	totalVisits: number,
}

export type VisitInfo = {
	id: number,
	birdId: string,
	ownerUserId: number,
	perch: Vector3,
	from: Vector3,
	to: Vector3,
	facing: Vector3,
	startTime: number, -- server time
	arrive: number,
	stay: number,
	leave: number,
	seed: number, -- cosmetic variation
}

export type StockInfo = {
	stock: { [string]: number },
	nextRestock: number, -- server time
}

export type Notice = {
	kind: string, -- "toast" | "reward" | "discovery"
	text: string?,
	color: Color3?,
	amount: number?,
	birdId: string?,
	position: Vector3?,
	bonus: number?,
}

export type Result = { ok: boolean, message: string }

return {}
