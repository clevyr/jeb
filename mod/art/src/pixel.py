"""Pixel-art primitives for Jeb's sprites: one shared palette, frame drawing,
outlines, and the exports (sheets, optimized GIFs, and run-length data the
mod composites at runtime).

Scale: one terminal cell is 4x8 sprite pixels, so pixels stay square in a
1:2 cell. A 6-row band is 48 pixels tall.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw

CELL_W, CELL_H = 4, 8

# One palette for every sprite (index 0 is transparent). Kept small so the
# runtime data is one byte per run and the GIFs stay tiny.
PALETTE: dict[str, tuple[int, int, int]] = {
    'ink': (43, 26, 14),
    'hat': (222, 172, 78),
    'hat_dark': (176, 125, 42),
    'hat_light': (240, 205, 120),
    'band': (122, 59, 29),
    'skin': (241, 194, 125),
    'skin_dark': (214, 158, 98),
    'cheek': (230, 140, 110),
    'beard': (139, 106, 74),
    'beard_dark': (104, 78, 52),
    'mouth': (110, 40, 28),
    'white': (255, 255, 255),
    'shirt': (192, 57, 43),
    'shirt_dark': (140, 36, 28),
    'denim': (63, 111, 181),
    'denim_dark': (44, 79, 134),
    'boot': (74, 46, 26),
    'glass': (205, 232, 240),
    'glass_edge': (107, 143, 160),
    'amber': (227, 155, 58),
    'amber_dark': (190, 110, 30),
    'chrome': (205, 210, 215),
    'steel': (130, 135, 145),
    'tire': (35, 35, 38),
    'truck': (54, 104, 168),
    'truck_dark': (34, 70, 120),
    'green': (95, 175, 80),
    'green_dark': (60, 120, 50),
    'leaf': (130, 190, 70),
    'leaf_dry': (196, 150, 70),
    'corn': (240, 200, 60),
    'red': (220, 50, 50),
    'red_dark': (150, 30, 30),
    'soil': (120, 80, 50),
    'soil_dark': (88, 56, 34),
    'soil_dry': (200, 170, 100),
    'grass': (110, 160, 70),
    'road': (150, 130, 100),
    'road_dark': (120, 100, 75),
    'wood': (160, 110, 60),
    'wood_dark': (115, 75, 40),
    'roof': (120, 60, 50),
    'roof_dark': (85, 40, 35),
    'stone': (150, 150, 150),
    'stone_dark': (105, 105, 110),
    'copper': (196, 110, 60),
    'copper_dark': (140, 70, 35),
    'fire': (250, 150, 40),
    'fire_hot': (255, 225, 90),
    'smoke': (200, 200, 205),
    'smoke_dark': (160, 160, 168),
    'window': (60, 70, 90),
    'window_lit': (250, 215, 110),
    'blue_coat': (110, 125, 150),
    'blue_spot': (60, 70, 95),
    'tan': (196, 140, 80),
    'nose': (30, 30, 35),
    'drop': (80, 150, 230),
    'cloud': (215, 222, 232),
    'night_star': (250, 245, 200),
    'moon': (245, 240, 210),
    'pink': (240, 150, 170),
    'purple': (150, 90, 190),
    'yellow': (240, 210, 60),
    'grey': (90, 90, 95),
    'fur': (95, 65, 45),
    'cow_white': (240, 238, 230),
    'cow_black': (40, 40, 45),
    'dress': (130, 90, 160),
    'hair_grey': (200, 200, 205),
    'black_car': (30, 32, 40),
    'banjo_head': (245, 238, 220),
    'banjo_rim': (150, 100, 50),
    # Appalachian backdrop: muted so the ridges sit behind the farm.
    'ridge_far': (74, 92, 104),
    'ridge_far_night': (38, 46, 60),
    'ridge_mid': (52, 82, 54),
    'ridge_mid_night': (28, 42, 32),
    'pine': (36, 64, 40),
    'foliage_orange': (200, 112, 44),
    'foliage_red': (160, 52, 38),
    'foliage_gold': (212, 168, 56),
    'snowcap': (232, 234, 240),
    'fog': (168, 176, 184),
    # Hired hands: a range of skin tones, hair and work clothes.
    'skin_tan': (214, 160, 112),
    'skin_brown': (168, 112, 74),
    'skin_deep': (112, 72, 46),
    'hair_dark': (42, 32, 26),
    'hair_brown': (102, 70, 42),
    'hair_blond': (214, 182, 104),
    'flannel_green': (62, 112, 72),
    'flannel_green_dark': (40, 80, 50),
    'tee_grey': (142, 146, 152),
    'tee_teal': (60, 140, 140),
    # Little things around the farm: creek water, a bluebird, deer and owl fur.
    'water': (86, 150, 205),
    'water_light': (160, 210, 240),
    'bluebird': (66, 120, 215),
    'deer_tan': (176, 122, 74),
    'deer_light': (226, 196, 150),
    'owl_brown': (120, 88, 62),
    'owl_cream': (225, 205, 170),
    # The dirt road: muted, so white text and the vehicles read on top of it.
    'dirt': (122, 98, 72),
    'dirt_dark': (100, 79, 57),
    'dirt_light': (138, 112, 83),
    'pebble': (146, 140, 132),
}
NAMES = ['clear'] + list(PALETTE)
INDEX = {name: i for i, name in enumerate(NAMES)}
assert len(NAMES) <= 127, 'palette must fit in 7 bits'


def rgb(name: str) -> tuple[int, int, int, int]:
    return (*PALETTE[name], 255)


@dataclass
class Sprite:
    """A named sprite: one or more frames of the same size, plus per-frame
    durations for previews (the mod times its own frames)."""

    name: str
    frames: list[Image.Image]
    ms: list[int] = field(default_factory=list)
    # Where the sprite stands: offset of its "feet" from the bottom-left, used
    # by the scene composer. Most sprites stand on their bottom row.
    anchor: tuple[int, int] = (0, 0)

    @property
    def size(self) -> tuple[int, int]:
        return self.frames[0].size


def blank(w: int, h: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def outline(image: Image.Image, color: str = 'ink') -> Image.Image:
    """1px outline around every opaque pixel, inside the sprite's box."""
    src = image.copy()
    px, out = src.load(), image.load()
    w, h = image.size
    ink = rgb(color)
    for y in range(h):
        for x in range(w):
            if px[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 128:
                    out[x, y] = ink
                    break
    return image


def quantize(image: Image.Image) -> list[int]:
    """Map every pixel to its palette index (nearest colour), 0 for clear."""
    px = image.load()
    w, h = image.size
    colours = [(i, PALETTE[n]) for i, n in enumerate(NAMES) if i]
    cache: dict[tuple[int, int, int], int] = {}
    out = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                out.append(0)
                continue
            key = (r, g, b)
            if key not in cache:
                cache[key] = min(colours, key=lambda c: sum((p - q) ** 2 for p, q in zip(c[1], key)))[0]
            out.append(cache[key])
    return out


def rle(indices: list[int]) -> bytes:
    """Run-length pairs: (run length 1..255, palette index)."""
    out = bytearray()
    i = 0
    while i < len(indices):
        value, run = indices[i], 1
        while i + run < len(indices) and indices[i + run] == value and run < 255:
            run += 1
        out += bytes((run, value))
        i += run
    return bytes(out)


def save_sheet(sprite: Sprite, folder: Path, scale: int = 4) -> Path:
    """All frames side by side, scaled for viewing."""
    w, h = sprite.size
    sheet = Image.new('RGBA', (w * len(sprite.frames), h), (0, 0, 0, 0))
    for i, frame in enumerate(sprite.frames):
        sheet.alpha_composite(frame, (i * w, 0))
    path = folder / f'{sprite.name}.png'
    sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST).save(path, optimize=True)
    return path


