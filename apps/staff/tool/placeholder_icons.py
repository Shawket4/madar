#!/usr/bin/env python3
"""Dawam's PLACEHOLDER launcher icons (PS-6, APP-2), in the brand colours.

There is no Dawam mark yet. This draws a clean stand-in (a clock face in the
Madar symbol's ring-and-orbit style, white on Madar teal) at every size the
Android and iOS projects need. When the real mark arrives, replace the icons
with it (e.g. flutter_launcher_icons) and delete this script.

    python3 apps/staff/tool/placeholder_icons.py      # from the repo root

Needs Pillow. Writes:
  android/app/src/main/res/mipmap-*/ic_launcher.png              legacy, full bleed
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png   adaptive layer
  android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png   themed icon
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  android/app/src/main/res/values/ic_launcher_background.xml
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png            opaque RGB
"""
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
TEAL = (0x0F, 0x7A, 0x8A)  # design_system `brand` (light)
WHITE = (255, 255, 255)
BIG = 4096  # drawn large, then scaled down


def mark(size_frac: float, fg, bg) -> Image.Image:
    """The clock mark on a BIG canvas; `size_frac` is the ring's outer
    diameter as a fraction of the canvas."""
    img = Image.new("RGBA", (BIG, BIG), bg)
    d = ImageDraw.Draw(img)
    c = BIG / 2
    outer = BIG * size_frac / 2
    stroke = outer * 0.26
    r = outer - stroke / 2
    d.ellipse((c - outer, c - outer, c + outer, c + outer), outline=fg, width=int(stroke))
    # Hands: minute at 12, hour at 3 (round caps).
    hand = stroke * 0.72

    def line(angle_deg, length):
        a = math.radians(angle_deg)
        x, y = c + math.sin(a) * length, c - math.cos(a) * length
        d.line((c, c, x, y), fill=fg, width=int(hand))
        for px, py in ((c, c), (x, y)):
            d.ellipse((px - hand / 2, py - hand / 2, px + hand / 2, py + hand / 2), fill=fg)

    line(0, r * 0.62)
    line(90, r * 0.45)
    # The orbit dot on the ring, as on the Madar symbol (top-right).
    a = math.radians(45)
    dx, dy = c + math.sin(a) * r, c - math.cos(a) * r
    dot = stroke * 0.95
    d.ellipse((dx - dot, dy - dot, dx + dot, dy + dot), fill=fg)
    return img


def save(img: Image.Image, px: int, path: str, rgb: bool = False) -> None:
    out = img.resize((px, px), Image.LANCZOS)
    if rgb:
        out = out.convert("RGB")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path, optimize=True)


def main() -> None:
    full = mark(0.62, WHITE + (255,), TEAL + (255,))
    # Adaptive layers: the mark inside the 66/108 safe zone, no background.
    fore = mark(0.50, WHITE + (255,), (0, 0, 0, 0))
    mono = mark(0.50, (0, 0, 0, 255), (0, 0, 0, 0))

    res = os.path.join(APP, "android/app/src/main/res")
    for dpi, legacy in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        adaptive = legacy * 108 // 48
        save(full, legacy, f"{res}/mipmap-{dpi}/ic_launcher.png")
        save(fore, adaptive, f"{res}/mipmap-{dpi}/ic_launcher_foreground.png")
        save(mono, adaptive, f"{res}/mipmap-{dpi}/ic_launcher_monochrome.png")
    os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
    with open(f"{res}/mipmap-anydpi-v26/ic_launcher.xml", "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Dawam placeholder icon (apps/staff/tool/placeholder_icons.py). -->\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n'
        )
    with open(f"{res}/values/ic_launcher_background.xml", "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            '    <!-- Madar teal (design_system `brand`). -->\n'
            '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n'
            '</resources>\n' % TEAL
        )

    ios = os.path.join(APP, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    for name in sorted(os.listdir(ios)):
        if not name.endswith(".png"):
            continue
        with Image.open(os.path.join(ios, name)) as old:
            px = old.size[0]
        # iOS masks the corners itself; the App Store refuses alpha.
        save(full, px, os.path.join(ios, name), rgb=True)


if __name__ == "__main__":
    main()
