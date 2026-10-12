#!/usr/bin/env python3
"""Generate the launcher icon and the 512 px dot-grid brand mark (docs/store/icon-512.png).

Data field icons are vector shapes in source/Icons.mc, and text uses the watch's own vector
fonts, so there are no other assets.

Usage: python3 tools/gen_assets.py
Needs Pillow.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---- launcher and store icon ---------------------------------------------------------------

def dot_icon(size, round_bg):
    """A 7 x 7 dot grid with a glucose curve lit through it, in the face's dot language."""
    k = 8
    n = size * k
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if round_bg:
        d.ellipse((0, 0, n - 1, n - 1), fill=(0, 0, 0, 255))
    else:
        d.rounded_rectangle((0, 0, n - 1, n - 1), radius=n * 0.22, fill=(0, 0, 0, 255))
    cols = 7
    pitch = n * 0.105
    x0 = n / 2 - pitch * (cols - 1) / 2
    y0 = n / 2 - pitch * (cols - 1) / 2
    # Row per column (0 = top): steady, a dip, then rising into the latest reading.
    curve = [3, 3, 4, 4, 3, 2, 1]
    for c in range(cols):
        for r in range(cols):
            cx, cy = x0 + c * pitch, y0 + r * pitch
            if curve[c] == r:
                rad = pitch * (0.42 if c == cols - 1 else 0.3)
                d.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=(0x34, 0xD3, 0x99, 255))
            else:
                rad = pitch * 0.14
                d.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=(0x3A, 0x4A, 0x50, 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    dot_icon(65, True).save(os.path.join(ROOT, "resources", "drawables", "launcher_icon.png"))
    os.makedirs(os.path.join(ROOT, "docs", "store"), exist_ok=True)
    dot_icon(512, False).save(os.path.join(ROOT, "docs", "store", "icon-512.png"))


if __name__ == "__main__":
    main()
