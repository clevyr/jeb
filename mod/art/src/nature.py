"""The little things around the farm: wildlife, seasons, Jeb's daily rhythm and
homestead details. Same palette, 1px ink outline on the solid things, band
scale (ground at y 39 of 48)."""

from __future__ import annotations

from PIL import Image

from pixel import Sprite, blank, outline, rgb

c = rgb


def birdhouse():
    img, d = blank(7, 9)
    d.rectangle([1, 4, 5, 7], fill=c('wood'))
    d.polygon([(1, 4), (3, 1), (5, 4)], fill=c('roof'))
    d.point((3, 6), fill=c('ink'))
    return outline(img)


def bluebird(beat: int):
    img, d = blank(7, 5)
    d.rectangle([1, 1, 4, 3], fill=c('bluebird'))
    d.rectangle([4, 0, 5, 2], fill=c('bluebird'))
    d.point((2, 3), fill=c('amber'))
    d.point((3, 3), fill=c('amber'))
    d.point((0, 2 if beat else 3), fill=c('bluebird'))
    img = outline(img)
    img.putpixel((6, 1), c('amber'))
    img.putpixel((5, 1), c('white') if beat else c('ink'))
    return img


def cardinal():
    img, d = blank(8, 7)
    d.rectangle([1, 2, 5, 5], fill=c('red'))
    d.rectangle([4, 1, 6, 3], fill=c('red'))
    d.point((5, 0), fill=c('red'))
    d.point((1, 5), fill=c('red_dark'))
    d.point((2, 5), fill=c('red_dark'))
    img = outline(img)
    img.putpixel((7, 2), c('amber'))
    img.putpixel((6, 2), c('amber'))
    img.putpixel((5, 2), c('ink'))
    return img


def owl(blink: bool):
    img, d = blank(9, 11)
    d.rectangle([1, 2, 7, 9], fill=c('owl_brown'))
    d.rectangle([3, 6, 5, 9], fill=c('owl_cream'))
    d.point([(1, 1), (7, 1)], fill=c('owl_brown'))
    img = outline(img)
    d = __import__('PIL.ImageDraw', fromlist=['ImageDraw']).Draw(img)
    if blink:
        d.line([2, 4, 3, 4], fill=c('ink'))
        d.line([5, 4, 6, 4], fill=c('ink'))
    else:
        d.rectangle([2, 3, 3, 5], fill=c('white'))
        d.rectangle([5, 3, 6, 5], fill=c('white'))
        d.point([(3, 4), (5, 4)], fill=c('ink'))
    d.point((4, 5), fill=c('amber'))
    return img


def butterfly(beat: int):
    img, d = blank(6, 5)
    if beat == 0:
        d.rectangle([0, 0, 2, 2], fill=c('amber'))
        d.rectangle([3, 0, 5, 2], fill=c('amber'))
        d.rectangle([0, 3, 1, 4], fill=c('yellow'))
        d.rectangle([4, 3, 5, 4], fill=c('yellow'))
        d.point([(1, 1), (4, 1)], fill=c('pink'))
    else:
        d.rectangle([1, 0, 2, 3], fill=c('amber'))
        d.rectangle([3, 0, 4, 3], fill=c('yellow'))
    d.line([2, 1, 3, 1] if beat else [2, 1, 3, 1], fill=c('ink'))
    d.line([2, 1, 2, 4], fill=c('ink'))
    d.line([3, 1, 3, 4], fill=c('ink'))
    return img


def deer():
    img, d = blank(15, 14)
    d.rectangle([3, 5, 10, 9], fill=c('deer_tan'))
    d.rectangle([4, 9, 9, 9], fill=c('deer_light'))
    for x in (4, 5, 8, 9):
        d.line([x, 10, x, 12], fill=c('deer_tan'))
    d.rectangle([10, 3, 11, 6], fill=c('deer_tan'))
    d.rectangle([11, 1, 13, 3], fill=c('deer_tan'))
    d.point([(11, 0), (13, 0)], fill=c('deer_tan'))
    d.line([2, 5, 2, 6], fill=c('white'))
    img = outline(img)
    img.putpixel((13, 2), c('ink'))
    img.putpixel((14, 3), c('nose'))
    return img


