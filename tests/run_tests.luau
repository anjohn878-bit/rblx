-- Entry point: loads the harness and every *_spec file.
local harnessSource = __readfile("tests/harness.luau")
local Harness = __loadstring(harnessSource, "@tests/harness.luau")()

for _, spec in { "tests/format_spec.luau", "tests/economy_spec.luau", "tests/illness_spec.luau" } do
	print("== " .. spec)
	local fn, err = __loadstring(__readfile(spec), "@" .. spec)
	assert(fn, err)
	fn(Harness)
end

if not Harness.summary() then
	error("tests failed")
end
