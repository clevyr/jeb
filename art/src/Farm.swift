// Farm: the homestead at band scale (farm.py): house, still, sign, truck, crops, stack icons, quilt squares, lanterns,
// sky, weather and small overlays, plus the 3x5 font and the text helper the scenes reuse. Every builder draws on a
// Raster with Pillow's semantics, so the frames match what the Python drew.
import Foundation

private func c(_ name: String) -> RGBA { rgb(name) }

/// 3x5 pixel font for the sign, labels and counts, in farm.py's order (pixel-art.ts exports the single-character ones).
let farmFont: [(String, String)] = [
    ("A", "010101111101101"), ("B", "110101110101110"), ("C", "011100100100011"),
    ("D", "110101101101110"), ("E", "111100110100111"), ("F", "111100110100100"),
    ("G", "011100101101011"), ("H", "101101111101101"), ("I", "111010010010111"),
    ("J", "001001001101010"), ("K", "101101110101101"), ("L", "100100100100111"),
    ("M", "101111111101101"), ("N", "110101101101101"), ("O", "010101101101010"),
    ("P", "110101110100100"), ("Q", "010101101110011"), ("R", "110101110101101"),
    ("S", "011100010001110"), ("T", "111010010010010"), ("U", "101101101101111"),
    ("V", "101101101101010"), ("W", "101101111111101"), ("X", "101101010101101"),
    ("Y", "101101010010010"), ("Z", "111001010100111"),
    ("0", "111101101101111"), ("1", "010110010010111"), ("2", "110001010100111"),
    ("3", "110001010001110"), ("4", "101101111001001"), ("5", "111100110001110"),
    ("6", "011100111101111"), ("7", "111001010010010"), ("8", "111101111101111"),
    ("9", "111101111001110"), ("$", "011110010011110"), (".", "000000000000010"),
    ("'", "010010000000000"), ("+", "000010111010000"), ("K_", "101110100110101"),
    (" ", "000000000000000"), ("-", "000000111000000"), ("x", "000101010101000"),
    (",", "000000000010100"), ("!", "010010010000010"), ("?", "110001010000010"),
    (":", "000010000010000"), (";", "000010000010100"), ("(", "001010010010001"),
    (")", "100010010010100"), ("/", "001001010100100"), ("&", "010101010101011"),
    ("\"", "101101000000000"), ("%", "101001010100101"), ("#", "101111101111101"),
]

private let fontLookup: [String: [UInt8]] = Dictionary(
    farmFont.map { ($0.0, Array($0.1.utf8)) }, uniquingKeysWith: { _, last in last })

/// Draw `s` in the 3x5 font (upper-cased; unknown characters are a blank); returns the width drawn.
@discardableResult
func drawText(_ d: Raster, _ x: Int, _ y: Int, _ s: String, _ colour: String = "ink") -> Int {
    var cx = x
    let ink = c(colour)
    for ch in s.uppercased() {
        let bits = fontLookup[String(ch)] ?? fontLookup[" "]!
        for (i, bit) in bits.enumerated() where bit == UInt8(ascii: "1") {
            d.point(cx + i % 3, y + i / 3, fill: ink)
        }
        cx += 4
    }
    return cx - x - 1
}

// --------------------------------------------------------------- house ----

func houseSprite(night: Bool = false, coat: Bool = false) -> Raster {
    let d = Raster(50, 40)
    let (wall, wallDark) = coat ? ("hat", "hat_dark") : ("wood", "wood_dark")
    d.rectangle(4, 16, 45, 37, fill: c(wall))  // log walls
    for y in stride(from: 18, to: 37, by: 3) { d.line(4, y, 45, y, fill: c(wallDark)) }
    d.polygon([(1, 17), (25, 3), (48, 17)], fill: c("roof"))  // roof
    d.line(1, 17, 48, 17, fill: c("roof_dark"))
    for y in stride(from: 8, to: 17, by: 3) {
        d.line(25 - (y - 3) * 24 / 14, y, 25 + (y - 3) * 23 / 14, y, fill: c("roof_dark"))
    }
    d.rectangle(34, 2, 38, 10, fill: c("stone"))  // chimney
    d.line(34, 2, 38, 2, fill: c("stone_dark"))
    d.points([(35, 5), (37, 7)], fill: c("stone_dark"))
    let glass = night ? "window_lit" : "window"
    for x in [8, 32] {
        d.rectangle(x, 21, x + 7, 27, fill: c(glass))
        d.line(x + 3, 21, x + 3, 27, fill: c(wallDark))
        d.line(x, 24, x + 7, 24, fill: c(wallDark))
    }
    d.rectangle(20, 22, 28, 37, fill: c("wood_dark"))  // door
    d.point(26, 30, fill: c("amber"))
    d.rectangle(2, 37, 47, 38, fill: c("wood_dark"))  // porch boards
    for x in [3, 46] { d.line(x, 17, x, 37, fill: c("wood_dark")) }  // porch posts
    return outline(d)
}

