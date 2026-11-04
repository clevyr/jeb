"""Jeb, Blue, the hired hands and the visitors, as full-body pixel sprites at
band scale (feet on the sprite's bottom row)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from PIL import Image, ImageDraw

from pixel import Sprite, blank, outline, rgb

JEB_W, JEB_H = 20, 40
HEADROOM = 8  # rows a holiday variant may add above the base
BODY_H, BODY_DY = 36, 4  # the body layer, drawn as before and set 4 px lower


# ------------------------------------------------------------------ Jeb ----

def _jeb_base(d: ImageDraw.ImageDraw, arms: bool = True) -> None:
    c = rgb
    # boots and legs
    d.rectangle([5, 32, 9, 34], fill=c('boot'))
    d.rectangle([10, 32, 14, 34], fill=c('boot'))
    d.rectangle([6, 25, 9, 31], fill=c('denim'))
    d.rectangle([10, 25, 13, 31], fill=c('denim'))
    d.line([9, 26, 9, 31], fill=c('denim_dark'))
    # shirt and overall bib
    d.rectangle([5, 16, 14, 24], fill=c('shirt'))
    for x in (6, 9, 13):
        d.line([x, 16, x, 24], fill=c('shirt_dark'))
    d.rectangle([7, 18, 12, 24], fill=c('denim'))
    d.line([7, 16, 7, 18], fill=c('denim'))
    d.line([12, 16, 12, 18], fill=c('denim'))
    d.point([(7, 18), (12, 18)], fill=c('chrome'))
    d.line([7, 24, 12, 24], fill=c('denim_dark'))
    if arms:
        d.rectangle([3, 17, 4, 23], fill=c('shirt'))
        d.rectangle([15, 17, 16, 23], fill=c('shirt'))
        d.rectangle([3, 24, 4, 25], fill=c('skin'))
        d.rectangle([15, 24, 16, 25], fill=c('skin'))


def _jeb_head(d: ImageDraw.ImageDraw, eyes: str, mouth: str) -> None:
    c = rgb
    d.rectangle([6, 8, 13, 13], fill=c('skin'))
    d.point([(5, 9), (5, 10), (14, 9), (14, 10)], fill=c('skin_dark'))  # ears
    d.line([6, 8, 13, 8], fill=c('skin_dark'))  # brim shadow
    d.rectangle([9, 11, 10, 11], fill=c('skin_dark'))  # nose
    # beard
    d.rectangle([6, 12, 13, 15], fill=c('beard'))
    d.line([7, 16, 12, 16], fill=c('beard'))
    d.point([(7, 14), (11, 15), (9, 16)], fill=c('beard_dark'))
    d.point([(6, 11), (13, 11)], fill=c('cheek'))
    # eyes (row 9-10)
    if eyes == 'open':
        d.line([8, 9, 8, 10], fill=c('ink'))
        d.line([11, 9, 11, 10], fill=c('ink'))
    elif eyes == 'shut':
        d.point([(7, 10), (8, 10), (11, 10), (12, 10)], fill=c('ink'))
    elif eyes == 'happy':
        d.point([(7, 10), (8, 9), (11, 9), (12, 10)], fill=c('ink'))
    elif eyes == 'wide':
        d.rectangle([7, 9, 8, 10], fill=c('white'))
        d.rectangle([11, 9, 12, 10], fill=c('white'))
        d.point([(8, 10), (11, 10)], fill=c('ink'))
    elif eyes == 'wink':
        d.line([8, 9, 8, 10], fill=c('ink'))
        d.point([(11, 10), (12, 10)], fill=c('ink'))
    elif eyes == 'down':
        d.point([(8, 10), (11, 10)], fill=c('ink'))
    # mouth (row 13, inside the beard)
    if mouth == 'smile':
        d.line([8, 13, 11, 13], fill=c('mouth'))
    elif mouth == 'grin':
        d.rectangle([8, 13, 11, 14], fill=c('mouth'))
        d.line([8, 13, 11, 13], fill=c('white'))
    elif mouth == 'o':
        d.rectangle([9, 13, 10, 14], fill=c('mouth'))
    elif mouth == 'flat':
        d.line([8, 14, 11, 14], fill=c('mouth'))


def _jeb_hat(d: ImageDraw.ImageDraw) -> None:
    c = rgb
    d.rectangle([6, 1, 13, 5], fill=c('hat'))
    d.line([7, 1, 12, 1], fill=c('hat_light'))
    d.point([(9, 1), (10, 1)], fill=c('hat_dark'))  # crease
    d.rectangle([6, 4, 13, 5], fill=c('band'))
    d.rectangle([2, 6, 17, 7], fill=c('hat'))
    d.line([2, 7, 17, 7], fill=c('hat_dark'))


def _witch_paint(name: str) -> tuple[int, int, int, int]:
    """The witch's palette: the arms' shirt colour becomes the sleeve shade."""
    return rgb('witch_sleeve' if name == 'shirt' else name)


@dataclass(frozen=True)
class Costume:
    """A holiday's look for Jeb (`<pose>--<name>`): the same pose and face with
    a different body layer and a hat drawn in the headroom above."""
    name: str
    paint: Callable[[str], tuple[int, int, int, int]]  # colour lookup for the body and arms
    body: Callable[[ImageDraw.ImageDraw, bool], None]  # the body layer (boots to shoulders), given whether the arms hang
    keeps_straw_hat: bool  # the everyday hat stays on, with the costume drawn over it
    raised_arms: bool  # salute and wave raise the arm clear of the hat, as the witch's do
    hat: Callable[[ImageDraw.ImageDraw], None]  # drawn on the taller box (feet on its bottom row), once for every pose
    post: Callable[[Image.Image], None] | None = None  # a pass over the finished taller box, before the outline


def jeb(eyes: str = 'open', mouth: str = 'smile', pose: str = 'stand', beat: int = 0, costume: Costume | None = None):
    """One Jeb frame. `pose` decides the arms and any held prop; `beat`
    picks the alternate frame of a working pose. `costume` is a holiday
    variant: same pose and face, its own body and hat in the headroom above."""
    img, d = blank(JEB_W, BODY_H)
    c = costume.paint if costume else rgb
    arms = pose in ('stand', 'sleep')
    if costume:
        costume.body(d, arms)
    else:
        _jeb_base(d, arms=arms)
    if pose == 'banjo':
        d.rectangle([3, 17, 4, 21], fill=c('shirt'))  # left sleeve
        d.rectangle([15, 17, 16, 20], fill=c('shirt'))  # right sleeve
        d.line([10, 21, 18, 17], fill=c('band'))  # neck across the chest
        d.line([10, 22, 18, 18], fill=c('band'))
        d.rectangle([18, 15, 19, 17], fill=c('band'))  # peghead
        d.ellipse([2, 18, 10, 26], fill=c('banjo_rim'))  # pot at his hip
        d.ellipse([3, 19, 9, 25], fill=c('banjo_head'))
        d.rectangle([15, 18, 16, 19], fill=c('skin'))  # fretting hand
        hand_y = 20 if beat == 0 else 23
        d.rectangle([5, hand_y, 6, hand_y + 1], fill=c('skin'))  # picking hand
    elif pose == 'jar':
        d.rectangle([3, 17, 4, 23], fill=c('shirt'))
        d.rectangle([3, 24, 4, 25], fill=c('skin'))
    elif pose == 'sip':
        d.rectangle([3, 17, 4, 23], fill=c('shirt'))
        d.rectangle([3, 24, 4, 25], fill=c('skin'))
        if beat == 1:  # lowered, a satisfied breath
            d.rectangle([14, 16, 16, 18], fill=c('shirt'))
            d.rectangle([14, 17, 18, 23], fill=c('glass'))
            d.rectangle([14, 19, 18, 23], fill=c('amber'))
            d.line([14, 17, 18, 17], fill=c('steel'))
            d.rectangle([14, 23, 17, 24], fill=c('skin'))
    elif pose == 'hoe':
        d.rectangle([3, 17, 4, 20], fill=c('shirt'))
        d.rectangle([15, 17, 16, 21], fill=c('shirt'))
        top, low = ((1, 14), (17, 31)) if beat == 0 else ((4, 11), (18, 29))
        d.line([*top, *low], fill=c('wood'))
        d.rectangle([low[0] - 1, low[1], low[0] + 2, low[1] + 2], fill=c('steel'))  # blade
        d.rectangle([5, 19, 6, 20], fill=c('skin'))  # hands on the handle
        d.rectangle([12, 24, 13, 25], fill=c('skin'))
    elif pose == 'broom':
        d.rectangle([3, 17, 4, 21], fill=c('shirt'))
        d.rectangle([15, 17, 16, 21], fill=c('shirt'))
        lean = 0 if beat == 0 else 2
        d.line([16 + lean, 10, 14, 30], fill=c('wood'))
        d.rectangle([11 + lean, 30, 17 + lean, 34], fill=c('hat'))  # bristles
        d.line([11 + lean, 34, 17 + lean, 34], fill=c('hat_dark'))
        d.rectangle([15, 19, 16, 20], fill=c('skin'))
        d.rectangle([14, 23, 15, 24], fill=c('skin'))
    elif pose == 'book':
        d.rectangle([3, 17, 4, 21], fill=c('shirt'))
        d.rectangle([15, 17, 16, 21], fill=c('shirt'))
        d.rectangle([5, 19, 14, 23], fill=c('wood_dark'))  # almanac, open, brown cover
        d.rectangle([6, 19, 9, 22], fill=c('hat_light'))  # left page
        d.rectangle([10, 19, 13, 22], fill=c('hat_light'))  # right page
        d.line([9, 19, 9, 23], fill=c('wood_dark'))  # spine
        d.line([7, 20, 8, 20], fill=c('hat_dark'))  # lines of print
        d.line([11, 21, 12, 21], fill=c('hat_dark'))
        d.rectangle([5, 21, 6, 22], fill=c('skin'))
        d.rectangle([13, 21, 14, 22], fill=c('skin'))
    elif pose == 'stir':
        d.rectangle([3, 17, 4, 23], fill=c('shirt'))
        d.rectangle([3, 24, 4, 25], fill=c('skin'))
        d.rectangle([15, 17, 17, 19], fill=c('shirt'))  # arm out to the still
        tip = (19, 30) if beat == 0 else (17, 31)
        d.line([18, 18, *tip], fill=c('wood'))  # paddle
        d.rectangle([17, 18, 18, 19], fill=c('skin'))
    elif pose == 'salute':
        d.rectangle([15, 17, 16, 23], fill=c('shirt'))
        d.rectangle([15, 24, 16, 25], fill=c('skin'))
    elif pose == 'wave':
        d.rectangle([3, 17, 4, 23], fill=c('shirt'))
        d.rectangle([3, 24, 4, 25], fill=c('skin'))
    elif pose == 'hold':  # a small prop at his chest, drawn by the scene
        d.rectangle([3, 17, 4, 23], fill=c('shirt'))
        d.rectangle([3, 24, 4, 25], fill=c('skin'))
        d.rectangle([15, 17, 16, 20], fill=c('shirt'))
        d.rectangle([14, 20, 16, 21], fill=c('skin'))
    # The emoji's proportions: the body layer set lower, a big head on top.
    full, fd = blank(JEB_W, JEB_H)
    full.alpha_composite(img, (0, BODY_DY))
    _jeb_big_head(fd, eyes, mouth)
    if not costume or costume.keeps_straw_hat:
        _jeb_big_hat(fd)
    _jeb_head_props(fd, pose, beat, costume)
    if not costume:
        return outline(full)
    # the same body at the bottom of a taller box, the hat in the rows above
    tall, td = blank(JEB_W, JEB_H + HEADROOM)
    tall.alpha_composite(full, (0, HEADROOM))
    costume.hat(td)
    if costume.post:
        costume.post(tall)
    return outline(tall)


def _jeb_big_head(d: ImageDraw.ImageDraw, eyes: str, mouth: str) -> None:
    """Jeb's face as the Slack emoji draws it: a broad face, 2x2 eyes, a
    nose, rosy cheeks and a full brown beard."""
    c = rgb
    d.rectangle([5, 7, 14, 16], fill=c('skin'))  # face
    d.rectangle([4, 8, 15, 15], fill=c('skin'))
    d.rectangle([3, 10, 3, 12], fill=c('skin_dark'))  # ears
    d.rectangle([16, 10, 16, 12], fill=c('skin_dark'))
    d.line([5, 7, 14, 7], fill=c('skin_dark'))  # brim shadow
    d.rectangle([9, 11, 10, 12], fill=c('skin_dark'))  # nose
    d.point([(5, 12), (14, 12)], fill=c('cheek'))
    # beard, from the cheeks down past the chin
    d.rectangle([4, 13, 15, 17], fill=c('beard'))
    d.rectangle([5, 18, 14, 18], fill=c('beard'))
    d.rectangle([7, 19, 12, 19], fill=c('beard'))
    d.point([(6, 15), (10, 17), (13, 16), (8, 18), (12, 18)], fill=c('beard_dark'))
    # eyes, 2x2 like the emoji
    if eyes == 'open':
        d.rectangle([7, 9, 8, 10], fill=c('ink'))
        d.rectangle([11, 9, 12, 10], fill=c('ink'))
    elif eyes == 'shut':
        d.line([6, 10, 8, 10], fill=c('ink'))
        d.line([11, 10, 13, 10], fill=c('ink'))
    elif eyes == 'happy':  # ^ ^
        d.point([(6, 10), (7, 9), (8, 9), (9, 10)], fill=c('ink'))
        d.point([(10, 10), (11, 9), (12, 9), (13, 10)], fill=c('ink'))
    elif eyes == 'wide':  # O O
        d.rectangle([6, 8, 8, 10], fill=c('white'))
        d.rectangle([11, 8, 13, 10], fill=c('white'))
        d.point([(7, 9), (12, 9)], fill=c('ink'))
    elif eyes == 'wink':
        d.rectangle([7, 9, 8, 10], fill=c('ink'))
        d.point([(10, 10), (11, 9), (12, 9), (13, 10)], fill=c('ink'))
    elif eyes == 'down':
        d.line([7, 10, 8, 10], fill=c('ink'))
        d.line([11, 10, 12, 10], fill=c('ink'))
    # mouth, inside the beard
    if mouth == 'smile':
        d.line([8, 15, 11, 15], fill=c('mouth'))
        d.point([(7, 14), (12, 14)], fill=c('mouth'))
    elif mouth == 'grin':
        d.rectangle([7, 14, 12, 16], fill=c('mouth'))
        d.line([8, 14, 11, 14], fill=c('white'))
    elif mouth == 'o':
        d.rectangle([9, 14, 10, 16], fill=c('mouth'))
    elif mouth == 'flat':
        d.line([8, 15, 11, 15], fill=c('mouth'))


def _jeb_big_hat(d: ImageDraw.ImageDraw) -> None:
    c = rgb
    d.rectangle([6, 0, 13, 4], fill=c('hat'))  # crown
    d.line([7, 0, 12, 0], fill=c('hat_light'))
    d.point([(9, 0), (10, 0)], fill=c('hat_dark'))  # crease
    d.rectangle([6, 3, 13, 4], fill=c('band'))
    d.rectangle([1, 5, 18, 6], fill=c('hat'))  # brim
    d.line([1, 6, 18, 6], fill=c('hat_dark'))
    for x in (3, 7, 12, 16):
        d.point((x, 5), fill=c('hat_dark'))


def _jeb_head_props(d: ImageDraw.ImageDraw, pose: str, beat: int, costume: Costume | None = None) -> None:
    """What he holds up near his head, drawn over the big head."""
    c = costume.paint if costume else rgb
    raised = bool(costume and costume.raised_arms)
    if pose == 'jar':
        d.rectangle([15, 19, 16, 23], fill=c('shirt'))  # arm raised
        d.rectangle([15, 11, 19, 19], fill=c('glass'))  # jar beside his head
        d.rectangle([15, 14, 19, 19], fill=c('amber'))
        d.line([15, 11, 19, 11], fill=c('steel'))
        d.line([16, 12, 16, 18], fill=c('white'))
        d.rectangle([15, 19, 18, 20], fill=c('skin'))  # hand round the jar
    elif pose == 'sip' and beat == 0:
        d.rectangle([14, 19, 16, 22], fill=c('shirt'))
        d.rectangle([9, 13, 13, 19], fill=c('glass'))  # jar at his mouth
        d.rectangle([9, 15, 13, 19], fill=c('amber'))
        d.line([9, 13, 13, 13], fill=c('steel'))
        d.rectangle([12, 19, 15, 20], fill=c('skin'))
    elif pose == 'salute' and raised:
        # the hand stays three rows under the brim; the forearm and its
        # shadow keep it apart from the face
        d.line([4, 21, 1, 16], fill=c('shirt'), width=2)  # upper arm, elbow out
        d.line([1, 16, 2, 11], fill=c('shirt'), width=2)  # forearm up to the temple
        d.rectangle([1, 9, 6, 10], fill=c('skin'))  # flat hand
        d.line([4, 11, 6, 11], fill=c('skin_dark'))  # its shadow on the cheek
    elif pose == 'salute':
        d.line([4, 21, 1, 16], fill=c('shirt'), width=2)  # upper arm, elbow out
        d.line([1, 16, 3, 10], fill=c('shirt'), width=2)  # forearm to the brow
        d.line([2, 8, 9, 7], fill=c('skin'), width=2)  # flat hand at the brim, over the eye
    elif pose == 'wave' and raised:
        y = 10 if beat == 0 else 11
        d.rectangle([15, 15, 16, 22], fill=c('shirt'))
        d.rectangle([17, y + 4, 17, 15], fill=c('shirt'))  # forearm steps out past the ear
        d.rectangle([17, y, 19, y + 3], fill=c('skin'))  # hand clear of ear and brim
    elif pose == 'wave':
        d.rectangle([15, 15, 16, 22], fill=c('shirt'))
        y = 10 if beat == 0 else 11
        d.rectangle([16, y, 18, y + 4], fill=c('skin'))


def _witch_robe(d: ImageDraw.ImageDraw, arms: bool = True) -> None:
    """The witch's body layer: boots, a robe that flares to the hem instead of
    overalls, and sleeves in their own shade. Shading is hue-shifted: shadow
    leans blue, light leans magenta."""
    c = rgb
    robe, dark, light = c('witch_robe'), c('witch_robe_dark'), c('witch_robe_light')
    d.rectangle([5, 32, 9, 34], fill=c('boot'))
    d.rectangle([10, 32, 14, 34], fill=c('boot'))
    d.rectangle([5, 16, 14, 24], fill=robe)
    for y, x0, x1 in ((25, 4, 15), (26, 4, 15), (27, 3, 16), (28, 3, 16), (29, 3, 16), (30, 2, 17), (31, 2, 17)):
        d.line([x0, y, x1, y], fill=robe)
    d.line([5, 17, 5, 23], fill=light)  # light from the left
    d.line([13, 16, 14, 16], fill=dark)  # shadow down the right
    d.line([13, 16, 13, 24], fill=dark)
    d.line([14, 16, 14, 24], fill=dark)
    for y, x1 in ((25, 15), (26, 15), (27, 16), (28, 16), (29, 16), (30, 17)):
        d.line([x1 - 1, y, x1, y], fill=dark)
    d.line([9, 25, 9, 30], fill=dark)  # a fold in the skirt
    d.line([2, 31, 17, 31], fill=dark)  # hem
    d.point([(5, 28), (4, 29), (5, 29), (6, 29), (5, 30)], fill=c('yellow'))  # a small four point star
    if arms:
        d.rectangle([3, 17, 4, 23], fill=c('witch_sleeve'))
        d.rectangle([15, 17, 16, 23], fill=c('witch_sleeve'))
        d.rectangle([3, 24, 4, 25], fill=c('skin'))
        d.rectangle([15, 24, 16, 25], fill=c('skin'))


# the tall hat's cone, row by row: (x0, x1), leaning right toward a bent tip
_WITCH_CONE = {12: (5, 14), 11: (5, 14), 10: (6, 13), 9: (6, 13), 8: (7, 12), 7: (7, 12),
               6: (8, 11), 5: (8, 11), 4: (9, 12), 3: (10, 12), 2: (11, 13), 1: (13, 14)}


def _witch_hat(d: ImageDraw.ImageDraw) -> None:
    """A tall pointed hat in rows 1-12 of the taller box and a flat brim as
    wide as the straw hat's. One orange band with a gold buckle; the tip
    (rows 1-4) is plain. Drawn once, so it is identical in every pose."""
    c = rgb
    robe, dark = c('witch_robe'), c('witch_robe_dark')
    for y, (x0, x1) in _WITCH_CONE.items():
        d.line([x0, y, x1, y], fill=robe)
        d.point((x1, y), fill=dark)  # shaded side
    for y in (11, 12):
        x0, x1 = _WITCH_CONE[y]
        d.line([x0, y, x1, y], fill=c('fire'))
        d.point((x1, y), fill=c('copper'))
    d.rectangle([9, 11, 10, 12], fill=c('yellow'))  # buckle
    d.line([1, 13, 18, 13], fill=robe)  # brim
    d.line([1, 14, 18, 14], fill=dark)
    d.line([1, 13, 3, 13], fill=c('witch_robe_light'))


def _sleeve_edges(img: Image.Image) -> None:
    """The selective outline: a sleeve pixel on the outer edge of the arm
    (empty space on the side away from the body) takes the robe's dark shade,
    and one that touches skin, beard or a prop takes the sleeve's own darker
    shade, so the arm separates from the body in every pose."""
    c = rgb
    px = img.load()
    w, h = img.size
    sleeve, edge, outer = c('witch_sleeve'), c('witch_sleeve_dark'), c('witch_robe_dark')
    robe = {c('witch_robe'), c('witch_robe_dark'), c('witch_robe_light')}
    marks = []
    for y in range(h):
        for x in range(w):
            if px[x, y] != sleeve:
                continue
            ox = x - 1 if x < w // 2 else x + 1
            if 0 <= ox < w and not px[ox, y][3]:
                marks.append((x, y, outer))
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] and px[nx, ny] not in robe | {sleeve, edge, outer}:
                    marks.append((x, y, edge))
                    break
    for x, y, col in marks:
        px[x, y] = col


# The Santa hat: a red cone leaning right, its tip flopped over to a white pom-pom, on a fur band. Rows 1-11 of the taller box.
_SANTA_CONE = {11: (4, 15), 10: (4, 15), 9: (5, 14), 8: (6, 13), 7: (7, 12), 6: (8, 12), 5: (9, 12), 4: (10, 13), 3: (11, 14), 2: (12, 16), 1: (14, 16)}


def _santa_hat(d: ImageDraw.ImageDraw) -> None:
    c = rgb
    for y, (x0, x1) in _SANTA_CONE.items():
        d.line([x0, y, x1, y], fill=c('red'))
        d.point((x1, y), fill=c('red_dark'))  # shaded side
    d.line([16, 3, 16, 4], fill=c('red'))  # the tip flops over
    d.line([17, 3, 17, 4], fill=c('red_dark'))
    d.rectangle([16, 5, 18, 7], fill=c('white'))  # pom-pom
    d.point((18, 7), fill=c('cloud'))
    d.rectangle([3, 12, 16, 14], fill=c('white'))  # fur band
    d.line([3, 14, 16, 14], fill=c('cloud'))
    d.point([(5, 13), (8, 13), (11, 13), (14, 13)], fill=c('cloud'))


def _scarf(d: ImageDraw.ImageDraw, base: str, stripe: str, edge: str) -> None:
    """A scarf wrapped at the neck (rows 15-16 of the body layer, under the beard) with a tail down the right side."""
    c = rgb
    d.rectangle([5, 15, 14, 16], fill=c(base))
    for x in (6, 9, 12):
        d.line([x, 15, x, 16], fill=c(stripe))
    d.line([5, 16, 14, 16], fill=c(edge))
    d.rectangle([12, 17, 13, 22], fill=c(base))
    d.line([12, 19, 13, 19], fill=c(stripe))
    d.line([12, 22, 13, 22], fill=c(edge))


def _santa_body(d: ImageDraw.ImageDraw, arms: bool = True) -> None:
    _jeb_base(d, arms=arms)
    _scarf(d, 'flannel_green', 'white', 'flannel_green_dark')


def _harvest_body(d: ImageDraw.ImageDraw, arms: bool = True) -> None:
    _jeb_base(d, arms=arms)
    _scarf(d, 'foliage_gold', 'foliage_orange', 'amber_dark')


def _harvest_hat(d: ImageDraw.ImageDraw) -> None:
    """Autumn leaves tucked in the straw hat's band (rows 11-12 of the taller box) and a small cluster of broad leaves fanned out from its right end."""
    c = rgb
    for x, y, col in ((6, 11, 'foliage_red'), (7, 11, 'foliage_red'), (7, 12, 'foliage_orange'), (8, 12, 'foliage_orange'),
                      (9, 11, 'foliage_gold'), (10, 12, 'foliage_gold'), (10, 11, 'foliage_orange'), (11, 11, 'foliage_red'), (6, 12, 'foliage_red')):
        d.point((x, y), fill=c(col))
    # a cluster of three broad leaves fanned out from the band's right end: red up-left, orange up-right, gold out to the side
    red, red_edge, orange, orange_edge, gold, stem = 'foliage_red', 'red_dark', 'foliage_orange', 'copper_dark', 'foliage_gold', 'amber_dark'
    leaves = (
        [(10, 5, red_edge), (9, 6, red_edge), (10, 6, red), (11, 6, red_edge), (9, 7, red), (10, 7, red), (11, 7, red_edge), (10, 8, red), (11, 8, red_edge)]
        + [(14, 6, orange_edge), (13, 7, orange_edge), (14, 7, orange), (15, 7, orange_edge), (13, 8, orange), (14, 8, orange), (15, 8, orange_edge), (14, 9, orange_edge)]
        + [(16, 9, stem), (17, 9, gold), (15, 10, stem), (16, 10, gold), (17, 10, gold), (18, 10, stem), (16, 11, stem), (17, 11, stem)]
        + [(12, 9, stem), (12, 10, stem), (13, 10, stem), (14, 10, stem)]
    )
    for x, y, col in leaves:
        d.point((x, y), fill=c(col))

