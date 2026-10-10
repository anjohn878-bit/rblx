---
name: roblox-ui
description: Design and build Roblox game UI (HUDs, shops, menus, popups, icons). Use whenever a screen, button, panel or icon is needed or changed. One JSON spec produces the preview image, the generated Luau UI module, and passes an automatic layout checker at four real screen sizes.
---

# Roblox UI

No design tool: a design is just a picture and the real thing drifts from it.
**One spec → three outputs** that can't disagree, because they share one layout engine.

```
specs/ui/<name>.json  ──►  out/ui/<Screen>_<size>.png       (preview)
                      ──►  src/client/UI/Generated/<Screen>.luau  (the game UI)
                      ──►  checker at phone_small / phone / tablet / desktop_hd
```

## Commands

```bash
python -m tools.ui.uikit all specs/ui/hud.json   # check + preview + build
```
Then LOOK at every preview PNG (Read tool) before calling it done. Mount in game with
`UI.mount("<Screen>")` from `src/client/UI/init.luau`; elements are in `refs["Screen.Path.To.Node"]`.

## Spec format

Node: `name`, `type` (`Panel` | `Button` | `Label` | `Icon` | `Group`), `size` / `pos` as UDim2 `[xScale, xOffset, yScale, yOffset]` (offsets authored at 1080p, auto-scaled), `anchor`, `text`, `textSize`, `textAlign`, `color` (theme key or hex), `icon`, `padding`, `list` (`{"dir": "x"|"y", "gap": px, "align": "center"|"start"}`), `aspect`, `centered` (`"x"`, `"y"`, `"xy"` — measured to ±1.5px), `layer` / `allowOverlap` (intentional stacking), `children`.
Theme overrides go in `"theme"` (see `DEFAULT_THEME` in `tools/ui/uikit.py`).

## The depth stack (automatic on every Panel/Button)

Blue-shifted drop shadow · top-lift gradient · **one outline thickness everywhere** · rounded corners.
Mixed outline thicknesses are the #1 giveaway of beginner/AI UI — never override stroke per element.

## Checker rules (fail = fix the spec, never loosen the rule without the user)

- Buttons ≥ 40×40 px at every size (thumb-tappable). Phone scale floor is 0.55 → author buttons ≥ 80 px tall.
- Siblings never touch; children stay inside parents; nothing off-screen.
- `centered` elements within 1.5 px.
- Text ≥ 11 px after scaling and never taller than its box.
- No Panel that exists only to draw a box around a single Button (AI habit).
- Nothing over Roblox's own UI: menu buttons top-left (0,0,230,64 px, all devices), mobile thumbstick bottom-left and jump button bottom-right (phones/tablets). Previews draw these zones in red. Screens with `"modal": true` may cover the thumb zones (player isn't moving), never the menu.

## Icons — never emoji

```bash
python -m tools.imagegen.flux --preset icon "gold coin" -o assets/icons/coin.png
```
Look at it; re-prompt until it reads at 48 px. Remove the white background if needed, upload with
`python -m tools.roblox.opencloud_upload assets/icons/coin.png --type Decal --name "icon coin"`, and add the
id to `src/client/UI/Icons.luau`. Previews use `assets/icons/<name>.png` automatically.

## Style templates

The default theme is our own. To adopt a look the user likes, have them provide screenshots of
games they admire; extract **principles** (palette relationships, corner radius, outline weight, shadow
depth, density, type scale) into a new theme block + notes in `references/styles.md`. Build an original
template from those principles — never trace or copy another game's art, logos or icons.

## Learned rules

- Children render above parents in Sibling mode → depth layers are siblings inside a transparent container (`Depth.luau`).
- A list that repositions a child must re-lay out that child's subtree (fixed in `layout_children`).
- Pure scale-by-height makes phone buttons ~30 px; keep the 0.55 scale floor in BOTH `uikit.py` and `Depth.luau` (a test enforces they match).
- Paths written into generated files use `/` (`as_posix`), otherwise Windows regenerates different files and the up-to-date test fails.
- Found in Studio: a HUD element at (24,24) hid under the Roblox menu buttons. Reserved zones are absolute px (Roblox's UI doesn't use our scale).
