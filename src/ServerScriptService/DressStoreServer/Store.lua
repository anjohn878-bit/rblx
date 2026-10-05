-- One dress store plot: who owns it, what is built, the dresses on the racks,
-- the shoppers inside and the line at the register.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local shared = ReplicatedStorage:WaitForChild("DressStore")
local Config = require(shared:WaitForChild("Config"))
local Util = require(shared:WaitForChild("Util"))

local Builders = require(script.Parent.Builders)
local Customer = require(script.Parent.Customer)
local Data = require(script.Parent.DataManager)
local DressModel = require(script.Parent.DressModel)
local Layout = require(script.Parent.Layout)
local Parts = require(script.Parent.Parts)
local Remotes = require(script.Parent.Remotes)

local PAD_TAG = "DressStorePad"

local Store = {}
Store.__index = Store

export type Slot = {
	cf: CFrame,
	browse: Vector3,
	lookAt: Vector3,
	model: Model?,
	reserved: boolean,
}

export type Rack = {
	dress: any,
	side: number,
	slots: { Slot },
	label: TextLabel?,
}

export type Machine = {
	interval: number,
	timer: number,
	light: BasePart?,
}

-- plot: { index, cf, model, labels } created by WorldBuilder
function Store.new(plot)
	local self = setmetatable({}, Store)
	self.index = plot.index
	self.cf = plot.cf :: CFrame
	self.model = plot.model :: Model
	self.labels = plot.labels :: { TextLabel }
	self.ownerBillboard = plot.ownerBillboard :: TextLabel?

	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = self.model
		return f
	end
	self.itemsFolder = folder("Items")
	self.padsFolder = folder("Buttons")
	self.shoppersFolder = folder("Shoppers")

	self.owner = nil :: Player?
	self.session = 0
	self:_clear()
	self:_updateOwnerSign()
	return self
end

function Store:_clear()
	self.owned = {} :: { [string]: boolean }
	self.models = {} :: { [string]: Model }
	self.pads = {} :: { [string]: Model }
	self.padSlots = {} :: { [number]: string }
	self.racks = {} :: { Rack }
	self.machines = {} :: { Machine }
	self.customers = {} :: { [any]: boolean }
	self.queue = {} :: { any }
	self.register = nil :: BasePart?
	self.registerPrompt = nil :: ProximityPrompt?
	self.sewTable = nil :: BasePart?
	self.hasCashier = false
	self.appeal = 0
	self.capacity = Config.Customer.BASE_CAPACITY
	self.priceBonus = 0
	self.lastSoldOutWarning = 0
	self.lastWaitingWarning = 0
	self.published = {} :: { [string]: any }
end

----------------------------------------------------------------------------
-- Coordinates
----------------------------------------------------------------------------

-- Plot-space CFrame -> world CFrame
function Store:at(x: number, y: number, z: number, rotationY: number?): CFrame
	return self.cf * CFrame.new(x, y, z) * CFrame.Angles(0, rotationY or 0, 0)
end

-- Plot-space point on the floor -> world position
function Store:toWorldPoint(localPoint: Vector3): Vector3
	return (self.cf * CFrame.new(localPoint.X, Layout.FLOOR_Y, localPoint.Z)).Position
end

function Store:spawnCFrame(): CFrame
	local p = Layout.PLAYER_SPAWN
	return self.cf * CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(0, math.pi, 0)
end

----------------------------------------------------------------------------
-- Owner
----------------------------------------------------------------------------

function Store:_updateOwnerSign()
	local text = if self.owner then self.owner.DisplayName .. "'s Dress Store" else "Empty Store"
	for _, label in self.labels do
		label.Text = text
	end
	if self.ownerBillboard then
		self.ownerBillboard.Text = if self.owner then "👗 " .. self.owner.DisplayName else ""
	end
	self.model:SetAttribute("OwnerUserId", if self.owner then self.owner.UserId else 0)
end

function Store:isOwnedBy(player: Player): boolean
	return self.owner == player
end