func smokeSprite(_ beat: Int) -> Raster {
    let d = Raster(10, 12)
    let puffs = [(3, 9, 6, 11), (2, 5, 6, 8), (4, 1, 8, 4)]
    for (i, b) in puffs.enumerated() where (i + beat) % 3 != 2 {
        d.ellipse(b.0, b.1, b.2, b.3, fill: c(i % 2 != 0 ? "smoke" : "smoke_dark"))
    }
    return d
}

// ---------------------------------------------------------------- still ----

func stillSprite(lit: Bool = false, tarp: Bool = false, keg: Bool = false, worm: Bool = false) -> Raster {
    let d = Raster(38, 34)
    if tarp {
        d.polygon([(1, 33), (4, 6), (33, 6), (36, 33)], fill: c("green_dark"))
        d.line(6, 14, 31, 14, fill: c("green"))
        d.line(5, 24, 32, 24, fill: c("green"))
        d.rectangle(10, 3, 26, 6, fill: c("green_dark"))
        return outline(d)
    }
    d.ellipse(3, 5, 17, 13, fill: c("copper"))  // onion dome
    d.rectangle(8, 2, 12, 6, fill: c("copper_dark"))  // cap
    d.rectangle(2, 11, 18, 26, fill: c("copper"))  // pot
    d.line(4, 12, 4, 25, fill: lit ? c("fire_hot") : c("copper_dark"))  // shine
    d.line(2, 26, 18, 26, fill: c("copper_dark"))
    d.rectangle(4, 27, 16, 29, fill: c("stone"))  // firebox
    d.line(12, 3, 27, 3, fill: c("copper_dark"))  // lyne arm
    d.line(27, 3, 27, 9, fill: c("copper_dark"))
    if keg {  // thump keg between the pot and the worm
        d.rectangle(20, 8, 25, 15, fill: c("wood"))
        d.line(20, 10, 25, 10, fill: c("steel"))
        d.line(20, 13, 25, 13, fill: c("steel"))
    }
    d.rectangle(23, 10, 35, 27, fill: c("wood"))  // worm tub barrel
    for y in [12, 19, 25] { d.line(23, y, 35, y, fill: c("steel")) }
    let coil = worm ? "copper" : "copper_dark"
    for y in stride(from: 14, to: 25, by: 3) { d.line(25, y, 33, y + 1, fill: c(coil)) }
    d.line(35, 24, 37, 26, fill: c("copper_dark"))  // spout
    d.rectangle(33, 28, 37, 33, fill: c("glass"))  // jar catching the run
    d.rectangle(33, 30, 37, 33, fill: c("amber"))
    return outline(d)
}

func fireSprite(_ beat: Int, lit: Bool) -> Raster {
    let d = Raster(14, 6)
    if !lit {
        for x in [2, 5, 8, 11] { d.point(x, 5, fill: c("amber_dark")) }
        return d
    }
    let flames = beat == 0 ? [(1, 2), (4, 0), (7, 1), (10, 0)] : [(1, 0), (4, 2), (7, 0), (10, 1)]
    for (x, top) in flames {
        d.polygon([(x, 5), (x + 1, top), (x + 3, 5)], fill: c("fire"))
        d.point(x + 1, min(5, top + 2), fill: c("fire_hot"))
    }
    return d
}

func steamSprite(_ beat: Int) -> Raster {
    let d = Raster(8, 8)
    let y = beat == 0 ? 4 : 1
    d.ellipse(1, y, 5, y + 3, fill: c("smoke"))
    d.ellipse(3, y != 0 ? y - 1 : 0, 7, y + 2, fill: c("cloud"))
    return d
}

// ----------------------------------------------------------------- sign ----

