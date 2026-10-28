"""The homestead at band scale: house, still, sign, truck, crops, stack icons,
quilt squares, lanterns, sky, weather and small overlays."""

from __future__ import annotations

from PIL import ImageDraw

from pixel import Sprite, blank, outline, rgb

c = rgb

# 3x5 pixel font for the sign, labels and counts.
FONT = {
    'A': '010101111101101', 'B': '110101110101110', 'C': '011100100100011',
    'D': '110101101101110', 'E': '111100110100111', 'F': '111100110100100',
    'G': '011100101101011', 'H': '101101111101101', 'I': '111010010010111',
    'J': '001001001101010', 'K': '101101110101101', 'L': '100100100100111',
    'M': '101111111101101', 'N': '110101101101101', 'O': '010101101101010',
    'P': '110101110100100', 'Q': '010101101110011', 'R': '110101110101101',
    'S': '011100010001110', 'T': '111010010010010', 'U': '101101101101111',
    'V': '101101101101010', 'W': '101101111111101', 'X': '101101010101101',
    'Y': '101101010010010', 'Z': '111001010100111',
    '0': '111101101101111', '1': '010110010010111', '2': '110001010100111',
    '3': '110001010001110', '4': '101101111001001', '5': '111100110001110',
    '6': '011100111101111', '7': '111001010010010', '8': '111101111101111',
    '9': '111101111001110', '$': '011110010011110', '.': '000000000000010',
    "'": '010010000000000', '+': '000010111010000', 'K_': '101110100110101',
    ' ': '000000000000000', '-': '000000111000000', 'x': '000101010101000',
    ',': '000000000010100', '!': '010010010000010', '?': '110001010000010',
    ':': '000010000010000', ';': '000010000010100', '(': '001010010010001',
    ')': '100010010010100', '/': '001001010100100', '&': '010101010101011',
    '"': '101101000000000', '%': '101001010100101', '#': '101111101111101',
}


