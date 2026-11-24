// Characters: Jeb, Blue, the hired hands and the visitors, as full-body pixel sprites at band scale (feet on the
// sprite's bottom row). A port of the original Python art source; every sprite has to come out pixel for pixel the same.
import Foundation

let jebW = 20, jebH = 40
let headroom = 8              // rows a holiday variant may add above the base
let bodyH = 36, bodyDY = 4    // the body layer, drawn as before and set 4 px lower

private func c(_ name: String) -> RGBA { rgb(name) }

// ------------------------------------------------------------------ Jeb ----

private func jebBase(_ d: Raster, arms: Bool = true) {
    // boots and legs
    d.rectangle(5, 32, 9, 34, fill: c("boot"))
    d.rectangle(10, 32, 14, 34, fill: c("boot"))
    d.rectangle(6, 25, 9, 31, fill: c("denim"))
    d.rectangle(10, 25, 13, 31, fill: c("denim"))
    d.line(9, 26, 9, 31, fill: c("denim_dark"))
    // shirt and overall bib
    d.rectangle(5, 16, 14, 24, fill: c("shirt"))
    for x in [6, 9, 13] { d.line(x, 16, x, 24, fill: c("shirt_dark")) }
    d.rectangle(7, 18, 12, 24, fill: c("denim"))
    d.line(7, 16, 7, 18, fill: c("denim"))
    d.line(12, 16, 12, 18, fill: c("denim"))
    d.points([(7, 18), (12, 18)], fill: c("chrome"))
    d.line(7, 24, 12, 24, fill: c("denim_dark"))
    if arms {
        d.rectangle(3, 17, 4, 23, fill: c("shirt"))
        d.rectangle(15, 17, 16, 23, fill: c("shirt"))
        d.rectangle(3, 24, 4, 25, fill: c("skin"))
        d.rectangle(15, 24, 16, 25, fill: c("skin"))
    }
}

/// The witch's palette: the arms' shirt colour becomes the sleeve shade.
private func witchPaint(_ name: String) -> RGBA { rgb(name == "shirt" ? "witch_sleeve" : name) }

/// A holiday's look for Jeb (`<pose>--<name>`): the same pose and face with a different body layer and a hat drawn in
/// the headroom above.
struct Costume {
    var name: String
    var paint: (String) -> RGBA               // colour lookup for the body and arms
    var body: (Raster, Bool) -> Void          // the body layer (boots to shoulders), given whether the arms hang
    var keepsStrawHat: Bool                   // the everyday hat stays on, with the costume drawn over it
    var raisedArms: Bool                      // salute and wave raise the arm clear of the hat, as the witch's do
    var hat: (Raster) -> Void                 // drawn on the taller box (feet on its bottom row), once for every pose
    var post: ((Raster) -> Void)? = nil       // a pass over the finished taller box, before the outline
}