func signSprite(night: Bool = false, coat: Bool = false) -> Raster {
    let d = Raster(46, 24)
    // A painted sign: cream boards, dark brown letters, a wooden frame.
    var (board, letters) = coat ? ("white", "red_dark") : ("hat_light", "band")
    if night { board = "hat" }  // the same sign under lantern light
    for x in [8, 36] { d.rectangle(x, 13, x + 2, 23, fill: c("wood_dark")) }  // posts
    d.rectangle(1, 1, 44, 14, fill: c(board))
    d.rectangle(1, 1, 44, 14, outline: c("wood_dark"))
    d.line(2, 12, 43, 12, fill: c("hat_dark"))  // board seam, below the letters
    let width = "JEB'S FARM".count * 4 - 1
    drawText(d, 23 - width / 2, 5, "JEB'S FARM", letters)
    return outline(d)
}

// ---------------------------------------------------------------- truck ----

let truckLoads = ["empty", "crate", "jars", "bales", "apples", "corn"]

func truckSprite(_ load: String = "crate", _ beat: Int = 0) -> Raster {
    let d = Raster(42, 22)
    d.rectangle(1, 9, 22, 16, fill: c("truck"))  // bed
    d.line(1, 9, 22, 9, fill: c("truck_dark"))
    d.rectangle(23, 3, 32, 16, fill: c("truck"))  // cab
    d.rectangle(25, 5, 31, 9, fill: c("glass"))  // window
    d.line(28, 5, 28, 9, fill: c("truck_dark"))
    d.rectangle(33, 9, 39, 16, fill: c("truck"))  // hood
    d.line(33, 9, 39, 9, fill: c("truck_dark"))
    d.rectangle(39, 10, 40, 15, fill: c("chrome"))  // grille
    d.point(40, 11, fill: c("fire_hot"))  // headlight
    d.line(1, 14, 40, 14, fill: c("truck_dark"))
    d.rectangle(0, 15, 41, 16, fill: c("chrome"))  // bumpers
    for x in [8, 33] {
        d.ellipse(x - 4, 13, x + 4, 21, fill: c("tire"))
        d.ellipse(x - 2, 15, x + 2, 19, fill: c("steel"))
        d.point(x, beat == 0 ? 15 : 19, fill: c("tire"))
    }
    switch load {
    case "crate":
        d.rectangle(4, 2, 18, 8, fill: c("wood"))
        d.line(4, 5, 18, 5, fill: c("wood_dark"))
        d.line(11, 2, 11, 8, fill: c("wood_dark"))
    case "jars":
        for x in [3, 9, 15] {
            d.rectangle(x, 3, x + 4, 8, fill: c("glass"))
            d.rectangle(x, 5, x + 4, 8, fill: c("amber"))
            d.line(x, 3, x + 4, 3, fill: c("steel"))
        }
    case "bales":
        for x in [3, 12] {
            d.rectangle(x, 3, x + 7, 8, fill: c("leaf_dry"))
            d.line(x + 2, 3, x + 2, 8, fill: c("wood_dark"))
            d.line(x + 5, 3, x + 5, 8, fill: c("wood_dark"))
        }
    case "apples":
        d.rectangle(4, 4, 18, 8, fill: c("wood"))
        for x in stride(from: 5, to: 18, by: 3) { d.ellipse(x, 2, x + 2, 4, fill: c("red")) }
    case "corn":
        for x in stride(from: 3, to: 20, by: 4) {
            d.rectangle(x, 3, x + 2, 8, fill: c("corn"))
            d.point(x + 1, 2, fill: c("green"))
        }
    default: break
    }
    return outline(d)
}

