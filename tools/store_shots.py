#!/usr/bin/env python3
"""Render the store screenshots, the store icon and the device sheet in the Connect IQ simulator.

Each shot builds a patched copy of the project: demo data in a fixed state, a fixed time and
reading age, sample field values instead of the simulator's zeros, and always-on forced on when
asked. It runs the copy in the simulator, captures the window and crops the watch screen using
the device's display rectangle from the SDK.

Usage: python3 tools/store_shots.py [screens] [icon] [sheet]   (default: all three)
Needs Pillow, the Connect IQ SDK with the devices installed, and the developer key (DEVKEY).
Runs on macOS: it drives the simulator window with screencapture and Swift.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "store")
DEVICES = os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Devices")
DEVKEY = os.environ.get("DEVKEY", os.path.expanduser("~/projects/cgm-garmin-datafield/.env/developer_key"))
TITLE_BAR = 28  # simulator window title bar, in points; the status bar below the device is the same

ICON_BG = (0x26, 0x2E, 0x36)    # dark slate, so the black face still reads as a disc
HERO_BG = (0x1B, 0x21, 0x28)
HERO = ["venu3", "fr965", "fenix8pro47mm"]    # left, centre (largest), right

# Mock buckets with a pleasant in-range day curve (MockCgm.DAY is a function of the bucket).
DAY_BUCKET = 100869

# name: device, scenario (MockCgm enum), layout (0 classic, 1 tall), time colour, units (1 mmol),
# reading age in minutes, always-on.
SCREENS = [
    ("1-in-range", dict(device="fr965", scenario="DAY", layout=1, tint=0, units=0, age=2)),
    ("2-rising-classic", dict(device="fr965", scenario="RISING", layout=0, tint=0, units=0, age=1)),
    ("3-low-tinted-mmol", dict(device="fr965", scenario="FALLING", layout=1, tint=1, units=1, age=3)),
    ("4-always-on", dict(device="fr965", scenario="DAY", layout=1, tint=0, units=0, age=2, aod=True)),
]

SHEET = [
    ("fr965", "Forerunner 965", dict(scenario="DAY", layout=1, tint=0, units=0)),
    ("fr970", "Forerunner 970", dict(scenario="RISING", layout=1, tint=1, units=0)),
    ("fr57047mm", "Forerunner 570", dict(scenario="FALLING", layout=1, tint=2, units=0)),
    ("venu3", "Venu 3", dict(scenario="DAY", layout=0, tint=1, units=1)),
    ("venu445mm", "Venu 4", dict(scenario="HIGH", layout=1, tint=2, units=0)),
    ("fenix847mm", "fēnix 8", dict(scenario="STALE", layout=0, tint=0, units=0)),
    ("fenix8pro47mm", "fēnix 8 Pro", dict(scenario="FALLING", layout=1, tint=1, units=1)),
    ("epix2pro51mm", "epix Pro 51 mm", dict(scenario="RISING", layout=1, tint=1, units=0, aod=True)),
    ("d2mach2", "D2 Mach 2", dict(scenario="RISING", layout=1, tint=2, units=0)),
    ("d2mach2pro", "D2 Mach 2 Pro", dict(scenario="DAY", layout=0, tint=0, units=1)),
    ("fr265", "Forerunner 265", dict(scenario="DAY", layout=1, tint=1, units=0)),
    ("fr265s", "Forerunner 265S", dict(scenario="RISING", layout=1, tint=0, units=1)),
    ("vivoactive6", "vívoactive 6", dict(scenario="FALLING", layout=0, tint=2, units=0)),
    ("venu441mm", "Venu 4 41 mm", dict(scenario="DAY", layout=1, tint=0, units=1)),
    ("fr165", "Forerunner 165", dict(scenario="HIGH", layout=1, tint=1, units=0)),
]

SWIFT = r'''
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
  let name = w[kCGWindowName as String] as? String ?? ""
  if name.hasPrefix("CIQ Simulator") {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print("\(w[kCGWindowNumber as String]!)\t\(b["Width"]!)\t\(b["Height"]!)\t\(name)")
  }
}
'''


def sh(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw).stdout


def patch(path, pairs):
    s = open(path).read()
    for old, new in pairs:
        assert old in s, "%s: %r not found" % (os.path.basename(path), old)
        s = s.replace(old, new)
    open(path, "w").write(s)


def build(work, device, scenario, layout, tint, units, age=2, aod=False, hhmm=(10, 8)):
    """Copy the project into `work`, patch it into a fixed demo state, and build it."""
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    for name in ("manifest.xml", "monkey.jungle", "source", "resources", "resources-mip"):
        src = os.path.join(ROOT, name)
        (shutil.copytree if os.path.isdir(src) else shutil.copy)(src, os.path.join(work, name))
    src = os.path.join(work, "source")
    patch(os.path.join(src, "CgmConfig.mc"), [
        ('return getNumber("DataSource", SRC_NIGHTSCOUT);', "return SRC_MOCK;"),
    ])
    patch(os.path.join(src, "CgmModel.mc"), [
        ('CgmConfig.getNumber("MockScenario", MockCgm.DAY)', "MockCgm." + scenario),
        ('return CgmConfig.getNumber("Units", 0) == 1;', "return %d == 1;" % units),
    ])
    patch(os.path.join(src, "MockCgm.mc"), [
        ("hist[i] = value(scenario, latest - k, k + gap);", "hist[i] = value(scenario, %d - k, k + gap);" % DAY_BUCKET),
    ])
    view = [
        ('CgmConfig.getNumber("Layout", 1) == 1', "%d == 1" % layout),
        ('var tint = CgmConfig.getNumber("TimeColor", 0);', "var tint = %d;" % tint),
        ("var hour = clock.hour;", "var hour = %d;" % hhmm[0]),
        ("dotDigit(dc, clock.min / 10,", "dotDigit(dc, %d / 10," % hhmm[1]),
        ("dotDigit(dc, clock.min % 10,", "dotDigit(dc, %d %% 10," % hhmm[1]),
    ]
    if scenario != "STALE":
        view.append(('var age = (now - (cgm["t"] as Number)) / 60;', "var age = %d;" % age))
    if aod:
        # Minute 12 has no burn-in shift sideways and the standard one down, so the face is centred.
        view += [
            ("_aod = _sleeping && (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;", "_aod = true;"),
            ("var min = System.getClockTime().min;", "var min = 12;"),
        ]
    patch(os.path.join(src, "CgmFaceView.mc"), view)
    patch(os.path.join(src, "Fields.mc"), [
        ("    function value(field as Number, cgm as Dictionary?) as Array? {\n",
         "    function value(field as Number, cgm as Dictionary?) as Array? {\n"
         '        if (field == STEPS) { return [:steps, "8432", ""]; }\n'
         '        if (field == ELEVATION_GAIN) { return [:ascent, "124", "m"]; }\n'
         '        if (field == TEMPERATURE) { return [:temperature, "19°", ""]; }\n'),
    ])
    prg = os.path.join(work, "face.prg")
    sh("monkeyc", "-d", device, "-f", "monkey.jungle", "-o", prg, "-y", DEVKEY, cwd=work)
    return prg


def windows(swift):
    out = sh("swift", swift)
    rows = [line.split("\t") for line in out.splitlines() if line.strip()]
    return [(int(r[0]), int(r[1]), int(r[2]), r[3]) for r in rows]


def start_simulator(swift):
    subprocess.Popen(["connectiq"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(30):
        time.sleep(2)
        if windows(swift):
            time.sleep(3)
            return
    raise RuntimeError("the simulator did not start")


def drawn(face):
    """True once the face has drawn: the time's dots light the top of the screen. A face that
    failed to load shows only the simulator's blue triangle in the middle."""
    top = face.crop((0, int(face.height * 0.15), face.width, int(face.height * 0.4)))
    return sum(1 for r, g, b in top.getdata() if max(r, g, b) > 150 and b < r + 60) > 300


