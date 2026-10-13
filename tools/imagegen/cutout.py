"""Remove the plain background from a generated icon/sprite and trim it square.

    python -m tools.imagegen.cutout assets/icons/coin.png            # in place
    python -m tools.imagegen.cutout in.png -o out.png --size 256

Flood-fills from every border pixel that is close to the corner colour, so only the
background connected to the edges goes transparent (white highlights inside the
object survive). RULE: Flux icons come on a white square - Roblox shows that square.
"""
import argparse
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

MARK = (255, 0, 255, 0)


def cutout(img, thresh=40, size=256, pad=0.06):
    rgba = img.convert("RGBA")
    work = rgba.copy()
    w, h = work.size
    border = [(x, 0) for x in range(0, w, 4)] + [(x, h - 1) for x in range(0, w, 4)]
    border += [(0, y) for y in range(0, h, 4)] + [(w - 1, y) for y in range(0, h, 4)]
    bg = rgba.getpixel((0, 0))
    for xy in border:
        px = work.getpixel(xy)
        if px == MARK:
            continue
        if sum(abs(a - b) for a, b in zip(px[:3], bg[:3])) <= thresh * 3:
            ImageDraw.floodfill(work, xy, MARK, thresh=thresh)
    # alpha mask: background -> 0, then soften the edge by 1px
    r, g, b, _ = work.split()
    is_bg = ImageChops.multiply(
        ImageChops.multiply(r.point(lambda v: 255 if v == 255 else 0), g.point(lambda v: 255 if v == 0 else 0)),
        b.point(lambda v: 255 if v == 255 else 0),
    )
    alpha = ImageChops.invert(is_bg).filter(ImageFilter.GaussianBlur(0.7))
    out = rgba.copy()
    out.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 16 else 0).getbbox()
    if not bbox:
        raise SystemExit("cutout removed everything - background too similar to the object; lower --thresh")
    out = out.crop(bbox)
    side = int(max(out.size) * (1 + 2 * pad))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(out, ((side - out.width) // 2, (side - out.height) // 2))
    coverage = sum(1 for v in alpha.getdata() if v > 128) / (w * h)
    return canvas.resize((size, size), Image.LANCZOS), coverage


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("-o", "--out")
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--thresh", type=int, default=40)
    a = ap.parse_args()
    img, coverage = cutout(Image.open(a.input), a.thresh, a.size)
    out = pathlib.Path(a.out or a.input).with_suffix(".png")
    img.save(out)
    print(f"{out} (object covers {coverage:.0%} of the original)")
    if coverage > 0.9:
        print("WARN: almost nothing was removed - the background may not be plain; regenerate with a plain background")


if __name__ == "__main__":
    main()