/// One Jeb frame. `pose` decides the arms and any held prop; `beat` picks the alternate frame of a working pose.
/// `costume` is a holiday variant: same pose and face, its own body and hat in the headroom above.
func jeb(_ eyes: String = "open", _ mouth: String = "smile", _ pose: String = "stand", _ beat: Int = 0,
         costume: Costume? = nil) -> Raster {
    let d = Raster(jebW, bodyH)
    let c: (String) -> RGBA = costume?.paint ?? rgb
    let arms = pose == "stand" || pose == "sleep"
    if let costume = costume { costume.body(d, arms) } else { jebBase(d, arms: arms) }
    switch pose {
    case "banjo":
        d.rectangle(3, 17, 4, 21, fill: c("shirt"))     // left sleeve
        d.rectangle(15, 17, 16, 20, fill: c("shirt"))   // right sleeve
        d.line(10, 21, 18, 17, fill: c("band"))         // neck across the chest
        d.line(10, 22, 18, 18, fill: c("band"))
        d.rectangle(18, 15, 19, 17, fill: c("band"))    // peghead
        d.ellipse(2, 18, 10, 26, fill: c("banjo_rim"))  // pot at his hip
        d.ellipse(3, 19, 9, 25, fill: c("banjo_head"))
        d.rectangle(15, 18, 16, 19, fill: c("skin"))    // fretting hand
        let handY = beat == 0 ? 20 : 23
        d.rectangle(5, handY, 6, handY + 1, fill: c("skin"))  // picking hand
    case "jar":
        d.rectangle(3, 17, 4, 23, fill: c("shirt"))
        d.rectangle(3, 24, 4, 25, fill: c("skin"))
    case "sip":
        d.rectangle(3, 17, 4, 23, fill: c("shirt"))
        d.rectangle(3, 24, 4, 25, fill: c("skin"))
        if beat == 1 {  // lowered, a satisfied breath
            d.rectangle(14, 16, 16, 18, fill: c("shirt"))
            d.rectangle(14, 17, 18, 23, fill: c("glass"))
            d.rectangle(14, 19, 18, 23, fill: c("amber"))
            d.line(14, 17, 18, 17, fill: c("steel"))
            d.rectangle(14, 23, 17, 24, fill: c("skin"))
        }
    case "hoe":
        d.rectangle(3, 17, 4, 20, fill: c("shirt"))
        d.rectangle(15, 17, 16, 21, fill: c("shirt"))
        let (top, low) = beat == 0 ? ((1, 14), (17, 31)) : ((4, 11), (18, 29))
        d.line(top.0, top.1, low.0, low.1, fill: c("wood"))
        d.rectangle(low.0 - 1, low.1, low.0 + 2, low.1 + 2, fill: c("steel"))  // blade
        d.rectangle(5, 19, 6, 20, fill: c("skin"))   // hands on the handle
        d.rectangle(12, 24, 13, 25, fill: c("skin"))
    case "broom":
        d.rectangle(3, 17, 4, 21, fill: c("shirt"))
        d.rectangle(15, 17, 16, 21, fill: c("shirt"))
        let lean = beat == 0 ? 0 : 2
        d.line(16 + lean, 10, 14, 30, fill: c("wood"))
        d.rectangle(11 + lean, 30, 17 + lean, 34, fill: c("hat"))  // bristles
        d.line(11 + lean, 34, 17 + lean, 34, fill: c("hat_dark"))
        d.rectangle(15, 19, 16, 20, fill: c("skin"))
        d.rectangle(14, 23, 15, 24, fill: c("skin"))
    case "book":
        d.rectangle(3, 17, 4, 21, fill: c("shirt"))
        d.rectangle(15, 17, 16, 21, fill: c("shirt"))
        d.rectangle(5, 19, 14, 23, fill: c("wood_dark"))   // almanac, open, brown cover
        d.rectangle(6, 19, 9, 22, fill: c("hat_light"))    // left page
        d.rectangle(10, 19, 13, 22, fill: c("hat_light"))  // right page
        d.line(9, 19, 9, 23, fill: c("wood_dark"))         // spine
        d.line(7, 20, 8, 20, fill: c("hat_dark"))          // lines of print
        d.line(11, 21, 12, 21, fill: c("hat_dark"))
        d.rectangle(5, 21, 6, 22, fill: c("skin"))
        d.rectangle(13, 21, 14, 22, fill: c("skin"))
    case "stir":
        d.rectangle(3, 17, 4, 23, fill: c("shirt"))
        d.rectangle(3, 24, 4, 25, fill: c("skin"))
        d.rectangle(15, 17, 17, 19, fill: c("shirt"))  // arm out to the still
        let tip = beat == 0 ? (19, 30) : (17, 31)
        d.line(18, 18, tip.0, tip.1, fill: c("wood"))  // paddle
        d.rectangle(17, 18, 18, 19, fill: c("skin"))
    case "salute":
        d.rectangle(15, 17, 16, 23, fill: c("shirt"))
        d.rectangle(15, 24, 16, 25, fill: c("skin"))
    case "wave":
        d.rectangle(3, 17, 4, 23, fill: c("shirt"))
        d.rectangle(3, 24, 4, 25, fill: c("skin"))
    case "hold":  // a small prop at his chest, drawn by the scene
        d.rectangle(3, 17, 4, 23, fill: c("shirt"))
        d.rectangle(3, 24, 4, 25, fill: c("skin"))
        d.rectangle(15, 17, 16, 20, fill: c("shirt"))
        d.rectangle(14, 20, 16, 21, fill: c("skin"))
    default: break
    }
    // The emoji's proportions: the body layer set lower, a big head on top.
    let full = Raster(jebW, jebH)
    full.alphaComposite(d, at: 0, bodyDY)
    jebBigHead(full, eyes, mouth)
    if costume == nil || costume!.keepsStrawHat { jebBigHat(full) }
    jebHeadProps(full, pose, beat, costume)
    guard let costume = costume else { return outline(full) }
    // the same body at the bottom of a taller box, the hat in the rows above
    let tall = Raster(jebW, jebH + headroom)
    tall.alphaComposite(full, at: 0, headroom)
    costume.hat(tall)
    costume.post?(tall)
    return outline(tall)
}

