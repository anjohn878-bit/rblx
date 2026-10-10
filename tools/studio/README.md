# Studio-side scripts

These run **inside Roblox Studio** through the Studio MCP (`run_code` / execute-Luau
tool). Claude pastes the file's contents into the tool call. They only read the
place or create temporary preview objects; game code lives in `src/` and syncs via Rojo.

| Script | Purpose |
| --- | --- |
| `export_map.luau` | Dump `workspace.Map` parts as JSON → save to `specs/maps/<name>.json` → `python -m tools.map.mapcheck` |
| `vfx_harvest.luau` | Classify every emitter/beam/trail in `ServerStorage.VFXPacks` into building blocks under `ServerStorage.VFXLibrary` and print a JSON index |
| `vfx_phase_freeze.luau` | Spawn an effect in front of the camera, emit, wait to a phase time, freeze (TimeScale 0) for a screenshot |
| `sound_harvest.luau` | List every Sound in `ServerStorage.SoundPacks` as JSON for `library/sound/catalog.json` |

Output comes back through the output log, so scripts print JSON between
`BEGIN_JSON` / `END_JSON` markers in chunks of ≤ 3,000 characters.
