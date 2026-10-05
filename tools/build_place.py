#!/usr/bin/env python3
"""Build BecomeADeliveryDriver.rbxlx from the Luau sources.

Takes the blank base place (Place1.rbxlx), and inserts every script listed in
default.project.json using the same conventions as Rojo:

  init.server.luau -> the folder becomes a Script
  init.client.luau -> the folder becomes a LocalScript
  init.luau        -> the folder becomes a ModuleScript
  Name.server.luau -> Script, Name.client.luau -> LocalScript, Name.luau -> ModuleScript
  any other folder -> Folder

Usage: python3 tools/build_place.py [--base Place1.rbxlx] [--out BecomeADeliveryDriver.rbxlx]
"""

import argparse
import json
import re
import sys
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def referent() -> str:
    return "RBX" + uuid.uuid4().hex.upper()


def cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def script_kind(filename: str):
    """Return (class, name) for a Luau file, or None if it isn't one."""
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if filename.endswith(suffix):
            return cls, filename[: -len(suffix)]
    return None


def item_xml(cls: str, name: str, source, children, indent: int) -> str:
    pad = "\t" * indent
    lines = [f'{pad}<Item class="{cls}" referent="{referent()}">', f"{pad}\t<Properties>"]
    lines.append(f'{pad}\t\t<string name="Name">{escape(name)}</string>')
    if cls == "Script":
        lines.append(f'{pad}\t\t<token name="RunContext">0</token>')
    if source is not None:
        lines.append(f'{pad}\t\t<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
    lines.append(f"{pad}\t</Properties>")
    lines.extend(children)
    lines.append(f"{pad}</Item>")
    return "\n".join(lines)


def build_path(path: Path, name: str, indent: int, counts: dict) -> str:
    if path.is_file():
        kind = script_kind(path.name)
        if not kind:
            raise SystemExit(f"Not a Luau file: {path}")
        counts[kind[0]] = counts.get(kind[0], 0) + 1
        return item_xml(kind[0], name, path.read_text(encoding="utf-8"), [], indent)

    cls, source = "Folder", None
    for init_name, init_cls in (("init.server.luau", "Script"), ("init.client.luau", "LocalScript"), ("init.luau", "ModuleScript")):
        init = path / init_name
        if init.exists():
            cls, source = init_cls, init.read_text(encoding="utf-8")
            counts[cls] = counts.get(cls, 0) + 1
            break

    children = []
    for child in sorted(path.iterdir()):
        if child.name.startswith("init.") or child.name.startswith("."):
            continue
        if child.is_dir():
            children.append(build_path(child, child.name, indent + 1, counts))
        else:
            kind = script_kind(child.name)
            if kind:
                children.append(build_path(child, kind[1], indent + 1, counts))
    return item_xml(cls, name, source, children, indent)


def insert_into_service(place: str, service_chain, items) -> str:
    """Insert XML items as children of the last class in service_chain (e.g. StarterPlayer > StarterPlayerScripts)."""
    pos = 0
    for cls in service_chain:
        match = re.compile(rf'<Item class="{cls}" referent="[^"]+">').search(place, pos)
        if not match:
            raise SystemExit(f"Base place has no {cls}")
        pos = match.end()
    end_props = place.index("</Properties>", pos) + len("</Properties>")
    return place[:end_props] + "\n" + "\n".join(items) + place[end_props:]


def collect(tree: dict, chain, out: list):
    for key, node in tree.items():
        if key.startswith("$") or not isinstance(node, dict):
            continue
        if "$path" in node:
            out.append((tuple(chain), key, ROOT / node["$path"]))
        else:
            collect(node, chain + [key], out)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="Place1.rbxlx")
    parser.add_argument("--out", default="BecomeADeliveryDriver.rbxlx")
    parser.add_argument("--project", default="default.project.json")
    args = parser.parse_args()

    project = json.loads((ROOT / args.project).read_text(encoding="utf-8"))
    mounts = []
    collect(project["tree"], [], mounts)

    place = (ROOT / args.base).read_text(encoding="utf-8")
    counts: dict = {}
    for chain, name, path in mounts:
        if not path.exists():
            raise SystemExit(f"Missing source path {path}")
        depth = len(chain) + 1
        place = insert_into_service(place, chain, [build_path(path, name, depth, counts)])

    ET.fromstring(place)  # fail loudly if we produced broken XML
    (ROOT / args.out).write_text(place, encoding="utf-8")
    summary = ", ".join(f"{n} {cls}" for cls, n in sorted(counts.items()))
    print(f"Wrote {args.out} ({summary})")


if __name__ == "__main__":
    sys.exit(main())
