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
- Tool path: `~/.local/bin` or rokit-managed (`rokit.toml`).