def capture(prg, device, swift, shot):
    """Run `prg` on `device` and return the window capture once the face has drawn. Restarts the
    simulator once if it stops loading apps, which happens after many relaunches."""
    sim = json.load(open(os.path.join(DEVICES, device, "simulator.json")))
    name = json.load(open(os.path.join(DEVICES, device, "compiler.json")))["displayName"]
    image = Image.open(os.path.join(DEVICES, device, sim["image"]))
    if not windows(swift):
        start_simulator(swift)
    for launch in range(4):
        if launch == 2:
            subprocess.run(["pkill", "-f", "monkeydodeux"])
            subprocess.run(["pkill", "-f", "ConnectIQ.app/Contents/MacOS/simulator"])
            time.sleep(2)
            start_simulator(swift)
        subprocess.run(["pkill", "-f", "monkeydodeux"])
        subprocess.Popen(["monkeydo", prg, device], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        for attempt in range(15):
            time.sleep(2)
            wins = [w for w in windows(swift) if name in w[3] and w[1] == image.width]
            if not wins or attempt < 3:
                continue
            # The window can vanish between listing and capture while the simulator relaunches.
            if subprocess.run(["screencapture", "-x", "-o", "-l", str(wins[0][0]), shot]).returncode != 0:
                continue
            im = Image.open(shot).convert("RGB")
            if im.width == image.width:
                # A window on a non-Retina screen captures at 1x; double it so the crops below
                # work the same, and the watch screen comes back at its native size unchanged.
                im = im.resize((2 * im.width, 2 * im.height), Image.NEAREST)
            if im.width == 2 * image.width and drawn(screen(im, sim)):
                return im, sim, image
    raise RuntimeError("%s never drew on the %s" % (os.path.basename(prg), name))


def screen(im, sim):
    """The watch screen at its native resolution, from a 2x window capture."""
    loc = sim["display"]["location"]
    x, y = 2 * loc["x"], 2 * (TITLE_BAR + loc["y"])
    crop = im.crop((x, y, x + 2 * loc["width"], y + 2 * loc["height"]))
    face = crop.resize((loc["width"], loc["height"]), Image.LANCZOS)
    # Black outside the round display, so the bezel doesn't show in the corners.
    return Image.composite(face, Image.new("RGB", face.size, "black"), round_mask(face).getchannel("A"))


def device_shot(im, image):
    """The whole device render with the face on it, at the render's own size, cut out of the
    render's background (white for most, black for some; flood-filled from the corners) onto
    transparency."""
    crop = im.crop((0, 2 * TITLE_BAR, im.width, 2 * (TITLE_BAR + image.height)))
    crop = crop.resize(image.size, Image.LANCZOS)
    # The window's frame and the title and status bar separators run along the edges.
    draw = ImageDraw.Draw(crop)
    bg = crop.getpixel((8, 8))
    draw.rectangle((0, 0, 2, crop.height), fill=bg)
    draw.rectangle((crop.width - 3, 0, crop.width, crop.height), fill=bg)
    draw.rectangle((0, 0, crop.width, 2), fill=bg)
    draw.rectangle((0, crop.height - 3, crop.width, crop.height), fill=bg)
    # Lift every value off 0 so 0 can mark the background, whatever colour the render sits on.
    mask = crop.convert("L").point(lambda v: 20 + v * 235 // 255)
    w, h = mask.size
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        ImageDraw.floodfill(mask, corner, 0, thresh=10)
    mask = mask.point(lambda v: 0 if v == 0 else 255)
    out = crop.convert("RGBA")
    out.putalpha(mask)
    return out


def round_mask(img):
    size = img.width
    k = 4
    mask = Image.new("L", (size * k, size * k), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * k - 1, size * k - 1), fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask.resize((size, size), Image.LANCZOS))
    return out


def main():
    want = set(sys.argv[1:]) or {"screens", "icon", "sheet"}
    tmp = tempfile.mkdtemp(prefix="dotscout-shots-")
    swift = os.path.join(tmp, "windows.swift")
    open(swift, "w").write(SWIFT)
    work = os.path.join(tmp, "work")
    shot = os.path.join(tmp, "shot.png")

    if want & {"screens", "icon"}:
        for name, spec in SCREENS:
            if "screens" not in want and name != "1-in-range":
                continue
            spec = dict(spec)
            device = spec.pop("device")
            im, sim, _ = capture(build(work, device, **spec), device, swift, shot)
            face = screen(im, sim)
            if "screens" in want:
                face.save(os.path.join(OUT, name + ".png"))
                print("wrote", name)
            if name == "1-in-range" and "icon" in want:
                # The store icon is the face itself. Garmin asks for 500 x 500 sRGB with about
                # 10 px of padding on a solid background that is neither transparent nor black.
                icon = Image.new("RGB", (500, 500), ICON_BG)
                disc = round_mask(face.resize((480, 480), Image.LANCZOS))
                icon.paste(disc, (10, 10), disc)
                icon.save(os.path.join(OUT, "store-icon-500.png"))
                print("wrote store-icon-500")

    if "sheet" in want:
        tiles = []
        for device, label, spec in SHEET:
            im, sim, image = capture(build(work, device, **spec), device, swift, shot)
            tiles.append((device_shot(im, image), label))
            print("captured", device)
        cols, cell_w, cell_h, label_h = 5, 560, 660, 60
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell_w, rows * (cell_h + label_h)), "white")
        draw = ImageDraw.Draw(sheet)
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 30)
        except OSError:
            font = ImageFont.load_default()
        for i, (tile, label) in enumerate(tiles):
            tile = tile.convert("RGBA")
            tile.thumbnail((cell_w - 20, cell_h - 10), Image.LANCZOS)
            cx = (i % cols) * cell_w + cell_w // 2
            top = (i // cols) * (cell_h + label_h)
            sheet.paste(tile, (cx - tile.width // 2, top + cell_h - tile.height), tile)
            w = draw.textlength(label, font=font)
            draw.text((cx - w / 2, top + cell_h + 10), label, fill=(40, 40, 40), font=font)
        sheet.save(os.path.join(OUT, "all-devices.png"))
        print("wrote all-devices")

        # Hero: three watches on slate, no text, so one image serves every language.
        shots = {device: tile for (device, _, _), (tile, _) in zip(SHEET, tiles)}
        hero = Image.new("RGB", (1440, 720), HERO_BG)
        for device, cx, height in zip(HERO, (290, 720, 1150), (520, 640, 520)):
            tile = shots[device]
            tile = tile.resize((round(tile.width * height / tile.height), height), Image.LANCZOS)
            hero.paste(tile, (cx - tile.width // 2, (720 - height) // 2), tile)
        hero.save(os.path.join(OUT, "hero-1440x720.png"))
        print("wrote hero")

    subprocess.run(["pkill", "-f", "monkeydodeux"])
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
