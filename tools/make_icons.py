"""Builds the P.A.Z.I.Y.O.N app icons from the logo artwork.

The source is a 3D render on a white background with a drop shadow, so it is
not used as-is: the white/red artwork is cut out of the blue tile (anything
clearly blue becomes transparent), then placed on a clean blue tile at every
size Android and the web need. The adaptive icon keeps the artwork inside the
launcher-safe zone so no launcher mask crops it.

    pip install pillow
    python3 tools/make_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'app/assets/brand/logo-source.jpg'
RES = ROOT / 'app/android/app/src/main/res'

TOP = (122, 184, 236)     # tile gradient, sampled from the logo
BOTTOM = (78, 145, 205)
BRAND_HEX = '#5B9BD8'

# Inner region of the blue tile in the source (skips its bevelled edge and the
# white page around it).
INNER = (150, 240, 1118, 975)


def cut_out_artwork() -> Image.Image:
    src = Image.open(SRC).convert('RGB').crop(INNER)
    art = Image.new('RGBA', src.size)
    sp, ap = src.load(), art.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b = sp[x, y]
            blueness = b - r  # tile ≈ 120–145, white art ≈ 0–30, red art < 0
            a = max(0.0, min(1.0, (85 - blueness) / 45))
            ap[x, y] = (r, g, b, int(a * 255))
    # Drop specks of noise and anything touching the crop edge (the tile's
    # bevel), then trim to the artwork.
    alpha = art.getchannel('A').filter(ImageFilter.MedianFilter(3))
    margin = 12
    edge = Image.new('L', alpha.size, 0)
    edge.paste(255, (margin, margin, alpha.width - margin, alpha.height - margin))
    alpha = Image.composite(alpha, edge, edge)
    art.putalpha(alpha)
    return art.crop(alpha.point(lambda v: 255 if v > 40 else 0).getbbox())


def gradient(size: int) -> Image.Image:
    g = Image.new('RGB', (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y), tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    return g.resize((size, size))


def place(canvas: Image.Image, art: Image.Image, fraction: float) -> None:
    """Centers art so its longer side is `fraction` of the canvas."""
    scale = canvas.width * fraction / max(art.size)
    a = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    canvas.alpha_composite(a, ((canvas.width - a.width) // 2, (canvas.height - a.height) // 2))


def tile(size: int, art: Image.Image, radius: float = 0.225) -> Image.Image:
    """Rounded blue tile with the artwork: the classic icon / in-app logo."""
    big = size * 4
    mask = Image.new('L', (big, big))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=big * radius, fill=255)
    img = Image.new('RGBA', (big, big))
    img.paste(gradient(big), mask=mask)
    place(img, art, 0.74)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    art = cut_out_artwork()

    # Legacy launcher icons (pre-Android 8 and some launchers).
    for density, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        d = RES / f'mipmap-{density}'
        d.mkdir(parents=True, exist_ok=True)
        icon = tile(px, art)
        icon.save(d / 'ic_launcher.png')
        icon.save(d / 'ic_launcher_round.png')
        # Adaptive foreground: 108dp canvas, artwork within the 66dp safe zone.
        fg = Image.new('RGBA', (px * 108 // 48, px * 108 // 48))
        place(fg, art, 0.52)
        fg.save(d / 'ic_launcher_foreground.png')

    anydpi = RES / 'mipmap-anydpi-v26'
    anydpi.mkdir(exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@color/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '</adaptive-icon>\n')
    (anydpi / 'ic_launcher.xml').write_text(xml)
    (anydpi / 'ic_launcher_round.xml').write_text(xml)
    values = RES / 'values'
    values.mkdir(exist_ok=True)
    (values / 'ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{BRAND_HEX}</color>\n</resources>\n')

    # In-app and web logos.
    tile(512, art).save(ROOT / 'app/assets/brand/logo.png')
    web = ROOT / 'prototype/img'
    web.mkdir(exist_ok=True)
    tile(512, art).save(web / 'logo.png')
    tile(64, art).save(web / 'favicon.png')
    tile(180, art, radius=0).save(web / 'apple-touch-icon.png')
    print('icons written')


if __name__ == '__main__':
    main()
