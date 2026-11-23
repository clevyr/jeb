// Nature: the little things around the farm (nature.py): wildlife, seasons, Jeb's daily rhythm and homestead details.
// Same palette, 1px ink outline on the solid things, band scale (ground at y 39 of 48).
import Foundation

private func c(_ name: String) -> RGBA { rgb(name) }

func birdhouseSprite() -> Raster {
    let d = Raster(7, 9)
    d.rectangle(1, 4, 5, 7, fill: c("wood"))
    d.polygon([(1, 4), (3, 1), (5, 4)], fill: c("roof"))
    d.point(3, 6, fill: c("ink"))
    return outline(d)
}

func bluebirdSprite(_ beat: Int) -> Raster {
    let d = Raster(7, 5)
    d.rectangle(1, 1, 4, 3, fill: c("bluebird"))
    d.rectangle(4, 0, 5, 2, fill: c("bluebird"))
    d.point(2, 3, fill: c("amber"))
    d.point(3, 3, fill: c("amber"))
    d.point(0, beat != 0 ? 2 : 3, fill: c("bluebird"))
    outline(d)
    d[6, 1] = c("amber")
    d[5, 1] = beat != 0 ? c("white") : c("ink")
    return d
}

func cardinalSprite() -> Raster {
    let d = Raster(8, 7)
    d.rectangle(1, 2, 5, 5, fill: c("red"))
    d.rectangle(4, 1, 6, 3, fill: c("red"))
    d.point(5, 0, fill: c("red"))
    d.point(1, 5, fill: c("red_dark"))
    d.point(2, 5, fill: c("red_dark"))
    outline(d)
    d[7, 2] = c("amber")
    d[6, 2] = c("amber")
    d[5, 2] = c("ink")
    return d
}

func owlSprite(blink: Bool) -> Raster {
    let d = Raster(9, 11)
    d.rectangle(1, 2, 7, 9, fill: c("owl_brown"))
    d.rectangle(3, 6, 5, 9, fill: c("owl_cream"))
    d.points([(1, 1), (7, 1)], fill: c("owl_brown"))
    outline(d)
    if blink {
        d.line(2, 4, 3, 4, fill: c("ink"))
        d.line(5, 4, 6, 4, fill: c("ink"))
    } else {
        d.rectangle(2, 3, 3, 5, fill: c("white"))
        d.rectangle(5, 3, 6, 5, fill: c("white"))
        d.points([(3, 4), (5, 4)], fill: c("ink"))
    }
    d.point(4, 5, fill: c("amber"))
    return d
}

func butterflySprite(_ beat: Int) -> Raster {
    let d = Raster(6, 5)
    if beat == 0 {
        d.rectangle(0, 0, 2, 2, fill: c("amber"))
        d.rectangle(3, 0, 5, 2, fill: c("amber"))
        d.rectangle(0, 3, 1, 4, fill: c("yellow"))
        d.rectangle(4, 3, 5, 4, fill: c("yellow"))
        d.points([(1, 1), (4, 1)], fill: c("pink"))
    } else {
        d.rectangle(1, 0, 2, 3, fill: c("amber"))
        d.rectangle(3, 0, 4, 3, fill: c("yellow"))
    }
    d.line(2, 1, 3, 1, fill: c("ink"))
    d.line(2, 1, 2, 4, fill: c("ink"))
    d.line(3, 1, 3, 4, fill: c("ink"))
    return d
}

func deerSprite() -> Raster {
    let d = Raster(15, 14)
    d.rectangle(3, 5, 10, 9, fill: c("deer_tan"))
    d.rectangle(4, 9, 9, 9, fill: c("deer_light"))
    for x in [4, 5, 8, 9] { d.line(x, 10, x, 12, fill: c("deer_tan")) }
    d.rectangle(10, 3, 11, 6, fill: c("deer_tan"))
    d.rectangle(11, 1, 13, 3, fill: c("deer_tan"))
    d.points([(11, 0), (13, 0)], fill: c("deer_tan"))
    d.line(2, 5, 2, 6, fill: c("white"))
    outline(d)
    d[13, 2] = c("ink")
    d[14, 3] = c("nose")
    return d
}