def creek(beat: int):
    img, d = blank(12, 3)
    d.rectangle([0, 0, 11, 2], fill=c('water'))
    for x in ((1, 5, 9) if beat == 0 else (3, 7)):
        d.line([x, 1, x + 1, 1], fill=c('water_light'))
    d.point([(0, 0), (11, 0)], fill=c('soil_dark'))
    d.point([(0, 2), (11, 2)], fill=c('soil_dark'))
    return img


def fisher(beat: int):
    img, d = blank(11, 13)
    d.rectangle([2, 0, 5, 1], fill=c('hat'))
    d.rectangle([1, 2, 6, 2], fill=c('hat_dark'))
    d.rectangle([2, 3, 5, 5], fill=c('skin'))
    d.rectangle([2, 5, 5, 6], fill=c('beard'))
    d.rectangle([1, 7, 6, 9], fill=c('shirt'))
    d.rectangle([2, 10, 5, 11], fill=c('denim'))
    d.rectangle([2, 12, 5, 12], fill=c('boot'))
    img = outline(img)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    d.line([6, 8, 10, 3], fill=c('wood_dark'))
    d.line([10, 3, 10, 10 + beat], fill=c('white'))
    d.point((10, 11 + beat), fill=c('red'))
    return img


def woodpile(level: int):
    img, d = blank(14, 11)
    for r in range(level):
        y = 9 - 2 * r
        for k in range(4 if r % 2 == 0 else 3):
            x = 1 + 3 * k + (0 if r % 2 == 0 else 1)
            d.rectangle([x, y, x + 2, y + 1], fill=c('wood'))
            d.point((x, y), fill=c('hat_light'))
    return outline(img)


def axe_stump(beat: int):
    img, d = blank(8, 11)
    d.rectangle([1, 7, 5, 10], fill=c('wood'))
    d.rectangle([1, 6, 5, 7], fill=c('hat_light'))
    img = outline(img)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    d.line([3, 6, 5, 2], fill=c('wood_dark'))
    d.rectangle([4, 0, 6, 2], fill=c('steel'))
    if beat:
        d.point([(0, 3), (7, 5), (1, 1)], fill=c('hat_light'))
    return img


def garden(stage: int):
    img, d = blank(10, 15)
    d.rectangle([0, 13, 9, 14], fill=c('soil_dark'))
    d.line([1, 7, 1, 13], fill=c('wood_dark'))
    d.line([4, 7, 4, 13], fill=c('wood_dark'))
    if stage >= 1:
        d.point([(2, 12), (6, 12), (7, 11)], fill=c('leaf'))
    if stage >= 2:
        d.rectangle([1, 9, 4, 12], fill=c('green'))
        d.line([7, 7, 7, 12], fill=c('green_dark'))
        d.point([(6, 9), (8, 10)], fill=c('green'))
    if stage >= 3:
        d.line([7, 3, 7, 12], fill=c('green_dark'))
        d.rectangle([5, 0, 9, 4], fill=c('yellow'))
        d.rectangle([6, 1, 8, 3], fill=c('soil_dark'))
        d.point([(2, 10), (3, 11), (1, 12)], fill=c('red'))
    return img


def porch_light():
    img, d = blank(5, 8)
    d.line([0, 0, 0, 1], fill=c('steel'))
    d.rectangle([1, 1, 3, 2], fill=c('steel'))
    d.rectangle([1, 3, 3, 5], fill=c('fire_hot'))
    d.point([(0, 4), (4, 4), (2, 6), (0, 6), (4, 6)], fill=c('amber'))
    return img


def mug(beat: int):
    img, d = blank(6, 7)
    d.rectangle([1, 3, 4, 6], fill=c('white'))
    d.point([(5, 4), (5, 5)], fill=c('white'))
    d.line([1, 3, 4, 3], fill=c('band'))
    img = outline(img)
    img.putpixel((2, 0 if beat == 0 else 1), c('smoke'))
    img.putpixel((3, 1 if beat == 0 else 0), c('smoke'))
    return img


