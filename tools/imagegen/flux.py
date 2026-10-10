"""Generate an image with FLUX.1 [schnell] on Cloudflare Workers AI (free tier).

    python -m tools.imagegen.flux "a wooden treasure chest, game asset, plain white background" -o out/chest.png
    python -m tools.imagegen.flux --preset icon "gold coin" -o out/icons/coin.png

Env: CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN (Workers AI: Read permission).
Claude looks at every result and re-prompts until it is right - keep the
prompt log (`<out>.prompt.txt`) so the winning prompt can be reused.
"""
import argparse
import base64
import pathlib
import sys

from tools.common.http import json_request, require_env

MODEL = "@cf/black-forest-labs/flux-1-schnell"

# Prompt suffixes that make outputs usable downstream. Learned rules live here.
PRESETS = {
    # Single object, centred, nothing cropped - what image->3D needs.
    "model3d": ", single object, centered, full object visible, three-quarter view, "
    "plain pure white background, soft even studio lighting, no shadow, no text",
    # Flat game UI icon - no emoji look, readable at 48px.
    "icon": ", game UI icon, bold simple silhouette, thick dark outline, cel shaded, "
    "centered, plain solid white background, no text, no border",
    "texture": ", seamless tileable texture, top-down, flat even lighting, stylized",
    "none": "",
}


def generate(prompt, steps=8, seed=None):
    account, token = require_env("CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_TOKEN")
    url = f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL}"
    payload = {"prompt": prompt, "steps": max(1, min(steps, 8))}
    if seed is not None:
        payload["seed"] = seed
    status, data = json_request("POST", url, payload, {"Authorization": f"Bearer {token}"})
    if status != 200 or not data.get("success", True):
        sys.exit(f"Cloudflare error {status}: {data}")
    return base64.b64decode(data["result"]["image"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--preset", choices=PRESETS, default="none")
    ap.add_argument("--steps", type=int, default=8)
    ap.add_argument("--seed", type=int)
    a = ap.parse_args()
    full = a.prompt + PRESETS[a.preset]
    out = pathlib.Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    img = generate(full, a.steps, a.seed)
    out.write_bytes(img)
    out.with_suffix(out.suffix + ".prompt.txt").write_text(full + (f"\nseed={a.seed}" if a.seed else "") + "\n")
    print(out)


if __name__ == "__main__":
    main()