/// The visitors' rigs, facing right (the renderer flips them for the way back).
func vehicleSprite(_ kind: String, _ beat: Int = 0) -> Raster {
    let d = Raster(40, 20)
    func wheels(_ xs: [Int], r: Int = 4, y: Int = 15) {
        for x in xs {
            d.ellipse(x - r, y - r, x + r, y + r, fill: c("tire"))
            d.ellipse(x - 2, y - 2, x + 2, y + 2, fill: c("steel"))
            d.point(x, beat == 0 ? y - 2 : y + 2, fill: c("tire"))
        }
    }
    switch kind {
    case "store":  // Tolliver's red delivery truck, box body with a sign
        d.rectangle(1, 2, 25, 14, fill: c("red"))
        d.rectangle(3, 4, 23, 8, fill: c("cow_white"))
        d.line(4, 6, 22, 6, fill: c("red_dark"))
        d.rectangle(26, 6, 34, 14, fill: c("red"))
        d.rectangle(28, 7, 33, 10, fill: c("glass"))
        d.rectangle(34, 9, 38, 14, fill: c("red_dark"))
        d.point(38, 10, fill: c("fire_hot"))
        d.rectangle(0, 13, 39, 14, fill: c("chrome"))
        wheels([8, 31])
    case "mill":  // feed mill flatbed with sacks
        d.rectangle(1, 10, 25, 13, fill: c("wood"))
        for x in [3, 9, 15, 21] {
            d.rectangle(x, 5, x + 4, 9, fill: c("white"))
            d.line(x + 1, 5, x + 3, 5, fill: c("stone"))
        }
        d.rectangle(26, 4, 34, 13, fill: c("stone_dark"))
        d.rectangle(28, 5, 33, 8, fill: c("glass"))
        d.rectangle(34, 8, 38, 13, fill: c("grey"))
        d.point(38, 9, fill: c("fire_hot"))
        wheels([8, 31])
    case "mail":  // mail carrier's jeep
        d.rectangle(8, 6, 30, 13, fill: c("white"))
        d.line(8, 10, 30, 10, fill: c("denim"))
        d.line(8, 11, 30, 11, fill: c("red"))
        d.rectangle(12, 2, 24, 6, fill: c("white"))
        d.rectangle(14, 3, 18, 5, fill: c("glass"))
        d.rectangle(20, 3, 23, 5, fill: c("glass"))
        d.point(30, 7, fill: c("fire_hot"))
        wheels([13, 26], r: 3, y: 15)
    case "tractor":  // neighbour's old green tractor
        d.rectangle(12, 6, 30, 11, fill: c("green_dark"))
        d.rectangle(26, 3, 27, 6, fill: c("steel"))  // exhaust stack
        d.rectangle(8, 1, 15, 6, fill: c("green_dark"))  // seat and fender
        d.point(10, 0, fill: c("hat"))  // farmer's straw hat
        d.rectangle(9, 1, 11, 3, fill: c("skin"))
        d.ellipse(3, 6, 17, 19, fill: c("tire"))  // big rear wheel
        d.ellipse(7, 10, 13, 16, fill: c("yellow"))
        d.point(10, beat == 0 ? 9 : 16, fill: c("tire"))
        d.ellipse(25, 12, 31, 18, fill: c("tire"))
        d.ellipse(27, 14, 29, 16, fill: c("yellow"))
    case "tripper":  // the night buyer's dark coupe, lights low
        d.rectangle(2, 7, 36, 13, fill: c("ridge_mid_night"))
        d.rectangle(10, 2, 26, 7, fill: c("ridge_mid_night"))
        d.rectangle(12, 3, 17, 6, fill: c("glass_edge"))
        d.rectangle(19, 3, 24, 6, fill: c("glass_edge"))
        d.line(2, 11, 36, 11, fill: c("chrome"))
        d.point(36, 8, fill: c("amber_dark"))
        wheels([9, 29])
    default: break
    }
    return outline(d)
}

func dustSprite(_ beat: Int) -> Raster {
    let d = Raster(10, 6)
    if beat == 0 {
        d.ellipse(4, 1, 9, 5, fill: c("road"))
        d.ellipse(0, 3, 4, 6, fill: c("road_dark"))
    } else {
        d.ellipse(2, 0, 7, 4, fill: c("road_dark"))
    }
    return d
}

// ---------------------------------------------------------------- crops ----

func tobaccoSprite(_ stage: Int) -> Raster {
    let d = Raster(6, 18)
    d.rectangle(0, 16, 5, 17, fill: c("soil_dark"))  // hill
    if stage == 0 { return d }
    if stage == 1 {
        d.points([(2, 15), (3, 15), (1, 14), (4, 14)], fill: c("leaf"))
        return d
    }
    // Burley: a stalk with broad, drooping leaves stacked up it.
    let top = stage == 2 ? 9 : 3
    d.line(2, top, 2, 15, fill: c("green_dark"))
    for (i, y) in stride(from: 15, to: top, by: -3).enumerated() {
        let left = i % 2 == 0
        if left { d.ellipse(0, y - 2, 3, y, fill: c(i == 0 ? "green" : "leaf")) }
        else { d.ellipse(2, y - 3, 5, y - 1, fill: c(i == 0 ? "green" : "leaf")) }
        d.point(left ? 1 : 4, left ? y - 1 : y - 2, fill: c("green_dark"))
    }
    if stage == 3 { d.points([(2, 1), (1, 2), (3, 2), (2, 2)], fill: c("pink")) }  // flower head
    return d
}