/// Jeb's face as the Slack emoji draws it: a broad face, 2x2 eyes, a nose, rosy cheeks and a full brown beard.
private func jebBigHead(_ d: Raster, _ eyes: String, _ mouth: String) {
    d.rectangle(5, 7, 14, 16, fill: c("skin"))   // face
    d.rectangle(4, 8, 15, 15, fill: c("skin"))
    d.rectangle(3, 10, 3, 12, fill: c("skin_dark"))  // ears
    d.rectangle(16, 10, 16, 12, fill: c("skin_dark"))
    d.line(5, 7, 14, 7, fill: c("skin_dark"))    // brim shadow
    d.rectangle(9, 11, 10, 12, fill: c("skin_dark"))  // nose
    d.points([(5, 12), (14, 12)], fill: c("cheek"))
    // beard, from the cheeks down past the chin
    d.rectangle(4, 13, 15, 17, fill: c("beard"))
    d.rectangle(5, 18, 14, 18, fill: c("beard"))
    d.rectangle(7, 19, 12, 19, fill: c("beard"))
    d.points([(6, 15), (10, 17), (13, 16), (8, 18), (12, 18)], fill: c("beard_dark"))
    // eyes, 2x2 like the emoji
    switch eyes {
    case "open":
        d.rectangle(7, 9, 8, 10, fill: c("ink"))
        d.rectangle(11, 9, 12, 10, fill: c("ink"))
    case "shut":
        d.line(6, 10, 8, 10, fill: c("ink"))
        d.line(11, 10, 13, 10, fill: c("ink"))
    case "happy":  // ^ ^
        d.points([(6, 10), (7, 9), (8, 9), (9, 10)], fill: c("ink"))
        d.points([(10, 10), (11, 9), (12, 9), (13, 10)], fill: c("ink"))
    case "wide":   // O O
        d.rectangle(6, 8, 8, 10, fill: c("white"))
        d.rectangle(11, 8, 13, 10, fill: c("white"))
        d.points([(7, 9), (12, 9)], fill: c("ink"))
    case "wink":
        d.rectangle(7, 9, 8, 10, fill: c("ink"))
        d.points([(10, 10), (11, 9), (12, 9), (13, 10)], fill: c("ink"))
    case "down":
        d.line(7, 10, 8, 10, fill: c("ink"))
        d.line(11, 10, 12, 10, fill: c("ink"))
    default: break
    }
    // mouth, inside the beard
    switch mouth {
    case "smile":
        d.line(8, 15, 11, 15, fill: c("mouth"))
        d.points([(7, 14), (12, 14)], fill: c("mouth"))
    case "grin":
        d.rectangle(7, 14, 12, 16, fill: c("mouth"))
        d.line(8, 14, 11, 14, fill: c("white"))
    case "o":
        d.rectangle(9, 14, 10, 16, fill: c("mouth"))
    case "flat":
        d.line(8, 15, 11, 15, fill: c("mouth"))
    default: break
    }
}

private func jebBigHat(_ d: Raster) {
    d.rectangle(6, 0, 13, 4, fill: c("hat"))  // crown
    d.line(7, 0, 12, 0, fill: c("hat_light"))
    d.points([(9, 0), (10, 0)], fill: c("hat_dark"))  // crease
    d.rectangle(6, 3, 13, 4, fill: c("band"))
    d.rectangle(1, 5, 18, 6, fill: c("hat"))  // brim
    d.line(1, 6, 18, 6, fill: c("hat_dark"))
    for x in [3, 7, 12, 16] { d.point(x, 5, fill: c("hat_dark")) }
}

/// What he holds up near his head, drawn over the big head.
private func jebHeadProps(_ d: Raster, _ pose: String, _ beat: Int, _ costume: Costume?) {
    let c: (String) -> RGBA = costume?.paint ?? rgb
    let raised = costume?.raisedArms ?? false
    if pose == "jar" {
        d.rectangle(15, 19, 16, 23, fill: c("shirt"))  // arm raised
        d.rectangle(15, 11, 19, 19, fill: c("glass"))  // jar beside his head
        d.rectangle(15, 14, 19, 19, fill: c("amber"))
        d.line(15, 11, 19, 11, fill: c("steel"))
        d.line(16, 12, 16, 18, fill: c("white"))
        d.rectangle(15, 19, 18, 20, fill: c("skin"))   // hand round the jar
    } else if pose == "sip" && beat == 0 {
        d.rectangle(14, 19, 16, 22, fill: c("shirt"))
        d.rectangle(9, 13, 13, 19, fill: c("glass"))   // jar at his mouth
        d.rectangle(9, 15, 13, 19, fill: c("amber"))
        d.line(9, 13, 13, 13, fill: c("steel"))
        d.rectangle(12, 19, 15, 20, fill: c("skin"))
    } else if pose == "salute" && raised {
        // the hand stays three rows under the brim; the forearm and its shadow keep it apart from the face
        d.line(4, 21, 1, 16, fill: c("shirt"), width: 2)  // upper arm, elbow out
        d.line(1, 16, 2, 11, fill: c("shirt"), width: 2)  // forearm up to the temple
        d.rectangle(1, 9, 6, 10, fill: c("skin"))         // flat hand
        d.line(4, 11, 6, 11, fill: c("skin_dark"))        // its shadow on the cheek
    } else if pose == "salute" {
        d.line(4, 21, 1, 16, fill: c("shirt"), width: 2)  // upper arm, elbow out
        d.line(1, 16, 3, 10, fill: c("shirt"), width: 2)  // forearm to the brow
        d.line(2, 8, 9, 7, fill: c("skin"), width: 2)     // flat hand at the brim, over the eye
    } else if pose == "wave" && raised {
        let y = beat == 0 ? 10 : 11
        d.rectangle(15, 15, 16, 22, fill: c("shirt"))
        d.rectangle(17, y + 4, 17, 15, fill: c("shirt"))  // forearm steps out past the ear
        d.rectangle(17, y, 19, y + 3, fill: c("skin"))    // hand clear of ear and brim
    } else if pose == "wave" {
        d.rectangle(15, 15, 16, 22, fill: c("shirt"))
        let y = beat == 0 ? 10 : 11
        d.rectangle(16, y, 18, y + 4, fill: c("skin"))
    }
}

