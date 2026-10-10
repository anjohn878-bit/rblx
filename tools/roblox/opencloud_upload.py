"""Upload a finished asset to Roblox with the Open Cloud Assets API.

    python -m tools.roblox.opencloud_upload out/chest.fbx --type Model --name "Chest"
    python -m tools.roblox.opencloud_upload out/icons/coin.png --type Decal --name "Coin icon"

Env: ROBLOX_API_KEY (Assets API: read+write), and ROBLOX_USER_ID or ROBLOX_GROUP_ID.
Prints the asset id and appends it to assets.lock.json so code can reference it.
Audio uploads are rate-limited per month - prefer the sound library (see roblox-sound skill).
"""
import argparse
import json
import os
import pathlib
import sys
import time

from tools.common.http import json_request, multipart, request, require_env

BASE = "https://apis.roblox.com/assets/v1"
CONTENT_TYPES = {
    ".fbx": "model/fbx",
    ".rbxm": "model/x-rbxm",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".bmp": "image/bmp",
    ".tga": "image/tga",
    ".mp3": "audio/mpeg",
    ".ogg": "audio/ogg",
}
LEDGER = pathlib.Path("assets.lock.json")


def creator():
    if os.environ.get("ROBLOX_GROUP_ID"):
        return {"groupId": os.environ["ROBLOX_GROUP_ID"]}
    (uid,) = require_env("ROBLOX_USER_ID")
    return {"userId": uid}


def upload(path, asset_type, name, description=""):
    (key,) = require_env("ROBLOX_API_KEY")
    path = pathlib.Path(path)
    ctype = CONTENT_TYPES.get(path.suffix.lower())
    if not ctype:
        sys.exit(f"Unsupported file type {path.suffix}")
    meta = {
        "assetType": asset_type,
        "displayName": name[:50],
        "description": description or name,
        "creationContext": {"creator": creator()},
    }
    body, mp_type = multipart(
        [
            ("request", None, "application/json", json.dumps(meta).encode()),
            ("fileContent", path.name, ctype, path.read_bytes()),
        ]
    )
    status, raw = request("POST", f"{BASE}/assets", {"x-api-key": key, "Content-Type": mp_type}, body, 300)
    op = json.loads(raw or b"{}")
    if status >= 300:
        sys.exit(f"Upload failed {status}: {op}")
    for _ in range(60):
        if op.get("done"):
            break
        time.sleep(2)
        status, op = json_request("GET", f"{BASE}/{op['path']}", headers={"x-api-key": key})
    if "error" in op or not op.get("done"):
        sys.exit(f"Upload did not finish: {op}")
    return op["response"]["assetId"]


def record(name, asset_type, asset_id, source):
    ledger = json.loads(LEDGER.read_text()) if LEDGER.exists() else {}
    ledger[name] = {"type": asset_type, "id": f"rbxassetid://{asset_id}", "source": str(source)}
    LEDGER.write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--type", required=True, choices=["Model", "Decal", "Audio"])
    ap.add_argument("--name", required=True)
    ap.add_argument("--description", default="")
    a = ap.parse_args()
    asset_id = upload(a.file, a.type, a.name, a.description)
    record(a.name, a.type, asset_id, a.file)
    print(f"rbxassetid://{asset_id}")


if __name__ == "__main__":
    main()
