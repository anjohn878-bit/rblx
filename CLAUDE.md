# rblx — AI Roblox game workflow

Claude is the brain; every discipline has its own skill, tools and way of checking its work.
Start any "make a game" request with the **create-roblox-game** skill (`.claude/skills/`).

| Need | Skill | Proof it works |
| --- | --- | --- |
| Game logic, remotes, config | roblox-code | `scripts/check.sh` green, MCP playtest log |
| Screens, buttons, icons | roblox-ui | `tools/ui/uikit.py check` 0 problems + previews looked at |
| Levels / arenas | roblox-map | `tools/map/mapcheck.py` 0 problems + screenshots |
| Meshes | roblox-3d-model | turntable sheet looked at, ≤ 20k tris |
| Effects | roblox-vfx | phase-freeze screenshots start/middle/end |
| Sound | roblox-sound | recipe plays, no new uploads unless needed |
| Animation | roblox-animation | contact sheet looked at, lint clean |

## Non-negotiables
1. Code lives in `src/` files and syncs with Rojo — never typed straight into Studio.
2. Tweakable numbers live in `src/shared/Config/`.
3. Every remote is named in `src/shared/Net.luau`.
4. `scripts/check.sh` (rojo build · tests · selene · stylua) passes before anything goes to Studio.
5. Never ask for or accept API keys in chat. Keys are environment variables on the user's machine (SETUP.md).
6. When something breaks and gets fixed, write the rule + reason into the relevant skill ("Learned rules") and add a regression test when a tool was at fault.

## Environment notes
- Studio MCP: prefer the official Roblox Studio MCP; fall back to the third-party one if it fails twice.
- Cloud sessions (claude.ai/code) have no Studio: there, work offline (code, specs, checks, Blender, previews) and leave Studio steps for a desktop session.
- Windows: run the gates with `powershell -ExecutionPolicy Bypass -File scripts\check.ps1` (bash quoting through PowerShell breaks).
- Windows Python: use Python **3.13** for every tool (it has `bpy`/Blender, pillow, pytest, kaggle):
  `py -3.13 ...`, or if `py` isn't found, `$env:LOCALAPPDATA\Python\pythoncore-3.13-64\python.exe ...`.
  Plain `python` may be 3.14, which has no `bpy` - don't install packages into it.
- Studio: only play-test in the place connected to `rojo serve` (the Baseplate for this repo). If Studio has another game open, ask the user to switch; never sync this project into another game.
- Tool path: `~/.local/bin` or rokit-managed (`rokit.toml`).
