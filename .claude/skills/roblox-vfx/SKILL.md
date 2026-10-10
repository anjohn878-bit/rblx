---
name: roblox-vfx
description: Create Roblox visual effects (particles, beams, trails - fireballs, hits, auras, explosions, level-ups). Use when the game needs any VFX. Builds effects from a harvested library of classified building blocks and verifies them with phase-freeze screenshots at start/middle/end.
---

# Roblox VFX

Particle effects can't be simulated faithfully outside Roblox, so this skill doesn't invent
effects from nothing: it **collects** them, turns them into **building blocks**, and **composes**
new effects from those blocks — then checks them frozen in time.

## 1. Harvest (once per pack, user's Studio)
1. User inserts free VFX packs from the Toolbox into `ServerStorage.VFXPacks`.
2. Run `tools/studio/vfx_harvest.luau` via Studio MCP `run_code`. It copies every ParticleEmitter /
   Beam / Trail into `ServerStorage.VFXLibrary/<class>/<id>` (classes: fire, smoke, spark, glow,
   shockwave, slash, electric, water, debris, beam, trail, misc) and prints a JSON index.
3. Save the index to `library/vfx/index.json`. Fix misclassifications by hand-editing `class`.

The library contains other creators' textures: it stays in the user's own place/repo. Share the
harvester, never the library.

## 2. Compose
Write a recipe in `specs/vfx/<effect>.json`:
```json
{"name": "Fireball", "blocks": [
  {"block": "glow_012", "role": "core", "emit": 1, "size": 1.2},
  {"block": "fire_004", "role": "body", "rate": 40},
  {"block": "spark_021", "role": "accent", "emit": 12, "delay": 0.05},
  {"block": "trail_003", "role": "trail"}]}
```
Build it in Studio via MCP `run_code`: clone the blocks from `ServerStorage.VFXLibrary` into one
Attachment under `ReplicatedStorage.VFX.<Name>`, apply the overrides, set an `EmitCount` attribute on
burst emitters. A good effect = **core + body + accent** with one dominant colour family; at most ~4 emitters.

## 3. Phase freeze (verification)
A burst is < 1 s, so a single screenshot is a coin flip. For each phase (start ≈ 0.05 s, middle ≈ 0.3 s,
end ≈ 0.8 s): set `EFFECT_PATH`/`PHASE` in `tools/studio/vfx_phase_freeze.luau`, run it, take an MCP
screenshot, look at it. Pass only if all three read as one coherent effect (shape, colour, no stray
block, fades out rather than popping). Delete `workspace._VFXPreview` afterwards.

## 4. Use in game
Clone from `ReplicatedStorage.VFX` on the client, `:Emit(EmitCount)` each burst emitter, `Debris`
clean-up after the longest lifetime. Server only tells clients *what* and *where* via `Net`.

## Learned rules
- Freeze with `ParticleEmitter.TimeScale = 0`; don't pause the whole game.
- Beams need two Attachments; harvesting a Beam without its attachments gives nothing visible.
