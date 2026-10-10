---
name: roblox-map
description: Design, build and verify Roblox maps/levels/arenas/obbies. Use when creating or changing any playable space. Measures reachability, falls, sight lines and geometry with the game's real movement numbers (nine checks), and keeps maps made of optimised meshes rather than piles of parts.
---

# Roblox maps

A map isn't a pile of parts — it's a space a player moves through, and the important
questions have measurable answers: can you get there, can you get back, can you see across,
how long do you fall.

## Two halves

### 1. Usable (measured)
```bash
# from Studio (MCP run_code): paste tools/studio/export_map.luau, copy the JSON between
# BEGIN_JSON/END_JSON into specs/maps/<name>.json, then:
python -m tools.map.mapcheck specs/maps/<name>.json --report out/maps/<name>.md
```
Movement numbers are read from `src/shared/Config/Movement.luau` and each is labelled with its source
line; every assumption is listed in the report. The nine checks:

1. Floating parts · 2. Tops you can't stand on (too small / no headroom) · 3. High ground nobody can reach ·
4. Places reachable that shouldn't be (`noreach`) · 5. Pockets you fall into and can't climb out of ·
6. Sight lines too open (>85%) or too closed (<25%) between POIs · 7. Parts stuck inside each other ·
8. Rings that aren't evenly spaced · 9. Falls shorter than the ragdoll recovery time / overly long falls.

Tag parts (CollectionService tag or `MapTags` attribute): `spawn`, `poi`, `noreach`, `decor`,
`floating_ok`, `overlap_ok`, `oneway_ok`, `kill`, `ring:<id>`. A failing check is fixed in the map,
or — if intentional — tagged with the `_ok` tag and the reason written in the design doc.

### 2. Looks good (reviewed)
- Build from meshes (`roblox-3d-model` skill, or `tools/blender/hardsurface.py` for hard-edged props), not raw parts. Parts are fine for invisible collision and greybox.
- Greybox first → pass the nine checks → then dress with meshes → re-export and re-check (meshes shift collision).
- Style: if the user names games they like, gather screenshots, write the *principles* (palette, shape language, texture stylisation, prop density) into `references/style.md`, and design an original map from them.
- Screenshot the dressed map in edit mode from spawn, from each POI and from above; look at every shot.

### Optimisation gate (every model, before import)
- ≤ 20,000 triangles per mesh (Roblox limit); target 2–10k for props. `decimate_bake.py` refuses over-limit output.
- Collision: `CollisionFidelity = Box/Hull` for props; precise only where players walk on detail.
- Reuse meshes (same MeshId) instead of uploading near-duplicates.

## Learned rules
- glTF/OBJ imports split vertices per face → always merge by distance before decimating (done in `decimate_bake.py`).
- A part resting ON a top is not a ceiling — headroom only counts parts hanging above the whole surface.
- Spawn-missing maps must still run the static checks (7, 8), not bail early.
