#!/usr/bin/env node
// Test runner. Bundles every .luau under src/ plus tests/*.spec.luau into one
// script and runs it under the standalone Luau CLI (set $LUAU, or have `luau` on PATH).
//
//   node tests/run.js              run every spec
//   node tests/run.js logic        run only specs whose name contains "logic"

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const root = path.join(__dirname, "..");
const luau = process.env.LUAU || "luau";
const filter = process.argv[2];

function longString(text) {
	let level = 0;
	while (text.includes("]" + "=".repeat(level) + "]")) level++;
	const eq = "=".repeat(level);
	return `[${eq}[\n${text}]${eq}]`;
}

// path keys look like "shared/Config", "server/DataService", "server/init"
const sources = {};
for (const area of ["shared", "server", "client"]) {
	const dir = path.join(root, "src", area);
	for (const file of fs.readdirSync(dir)) {
		if (!file.endsWith(".luau")) continue;
		const name = file.replace(/\.luau$/, "").replace(/^init\.(server|client)$/, "init");
		sources[`${area}/${name}`] = fs.readFileSync(path.join(dir, file), "utf8");
	}
}

const specs = fs
	.readdirSync(__dirname)
	.filter((f) => f.endsWith(".spec.luau") && (!filter || f.includes(filter)))
	.sort();
if (specs.length === 0) {
	console.error("No specs matched.");
	process.exit(1);
}

let out = "local SOURCES = {}\n";
for (const [key, src] of Object.entries(sources)) out += `SOURCES[${JSON.stringify(key)}] = ${longString(src)}\n`;
out += `local MOCK = (function()\n${fs.readFileSync(path.join(__dirname, "robloxmock.luau"), "utf8")}\nend)()\n`;
out += `
local H = {
	SOURCES = SOURCES,
	MOCK = MOCK,
	newWorld = function(opts)
		local world = MOCK.create(opts or {})
		world.mountSources(SOURCES)
		return world
	end,
}
local allOk = true
`;
for (const spec of specs) {
	out += `
do
	print("\\n########## ${spec} ##########")
	local fn, err = loadstring(${longString(fs.readFileSync(path.join(__dirname, spec), "utf8"))}, "=${spec}")
	assert(fn, err)
	setfenv(fn, setmetatable({ H = H }, { __index = _G }))
	local ok = fn()(H)
	if not ok then allOk = false end
end
`;
}
out += `\nif not allOk then error("TESTS FAILED", 0) end\nprint("\\nALL SPECS PASSED")\n`;

const tmp = path.join(os.tmpdir(), "bird-garden-tests.luau");
fs.writeFileSync(tmp, out);
const res = spawnSync(luau, [tmp], { stdio: "inherit" });
process.exit(res.status ?? 1);