func cornSprite(_ stage: Int) -> Raster {
    let d = Raster(6, 20)
    d.rectangle(0, 18, 5, 19, fill: c("soil_dark"))
    if stage == 0 { return d }
    if stage == 1 {
        d.line(2, 15, 2, 17, fill: c("green"))
        d.point(3, 15, fill: c("green"))
        return d
    }
    let top = stage == 2 ? 9 : 1
    d.line(2, top, 2, 17, fill: c("green_dark"))
    for y in stride(from: top + 3, to: 17, by: 4) {
        d.line(2, y, 0, y + 2, fill: c("green"))
        d.line(3, y - 1, 5, y + 1, fill: c("green"))
    }
    if stage == 3 {
        d.rectangle(3, 7, 4, 11, fill: c("corn"))  // ear
        d.points([(1, 0), (2, 0), (3, 0)], fill: c("hat_light"))  // tassel
    }
    return d
}

func appleTreeSprite(_ stage: Int, pumpkin: Bool = false) -> Raster {
    let d = Raster(10, 20)
    d.rectangle(2, 18, 7, 19, fill: c("soil_dark"))
    if stage == 0 {
        d.line(4, 14, 4, 17, fill: c("wood_dark"))
        d.points([(3, 14), (5, 13)], fill: c("leaf"))
        return d
    }
    let top = stage == 1 ? 8 : 2
    d.rectangle(4, 12, 5, 17, fill: c("wood_dark"))
    d.ellipse(0, top, 9, 14, fill: c("green"))
    d.points([(2, top + 3), (6, top + 2), (4, top + 7)], fill: c("green_dark"))
    if stage == 3 {
        for p in [(2, top + 5), (6, top + 4), (4, top + 2), (7, top + 8), (1, top + 8)] {
            d.point(p.0, p.1, fill: c("red"))
        }
    }
    if pumpkin {
        d.ellipse(5, 15, 9, 19, fill: c("amber"))
        d.point(7, 14, fill: c("green_dark"))
    }
    return d
}

// ---------------------------------------------------------- stack icons ----

func iconSprite(_ kind: String) -> Raster {
    let d = Raster(8, 8)
    switch kind {
    case "lumber":
        d.rectangle(0, 2, 7, 6, fill: c("wood"))
        d.ellipse(0, 2, 3, 6, fill: c("hat_light"))
        d.point(1, 4, fill: c("wood_dark"))
    case "stone":
        d.ellipse(0, 2, 7, 7, fill: c("stone"))
        d.points([(2, 4), (5, 3)], fill: c("stone_dark"))
    case "straw":
        for x in stride(from: 1, to: 7, by: 2) { d.line(x, 1, x + 1, 7, fill: c("hat")) }
        d.line(0, 4, 7, 4, fill: c("band"))
    case "iron":
        d.rectangle(3, 0, 4, 7, fill: c("steel"))
        d.rectangle(1, 0, 6, 1, fill: c("steel"))
    case "sugar":
        d.rectangle(1, 2, 6, 7, fill: c("white"))
        d.line(2, 1, 5, 1, fill: c("white"))
        d.point(3, 4, fill: c("stone"))
    case "copper":
        d.polygon([(1, 6), (2, 2), (7, 2), (6, 6)], fill: c("copper"))
        d.line(2, 3, 6, 3, fill: c("fire_hot"))
    case "apple_butter":
        d.rectangle(1, 2, 6, 7, fill: c("wood_dark"))
        d.rectangle(1, 1, 6, 2, fill: c("hat_light"))
    case "twist":
        d.line(1, 7, 6, 0, fill: c("leaf_dry"), width: 2)
        d.points([(2, 4), (4, 2)], fill: c("wood_dark"))
    case "whiskey":
        d.rectangle(1, 1, 6, 7, fill: c("glass"))
        d.rectangle(1, 3, 6, 7, fill: c("amber_dark"))
    case "jar":
        d.rectangle(1, 1, 6, 7, fill: c("glass"))
        d.rectangle(1, 3, 6, 7, fill: c("amber"))
        d.line(1, 1, 6, 1, fill: c("steel"))
    case "bale":
        d.rectangle(0, 2, 7, 7, fill: c("leaf_dry"))
        d.line(2, 2, 2, 7, fill: c("wood_dark"))
        d.line(5, 2, 5, 7, fill: c("wood_dark"))
    case "apples":
        d.rectangle(0, 4, 7, 7, fill: c("wood"))
        for x in [1, 3, 5] { d.ellipse(x, 2, x + 2, 4, fill: c("red")) }
    case "corn":
        d.rectangle(2, 1, 5, 7, fill: c("corn"))
        d.line(1, 3, 1, 7, fill: c("green"))
    case "cash":
        d.rectangle(0, 2, 7, 6, fill: c("green"))
        d.points([(3, 4), (4, 4)], fill: c("green_dark"))
    default: break
    }
    return kind != "cash" ? outline(d) : d
}

