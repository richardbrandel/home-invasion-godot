#!/usr/bin/env python3
"""Generate the game's surface textures procedurally.

`grep -c albedo_texture scripts/` used to find exactly ONE texture in the whole project
(wall_texture_clean.png); the floors, the ceiling, the lawn and the driveway were flat
albedo colours, which is the root of the synthetic look — and the lighting strategy
explicitly RELIED on darkness to hide flat materials until the scene went daylight.

There is no texture library to fetch here, so these are generated. The one thing that
matters technically is that they TILE: a floor is one large surface, so any visible seam
grid would be worse than the flat colour it replaces. Tileability comes from building the
variation out of integer-frequency sinusoids, which repeat exactly across the image, plus
a low-amplitude per-pixel grain whose seams are far below the noise floor.

    python3 tools/gen-textures.py
"""
import math
import pathlib
import random

from PIL import Image

OUT = pathlib.Path("assets/textures")
SIZE = 512


def tileable(x: int, y: int, w: int, h: int, octaves, rnd) -> float:
    """Sum of integer-frequency sinusoids: exactly tileable by construction."""
    v = 0.0
    amp = 1.0
    total = 0.0
    for (fx, fy) in octaves:
        phase_x = rnd.uniform(0, math.tau)
        phase_y = rnd.uniform(0, math.tau)
        v += amp * math.sin(math.tau * fx * x / w + phase_x) \
            * math.sin(math.tau * fy * y / h + phase_y)
        total += amp
        amp *= 0.5
    return 0.5 + 0.5 * (v / max(total, 1e-6))


def save(name: str, px, w: int = SIZE, h: int = SIZE) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGB", (w, h))
    img.putdata(px)
    p = OUT / f"{name}.png"
    img.save(p)
    print(f"  {name:<14} {w}x{h}  {p.stat().st_size // 1024} KB")


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def wood_floor() -> None:
    """Planks running across the image, so the seams tile horizontally."""
    rnd = random.Random(11)
    octaves = [(3, 9), (7, 21), (15, 44), (31, 91)]
    plank_h = 64
    px = []
    grain = [[tileable(x, y, SIZE, SIZE, octaves, rnd) for x in range(SIZE)]
             for y in range(SIZE)]
    for y in range(SIZE):
        band = y // plank_h
        # each plank a slightly different tone, chosen so the pattern wraps
        tone = 0.5 + 0.5 * math.sin(band * 2.1)
        seam = (y % plank_h) < 2          # the dark line between planks
        for x in range(SIZE):
            base = mix((96, 62, 34), (134, 92, 52), tone)
            g = grain[y][x]
            c = mix(base, (58, 36, 18), g * 0.55)
            if seam:
                c = mix(c, (32, 20, 10), 0.75)
            # fine per-pixel speckle, low enough not to show as a seam
            n = rnd.randint(-6, 6)
            px.append(tuple(max(0, min(255, v + n)) for v in c))
    save("floor_wood", px)


def lawn() -> None:
    rnd = random.Random(23)
    octaves = [(4, 4), (11, 11), (29, 29), (61, 61)]
    field = [[tileable(x, y, SIZE, SIZE, octaves, rnd) for x in range(SIZE)]
             for y in range(SIZE)]
    px = []
    for y in range(SIZE):
        for x in range(SIZE):
            t = field[y][x]
            c = mix((48, 78, 34), (88, 124, 52), t)
            # blades: a fast horizontal shimmer
            blade = 0.5 + 0.5 * math.sin(math.tau * 97 * x / SIZE + t * 6.0)
            c = mix(c, (104, 138, 60), blade * 0.16)
            n = rnd.randint(-8, 8)
            px.append(tuple(max(0, min(255, v + n)) for v in c))
    save("lawn", px)


def driveway() -> None:
    rnd = random.Random(37)
    octaves = [(3, 3), (8, 8), (17, 17), (37, 37)]
    field = [[tileable(x, y, SIZE, SIZE, octaves, rnd) for x in range(SIZE)]
             for y in range(SIZE)]
    px = []
    for y in range(SIZE):
        for x in range(SIZE):
            t = field[y][x]
            c = mix((62, 62, 64), (96, 96, 99), t)
            n = rnd.randint(-14, 14)
            # a scatter of light aggregate so it is not just noise
            if rnd.random() < 0.02:
                n += rnd.randint(18, 40)
            px.append(tuple(max(0, min(255, v + n)) for v in c))
    save("driveway", px)


def plaster() -> None:
    """Ceiling. Very subtle — it should read as a surface, not a pattern."""
    rnd = random.Random(41)
    octaves = [(2, 2), (5, 5), (13, 13)]
    field = [[tileable(x, y, SIZE, SIZE, octaves, rnd) for x in range(SIZE)]
             for y in range(SIZE)]
    px = []
    for y in range(SIZE):
        for x in range(SIZE):
            t = field[y][x]
            c = mix((203, 198, 190), (226, 222, 214), t)
            n = rnd.randint(-4, 4)
            px.append(tuple(max(0, min(255, v + n)) for v in c))
    save("ceiling_plaster", px)


def shingles() -> None:
    """Roof. Courses of overlapping tiles, offset row to row."""
    rnd = random.Random(53)
    W = 64
    H = 32
    px = []
    for y in range(SIZE):
        row = y // H
        off = (W // 2) if row % 2 else 0
        for x in range(SIZE):
            tone = 0.5 + 0.5 * math.sin((x + off) // W * 1.7 + row * 2.3)
            c = mix((58, 52, 50), (92, 84, 80), tone)
            if (y % H) < 3:                      # the lap between courses
                c = mix(c, (30, 27, 26), 0.6)
            if ((x + off) % W) < 2:
                c = mix(c, (34, 30, 29), 0.5)
            n = rnd.randint(-7, 7)
            px.append(tuple(max(0, min(255, v + n)) for v in c))
    save("roof_shingle", px)


def main() -> None:
    print("writing assets/textures/")
    wood_floor()
    lawn()
    driveway()
    plaster()
    shingles()
    print("all tileable by construction — integer-frequency sinusoids plus fine grain")


if __name__ == "__main__":
    main()
