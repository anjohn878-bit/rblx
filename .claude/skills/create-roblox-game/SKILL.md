---
name: create-roblox-game
description: Make a whole Roblox game (or a big new feature/mode) from an idea. Use when the user asks to create/build/make a Roblox game. Acts as the manager - owns research, game design and final assembly, and hands every discipline to its own skill (roblox-code, roblox-ui, roblox-map, roblox-3d-model, roblox-vfx, roblox-sound, roblox-animation).
---

# Create a Roblox game (manager skill)

This skill owns the three jobs nothing else does: **research, design, assembly**. Everything
else is delegated to the discipline skills, each with its own tools and its own way of checking its work.

## 0. Preflight (every session)
- `scripts/check.sh` is green on the current tree. If not, fix that first.
- Which capabilities exist right now? Check and note in the design doc:
  Studio MCP connected (official / fallback) · `CLOUDFLARE_*` · `KAGGLE_*` or `~/.kaggle/kaggle.json` ·
  `ROBLOX_API_KEY` + `ROBLOX_USER_ID` · Blender (`blender` or `python3 -c "import bpy"`).
  Missing ones → plan around them and tell the user exactly what to set up (SETUP.md).

## 1. Research
- Pin down with the user: genre, core loop in one sentence, session length, target device (phone-first?), monetisation (if any), art style references.
- Study comparable successful Roblox games: what is the loop, the first 60 seconds, the progression hooks, the UI layout conventions players expect. Write findings — not copied content — to `docs/design/<game>/research.md`.

## 2. Design → `docs/design/<game>/design.md` (template: `docs/design/TEMPLATE.md`)
- Core loop, progression, economy numbers (go straight into `Config/`), win/lose conditions.
- Every screen (→ roblox-ui), every map space with its POIs and intended routes (→ roblox-map),
  asset list split hard-surface vs AI (→ roblox-3d-model), VFX list, sound list, animation list.
- Net message list (→ `Net.luau`). Rules to unit-test.
- Get the user's OK on the design before building.

## 3. Plan
Order work so something playable exists early:
1. Config + Rules + tests (roblox-code) → gates green.
2. Greybox map that passes the nine checks (roblox-map).
3. Server/client loop wired through Net; playtest via MCP, read the output log.
4. UI screens (roblox-ui).
5. Assets (roblox-3d-model), then dress the map; re-run map checks.
6. VFX, sound, animation.
7. Balance pass: change numbers in `Config/` only.

## 4. Delegate & verify
For each task, invoke the discipline skill and require its proof: gates green, checker output,
preview/sheet/turntable images that Claude actually looked at, MCP playtest log.
A task is not done on "it should work".

## 5. Assemble & ship checklist
- [ ] `scripts/check.sh` green · [ ] map report 0 problems (or justified `_ok` tags) · [ ] UI check 0 problems
- [ ] Playtest: join, core loop x3, leave/rejoin; no errors in output · [ ] all asset ids in `assets.lock.json`
- [ ] Every mesh ≤ 20k tris · [ ] licences recorded for every generated/harvested asset
- [ ] Mobile: playtest with the device emulator at a phone size

## 6. Learn
Anything that broke and cost time → write it as a rule (with the reason) in the relevant skill's
"Learned rules" or `roblox-code` traps, and add a regression test if a tool was at fault.