let farmIcons = ["lumber", "stone", "straw", "iron", "sugar", "copper", "apple_butter",
                 "twist", "whiskey", "jar", "bale", "apples", "corn", "cash"]

/// The quilt codes in farm.py's dict order.
let farmQuilt: [(String, String)] = [("B", "denim"), ("R", "red"), ("G", "green"), ("P", "purple"), ("Y", "yellow"), ("N", "soil")]

func quiltSquareSprite(_ code: String) -> Raster {
    let d = Raster(5, 5)
    d.rectangle(0, 0, 4, 4, fill: c(farmQuilt.first { $0.0 == code }!.1))
    d.points([(0, 0), (4, 4)], fill: c("white"))  // stitch corners
    return d
}

func lanternSprite(_ beat: Int) -> Raster {
    let d = Raster(5, 8)
    d.line(2, 0, 2, 1, fill: c("steel"))
    d.rectangle(1, 2, 3, 6, fill: c(beat == 0 ? "fire_hot" : "fire"))
    d.rectangle(0, 2, 4, 2, fill: c("steel"))
    d.rectangle(0, 7, 4, 7, fill: c("steel"))
    return d
}

// ------------------------------------------------------------- sky etc ----

func sunSprite() -> Raster {
    let d = Raster(9, 9)
    d.ellipse(1, 1, 7, 7, fill: c("yellow"))
    d.points([(4, 0), (0, 4), (8, 4), (4, 8)], fill: c("yellow"))
    return d
}

/// The box of the dark disc laid over the moon for a phase 0..7 (new, waxing crescent ... waning crescent); nil for full.
func moonShadow(_ phase: Int) -> (Int, Int, Int, Int)? {
    switch phase {
    case 0: return (0, 0, 8, 8)
    case 1: return (-3, 0, 5, 8)
    case 2: return (-8, 0, 4, 8)
    case 3: return (-12, 0, 2, 8)
    case 4: return nil
    case 5: return (6, 0, 20, 8)
    case 6: return (4, 0, 16, 8)
    case 7: return (3, 0, 11, 8)
    default: preconditionFailure("moon phase \(phase)")
    }
}

/// phase 0..7: new, waxing crescent ... waning crescent.
func moonSprite(_ phase: Int) -> Raster {
    let d = Raster(9, 9)
    d.ellipse(0, 0, 8, 8, fill: c("moon"))
    if let s = moonShadow(phase) {
        d.ellipse(s.0, s.1, s.2, s.3, fill: phase != 0 ? .clear : c("grey"))
    }
    return d
}

func cloudSprite(dark: Bool = false) -> Raster {
    let d = Raster(22, 9)
    let fill = c(dark ? "smoke_dark" : "cloud")
    for b in [(1, 3, 9, 8), (6, 0, 15, 8), (12, 2, 21, 8)] { d.ellipse(b.0, b.1, b.2, b.3, fill: fill) }
    return d
}

