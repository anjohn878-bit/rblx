"""One UI spec -> preview images, the game's UI module, and a layout checker.

    python -m tools.ui.uikit preview specs/ui/hud.json      # out/ui/<screen>_<size>.png
    python -m tools.ui.uikit build   specs/ui/hud.json      # src/client/UI/Generated/<Screen>.luau
    python -m tools.ui.uikit check   specs/ui/hud.json      # exit 1 on any violation
    python -m tools.ui.uikit all     specs/ui/hud.json

Layout maths (UDim2 + AnchorPoint + one global scale) is implemented once here
and mirrored exactly in the generated Luau, so preview and game cannot disagree.
"""
import argparse
import json
import pathlib
import subprocess
import sys

# Real screen sizes the checker runs at (landscape, in Roblox UI pixels).
SCREENS = {
    "phone_small": (667, 375),
    "phone": (844, 390),
    "tablet": (1024, 768),
    "desktop_hd": (1920, 1080),
}
# Global scale: offsets are authored at 1080p-tall and scaled by height, clamped.
REF_HEIGHT, MIN_SCALE, MAX_SCALE = 1080, 0.55, 1.25
MIN_TAP = 40  # px; Roblox's own touch controls are ~40-70
MIN_TEXT = 11  # px after scaling
CENTER_TOL = 1.5  # px

DEFAULT_THEME = {
    "font": "GothamBold",
    "text": "#ffffff",
    "textStroke": "#1b1f3a",
    "stroke": 3,  # ONE outline thickness everywhere (px at 1080p)
    "strokeColor": "#1b1f3a",
    "corner": 14,
    "shadowOffset": 6,
    "shadowTint": "#1b2350",  # shadows are shifted toward blue, never pure black
    "lift": 0.18,  # gradient: top this much lighter than base
    "panel": "#2f3a6b",
    "primary": "#3fb6ff",
    "accent": "#ffc23f",
    "danger": "#ff5a5a",
    "success": "#58d26b",
}


def ui_scale(h):
    return max(MIN_SCALE, min(MAX_SCALE, h / REF_HEIGHT))


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


# ---------------------------------------------------------------- layout


class Node:
    def __init__(self, d, theme, parent=None):
        self.d, self.parent, self.theme = d, parent, theme
        self.type = d.get("type", "Panel")
        self.name = d["name"]
        self.children = [Node(c, theme, self) for c in d.get("children", [])]
        self.rect = None  # (x, y, w, h) absolute

    @property
    def path(self):
        return (self.parent.path + "." if self.parent else "") + self.name

    def color(self):
        c = self.d.get("color", "panel" if self.type == "Panel" else "primary")
        return self.theme.get(c, c)

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


def layout(node, prect, s):
    px, py, pw, ph = prect
    sx, ox, sy, oy = node.d.get("size", [1, 0, 1, 0])
    w, h = sx * pw + ox * s, sy * ph + oy * s
    if "aspect" in node.d:  # UIAspectRatioConstraint, dominant axis = width
        h = w / node.d["aspect"]
    psx, pox, psy, poy = node.d.get("pos", [0, 0, 0, 0])
    ax, ay = node.d.get("anchor", [0, 0])
    node.rect = (px + psx * pw + pox * s - ax * w, py + psy * ph + poy * s - ay * h, w, h)
    layout_children(node, s)


def layout_children(node, s):
    x, y, w, h = node.rect
    pad = node.d.get("padding", 0) * s
    inner = (x + pad, y + pad, w - 2 * pad, h - 2 * pad)
    for c in node.children:
        layout(c, inner, s)
    lst = node.d.get("list")  # {"dir": "x"|"y", "gap": px, "align": "center"|"start"} = UIListLayout
    if not lst:
        return
    horizontal = lst["dir"] == "x"
    gap = lst.get("gap", 0) * s
    sizes = [c.rect[2] if horizontal else c.rect[3] for c in node.children]
    total = sum(sizes) + gap * max(len(sizes) - 1, 0)
    main_len = inner[2] if horizontal else inner[3]
    cursor = (main_len - total) / 2 if lst.get("align", "center") == "center" else 0
    for c, size in zip(node.children, sizes):
        _, _, cw, ch = c.rect
        if horizontal:
            c.rect = (inner[0] + cursor, inner[1] + (inner[3] - ch) / 2, cw, ch)
        else:
            c.rect = (inner[0] + (inner[2] - cw) / 2, inner[1] + cursor, cw, ch)
        layout_children(c, s)  # the list moved c; its subtree follows
        cursor += size + gap


