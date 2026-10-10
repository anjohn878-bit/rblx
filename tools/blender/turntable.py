"""Render a mesh from several angles into one contact sheet for visual review.

    python3 tools/blender/turntable.py out/chest.glb out/chest_views.png [--views 6]

Cycles on CPU at low samples: works headless with no GPU/EGL (Workbench and
Eevee need EGL, which many servers lack). Claude reads the sheet and decides whether the
asset passes (silhouette readable from every side, no holes, no floating bits).
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("out")
    ap.add_argument("--views", type=int, default=6)
    ap.add_argument("--res", type=int, default=384)
    a = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(a.input)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=os.path.abspath(a.input))
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=os.path.abspath(a.input))
    else:
        bpy.ops.wm.obj_import(filepath=os.path.abspath(a.input))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre, radius = (lo + hi) / 2, (hi - lo).length / 2

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = False
    scene.view_settings.view_transform = "Standard"  # RULE: AgX/Filmic washes colours out; review true colours
    scene.render.resolution_x = scene.render.resolution_y = a.res
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.37, 0.4, 1)
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(40), math.radians(20), math.radians(30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = radius * 2.3

    frames = []
    tmp = os.path.splitext(os.path.abspath(a.out))[0]
    for i in range(a.views):
        yaw = 2 * math.pi * i / a.views
        pitch = math.radians(20 if i % 2 == 0 else -10) if a.views > 4 else math.radians(20)
        d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
        cam.location = centre + d * radius * 4
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        path = f"{tmp}_{i}.png"
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        frames.append(path)

    from PIL import Image, ImageDraw

    cols = min(3, a.views)
    rows = math.ceil(a.views / cols)
    sheet = Image.new("RGB", (cols * a.res, rows * a.res), (40, 40, 40))
    for i, f in enumerate(frames):
        img = Image.open(f).convert("RGB")
        ImageDraw.Draw(img).text((6, 6), f"{round(360 * i / a.views)} deg", fill=(255, 255, 0))
        sheet.paste(img, ((i % cols) * a.res, (i // cols) * a.res))
        os.remove(f)
    sheet.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
