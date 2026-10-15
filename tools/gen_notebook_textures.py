"""Textures of the paper notebook (E06-T06, mock-up docs/maquettes/carnet-papier.dc.html), generated, no external image.

    python RadioSurvivor/tools/gen_notebook_textures.py                 # writes the PNG files of the mod
    python RadioSurvivor/tools/gen_notebook_textures.py --preview OUT.png   # plus an offline composed preview

Files (media/textures/RadioSurvivor/, prefixed names: getTexture looks a base name up in the vanilla packs first,
base ui-windows.md), sizes in powers of two:
  RS_Notebook_Paper.png   256x256 cream paper, seamless (tiled by drawTextureTiled)
  RS_Notebook_Binding.png  32x256 brown leather strip, seamless vertically (tiled)
  RS_Notebook_Ring.png     32x32  metal ring through a punched hole (alpha)
  RS_Notebook_Tab.png      64x32  white bookmark, rounded on the left (tinted by the draw colour)
  RS_Notebook_Dot.png      16x16  white disc (tinted: unread indicator)
Deterministic (fixed seed): running it twice gives identical files. Requires Pillow.
"""
from __future__ import annotations

import argparse
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'textures' / 'RadioSurvivor'

PAPER = (0xef, 0xe6, 0xcf)
BINDING = (0x6b, 0x4a, 0x2b)


def seamless_noise(size: tuple[int, int], seed: int, amplitude: int, blur: float) -> Image.Image:
    """Grey noise centred on 128, blurred on a 3x3 tiling then cropped: the edges match (seamless tile)."""
    w, h = size
    rng = random.Random(seed)
    tile = Image.new('L', size)
    tile.putdata([128 + rng.randint(-amplitude, amplitude) for _ in range(w * h)])
    big = Image.new('L', (w * 3, h * 3))
    for i in range(3):
        for j in range(3):
            big.paste(tile, (i * w, j * h))
    big = big.filter(ImageFilter.GaussianBlur(blur))
    return big.crop((w, h, w * 2, h * 2))


def tint(noise: Image.Image, base: tuple[int, int, int], strength: float) -> Image.Image:
    out = Image.new('RGB', noise.size)
    src = noise.load()
    dst = out.load()
    for y in range(noise.size[1]):
        for x in range(noise.size[0]):
            d = (src[x, y] - 128) * strength
            dst[x, y] = tuple(max(0, min(255, int(round(c + d)))) for c in base)
    return out


def paper() -> Image.Image:
    fine = seamless_noise((256, 256), 11, 60, 0.6)
    coarse = seamless_noise((256, 256), 12, 90, 6.0)
    mixed = Image.blend(fine, coarse, 0.5)
    return tint(mixed, PAPER, 0.18)


def binding() -> Image.Image:
    # Grain stretched vertically (leather), seamless on y; darker edges for the fold.
    noise = seamless_noise((32, 256), 21, 80, 1.2)
    img = tint(noise, BINDING, 0.25)
    px = img.load()
    for y in range(256):
        for x in range(32):
            edge = min(x, 31 - x)
            k = 0.72 + 0.28 * min(1.0, edge / 8.0)
            px[x, y] = tuple(int(c * k) for c in px[x, y])
    return img


def ring() -> Image.Image:
    scale = 4  # drawn large then reduced: smooth edges
    s = 32 * scale
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # punched hole, dark
    d.ellipse((7 * scale, 7 * scale, 25 * scale, 25 * scale), fill=(0x2b, 0x2a, 0x26, 255))
    # metal ring, partly over the hole (light from the top left)
    d.ellipse((3 * scale, 9 * scale, 29 * scale, 23 * scale), outline=(0x8a, 0x8c, 0x8e, 255), width=3 * scale)
    d.arc((3 * scale, 9 * scale, 29 * scale, 23 * scale), 180, 300, fill=(0xd8, 0xda, 0xdc, 255), width=1 * scale)
    return img.resize((32, 32), Image.LANCZOS)


