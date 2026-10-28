"""Build the Jeb logo (standard library only).

  python logo.py PIXEL_ART_TS OUT_DIR [ICON_PNG]

reads the runtime sprite data the mod uses (hooks/pixel-art.ts): Jeb playing the
banjo with Blue at his side, and a pixel wordmark beside them. Writes
OUT_DIR/logo.svg (animated, crisp at any size) and OUT_DIR/logo.png (first
frame, 8x). With ICON_PNG, also writes the plugin icon there: the pair alone,
first frame, square with a small margin, 12x (528 px).
"""

from __future__ import annotations

import base64
import json
import re
import struct
import sys
import zlib
from pathlib import Path
from typing import List, Optional, Tuple

Color = Tuple[int, int, int]
Grid = List[List[Optional[Color]]]

# (sprite, x, ms per frame); both stand on the bottom row.
CAST = [('blue-wag', 0, 250), ('jeb-banjo', 20, 260)]
PNG_SCALE = 8
FILL = (0xE0, 0x9A, 0x34)
SHADOW = (0x5C, 0x38, 0x1C)

# 5x7 letters for the wordmark, drawn 3x.
LETTERS = {
    'J': ['00111', '00010', '00010', '00010', '10010', '10010', '01100'],
    'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
    'B': ['11110', '10001', '10001', '11110', '10001', '10001', '11110'],
}
LETTER_SCALE = 3
GAP = 6
ICON_PAD = 2
ICON_SCALE = 12


def load_frames(ts: str, name: str) -> list[Grid]:
    palette = json.loads(re.search(r'PIXEL_PALETTE[^=]*=\s*(\[[^\]]*\])', ts).group(1))
    m = re.search(r"'%s':\s*\{\s*w:\s*(\d+),\s*h:\s*(\d+),\s*frames:\s*\[([^\]]*)\]" % re.escape(name), ts)
    w, h = int(m.group(1)), int(m.group(2))
    frames = []
    for data in re.findall(r"'([A-Za-z0-9+/=]*)'", m.group(3)):
        raw = base64.b64decode(data)
        flat: list[Color | None] = []
        for run, index in zip(raw[0::2], raw[1::2]):
            c = palette[index]
            flat += [None if index == 0 else ((c >> 16) & 255, (c >> 8) & 255, c & 255)] * run
        frames.append([flat[y * w:(y + 1) * w] for y in range(h)])
    return frames


def blank(w: int, h: int) -> Grid:
    return [[None] * w for _ in range(h)]


def paste(grid: Grid, sprite: Grid, x0: int, y0: int) -> None:
    for y, row in enumerate(sprite):
        for x, c in enumerate(row):
            if c:
                grid[y0 + y][x0 + x] = c


def compose(ts: str):
    """(width, height, wordmark grid, [(cast grids per frame, ms)])."""
    cast = [(load_frames(ts, name), x, ms) for name, x, ms in CAST]
    height = max(len(frames[0]) for frames, _, _ in cast)
    cast_w = max(x + len(frames[0][0]) for frames, x, _ in cast)
    word_w = len(LETTERS) * 5 * LETTER_SCALE + (len(LETTERS) - 1) * LETTER_SCALE
    word_h = 7 * LETTER_SCALE
    width = cast_w + GAP + word_w + 2
    word = blank(width, height)
    x0, y0 = cast_w + GAP, (height - word_h) // 2
    for d, color in ((2, SHADOW), (0, FILL)):
        for i, ch in enumerate('JEB'):
            lx = x0 + i * 6 * LETTER_SCALE
            for r, bits in enumerate(LETTERS[ch]):
                for c, bit in enumerate(bits):
                    if bit == '1':
                        for yy in range(LETTER_SCALE):
                            for xx in range(LETTER_SCALE):
                                word[y0 + d + r * LETTER_SCALE + yy][lx + d + c * LETTER_SCALE + xx] = color
    layers = []
    for frames, x, ms in cast:
        grids = []
        for f in frames:
            g = blank(width, height)
            paste(g, f, x, height - len(f))
            grids.append(g)
        layers.append((grids, ms))
    return width, height, word, layers


def rects(grid: Grid) -> list[str]:
    out = []
    for y, row in enumerate(grid):
        x = 0
        while x < len(row):
            c = row[x]
            if c is None:
                x += 1
                continue
            end = x
            while end < len(row) and row[end] == c:
                end += 1
            out.append(f'<rect x="{x}" y="{y}" width="{end - x}" height="1" fill="#{c[0]:02x}{c[1]:02x}{c[2]:02x}"/>')
            x = end
    return out


def svg(width: int, height: int, word: Grid, layers) -> str:
    # Each frame is a group shown for its share of the loop (step timing, so frames swap cleanly).
    style, groups = [], []
    for i, (grids, ms) in enumerate(layers):
        n = len(grids)
        for k, g in enumerate(grids):
            name = f's{i}f{k}'
            if n > 1:
                start, end = 100 * k / n, 100 * (k + 1) / n
                keys = [f'0%{{opacity:{1 if k == 0 else 0}}}']
                if k > 0:
                    keys.append(f'{start:g}%{{opacity:1}}')
                if end < 100:
                    keys.append(f'{end:g}%{{opacity:0}}')
                style.append(f'@keyframes {name}{{{"".join(keys)}}}'
                             f'.{name}{{{"" if k == 0 else "opacity:0;"}animation:{name} {ms * n}ms step-end infinite}}')
            groups.append(f'<g class="{name}">\n' + '\n'.join(rects(g)) + '\n</g>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width * PNG_SCALE}" '
            f'height="{height * PNG_SCALE}" shape-rendering="crispEdges">\n<title>Jeb</title>\n'
            f'<style>{"".join(style)}</style>\n' + '\n'.join(groups) + '\n' + '\n'.join(rects(word)) + '\n</svg>\n')


def png(grid: Grid, k: int) -> bytes:
    h, w = len(grid), len(grid[0])
    raw = bytearray()
    for row in grid:
        line = bytearray()
        for c in row:
            line += bytes((*c, 255)) * k if c else bytes(4) * k
        raw += (b'\0' + bytes(line)) * k

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    ihdr = struct.pack('>IIBBBBB', w * k, h * k, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')


def icon(ts: str) -> Grid:
    """The cast alone (first frame), centred on a square with ICON_PAD around it."""
    cast = [(load_frames(ts, name)[0], x) for name, x, _ in CAST]
    w = max(x + len(f[0]) for f, x in cast)
    h = max(len(f) for f, _ in cast)
    side = max(w, h) + 2 * ICON_PAD
    grid = blank(side, side)
    x0, y0 = (side - w) // 2, (side - h) // 2
    for f, x in cast:
        paste(grid, f, x0 + x, y0 + h - len(f))
    return grid


def main() -> None:
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    ts = Path(sys.argv[1]).read_text()
    width, height, word, layers = compose(ts)
    (out / 'logo.svg').write_text(svg(width, height, word, layers))
    still = blank(width, height)
    for grids, _ in layers:
        paste(still, grids[0], 0, 0)
    paste(still, word, 0, 0)
    (out / 'logo.png').write_bytes(png(still, PNG_SCALE))
    if len(sys.argv) > 3:
        Path(sys.argv[3]).write_bytes(png(icon(ts), ICON_SCALE))


if __name__ == '__main__':
    main()