def lunch():
    img, d = blank(9, 6)
    d.rectangle([0, 4, 8, 5], fill=c('white'))
    d.ellipse([1, 0, 7, 4], fill=c('hat'))
    d.point([(3, 1), (5, 2), (2, 2)], fill=c('red'))
    return outline(img)


def hat_feather():
    img, d = blank(5, 6)
    d.line([0, 5, 3, 1], fill=c('red'))
    d.line([1, 5, 4, 2], fill=c('red_dark'))
    d.point([(3, 0), (4, 1)], fill=c('white'))
    return img


def laundry(kind: str):
    if kind == 'shirt':
        img, d = blank(6, 7)
        d.rectangle([1, 1, 4, 6], fill=c('shirt'))
        d.rectangle([0, 1, 0, 3], fill=c('shirt_dark'))
        d.rectangle([5, 1, 5, 3], fill=c('shirt_dark'))
        d.point([(2, 0), (3, 0)], fill=c('white'))
    elif kind == 'overalls':
        img, d = blank(6, 8)
        d.rectangle([1, 1, 4, 3], fill=c('denim'))
        d.rectangle([1, 4, 2, 7], fill=c('denim_dark'))
        d.rectangle([3, 4, 4, 7], fill=c('denim_dark'))
        d.point([(1, 0), (4, 0)], fill=c('white'))
    else:
        img, d = blank(8, 5)
        d.rectangle([0, 1, 7, 4], fill=c('white'))
        d.line([0, 4, 7, 4], fill=c('cloud'))
        d.point([(1, 0), (6, 0)], fill=c('hat_light'))
    return img


def postcard():
    img, d = blank(7, 6)
    d.rectangle([1, 1, 5, 4], fill=c('white'))
    d.point([(5, 1)], fill=c('red'))
    d.line([2, 3, 4, 3], fill=c('denim'))
    return outline(img)


def cake(beat: int):
    img, d = blank(9, 10)
    d.rectangle([1, 6, 7, 8], fill=c('hat_light'))
    d.rectangle([1, 5, 7, 6], fill=c('pink'))
    d.line([4, 3, 4, 4], fill=c('red'))
    img = outline(img)
    img.putpixel((4, 2), c('fire') if beat == 0 else c('fire_hot'))
    return img


def rainbow():
    from PIL import ImageDraw
    img, d = blank(32, 14)
    for i, name in enumerate(('red', 'amber', 'yellow', 'green', 'drop', 'purple')):
        d.arc([i, i, 31 - i, 27 - i], 180, 360, fill=c(name), width=1)
    d.ellipse([0, 10, 5, 13], fill=c('cloud'))
    d.ellipse([26, 10, 31, 13], fill=c('cloud'))
    return img


def puddle():
    img, d = blank(9, 2)
    d.line([1, 0, 7, 0], fill=c('water'))
    d.line([0, 1, 8, 1], fill=c('water'))
    d.point([(3, 0), (4, 0)], fill=c('water_light'))
    return img


def star_streak():
    img, d = blank(8, 4)
    d.point([(7, 0), (6, 0)], fill=c('white'))
    d.point([(5, 1), (4, 1)], fill=c('night_star'))
    d.point([(3, 2), (2, 2)], fill=c('night_star'))
    d.point([(1, 3)], fill=c('smoke_dark'))
    return img


def drift_leaf(tint: str):
    img, d = blank(3, 3)
    d.point([(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)], fill=c(tint))
    return img


def drift_flake():
    img, d = blank(3, 3)
    d.point([(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)], fill=c('white'))
    return img


def badge(rows: list[str], legend: dict[str, str]):
    """A holiday badge for the desktop banner's tab row: the picture in `rows` ('.' clear, at most 7x7) inside an ink outline."""
    img, d = blank(len(rows[0]) + 2, len(rows) + 2)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != '.':
                d.point((x + 1, y + 1), fill=c(legend[ch]))
    return outline(img)