/// The witch's body layer: boots, a robe that flares to the hem instead of overalls, and sleeves in their own shade.
/// Shading is hue-shifted: shadow leans blue, light leans magenta.
private func witchRobe(_ d: Raster, _ arms: Bool = true) {
    let robe = c("witch_robe"), dark = c("witch_robe_dark"), light = c("witch_robe_light")
    d.rectangle(5, 32, 9, 34, fill: c("boot"))
    d.rectangle(10, 32, 14, 34, fill: c("boot"))
    d.rectangle(5, 16, 14, 24, fill: robe)
    for (y, x0, x1) in [(25, 4, 15), (26, 4, 15), (27, 3, 16), (28, 3, 16), (29, 3, 16), (30, 2, 17), (31, 2, 17)] {
        d.line(x0, y, x1, y, fill: robe)
    }
    d.line(5, 17, 5, 23, fill: light)  // light from the left
    d.line(13, 16, 14, 16, fill: dark)  // shadow down the right
    d.line(13, 16, 13, 24, fill: dark)
    d.line(14, 16, 14, 24, fill: dark)
    for (y, x1) in [(25, 15), (26, 15), (27, 16), (28, 16), (29, 16), (30, 17)] {
        d.line(x1 - 1, y, x1, y, fill: dark)
    }
    d.line(9, 25, 9, 30, fill: dark)  // a fold in the skirt
    d.line(2, 31, 17, 31, fill: dark) // hem
    d.points([(5, 28), (4, 29), (5, 29), (6, 29), (5, 30)], fill: c("yellow"))  // a small four point star
    if arms {
        d.rectangle(3, 17, 4, 23, fill: c("witch_sleeve"))
        d.rectangle(15, 17, 16, 23, fill: c("witch_sleeve"))
        d.rectangle(3, 24, 4, 25, fill: c("skin"))
        d.rectangle(15, 24, 16, 25, fill: c("skin"))
    }
}

// the tall hat's cone, row by row: (x0, x1), leaning right toward a bent tip. Row order is the Python dict's order.
private let witchCone: [(y: Int, x0: Int, x1: Int)] = [
    (12, 5, 14), (11, 5, 14), (10, 6, 13), (9, 6, 13), (8, 7, 12), (7, 7, 12),
    (6, 8, 11), (5, 8, 11), (4, 9, 12), (3, 10, 12), (2, 11, 13), (1, 13, 14),
]

/// A tall pointed hat in rows 1-12 of the taller box and a flat brim as wide as the straw hat's.
private func witchHat(_ d: Raster) {
    let robe = c("witch_robe"), dark = c("witch_robe_dark")
    for (y, x0, x1) in witchCone {
        d.line(x0, y, x1, y, fill: robe)
        d.point(x1, y, fill: dark)  // shaded side
    }
    for y in [11, 12] {
        let row = witchCone.first { $0.y == y }!
        d.line(row.x0, y, row.x1, y, fill: c("fire"))
        d.point(row.x1, y, fill: c("copper"))
    }
    d.rectangle(9, 11, 10, 12, fill: c("yellow"))  // buckle
    d.line(1, 13, 18, 13, fill: robe)  // brim
    d.line(1, 14, 18, 14, fill: dark)
    d.line(1, 13, 3, 13, fill: c("witch_robe_light"))
}

/// The selective outline: a sleeve pixel on the outer edge of the arm (empty space on the side away from the body)
/// takes the robe's dark shade, and one that touches skin, beard or a prop takes the sleeve's own darker shade.
private func sleeveEdges(_ img: Raster) {
    let w = img.width, h = img.height
    let sleeve = c("witch_sleeve"), edge = c("witch_sleeve_dark"), outer = c("witch_robe_dark")
    let known: Set<RGBA> = [c("witch_robe"), c("witch_robe_dark"), c("witch_robe_light"), sleeve, edge, outer]
    var marks: [(Int, Int, RGBA)] = []
    for y in 0..<h {
        for x in 0..<w {
            if img[x, y] != sleeve { continue }
            let ox = x < w / 2 ? x - 1 : x + 1
            if ox >= 0 && ox < w && img[ox, y].a == 0 {
                marks.append((x, y, outer))
                continue
            }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                if nx >= 0 && nx < w && ny >= 0 && ny < h && img[nx, ny].a != 0 && !known.contains(img[nx, ny]) {
                    marks.append((x, y, edge))
                    break
                }
            }
        }
    }
    for (x, y, col) in marks { img[x, y] = col }
}

// The Santa hat: a red cone leaning right, its tip flopped over to a white pom-pom, on a fur band. Rows 1-11.
private let santaCone: [(y: Int, x0: Int, x1: Int)] = [
    (11, 4, 15), (10, 4, 15), (9, 5, 14), (8, 6, 13), (7, 7, 12), (6, 8, 12),
    (5, 9, 12), (4, 10, 13), (3, 11, 14), (2, 12, 16), (1, 14, 16),
]