WITCH = Costume('halloween', _witch_paint, _witch_robe, keeps_straw_hat=False, raised_arms=True, hat=_witch_hat, post=_sleeve_edges)
HARVEST = Costume('thanksgiving', rgb, _harvest_body, keeps_straw_hat=True, raised_arms=False, hat=_harvest_hat)
SANTA = Costume('christmas', rgb, _santa_body, keeps_straw_hat=False, raised_arms=True, hat=_santa_hat)
# the only holidays that dress Jeb up: religious and cultural holidays get a banner badge, never a costume
COSTUMES = [WITCH, HARVEST, SANTA]


def jeb_sprites() -> list[Sprite]:
    base = _jeb_base_sprites()
    out = list(base)
    # every pose wears each holiday's costume as a --<holiday> variant
    for costume in COSTUMES:
        out += [Sprite(f'{sp.name}--{costume.name}', w.frames, list(sp.ms), sp.anchor)
                for sp, w in zip(base, _jeb_base_sprites(costume))]
    return out


def _jeb_base_sprites(costume: Costume | None = None) -> list[Sprite]:
    def j(*args: str | int) -> Image.Image:
        return jeb(*args, costume=costume)

    return [
        Sprite('jeb-idle', [j(), j(), j(), j('shut')], [900, 900, 900, 160]),
        Sprite('jeb-happy', [j('happy', 'grin')], [400]),
        Sprite('jeb-spooked', [j('wide', 'o')], [400]),
        Sprite('jeb-wink', [j('wink', 'smile')], [400]),
        Sprite('jeb-think', [j('down', 'flat', 'hold')], [400]),
        Sprite('jeb-sleep', [j('shut', 'flat', 'sleep')], [400]),
        Sprite('jeb-banjo', [j('happy', 'smile', 'banjo', 0), j('shut', 'smile', 'banjo', 1)], [260, 260]),
        Sprite('jeb-jar', [j('happy', 'grin', 'jar')], [400]),
        Sprite('jeb-sip', [j('shut', 'smile', 'sip', 0), j('happy', 'smile', 'sip', 1)], [700, 700]),
        Sprite('jeb-hoe', [j('down', 'flat', 'hoe', 0), j('down', 'flat', 'hoe', 1)], [300, 300]),
        Sprite('jeb-broom', [j('open', 'smile', 'broom', 0), j('open', 'smile', 'broom', 1)], [280, 280]),
        Sprite('jeb-book', [j('down', 'smile', 'book')], [400]),
        Sprite('jeb-stir', [j('open', 'flat', 'stir', 0), j('open', 'flat', 'stir', 1)], [320, 320]),
        Sprite('jeb-salute', [j('open', 'flat', 'stand'), j('open', 'flat', 'salute')], [500, 1500]),
        Sprite('jeb-wave', [j('happy', 'grin', 'wave', 0), j('happy', 'grin', 'wave', 1)], [250, 250]),
        Sprite('jeb-hold', [j('open', 'smile', 'hold')], [400]),
    ]


