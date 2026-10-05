--[[
	Signal
	Tiny pure-Luau signal (no BindableEvent, no argument copying).
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({}, Signal)
	self._handlers = {} :: { [any]: (...any) -> () }
	return self
end

function Signal:Connect(handler: (...any) -> ())
	local key = {}
	self._handlers[key] = handler
	local connection = { Connected = true }
	function connection.Disconnect(conn)
		conn.Connected = false
		self._handlers[key] = nil
	end
	return connection
end

function Signal:Fire(...)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal:Once(handler: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
