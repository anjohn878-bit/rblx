"""Measure a map the way a player experiences it, using the game's real movement numbers.

    python -m tools.map.mapcheck specs/maps/arena.json [--report out/maps/arena.md]

Map JSON (from tools/map/export_map.luau run in Studio, or written by hand/generator):
  {"parts": [{"name": "A", "size": [x,y,z], "pos": [x,y,z], "tags": ["spawn"]}, ...]}
pos is the part centre, Roblox axes (Y up). Tags:
  spawn         player start (at least one)
  noreach       players must NOT be able to stand here
  decor         not walkable, ignored for standing/reach (still collides for sight)
  floating_ok   allowed to float (intentional)
  overlap_ok    allowed to intersect others
  oneway_ok     allowed to be a drop with no way back
  kill          touching it kills/resets (lava, void floor)
  ring:<id>     member of a ring that must be evenly spaced
  poi           point of interest used for sight-line checks
Exit code 1 if any check fails.
"""
import argparse
import itertools
import json
import math
import pathlib
import re
import sys
from collections import deque

CONFIG = pathlib.Path("src/shared/Config/Movement.luau")
EPS = 0.05


# ------------------------------------------------------------ movement numbers


def load_movement(path=CONFIG):
    """Every number is labelled with where it came from."""
    nums = {}
    for i, line in enumerate(path.read_text().splitlines(), 1):
        m = re.match(r"\s*(\w+)\s*=\s*([-\d.]+)", line)
        if m:
            nums[m.group(1)] = (float(m.group(2)), f"{path}:{i}")
    need = ["WalkSpeed", "JumpHeight", "Gravity", "CharacterHeight", "CharacterRadius",
            "RagdollRecoverTime", "SafeFallHeight"]
    missing = [k for k in need if k not in nums]
    if missing:
        sys.exit(f"Movement config missing {missing}")
    return nums


ASSUMPTIONS = [
    "Parts are treated as axis-aligned boxes; yaw-rotated parts use their rotated bounding box (approximate).",
    "Jumps assume full WalkSpeed in the air and no run-up acceleration.",
    "Headroom above a jump arc is not checked (low ceilings can still block jumps).",
    "A jump must clear 0.2 studs below the full JumpHeight (safety margin for step-up feel).",
    "Sight lines are cast eye-height to eye-height between points of interest and only hit parts, not terrain.",
]


# ------------------------------------------------------------ geometry


class Part:
    def __init__(self, d):
        self.name = d["name"]
        sx, sy, sz = d["size"]
        yaw = math.radians(d.get("rot", [0, 0, 0])[1])
        if yaw:
            c, s = abs(math.cos(yaw)), abs(math.sin(yaw))
            sx, sz = sx * c + sz * s, sx * s + sz * c
        self.size = (sx, sy, sz)
        self.pos = tuple(d["pos"])
        self.tags = set(d.get("tags", []))
        self.rotated = bool(yaw)
        x, y, z = self.pos
        self.min = (x - sx / 2, y - sy / 2, z - sz / 2)
        self.max = (x + sx / 2, y + sy / 2, z + sz / 2)

    @property
    def top(self):
        return self.max[1]

    def has(self, prefix):
        return any(t == prefix or t.startswith(prefix + ":") for t in self.tags)


def xz_gap(a, b):
    dx = max(a.min[0] - b.max[0], b.min[0] - a.max[0], 0)
    dz = max(a.min[2] - b.max[2], b.min[2] - a.max[2], 0)
    return math.hypot(dx, dz)


def overlap_volume(a, b):
    v = 1
    for i in range(3):
        d = min(a.max[i], b.max[i]) - max(a.min[i], b.min[i])
        if d <= EPS:
            return 0
        v *= d
    return v


def segment_hits(p, q, part):
    """Slab test: does segment p->q pass through the part's box?"""
    t0, t1 = 0.0, 1.0
    for i in range(3):
        d = q[i] - p[i]
        if abs(d) < 1e-9:
            if p[i] < part.min[i] or p[i] > part.max[i]:
                return False
            continue
        a, b = (part.min[i] - p[i]) / d, (part.max[i] - p[i]) / d
        if a > b:
            a, b = b, a
        t0, t1 = max(t0, a), min(t1, b)
        if t0 > t1:
            return False
    return t1 > 0.001 and t0 < 0.999


# ------------------------------------------------------------ movement model


def jump_reach(dh, mv):
    """Max horizontal distance for a jump that lands dh studs higher (dh may be negative)."""
    g, J, v = mv["Gravity"][0], mv["JumpHeight"][0] - 0.2, mv["WalkSpeed"][0]
    if dh > J:
        return -1
    v0 = math.sqrt(2 * g * J)
    t = (v0 + math.sqrt(max(v0 * v0 - 2 * g * dh, 0))) / g
    return v * t