private func santaHat(_ d: Raster) {
    for (y, x0, x1) in santaCone {
        d.line(x0, y, x1, y, fill: c("red"))
        d.point(x1, y, fill: c("red_dark"))  // shaded side
    }
    d.line(16, 3, 16, 4, fill: c("red"))       // the tip flops over
    d.line(17, 3, 17, 4, fill: c("red_dark"))
    d.rectangle(16, 5, 18, 7, fill: c("white"))  // pom-pom
    d.point(18, 7, fill: c("cloud"))
    d.rectangle(3, 12, 16, 14, fill: c("white"))  // fur band
    d.line(3, 14, 16, 14, fill: c("cloud"))
    d.points([(5, 13), (8, 13), (11, 13), (14, 13)], fill: c("cloud"))
}

/// A scarf wrapped at the neck (rows 15-16 of the body layer, under the beard) with a tail down the right side.
private func scarf(_ d: Raster, _ base: String, _ stripe: String, _ edge: String) {
    d.rectangle(5, 15, 14, 16, fill: c(base))
    for x in [6, 9, 12] { d.line(x, 15, x, 16, fill: c(stripe)) }
    d.line(5, 16, 14, 16, fill: c(edge))
    d.rectangle(12, 17, 13, 22, fill: c(base))
    d.line(12, 19, 13, 19, fill: c(stripe))
    d.line(12, 22, 13, 22, fill: c(edge))
}

private func santaBody(_ d: Raster, _ arms: Bool = true) {
    jebBase(d, arms: arms)
    scarf(d, "flannel_green", "white", "flannel_green_dark")
}

private func harvestBody(_ d: Raster, _ arms: Bool = true) {
    jebBase(d, arms: arms)
    scarf(d, "foliage_gold", "foliage_orange", "amber_dark")
}

/// Autumn leaves tucked in the straw hat's band (rows 11-12 of the taller box) and a small cluster of broad leaves
/// fanned out from its right end.
private func harvestHat(_ d: Raster) {
    let band: [(Int, Int, String)] = [
        (6, 11, "foliage_red"), (7, 11, "foliage_red"), (7, 12, "foliage_orange"), (8, 12, "foliage_orange"),
        (9, 11, "foliage_gold"), (10, 12, "foliage_gold"), (10, 11, "foliage_orange"), (11, 11, "foliage_red"),
        (6, 12, "foliage_red"),
    ]
    for (x, y, col) in band { d.point(x, y, fill: c(col)) }
    // a cluster of three broad leaves fanned out from the band's right end: red up-left, orange up-right, gold out
    let red = "foliage_red", redEdge = "red_dark", orange = "foliage_orange", orangeEdge = "copper_dark"
    let gold = "foliage_gold", stem = "amber_dark"
    let leaves: [(Int, Int, String)] = [
        (10, 5, redEdge), (9, 6, redEdge), (10, 6, red), (11, 6, redEdge), (9, 7, red), (10, 7, red), (11, 7, redEdge),
        (10, 8, red), (11, 8, redEdge),
        (14, 6, orangeEdge), (13, 7, orangeEdge), (14, 7, orange), (15, 7, orangeEdge), (13, 8, orange), (14, 8, orange),
        (15, 8, orangeEdge), (14, 9, orangeEdge),
        (16, 9, stem), (17, 9, gold), (15, 10, stem), (16, 10, gold), (17, 10, gold), (18, 10, stem), (16, 11, stem),
        (17, 11, stem),
        (12, 9, stem), (12, 10, stem), (13, 10, stem), (14, 10, stem),
    ]
    for (x, y, col) in leaves { d.point(x, y, fill: c(col)) }
}

let witchCostume = Costume(name: "halloween", paint: witchPaint, body: witchRobe, keepsStrawHat: false,
                           raisedArms: true, hat: witchHat, post: sleeveEdges)
let harvestCostume = Costume(name: "thanksgiving", paint: rgb, body: harvestBody, keepsStrawHat: true,
                             raisedArms: false, hat: harvestHat)
let santaCostume = Costume(name: "christmas", paint: rgb, body: santaBody, keepsStrawHat: false,
                           raisedArms: true, hat: santaHat)
/// The only holidays that dress Jeb up: religious and cultural holidays get a banner badge, never a costume.
let costumes = [witchCostume, harvestCostume, santaCostume]

func jebSprites() -> [Sprite] {
    let base = jebBaseSprites()
    var out = base
    // every pose wears each holiday's costume as a --<holiday> variant
    for costume in costumes {
        for (sp, w) in zip(base, jebBaseSprites(costume)) {
            out.append(Sprite(name: "\(sp.name)--\(costume.name)", frames: w.frames, ms: sp.ms, anchor: sp.anchor))
        }
    }
    return out
}

