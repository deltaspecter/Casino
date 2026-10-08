#!/usr/bin/env python3
"""Erzeugt die App-Symbole der Web-App (Home-Bildschirm) als PNG – roter Casino-Chip mit „BC“."""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "web", "public", "icons")
RED = (220, 18, 41)
RED_DEEP = (107, 5, 18)
GOLD = (212, 173, 102)
GOLD_LIGHT = (247, 222, 158)
BG = (9, 9, 12)


def font(size):
    for name in ["DejaVuSerif-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
                 "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf"]:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_icon(size, maskable=False):
    s = size * 4  # Supersampling
    img = Image.new("RGB", (s, s), BG)
    d = ImageDraw.Draw(img)
    # Dezenter roter Schein im Hintergrund
    glow = Image.new("RGB", (s, s), BG)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([s * 0.1, s * 0.05, s * 0.9, s * 0.85], fill=(70, 4, 14))
    glow = glow.filter(ImageFilter.GaussianBlur(s * 0.12))
    img.paste(glow)
    d = ImageDraw.Draw(img)

    scale = 0.62 if maskable else 0.80
    r = s * scale / 2
    cx = cy = s / 2
    # Schatten
    shadow = Image.new("L", (s, s), 0)
    ImageDraw.Draw(shadow).ellipse([cx - r, cy - r + s * 0.03, cx + r, cy + r + s * 0.03], fill=170)
    shadow = shadow.filter(ImageFilter.GaussianBlur(s * 0.025))
    img.paste((0, 0, 0), mask=shadow)
    d = ImageDraw.Draw(img)
    # Chip-Körper
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=RED)
    # Randeinlagen
    for i in range(8):
        a0 = i * 45 - 9
        d.pieslice([cx - r, cy - r, cx + r, cy + r], a0, a0 + 18, fill=(245, 240, 232))
    ri = r * 0.80
    d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], fill=RED)
    # Innenring gold
    rg = r * 0.66
    d.ellipse([cx - rg, cy - rg, cx + rg, cy + rg], fill=GOLD)
    rc = r * 0.61
    d.ellipse([cx - rc, cy - rc, cx + rc, cy + rc], fill=RED_DEEP)
    # Dezente Lichtkante oben
    hl = Image.new("L", (s, s), 0)
    ImageDraw.Draw(hl).ellipse([cx - r * 0.95, cy - r * 0.98, cx + r * 0.95, cy + r * 0.2], fill=40)
    hl = hl.filter(ImageFilter.GaussianBlur(s * 0.03))
    img.paste((255, 255, 255), mask=hl)
    d = ImageDraw.Draw(img)
    # „BC“
    f = font(int(rc * 0.95))
    text = "BC"
    box = d.textbbox((0, 0), text, font=f)
    tw, th = box[2] - box[0], box[3] - box[1]
    d.text((cx - tw / 2 - box[0], cy - th / 2 - box[1]), text, font=f, fill=GOLD_LIGHT)
    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for size in (180, 192, 512):
        draw_icon(size).save(os.path.join(OUT, f"icon-{size}.png"), optimize=True)
    draw_icon(512, maskable=True).save(os.path.join(OUT, "icon-maskable-512.png"), optimize=True)
    draw_icon(64).save(os.path.join(OUT, "favicon-64.png"), optimize=True)


if __name__ == "__main__":
    main()
