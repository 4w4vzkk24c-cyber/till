#!/usr/bin/env python3
"""Builds Till's macOS app icon from the 512 px seedling artwork.

Source artwork: "Seedling icons created by Umeicon - Flaticon"
https://www.flaticon.com/free-icons/seedling (see README.md and THIRD_PARTY_NOTICES.md).

Output: Sources/Till/Assets.xcassets/AppIcon.appiconset (all macOS sizes) and a 1024 px
master at Design/AppIcon/AppIcon-1024.png. Needs Pillow. Run from the repository root:

    python3 Design/AppIcon/make_icon.py
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import json

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Design/AppIcon/seedling-umeicon-512.png"
MASTER = ROOT / "Design/AppIcon/AppIcon-1024.png"
SET = ROOT / "Sources/Till/Assets.xcassets/AppIcon.appiconset"

CANVAS = 1024
PLATE = 824                 # macOS icon grid: the rounded square is 824 of 1024, centred
SUPER = 4                   # supersampling for clean edges
EXPONENT = 5.0              # superellipse exponent: close to the macOS continuous-corner shape
GLYPH_WIDTH = 590           # seedling width inside the plate (about 72% of it)


def superellipse_mask(size: int, exponent: float) -> Image.Image:
    big = size * SUPER
    mask = Image.new("L", (big, big), 0)
    px = mask.load()
    half = big / 2
    for y in range(big):
        ny = abs((y + 0.5 - half) / half)
        for x in range(big):
            nx = abs((x + 0.5 - half) / half)
            if nx ** exponent + ny ** exponent <= 1.0:
                px[x, y] = 255
    return mask.resize((size, size), Image.LANCZOS)


def plate(size: int) -> Image.Image:
    """Deep green gradient with a soft top highlight, matching the app's dark glass UI."""
    top, bottom = (31, 74, 52), (11, 33, 23)
    base = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(base)
    for y in range(size):
        t = y / (size - 1)
        draw.line([(0, y), (size, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse([size * 0.1, -size * 0.55, size * 0.9, size * 0.45], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.08))
    white = Image.new("RGB", (size, size), (255, 255, 255))
    return Image.composite(white, base, glow)


def build_master() -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    mask = superellipse_mask(PLATE, EXPONENT)
    offset = ((CANVAS - PLATE) // 2, (CANVAS - PLATE) // 2)

    # soft drop shadow under the plate
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (offset[0], offset[1] + 14), mask)
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(22)))

    tile = plate(PLATE).convert("RGBA")
    tile.putalpha(mask)
    # thin lighter rim at the top edge for depth
    rim = ImageChops.subtract(mask, mask.transform(mask.size, Image.AFFINE, (1, 0, 0, 0, 1, -4)))
    ImageDraw.Draw(tile)
    tile.alpha_composite(Image.merge("RGBA", (Image.new("L", mask.size, 255),) * 3 + (rim.point(lambda v: v // 3),)))
    canvas.alpha_composite(tile, offset)

    # the seedling, upscaled from 512 px, centred (slightly below centre: it has a heavy base)
    art = Image.open(SOURCE).convert("RGBA")
    box = art.getchannel("A").getbbox()
    art = art.crop(box)
    scale = GLYPH_WIDTH / art.width
    art = art.resize((GLYPH_WIDTH, round(art.height * scale)), Image.LANCZOS)
    glyph_shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gx, gy = (CANVAS - art.width) // 2, (CANVAS - art.height) // 2 + 6
    glyph_shadow.paste((0, 0, 0, 120), (gx, gy + 10), art.getchannel("A"))
    canvas = Image.alpha_composite(canvas, glyph_shadow.filter(ImageFilter.GaussianBlur(12)))
    canvas.alpha_composite(art, (gx, gy))
    return canvas


SLOTS = [  # (point size, scale, pixels)
    (16, 1, 16), (16, 2, 32), (32, 1, 32), (32, 2, 64), (128, 1, 128),
    (128, 2, 256), (256, 1, 256), (256, 2, 512), (512, 1, 512), (512, 2, 1024),
]


def main() -> None:
    master = build_master()
    master.save(MASTER)
    SET.mkdir(parents=True, exist_ok=True)
    images = []
    for point, scale, pixels in SLOTS:
        name = f"icon_{point}x{point}" + ("@2x" if scale == 2 else "") + ".png"
        master.resize((pixels, pixels), Image.LANCZOS).save(SET / name)
        images.append({"idiom": "mac", "scale": f"{scale}x", "size": f"{point}x{point}", "filename": name})
    (SET / "Contents.json").write_text(json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    (SET.parent / "Contents.json").write_text(json.dumps({"info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    print("wrote", MASTER.relative_to(ROOT), "and", len(images), "icon sizes")


if __name__ == "__main__":
    main()