private func jebBaseSprites(_ costume: Costume? = nil) -> [Sprite] {
    func j(_ eyes: String = "open", _ mouth: String = "smile", _ pose: String = "stand", _ beat: Int = 0) -> Raster {
        jeb(eyes, mouth, pose, beat, costume: costume)
    }
    return [
        Sprite(name: "jeb-idle", frames: [j(), j(), j(), j("shut")], ms: [900, 900, 900, 160]),
        Sprite(name: "jeb-happy", frames: [j("happy", "grin")], ms: [400]),
        Sprite(name: "jeb-spooked", frames: [j("wide", "o")], ms: [400]),
        Sprite(name: "jeb-wink", frames: [j("wink", "smile")], ms: [400]),
        Sprite(name: "jeb-think", frames: [j("down", "flat", "hold")], ms: [400]),
        Sprite(name: "jeb-sleep", frames: [j("shut", "flat", "sleep")], ms: [400]),
        Sprite(name: "jeb-banjo", frames: [j("happy", "smile", "banjo", 0), j("shut", "smile", "banjo", 1)], ms: [260, 260]),
        Sprite(name: "jeb-jar", frames: [j("happy", "grin", "jar")], ms: [400]),
        Sprite(name: "jeb-sip", frames: [j("shut", "smile", "sip", 0), j("happy", "smile", "sip", 1)], ms: [700, 700]),
        Sprite(name: "jeb-hoe", frames: [j("down", "flat", "hoe", 0), j("down", "flat", "hoe", 1)], ms: [300, 300]),
        Sprite(name: "jeb-broom", frames: [j("open", "smile", "broom", 0), j("open", "smile", "broom", 1)], ms: [280, 280]),
        Sprite(name: "jeb-book", frames: [j("down", "smile", "book")], ms: [400]),
        Sprite(name: "jeb-stir", frames: [j("open", "flat", "stir", 0), j("open", "flat", "stir", 1)], ms: [320, 320]),
        Sprite(name: "jeb-salute", frames: [j("open", "flat", "stand"), j("open", "flat", "salute")], ms: [500, 1500]),
        Sprite(name: "jeb-wave", frames: [j("happy", "grin", "wave", 0), j("happy", "grin", "wave", 1)], ms: [250, 250]),
        Sprite(name: "jeb-hold", frames: [j("open", "smile", "hold")], ms: [400]),
    ]
}

// ----------------------------------------------------------------- Blue ----

func blue(_ kind: String = "stand", _ beat: Int = 0) -> Raster {
    let d = Raster(20, 13)
    if kind == "nap" {
        d.ellipse(2, 5, 15, 11, fill: c("blue_coat"))  // curled up
        d.ellipse(11, 4, 18, 10, fill: c("blue_coat"))
        d.rectangle(13, 5, 14, 10, fill: c("blue_spot"))  // ear flopped
        d.rectangle(16, 7, 18, 9, fill: c("tan"))
        d.point(18, 7, fill: c("nose"))
        d.line(15, 6, 16, 6, fill: c("ink"))  // shut eye
        d.points([(5, 7), (8, 6), (10, 8)], fill: c("blue_spot"))
        return outline(d)
    }
    let run = kind == "run"
    d.rectangle(4, 4, 13, 8, fill: c("blue_coat"))  // body
    for (x, y) in [(5, 5), (8, 4), (10, 6), (12, 5), (6, 7)] { d.point(x, y, fill: c("blue_spot")) }
    d.rectangle(12, 1, 17, 6, fill: c("blue_coat"))  // head
    d.rectangle(12, 2, 13, 8, fill: c("blue_spot"))  // long ear
    d.rectangle(16, 4, 18, 6, fill: c("tan"))        // muzzle
    d.point(18, 4, fill: c("nose"))
    d.point(15, 3, fill: c("ink"))                   // eye
    if kind == "bark" { d.line(16, 6, 18, 7, fill: c("mouth")) }
    let tailUp = beat == 0
    d.line(4, 4, 1, tailUp ? 1 : 3, fill: c("blue_coat"), width: 2)  // tail
    if run {
        let legs = beat == 0
            ? [(4, 9, 2, 11), (6, 9, 7, 11), (11, 9, 9, 11), (13, 9, 15, 11)]
            : [(4, 9, 5, 11), (6, 9, 4, 11), (11, 9, 13, 11), (13, 9, 12, 11)]
        for (x0, y0, x1, y1) in legs { d.line(x0, y0, x1, y1, fill: c("blue_spot")) }
    } else {
        for x in [5, 7, 11, 13] { d.line(x, 9, x, 11, fill: c("blue_spot")) }
    }
    return outline(d)
}

func blueSprites() -> [Sprite] {
    [
        Sprite(name: "blue-wag", frames: [blue("stand", 0), blue("stand", 1)], ms: [250, 250]),
        Sprite(name: "blue-run", frames: [blue("run", 0), blue("run", 1)], ms: [120, 120]),
        Sprite(name: "blue-nap", frames: [blue("nap")], ms: [400]),
        Sprite(name: "blue-bark", frames: [blue("bark", 0), blue("stand", 1)], ms: [220, 220]),
    ]
}

// ------------------------------------------------------------ hired hand ----

/// Hired hands: six different farmhands in Jeb's own plain style, with everyday work clothes and a range of skin
/// tones and hair. Same face style as Jeb (simple eyes, a smile), no exaggerated features.
struct Hand { var skin, hair, hat: String; var hatC: String?; var shirt: String; var stripe: String? }

