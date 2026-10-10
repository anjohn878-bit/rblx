-- Runs every *.spec.luau in tests/. Usage: lune run tests/run
local fs = require("@lune/fs")
local process = require("@lune/process")
local H = require("./harness")

for _, file in fs.readDir("tests") do
	if string.match(file, "%.spec%.luau$") then
		require("./" .. string.gsub(file, "%.luau$", ""))
	end
end

local r = H.results
for _, failure in r.failures do
	print("FAIL " .. failure)
end
print(`{r.passed} passed, {r.failed} failed`)
process.exit(if r.failed == 0 then 0 else 1)
