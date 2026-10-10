---
name: roblox-code
description: Write or change Roblox game code (Luau) in this repo - game rules, server/client scripts, remotes, config. Use for any gameplay logic, bug fix, balancing change, or new system. Enforces the four gates (rojo build, tests, selene, stylua) before anything reaches Studio.
---

# Roblox code

Claude can't watch play mode: screenshots only work in edit mode and the only
thing that comes back from a running game is the output log. So **as much of the
game as possible must be checkable while it sits still.**

## Layout (Rojo, files are the source of truth)

| Path | Synced to | What goes there |
| --- | --- | --- |
| `src/shared/Config/*.luau` | ReplicatedStorage.Shared.Config | Every tweakable number (speed, damage, prices). Plain tables only. |
| `src/shared/Rules/*.luau` | ReplicatedStorage.Shared.Rules | Pure game rules: numbers in, numbers out. **No Roblox objects, no `game`, no `require` of Config** — config is passed in as an argument so Lune can test it. |
| `src/shared/Net.luau` | ReplicatedStorage.Shared.Net | The ONE list of every RemoteEvent/RemoteFunction name. |
| `src/server/` | ServerScriptService.Server | `*.server.luau` scripts and server modules. |
| `src/client/` | StarterPlayerScripts.Client | `*.client.luau`, UI, Sfx. |
| `tests/*.spec.luau` | — | Lune specs for Rules (run without Roblox). |

## The five rules

1. **Code lives in files, never typed into Studio.** Studio and files drift apart and the game dies. If you must test a snippet in Studio via MCP, port it back to `src/` the same turn.
2. **Every number you'd tweak lives in `Config/`.** Balancing = editing data, not code.
3. **All player↔server messages go through `Net.luau`.** Add the name to `Net.Events`/`Net.Functions`; never `Instance.new("RemoteEvent")` elsewhere. Server validates every client request (never trust client numbers).
4. **Rules are pure and tested.** New rule → new spec in `tests/`. A bug in a rule → first write the failing spec, then fix.
5. **Read the traps list below before writing code** and add to it whenever something costs time.

## Workflow

1. New project only: run `scripts/check.sh` on the empty scaffold first. If the start is red you can't tell your mistakes from leftover slop.
2. Write/modify code following the layout above.
3. Run `scripts/check.sh` — all four gates: `rojo build` (~1s, catches broken files/project), Lune + pytest tests, `selene` (lint; warnings fail the gate), `stylua --check`. Run `stylua src tests` to auto-format.
4. Only when green: sync with `rojo serve` (user's machine) and play-test via the Studio MCP. Read the output log for `[Server]`/`[Client]` prints and errors.
5. Something broke in play mode → reproduce it in a Rules spec if at all possible, fix, re-run gates.

## Studio MCP

- Prefer the **official Roblox Studio MCP** (has play-mode tools: start/stop play test, read output, run code, screenshot in edit mode).
- If its calls fail/time out twice, fall back to the third-party MCP for edit-mode work and tell the user the official one needs restarting (Studio → Assistant → ⋯ → Manage MCP servers).

## Traps (each cost real time — keep adding)

- `Humanoid.JumpHeight` is ignored unless `UseJumpPower = false`.
- Lune `require` paths are relative to the file (`"../src/shared/Rules/X"`); Roblox requires use instances. That's why Rules never require Config.
- `selene` needs the Roblox API dump from setup.rbxcdn.com; `scripts/check.sh` falls back to `roblox_offline.yml` when it's unreachable (sandboxed cloud).
- With `ZIndexBehavior.Sibling`, children ALWAYS draw over their parent — shadows/backgrounds must be sibling layers (see `src/client/UI/Depth.luau`).
- Don't fire remotes every frame; batch state into one `StateChanged` event.
- `PlayerAdded` can fire before your connection on a fast join in Studio — also loop `Players:GetPlayers()` when the script starts if it matters.
- Windows Git converts LF→CRLF on checkout and StyLua then fails every file: `.gitattributes` pins `eol=lf`. Write generated files with `newline="\n"`.