let hands = [
    Hand(skin: "skin", hair: "hair_brown", hat: "cap", hatC: "red", shirt: "flannel_green", stripe: "flannel_green_dark"),
    Hand(skin: "skin_deep", hair: "hair_dark", hat: "beanie", hatC: "denim", shirt: "tee_grey", stripe: nil),
    Hand(skin: "skin_tan", hair: "hair_dark", hat: "none", hatC: nil, shirt: "tee_teal", stripe: nil),
    Hand(skin: "skin_brown", hair: "hair_dark", hat: "cap", hatC: "denim", shirt: "shirt", stripe: "shirt_dark"),
    Hand(skin: "skin", hair: "hair_blond", hat: "bandana", hatC: "red", shirt: "tee_grey", stripe: nil),
    Hand(skin: "skin_deep", hair: "hair_dark", hat: "cap", hatC: "green_dark", shirt: "flannel_green", stripe: "flannel_green_dark"),
]

func hand(_ variant: Int = 0, _ beat: Int = 0) -> Raster {
    let v = hands[variant % hands.count]
    let d = Raster(16, 28)
    d.rectangle(4, 25, 7, 26, fill: c("boot"))
    d.rectangle(8, 25, 11, 26, fill: c("boot"))
    d.rectangle(5, 19, 7, 24, fill: c("denim"))  // work pants
    d.rectangle(8, 19, 10, 24, fill: c("denim"))
    d.rectangle(4, 12, 11, 18, fill: c(v.shirt))  // shirt
    if let stripe = v.stripe {
        for x in [5, 8, 10] { d.line(x, 12, x, 18, fill: c(stripe)) }
    }
    d.rectangle(5, 5, 10, 11, fill: c(v.skin))  // face
    d.points([(6, 7), (9, 7)], fill: c("ink"))  // eyes
    d.line(7, 9, 8, 9, fill: c("mouth"))        // smile
    d.points([(4, 8), (11, 8)], fill: c(v.skin))  // ears
    // hair, then whatever is on their head
    d.rectangle(5, 3, 10, 4, fill: c(v.hair))
    switch v.hat {
    case "cap":
        d.rectangle(5, 2, 10, 4, fill: c(v.hatC!))
        d.line(10, 4, 12, 4, fill: c(v.hatC!))  // bill
    case "beanie":
        d.rectangle(5, 1, 10, 4, fill: c(v.hatC!))
        d.line(5, 4, 10, 4, fill: c("white"))
    case "bandana":
        d.rectangle(5, 3, 10, 4, fill: c(v.hatC!))
        d.point(4, 4, fill: c(v.hatC!))
    default:
        d.rectangle(5, 2, 10, 4, fill: c(v.hair))
    }
    // the hoe, swung between frames
    let (top, low) = beat == 0 ? ((1, 10), (13, 24)) : ((3, 8), (14, 22))
    d.line(top.0, top.1, low.0, low.1, fill: c("wood"))
    d.rectangle(low.0 - 1, low.1, low.0 + 1, low.1 + 2, fill: c("steel"))
    d.rectangle(3, 13, 4, 14, fill: c(v.skin))  // hands on the handle
    d.rectangle(9, 18, 10, 19, fill: c(v.skin))
    return outline(d)
}

