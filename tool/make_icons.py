#!/usr/bin/env python3
"""Builds the app icons from assets/revoice_logo.png (the R mark only, without the "ReVoice" text).

  python3 tool/make_icons.py

iOS: every size in ios/Runner/Assets.xcassets/AppIcon.appiconset (opaque RGB, no alpha).
Android: adaptive icon (white background + foreground) and legacy mipmap launcher icons.
"""
import json
import os
from collections import deque

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "revoice_logo.png")
MARK_BOTTOM = 860          # the word "ReVoice" starts below this row
IOS_DIR = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
RES = os.path.join(ROOT, "android/app/src/main/res")


def load_mark():
    """Returns (RGBA mark with transparent surroundings, background colour)."""
    img = Image.open(SRC).convert("RGB")
    w, h = img.size
    # Background colour: median of the border pixels.
    border = [img.getpixel((x, 5)) for x in range(0, w, 7)] + [img.getpixel((5, y)) for y in range(0, MARK_BOTTOM, 7)]
    bg = tuple(sorted(c[i] for c in border)[len(border) // 2] for i in range(3))
    top = img.crop((0, 0, w, MARK_BOTTOM))
    px = top.load()
    tw, th = top.size

    def far(x, y):
        r, g, b = px[x, y]
        return abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 60

    xs = [x for x in range(tw) if any(far(x, y) for y in range(0, th, 3))]
    ys = [y for y in range(th) if any(far(x, y) for x in range(0, tw, 3))]
    box = (min(xs) - 6, min(ys) - 6, max(xs) + 7, max(ys) + 7)
    mark = top.crop(box).convert("RGBA")
    mw, mh = mark.size
    mp = mark.load()

    # Everything connected to the crop border that is close to the background is outside the mark
    # (the light-blue microphone inside the mark is not connected to the border, so it stays).
    def near(x, y):
        r, g, b = mp[x, y][:3]
        return abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) <= 36

    outside = [[False] * mw for _ in range(mh)]
    q = deque()
    for x in range(mw):
        for y in (0, mh - 1):
            if near(x, y) and not outside[y][x]:
                outside[y][x] = True
                q.append((x, y))
    for y in range(mh):
        for x in (0, mw - 1):
            if near(x, y) and not outside[y][x]:
                outside[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < mw and 0 <= ny < mh and not outside[ny][nx] and near(nx, ny):
                outside[ny][nx] = True
                q.append((nx, ny))
    alpha = Image.new("L", (mw, mh), 255)
    ap = alpha.load()
    for y in range(mh):
        for x in range(mw):
            if outside[y][x]:
                ap[x, y] = 0
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    mark.putalpha(alpha)
    return mark, bg


def compose(mark, size, fill, bg=None):
    """Mark centred on a square; `fill` is the share of the canvas height the mark may use."""
    mw, mh = mark.size
    scale = size * fill / mh
    m = mark.resize((max(1, round(mw * scale)), max(1, round(mh * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (*bg, 255) if bg else (0, 0, 0, 0))
    canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas


def main():
    mark, bg = load_mark()
    print("background colour", bg, "mark size", mark.size)
    # --- iOS: one 1024 master, then every size the asset catalog lists (RGB, no alpha)
    master = compose(mark, 1024, 0.62, bg).convert("RGB")
    with open(os.path.join(IOS_DIR, "Contents.json")) as f:
        contents = json.load(f)
    for image in contents["images"]:
        points = float(image["size"].split("x")[0])
        px = round(points * int(image["scale"].rstrip("x")))
        master.resize((px, px), Image.LANCZOS).save(os.path.join(IOS_DIR, image["filename"]), "PNG")
    print("iOS icons:", len(contents["images"]))
    # --- Android adaptive icon: 108dp canvas, the mark stays inside the 66% safe zone
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, d in densities.items():
        folder = os.path.join(RES, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        compose(mark, round(108 * d), 0.50).save(os.path.join(folder, "ic_launcher_foreground.png"))
        legacy = compose(mark, round(48 * d), 0.66, bg).convert("RGB")
        legacy.save(os.path.join(folder, "ic_launcher.png"))
    any26 = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(any26, exist_ok=True)
    adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""
    with open(os.path.join(any26, "ic_launcher.xml"), "w") as f:
        f.write(adaptive)
    with open(os.path.join(RES, "values", "ic_launcher_background.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#FFFFFF</color>\n</resources>\n')
    print("Android icons done")


main()