def layout_screen(spec_screen, theme, size):
    w, h = size
    s = ui_scale(h)
    root = Node({"name": spec_screen["name"], "type": "Screen", "children": spec_screen["children"]}, theme)
    root.rect = (0, 0, w, h)
    layout_children(root, s)
    return root, s


# ---------------------------------------------------------------- checks


def overlaps(a, b, eps=0.5):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return ax + aw - eps > bx and bx + bw - eps > ax and ay + ah - eps > by and by + bh - eps > ay


def check_screen(screen, theme, size_name, size):
    root, s = layout_screen(screen, theme, size)
    W, H = size
    out = []

    def bad(node, msg):
        out.append(f"[{size_name} {W}x{H}] {node.path}: {msg}")

    for n in root.walk():
        if n is root:
            continue
        x, y, w, h = n.rect
        if n.d.get("offscreen_ok") is not True and (x < -0.5 or y < -0.5 or x + w > W + 0.5 or y + h > H + 0.5):
            bad(n, f"off screen ({x:.0f},{y:.0f},{w:.0f}x{h:.0f})")
        if n.type == "Button" and (w < MIN_TAP or h < MIN_TAP):
            bad(n, f"tap target {w:.0f}x{h:.0f} < {MIN_TAP}px")
        if "text" in n.d:
            ts = n.d.get("textSize", 28) * s
            if ts < MIN_TEXT:
                bad(n, f"text {ts:.1f}px < {MIN_TEXT}px")
            if ts > h + 0.5:
                bad(n, f"text {ts:.0f}px taller than its box {h:.0f}px")
        if n.d.get("centered") and n.parent is not None:
            px, py, pw, ph = n.parent.rect
            dx = abs((x + w / 2) - (px + pw / 2))
            dy = abs((y + h / 2) - (py + ph / 2))
            axes = n.d["centered"] if isinstance(n.d["centered"], str) else "xy"
            if ("x" in axes and dx > CENTER_TOL) or ("y" in axes and dy > CENTER_TOL):
                bad(n, f"not centred (dx={dx:.2f}, dy={dy:.2f})")
        # siblings must not touch (layer: siblings sharing a non-zero "layer" may stack)
        sibs = n.parent.children if n.parent else []
        for o in sibs:
            if o is n or id(o) < id(n):
                continue
            if n.d.get("layer") and n.d.get("layer") == o.d.get("layer"):
                continue
            if n.d.get("allowOverlap") or o.d.get("allowOverlap"):
                continue
            if overlaps(n.rect, o.rect):
                bad(n, f"touches sibling {o.name}")
        # children must sit inside their parent
        if n.parent is not root and n.parent is not None and not n.d.get("offscreen_ok"):
            px, py, pw, ph = n.parent.rect
            if x < px - 0.5 or y < py - 0.5 or x + w > px + pw + 0.5 or y + h > py + ph + 0.5:
                bad(n, "spills outside its parent")
        # RULE: no decorative frame drawn around a lone button (AI habit)
        if n.type == "Panel" and len(n.children) == 1 and n.children[0].type == "Button":
            cx, cy, cw, ch = n.children[0].rect
            if cw * ch > 0.5 * w * h:
                bad(n, "panel exists only to box a button - remove it")
    return out


# ---------------------------------------------------------------- preview


