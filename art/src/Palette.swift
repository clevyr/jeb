// Palette: the one palette every sprite shares (index 0 is transparent, so the names start at 1). It is kept small so
// the runtime data is one byte per run and the GIFs stay tiny; the order is the wire format (mod/hooks/pixel-art.ts
// stores indices), so new colours go at the end.
import Foundation

/// One terminal cell is 4x8 sprite pixels, so pixels stay square in a 1:2 cell. A 6-row band is 48 pixels tall.
let cellW = 4, cellH = 8

let palette: [(name: String, r: UInt8, g: UInt8, b: UInt8)] = [
    ("ink", 43, 26, 14),
    ("hat", 222, 172, 78),
    ("hat_dark", 176, 125, 42),
    ("hat_light", 240, 205, 120),
    ("band", 122, 59, 29),
    ("skin", 241, 194, 125),
    ("skin_dark", 214, 158, 98),
    ("cheek", 230, 140, 110),
    ("beard", 139, 106, 74),
    ("beard_dark", 104, 78, 52),
    ("mouth", 110, 40, 28),
    ("white", 255, 255, 255),
    ("shirt", 192, 57, 43),
    ("shirt_dark", 140, 36, 28),
    ("denim", 63, 111, 181),
    ("denim_dark", 44, 79, 134),
    ("boot", 74, 46, 26),
    ("glass", 205, 232, 240),
    ("glass_edge", 107, 143, 160),
    ("amber", 227, 155, 58),
    ("amber_dark", 190, 110, 30),
    ("chrome", 205, 210, 215),
    ("steel", 130, 135, 145),
    ("tire", 35, 35, 38),
    ("truck", 54, 104, 168),
    ("truck_dark", 34, 70, 120),
    ("green", 95, 175, 80),
    ("green_dark", 60, 120, 50),
    ("leaf", 130, 190, 70),
    ("leaf_dry", 196, 150, 70),
    ("corn", 240, 200, 60),
    ("red", 220, 50, 50),
    ("red_dark", 150, 30, 30),
    ("soil", 120, 80, 50),
    ("soil_dark", 88, 56, 34),
    ("soil_dry", 200, 170, 100),
    ("grass", 110, 160, 70),
    ("road", 150, 130, 100),
    ("road_dark", 120, 100, 75),
    ("wood", 160, 110, 60),
    ("wood_dark", 115, 75, 40),
    ("roof", 120, 60, 50),
    ("roof_dark", 85, 40, 35),
    ("stone", 150, 150, 150),
    ("stone_dark", 105, 105, 110),
    ("copper", 196, 110, 60),
    ("copper_dark", 140, 70, 35),
    ("fire", 250, 150, 40),
    ("fire_hot", 255, 225, 90),
    ("smoke", 200, 200, 205),
    ("smoke_dark", 160, 160, 168),
    ("window", 60, 70, 90),
    ("window_lit", 250, 215, 110),
    ("blue_coat", 110, 125, 150),
    ("blue_spot", 60, 70, 95),
    ("tan", 196, 140, 80),
    ("nose", 30, 30, 35),
    ("drop", 80, 150, 230),
    ("cloud", 215, 222, 232),
    ("night_star", 250, 245, 200),
    ("moon", 245, 240, 210),
    ("pink", 240, 150, 170),
    ("purple", 150, 90, 190),
    ("yellow", 240, 210, 60),
    ("grey", 90, 90, 95),
    ("fur", 95, 65, 45),
    ("cow_white", 240, 238, 230),
    ("cow_black", 40, 40, 45),
    ("dress", 130, 90, 160),
    ("hair_grey", 200, 200, 205),
    ("black_car", 30, 32, 40),
    ("banjo_head", 245, 238, 220),
    ("banjo_rim", 150, 100, 50),
    // Appalachian backdrop: muted so the ridges sit behind the farm.
    ("ridge_far", 74, 92, 104),
    ("ridge_far_night", 38, 46, 60),
    ("ridge_mid", 52, 82, 54),
    ("ridge_mid_night", 28, 42, 32),
    ("pine", 36, 64, 40),
    ("foliage_orange", 200, 112, 44),
    ("foliage_red", 160, 52, 38),
    ("foliage_gold", 212, 168, 56),
    ("snowcap", 232, 234, 240),
    ("fog", 168, 176, 184),
    // Hired hands: a range of skin tones, hair and work clothes.
    ("skin_tan", 214, 160, 112),
    ("skin_brown", 168, 112, 74),
    ("skin_deep", 112, 72, 46),
    ("hair_dark", 42, 32, 26),
    ("hair_brown", 102, 70, 42),
    ("hair_blond", 214, 182, 104),
    ("flannel_green", 62, 112, 72),
    ("flannel_green_dark", 40, 80, 50),
    ("tee_grey", 142, 146, 152),
    ("tee_teal", 60, 140, 140),
    // Little things around the farm: creek water, a bluebird, deer and owl fur.
    ("water", 86, 150, 205),
    ("water_light", 160, 210, 240),
    ("bluebird", 66, 120, 215),
    ("deer_tan", 176, 122, 74),
    ("deer_light", 226, 196, 150),
    ("owl_brown", 120, 88, 62),
    ("owl_cream", 225, 205, 170),
    // The dirt road: muted, so white text and the vehicles read on top of it.
    ("dirt", 122, 98, 72),
    ("dirt_dark", 100, 79, 57),
    ("dirt_light", 138, 112, 83),
    ("pebble", 146, 140, 132),
    // The Halloween witch: a dark robe (shade leans blue, light leans magenta)
    // and lighter sleeves with a darker edge so the arms read in every pose.
    ("witch_robe", 82, 54, 122),
    ("witch_robe_dark", 52, 38, 104),
    ("witch_robe_light", 122, 76, 144),
    ("witch_sleeve", 178, 118, 198),
    ("witch_sleeve_dark", 120, 68, 156),
]

/// Every palette index's name: "clear" for 0, then the palette in order.
let paletteNames: [String] = ["clear"] + palette.map { $0.name }

let paletteIndex: [String: Int] = {
    precondition(paletteNames.count <= 127, "palette must fit in 7 bits")
    return Dictionary(uniqueKeysWithValues: paletteNames.enumerated().map { ($1, $0) })
}()

/// The opaque colour with that palette name.
func rgb(_ name: String) -> RGBA {
    guard let i = paletteIndex[name], i > 0 else { preconditionFailure("no palette colour named \(name)") }
    let c = palette[i - 1]
    return RGBA(c.r, c.g, c.b, 255)
}