func overlaySprite(_ kind: String, _ beat: Int = 0) -> Raster {
    switch kind {
    case "note":  // cream, so it shows on a dark terminal
        let d = Raster(4, 6)
        d.rectangle(0, 4, 1, 5, fill: c("hat_light"))
        d.line(1, 0, 1, 4, fill: c("hat_light"))
        d.point(2, 0, fill: c("hat_light"))
        d.point(3, 1, fill: c("hat_light"))
        return d
    case "zz":
        let d = Raster(8, 8)
        for (x, y, s) in beat == 0 ? [(0, 4, 3), (4, 0, 2)] : [(1, 3, 3), (5, 0, 2)] {
            d.line(x, y, x + s, y, fill: c("white"))
            d.line(x + s, y, x, y + s, fill: c("white"))
            d.line(x, y + s, x + s, y + s, fill: c("white"))
        }
        return d
    case "bang":
        let d = Raster(3, 7)
        d.rectangle(1, 0, 1, 4, fill: c("red"))
        d.point(1, 6, fill: c("red"))
        return d
    case "ask":
        let d = Raster(4, 7)
        d.line(0, 0, 2, 0, fill: c("white"))
        d.points([(3, 1), (2, 2), (1, 3), (1, 4), (1, 6)], fill: c("white"))
        return d
    case "sweat":
        let d = Raster(3, 4)
        d.ellipse(0, 1, 2, 3, fill: c("drop"))
        d.point(1, 0, fill: c("drop"))
        return d
    case "heart":
        let d = Raster(5, 5)
        d.points([(1, 0), (3, 0)], fill: c("red"))
        d.rectangle(0, 1, 4, 2, fill: c("red"))
        d.polygon([(0, 2), (4, 2), (2, 4)], fill: c("red"))
        return d
    case "firefly":
        let d = Raster(3, 3)
        d.point(1, 1, fill: c(beat == 0 ? "fire_hot" : "yellow"))
        if beat == 0 { d.points([(0, 1), (2, 1), (1, 0), (1, 2)], fill: c("yellow")) }
        return d
    case "mothman":
        let d = Raster(7, 3)
        d.rectangle(0, 1, 1, 2, fill: c("red"))
        d.rectangle(5, 1, 6, 2, fill: c("red"))
        return d
    default:
        preconditionFailure("unknown overlay \(kind)")
    }
}

// ---------------------------------------------------------------- props ----

func propSprite(_ kind: String) -> Raster {
    let d: Raster
    switch kind {
    case "mailbox":
        d = Raster(8, 12)
        d.line(3, 5, 3, 11, fill: c("wood_dark"))
        d.rectangle(0, 1, 6, 5, fill: c("steel"))
        d.rectangle(6, 0, 7, 2, fill: c("red"))  // flag
    case "chair":
        d = Raster(10, 14)
        d.rectangle(1, 0, 3, 9, fill: c("wood"))
        d.rectangle(1, 7, 8, 9, fill: c("wood"))
        d.arc(0, 9, 9, 15, start: 180, end: 360, fill: c("wood_dark"))
    case "smokehouse":
        d = Raster(18, 20)
        d.rectangle(2, 7, 15, 19, fill: c("wood_dark"))
        d.polygon([(0, 8), (9, 1), (17, 8)], fill: c("roof"))
        d.rectangle(7, 12, 10, 19, fill: c("soil_dark"))
    case "keg":
        d = Raster(8, 10)
        d.rectangle(1, 1, 6, 9, fill: c("wood"))
        d.line(1, 3, 6, 3, fill: c("steel"))
        d.line(1, 7, 6, 7, fill: c("steel"))
    case "xmas":
        d = Raster(12, 18)
        d.polygon([(6, 0), (11, 14), (0, 14)], fill: c("green_dark"))
        d.rectangle(5, 14, 6, 17, fill: c("wood_dark"))
        for p in [(6, 3), (4, 8), (8, 10), (3, 12), (7, 6)] {
            d.point(p.0, p.1, fill: c(p.0 % 2 != 0 ? "red" : "yellow"))
        }
    case "pumpkin":
        d = Raster(8, 7)
        d.ellipse(0, 1, 7, 6, fill: c("amber"))
        d.line(3, 1, 3, 6, fill: c("amber_dark"))
        d.point(4, 0, fill: c("green_dark"))
    case "bell":
        d = Raster(7, 8)
        d.polygon([(1, 6), (3, 0), (5, 0), (6, 6)], fill: c("yellow"))
        d.point(3, 7, fill: c("amber_dark"))
    case "gate":
        d = Raster(14, 9)
        d.rectangle(0, 0, 13, 3, fill: c("white"))
        for x in [1, 6, 11] { d.line(x, 0, x + 2, 3, fill: c("red")) }
        d.line(2, 4, 2, 8, fill: c("steel"))
        d.line(11, 4, 11, 8, fill: c("steel"))
    case "fence":
        d = Raster(8, 7)
        for x in [0, 7] { d.line(x, 0, x, 6, fill: c("wood_dark")) }
        d.line(0, 2, 7, 2, fill: c("wood"))
        d.line(0, 5, 7, 5, fill: c("wood"))
    case "parachute":
        d = Raster(11, 14)
        d.chord(0, 0, 10, 8, start: 180, end: 360, fill: c("red"))
        d.line(0, 4, 5, 11, fill: c("ink"))
        d.line(10, 4, 5, 11, fill: c("ink"))
        d.rectangle(4, 11, 6, 13, fill: c("denim"))
    default:
        preconditionFailure("unknown prop \(kind)")
    }
    return outline(d)
}