# ----------------------------------------------------------------- Blue ----

def blue(kind: str = 'stand', beat: int = 0):
    img, d = blank(20, 13)
    c = rgb
    if kind == 'nap':
        d.ellipse([2, 5, 15, 11], fill=c('blue_coat'))  # curled up
        d.ellipse([11, 4, 18, 10], fill=c('blue_coat'))
        d.rectangle([13, 5, 14, 10], fill=c('blue_spot'))  # ear flopped
        d.rectangle([16, 7, 18, 9], fill=c('tan'))
        d.point((18, 7), fill=c('nose'))
        d.line([15, 6, 16, 6], fill=c('ink'))  # shut eye
        d.point([(5, 7), (8, 6), (10, 8)], fill=c('blue_spot'))
        return outline(img)
    run = kind == 'run'
    d.rectangle([4, 4, 13, 8], fill=c('blue_coat'))  # body
    for p in ((5, 5), (8, 4), (10, 6), (12, 5), (6, 7)):
        d.point(p, fill=c('blue_spot'))
    d.rectangle([12, 1, 17, 6], fill=c('blue_coat'))  # head
    d.rectangle([12, 2, 13, 8], fill=c('blue_spot'))  # long ear
    d.rectangle([16, 4, 18, 6], fill=c('tan'))  # muzzle
    d.point((18, 4), fill=c('nose'))
    d.point((15, 3), fill=c('ink'))  # eye
    if kind == 'bark':
        d.line([16, 6, 18, 7], fill=c('mouth'))
    tail_up = beat == 0
    d.line([4, 4, 1, 1 if tail_up else 3], fill=c('blue_coat'), width=2)  # tail
    if run:
        legs = [(4, 9, 2, 11), (6, 9, 7, 11), (11, 9, 9, 11), (13, 9, 15, 11)] if beat == 0 else \
               [(4, 9, 5, 11), (6, 9, 4, 11), (11, 9, 13, 11), (13, 9, 12, 11)]
        for x0, y0, x1, y1 in legs:
            d.line([x0, y0, x1, y1], fill=c('blue_spot'))
    else:
        for x in (5, 7, 11, 13):
            d.line([x, 9, x, 11], fill=c('blue_spot'))
    return outline(img)


