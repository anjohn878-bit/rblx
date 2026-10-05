--[[
	Minimal test framework: T.test(name, fn) registers, T.run() executes and reports.
	Assertion helpers raise errors with readable messages.
]]

local process = require("@lune/process")

local T = {}

local tests = {}

function T.test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

local function show(value): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function T.eq(actual, expected, message: string?)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", message and (message .. ": ") or "", show(expected), show(actual)), 2)
	end
end

function T.near(actual: number, expected: number, tolerance: number?, message: string?)
	tolerance = tolerance or 1e-6
	if math.abs(actual - expected) > tolerance then
		error(string.format("%sexpected %s ± %s, got %s", message and (message .. ": ") or "", show(expected), show(tolerance), show(actual)), 2)
	end
end

function T.truthy(value, message: string?)
	if not value then
		error(message or ("expected a truthy value, got " .. show(value)), 2)
	end
end

function T.falsy(value, message: string?)
	if value then
		error(message or ("expected a falsy value, got " .. show(value)), 2)
	end
end

function T.throws(fn: () -> (), needle: string?, message: string?)
	local ok, err = pcall(fn)
	if ok then
		error(message or "expected the call to throw, but it did not", 2)
	end
	if needle and not string.find(tostring(err), needle, 1, true) then
		error(string.format("expected error containing %s, got %s", show(needle), tostring(err)), 2)
	end
end

function T.run(): boolean
	local failed = 0
	for _, entry in tests do
		local ok, err = pcall(entry.fn)
		if ok then
			print("  ok   " .. entry.name)
		else
			failed += 1
			print("  FAIL " .. entry.name)
			for line in string.gmatch(tostring(err), "[^\n]+") do
				if not line:find("Stack Begin") and not line:find("Stack End") then
					print("         " .. line)
				end
			end
		end
	end
	print(string.format("\n%d passed, %d failed", #tests - failed, failed))
	return failed == 0
end

function T.exit(ok: boolean)
	process.exit(ok and 0 or 1)
end

return T