def _font(px):
    from PIL import ImageFont

    for f in ("DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "arialbd.ttf"):
        try:
            return ImageFont.truetype(f, max(int(px), 6))
        except OSError:
            continue
    return ImageFont.load_default()


def render(screen, theme, size, out_path, icon_dir):
    from PIL import Image, ImageDraw

    root, s = layout_screen(screen, theme, size)
    W, H = size
    img = Image.new("RGBA", (W, H), (110, 150, 120, 255))
    # fake 3D scene behind so contrast is judged realistically
    g = ImageDraw.Draw(img)
    for i in range(H):
        g.line([(0, i), (W, i)], fill=mix((120, 180, 230), (90, 140, 90), i / H) + (255,))
    stroke = max(1, round(theme["stroke"] * s))
    corner = round(theme["corner"] * s)
    so = max(1, round(theme["shadowOffset"] * s))
    for n in root.walk():
        if n is root or n.type == "Group":
            continue
        x, y, w, h = (round(v) for v in n.rect)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        if n.type in ("Panel", "Button"):
            base = hex_rgb(n.color())
            shadow = mix(base, hex_rgb(theme["shadowTint"]), 0.75)
            d.rounded_rectangle([x, y + so, x + w, y + h + so], corner, fill=shadow + (255,))
            # gradient face (lift from the top)
            top = mix(base, (255, 255, 255), theme["lift"])
            face = Image.new("RGBA", (max(w, 1), max(h, 1)))
            fd = ImageDraw.Draw(face)
            for i in range(max(h, 1)):
                fd.line([(0, i), (w, i)], fill=mix(top, base, i / max(h - 1, 1)) + (255,))
            mask = Image.new("L", (max(w, 1), max(h, 1)), 0)
            ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], corner, fill=255)
            layer.paste(face, (x, y), mask)
            d.rounded_rectangle([x, y, x + w, y + h], corner, outline=hex_rgb(theme["strokeColor"]) + (255,), width=stroke)
        if n.type == "Icon":
            p = pathlib.Path(icon_dir) / f"{n.d['icon']}.png"
            if p.exists():
                ic = Image.open(p).convert("RGBA").resize((max(w, 1), max(h, 1)))
                layer.alpha_composite(ic, (x, y))
            else:
                d.ellipse([x, y, x + w, y + h], fill=hex_rgb(theme["accent"]) + (255,),
                          outline=hex_rgb(theme["strokeColor"]) + (255,), width=stroke)
                d.text((x + w / 2, y + h / 2), n.d["icon"][:2].upper(), anchor="mm",
                       font=_font(h * 0.4), fill=(30, 30, 30, 255))
        if "text" in n.d:
            f = _font(n.d.get("textSize", 28) * s)
            align = n.d.get("textAlign", "center")
            ax = {"left": x + 6 * s, "center": x + w / 2, "right": x + w - 6 * s}[align]
            anchor = {"left": "lm", "center": "mm", "right": "rm"}[align]
            d.text((ax, y + h / 2), n.d["text"], font=f, anchor=anchor, fill=hex_rgb(theme["text"]) + (255,),
                   stroke_width=max(1, round(2 * s)), stroke_fill=hex_rgb(theme["textStroke"]) + (255,))
        img.alpha_composite(layer)
    img.convert("RGB").save(out_path)


# ---------------------------------------------------------------- Luau codegen


def lua_str(v):
    return json.dumps(v)


def color3(h):
    r, g, b = hex_rgb(h)
    return f"Color3.fromRGB({r}, {g}, {b})"


def udim2(v):
    return f"UDim2.new({v[0]}, {v[1]} * S, {v[2]}, {v[3]} * S)"


def emit_node(n, parent_var, lines, theme, idx):
    v = f"n{idx[0]}"
    idx[0] += 1
    cls = {"Panel": "Frame", "Group": "Frame", "Button": "TextButton", "Label": "TextLabel", "Icon": "ImageLabel"}[n.type]
    d = n.d
    align = "Enum.TextXAlignment." + {"left": "Left", "center": "Center", "right": "Right"}[d.get("textAlign", "center")]
    lines.append(f'\tlocal {v} = Instance.new("{cls}")')
    lines.append(f"\t{v}.Name = {lua_str(n.name)}")
    lines.append(f"\t{v}.Size = {udim2(d.get('size', [1, 0, 1, 0]))}")
    lines.append(f"\t{v}.Position = {udim2(d.get('pos', [0, 0, 0, 0]))}")
    ax, ay = d.get("anchor", [0, 0])
    lines.append(f"\t{v}.AnchorPoint = Vector2.new({ax}, {ay})")
    lines.append(f"\t{v}.BorderSizePixel = 0")
    lines.append(f"\t{v}.BackgroundTransparency = 1")
    if "aspect" in d:
        lines.append(f'\tdepth.aspect({v}, {d["aspect"]})')
    content = v
    if n.type in ("Panel", "Button"):
        if n.children or d.get("padding") or d.get("list"):
            content = f"{v}c"
            lines.append(f"\tlocal {content} = depth.apply({v}, {color3(n.color())}, S)")
        else:
            lines.append(f"\tdepth.apply({v}, {color3(n.color())}, S)")
        if cls == "TextButton":
            lines.append(f'\t{v}.Text = ""')
            lines.append(f"\t{v}.AutoButtonColor = false")
        if "text" in d:
            lines.append(f"\tdepth.text({v}, {lua_str(d['text'])}, {d.get('textSize', 28)}, {align}, S)")
    elif cls == "TextLabel":
        lines.append(f"\t{v}.Text = {lua_str(d.get('text', ''))}")
        lines.append(f"\t{v}.TextSize = math.floor({d.get('textSize', 28)} * S + 0.5)")
        lines.append(f"\t{v}.TextXAlignment = {align}")
        lines.append(f"\tdepth.styleText({v}, S)")
    elif cls == "ImageLabel":
        lines.append(f"\t{v}.Image = Icons[{lua_str(d['icon'])}] or \"\"")
        lines.append(f"\t{v}.ScaleType = Enum.ScaleType.Fit")
    if d.get("padding"):
        lines.append(f'\tdepth.pad({content}, {d["padding"]} * S)')
    if d.get("list"):
        lst = d["list"]
        lines.append(
            f'\tdepth.list({content}, {lua_str(lst["dir"])}, {lst.get("gap", 0)} * S, {lua_str(lst.get("align", "center"))})'
        )
    lines.append(f"\t{v}.Parent = {parent_var}")
    lines.append(f"\trefs[{lua_str(n.path)}] = {v}")
    for c in n.children:
        emit_node(c, content, lines, theme, idx)


