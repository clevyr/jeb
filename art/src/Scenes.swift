// Scenes (build.py's Scene and mockups): three full-band mockups at 150 columns, 3x, for review: a busy day, an evening
// with the banjo, and the night. They stamp the finished sprites onto a band-sized canvas, with the 3x5 font for the
// plot labels, so they show what the mod composites at runtime.
import Foundation

/// A band-sized canvas. Columns x 4 by rows x 8 pixels.
final class Scene {
    let sprites: [String: Sprite]
    let w: Int
    let h: Int
    let img: Raster
    let ground: Int      // top of the grass strip

    init(_ sprites: [String: Sprite], cols: Int = 150, rows: Int = 6, night: Bool = false) {
        self.sprites = sprites
        w = cols * cellW
        h = rows * cellH
        let sky = night ? RGBA(34, 40, 70) : RGBA(150, 200, 235)
        img = Raster(w, h, fill: sky)
        ground = h - 9
    }

    @discardableResult
    func stamp(_ name: String, _ x: Int, bottom: Int? = nil, frame: Int = 0, y: Int? = nil) -> Int {
        guard let sprite = sprites[name] else { preconditionFailure("no sprite named \(name)") }
        let image = sprite.frames[frame % sprite.frames.count]
        let top = y ?? ((bottom ?? ground) - image.height)
        img.alphaComposite(image, at: x, top)
        return image.width
    }

    func land() {
        img.rectangle(0, ground, w, ground + 1, fill: rgb("grass"))
        img.rectangle(0, ground + 2, w, h, fill: rgb("road"))
        for x in stride(from: 0, to: w, by: 12) {
            img.line(x, h - 3, x + 5, h - 3, fill: rgb("road_dark"))
        }
    }

    func plots(_ stages: [String: [Int]], _ labels: [String: String]) -> Int {
        var x = 2
        for crop in ["tobacco", "corn"] {
            img.rectangle(x, ground - 2, x + 49, ground, fill: rgb("soil"))
            for (i, stage) in (stages[crop] ?? []).enumerated() {
                stamp("\(crop)-\(stage)", x + 1 + i * 6, bottom: ground)
            }
            drawText(img, x + 2, h - 7, labels[crop] ?? "", "white")
            x += 56
        }
        for (i, stage) in (stages["apples"] ?? []).prefix(4).enumerated() {
            stamp("apple-\(stage)", x + i * 11, bottom: ground)
        }
        drawText(img, x + 2, h - 7, labels["apples"] ?? "", "white")
        return x + 46
    }

    /// Image.resize(NEAREST) and a PNG: each 4x8 block shows as the one cell the terminal uses.
    func png(scale: Int = 3) -> [UInt8] {
        pngEncode(img.resized(w * scale, h * scale), level: 9)
    }
}