func creekSprite(_ beat: Int) -> Raster {
    let d = Raster(12, 3)
    d.rectangle(0, 0, 11, 2, fill: c("water"))
    for x in beat == 0 ? [1, 5, 9] : [3, 7] { d.line(x, 1, x + 1, 1, fill: c("water_light")) }
    d.points([(0, 0), (11, 0)], fill: c("soil_dark"))
    d.points([(0, 2), (11, 2)], fill: c("soil_dark"))
    return d
}

func fisherSprite(_ beat: Int) -> Raster {
    let d = Raster(11, 13)
    d.rectangle(2, 0, 5, 1, fill: c("hat"))
    d.rectangle(1, 2, 6, 2, fill: c("hat_dark"))
    d.rectangle(2, 3, 5, 5, fill: c("skin"))
    d.rectangle(2, 5, 5, 6, fill: c("beard"))
    d.rectangle(1, 7, 6, 9, fill: c("shirt"))
    d.rectangle(2, 10, 5, 11, fill: c("denim"))
    d.rectangle(2, 12, 5, 12, fill: c("boot"))
    outline(d)
    d.line(6, 8, 10, 3, fill: c("wood_dark"))
    d.line(10, 3, 10, 10 + beat, fill: c("white"))
    d.point(10, 11 + beat, fill: c("red"))
    return d
}

func woodpileSprite(_ level: Int) -> Raster {
    let d = Raster(14, 11)
    for r in 0..<max(level, 0) {
        let y = 9 - 2 * r
        for k in 0..<(r % 2 == 0 ? 4 : 3) {
            let x = 1 + 3 * k + (r % 2 == 0 ? 0 : 1)
            d.rectangle(x, y, x + 2, y + 1, fill: c("wood"))
            d.point(x, y, fill: c("hat_light"))
        }
    }
    return outline(d)
}

func axeStumpSprite(_ beat: Int) -> Raster {
    let d = Raster(8, 11)
    d.rectangle(1, 7, 5, 10, fill: c("wood"))
    d.rectangle(1, 6, 5, 7, fill: c("hat_light"))
    outline(d)
    d.line(3, 6, 5, 2, fill: c("wood_dark"))
    d.rectangle(4, 0, 6, 2, fill: c("steel"))
    if beat != 0 { d.points([(0, 3), (7, 5), (1, 1)], fill: c("hat_light")) }
    return d
}

func gardenSprite(_ stage: Int) -> Raster {
    let d = Raster(10, 15)
    d.rectangle(0, 13, 9, 14, fill: c("soil_dark"))
    d.line(1, 7, 1, 13, fill: c("wood_dark"))
    d.line(4, 7, 4, 13, fill: c("wood_dark"))
    if stage >= 1 { d.points([(2, 12), (6, 12), (7, 11)], fill: c("leaf")) }
    if stage >= 2 {
        d.rectangle(1, 9, 4, 12, fill: c("green"))
        d.line(7, 7, 7, 12, fill: c("green_dark"))
        d.points([(6, 9), (8, 10)], fill: c("green"))
    }
    if stage >= 3 {
        d.line(7, 3, 7, 12, fill: c("green_dark"))
        d.rectangle(5, 0, 9, 4, fill: c("yellow"))
        d.rectangle(6, 1, 8, 3, fill: c("soil_dark"))
        d.points([(2, 10), (3, 11), (1, 12)], fill: c("red"))
    }
    return d
}

func porchLightSprite() -> Raster {
    let d = Raster(5, 8)
    d.line(0, 0, 0, 1, fill: c("steel"))
    d.rectangle(1, 1, 3, 2, fill: c("steel"))
    d.rectangle(1, 3, 3, 5, fill: c("fire_hot"))
    d.points([(0, 4), (4, 4), (2, 6), (0, 6), (4, 6)], fill: c("amber"))
    return d
}

func mugSprite(_ beat: Int) -> Raster {
    let d = Raster(6, 7)
    d.rectangle(1, 3, 4, 6, fill: c("white"))
    d.points([(5, 4), (5, 5)], fill: c("white"))
    d.line(1, 3, 4, 3, fill: c("band"))
    outline(d)
    d[2, beat == 0 ? 0 : 1] = c("smoke")
    d[3, beat == 0 ? 1 : 0] = c("smoke")
    return d
}

