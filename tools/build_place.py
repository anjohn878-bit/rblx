#!/usr/bin/env python3
"""Injects the scripts in src/ into Place1.rbxlx so the place opens ready to play in Studio.

Re-running is safe: previously injected items (referents starting with RBXMR) are removed first.

    python3 tools/build_place.py
"""

import pathlib
import re
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLACE = ROOT / "Place1.rbxlx"
SRC = ROOT / "src"
PREFIX = "RBXMR"


def ref() -> str:
    return PREFIX + uuid.uuid4().hex.upper()


def script_item(cls: str, name: str, path: pathlib.Path, indent: str) -> str:
    source = path.read_text(encoding="utf-8")
    if "]]>" in source:
        raise SystemExit(f"{path} contains ']]>' which can't go in CDATA")
    return (
        f'{indent}<Item class="{cls}" referent="{ref()}">\n'
        f"{indent}\t<Properties>\n"
        f'{indent}\t\t<string name="Name">{name}</string>\n'
        f'{indent}\t\t<ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>\n'
        f"{indent}\t</Properties>\n"
        f"{indent}</Item>\n"
    )


def folder_item(name: str, children: str, indent: str) -> str:
    return (
        f'{indent}<Item class="Folder" referent="{ref()}">\n'
        f"{indent}\t<Properties>\n"
        f'{indent}\t\t<string name="Name">{name}</string>\n'
        f"{indent}\t</Properties>\n"
        f"{children}"
        f"{indent}</Item>\n"
    )


def strip_injected(lines: list[str]) -> list[str]:
    out, depth = [], 0
    for line in lines:
        if depth == 0 and "<Item " in line and f'referent="{PREFIX}' in line:
            depth = 1
            continue
        if depth > 0:
            # Script sources live in CDATA on a single logical item, so only count tags
            # that start a line (sources never contain indented <Item> tags).
            stripped = line.lstrip()
            if stripped.startswith("<Item "):
                depth += 1
            elif stripped.startswith("</Item>"):
                depth -= 1
            continue
        out.append(line)
    return out


def find_close(lines: list[str], cls: str) -> tuple[int, str]:
    """Returns the index of the </Item> closing the first item of class `cls`, and its indent."""
    start = next(i for i, l in enumerate(lines) if f'<Item class="{cls}"' in l)
    indent = re.match(r"\s*", lines[start]).group(0)
    depth = 0
    for i in range(start, len(lines)):
        stripped = lines[i].lstrip()
        if stripped.startswith("<Item "):
            depth += 1
        elif stripped.startswith("</Item>"):
            depth -= 1
            if depth == 0:
                return i, indent
    raise SystemExit(f"Could not find end of {cls}")


def insert(lines: list[str], cls: str, make) -> list[str]:
    idx, indent = find_close(lines, cls)
    block = make(indent + "\t")
    return lines[:idx] + block.splitlines(keepends=True) + lines[idx:]


def main() -> None:
    text = PLACE.read_text(encoding="utf-8")
    lines = strip_injected(text.splitlines(keepends=True))

    shared = SRC / "ReplicatedStorage" / "MarbleRun"
    lines = insert(
        lines,
        "ReplicatedStorage",
        lambda ind: folder_item(
            "MarbleRun",
            script_item("ModuleScript", "Config", shared / "Config.luau", ind + "\t")
            + script_item("ModuleScript", "Pieces", shared / "Pieces.luau", ind + "\t"),
            ind,
        ),
    )
    lines = insert(
        lines,
        "ServerScriptService",
        lambda ind: script_item(
            "Script", "MarbleRunServer", SRC / "ServerScriptService" / "MarbleRunServer.server.luau", ind
        ),
    )
    lines = insert(
        lines,
        "StarterPlayerScripts",
        lambda ind: script_item(
            "LocalScript", "MarbleRunClient", SRC / "StarterPlayerScripts" / "MarbleRunClient.client.luau", ind
        ),
    )

    out = "".join(lines)
    # Plots and marbles are small; disabling streaming keeps every piece available to the client.
    out = out.replace('<bool name="StreamingEnabled">true</bool>', '<bool name="StreamingEnabled">false</bool>')
    PLACE.write_text(out, encoding="utf-8")
    print(f"Wrote {PLACE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