# One 9x9-or-smaller picture per holiday (Holiday.names): firework, heart, shamrock, egg, flag, pumpkin, turkey, holly.
# No sacred text or figures, no animals.
BADGES = {
    'newyear': (['...y...', '.f.y.f.', '..fyf..', 'yyywyyy', '..fyf..', '.f.y.f.', '...y...'], {'y': 'yellow', 'f': 'fire', 'w': 'white'}),
    'valentines': (['.pp.pp.', 'pwppppp', 'ppppppr', '.ppppr.', '..prr..', '...r...'], {'p': 'pink', 'w': 'white', 'r': 'red'}),
    'stpatricks': (['.gg.gg.', 'glggggg', '.ggggg.', '..ggg..', '...s...', '...s...'], {'g': 'green', 'l': 'leaf', 's': 'green_dark'}),
    'easter': (['..ppp..', '.ppppp.', '.pwppp.', 'ppppppp', 'yyyyyyy', 'ppppppp', '.ppppp.'], {'p': 'pink', 'y': 'yellow', 'w': 'white'}),
    'july4': (['pDwDwww', 'pwDwrrr', 'pDwDwww', 'prrrrrr', 'pwwwwww', 'p......', 'p......'], {'p': 'tan', 'D': 'water', 'r': 'red', 'w': 'white'}),
    'halloween': (['...s...', '.fffff.', 'fffffff', 'fiffifi', 'fffffff', 'fiiiiif', '.fffff.'], {'s': 'green_dark', 'f': 'fire', 'i': 'ink'}),
    'thanksgiving': (['.rfyfr.', 'rfyyyfr', 'fyyyyyf', '.ooooo.', '.ooeoo.', '..oro..', '..a.a..'], {'r': 'red', 'f': 'fire', 'y': 'yellow', 'o': 'tan', 'e': 'ink', 'a': 'amber'}),
    'christmas': (['.gg.gg.', 'gGgggGg', '.ggGgg.', '..rrr..', '..rwr..', '...r...'], {'g': 'green', 'G': 'green_dark', 'r': 'red', 'w': 'white'}),
}


def unlock_sprites() -> list[Sprite]:
    out = [
        Sprite('birdhouse', [birdhouse()]),
        Sprite('bluebird', [bluebird(0), bluebird(1)], [400, 400]),
        Sprite('cardinal', [cardinal()]),
        Sprite('owl', [owl(False), owl(True)], [900, 150]),
        Sprite('butterfly', [butterfly(0), butterfly(1)], [180, 180]),
        Sprite('deer', [deer()]),
        Sprite('creek', [creek(0), creek(1)], [500, 500]),
        Sprite('fisher', [fisher(0), fisher(1)], [600, 600]),
        Sprite('axe-stump', [axe_stump(0), axe_stump(1)], [900, 150]),
        Sprite('porch-light', [porch_light()]),
        Sprite('mug', [mug(0), mug(1)], [400, 400]),
        Sprite('lunch', [lunch()]),
        Sprite('hat-feather', [hat_feather()]),
        Sprite('laundry-shirt', [laundry('shirt')]),
        Sprite('laundry-overalls', [laundry('overalls')]),
        Sprite('postcard', [postcard()]),
        Sprite('cake', [cake(0), cake(1)], [300, 300]),
        Sprite('rainbow', [rainbow()]),
        Sprite('puddle', [puddle()]),
        Sprite('star-streak', [star_streak()]),
        Sprite('drift-flake', [drift_flake()]),
    ]
    out += [Sprite(f'badge-{name}', [badge(*BADGES[name])]) for name in BADGES]
    out += [Sprite(f'woodpile-{n}', [woodpile(n)]) for n in range(1, 5)]
    out += [Sprite(f'garden-{n}', [garden(n)]) for n in range(4)]
    out += [Sprite(f'drift-leaf-{i}', [drift_leaf(t)]) for i, t in enumerate(('foliage_orange', 'foliage_red', 'foliage_gold'))]
    return out