func lunchSprite() -> Raster {
    let d = Raster(9, 6)
    d.rectangle(0, 4, 8, 5, fill: c("white"))
    d.ellipse(1, 0, 7, 4, fill: c("hat"))
    d.points([(3, 1), (5, 2), (2, 2)], fill: c("red"))
    return outline(d)
}

func hatFeatherSprite() -> Raster {
    let d = Raster(5, 6)
    d.line(0, 5, 3, 1, fill: c("red"))
    d.line(1, 5, 4, 2, fill: c("red_dark"))
    d.points([(3, 0), (4, 1)], fill: c("white"))
    return d
}

func laundrySprite(_ kind: String) -> Raster {
    switch kind {
    case "shirt":
        let d = Raster(6, 7)
        d.rectangle(1, 1, 4, 6, fill: c("shirt"))
        d.rectangle(0, 1, 0, 3, fill: c("shirt_dark"))
        d.rectangle(5, 1, 5, 3, fill: c("shirt_dark"))
        d.points([(2, 0), (3, 0)], fill: c("white"))
        return d
    case "overalls":
        let d = Raster(6, 8)
        d.rectangle(1, 1, 4, 3, fill: c("denim"))
        d.rectangle(1, 4, 2, 7, fill: c("denim_dark"))
        d.rectangle(3, 4, 4, 7, fill: c("denim_dark"))
        d.points([(1, 0), (4, 0)], fill: c("white"))
        return d
    default:
        let d = Raster(8, 5)
        d.rectangle(0, 1, 7, 4, fill: c("white"))
        d.line(0, 4, 7, 4, fill: c("cloud"))
        d.points([(1, 0), (6, 0)], fill: c("hat_light"))
        return d
    }
}

func postcardSprite() -> Raster {
    let d = Raster(7, 6)
    d.rectangle(1, 1, 5, 4, fill: c("white"))
    d.point(5, 1, fill: c("red"))
    d.line(2, 3, 4, 3, fill: c("denim"))
    return outline(d)
}

func cakeSprite(_ beat: Int) -> Raster {
    let d = Raster(9, 10)
    d.rectangle(1, 6, 7, 8, fill: c("hat_light"))
    d.rectangle(1, 5, 7, 6, fill: c("pink"))
    d.line(4, 3, 4, 4, fill: c("red"))
    outline(d)
    d[4, 2] = beat == 0 ? c("fire") : c("fire_hot")
    return d
}

func rainbowSprite() -> Raster {
    let d = Raster(32, 14)
    for (i, name) in ["red", "amber", "yellow", "green", "drop", "purple"].enumerated() {
        d.arc(i, i, 31 - i, 27 - i, start: 180, end: 360, fill: c(name), width: 1)
    }
    d.ellipse(0, 10, 5, 13, fill: c("cloud"))
    d.ellipse(26, 10, 31, 13, fill: c("cloud"))
    return d
}

func puddleSprite() -> Raster {
    let d = Raster(9, 2)
    d.line(1, 0, 7, 0, fill: c("water"))
    d.line(0, 1, 8, 1, fill: c("water"))
    d.points([(3, 0), (4, 0)], fill: c("water_light"))
    return d
}

func starStreakSprite() -> Raster {
    let d = Raster(8, 4)
    d.points([(7, 0), (6, 0)], fill: c("white"))
    d.points([(5, 1), (4, 1)], fill: c("night_star"))
    d.points([(3, 2), (2, 2)], fill: c("night_star"))
    d.points([(1, 3)], fill: c("smoke_dark"))
    return d
}

func driftLeafSprite(_ tint: String) -> Raster {
    let d = Raster(3, 3)
    d.points([(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)], fill: c(tint))
    return d
}

func driftFlakeSprite() -> Raster {
    let d = Raster(3, 3)
    d.points([(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)], fill: c("white"))
    return d
}

/// A holiday badge for the desktop banner's tab row: the picture in `rows` ('.' clear, at most 7x7) inside an ink outline.
func badgeSprite(_ rows: [String], _ legend: [Character: String]) -> Raster {
    let d = Raster(rows[0].count + 2, rows.count + 2)
    for (y, row) in rows.enumerated() {
        for (x, ch) in row.enumerated() where ch != "." {
            d.point(x + 1, y + 1, fill: c(legend[ch]!))
        }
    }
    return outline(d)
}

