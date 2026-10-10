---
name: roblox-3d-model
description: Create 3D models/props/characters/environment pieces for Roblox from a text idea - AI image (Flux on Cloudflare) -> image-to-3D (Hi3DGen on Kaggle GPU) -> Blender decimate + detail bake -> angle review -> Roblox Open Cloud upload. Also builds hard-edged props (crates, guns, doors) directly in Blender. Use whenever the game needs a mesh.
---

# Roblox 3D models

## Route choice
- **Hard-edged / geometric** (crates, guns, doors, fences, platforms) → `tools/blender/hardsurface.py specs/props/<x>.json out/<x>` (JSON of boxes/cylinders, studs, Y-up). Fast, exact, tiny triangle counts.
- **Organic / sculpted** (rocks, trees, creatures, statues, stylised props) → AI route below.

## AI route
1. **Reference image** (Cloudflare Workers AI, FLUX.1 schnell, free tier):
   `python -m tools.imagegen.flux "<object>, <style>" --preset model3d -o out/ref/<x>.png`
   Look at it. Single object, fully in frame, plain background, clear silhouette? If not, change the
   prompt (not just the seed) and retry. Keep the winning prompt (`.prompt.txt` is saved).
2. **Image → mesh** (Hi3DGen, MIT licence; Kaggle free GPU ~30 h/week, ~100 GPU-s per asset):
   `python -m tools.model3d.kaggle_hi3dgen out/ref/<x>.png -o out/high` → `out/high/<x>.glb` (~600k faces).
   Batch several images in one call — environment setup is the slow part.
3. **Decimate + bake** (Blender headless):
   `python3 tools/blender/decimate_bake.py out/high/<x>.glb out/low/<x> --tris 6000 --palette "#hex,#hex"`
   ~60:1 reduction to 6–10k tris; normal detail and colour baked onto a texture. Colour comes from the
   mesh if it has any, else from the small `--palette` spec (bottom→top) — never guessed.
4. **Angle review**: `python3 tools/blender/turntable.py out/low/<x>.glb out/low/<x>_views.png` and LOOK at
   every angle. Holes, melted areas, floating bits, unreadable silhouette → regenerate (new image or seed).
5. **Upload**: `python -m tools.roblox.opencloud_upload out/low/<x>.fbx --type Model --name "<x>"` → id in
   `assets.lock.json`. Textures upload as Decals (`--type Decal`) and are applied via SurfaceAppearance/MeshPart TextureID in Studio.

## Licences
Check every model's licence before using its output in a game. Hi3DGen (MIT) is fine. Tencent
Hunyuan3D's licence excludes the UK, EU and South Korea — don't use it if the user is in one of those.

## Learned rules
- Importers split verts per face on flat-shaded meshes → merge by distance before decimate (else tiny UV islands and junk bakes).
- Turntable renders with Cycles CPU (Workbench/Eevee need EGL; headless servers lack it) and the Standard view transform (AgX washes colours out).
- `decimate_bake.py` refuses anything over 20,000 tris.
- The Kaggle kernel is untested until the first real run: if it fails, read the log (`kaggle kernels output <user>/rblx-hi3dgen -p build/kaggle/log`), fix `tools/model3d/hi3dgen_kernel.py`, and write the fix here.
