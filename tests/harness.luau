-- Minimal test harness for Lune. Specs call describe/it/expect.
local Harness = {}
local results = { passed = 0, failed = 0, failures = {} :: { string } }
local prefix = ""

function Harness.describe(name: string, fn: () -> ())
	local previous = prefix
	prefix = prefix .. name .. " > "
	fn()
	prefix = previous
end

function Harness.it(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, prefix .. name .. ": " .. tostring(err))
	end
end

function Harness.expect(actual: any)
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				error(`expected {tostring(expected)}, got {tostring(actual)}`, 2)
			end
		end,
		toBeNear = function(expected: number, eps: number?)
			if math.abs(actual - expected) > (eps or 1e-6) then
				error(`expected ~{expected}, got {actual}`, 2)
			end
		end,
	}
end

Harness.results = results
return Harness
