"""Poses written as data -> contact sheet for review + Roblox KeyframeSequence (.rbxmx).

    python -m tools.anim.animate specs/anims/wave.json            # out/anims/wave_sheet.png + .rbxmx
    python -m tools.anim.animate specs/anims/wave.json --fps 10

Spec:
  {"name": "Wave", "rig": "R15", "length": 1.0, "loop": true, "priority": "Action",
   "keys": [{"t": 0.0, "ease": "Cubic", "pose": {"RightUpperArm": [0, 0, 160]}}, ...]}
Rotations are degrees [x, y, z] in each joint's own space (Motor6D Transform),
x = pitch forward/back, y = twist, z = roll sideways. Missing joints = rest.
The sheet shows front + side views of every frame so Claude can judge whether
the motion reads (anticipation, overshoot, no limb through the body, feet planted).
Import the .rbxmx in Studio (or via MCP), then publish with the Animation Editor
or Open Cloud to get an animation id for Config.
"""
import argparse
import json
import math
import pathlib

# Joint -> (parent, offset from parent joint in studs at rest, R15 proportions; Y up, -Z forward)
R15 = {
    "LowerTorso": (None, (0, 3.0, 0)),
    "UpperTorso": ("LowerTorso", (0, 0.4, 0)),
    "Head": ("UpperTorso", (0, 1.5, 0)),
    "LeftUpperArm": ("UpperTorso", (-1.0, 1.2, 0)),
    "LeftLowerArm": ("LeftUpperArm", (0, -0.8, 0)),
    "LeftHand": ("LeftLowerArm", (0, -0.8, 0)),
    "RightUpperArm": ("UpperTorso", (1.0, 1.2, 0)),
    "RightLowerArm": ("RightUpperArm", (0, -0.8, 0)),
    "RightHand": ("RightLowerArm", (0, -0.8, 0)),
    "LeftUpperLeg": ("LowerTorso", (-0.5, -0.2, 0)),
    "LeftLowerLeg": ("LeftUpperLeg", (0, -1.2, 0)),
    "LeftFoot": ("LeftLowerLeg", (0, -1.2, 0)),
    "RightUpperLeg": ("LowerTorso", (0.5, -0.2, 0)),
    "RightLowerLeg": ("RightUpperLeg", (0, -1.2, 0)),
    "RightFoot": ("RightLowerLeg", (0, -1.2, 0)),
}
BONE_END = {  # where to draw each segment to (child joint), leaf segments get a stub
    "Head": (0, 1.0, 0), "LeftHand": (0, -0.3, 0), "RightHand": (0, -0.3, 0),
    "LeftFoot": (0, -0.3, -0.4), "RightFoot": (0, -0.3, -0.4),
}
# Reasonable joint limits (deg) - poses outside them are flagged as broken-looking.
LIMITS = {
    "LowerLeg": {"x": (-150, 5)},  # knees only bend backwards (-x swings the shin back)
    "LowerArm": {"x": (-5, 150)},  # elbows only bend forwards (+x swings the forearm forward)
    "Head": {"x": (-60, 60), "y": (-80, 80), "z": (-45, 45)},
}


# ------------------------------------------------------------ maths


def rot_matrix(deg):
    x, y, z = (math.radians(v) for v in deg)
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    return mat_mul(mat_mul(rx, ry), rz)  # Roblox CFrame.Angles order: X, then Y, then Z


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(m, v):
    return tuple(sum(m[i][k] * v[k] for k in range(3)) for i in range(3))


def ease(kind, t):
    if kind == "Constant":
        return 0.0
    if kind == "Cubic":
        return 4 * t**3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2
    if kind == "Elastic":
        return 1 if t == 1 else 1 - 2 ** (-10 * t) * math.cos(t * 10 * math.pi / 3) if t > 0 else 0
    if kind == "Bounce":
        n, d = 7.5625, 2.75
        if t < 1 / d:
            return n * t * t
        if t < 2 / d:
            t -= 1.5 / d
            return n * t * t + 0.75
        if t < 2.5 / d:
            t -= 2.25 / d
            return n * t * t + 0.9375
        t -= 2.625 / d
        return n * t * t + 0.984375
    return t  # Linear


