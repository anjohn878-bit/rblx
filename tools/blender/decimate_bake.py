"""High-poly AI mesh -> Roblox-ready low-poly mesh with the lost detail baked back on.

    blender -b -P tools/blender/decimate_bake.py -- in.glb out/chest --tris 6000
    python3 tools/blender/decimate_bake.py in.glb out/chest --tris 6000   # with `pip install bpy`

Writes out/chest.fbx (upload), out/chest.glb (preview), out/chest_normal.png,
out/chest_color.png and out/chest.report.json. Fails if the result is over the
Roblox per-mesh triangle limit.

Colour: baked from the high-poly's own colours when it has any; otherwise
painted from --palette (a small spec: a list of hex colours bottom->top), never guessed.
"""
import argparse
import json
import math
import os
import sys

import bpy

ROBLOX_TRI_LIMIT = 20000


def parse():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("out_prefix")
    ap.add_argument("--tris", type=int, default=6000)
    ap.add_argument("--tex", type=int, default=1024)
    ap.add_argument("--size", type=float, default=4.0, help="longest side in studs after import")
    ap.add_argument("--palette", default="", help="comma hex colours bottom->top, e.g. '#6b4423,#c08a4d'")
    return ap.parse_args(argv)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_mesh(path):
    ext = os.path.splitext(path)[1].lower()
    before = set(bpy.data.objects)
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        sys.exit(f"unsupported input {ext}")
    meshes = [o for o in set(bpy.data.objects) - before if o.type == "MESH"]
    if not meshes:
        sys.exit("no mesh in input")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # RULE: glTF/OBJ importers split vertices per face on flat-shaded meshes. Without a
    # merge, decimate and UV unwrap see thousands of loose triangles (tiny islands, junk bake).
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=1e-5)
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def normalize(obj, size):
    dims = obj.dimensions
    longest = max(dims) or 1
    obj.scale = [size / longest] * 3
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.location = (0, 0, 0)


def make_low(high, target):
    low = high.copy()
    low.data = high.data.copy()
    low.name = "Low"
    bpy.context.collection.objects.link(low)
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode="OBJECT")
    start = tri_count(low)
    if start > target:
        mod = low.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = target / start
        bpy.ops.object.modifier_apply(modifier=mod.name)
    # strip inherited UVs/materials; fresh unwrap for the bake
    while low.data.uv_layers:
        low.data.uv_layers.remove(low.data.uv_layers[0])
    low.data.materials.clear()
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()
    return low, start


def has_colour(obj):
    if obj.data.color_attributes:
        return True
    for slot in obj.material_slots:
        m = slot.material
        if m and m.use_nodes and any(n.type == "TEX_IMAGE" for n in m.node_tree.nodes):
            return True
    return False


def paint_palette(high, palette):
    """Vertex-colour the high mesh by height from a tiny palette spec."""
    cols = [tuple(int(h.lstrip("#")[i : i + 2], 16) / 255 for i in (0, 2, 4)) for h in palette]
    mesh = high.data
    attr = mesh.color_attributes.new("PaletteCol", "FLOAT_COLOR", "POINT")
    zs = [v.co.z for v in mesh.vertices]
    lo, hi = min(zs), max(zs)
    for v in mesh.vertices:
        t = (v.co.z - lo) / ((hi - lo) or 1)
        idx = min(int(t * len(cols)), len(cols) - 1)
        attr.data[v.index].color = (*cols[idx], 1.0)
    mat = bpy.data.materials.new("Palette")
    mat.use_nodes = True
    nt = mat.node_tree
    ca = nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = "PaletteCol"
    nt.links.new(ca.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    high.data.materials.clear()
    high.data.materials.append(mat)


def ensure_vertex_colour_material(high):
    if high.data.materials:
        return
    mat = bpy.data.materials.new("HighCol")
    mat.use_nodes = True
    nt = mat.node_tree
    ca = nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = high.data.color_attributes[0].name
    nt.links.new(ca.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    high.data.materials.append(mat)


def bake(high, low, kind, path, res):
    img = bpy.data.images.new(os.path.basename(path), res, res, alpha=False, float_buffer=False)
    if kind == "NORMAL":
        img.colorspace_settings.name = "Non-Color"
    mat = low.data.materials[0] if low.data.materials else None
    if mat is None:
        mat = bpy.data.materials.new("LowMat")
        mat.use_nodes = True
        low.data.materials.append(mat)
    nt = mat.node_tree
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = img
    nt.nodes.active = node
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = max(low.dimensions) * 0.02
    scene.render.bake.margin = 8
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    if kind == "DIFFUSE":
        scene.render.bake.use_pass_direct = False
        scene.render.bake.use_pass_indirect = False
        scene.render.bake.use_pass_color = True
        bpy.ops.object.bake(type="DIFFUSE")
    else:
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img, node


def wire_material(low, color_img, normal_img):
    mat = low.data.materials[0]
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    for n in list(nt.nodes):
        if n.type == "TEX_IMAGE":
            nt.nodes.remove(n)
    if color_img:
        c = nt.nodes.new("ShaderNodeTexImage")
        c.image = color_img
        nt.links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = normal_img
    n.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])


def export(low, prefix):
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.export_scene.fbx(
        filepath=prefix + ".fbx", use_selection=True, path_mode="COPY", embed_textures=True,
        axis_forward="-Z", axis_up="Y",
    )
    bpy.ops.export_scene.gltf(filepath=prefix + ".glb", use_selection=True, export_format="GLB")


def main():
    a = parse()
    if a.tris > ROBLOX_TRI_LIMIT:
        sys.exit(f"--tris {a.tris} is over the Roblox limit {ROBLOX_TRI_LIMIT}")
    os.makedirs(os.path.dirname(os.path.abspath(a.out_prefix)), exist_ok=True)
    prefix = os.path.abspath(a.out_prefix)
    reset()
    high = import_mesh(os.path.abspath(a.input))
    normalize(high, a.size)
    high.name = "High"
    if not has_colour(high) and a.palette:
        paint_palette(high, a.palette.split(","))
    elif high.data.color_attributes:
        ensure_vertex_colour_material(high)
    low, high_tris = make_low(high, a.tris)
    color_img = None
    if has_colour(high):
        color_img, _ = bake(high, low, "DIFFUSE", prefix + "_color.png", a.tex)
    normal_img, _ = bake(high, low, "NORMAL", prefix + "_normal.png", a.tex)
    wire_material(low, color_img, normal_img)
    bpy.data.objects.remove(high, do_unlink=True)
    low_tris = tri_count(low)
    if low_tris > ROBLOX_TRI_LIMIT:
        sys.exit(f"FAIL: {low_tris} tris > {ROBLOX_TRI_LIMIT}")
    export(low, prefix)
    report = {
        "input": a.input, "high_tris": high_tris, "low_tris": low_tris,
        "ratio": round(high_tris / max(low_tris, 1), 1), "color_baked": color_img is not None,
        "size_studs": [round(d, 3) for d in low.dimensions], "roblox_limit": ROBLOX_TRI_LIMIT,
    }
    with open(prefix + ".report.json", "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report))


if __name__ == "__main__":
    main()