def blue_sprites() -> list[Sprite]:
    return [
        Sprite('blue-wag', [blue('stand', 0), blue('stand', 1)], [250, 250]),
        Sprite('blue-run', [blue('run', 0), blue('run', 1)], [120, 120]),
        Sprite('blue-nap', [blue('nap')], [400]),
        Sprite('blue-bark', [blue('bark', 0), blue('stand', 1)], [220, 220]),
    ]


# ------------------------------------------------------------ hired hand ----

# Hired hands: six different farmhands in Jeb's own plain style, with
# everyday work clothes and a range of skin tones and hair. Same face style
# as Jeb (simple eyes, a smile), no exaggerated features.
HANDS = [
    {'skin': 'skin', 'hair': 'hair_brown', 'hat': 'cap', 'hat_c': 'red', 'shirt': 'flannel_green', 'stripe': 'flannel_green_dark'},
    {'skin': 'skin_deep', 'hair': 'hair_dark', 'hat': 'beanie', 'hat_c': 'denim', 'shirt': 'tee_grey', 'stripe': None},
    {'skin': 'skin_tan', 'hair': 'hair_dark', 'hat': 'none', 'hat_c': None, 'shirt': 'tee_teal', 'stripe': None},
    {'skin': 'skin_brown', 'hair': 'hair_dark', 'hat': 'cap', 'hat_c': 'denim', 'shirt': 'shirt', 'stripe': 'shirt_dark'},
    {'skin': 'skin', 'hair': 'hair_blond', 'hat': 'bandana', 'hat_c': 'red', 'shirt': 'tee_grey', 'stripe': None},
    {'skin': 'skin_deep', 'hair': 'hair_dark', 'hat': 'cap', 'hat_c': 'green_dark', 'shirt': 'flannel_green', 'stripe': 'flannel_green_dark'},
]