function Store:assign(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	self.owner = player
	self.session += 1
	self:_clear()
	self:_updateOwnerSign()

	for _, item in Config.Items do
		if profile.data.owned[item.id] then
			self.owned[item.id] = true
			self:_build(item, false)
		end
	end
	self:_recalculate()
	self:_refreshPads()
	self:_startLoop()
	self:_publish()
end

function Store:release()
	self.session += 1
	for customer in self.customers do
		customer:destroy()
	end
	self.itemsFolder:ClearAllChildren()
	self.padsFolder:ClearAllChildren()
	self.shoppersFolder:ClearAllChildren()
	self:_clear()
	self.owner = nil
	self:_updateOwnerSign()
end

----------------------------------------------------------------------------
-- Building things
----------------------------------------------------------------------------

local function requirementsMet(owned: { [string]: boolean }, item): boolean
	for _, required in item.requires do
		if not owned[required] then
			return false
		end
	end
	return true
end

function Store:allBuilt(): boolean
	for _, item in Config.Items do
		if not self.owned[item.id] then
			return false
		end
	end
	return true
end

local function popIn(model: Model)
	local info = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(0.35)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Anchored and part.Transparency < 1 then
			local finalCFrame = part.CFrame
			local finalTransparency = part.Transparency
			part.CFrame = finalCFrame + Vector3.new(0, 2.5, 0)
			part.Transparency = 1
			TweenService:Create(part, info, { CFrame = finalCFrame }):Play()
			TweenService:Create(part, fade, { Transparency = finalTransparency }):Play()
		end
	end
end

function Store:_build(item, animate: boolean)
	local model = Instance.new("Model")
	model.Name = item.id
	local builder = Builders[item.builder or item.id]
	if builder then
		local ok, err = pcall(builder, self, model, item)
		if not ok then
			warn("[DressStore] Building " .. item.id .. " failed:", err)
		end
	else
		warn("[DressStore] No builder for item " .. item.id)
	end
	model.Parent = self.itemsFolder
	self.models[item.id] = model
	if animate then
		popIn(model)
	end
end

function Store:_recalculate()
	local appeal = Config.Customer.RACK_APPEAL * #self.racks
	local capacity = Config.Customer.BASE_CAPACITY
	local priceBonus = 0
	for _, item in Config.Items do
		if self.owned[item.id] then
			appeal += item.appeal or 0
			capacity += item.capacity or 0
			priceBonus += item.priceBonus or 0
		end
	end
	self.appeal = appeal
	self.capacity = math.min(capacity, Layout.MAX_QUEUE)
	self.priceBonus = priceBonus
end

function Store:_createPad(item)
	local slotIndex = nil
	for i = 1, #Layout.PAD_SLOTS do
		if not self.padSlots[i] then
			slotIndex = i
			break
		end
	end
	if not slotIndex then
		warn("[DressStore] Not enough button spots for " .. item.id)
		return
	end
	self.padSlots[slotIndex] = item.id
	local spot = Layout.PAD_SLOTS[slotIndex]

	local pad = Instance.new("Model")
	pad.Name = "Buy_" .. item.id
	pad:SetAttribute("Slot", slotIndex)

	local base = Parts.cylinder(pad, self:at(spot.X, 0.3, spot.Z), 0.3, 5.2, Color3.fromRGB(60, 40, 70), Enum.Material.SmoothPlastic)
	base.Name = "Base"
	local button = Parts.cylinder(pad, self:at(spot.X, 0.5, spot.Z), 0.25, 4.3, Color3.fromRGB(90, 220, 120), Enum.Material.Neon)
	button.Name = "Button"
	button.CanCollide = false

	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.new(8, 0, 3.4, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	gui.MaxDistance = 55
	gui.LightInfluence = 0
	gui.Adornee = button
	gui.Parent = button

	local function label(name: string, text: string, y: number, height: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0, y)
		l.Size = UDim2.fromScale(1, height)
		l.Font = Enum.Font.FredokaOne
		l.Text = text
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.1
		l.TextStrokeColor3 = Color3.fromRGB(70, 20, 60)
		l.Parent = gui
		return l
	end
	label("ItemName", item.name, 0, 0.42, Color3.fromRGB(255, 255, 255))
	label("Price", Util.formatPrice(item.price), 0.4, 0.36, Color3.fromRGB(120, 255, 140))
	label("Info", item.info or "", 0.76, 0.24, Color3.fromRGB(255, 220, 240))

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = if item.price > 0 then "Buy " .. Util.formatPrice(item.price) else "Build (FREE)"
	prompt.ObjectText = item.name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = button

	prompt.Triggered:Connect(function(player)
		self:tryPurchase(player, item.id)
	end)

	pad:SetAttribute("ItemId", item.id)
	pad:SetAttribute("Price", item.price)
	pad:SetAttribute("OwnerUserId", if self.owner then self.owner.UserId else 0)
	pad:AddTag(PAD_TAG)
	pad.Parent = self.padsFolder
	self.pads[item.id] = pad
end

function Store:_removePad(itemId: string)
	local pad = self.pads[itemId]
	if pad then
		local slot = pad:GetAttribute("Slot")
		if slot then
			self.padSlots[slot] = nil
		end
		pad:Destroy()
		self.pads[itemId] = nil
	end
end

function Store:_refreshPads()
	for _, item in Config.Items do
		local available = not self.owned[item.id] and requirementsMet(self.owned, item)
		if available and not self.pads[item.id] then
			self:_createPad(item)
		elseif not available and self.pads[item.id] then
			self:_removePad(item.id)
		end
	end
end

function Store:tryPurchase(player: Player, itemId: string)
	local item = Config.ItemById[itemId]
	if not item or self.owned[itemId] then
		return
	end
	if player ~= self.owner then
		Remotes.notify(player, "This isn't your store! Yours has your name on the gate.", "error")
		return
	end
	if not requirementsMet(self.owned, item) then
		return
	end
	if not Data.spend(player, item.price) then
		local missing = item.price - Data.getCash(player)
		Remotes.notify(player, "You need " .. Util.formatMoney(missing) .. " more for " .. item.name .. "!", "error")
		return
	end

	local pad = self.pads[itemId]
	local button = if pad then pad:FindFirstChild("Button") :: BasePart? else nil
	local popupAt = if button then button.Position else nil

	self.owned[itemId] = true
	Data.setOwned(player, itemId)
	self:_removePad(itemId)
	self:_build(item, true)
	self:_recalculate()
	self:_refreshPads()

	if popupAt then
		Remotes.popup(popupAt + Vector3.new(0, 3, 0), "✨ " .. item.name .. "!", "build", player.UserId)
	end
	Remotes.notify(player, "You built: " .. item.name .. "!", "success")
	if self:allBuilt() then
		Remotes.notify(player, "Your dress store is complete! 🎉 Press Rebirth to start again with more money.", "success")
	end
	self:_publish()
end

----------------------------------------------------------------------------
-- Called by the builders
----------------------------------------------------------------------------

function Store:addRack(rack: Rack)
	table.insert(self.racks, rack)
	for _ = 1, Config.Sewing.NEW_RACK_STOCK do
		self:_putDressOn(rack)
	end
	self:_updateRackLabel(rack)
end

function Store:addMachine(interval: number, light: BasePart?)
	table.insert(self.machines, { interval = interval, timer = 0, light = light })
end

function Store:setRegister(part: BasePart, prompt: ProximityPrompt)
	self.register = part
	self.registerPrompt = prompt
	prompt.Enabled = false
	prompt.Triggered:Connect(function(player)
		if player ~= self.owner then
			Remotes.notify(player, "Only the store owner can ring up customers.", "error")
			return
		end
		local front = self.queue[1]
		if front and front:isReadyToPay() then
			self:checkout(front)
		end
	end)
end

function Store:setSewingTable(part: BasePart, prompt: ProximityPrompt)
	self.sewTable = part
	prompt.Triggered:Connect(function(player)
		if player ~= self.owner then
			Remotes.notify(player, "Only the store owner can sew here.", "error")
			return
		end
		if #self.racks == 0 then
			Remotes.notify(player, "Build a dress rack first so you have somewhere to hang your dresses!", "error")
			return
		end
		if self:addDress() then
			Remotes.popup(part.Position + Vector3.new(0, 3, 0), "+1 👗", "dress", player.UserId)
		else
			Remotes.notify(player, "All your racks are full! Wait for shoppers or build another rack.", "info")
		end
	end)
end

function Store:setCashier()
	self.hasCashier = true
end

----------------------------------------------------------------------------
-- Dresses on racks
----------------------------------------------------------------------------

local function countDresses(rack: Rack): number
	local n = 0
	for _, slot in rack.slots do
		if slot.model then
			n += 1
		end
	end
	return n
end

function Store:_updateRackLabel(rack: Rack)
	if rack.label then
		rack.label.Text = string.format(
			"👗 %s  %s\n%d / %d",
			rack.dress.name,
			Util.formatMoney(rack.dress.price),
			countDresses(rack),
			#rack.slots
		)
	end
end

function Store:_putDressOn(rack: Rack): boolean
	for _, slot in rack.slots do
		if not slot.model then
			local dressModel = DressModel.build(rack.dress)
			dressModel:PivotTo(slot.cf)
			dressModel.Parent = self.itemsFolder
			slot.model = dressModel
			slot.reserved = false
			self:_updateRackLabel(rack)
			return true
		end
	end
	return false
end

-- Sews one dress and hangs it on the emptiest rack (fancier dresses first on ties).
function Store:addDress(): boolean
	local best: Rack? = nil
	local bestFill = math.huge
	for _, rack in self.racks do
		local count = countDresses(rack)
		if count < #rack.slots then
			local fill = count / #rack.slots
			if fill < bestFill or (fill == bestFill and best and rack.dress.price > best.dress.price) then
				best = rack
				bestFill = fill
			end
		end
	end
	if best then
		return self:_putDressOn(best)
	end
	return false
end

function Store:reserveDress(): (Rack?, Slot?)
	local choices = {}
	for _, rack in self.racks do
		for _, slot in rack.slots do
			if slot.model and not slot.reserved then
				table.insert(choices, { rack = rack, slot = slot })
			end
		end
	end
	if #choices == 0 then
		return nil, nil
	end
	local choice = choices[math.random(1, #choices)]
	choice.slot.reserved = true
	return choice.rack, choice.slot
end

function Store:cancelReservation(slot: Slot)
	slot.reserved = false
end

function Store:takeDress(slot: Slot)
	if slot.model then
		slot.model:Destroy()
		slot.model = nil
	end
	slot.reserved = false
	for _, rack in self.racks do
		if table.find(rack.slots, slot) then
			self:_updateRackLabel(rack)
		end
	end
end

-- A shopper left without paying: the dress goes back on its rack.
function Store:returnDress(dress)
	for _, rack in self.racks do
		if rack.dress == dress then
			self:_putDressOn(rack)
			return
		end
	end
end

function Store:customerDisappointed(_customer)
	local owner = self.owner
	if owner and os.clock() - self.lastSoldOutWarning > 20 then
		self.lastSoldOutWarning = os.clock()
		Remotes.notify(owner, "A shopper found no dresses! Hold E at your Sewing Table to sew more. ✂️", "error")
	end
end

function Store:stockCounts(): (number, number)
	local stock, max = 0, 0
	for _, rack in self.racks do
		stock += countDresses(rack)
		max += #rack.slots
	end
	return stock, max
end

----------------------------------------------------------------------------
-- Shoppers and the register line
----------------------------------------------------------------------------

function Store:customerCount(): number
	local n = 0
	for _ in self.customers do
		n += 1
	end
	return n
end

function Store:_spawnCustomer()
	local session = self.session
	local customer = Customer.new(self)
	self.customers[customer] = true
	task.spawn(function()
		local ok, err = pcall(function()
			if customer:spawn(self.shoppersFolder) and self.session == session then
				customer:run()
			end
		end)
		if not ok then
			warn("[DressStore] Shopper error:", err)
		end
		if self.session == session then
			self:leaveQueue(customer)
			self.customers[customer] = nil
		end
		customer:destroy()
	end)
end

function Store:joinQueue(customer)
	if not table.find(self.queue, customer) then
		table.insert(self.queue, customer)
	end
	self:_updateQueue()
end

function Store:leaveQueue(customer)
	local index = table.find(self.queue, customer)
	if index then
		table.remove(self.queue, index)
		self:_updateQueue()
	end
end

function Store:_updateQueue()
	for i, customer in self.queue do
		if customer.queueIndex ~= i then
			customer.queueIndex = i
			customer.atSpot = false
		end
	end
end

function Store:checkout(customer): boolean
	if not customer:isReadyToPay() then
		return false
	end
	local owner = self.owner
	if not owner then
		return false
	end
	self:leaveQueue(customer)
	customer:markPaid()

	local amount = math.floor(customer.dress.price * (1 + self.priceBonus) * Data.multiplier(owner) + 0.5)
	Data.addCash(owner, amount)
	Data.addSold(owner, 1)

	local at = if self.register then self.register.Position else self:toWorldPoint(Layout.REGISTER)
	Remotes.popup(at + Vector3.new(0, 3, 0), "+" .. Util.formatMoney(amount), "money", owner.UserId)
	return true
end

function Store:_flashMachine(machine: Machine)
	local light = machine.light
	if not light then
		return
	end
	light.Color = Color3.fromRGB(120, 255, 150)
	task.delay(0.4, function()
		if light.Parent then
			light.Color = Color3.fromRGB(255, 120, 190)
		end
	end)
	Remotes.popup(light.Position + Vector3.new(0, 2, 0), "+1 👗", "dress", if self.owner then self.owner.UserId else 0)
end

function Store:_startLoop()
	local session = self.session
	task.spawn(function()
		local spawnTimer = 2
		local cashierTimer = 0
		local publishTimer = 0
		while self.session == session do
			local dt = task.wait(0.25)
			if self.session ~= session then
				break
			end

			-- Sewing machines
			for _, machine in self.machines do
				machine.timer += dt
				if machine.timer >= machine.interval then
					machine.timer -= machine.interval
					if self:addDress() then
						self:_flashMachine(machine)
					end
				end
			end

			-- New shoppers
			if self.register and #self.racks > 0 then
				spawnTimer -= dt
				if spawnTimer <= 0 then
					local interval = Config.Customer.BASE_SPAWN_INTERVAL / (1 + self.appeal)
					spawnTimer = interval * (0.8 + math.random() * 0.4)
					if self:customerCount() < self.capacity then
						self:_spawnCustomer()
					end
				end
			end

			-- Register line
			local front = self.queue[1]
			local ready = front ~= nil and front:isReadyToPay()
			if self.registerPrompt then
				self.registerPrompt.Enabled = ready
			end
			if self.hasCashier and ready then
				cashierTimer += dt
				if cashierTimer >= Config.Customer.CASHIER_SPEED then
					cashierTimer = 0
					self:checkout(front)
				end
			else
				cashierTimer = 0
			end
			if ready and not self.hasCashier and self.owner and os.clock() - self.lastWaitingWarning > 25 then
				if os.clock() - front.queueStart > 6 then
					self.lastWaitingWarning = os.clock()
					Remotes.notify(self.owner, "A shopper is waiting to pay! Press E at the Cash Register. 💳", "info")
				end
			end

			publishTimer += dt
			if publishTimer >= 0.5 then
				publishTimer = 0
				self:_publish()
			end
		end
	end)
end

----------------------------------------------------------------------------
-- Status for the owner's screen (sent as player attributes)
----------------------------------------------------------------------------

function Store:_publish()
	local owner = self.owner
	if not owner then
		return
	end
	local stock, max = self:stockCounts()
	local ownedCount = 0
	for _ in self.owned do
		ownedCount += 1
	end
	local nextItem = nil
	for _, item in Config.Items do
		if not self.owned[item.id] and requirementsMet(self.owned, item) then
			if not nextItem or item.price < nextItem.price then
				nextItem = item
			end
		end
	end

	local values = {
		PlotIndex = self.index,
		Stock = stock,
		StockMax = max,
		Shoppers = self:customerCount(),
		Waiting = #self.queue,
		HasRegister = self.register ~= nil,
		HasCashier = self.hasCashier,
		HasSewingTable = self.sewTable ~= nil,
		Racks = #self.racks,
		ItemsOwned = ownedCount,
		ItemsTotal = #Config.Items,
		CanRebirth = self:allBuilt(),
		NextItem = if nextItem then nextItem.name else "",
		NextPrice = if nextItem then nextItem.price else 0,
		PriceBonus = self.priceBonus,
	}
	for key, value in values do
		if self.published[key] ~= value then
			self.published[key] = value
			owner:SetAttribute(key, value)
		end
	end
end

return Store