def tab() -> Image.Image:
    scale = 4
    w, h = 64 * scale, 32 * scale
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = 6 * scale
    d.rounded_rectangle((0, 0, w + r, h - 1), radius=r, fill=(255, 255, 255, 255))
    img = img.resize((64, 32), Image.LANCZOS)
    # light shading from top to bottom (multiplied by the tint colour in game)
    px = img.load()
    for y in range(32):
        k = 1.0 - 0.12 * (y / 31.0)
        for x in range(64):
            r_, g_, b_, a_ = px[x, y]
            px[x, y] = (int(r_ * k), int(g_ * k), int(b_ * k), a_)
    return img


def dot() -> Image.Image:
    scale = 8
    img = Image.new('RGBA', (16 * scale, 16 * scale), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((scale, scale, 15 * scale, 15 * scale), fill=(255, 255, 255, 255))
    return img.resize((16, 16), Image.LANCZOS)


TEXTURES = {
    'RS_Notebook_Paper.png': paper,
    'RS_Notebook_Binding.png': binding,
    'RS_Notebook_Ring.png': ring,
    'RS_Notebook_Tab.png': tab,
    'RS_Notebook_Dot.png': dot,
}


def colorize(img: Image.Image, color: tuple[int, int, int]) -> Image.Image:
    """Multiply a white RGBA texture by a colour, as drawTextureScaled(tex, ..., a, r, g, b) does."""
    r, g, b, a = img.split()
    r = r.point(lambda v: v * color[0] // 255)
    g = g.point(lambda v: v * color[1] // 255)
    b = b.point(lambda v: v * color[2] // 255)
    return Image.merge('RGBA', (r, g, b, a))


def preview(images: dict[str, Image.Image], path: Path) -> None:
    """Offline composition of the Radio tab (layout of RS_Notebook.lua at 1x, fonts are NOT the game fonts)."""
    W, H, TH = 880, 560, 20
    tab_w = 96
    img = Image.new('RGBA', (W, H), (0x20, 0x1f, 0x1c, 255))
    d = ImageDraw.Draw(img)
    try:
        font_s = ImageFont.truetype('arial.ttf', 13)
        font_m = ImageFont.truetype('arial.ttf', 17)
        font_l = ImageFont.truetype('arialbd.ttf', 24)
    except OSError:
        font_s = font_m = font_l = ImageFont.load_default()
    paper_right = W - tab_w
    d.rectangle((0, 0, W, TH), fill=(0x2b, 0x2a, 0x26, 255))
    d.text((W // 2 - 30, 3), 'Carnet', fill=PAPER, font=font_s)
    tile = images['RS_Notebook_Paper.png']
    for y in range(TH, H, 256):
        for x in range(0, paper_right, 256):
            img.paste(tile.crop((0, 0, min(256, paper_right - x), min(256, H - y))), (x, y))
    strip = images['RS_Notebook_Binding.png']
    for y in range(TH, H, 256):
        img.paste(strip.crop((0, 0, 26, min(256, H - y))), (0, y))
    ring_img = images['RS_Notebook_Ring.png']
    for i in range(6):
        y = TH + 30 + i * ((H - TH - 60) // 5)
        img.alpha_composite(ring_img.resize((20, 20)), (3, y - 10))
    col_x, col_w = 40, 190
    sep = col_x + col_w + 10
    for y in range(TH + 14, H - 12, 9):
        d.line((sep, y, sep, y + 4), fill=(0xc9, 0xb8, 0x8f), width=2)
    right_x = sep + 14
    for y in range(TH + 60, H - 70, 26):
        d.line((right_x, y, paper_right - 16, y), fill=(0xc8, 0xd3, 0xde))
    d.text((col_x, TH + 16), 'FRÉQUENCES ENTENDUES', fill=(0x6b, 0x5a, 0x3a), font=font_s)
    rows = [('140.8 MHz', 'Dernier : 07/07 14:20', True, False), ('118.4 MHz', 'Dernier : 07/07 09:05', False, True),
            ('90.0 MHz', 'Dernier : 07/06 20:12', False, False)]
    y = TH + 40
    for label, last, selected, unread in rows:
        if selected:
            d.rectangle((col_x, y, col_x + col_w, y + 46), fill=(0xf8, 0xf1, 0xdc), outline=(0xb8, 0x9d, 0x62))
        d.text((col_x + 8, y + 4), label, fill=(0x1e, 0x3a, 0x5f) if selected else (0x3b, 0x34, 0x27), font=font_m)
        if unread:
            dot_img = colorize(images['RS_Notebook_Dot.png'], (0xb5, 0x53, 0x1c)).resize((9, 9))
            img.alpha_composite(dot_img, (col_x + 8 + int(d.textlength(label, font=font_m)) + 6, y + 10))
        d.text((col_x + 8, y + 26), last, fill=(0x6b, 0x5a, 0x3a), font=font_s)
        y += 50
    d.rectangle((col_x, y + 6, col_x + 120, y + 36), outline=(0x7a, 0x3b, 0x12), width=2)
    d.text((col_x + 10, y + 13), 'Régler ma radio', fill=(0x7a, 0x3b, 0x12), font=font_s)
    d.text((right_x, TH + 16), '140.8 MHz', fill=(0x1e, 0x3a, 0x5f), font=font_l)
    lines = [((0x6b, 0x64, 0x57), "07/07 14:02 entendu — Il y a quelqu'un ? Ici Walt, j'écoute."),
             ((0x1e, 0x3a, 0x5f), '07/07 14:18 moi — Walt, tu m\'entends ? On est trois.'),
             ((0x2b, 0x2a, 0x26), '07/07 14:20 Réponse — Je t\'entends, petit. Restez à l\'intérieur.')]
    y = TH + 60
    for color, text in lines:
        d.text((right_x, y), text, fill=color, font=font_m)
        y += 26
    base = H - 50
    d.text((right_x, base + 8), 'Dire :', fill=(0x6b, 0x5a, 0x3a), font=font_s)
    d.line((right_x + 44, base + 28, paper_right - 130, base + 28), fill=(0x7a, 0x3b, 0x12), width=2)
    d.text((right_x + 50, base + 6), 'Parler sur 140.8 MHz', fill=(0x9a, 0x90, 0x7a), font=font_m)
    d.rectangle((paper_right - 116, base, paper_right - 16, base + 32), fill=(0x7a, 0x3b, 0x12))
    d.text((paper_right - 98, base + 8), 'Émettre', fill=PAPER, font=font_s)
    tab_img = images['RS_Notebook_Tab.png']
    tabs = [('Radio', (0xb5, 0x53, 0x1c)), ('Contacts', (0x7f, 0x6f, 0x45)), ('Missions', (0x5e, 0x7a, 0x4f)),
            ('Réputation', (0x4f, 0x5e, 0x7a))]
    y = TH + 30
    for i, (name, color) in enumerate(tabs):
        active = i == 0
        x = paper_right - (14 if active else 6)
        t = colorize(tab_img, color).resize((W - x, 30))
        img.alpha_composite(t, (x, y))
        d.text((x + 12, y + 8), name, fill=PAPER, font=font_s)
        y += 36
    img.convert('RGB').save(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--out', type=Path, default=OUT, help='destination folder (default: the mod)')
    parser.add_argument('--preview', type=Path, help='also write a composed preview PNG here')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    images = {}
    for name, make in TEXTURES.items():
        image = make()
        image.save(args.out / name, optimize=True)
        images[name] = image.convert('RGBA')
        print(f'{name}: {image.size[0]}x{image.size[1]}')
    if args.preview:
        preview(images, args.preview)
        print(f'preview: {args.preview}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