def text(d: ImageDraw.ImageDraw, x: int, y: int, s: str, colour: str = 'ink') -> int:
    """Draw `s` in the 3x5 font; returns the width drawn."""
    cx = x
    for ch in s.upper():
        bits = FONT.get(ch, FONT[' '])
        for i, bit in enumerate(bits):
            if bit == '1':
                d.point((cx + i % 3, y + i // 3), fill=c(colour))
        cx += 4
    return cx - x - 1


# --------------------------------------------------------------- house ----

def house(night: bool = False, coat: bool = False):
    img, d = blank(50, 40)
    wall, wall_dark = ('hat', 'hat_dark') if coat else ('wood', 'wood_dark')
    d.rectangle([4, 16, 45, 37], fill=c(wall))  # log walls
    for y in range(18, 37, 3):
        d.line([4, y, 45, y], fill=c(wall_dark))
    d.polygon([(1, 17), (25, 3), (48, 17)], fill=c('roof'))  # roof
    d.line([1, 17, 48, 17], fill=c('roof_dark'))
    for y in range(8, 17, 3):
        d.line([25 - (y - 3) * 24 // 14, y, 25 + (y - 3) * 23 // 14, y], fill=c('roof_dark'))
    d.rectangle([34, 2, 38, 10], fill=c('stone'))  # chimney
    d.line([34, 2, 38, 2], fill=c('stone_dark'))
    d.point([(35, 5), (37, 7)], fill=c('stone_dark'))
    glass = 'window_lit' if night else 'window'
    for x in (8, 32):
        d.rectangle([x, 21, x + 7, 27], fill=c(glass))
        d.line([x + 3, 21, x + 3, 27], fill=c(wall_dark))
        d.line([x, 24, x + 7, 24], fill=c(wall_dark))
    d.rectangle([20, 22, 28, 37], fill=c('wood_dark'))  # door
    d.point((26, 30), fill=c('amber'))
    d.rectangle([2, 37, 47, 38], fill=c('wood_dark'))  # porch boards
    for x in (3, 46):
        d.line([x, 17, x, 37], fill=c('wood_dark'))  # porch posts
    return outline(img)


def smoke(beat: int):
    img, d = blank(10, 12)
    puffs = [(3, 9, 6, 11), (2, 5, 6, 8), (4, 1, 8, 4)]
    for i, box in enumerate(puffs):
        if (i + beat) % 3 != 2:
            d.ellipse(box, fill=c('smoke' if i % 2 else 'smoke_dark'))
    return img


# ---------------------------------------------------------------- still ----

def still(lit: bool = False, tarp: bool = False, keg: bool = False, worm: bool = False):
    img, d = blank(38, 34)
    if tarp:
        d.polygon([(1, 33), (4, 6), (33, 6), (36, 33)], fill=c('green_dark'))
        d.line([6, 14, 31, 14], fill=c('green'))
        d.line([5, 24, 32, 24], fill=c('green'))
        d.rectangle([10, 3, 26, 6], fill=c('green_dark'))
        return outline(img)
    d.ellipse([3, 5, 17, 13], fill=c('copper'))  # onion dome
    d.rectangle([8, 2, 12, 6], fill=c('copper_dark'))  # cap
    d.rectangle([2, 11, 18, 26], fill=c('copper'))  # pot
    d.line([4, 12, 4, 25], fill=c('fire_hot') if lit else c('copper_dark'))  # shine
    d.line([2, 26, 18, 26], fill=c('copper_dark'))
    d.rectangle([4, 27, 16, 29], fill=c('stone'))  # firebox
    d.line([12, 3, 27, 3], fill=c('copper_dark'))  # lyne arm
    d.line([27, 3, 27, 9], fill=c('copper_dark'))
    if keg:  # thump keg between the pot and the worm
        d.rectangle([20, 8, 25, 15], fill=c('wood'))
        d.line([20, 10, 25, 10], fill=c('steel'))
        d.line([20, 13, 25, 13], fill=c('steel'))
    d.rectangle([23, 10, 35, 27], fill=c('wood'))  # worm tub barrel
    for y in (12, 19, 25):
        d.line([23, y, 35, y], fill=c('steel'))
    coil = 'copper' if worm else 'copper_dark'
    for y in range(14, 25, 3):
        d.line([25, y, 33, y + 1], fill=c(coil))
    d.line([35, 24, 37, 26], fill=c('copper_dark'))  # spout
    d.rectangle([33, 28, 37, 33], fill=c('glass'))  # jar catching the run
    d.rectangle([33, 30, 37, 33], fill=c('amber'))
    return outline(img)


def fire(beat: int, lit: bool):
    img, d = blank(14, 6)
    if not lit:
        for x in (2, 5, 8, 11):
            d.point((x, 5), fill=c('amber_dark'))
        return img
    flames = [(1, 2), (4, 0), (7, 1), (10, 0)] if beat == 0 else [(1, 0), (4, 2), (7, 0), (10, 1)]
    for x, top in flames:
        d.polygon([(x, 5), (x + 1, top), (x + 3, 5)], fill=c('fire'))
        d.point((x + 1, min(5, top + 2)), fill=c('fire_hot'))
    return img


def steam(beat: int):
    img, d = blank(8, 8)
    y = 4 if beat == 0 else 1
    d.ellipse([1, y, 5, y + 3], fill=c('smoke'))
    d.ellipse([3, y - 1 if y else 0, 7, y + 2], fill=c('cloud'))
    return img


# ----------------------------------------------------------------- sign ----

def sign(night: bool = False, coat: bool = False):
    img, d = blank(46, 24)
    # A painted sign: cream boards, dark brown letters, a wooden frame.
    board, letters = ('white', 'red_dark') if coat else ('hat_light', 'band')
    if night:
        board = 'hat'  # the same sign under lantern light
    for x in (8, 36):
        d.rectangle([x, 13, x + 2, 23], fill=c('wood_dark'))  # posts
    d.rectangle([1, 1, 44, 14], fill=c(board))
    d.rectangle([1, 1, 44, 14], outline=c('wood_dark'))
    d.line([2, 12, 43, 12], fill=c('hat_dark'))  # board seam, below the letters
    width = len("JEB'S FARM") * 4 - 1
    text(d, 23 - width // 2, 5, "JEB'S FARM", letters)
    return outline(img)


# ---------------------------------------------------------------- truck ----

LOADS = ('empty', 'crate', 'jars', 'bales', 'apples', 'corn')


def truck(load: str = 'crate', beat: int = 0):
    img, d = blank(42, 22)
    d.rectangle([1, 9, 22, 16], fill=c('truck'))  # bed
    d.line([1, 9, 22, 9], fill=c('truck_dark'))
    d.rectangle([23, 3, 32, 16], fill=c('truck'))  # cab
    d.rectangle([25, 5, 31, 9], fill=c('glass'))  # window
    d.line([28, 5, 28, 9], fill=c('truck_dark'))
    d.rectangle([33, 9, 39, 16], fill=c('truck'))  # hood
    d.line([33, 9, 39, 9], fill=c('truck_dark'))
    d.rectangle([39, 10, 40, 15], fill=c('chrome'))  # grille
    d.point((40, 11), fill=c('fire_hot'))  # headlight
    d.line([1, 14, 40, 14], fill=c('truck_dark'))
    d.rectangle([0, 15, 41, 16], fill=c('chrome'))  # bumpers
    for x in (8, 33):
        d.ellipse([x - 4, 13, x + 4, 21], fill=c('tire'))
        d.ellipse([x - 2, 15, x + 2, 19], fill=c('steel'))
        d.point((x, 15 if beat == 0 else 19), fill=c('tire'))
    if load == 'crate':
        d.rectangle([4, 2, 18, 8], fill=c('wood'))
        d.line([4, 5, 18, 5], fill=c('wood_dark'))
        d.line([11, 2, 11, 8], fill=c('wood_dark'))
    elif load == 'jars':
        for x in (3, 9, 15):
            d.rectangle([x, 3, x + 4, 8], fill=c('glass'))
            d.rectangle([x, 5, x + 4, 8], fill=c('amber'))
            d.line([x, 3, x + 4, 3], fill=c('steel'))
    elif load == 'bales':
        for x in (3, 12):
            d.rectangle([x, 3, x + 7, 8], fill=c('leaf_dry'))
            d.line([x + 2, 3, x + 2, 8], fill=c('wood_dark'))
            d.line([x + 5, 3, x + 5, 8], fill=c('wood_dark'))
    elif load == 'apples':
        d.rectangle([4, 4, 18, 8], fill=c('wood'))
        for x in range(5, 18, 3):
            d.ellipse([x, 2, x + 2, 4], fill=c('red'))
    elif load == 'corn':
        for x in range(3, 20, 4):
            d.rectangle([x, 3, x + 2, 8], fill=c('corn'))
            d.point((x + 1, 2), fill=c('green'))
    return outline(img)


def vehicle(kind: str, beat: int = 0):
    """The visitors' rigs, facing right (the renderer flips them for the way back)."""
    img, d = blank(40, 20)
    def wheels(xs, r=4, y=15):
        for x in xs:
            d.ellipse([x - r, y - r, x + r, y + r], fill=c('tire'))
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=c('steel'))
            d.point((x, y - 2 if beat == 0 else y + 2), fill=c('tire'))
    if kind == 'store':  # Tolliver's red delivery truck, box body with a sign
        d.rectangle([1, 2, 25, 14], fill=c('red'))
        d.rectangle([3, 4, 23, 8], fill=c('cow_white'))
        d.line([4, 6, 22, 6], fill=c('red_dark'))
        d.rectangle([26, 6, 34, 14], fill=c('red'))
        d.rectangle([28, 7, 33, 10], fill=c('glass'))
        d.rectangle([34, 9, 38, 14], fill=c('red_dark'))
        d.point((38, 10), fill=c('fire_hot'))
        d.rectangle([0, 13, 39, 14], fill=c('chrome'))
        wheels((8, 31))
    elif kind == 'mill':  # feed mill flatbed with sacks
        d.rectangle([1, 10, 25, 13], fill=c('wood'))
        for x in (3, 9, 15, 21):
            d.rectangle([x, 5, x + 4, 9], fill=c('white'))
            d.line([x + 1, 5, x + 3, 5], fill=c('stone'))
        d.rectangle([26, 4, 34, 13], fill=c('stone_dark'))
        d.rectangle([28, 5, 33, 8], fill=c('glass'))
        d.rectangle([34, 8, 38, 13], fill=c('grey'))
        d.point((38, 9), fill=c('fire_hot'))
        wheels((8, 31))
    elif kind == 'mail':  # mail carrier's jeep
        d.rectangle([8, 6, 30, 13], fill=c('white'))
        d.line([8, 10, 30, 10], fill=c('denim'))
        d.line([8, 11, 30, 11], fill=c('red'))
        d.rectangle([12, 2, 24, 6], fill=c('white'))
        d.rectangle([14, 3, 18, 5], fill=c('glass'))
        d.rectangle([20, 3, 23, 5], fill=c('glass'))
        d.point((30, 7), fill=c('fire_hot'))
        wheels((13, 26), r=3, y=15)
    elif kind == 'tractor':  # neighbour's old green tractor
        d.rectangle([12, 6, 30, 11], fill=c('green_dark'))
        d.rectangle([26, 3, 27, 6], fill=c('steel'))  # exhaust stack
        d.rectangle([8, 1, 15, 6], fill=c('green_dark'))  # seat and fender
        d.point((10, 0), fill=c('hat'))  # farmer's straw hat
        d.rectangle([9, 1, 11, 3], fill=c('skin'))
        d.ellipse([3, 6, 17, 19], fill=c('tire'))  # big rear wheel
        d.ellipse([7, 10, 13, 16], fill=c('yellow'))
        d.point((10, 9 if beat == 0 else 16), fill=c('tire'))
        d.ellipse([25, 12, 31, 18], fill=c('tire'))
        d.ellipse([27, 14, 29, 16], fill=c('yellow'))
    elif kind == 'tripper':  # the night buyer's dark coupe, lights low
        d.rectangle([2, 7, 36, 13], fill=c('ridge_mid_night'))
        d.rectangle([10, 2, 26, 7], fill=c('ridge_mid_night'))
        d.rectangle([12, 3, 17, 6], fill=c('glass_edge'))
        d.rectangle([19, 3, 24, 6], fill=c('glass_edge'))
        d.line([2, 11, 36, 11], fill=c('chrome'))
        d.point((36, 8), fill=c('amber_dark'))
        wheels((9, 29))
    return outline(img)


def dust(beat: int):
    img, d = blank(10, 6)
    if beat == 0:
        d.ellipse([4, 1, 9, 5], fill=c('road'))
        d.ellipse([0, 3, 4, 6], fill=c('road_dark'))
    else:
        d.ellipse([2, 0, 7, 4], fill=c('road_dark'))
    return img


# ---------------------------------------------------------------- crops ----

def tobacco(stage: int):
    img, d = blank(6, 18)
    d.rectangle([0, 16, 5, 17], fill=c('soil_dark'))  # hill
    if stage == 0:
        return img
    if stage == 1:
        d.point([(2, 15), (3, 15), (1, 14), (4, 14)], fill=c('leaf'))
        return img
    # Burley: a stalk with broad, drooping leaves stacked up it.
    top = 9 if stage == 2 else 3
    d.line([2, top, 2, 15], fill=c('green_dark'))
    for i, y in enumerate(range(15, top, -3)):
        left = i % 2 == 0
        box = [0, y - 2, 3, y] if left else [2, y - 3, 5, y - 1]
        d.ellipse(box, fill=c('green' if i == 0 else 'leaf'))
        d.point((1 if left else 4, y - 1 if left else y - 2), fill=c('green_dark'))
    if stage == 3:
        d.point([(2, 1), (1, 2), (3, 2), (2, 2)], fill=c('pink'))  # flower head
    return img


def corn(stage: int):
    img, d = blank(6, 20)
    d.rectangle([0, 18, 5, 19], fill=c('soil_dark'))
    if stage == 0:
        return img
    if stage == 1:
        d.line([2, 15, 2, 17], fill=c('green'))
        d.point((3, 15), fill=c('green'))
        return img
    top = 9 if stage == 2 else 1
    d.line([2, top, 2, 17], fill=c('green_dark'))
    for y in range(top + 3, 17, 4):
        d.line([2, y, 0, y + 2], fill=c('green'))
        d.line([3, y - 1, 5, y + 1], fill=c('green'))
    if stage == 3:
        d.rectangle([3, 7, 4, 11], fill=c('corn'))  # ear
        d.point([(1, 0), (2, 0), (3, 0)], fill=c('hat_light'))  # tassel
    return img


def apple_tree(stage: int, pumpkin: bool = False):
    img, d = blank(10, 20)
    d.rectangle([2, 18, 7, 19], fill=c('soil_dark'))
    if stage == 0:
        d.line([4, 14, 4, 17], fill=c('wood_dark'))
        d.point([(3, 14), (5, 13)], fill=c('leaf'))
        return img
    top = 8 if stage == 1 else 2
    d.rectangle([4, 12, 5, 17], fill=c('wood_dark'))
    d.ellipse([0, top, 9, 14], fill=c('green'))
    d.point([(2, top + 3), (6, top + 2), (4, top + 7)], fill=c('green_dark'))
    if stage == 3:
        for p in ((2, top + 5), (6, top + 4), (4, top + 2), (7, top + 8), (1, top + 8)):
            d.point(p, fill=c('red'))
    if pumpkin:
        d.ellipse([5, 15, 9, 19], fill=c('amber'))
        d.point((7, 14), fill=c('green_dark'))
    return img


# ---------------------------------------------------------- stack icons ----

def icon(kind: str):
    img, d = blank(8, 8)
    if kind == 'lumber':
        d.rectangle([0, 2, 7, 6], fill=c('wood'))
        d.ellipse([0, 2, 3, 6], fill=c('hat_light'))
        d.point((1, 4), fill=c('wood_dark'))
    elif kind == 'stone':
        d.ellipse([0, 2, 7, 7], fill=c('stone'))
        d.point([(2, 4), (5, 3)], fill=c('stone_dark'))
    elif kind == 'straw':
        for x in range(1, 7, 2):
            d.line([x, 1, x + 1, 7], fill=c('hat'))
        d.line([0, 4, 7, 4], fill=c('band'))
    elif kind == 'iron':
        d.rectangle([3, 0, 4, 7], fill=c('steel'))
        d.rectangle([1, 0, 6, 1], fill=c('steel'))
    elif kind == 'sugar':
        d.rectangle([1, 2, 6, 7], fill=c('white'))
        d.line([2, 1, 5, 1], fill=c('white'))
        d.point((3, 4), fill=c('stone'))
    elif kind == 'copper':
        d.polygon([(1, 6), (2, 2), (7, 2), (6, 6)], fill=c('copper'))
        d.line([2, 3, 6, 3], fill=c('fire_hot'))
    elif kind == 'apple_butter':
        d.rectangle([1, 2, 6, 7], fill=c('wood_dark'))
        d.rectangle([1, 1, 6, 2], fill=c('hat_light'))
    elif kind == 'twist':
        d.line([1, 7, 6, 0], fill=c('leaf_dry'), width=2)
        d.point([(2, 4), (4, 2)], fill=c('wood_dark'))
    elif kind == 'whiskey':
        d.rectangle([1, 1, 6, 7], fill=c('glass'))
        d.rectangle([1, 3, 6, 7], fill=c('amber_dark'))
    elif kind == 'jar':
        d.rectangle([1, 1, 6, 7], fill=c('glass'))
        d.rectangle([1, 3, 6, 7], fill=c('amber'))
        d.line([1, 1, 6, 1], fill=c('steel'))
    elif kind == 'bale':
        d.rectangle([0, 2, 7, 7], fill=c('leaf_dry'))
        d.line([2, 2, 2, 7], fill=c('wood_dark'))
        d.line([5, 2, 5, 7], fill=c('wood_dark'))
    elif kind == 'apples':
        d.rectangle([0, 4, 7, 7], fill=c('wood'))
        for x in (1, 3, 5):
            d.ellipse([x, 2, x + 2, 4], fill=c('red'))
    elif kind == 'corn':
        d.rectangle([2, 1, 5, 7], fill=c('corn'))
        d.line([1, 3, 1, 7], fill=c('green'))
    elif kind == 'cash':
        d.rectangle([0, 2, 7, 6], fill=c('green'))
        d.point([(3, 4), (4, 4)], fill=c('green_dark'))
    return outline(img) if kind != 'cash' else img


ICONS = ('lumber', 'stone', 'straw', 'iron', 'sugar', 'copper', 'apple_butter',
         'twist', 'whiskey', 'jar', 'bale', 'apples', 'corn', 'cash')

QUILT = {'B': 'denim', 'R': 'red', 'G': 'green', 'P': 'purple', 'Y': 'yellow', 'N': 'soil'}


def quilt_square(code: str):
    img, d = blank(5, 5)
    d.rectangle([0, 0, 4, 4], fill=c(QUILT[code]))
    d.point([(0, 0), (4, 4)], fill=c('white'))  # stitch corners
    return img


def lantern(beat: int):
    img, d = blank(5, 8)
    d.line([2, 0, 2, 1], fill=c('steel'))
    d.rectangle([1, 2, 3, 6], fill=c('fire_hot' if beat == 0 else 'fire'))
    d.rectangle([0, 2, 4, 2], fill=c('steel'))
    d.rectangle([0, 7, 4, 7], fill=c('steel'))
    return img


# ------------------------------------------------------------- sky etc ----

def sun():
    img, d = blank(9, 9)
    d.ellipse([1, 1, 7, 7], fill=c('yellow'))
    d.point([(4, 0), (0, 4), (8, 4), (4, 8)], fill=c('yellow'))
    return img


def moon(phase: int):
    """phase 0..7: new, waxing crescent ... waning crescent."""
    img, d = blank(9, 9)
    d.ellipse([0, 0, 8, 8], fill=c('moon'))
    shadow = {0: (0, 0, 8, 8), 1: (-3, 0, 5, 8), 2: (-8, 0, 4, 8), 3: (-12, 0, 2, 8),
              4: None, 5: (6, 0, 20, 8), 6: (4, 0, 16, 8), 7: (3, 0, 11, 8)}[phase]
    if shadow:
        d.ellipse(shadow, fill=(0, 0, 0, 0)) if phase else d.ellipse(shadow, fill=c('grey'))
    return img


def cloud(dark: bool = False):
    img, d = blank(22, 9)
    fill = c('smoke_dark' if dark else 'cloud')
    for box in ((1, 3, 9, 8), (6, 0, 15, 8), (12, 2, 21, 8)):
        d.ellipse(box, fill=fill)
    return img


def overlay(kind: str, beat: int = 0):
    if kind == 'note':  # cream, so it shows on a dark terminal
        img, d = blank(4, 6)
        d.rectangle([0, 4, 1, 5], fill=c('hat_light'))
        d.line([1, 0, 1, 4], fill=c('hat_light'))
        d.point((2, 0), fill=c('hat_light'))
        d.point((3, 1), fill=c('hat_light'))
    elif kind == 'zz':
        img, d = blank(8, 8)
        for (x, y, s) in ((0, 4, 3), (4, 0, 2)) if beat == 0 else ((1, 3, 3), (5, 0, 2)):
            d.line([x, y, x + s, y], fill=c('white'))
            d.line([x + s, y, x, y + s], fill=c('white'))
            d.line([x, y + s, x + s, y + s], fill=c('white'))
    elif kind == 'bang':
        img, d = blank(3, 7)
        d.rectangle([1, 0, 1, 4], fill=c('red'))
        d.point((1, 6), fill=c('red'))
    elif kind == 'ask':
        img, d = blank(4, 7)
        d.line([0, 0, 2, 0], fill=c('white'))
        d.point([(3, 1), (2, 2), (1, 3), (1, 4), (1, 6)], fill=c('white'))
    elif kind == 'sweat':
        img, d = blank(3, 4)
        d.ellipse([0, 1, 2, 3], fill=c('drop'))
        d.point((1, 0), fill=c('drop'))
    elif kind == 'heart':
        img, d = blank(5, 5)
        d.point([(1, 0), (3, 0)], fill=c('red'))
        d.rectangle([0, 1, 4, 2], fill=c('red'))
        d.polygon([(0, 2), (4, 2), (2, 4)], fill=c('red'))
    elif kind == 'firefly':
        img, d = blank(3, 3)
        d.point((1, 1), fill=c('fire_hot' if beat == 0 else 'yellow'))
        if beat == 0:
            d.point([(0, 1), (2, 1), (1, 0), (1, 2)], fill=c('yellow'))
    elif kind == 'mothman':
        img, d = blank(7, 3)
        d.rectangle([0, 1, 1, 2], fill=c('red'))
        d.rectangle([5, 1, 6, 2], fill=c('red'))
    else:
        raise ValueError(kind)
    return img


# ---------------------------------------------------------------- props ----

def prop(kind: str):
    if kind == 'mailbox':
        img, d = blank(8, 12)
        d.line([3, 5, 3, 11], fill=c('wood_dark'))
        d.rectangle([0, 1, 6, 5], fill=c('steel'))
        d.rectangle([6, 0, 7, 2], fill=c('red'))  # flag
    elif kind == 'chair':
        img, d = blank(10, 14)
        d.rectangle([1, 0, 3, 9], fill=c('wood'))
        d.rectangle([1, 7, 8, 9], fill=c('wood'))
        d.arc([0, 9, 9, 15], 180, 360, fill=c('wood_dark'))
    elif kind == 'smokehouse':
        img, d = blank(18, 20)
        d.rectangle([2, 7, 15, 19], fill=c('wood_dark'))
        d.polygon([(0, 8), (9, 1), (17, 8)], fill=c('roof'))
        d.rectangle([7, 12, 10, 19], fill=c('soil_dark'))
    elif kind == 'keg':
        img, d = blank(8, 10)
        d.rectangle([1, 1, 6, 9], fill=c('wood'))
        d.line([1, 3, 6, 3], fill=c('steel'))
        d.line([1, 7, 6, 7], fill=c('steel'))
    elif kind == 'xmas':
        img, d = blank(12, 18)
        d.polygon([(6, 0), (11, 14), (0, 14)], fill=c('green_dark'))
        d.rectangle([5, 14, 6, 17], fill=c('wood_dark'))
        for p in ((6, 3), (4, 8), (8, 10), (3, 12), (7, 6)):
            d.point(p, fill=c('red' if p[0] % 2 else 'yellow'))
    elif kind == 'pumpkin':
        img, d = blank(8, 7)
        d.ellipse([0, 1, 7, 6], fill=c('amber'))
        d.line([3, 1, 3, 6], fill=c('amber_dark'))
        d.point((4, 0), fill=c('green_dark'))
    elif kind == 'bell':
        img, d = blank(7, 8)
        d.polygon([(1, 6), (3, 0), (5, 0), (6, 6)], fill=c('yellow'))
        d.point((3, 7), fill=c('amber_dark'))
    elif kind == 'gate':
        img, d = blank(14, 9)
        d.rectangle([0, 0, 13, 3], fill=c('white'))
        for x in (1, 6, 11):
            d.line([x, 0, x + 2, 3], fill=c('red'))
        d.line([2, 4, 2, 8], fill=c('steel'))
        d.line([11, 4, 11, 8], fill=c('steel'))
    elif kind == 'fence':
        img, d = blank(8, 7)
        for x in (0, 7):
            d.line([x, 0, x, 6], fill=c('wood_dark'))
        d.line([0, 2, 7, 2], fill=c('wood'))
        d.line([0, 5, 7, 5], fill=c('wood'))
    elif kind == 'parachute':
        img, d = blank(11, 14)
        d.chord([0, 0, 10, 8], 180, 360, fill=c('red'))
        d.line([0, 4, 5, 11], fill=c('ink'))
        d.line([10, 4, 5, 11], fill=c('ink'))
        d.rectangle([4, 11, 6, 13], fill=c('denim'))
    else:
        raise ValueError(kind)
    return outline(img)


PROPS = ('mailbox', 'chair', 'smokehouse', 'keg', 'xmas', 'pumpkin', 'bell', 'gate', 'fence', 'parachute')


def farm_sprites() -> list[Sprite]:
    out = [
        Sprite('house', [house()]),
        Sprite('house-night', [house(night=True)]),
        Sprite('house-coat', [house(coat=True)]),
        Sprite('house-coat-night', [house(night=True, coat=True)]),
        Sprite('smoke', [smoke(0), smoke(1), smoke(2)], [400, 400, 400]),
        Sprite('still', [still()]),
        Sprite('still-keg', [still(keg=True)]),
        Sprite('still-worm', [still(keg=True, worm=True)]),
        Sprite('still-tarp', [still(tarp=True)]),
        Sprite('fire', [fire(0, True), fire(1, True)], [160, 160]),
        Sprite('embers', [fire(0, False)]),
        Sprite('steam', [steam(0), steam(1)], [300, 300]),
        Sprite('sign', [sign()]),
        Sprite('sign-night', [sign(night=True)]),
        Sprite('sign-coat', [sign(coat=True)]),
        Sprite('dust', [dust(0), dust(1)], [120, 120]),
        Sprite('rig-store', [vehicle('store', 0), vehicle('store', 1)], [120, 120]),
        Sprite('rig-mill', [vehicle('mill', 0), vehicle('mill', 1)], [120, 120]),
        Sprite('rig-mail', [vehicle('mail', 0), vehicle('mail', 1)], [120, 120]),
        Sprite('rig-tractor', [vehicle('tractor', 0), vehicle('tractor', 1)], [260, 260]),
        Sprite('rig-tripper', [vehicle('tripper', 0), vehicle('tripper', 1)], [120, 120]),
        Sprite('sun', [sun()]),
        Sprite('moon', [moon(p) for p in range(8)], [300] * 8),
        Sprite('cloud', [cloud()]),
        Sprite('cloud-dark', [cloud(True)]),
        Sprite('lantern', [lantern(0), lantern(1)], [500, 500]),
        Sprite('note', [overlay('note')]),
        Sprite('zz', [overlay('zz', 0), overlay('zz', 1)], [500, 500]),
        Sprite('bang', [overlay('bang')]),
        Sprite('ask', [overlay('ask')]),
        Sprite('sweat', [overlay('sweat')]),
        Sprite('heart', [overlay('heart')]),
        Sprite('firefly', [overlay('firefly', 0), overlay('firefly', 1)], [300, 300]),
        Sprite('mothman', [overlay('mothman')]),
    ]
    for load in LOADS:
        out.append(Sprite(f'truck-{load}', [truck(load, 0), truck(load, 1)], [110, 110]))
    out += [Sprite(f'tobacco-{s}', [tobacco(s)]) for s in range(4)]
    out += [Sprite(f'corn-{s}', [corn(s)]) for s in range(4)]
    out += [Sprite(f'apple-{s}', [apple_tree(s)]) for s in range(4)]
    out.append(Sprite('apple-pumpkin', [apple_tree(3, pumpkin=True)]))
    out += [Sprite(f'icon-{k}', [icon(k)]) for k in ICONS]
    out += [Sprite(f'quilt-{k}', [quilt_square(k)]) for k in QUILT]
    out += [Sprite(f'prop-{k}', [prop(k)]) for k in PROPS]
    return out