/// One 9x9-or-smaller picture per holiday (Holiday.names): firework, heart, shamrock, egg, flag, pumpkin, turkey, holly.
/// No sacred text or figures, no animals. In nature.py's order.
let badgePictures: [(name: String, rows: [String], legend: [Character: String])] = [
    ("newyear", ["...y...", ".f.y.f.", "..fyf..", "yyywyyy", "..fyf..", ".f.y.f.", "...y..."], ["y": "yellow", "f": "fire", "w": "white"]),
    ("valentines", [".pp.pp.", "pwppppp", "ppppppr", ".ppppr.", "..prr..", "...r..."], ["p": "pink", "w": "white", "r": "red"]),
    ("stpatricks", [".gg.gg.", "glggggg", ".ggggg.", "..ggg..", "...s...", "...s..."], ["g": "green", "l": "leaf", "s": "green_dark"]),
    ("easter", ["..ppp..", ".ppppp.", ".pwppp.", "ppppppp", "yyyyyyy", "ppppppp", ".ppppp."], ["p": "pink", "y": "yellow", "w": "white"]),
    ("july4", ["pDwDwww", "pwDwrrr", "pDwDwww", "prrrrrr", "pwwwwww", "p......", "p......"], ["p": "tan", "D": "water", "r": "red", "w": "white"]),
    ("halloween", ["...s...", ".fffff.", "fffffff", "fiffifi", "fffffff", "fiiiiif", ".fffff."], ["s": "green_dark", "f": "fire", "i": "ink"]),
    ("thanksgiving", [".rfyfr.", "rfyyyfr", "fyyyyyf", ".ooooo.", ".ooeoo.", "..oro..", "..a.a.."], ["r": "red", "f": "fire", "y": "yellow", "o": "tan", "e": "ink", "a": "amber"]),
    ("christmas", [".gg.gg.", "gGgggGg", ".ggGgg.", "..rrr..", "..rwr..", "...r..."], ["g": "green", "G": "green_dark", "r": "red", "w": "white"]),
]

private func sprite(_ name: String, _ frames: [Raster], _ ms: [Int] = []) -> Sprite {
    Sprite(name: name, frames: frames, ms: ms)
}

func unlockSprites() -> [Sprite] {
    var out: [Sprite] = [
        sprite("birdhouse", [birdhouseSprite()]),
        sprite("bluebird", [bluebirdSprite(0), bluebirdSprite(1)], [400, 400]),
        sprite("cardinal", [cardinalSprite()]),
        sprite("owl", [owlSprite(blink: false), owlSprite(blink: true)], [900, 150]),
        sprite("butterfly", [butterflySprite(0), butterflySprite(1)], [180, 180]),
        sprite("deer", [deerSprite()]),
        sprite("creek", [creekSprite(0), creekSprite(1)], [500, 500]),
        sprite("fisher", [fisherSprite(0), fisherSprite(1)], [600, 600]),
        sprite("axe-stump", [axeStumpSprite(0), axeStumpSprite(1)], [900, 150]),
        sprite("porch-light", [porchLightSprite()]),
        sprite("mug", [mugSprite(0), mugSprite(1)], [400, 400]),
        sprite("lunch", [lunchSprite()]),
        sprite("hat-feather", [hatFeatherSprite()]),
        sprite("laundry-shirt", [laundrySprite("shirt")]),
        sprite("laundry-overalls", [laundrySprite("overalls")]),
        sprite("postcard", [postcardSprite()]),
        sprite("cake", [cakeSprite(0), cakeSprite(1)], [300, 300]),
        sprite("rainbow", [rainbowSprite()]),
        sprite("puddle", [puddleSprite()]),
        sprite("star-streak", [starStreakSprite()]),
        sprite("drift-flake", [driftFlakeSprite()]),
    ]
    for b in badgePictures { out.append(sprite("badge-\(b.name)", [badgeSprite(b.rows, b.legend)])) }
    for n in 1..<5 { out.append(sprite("woodpile-\(n)", [woodpileSprite(n)])) }
    for n in 0..<4 { out.append(sprite("garden-\(n)", [gardenSprite(n)])) }
    for (i, t) in ["foliage_orange", "foliage_red", "foliage_gold"].enumerated() { out.append(sprite("drift-leaf-\(i)", [driftLeafSprite(t)])) }
    return out
}