def hand(variant: int = 0, beat: int = 0):
    v = HANDS[variant % len(HANDS)]
    img, d = blank(16, 28)
    c = rgb
    d.rectangle([4, 25, 7, 26], fill=c('boot'))
    d.rectangle([8, 25, 11, 26], fill=c('boot'))
    d.rectangle([5, 19, 7, 24], fill=c('denim'))  # work pants
    d.rectangle([8, 19, 10, 24], fill=c('denim'))
    d.rectangle([4, 12, 11, 18], fill=c(v['shirt']))  # shirt
    if v['stripe']:
        for x in (5, 8, 10):
            d.line([x, 12, x, 18], fill=c(v['stripe']))
    d.rectangle([5, 5, 10, 11], fill=c(v['skin']))  # face
    d.point([(6, 7), (9, 7)], fill=c('ink'))  # eyes
    d.line([7, 9, 8, 9], fill=c('mouth'))  # smile
    d.point([(4, 8), (11, 8)], fill=c(v['skin']))  # ears
    # hair, then whatever is on their head
    d.rectangle([5, 3, 10, 4], fill=c(v['hair']))
    if v['hat'] == 'cap':
        d.rectangle([5, 2, 10, 4], fill=c(v['hat_c']))
        d.line([10, 4, 12, 4], fill=c(v['hat_c']))  # bill
    elif v['hat'] == 'beanie':
        d.rectangle([5, 1, 10, 4], fill=c(v['hat_c']))
        d.line([5, 4, 10, 4], fill=c('white'))
    elif v['hat'] == 'bandana':
        d.rectangle([5, 3, 10, 4], fill=c(v['hat_c']))
        d.point((4, 4), fill=c(v['hat_c']))
    else:
        d.rectangle([5, 2, 10, 4], fill=c(v['hair']))
    # the hoe, swung between frames
    top, low = ((1, 10), (13, 24)) if beat == 0 else ((3, 8), (14, 22))
    d.line([*top, *low], fill=c('wood'))
    d.rectangle([low[0] - 1, low[1], low[0] + 1, low[1] + 2], fill=c('steel'))
    d.rectangle([3, 13, 4, 14], fill=c(v['skin']))  # hands on the handle
    d.rectangle([9, 18, 10, 19], fill=c(v['skin']))
    return outline(img)