def build_luau(spec, screen, theme):
    root = Node({"name": screen["name"], "type": "Screen", "children": screen["children"]}, theme)
    lines = [
        "--!strict",
        f"-- GENERATED by tools/ui/uikit.py from {spec['_path']} - do not edit; edit the spec and rebuild.",
        "local Depth = require(script.Parent.Parent.Depth)",
        "local Icons = require(script.Parent.Parent.Icons)",
        "",
        "local THEME = {",
        f"\tstroke = {theme['stroke']},",
        f"\tstrokeColor = {color3(theme['strokeColor'])},",
        f"\tcorner = {theme['corner']},",
        f"\tshadowOffset = {theme['shadowOffset']},",
        f"\tshadowTint = {color3(theme['shadowTint'])},",
        f"\tlift = {theme['lift']},",
        f"\ttext = {color3(theme['text'])},",
        f"\ttextStroke = {color3(theme['textStroke'])},",
        f"\tfont = Enum.Font.{theme['font']},",
        "}",
        "",
        "return function(parent: Instance, viewportHeight: number): (ScreenGui, { [string]: GuiObject })",
        "\tlocal S = Depth.scale(viewportHeight)",
        "\tlocal depth = Depth.with(THEME)",
        "\tlocal refs: { [string]: any } = {}",
        '\tlocal gui = Instance.new("ScreenGui")',
        f"\tgui.Name = {lua_str(screen['name'])}",
        "\tgui.ResetOnSpawn = false",
        "\tgui.IgnoreGuiInset = true",
        "\tgui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling",
    ]
    idx = [0]
    for c in root.children:
        emit_node(c, "gui", lines, theme, idx)
    lines += ["\tgui.Parent = parent", "\treturn gui, refs", "end", ""]
    return "\n".join(lines)


# ---------------------------------------------------------------- CLI


def spec_label(path):
    # RULE: "/" on every OS, or Windows regenerates different files and the up-to-date test fails
    return str(path).replace("\\", "/")


def load(path):
    spec = json.loads(pathlib.Path(path).read_text())
    spec["_path"] = spec_label(path)
    theme = {**DEFAULT_THEME, **spec.get("theme", {})}
    return spec, theme


def cmd_check(spec, theme):
    problems = []
    for screen in spec["screens"]:
        for name, size in SCREENS.items():
            problems += check_screen(screen, theme, name, size)
    for p in problems:
        print("FAIL", p)
    print(f"UI check: {len(problems)} problem(s) across {len(spec['screens'])} screen(s) x {len(SCREENS)} sizes")
    return not problems


def cmd_preview(spec, theme, out_dir, icon_dir):
    out = pathlib.Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for screen in spec["screens"]:
        for name, size in SCREENS.items():
            p = out / f"{screen['name']}_{name}.png"
            render(screen, theme, size, p, icon_dir)
            print(p)


def cmd_build(spec, theme, gen_dir):
    gen = pathlib.Path(gen_dir)
    gen.mkdir(parents=True, exist_ok=True)
    for screen in spec["screens"]:
        p = gen / f"{screen['name']}.luau"
        p.write_text(build_luau(spec, screen, theme), newline="\n")
        subprocess.run(["stylua", str(p)], check=False)
        print(p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["preview", "build", "check", "all"])
    ap.add_argument("spec")
    ap.add_argument("--out", default="out/ui")
    ap.add_argument("--gen", default="src/client/UI/Generated")
    ap.add_argument("--icons", default="assets/icons")
    a = ap.parse_args()
    spec, theme = load(a.spec)
    ok = True
    if a.cmd in ("check", "all"):
        ok = cmd_check(spec, theme)
    if a.cmd in ("preview", "all"):
        cmd_preview(spec, theme, a.out, a.icons)
    if a.cmd in ("build", "all"):
        cmd_build(spec, theme, a.gen)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
