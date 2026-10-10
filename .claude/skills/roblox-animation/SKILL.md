---
name: roblox-animation
description: Make Roblox character animations (R15/R6 - attacks, emotes, idles, walks, hit reactions). Use when the game needs a new animation. Poses are written as data, rendered to a front/side contact sheet for review, linted for broken joints, and exported as a KeyframeSequence.
---

# Roblox animation

## Pipeline
```bash
python -m tools.anim.animate specs/anims/<name>.json --fps 12
# -> out/anims/<name>_sheet.png  (front | side, every frame)
# -> out/anims/<name>.rbxmx      (KeyframeSequence)
```
1. Write poses as data: which joint, rotated how far, at what time (see `specs/anims/wave.json`, format in the tool docstring). Axes: +x swings a limb forward, +z rolls the right side outward (−z for left).
2. Run the tool. Fix every WARN (joint outside natural range, loop seam pop, limb through floor).
3. **Read the contact sheet.** Ask: does it read at a glance? Anticipation before the action, overshoot/settle after, weight on the feet, arcs not straight lines, no limb through the body.
4. Import the `.rbxmx` into Studio (MCP: insert model from file, or user drags it in), open in the Animation Editor to confirm axes on the real rig, then publish → animation id into `Config`.

## Getting good at Roblox-style motion
Claude is not naturally good at this. Improve the skill with references: the user picks Roblox animations
they like; describe their **timing and spacing** (key times, holds, how far each joint travels, easing)
in `references/motion-notes.md`, and reuse those numbers. Typical Roblox feel: snappy (attack hits at
0.1–0.15 s), exaggerated poses, short holds on the strongest pose, Cubic/Back-ish easing out.

## Learned rules
- Draw the torso as an outline on the sheet; parent→shoulder connector lines read as bent arms.
- Keep first and last key identical for loops.
