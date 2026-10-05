-- A shopper: walks in, picks a dress off a rack, waits in line at the
-- register, pays, and walks home happy (or grumpy if nobody served them).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("DressStore"):WaitForChild("Config"))
local Layout = require(script.Parent.Layout)
local Npc = require(script.Parent.Npc)

local Customer = {}
Customer.__index = Customer

local BAG_COLORS = {
	Color3.fromRGB(255, 105, 180),
	Color3.fromRGB(255, 182, 213),
	Color3.fromRGB(186, 140, 255),
	Color3.fromRGB(255, 255, 255),
}

local ARRIVE_DISTANCE = 1.3

-- store is the Store object that owns this shopper (see Store.lua)
function Customer.new(store)
	local self = setmetatable({}, Customer)
	self.store = store
	self.alive = true
	self.paid = false
	self.dress = nil
	self.queueIndex = 0
	self.atSpot = false
	self.queueStart = 0
	self.spawnSide = if math.random() < 0.5 then -1 else 1
	self.character = nil
	return self
end

-- Creates the character and puts it on the sidewalk. Returns false if the store closed meanwhile.
function Customer:spawn(parent: Instance): boolean
	local character = Npc.create("Shopper")
	if not self.alive then
		character.model:Destroy()
		return false
	end
	self.character = character
	local humanoid = character.humanoid
	humanoid.WalkSpeed = Config.Customer.WALK_SPEED * (0.9 + math.random() * 0.2)

	local spawnPoint = Vector3.new(self.spawnSide * Layout.CUSTOMER_SPAWN_X, 0, Layout.CUSTOMER_SPAWN_Z)
	local position = self.store:toWorldPoint(spawnPoint) + Vector3.new(0, character.groundOffset + 0.2, 0)
	local lookAt = self.store:toWorldPoint(Layout.STREET)
	character.model:PivotTo(CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
	character.model.Parent = parent
	pcall(function()
		character.root:SetNetworkOwner(nil)
	end)
	return true
end

function Customer:localPosition(): Vector3
	local root = self.character.root
	return self.store.cf:PointToObjectSpace(root.Position)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

function Customer:isNear(localPoint: Vector3): boolean
	return flatDistance(self:localPosition(), localPoint) <= ARRIVE_DISTANCE
end

-- Walks to a point in plot space. If something blocks the way, the shopper
-- is gently moved there so they never get stuck.
function Customer:walk(localPoint: Vector3): boolean
	if not self.alive then
		return false
	end
	local character = self.character
	local humanoid = character.humanoid
	local target = self.store:toWorldPoint(localPoint)
	local distance = flatDistance(self:localPosition(), localPoint)
	local timeout = distance / math.max(humanoid.WalkSpeed, 1) * 1.6 + 2
	local started = os.clock()
	local lastOrder = 0

	while self.alive and character.model.Parent do
		if flatDistance(self:localPosition(), localPoint) <= ARRIVE_DISTANCE then
			return true
		end
		local now = os.clock()
		if now - started > timeout then
			break
		end
		if now - lastOrder > 2 then
			lastOrder = now
			humanoid:MoveTo(target)
		end
		task.wait(0.1)
	end

	if not self.alive or not character.model.Parent then
		return false
	end
	-- Stuck: hop to the target
	local root = character.root
	local position = Vector3.new(target.X, target.Y + character.groundOffset + 0.1, target.Z)
	local look = root.CFrame.LookVector
	character.model:PivotTo(CFrame.lookAt(position, position + Vector3.new(look.X, 0, look.Z)))
	return true
end

function Customer:face(localPoint: Vector3)
	if not self.alive then
		return
	end
	local root = self.character.root
	local target = self.store:toWorldPoint(localPoint)
	local flatTarget = Vector3.new(target.X, root.Position.Y, target.Z)
	if (flatTarget - root.Position).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end
end

function Customer:bubble(text: string?)
	if self.alive and self.character then
		Npc.setBubble(self.character, text)
	end
end

function Customer:wait(seconds: number): boolean
	local started = os.clock()
	while self.alive and os.clock() - started < seconds do
		task.wait(0.1)
	end
	return self.alive
end

-- Called by the store when the shopper is rung up.
function Customer:markPaid()
	self.paid = true
end

function Customer:isReadyToPay(): boolean
	return self.alive and not self.paid and self.queueIndex == 1 and self.atSpot
end

-- Walks from wherever the shopper is back out to the street.
function Customer:leave()
	local here = self:localPosition()
	if here.Z > Layout.INSIDE.Z + 1 then
		local side = if here.X < -1 then -1 else 1
		local aisleX = side * Layout.AISLE_X
		if here.Z > Layout.BACK_AISLE_Z - 2 then
			if not self:walk(Vector3.new(aisleX, 0, Layout.BACK_AISLE_Z)) then
				return
			end
		end
		if not self:walk(Vector3.new(aisleX, 0, Layout.INSIDE.Z)) then
			return
		end
		if not self:walk(Layout.INSIDE) then
			return
		end
	end
	if not self:walk(Layout.STREET) then
		return
	end
	self:walk(Vector3.new(self.spawnSide * Layout.CUSTOMER_SPAWN_X, 0, Layout.CUSTOMER_SPAWN_Z))
end

function Customer:fadeAway()
	if not self.alive or not self.character then
		return
	end
	self:bubble(nil)
	local info = TweenInfo.new(0.6)
	for _, descendant in self.character.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			TweenService:Create(descendant, info, { Transparency = 1 }):Play()
		elseif descendant:IsA("Decal") then
			TweenService:Create(descendant, info, { Transparency = 1 }):Play()
		end
	end
	self:wait(0.7)
end

function Customer:destroy()
	self.alive = false
	if self.character then
		self.character.model:Destroy()
	end
end

-- The shopper's whole visit.
function Customer:run()
	local store = self.store
	if not self:walk(Layout.STREET) or not self:walk(Layout.INSIDE) then
		return
	end

	local rack, slot = store:reserveDress()
	if not rack then
		self:bubble("😢 Sold out!")
		store:customerDisappointed(self)
		if not self:wait(1.5) then
			return
		end
		self:bubble("😞")
		self:leave()
		self:fadeAway()
		return
	end

	self.dress = rack.dress
	self:bubble("💗 " .. rack.dress.name)

	local aisleX = rack.side * Layout.AISLE_X
	if not self:walk(Vector3.new(aisleX, 0, Layout.INSIDE.Z)) or not self:walk(slot.browse) then
		store:cancelReservation(slot)
		return
	end
	self:face(slot.lookAt)
	if not self:wait(Config.Customer.BROWSE_TIME_MIN + math.random() * (Config.Customer.BROWSE_TIME_MAX - Config.Customer.BROWSE_TIME_MIN)) then
		return
	end

	store:takeDress(slot)
	Npc.giveBag(self.character, BAG_COLORS[math.random(1, #BAG_COLORS)])
	self:bubble("🛍️")

	if not self:walk(Vector3.new(aisleX, 0, Layout.BACK_AISLE_Z)) then
		return
	end

	-- Wait in line at the register
	store:joinQueue(self)
	self.queueStart = os.clock()
	local mood = ""
	while self.alive and not self.paid do
		local spot = Layout.queueSpot(self.queueIndex)
		if self:isNear(spot) then
			if not self.atSpot then
				self.atSpot = true
				if self.queueIndex == 1 then
					self:face(Layout.REGISTER)
				else
					self:face(Layout.queueSpot(self.queueIndex - 1))
				end
			end
			task.wait(0.2)
		else
			self.atSpot = false
			self:walk(spot)
		end

		local waited = os.clock() - self.queueStart
		local patience = Config.Customer.PATIENCE
		local newMood = if waited > patience * 0.75 then "😤" elseif waited > patience * 0.45 then "😐" else "💳"
		if newMood ~= mood and not self.paid then
			mood = newMood
			self:bubble(mood)
		end
		if waited > patience and not self.paid and self.alive then
			store:leaveQueue(self)
			store:returnDress(self.dress)
			self:bubble("😠 Too slow!")
			local bag = self.character.model:FindFirstChild("ShoppingBag")
			if bag then
				bag:Destroy()
			end
			local handle = self.character.model:FindFirstChild("Handle")
			if handle then
				handle:Destroy()
			end
			self:leave()
			self:fadeAway()
			return
		end
	end
	if not self.alive then
		return
	end

	self:bubble(if math.random() < 0.5 then "😍" else "💖 Thank you!")
	self:leave()
	self:fadeAway()
end

return Customer