def can_move(a, b, mv):
    dh = b.top - a.top
    if dh > mv["JumpHeight"][0] - 0.2:
        return False
    return xz_gap(a, b) <= jump_reach(dh, mv) + EPS


def fall_time(h, mv):
    return math.sqrt(2 * max(h, 0) / mv["Gravity"][0])


# ------------------------------------------------------------ checks


def run(parts, mv):
    res = {k: [] for k in [
        "1 floating", "2 unstandable tops", "3 unreachable high ground", "4 reachable but shouldn't",
        "5 pockets (no way back)", "6 sight lines", "7 intersecting parts", "8 uneven rings",
        "9 falls vs ragdoll recovery"]}
    solid = [p for p in parts if not p.has("kill")]
    ground_y = min(p.min[1] for p in parts)
    need = 2 * mv["CharacterRadius"][0]

    # 1 floating: bottom face must rest on something (or be the lowest layer)
    for p in solid:
        if p.has("floating_ok") or abs(p.min[1] - ground_y) < EPS:
            continue
        supported = any(
            o is not p and abs(o.top - p.min[1]) < 0.1 and xz_gap(o, p) < EPS
            and min(o.max[0], p.max[0]) - max(o.min[0], p.min[0]) > EPS
            and min(o.max[2], p.max[2]) - max(o.min[2], p.min[2]) > EPS
            for o in parts
        ) or any(o is not p and overlap_volume(o, p) > 0 for o in parts)
        if not supported:
            res["1 floating"].append(f"{p.name} bottom at y={p.min[1]:.2f} rests on nothing")

    walk = [p for p in solid if not p.has("decor")]
    # 2 tops too small / covered
    standable = []
    for p in walk:
        sx, _, sz = p.size
        covered = any(
            o is not p and o.min[1] <= p.top + 0.05 < o.max[1]
            and o.min[0] <= p.min[0] and o.max[0] >= p.max[0] and o.min[2] <= p.min[2] and o.max[2] >= p.max[2]
            for o in parts
        )
        if covered:
            continue
        if min(sx, sz) < need:
            if not p.has("noreach"):
                res["2 unstandable tops"].append(f"{p.name} top is {sx:.1f}x{sz:.1f}, needs >= {need:.1f} each way")
            continue
        # a ceiling only counts if it hangs above the whole top (something resting ON it is not a ceiling)
        headroom = min(
            [o.min[1] - p.top for o in parts if o is not p and o.min[1] > p.top + EPS
             and o.min[0] <= p.min[0] + need and o.max[0] >= p.max[0] - need
             and o.min[2] <= p.min[2] + need and o.max[2] >= p.max[2] - need] or [math.inf]
        )
        if headroom < mv["CharacterHeight"][0]:
            res["2 unstandable tops"].append(f"{p.name} has only {headroom:.1f} studs headroom")
            continue
        standable.append(p)

    # 7 intersections
    for a, b in itertools.combinations(parts, 2):
        if a.has("overlap_ok") or b.has("overlap_ok"):
            continue
        v = overlap_volume(a, b)
        if v > 0.01:
            res["7 intersecting parts"].append(f"{a.name} and {b.name} overlap by {v:.2f} stud^3")
    # 8 rings
    rings = {}
    for p in parts:
        for t in p.tags:
            if t.startswith("ring:"):
                rings.setdefault(t, []).append(p)
    for tag, members in rings.items():
        if len(members) < 3:
            continue
        cx = sum(p.pos[0] for p in members) / len(members)
        cz = sum(p.pos[2] for p in members) / len(members)
        radii = [math.hypot(p.pos[0] - cx, p.pos[2] - cz) for p in members]
        angs = sorted(math.atan2(p.pos[2] - cz, p.pos[0] - cx) for p in members)
        steps = [(angs[(i + 1) % len(angs)] - angs[i]) % (2 * math.pi) for i in range(len(angs))]
        ideal = 2 * math.pi / len(members)
        worst = max(abs(s - ideal) for s in steps)
        if max(radii) - min(radii) > 0.25 or math.degrees(worst) > 1.0:
            res["8 uneven rings"].append(
                f"{tag}: radius spread {max(radii) - min(radii):.2f} studs, worst angle error {math.degrees(worst):.1f} deg")
    spawns = [p for p in standable if p.has("spawn")]
    if not spawns:
        res["3 unreachable high ground"].append("no standable part tagged 'spawn'")
        return res, set()
    idx = {p: i for i, p in enumerate(standable)}
    edges = {p: [q for q in standable if q is not p and can_move(p, q, mv)] for p in standable}

    def bfs(starts, graph):
        seen, dq = set(starts), deque(starts)
        while dq:
            u = dq.popleft()
            for w in graph[u]:
                if w not in seen:
                    seen.add(w)
                    dq.append(w)
        return seen

    reach = bfs(spawns, edges)
    # 3 / 4
    for p in standable:
        if p not in reach and not p.has("noreach"):
            res["3 unreachable high ground"].append(f"{p.name} (top y={p.top:.1f}) can't be reached from spawn")
        if p in reach and p.has("noreach"):
            res["4 reachable but shouldn't"].append(f"{p.name} is tagged noreach but players can get there")
    # 5 pockets: reachable, but can't get back to spawn
    rev = {p: [] for p in standable}
    for p, outs in edges.items():
        for q in outs:
            rev[q].append(p)
    back = bfs(spawns, rev)
    for p in reach:
        if p not in back and not p.has("oneway_ok"):
            res["5 pockets (no way back)"].append(f"{p.name}: you can fall in but never climb out")
    # 6 sight lines among points of interest
    eye = mv["CharacterHeight"][0] * 0.8
    pois = [p for p in standable if p.has("poi") or p.has("spawn")]
    pairs = list(itertools.combinations(pois, 2))
    if len(pairs) >= 3:
        open_ = 0
        for a, b in pairs:
            pa, pb = (a.pos[0], a.top + eye, a.pos[2]), (b.pos[0], b.top + eye, b.pos[2])
            blocked = any(segment_hits(pa, pb, o) for o in parts if o is not a and o is not b)
            open_ += not blocked
        frac = open_ / len(pairs)
        if frac > 0.85:
            res["6 sight lines"].append(f"too open: {frac:.0%} of {len(pairs)} POI pairs see each other (want 25-85%)")
        elif frac < 0.25:
            res["6 sight lines"].append(f"too closed: {frac:.0%} of {len(pairs)} POI pairs see each other (want 25-85%)")
    # 9 drops: shorter than ragdoll recovery = land still ragdolled; longer than safe = long fall
    rec = mv["RagdollRecoverTime"][0]
    for p in reach:
        for q in edges[p]:
            h = p.top - q.top
            if h <= 0.5:
                continue
            t = fall_time(h, mv)
            if h > mv["SafeFallHeight"][0]:
                res["9 falls vs ragdoll recovery"].append(f"{p.name} -> {q.name}: {h:.1f} stud fall ({t:.2f}s) is a long fall")
    for p in reach:
        for k in [o for o in parts if o.has("kill")]:
            if xz_gap(p, k) < 8 and k.top < p.top:
                t = fall_time(p.top - k.top, mv)
                if t < rec:
                    res["9 falls vs ragdoll recovery"].append(
                        f"{p.name} -> kill zone {k.name}: falls in {t:.2f}s, shorter than {rec}s ragdoll recovery")
    return res, reach


