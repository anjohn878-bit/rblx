"""Build hard-edged props (crates, guns, doors) from a JSON spec - no AI mesh needed.

    python3 tools/blender/hardsurface.py specs/props/crate.json out/crate

Spec: {"name": "...", "bevel": 0.05, "parts": [
   {"shape": "box", "size": [x,y,z], "pos": [x,y,z], "rot": [deg,deg,deg], "color": "#hex"},
   {"shape": "cylinder", "radius": r, "depth": d, "pos": [...], "rot": [...], "color": "#hex", "sides": 16}]}
Units are studs, Y up (Roblox axes). Writes <out>.fbx, <out>.glb, <out>.report.json.
"""
import json
import math
import os
import sys

import bpy

ROBLOX_TRI_LIMIT = 20000


def hex_rgba(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)) + (1.0,)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    spec_path, out = argv[0], os.path.abspath(argv[1])
    spec = json.load(open(spec_path))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats, objs = {}, []
    for p in spec["parts"]:
        x, y, z = p.get("pos", [0, 0, 0])
        loc = (x, -z, y)  # Roblox Y-up -> Blender Z-up
        if p["shape"] == "box":
            bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
            sx, sy, sz = p["size"]
            bpy.context.object.scale = (sx, sz, sy)
        elif p["shape"] == "cylinder":
            bpy.ops.mesh.primitive_cylinder_add(
                vertices=p.get("sides", 16), radius=p["radius"], depth=p["depth"], location=loc
            )
        else:
            sys.exit(f"unknown shape {p['shape']}")
        o = bpy.context.object
        rx, ry, rz = (math.radians(v) for v in p.get("rot", [0, 0, 0]))
        o.rotation_euler = (rx, -rz, ry)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        col = p.get("color", "#a0a0a0")
        if col not in mats:
            m = bpy.data.materials.new(col)
            m.use_nodes = True
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = hex_rgba(col)
            m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
            mats[col] = m
        o.data.materials.append(mats[col])
        if spec.get("bevel", 0) > 0:
            b = o.modifiers.new("Bevel", "BEVEL")
            b.width = spec["bevel"]
            b.segments = 2
            b.limit_method = "ANGLE"
            bpy.ops.object.modifier_apply(modifier="Bevel")
        objs.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = spec.get("name", "Prop")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode="OBJECT")
    tris = len(obj.data.polygons)
    if tris > ROBLOX_TRI_LIMIT:
        sys.exit(f"FAIL: {tris} tris > {ROBLOX_TRI_LIMIT}")
    bpy.ops.export_scene.fbx(filepath=out + ".fbx", use_selection=True, axis_forward="-Z", axis_up="Y")
    bpy.ops.export_scene.gltf(filepath=out + ".glb", use_selection=True, export_format="GLB")
    report = {"name": obj.name, "tris": tris, "parts": len(spec["parts"]), "materials": len(mats)}
    json.dump(report, open(out + ".report.json", "w"), indent=2)
    print(json.dumps(report))


if __name__ == "__main__":
    main()