func visitorSprites() -> [Sprite] {
    var out = [Sprite(name: "hand-work", frames: [hand(0, 0), hand(0, 1)], ms: [300, 300])]
    for v in 0..<hands.count {
        out.append(Sprite(name: "hand-work-\(v)", frames: [hand(v, 0), hand(v, 1)], ms: [300, 300]))
    }

    // Miss Opal: grey bun, purple dress, a basket on her arm.
    do {
        let d = Raster(14, 28)
        d.rectangle(3, 13, 10, 25, fill: c("dress"))
        d.polygon([(2, 25), (11, 25), (10, 15), (3, 15)], fill: c("dress"))
        d.rectangle(4, 26, 5, 26, fill: c("boot"))
        d.rectangle(8, 26, 9, 26, fill: c("boot"))
        d.rectangle(4, 6, 9, 12, fill: c("skin"))
        d.points([(5, 8), (8, 8)], fill: c("ink"))
        d.line(6, 10, 7, 10, fill: c("mouth"))
        d.rectangle(3, 3, 10, 6, fill: c("hair_grey"))
        d.rectangle(5, 1, 8, 3, fill: c("hair_grey"))  // bun
        d.rectangle(10, 17, 13, 20, fill: c("wood"))   // basket
        d.line(10, 16, 13, 16, fill: c("wood_dark"))
        out.append(Sprite(name: "opal", frames: [outline(d)], ms: [400]))
    }

    // A milk cow.
    func cow(_ beat: Int) -> Raster {
        let d = Raster(22, 15)
        d.rectangle(3, 4, 16, 10, fill: c("cow_white"))
        d.rectangle(5, 5, 8, 8, fill: c("cow_black"))
        d.rectangle(12, 4, 14, 7, fill: c("cow_black"))
        d.rectangle(15, 2, 20, 7, fill: c("cow_white"))  // head
        d.rectangle(18, 5, 21, 7, fill: c("pink"))       // muzzle
        d.point(17, 3, fill: c("ink"))
        d.line(15, 1, 16, 2, fill: c("cow_black"))       // horn/ear
        d.line(3, 4, 1, beat != 0 ? 7 : 8, fill: c("cow_white"))  // tail
        for x in [4, 6, 13, 15] { d.line(x, 11, x, 13, fill: c("cow_black")) }
        d.rectangle(8, 10, 10, 11, fill: c("pink"))      // udder
        return outline(d)
    }
    out.append(Sprite(name: "cow", frames: [cow(0), cow(1)], ms: [600, 600]))

    // Revenuer's black sedan.
    func car(_ beat: Int) -> Raster {
        let d = Raster(32, 15)
        d.rectangle(1, 6, 30, 11, fill: c("black_car"))
        d.rectangle(7, 2, 23, 6, fill: c("black_car"))
        d.rectangle(9, 3, 14, 5, fill: c("glass_edge"))
        d.rectangle(16, 3, 21, 5, fill: c("glass_edge"))
        d.point(30, 7, fill: c("fire_hot"))  // headlight
        d.line(1, 9, 30, 9, fill: c("chrome"))
        for x in [6, 24] {
            d.ellipse(x - 2, 10, x + 2, 14, fill: c("tire"))
            d.point(x, beat != 0 ? 12 : 11, fill: c("chrome"))
        }
        return outline(d)
    }
    out.append(Sprite(name: "revenuer", frames: [car(0), car(1)], ms: [120, 120]))

    // Black bear on its hind legs.
    do {
        let d = Raster(18, 20)
        d.ellipse(3, 6, 14, 18, fill: c("cow_black"))
        d.ellipse(5, 1, 12, 8, fill: c("cow_black"))
        d.points([(5, 1), (12, 1)], fill: c("cow_black"))
        d.rectangle(7, 5, 10, 7, fill: c("tan"))
        d.points([(7, 4), (10, 4)], fill: c("white"))
        d.point(8, 6, fill: c("nose"))
        d.rectangle(1, 8, 3, 11, fill: c("cow_black"))  // paws up
        d.rectangle(14, 8, 16, 11, fill: c("cow_black"))
        out.append(Sprite(name: "bear", frames: [outline(d)], ms: [400]))
    }

    // Wild turkey, strutting.
    func turkey(_ beat: Int) -> Raster {
        let d = Raster(14, 13)
        d.ellipse(1, 1, 9, 10, fill: c("fur"))  // fanned tail
        d.arc(1, 1, 9, 10, start: 180, end: 360, fill: c("amber"))
        d.ellipse(5, 5, 11, 10, fill: c("beard_dark"))  // body
        d.line(10, 2, 10, 6, fill: c("beard_dark"))     // neck
        d.rectangle(10, 1, 12, 3, fill: c("stone"))
        d.point(12, 4, fill: c("red"))                  // wattle
        d.line(7, 10, 7 + beat, 12, fill: c("amber"))
        d.line(9, 10, 9 - beat, 12, fill: c("amber"))
        return outline(d)
    }
    out.append(Sprite(name: "turkey", frames: [turkey(0), turkey(1)], ms: [260, 260]))

    // Groundhog (whistle pig) up on its haunches.
    do {
        let d = Raster(10, 11)
        d.ellipse(2, 3, 8, 10, fill: c("fur"))
        d.ellipse(3, 0, 7, 4, fill: c("fur"))
        d.points([(4, 2), (6, 2)], fill: c("ink"))
        d.point(5, 3, fill: c("nose"))
        out.append(Sprite(name: "groundhog", frames: [outline(d)], ms: [400]))
    }

    // A hen pecking.
    func hen(_ beat: Int) -> Raster {
        let d = Raster(10, 10)
        d.ellipse(1, 3, 7, 8, fill: c("cow_white"))
        let y = beat == 0 ? 1 : 4
        d.rectangle(6, y, 8, y + 2, fill: c("cow_white"))
        d.point(7, y - 1, fill: c("red"))
        d.point(9, y + 1, fill: c("amber"))
        d.line(3, 8, 3, 9, fill: c("amber"))
        d.line(5, 8, 5, 9, fill: c("amber"))
        return outline(d)
    }
    out.append(Sprite(name: "hen", frames: [hen(0), hen(1)], ms: [300, 300]))

    // The pup that follows Blue.
    do {
        let d = Raster(13, 9)
        d.rectangle(2, 3, 8, 6, fill: c("tan"))
        d.rectangle(8, 1, 11, 5, fill: c("tan"))
        d.rectangle(8, 2, 8, 5, fill: c("fur"))
        d.point(10, 2, fill: c("ink"))
        d.point(11, 3, fill: c("nose"))
        for x in [3, 7] { d.line(x, 7, x, 8, fill: c("fur")) }
        d.line(2, 3, 0, 1, fill: c("tan"))
        out.append(Sprite(name: "pup", frames: [outline(d)], ms: [400]))
    }
    return out
}
