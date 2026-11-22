#!/usr/bin/env python3
"""Generates procedural placeholder textures and sprites for Black Temple.

Usage: python3 tools/gen_textures.py [output_assets_dir]
All outputs are plain PNGs and can be replaced by hand-made art at any time.
"""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "Assets")
TEX = os.path.join(OUT, "Textures"); SPR = os.path.join(OUT, "Sprites")
os.makedirs(TEX, exist_ok=True); os.makedirs(SPR, exist_ok=True)
S = 64

def noise_img(size, base, var, seed):
    rnd = random.Random(seed)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            n = rnd.uniform(-var, var)
            px[x, y] = tuple(max(0, min(255, int(c + n))) for c in base)
    return img

def clamp(v): return max(0, min(255, int(v)))

def shade(c, f): return tuple(clamp(v * f) for v in c)

def bricks(name, base, mortar, rows=4, cols=2, seed=1, var=18, band=None):
    rnd = random.Random(seed)
    img = noise_img(S, base, var, seed)
    d = ImageDraw.Draw(img)
    bh = S // rows
    for r in range(rows):
        off = (S // cols // 2) * (r % 2)
        y0 = r * bh
        for c in range(-1, cols + 1):
            x0 = c * (S // cols) + off
            f = rnd.uniform(0.8, 1.15)
            px = img.load()
            for y in range(y0 + 1, y0 + bh - 1):
                for x in range(max(0, x0 + 1), min(S, x0 + S // cols - 1)):
                    px[x, y] = shade(px[x, y], f)
            d.line([(x0, y0), (x0, y0 + bh)], fill=mortar)
            # highlight / shadow edges
            d.line([(max(0, x0 + 1), y0 + 1), (min(S - 1, x0 + S // cols - 2), y0 + 1)], fill=shade(base, 1.35))
        d.line([(0, y0), (S, y0)], fill=mortar)
        d.line([(0, y0 + bh - 1), (S, y0 + bh - 1)], fill=shade(mortar, 0.7))
    if band:
        y = S // 2 - 4
        d.rectangle([0, y, S, y + 8], fill=band)
        for x in range(0, S, 8):
            d.polygon([(x, y + 4), (x + 4, y + 1), (x + 8, y + 4), (x + 4, y + 7)], fill=shade(band, 1.5))
    img.save(os.path.join(TEX, name + ".png"))

def tiles(name, base, line, n=2, seed=2, var=12):
    rnd = random.Random(seed)
    img = noise_img(S, base, var, seed)
    d = ImageDraw.Draw(img)
    t = S // n
    px = img.load()
    for ty in range(n):
        for tx in range(n):
            f = rnd.uniform(0.85, 1.1)
            for y in range(ty * t, ty * t + t):
                for x in range(tx * t, tx * t + t):
                    px[x, y] = shade(px[x, y], f)
    for i in range(n + 1):
        d.line([(i * t, 0), (i * t, S)], fill=line)
        d.line([(0, i * t), (S, i * t)], fill=line)
    # cracks
    for _ in range(3):
        x, y = rnd.randrange(S), rnd.randrange(S)
        for _ in range(10):
            nx, ny = x + rnd.randint(-3, 3), y + rnd.randint(-3, 3)
            d.line([(x, y), (nx, ny)], fill=shade(base, 0.6))
            x, y = nx, ny
    img.save(os.path.join(TEX, name + ".png"))

def grass(name, seed=3):
    rnd = random.Random(seed)
    img = noise_img(S, (58, 96, 40), 14, seed)
    d = ImageDraw.Draw(img)
    for _ in range(260):
        x, y = rnd.randrange(S), rnd.randrange(S)
        c = rnd.choice([(80, 130, 50), (40, 72, 30), (96, 140, 60)])
        d.line([(x, y), (x + rnd.randint(-1, 1), y - rnd.randint(1, 3))], fill=c)
    img.save(os.path.join(TEX, name + ".png"))

def door(name):
    img = noise_img(S, (96, 62, 34), 10, 7)
    d = ImageDraw.Draw(img)
    for x in range(0, S, 8):
        d.line([(x, 0), (x, S)], fill=(60, 36, 18))
    for y in (10, S - 12):
        d.rectangle([0, y, S, y + 4], fill=(70, 70, 76))
        for x in range(4, S, 12):
            d.point((x, y + 2), fill=(150, 150, 160))
    d.ellipse([S - 16, S // 2 - 3, S - 10, S // 2 + 3], fill=(170, 150, 60))
    d.rectangle([0, 0, S - 1, S - 1], outline=(50, 50, 56), width=2)
    img.save(os.path.join(TEX, name + ".png"))

# ---------------- sprites (RGBA) ----------------
def torch_frames():
    W, H = 32, 64
    for i in range(4):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        # stick
        d.rectangle([14, 26, 17, 63], fill=(92, 58, 28, 255))
        d.rectangle([14, 26, 14, 63], fill=(120, 80, 40, 255))
        d.rectangle([12, 24, 19, 28], fill=(60, 60, 64, 255))
        # flame
        rnd = random.Random(100 + i)
        sway = [0, 1, -1, 1][i]
        h = [16, 19, 15, 18][i]
        for layer, (col, w) in enumerate([((200, 50, 10), 7), ((250, 140, 20), 5), ((255, 230, 120), 3)]):
            top = 24 - h + layer * 3
            pts = [(16 - w, 24), (16 + sway - w // 2, (24 + top) // 2), (16 + sway * 2, top),
                   (16 + sway + w // 2 + 1, (24 + top) // 2), (16 + w, 24)]
            d.polygon(pts, fill=col + (255,))
        for _ in range(2):
            d.point((16 + rnd.randint(-4, 4), 24 - h - rnd.randint(1, 4)), fill=(255, 200, 80, 255))
        img.save(os.path.join(SPR, f"torch_{i}.png"))

def brazier_frames():
    W, H = 48, 48
    for i in range(4):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.polygon([(8, 26), (40, 26), (34, 36), (14, 36)], fill=(80, 80, 88, 255))
        d.line([(8, 26), (40, 26)], fill=(140, 140, 150, 255), width=2)
        d.rectangle([22, 36, 26, 46], fill=(60, 60, 66, 255))
        d.rectangle([14, 45, 34, 47], fill=(60, 60, 66, 255))
        rnd = random.Random(200 + i)
        for col, w, hh in [((210, 60, 10), 14, 18), ((250, 150, 30), 10, 13), ((255, 235, 140), 5, 8)]:
            for _ in range(3):
                cx = 24 + rnd.randint(-w // 2, w // 2)
                top = 26 - hh - rnd.randint(-2, 3)
                d.polygon([(cx - 4, 26), (cx, top), (cx + 4, 26)], fill=col + (255,))
        img.save(os.path.join(SPR, f"brazier_{i}.png"))

def pillar():
    W, H = 32, 96
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(9)
    for y in range(H):
        for x in range(4, W - 4):
            t = (x - 4) / (W - 9)
            f = 0.55 + 0.6 * math.sin(t * math.pi)
            c = shade((150, 140, 125), f * rnd.uniform(0.92, 1.05))
            if (x - 4) % 6 == 0: c = shade(c, 0.8)
            px[x, y] = c + (255,)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, 7], fill=(160, 150, 135, 255))
    d.rectangle([0, H - 8, W - 1, H - 1], fill=(130, 120, 108, 255))
    d.line([(0, 7), (W, 7)], fill=(90, 84, 76, 255))
    img.save(os.path.join(SPR, "pillar.png"))

def statue():
    W, H = 48, 80
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    stone = (110, 112, 120, 255); dark = (70, 72, 80, 255)
    d.rectangle([8, 64, 40, 79], fill=dark)
    d.rectangle([10, 62, 38, 66], fill=stone)
    d.polygon([(16, 62), (32, 62), (30, 30), (18, 30)], fill=stone)      # body
    d.ellipse([18, 14, 30, 28], fill=stone)                              # head
    d.polygon([(18, 32), (8, 46), (12, 48), (20, 38)], fill=stone)        # arm
    d.polygon([(30, 32), (40, 20), (42, 22), (32, 40)], fill=stone)       # raised arm
    d.line([(41, 4), (41, 30)], fill=dark, width=2)                       # staff
    d.ellipse([38, 1, 44, 7], fill=(90, 160, 200, 255))
    d.line([(24, 30), (24, 62)], fill=dark)
    img.save(os.path.join(SPR, "statue.png"))

def bush():
    W, H = 48, 40
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(11)
    for _ in range(40):
        x, y, r = rnd.randint(8, 40), rnd.randint(10, 34), rnd.randint(4, 8)
        c = rnd.choice([(40, 90, 30), (55, 110, 40), (30, 70, 25)])
        d.ellipse([x - r, y - r, x + r, min(H - 1, y + r)], fill=c + (255,))
    img.save(os.path.join(SPR, "bush.png"))

def crystal_frames():
    W, H = 32, 48
    for i in range(4):
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        g = [0.8, 1.0, 1.15, 1.0][i]
        d.rectangle([10, 40, 22, 47], fill=(70, 70, 80, 255))
        d.polygon([(16, 4), (24, 20), (16, 40), (8, 20)], fill=shade((60, 140, 220), g) + (255,))
        d.polygon([(16, 4), (24, 20), (16, 24)], fill=shade((140, 210, 255), g) + (255,))
        img.save(os.path.join(SPR, f"crystal_{i}.png"))

bricks("stone_wall", (88, 88, 96), (40, 40, 46), seed=1)
bricks("temple_wall", (120, 100, 78), (60, 48, 36), rows=4, cols=2, seed=4, band=(110, 40, 30))
bricks("dark_wall", (58, 54, 66), (26, 24, 30), rows=8, cols=4, seed=5, var=10)
bricks("outer_wall", (130, 122, 108), (70, 64, 56), rows=4, cols=2, seed=6)
tiles("stone_floor", (78, 76, 80), (40, 40, 44), n=2, seed=2)
tiles("temple_floor", (104, 64, 50), (50, 30, 24), n=4, seed=8)
tiles("stone_ceiling", (54, 52, 58), (32, 30, 36), n=1, seed=12, var=8)
tiles("cobble", (110, 104, 92), (70, 66, 58), n=4, seed=13, var=16)
grass("grass")
door("door")
torch_frames(); brazier_frames(); pillar(); statue(); bush(); crystal_frames()
print("Textures written to", os.path.abspath(OUT))