def sample(spec, t):
    keys = sorted(spec["keys"], key=lambda k: k["t"])
    if t <= keys[0]["t"]:
        return dict(keys[0]["pose"])
    for a, b in zip(keys, keys[1:]):
        if a["t"] <= t <= b["t"]:
            u = ease(a.get("ease", "Linear"), (t - a["t"]) / ((b["t"] - a["t"]) or 1))
            out = {}
            for j in set(a["pose"]) | set(b["pose"]):
                va, vb = a["pose"].get(j, [0, 0, 0]), b["pose"].get(j, [0, 0, 0])
                out[j] = [x + (y - x) * u for x, y in zip(va, vb)]
            return out
    return dict(keys[-1]["pose"])


def forward_kinematics(pose):
    world = {}  # joint -> (position, rotation)
    for joint, (parent, offset) in R15.items():
        local = rot_matrix(pose.get(joint, [0, 0, 0]))
        if parent is None:
            world[joint] = (offset, local)
        else:
            ppos, prot = world[parent]
            pos = tuple(p + o for p, o in zip(ppos, mat_vec(prot, offset)))
            world[joint] = (pos, mat_mul(prot, local))
    return world


def segments(world):
    """Limb bones joint->child, plus a torso outline (shoulder line, hip line, spine)."""
    segs = []
    for joint, (parent, _) in R15.items():
        if parent and not (parent in ("UpperTorso", "LowerTorso") and joint != "UpperTorso"):
            segs.append((joint, world[parent][0], world[joint][0]))
        if joint in BONE_END:
            pos, rot = world[joint]
            end = tuple(p + o for p, o in zip(pos, mat_vec(rot, BONE_END[joint])))
            segs.append((joint, pos, end))
    w = {k: v[0] for k, v in world.items()}
    mid = lambda a, b: tuple((x + y) / 2 for x, y in zip(a, b))  # noqa: E731
    shoulders, hips = mid(w["LeftUpperArm"], w["RightUpperArm"]), mid(w["LeftUpperLeg"], w["RightUpperLeg"])
    segs += [("Torso", w["LeftUpperArm"], w["RightUpperArm"]), ("Torso", w["LeftUpperLeg"], w["RightUpperLeg"]),
             ("Torso", shoulders, hips), ("Torso", shoulders, w["Head"])]
    return segs


def lint(spec):
    problems = []
    for k in spec["keys"]:
        for joint, rot in k["pose"].items():
            if joint not in R15:
                problems.append(f"t={k['t']}: unknown joint {joint}")
                continue
            for suffix, lim in LIMITS.items():
                if joint.endswith(suffix):
                    for axis, (lo, hi) in lim.items():
                        v = rot["xyz".index(axis)]
                        if not lo <= v <= hi:
                            problems.append(f"t={k['t']}: {joint} {axis}={v} outside natural range {lo}..{hi}")
    if spec.get("loop"):
        first, last = sorted(spec["keys"], key=lambda k: k["t"])[0], sorted(spec["keys"], key=lambda k: k["t"])[-1]
        if first["pose"] != last["pose"]:
            problems.append("loop=true but first and last poses differ (visible pop at the loop seam)")
    for fr in (0, spec["length"] / 2, spec["length"]):
        w = forward_kinematics(sample(spec, fr))
        lowest = min(p[1] for p, _ in w.values())
        if lowest < -0.6:
            problems.append(f"t={fr:.2f}: a limb goes {-lowest:.1f} studs below the floor")
    return problems


# ------------------------------------------------------------ contact sheet


