---
name: roblox-sound
description: Add sound effects and music to the Roblox game (hits, explosions, UI clicks, footsteps, ambience). Use when any sound is needed. Builds sounds by layering an already-harvested, named sound library instead of uploading new audio (Open Cloud audio uploads are rate-limited monthly).
---

# Roblox sound

Audio uploads through Open Cloud are capped per month, so new sounds are **combinations of library
sounds**, not new uploads.

## Library
1. User drops sound packs (Toolbox / Creator Store audio they're allowed to use) into `ServerStorage.SoundPacks`.
2. Run `tools/studio/sound_harvest.luau` via MCP; save to `library/sound/catalog.json`.
3. Give every sound a short semantic name + tags (`boom`, `whoosh_light`, `gunshot_heavy`, `ui_click`,
   `fire_crackle`…). Listen-check isn't possible for Claude, so rely on names/lengths and ask the user to
   confirm any sound that will be heard constantly (footsteps, UI clicks, music).
4. Copy the chosen ids into `Library` in `src/shared/Config/Sounds.luau` (names, never raw ids, in code).

## Recipes
In `Config/Sounds.luau` `Recipes`: layers with `sound`, `volume`, `pitch` range (randomised each play —
avoids machine-gun repetition), `delay`. E.g. explosion = low boom + debris (0.05 s later, 0.5 vol) +
high crack. Play with `Sfx.play("Explosion", part)` (`src/client/Sfx.luau`); positional when given a part.

## Rules
- Only upload new audio when no layer combination works, and tell the user it uses quota.
- Mix: UI ≤ 0.5 volume, music ≤ 0.3, impacts 0.6–1.0. Use SoundGroups for master/music/sfx.