def report(path, parts, mv, res, reach):
    lines = [f"# Map check: {path}", "", "## Movement numbers used", ""]
    for k, (v, src) in sorted(mv.items()):
        lines.append(f"- {k} = {v}  _(from {src})_")
    lines += ["", "## Assumptions (guesses, not measurements)", ""] + [f"- {a}" for a in ASSUMPTIONS]
    rotated = [p.name for p in parts if p.rotated]
    if rotated:
        lines.append(f"- Rotated parts approximated by bounding box: {', '.join(rotated)}")
    lines += ["", f"Parts: {len(parts)}, reachable standing surfaces: {len(reach)}", "", "## Checks", ""]
    total = 0
    for k, items in res.items():
        total += len(items)
        lines.append(f"### {'PASS' if not items else 'FAIL'} {k}")
        lines += [f"- {i}" for i in items]
        lines.append("")
    return "\n".join(lines), total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("map")
    ap.add_argument("--report")
    ap.add_argument("--config", default=str(CONFIG))
    a = ap.parse_args()
    mv = load_movement(pathlib.Path(a.config))
    parts = [Part(d) for d in json.loads(pathlib.Path(a.map).read_text())["parts"]]
    res, reach = run(parts, mv)
    text, total = report(a.map, parts, mv, res, reach)
    if a.report:
        pathlib.Path(a.report).parent.mkdir(parents=True, exist_ok=True)
        pathlib.Path(a.report).write_text(text)
    for k, items in res.items():
        print(("PASS " if not items else "FAIL ") + k + "".join(f"\n   - {i}" for i in items))
    print(f"Map check: {total} problem(s)")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
