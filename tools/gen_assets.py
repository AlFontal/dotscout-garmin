#!/usr/bin/env python3
"""Generate the face's icons into resources/drawables/.

Icons are drawn here at 4x, white, and downsampled; the face tints them. Text uses the watch's
own vector fonts, so there are no font assets.

Usage: python3 tools/gen_assets.py
Needs Pillow.
"""
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_OUT = os.path.join(ROOT, "resources", "drawables", "icons")

# ---- icons -------------------------------------------------------------------------------

S = 4            # supersampling
N = 32 * S       # canvas


def icon(name, size, draw_fn):
    global N
    N = size * S
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_fn(d, (255, 255, 255, 255))
    img = img.resize((size, size), Image.LANCZOS)
    img.save(os.path.join(ICON_OUT, "%s.png" % name))


def P(*pts):
    k = N / (28.0 * S)
    return [(x * S * k, y * S * k) for x, y in pts]


def flame(d, c):
    # Outer flame with a leaning tip and a side tongue, then a cut-out inner flame.
    def teardrop(cx, cy, r, tip_dx, tip_h):
        pts = [(cx + tip_dx, cy - tip_h)]
        for i in range(0, 41):
            t = math.pi * i / 40
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
        return pts[:1] + list(reversed(pts[1:]))
    d.polygon(P(*teardrop(14, 17, 9, 2, 16)), fill=c)
    d.polygon(P((6, 15), (5.5, 8), (10, 12)), fill=c)
    d.polygon(P(*teardrop(14, 21, 4, -1, 8)), fill=(0, 0, 0, 0))


def thermometer(d, c):
    w = 2.2 * S
    d.rounded_rectangle(P((11.5, 2), (16.5, 18)), radius=2.5 * S, outline=c, width=int(w))
    d.ellipse(P((8.5, 15), (19.5, 26)), fill=c)
    d.rectangle(P((13.2, 9), (14.8, 17)), fill=c)


def drop(d, c):
    pts = [(14, 2)]
    for i in range(0, 33):
        t = math.pi * i / 32
        pts.append((14 + 8 * math.cos(math.pi - t), 17 + 8 * math.sin(t)))
    pts = [(14, 2), (22, 17)] + [(14 + 8 * math.cos(t), 17 + 8 * math.sin(t)) for t in [math.pi * i / 32 for i in range(0, 33)]] + [(6, 17)]
    d.polygon(P(*pts), fill=c)


def cookie(d, c):
    d.ellipse(P((3, 3), (25, 25)), fill=c)
    for x, y in ((10, 10), (17, 9), (16, 17), (9, 17)):
        d.ellipse(P((x - 1.6, y - 1.6), (x + 1.6, y + 1.6)), fill=(0, 0, 0, 0))


def basal(d, c):
    w = int(2.4 * S)
    d.line(P((2, 20), (8, 20), (8, 10), (15, 10), (15, 15), (21, 15), (21, 7), (26, 7)), fill=c, width=w, joint="curve")


def lungs(d, c):
    d.rounded_rectangle(P((3, 8), (12.5, 25)), radius=4.5 * S, fill=c)
    d.rounded_rectangle(P((15.5, 8), (25, 25)), radius=4.5 * S, fill=c)
    d.rectangle(P((13, 2), (15, 13)), fill=c)


def wave(d, c):
    pts = [(2 + i * 0.5, 14 - 8 * math.sin(i * 0.5 * 2 * math.pi / 12) * (1 if (i // 12) % 2 == 0 else 0.6)) for i in range(49)]
    d.line(P(*pts), fill=c, width=int(2.6 * S), joint="curve")


def stopwatch(d, c):
    w = int(2.4 * S)
    d.ellipse(P((4, 6), (24, 26)), outline=c, width=w)
    d.rectangle(P((12, 1.5), (16, 4)), fill=c)
    d.line(P((14, 16), (14, 10)), fill=c, width=w)
    d.line(P((14, 16), (18, 18)), fill=c, width=w)


# Bitmap fallbacks for less common fields; the main icons are vector shapes in source/Icons.mc.
ICONS = [
    # name, size px, draw function
    ("calories", 18, flame), ("temperature", 18, thermometer), ("iob", 18, drop), ("cob", 18, cookie),
    ("basal", 18, basal), ("vo2max", 18, lungs), ("stress", 18, wave), ("activemin", 18, stopwatch),
]


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


def camel(name):
    return "".join(p[:1].upper() + p[1:] for p in name.split("_"))


def main():
    os.makedirs(ICON_OUT, exist_ok=True)

    # White icons; the face tints them per field.
    for f in os.listdir(ICON_OUT):
        os.remove(os.path.join(ICON_OUT, f))
    dot_icon(65, True).save(os.path.join(ROOT, "resources", "drawables", "launcher_icon.png"))
    os.makedirs(os.path.join(ROOT, "docs", "store"), exist_ok=True)
    dot_icon(512, False).save(os.path.join(ROOT, "docs", "store", "icon-512.png"))
    lines = ['    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>']
    for name, size, fn in ICONS:
        icon(name, size, fn)
        lines.append('    <bitmap id="Icon%s" filename="icons/%s.png" automaticPalette="false"/>' % (camel(name), name))
    with open(os.path.join(ROOT, "resources", "drawables", "drawables.xml"), "w") as f:
        f.write("<drawables>\n" + "\n".join(lines) + "\n</drawables>\n")


if __name__ == "__main__":
    main()