def contact_sheet(spec, fps, out_path):
    from PIL import Image, ImageDraw

    n = max(2, int(spec["length"] * fps) + 1)
    cell, cols = 220, 6
    rows = math.ceil(n / cols)
    sheet = Image.new("RGB", (cols * cell, rows * cell), (34, 36, 44))
    colours = {"Left": (90, 170, 255), "Right": (255, 120, 90)}
    for i in range(n):
        t = spec["length"] * i / (n - 1)
        world = forward_kinematics(sample(spec, t))
        ox, oy = (i % cols) * cell, (i // cols) * cell
        d = ImageDraw.Draw(sheet)
        d.rectangle([ox, oy, ox + cell - 1, oy + cell - 1], outline=(70, 72, 84))
        for view, cx in (("front", ox + cell * 0.28), ("side", ox + cell * 0.72)):
            scale = 26
            base = oy + cell - 22
            d.line([cx - 40, base, cx + 40, base], fill=(90, 90, 100))
            for joint, a, b in segments(world):
                col = next((c for k, c in colours.items() if joint.startswith(k)), (235, 235, 235))
                if view == "front":
                    pa, pb = (cx + a[0] * scale, base - a[1] * scale), (cx + b[0] * scale, base - b[1] * scale)
                else:
                    pa, pb = (cx - a[2] * scale, base - a[1] * scale), (cx - b[2] * scale, base - b[1] * scale)
                d.line([pa, pb], fill=col, width=4)
            hp = world["Head"][0]
            hx = cx + (hp[0] if view == "front" else -hp[2]) * scale
            d.ellipse([hx - 12, base - (hp[1] + 0.6) * scale - 12, hx + 12, base - (hp[1] + 0.6) * scale + 12],
                      outline=(235, 235, 235), width=3)
        d.text((ox + 6, oy + 4), f"{t:.2f}s  front | side", fill=(255, 220, 90))
    sheet.save(out_path)


# ------------------------------------------------------------ KeyframeSequence


def cframe_xml(deg):
    m = rot_matrix(deg)
    vals = "".join(f"<R{i}{j}>{m[i][j]:.6f}</R{i}{j}>" for i in range(3) for j in range(3))
    return f'<CoordinateFrame name="CFrame"><X>0</X><Y>0</Y><Z>0</Z>{vals}</CoordinateFrame>'


def pose_xml(joint, pose, ease_style, depth=0):
    kids = "".join(pose_xml(j, pose, ease_style, depth + 1) for j, (p, _) in R15.items() if p == joint)
    style = {"Linear": "Linear", "Cubic": "Cubic", "Elastic": "Elastic", "Bounce": "Bounce", "Constant": "Constant"}
    return (
        f'<Item class="Pose"><Properties><string name="Name">{joint}</string>'
        f"{cframe_xml(pose.get(joint, [0, 0, 0]))}"
        f'<float name="Weight">1</float>'
        f'<token name="EasingStyle">{list(style).index(style.get(ease_style, "Linear"))}</token>'
        f'<token name="EasingDirection">0</token>'
        f"</Properties>{kids}</Item>"
    )


def keyframe_sequence(spec):
    priority = {"Idle": 0, "Movement": 1, "Action": 2, "Core": 1000}.get(spec.get("priority", "Action"), 2)
    frames = ""
    for k in sorted(spec["keys"], key=lambda k: k["t"]):
        root = pose_xml("LowerTorso", k["pose"], k.get("ease", "Linear"))
        frames += (
            f'<Item class="Keyframe"><Properties><string name="Name">Keyframe</string>'
            f'<float name="Time">{k["t"]}</float></Properties>'
            f'<Item class="Pose"><Properties><string name="Name">HumanoidRootPart</string>'
            f"{cframe_xml([0, 0, 0])}<float name=\"Weight\">0</float></Properties>{root}</Item></Item>"
        )
    return (
        '<roblox version="4"><Item class="KeyframeSequence"><Properties>'
        f'<string name="Name">{spec["name"]}</string>'
        f'<bool name="Loop">{"true" if spec.get("loop") else "false"}</bool>'
        f'<token name="Priority">{priority}</token>'
        f"</Properties>{frames}</Item></roblox>"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--fps", type=int, default=12)
    ap.add_argument("--out", default="out/anims")
    a = ap.parse_args()
    spec = json.loads(pathlib.Path(a.spec).read_text())
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    stem = spec["name"].lower()
    contact_sheet(spec, a.fps, out / f"{stem}_sheet.png")
    (out / f"{stem}.rbxmx").write_text(keyframe_sequence(spec))
    problems = lint(spec)
    for p in problems:
        print("WARN", p)
    print(out / f"{stem}_sheet.png")
    print(out / f"{stem}.rbxmx")


if __name__ == "__main__":
    main()
