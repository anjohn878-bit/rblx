--!strict
-- Minimal signal so UI modules can react to state changes.

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: () -> () }
export type Signal = typeof(setmetatable({} :: { handlers: { [{}]: (...any) -> () } }, Signal))

function Signal.new(): Signal
	return setmetatable({ handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	local token = {}
	self.handlers[token] = fn
	return {
		Disconnect = function()
			self.handlers[token] = nil
		end,
	}
end

function Signal.Fire(self: Signal, ...: any)
	for _, fn in table.clone(self.handlers) do
		task.spawn(fn, ...)
	end
end

return Signal