let farmProps = ["mailbox", "chair", "smokehouse", "keg", "xmas", "pumpkin", "bell", "gate", "fence", "parachute"]

private func sprite(_ name: String, _ frames: [Raster], _ ms: [Int] = []) -> Sprite {
    Sprite(name: name, frames: frames, ms: ms)
}

func farmSprites() -> [Sprite] {
    var out: [Sprite] = [
        sprite("house", [houseSprite()]),
        sprite("house-night", [houseSprite(night: true)]),
        sprite("house-coat", [houseSprite(coat: true)]),
        sprite("house-coat-night", [houseSprite(night: true, coat: true)]),
        sprite("smoke", [smokeSprite(0), smokeSprite(1), smokeSprite(2)], [400, 400, 400]),
        sprite("still", [stillSprite()]),
        sprite("still-keg", [stillSprite(keg: true)]),
        sprite("still-worm", [stillSprite(keg: true, worm: true)]),
        sprite("still-tarp", [stillSprite(tarp: true)]),
        sprite("fire", [fireSprite(0, lit: true), fireSprite(1, lit: true)], [160, 160]),
        sprite("embers", [fireSprite(0, lit: false)]),
        sprite("steam", [steamSprite(0), steamSprite(1)], [300, 300]),
        sprite("sign", [signSprite()]),
        sprite("sign-night", [signSprite(night: true)]),
        sprite("sign-coat", [signSprite(coat: true)]),
        sprite("dust", [dustSprite(0), dustSprite(1)], [120, 120]),
        sprite("rig-store", [vehicleSprite("store", 0), vehicleSprite("store", 1)], [120, 120]),
        sprite("rig-mill", [vehicleSprite("mill", 0), vehicleSprite("mill", 1)], [120, 120]),
        sprite("rig-mail", [vehicleSprite("mail", 0), vehicleSprite("mail", 1)], [120, 120]),
        sprite("rig-tractor", [vehicleSprite("tractor", 0), vehicleSprite("tractor", 1)], [260, 260]),
        sprite("rig-tripper", [vehicleSprite("tripper", 0), vehicleSprite("tripper", 1)], [120, 120]),
        sprite("sun", [sunSprite()]),
        sprite("moon", (0..<8).map { moonSprite($0) }, Array(repeating: 300, count: 8)),
        sprite("cloud", [cloudSprite()]),
        sprite("cloud-dark", [cloudSprite(dark: true)]),
        sprite("lantern", [lanternSprite(0), lanternSprite(1)], [500, 500]),
        sprite("note", [overlaySprite("note")]),
        sprite("zz", [overlaySprite("zz", 0), overlaySprite("zz", 1)], [500, 500]),
        sprite("bang", [overlaySprite("bang")]),
        sprite("ask", [overlaySprite("ask")]),
        sprite("sweat", [overlaySprite("sweat")]),
        sprite("heart", [overlaySprite("heart")]),
        sprite("firefly", [overlaySprite("firefly", 0), overlaySprite("firefly", 1)], [300, 300]),
        sprite("mothman", [overlaySprite("mothman")]),
    ]
    for load in truckLoads { out.append(sprite("truck-\(load)", [truckSprite(load, 0), truckSprite(load, 1)], [110, 110])) }
    for s in 0..<4 { out.append(sprite("tobacco-\(s)", [tobaccoSprite(s)])) }
    for s in 0..<4 { out.append(sprite("corn-\(s)", [cornSprite(s)])) }
    for s in 0..<4 { out.append(sprite("apple-\(s)", [appleTreeSprite(s)])) }
    out.append(sprite("apple-pumpkin", [appleTreeSprite(3, pumpkin: true)]))
    for k in farmIcons { out.append(sprite("icon-\(k)", [iconSprite(k)])) }
    for (k, _) in farmQuilt { out.append(sprite("quilt-\(k)", [quiltSquareSprite(k)])) }
    for k in farmProps { out.append(sprite("prop-\(k)", [propSprite(k)])) }
    return out
}