/// build.py's mockups(): the three scene PNGs, written into `out`; returns their paths in order.
func writeMockups(_ sprites: [Sprite], to out: String) throws -> [String] {
    var by: [String: Sprite] = [:]
    for s in sprites { by[s.name] = s }
    let stages = ["tobacco": [3, 3, 2, 2, 1, 3, 2, 1], "corn": [3, 2, 3, 1, 2, 3, 0, 1], "apples": [3, 3, 2, 1]]
    let labels = ["tobacco": "TOBACCO 6", "corn": "CORN 5", "apples": "APPLES 118"]
    var paths: [String] = []

    @discardableResult
    func rightCluster(_ sc: Scene, _ jeb: String, night: Bool, lit: Bool, jebFrame: Int = 0,
                      extras: [(String, Int, Int)] = []) -> Int {
        let house = night ? "house-night" : "house"
        let hx = sc.w - 51
        sc.stamp(house, hx, bottom: sc.ground + 1)
        sc.stamp("smoke", hx + 34, frame: 1, y: 0)
        let sx = hx - 40
        sc.stamp("still", sx, bottom: sc.ground)
        sc.stamp(lit ? "fire" : "embers", sx + 3, bottom: sc.ground, frame: jebFrame)
        if lit { sc.stamp("steam", sx + 7, frame: jebFrame, y: 0) }
        let jx = sx - 22
        sc.stamp(jeb, jx, bottom: sc.ground + 1, frame: jebFrame)
        sc.stamp(night ? "blue-nap" : "blue-wag", jx - 20, bottom: sc.ground + 1)
        for (name, x, y) in extras { sc.stamp(name, x, y: y) }
        return jx
    }

    func middle(_ sc: Scene, _ start: Int, night: Bool, quilt: String, lanterns: Int) {
        let stack = [("icon-lumber", 3), ("icon-stone", 3), ("icon-straw", 2), ("icon-iron", 2), ("icon-twist", 1)]
        let x = start + 6
        let lineY = 4
        sc.img.line(x - 2, lineY, x + quilt.count * 6 + 1, lineY, fill: rgb("wood_dark"))
        for (i, code) in quilt.enumerated() { sc.stamp("quilt-\(code)", x + i * 6, y: lineY + 1) }
        for (col, (name, height)) in stack.enumerated() {
            for k in 0..<height { sc.stamp(name, x + col * 9, bottom: sc.ground - k * 8) }
        }
        let sign = night ? "sign-night" : "sign"
        let sgx = x + stack.count * 9 + 8
        sc.stamp(sign, sgx, bottom: sc.ground + 1)
        for i in 0..<lanterns { sc.stamp("lantern", sgx + 14 + i * 8, y: 1) }
    }

    func save(_ sc: Scene, _ name: String) throws {
        let path = out + "/" + name
        try Data(sc.png()).write(to: URL(fileURLWithPath: path))
        paths.append(path)
    }

    // Day, busy: hoeing, hired hands, the truck on the road, rain on the corn.
    var sc = Scene(by)
    sc.land()
    var end = sc.plots(stages, labels)
    sc.stamp("hand-work", 14, bottom: sc.ground + 1, frame: 0)
    sc.stamp("hand-work", 72, bottom: sc.ground + 1, frame: 1)
    for x in stride(from: 58, to: 108, by: 7) {
        sc.img.line(x, 6, x - 1, 9, fill: rgb("drop"))
        sc.img.line(x + 3, 13, x + 2, 16, fill: rgb("drop"))
    }
    sc.stamp("cloud-dark", 66, y: 0)
    middle(sc, end, night: false, quilt: "NBGGPBRG", lanterns: 0)
    var jx = rightCluster(sc, "jeb-hoe", night: false, lit: true)
    sc.stamp("sun", jx - 60, y: 2)
    sc.stamp("truck-jars", 250, bottom: sc.h)
    sc.stamp("dust", 240, bottom: sc.h - 2)
    try save(sc, "scene-day-busy.png")

    // Evening: banjo on the porch, lanterns for the other camps, still lit.
    sc = Scene(by)
    sc.land()
    end = sc.plots(stages, labels)
    sc.stamp("cow", 300, bottom: sc.h)
    middle(sc, end, night: false, quilt: "NBGGPBRGYB", lanterns: 2)
    jx = rightCluster(sc, "jeb-banjo", night: false, lit: true)
    sc.stamp("note", jx - 6, y: 6)
    sc.stamp("note", jx - 12, y: 1)
    try save(sc, "scene-evening-banjo.png")

    // Night: asleep on the porch, moon and fireflies, windows lit, embers.
    sc = Scene(by, night: true)
    sc.land()
    end = sc.plots(stages, labels)
    for (x, y) in [(30, 3), (90, 6), (140, 2), (200, 5), (330, 4), (420, 2), (470, 7)] {
        sc.img.point(x, y, fill: rgb("night_star"))
    }
    for (x, y) in [(20, 20), (64, 24), (110, 18)] { sc.stamp("firefly", x, y: y) }
    middle(sc, end, night: true, quilt: "NBGGPBRGYB", lanterns: 2)
    jx = rightCluster(sc, "jeb-sleep", night: true, lit: false)
    sc.stamp("moon", jx - 60, frame: 2, y: 2)
    sc.stamp("zz", jx + 14, y: 0)
    sc.stamp("mothman", 160, y: 8)
    try save(sc, "scene-night.png")
    return paths
}