def visitor_sprites() -> list[Sprite]:
    out = [Sprite('hand-work', [hand(0, 0), hand(0, 1)], [300, 300])]
    out += [Sprite(f'hand-work-{v}', [hand(v, 0), hand(v, 1)], [300, 300]) for v in range(len(HANDS))]

    # Miss Opal: grey bun, purple dress, a basket on her arm.
    img, d = blank(14, 28)
    c = rgb
    d.rectangle([3, 13, 10, 25], fill=c('dress'))
    d.polygon([(2, 25), (11, 25), (10, 15), (3, 15)], fill=c('dress'))
    d.rectangle([4, 26, 5, 26], fill=c('boot'))
    d.rectangle([8, 26, 9, 26], fill=c('boot'))
    d.rectangle([4, 6, 9, 12], fill=c('skin'))
    d.point([(5, 8), (8, 8)], fill=c('ink'))
    d.line([6, 10, 7, 10], fill=c('mouth'))
    d.rectangle([3, 3, 10, 6], fill=c('hair_grey'))
    d.rectangle([5, 1, 8, 3], fill=c('hair_grey'))  # bun
    d.rectangle([10, 17, 13, 20], fill=c('wood'))  # basket
    d.line([10, 16, 13, 16], fill=c('wood_dark'))
    out.append(Sprite('opal', [outline(img)], [400]))

    # A milk cow.
    def cow(beat):
        img, d = blank(22, 15)
        d.rectangle([3, 4, 16, 10], fill=c('cow_white'))
        d.rectangle([5, 5, 8, 8], fill=c('cow_black'))
        d.rectangle([12, 4, 14, 7], fill=c('cow_black'))
        d.rectangle([15, 2, 20, 7], fill=c('cow_white'))  # head
        d.rectangle([18, 5, 21, 7], fill=c('pink'))  # muzzle
        d.point((17, 3), fill=c('ink'))
        d.line([15, 1, 16, 2], fill=c('cow_black'))  # horn/ear
        d.line([3, 4, 1, 7 if beat else 8], fill=c('cow_white'))  # tail
        for x in (4, 6, 13, 15):
            d.line([x, 11, x, 13], fill=c('cow_black'))
        d.rectangle([8, 10, 10, 11], fill=c('pink'))  # udder
        return outline(img)
    out.append(Sprite('cow', [cow(0), cow(1)], [600, 600]))

    # Revenuer's black sedan.
    def car(beat):
        img, d = blank(32, 15)
        d.rectangle([1, 6, 30, 11], fill=c('black_car'))
        d.rectangle([7, 2, 23, 6], fill=c('black_car'))
        d.rectangle([9, 3, 14, 5], fill=c('glass_edge'))
        d.rectangle([16, 3, 21, 5], fill=c('glass_edge'))
        d.point((30, 7), fill=c('fire_hot'))  # headlight
        d.line([1, 9, 30, 9], fill=c('chrome'))
        for x in (6, 24):
            d.ellipse([x - 2, 10, x + 2, 14], fill=c('tire'))
            d.point((x, 12 if beat else 11), fill=c('chrome'))
        return outline(img)
    out.append(Sprite('revenuer', [car(0), car(1)], [120, 120]))

    # Black bear on its hind legs.
    img, d = blank(18, 20)
    d.ellipse([3, 6, 14, 18], fill=c('cow_black'))
    d.ellipse([5, 1, 12, 8], fill=c('cow_black'))
    d.point([(5, 1), (12, 1)], fill=c('cow_black'))
    d.rectangle([7, 5, 10, 7], fill=c('tan'))
    d.point([(7, 4), (10, 4)], fill=c('white'))
    d.point((8, 6), fill=c('nose'))
    d.rectangle([1, 8, 3, 11], fill=c('cow_black'))  # paws up
    d.rectangle([14, 8, 16, 11], fill=c('cow_black'))
    out.append(Sprite('bear', [outline(img)], [400]))

    # Wild turkey, strutting.
    def turkey(beat):
        img, d = blank(14, 13)
        d.ellipse([1, 1, 9, 10], fill=c('fur'))  # fanned tail
        d.arc([1, 1, 9, 10], 180, 360, fill=c('amber'))
        d.ellipse([5, 5, 11, 10], fill=c('beard_dark'))  # body
        d.line([10, 2, 10, 6], fill=c('beard_dark'))  # neck
        d.rectangle([10, 1, 12, 3], fill=c('stone'))
        d.point((12, 4), fill=c('red'))  # wattle
        d.line([7, 10, 7 + beat, 12], fill=c('amber'))
        d.line([9, 10, 9 - beat, 12], fill=c('amber'))
        return outline(img)
    out.append(Sprite('turkey', [turkey(0), turkey(1)], [260, 260]))

    # Groundhog (whistle pig) up on its haunches.
    img, d = blank(10, 11)
    d.ellipse([2, 3, 8, 10], fill=c('fur'))
    d.ellipse([3, 0, 7, 4], fill=c('fur'))
    d.point([(4, 2), (6, 2)], fill=c('ink'))
    d.point((5, 3), fill=c('nose'))
    out.append(Sprite('groundhog', [outline(img)], [400]))

    # A hen pecking.
    def hen(beat):
        img, d = blank(10, 10)
        d.ellipse([1, 3, 7, 8], fill=c('cow_white'))
        y = 1 if beat == 0 else 4
        d.rectangle([6, y, 8, y + 2], fill=c('cow_white'))
        d.point((7, y - 1), fill=c('red'))
        d.point((9, y + 1), fill=c('amber'))
        d.line([3, 8, 3, 9], fill=c('amber'))
        d.line([5, 8, 5, 9], fill=c('amber'))
        return outline(img)
    out.append(Sprite('hen', [hen(0), hen(1)], [300, 300]))

    # The pup that follows Blue.
    img, d = blank(13, 9)
    d.rectangle([2, 3, 8, 6], fill=c('tan'))
    d.rectangle([8, 1, 11, 5], fill=c('tan'))
    d.rectangle([8, 2, 8, 5], fill=c('fur'))
    d.point((10, 2), fill=c('ink'))
    d.point((11, 3), fill=c('nose'))
    for x in (3, 7):
        d.line([x, 7, x, 8], fill=c('fur'))
    d.line([2, 3, 0, 1], fill=c('tan'))
    out.append(Sprite('pup', [outline(img)], [400]))
    return out