def save_gif(sprite: Sprite, folder: Path, scale: int = 4) -> Path | None:
    """Optimized animated preview: indexed palette, 1-bit transparency,
    identical consecutive frames merged, dispose to background."""
    if len(sprite.frames) < 2:
        return None
    w, h = sprite.size
    frames, durations = [], []
    previous = None
    for frame, ms in zip(sprite.frames, sprite.ms or [200] * len(sprite.frames)):
        data = frame.tobytes()
        if data == previous:
            durations[-1] += ms
            continue
        previous = data
        big = frame.resize((w * scale, h * scale), Image.NEAREST)
        alpha = big.split()[3]
        p = big.convert('RGB').quantize(colors=63, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        p.paste(63, Image.eval(alpha, lambda a: 255 if a < 128 else 0))
        frames.append(p)
        durations.append(ms)
    path = folder / f'{sprite.name}.gif'
    frames[0].save(
        path, save_all=True, append_images=frames[1:], duration=durations,
        loop=0, transparency=63, disposal=2, optimize=True,
    )
    return path


def encode(sprite: Sprite) -> dict:
    """Runtime form for the mod: size and RLE base64 per frame."""
    w, h = sprite.size
    return {
        'w': w,
        'h': h,
        'frames': [base64.b64encode(rle(quantize(f))).decode() for f in sprite.frames],
    }
