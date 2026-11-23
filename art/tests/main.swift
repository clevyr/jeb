// Unit tests for the sprite encoding (art/src/Palette.swift, Sprite.swift, Build.swift): quantize, rle, encode,
// outline and the pixel-art.ts text, each against the bytes the Python produced (Expected.swift). The drawing
// primitives have their own check, `jebart raster-check`. tests/run.sh builds and runs this.
import Foundation

final class Tester {
    var failures: [String] = []
    var count = 0
    private var current = ""

    func test(_ name: String, _ body: () throws -> Void) {
        current = name
        count += 1
        do { try body() } catch { fail("threw \(error)") }
    }

    func fail(_ what: String) { failures.append("\(current): \(what)") }

    func eq<T: Equatable>(_ got: T, _ want: T, _ what: String = "") {
        if got != want { fail("\(what)\(what.isEmpty ? "" : ": ")got \(String(reflecting: got)), want \(String(reflecting: want))") }
    }

    func report() -> Int32 {
        for f in failures { print("FAIL " + f) }
        print("\(count - failures.count) of \(count) tests passed")
        return failures.isEmpty ? 0 : 1
    }
}

func unhex(_ s: String) -> [UInt8] {
    let digits = Array(s.utf8).map { UInt8(String(UnicodeScalar($0)), radix: 16) ?? 0 }
    return stride(from: 0, to: digits.count - 1, by: 2).map { digits[$0] << 4 | digits[$0 + 1] }
}

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func image(_ w: Int, _ h: Int, _ rgba: String) -> Raster {
    let b = unhex(rgba)
    return Raster(w, h, pixels: (0..<(w * h)).map { RGBA(b[$0 * 4], b[$0 * 4 + 1], b[$0 * 4 + 2], b[$0 * 4 + 3]) })
}

/// An rle input: plain hex, or runs written `value*count` joined by `x`.
func indices(_ spec: String) -> [UInt8] {
    guard spec.contains("*") else { return unhex(spec) }
    return spec.split(separator: "x").flatMap { run -> [UInt8] in
        let p = run.split(separator: "*")
        return Array(repeating: UInt8(p[0]) ?? 0, count: Int(p[1]) ?? 0)
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
let t = Tester()

t.test("the palette has pixel.py's names in order, clear first") {
    t.eq(paletteNames.count, palette.count + 1)
    t.eq(paletteNames[0], "clear")
    t.eq(paletteNames[1], "ink")
    t.eq(paletteIndex["ink"], 1)
    t.eq(rgb("ink"), RGBA(palette[0].r, palette[0].g, palette[0].b, 255))
}

t.test("quantize maps every pixel to pixel.py's palette index") {
    // the input opens with every palette colour as is; two names share one colour, and the first one wins
    t.eq(hex(quantize(image(quantizeSize.0, quantizeSize.1, quantizeIn))), quantizeWant)
}

t.test("rle writes pixel.py's (run, index) pairs, runs capped at 255") {
    for (input, want) in rleCases { t.eq(hex(rle(indices(input))), want, input) }
}

t.test("encode gives the size and one base64 string a frame") {
    let got = encode(Sprite(name: "walk", frames: [image(6, 4, encodeFrame1), image(6, 4, encodeFrame2)], ms: [100, 100]))
    t.eq(got.w, encodeWant.0)
    t.eq(got.h, encodeWant.1)
    t.eq(got.frames, encodeWant.2)
}

t.test("outline inks the clear neighbours of pixels over half opaque") {
    let a = image(6, 5, outlineIn)
    t.eq(hex(outline(a).bytes), outlineWant)
    t.eq(hex(a.bytes), outlineWant, "drawn in place")
    t.eq(hex(outline(image(6, 5, outlineIn), color: outlineColour).bytes), outlineWantColour, outlineColour)
}

let tsSprites = [
    Sprite(name: "walk", frames: [image(6, 4, encodeFrame1), image(6, 4, encodeFrame2)], ms: [100, 100]),
    Sprite(name: "idle", frames: [image(6, 4, encodeFrame2)]),
    Sprite(name: "walk", frames: [image(6, 4, encodeFrame2), image(6, 4, encodeFrame1), image(6, 4, encodeFrame1)]),
]
let tsFont = [("A", "010101111101101"), ("AB", "111"), ("\u{e9}", "101"), ("\"", "000")]

t.test("tsText is write_ts's text, line for line") {
    let got = tsText(tsSprites, font: tsFont).components(separatedBy: "\n")
    t.eq(got.count, tsWant.count, "line count")
    for (i, (g, w)) in zip(got, tsWant).enumerated() { t.eq(g, w, "line \(i + 1)") }
}

t.test("writeTs writes that text and returns its size") {
    let path = NSTemporaryDirectory() + "/jebart-tests-\(getpid()).ts"
    defer { try? FileManager.default.removeItem(atPath: path) }
    t.eq(try writeTs(tsSprites, font: tsFont, to: path), tsWantSize)
    t.eq(FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }, tsWant.joined(separator: "\n"))
}

t.test("the palette and colour lines match the tracked mod/hooks/pixel-art.ts") {
    let repo = ProcessInfo.processInfo.environment["JEB_REPO"] ?? FileManager.default.currentDirectoryPath
    guard let data = FileManager.default.contents(atPath: repo + "/mod/hooks/pixel-art.ts") else { t.fail("cannot read mod/hooks/pixel-art.ts"); return }
    let tracked = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
    let got = tsText([], font: []).components(separatedBy: "\n")
    for i in 0..<9 where i < tracked.count { t.eq(got[i], tracked[i], "line \(i + 1)") }
}

t.test("every holiday costume dresses every pose: 16 base poses, 3 costumes, taller boxes") {
    let sprites = jebSprites()
    t.eq(sprites.count, 16 * 4)
    t.eq(costumes.map { $0.name }, ["halloween", "thanksgiving", "christmas"])
    for s in sprites {
        let costumed = s.name.contains("--")
        t.eq(s.size.w, jebW, s.name)
        t.eq(s.size.h, costumed ? jebH + headroom : jebH, s.name)
    }
    t.eq(sprites.filter { $0.name.hasSuffix("--thanksgiving") }.count, 16)
    t.eq(sprites.first { $0.name == "jeb-idle--christmas" }?.ms, [900, 900, 900, 160])
}

t.test("costumes differ where the holiday says: witch sleeves, a kept straw hat, scarves") {
    let plain = jeb(), witch = jeb(costume: witchCostume), harvest = jeb(costume: harvestCostume)
    t.eq(witch.height, 48)
    // the witch's frame has no straw hat crown at its old place (row 0 of the base is row 8 of the tall box)
    t.eq(witch[6, 8].a == 0 || witch[6, 8] != plain[6, 0], true, "no straw hat crown")
    // thanksgiving keeps the straw hat, so the crown is the same colour, shifted down the headroom
    t.eq(harvest[9, 8 + 1], plain[9, 1])
    t.eq(harvest.pixels != plain.pixels, true)
}

t.test("the hand variants wrap around: variant 6 is variant 0") {
    t.eq(hand(6, 1).pixels, hand(0, 1).pixels)
    t.eq(visitorSprites().filter { $0.name.hasPrefix("hand-work") }.count, 7)
}

t.test("jeb, blue, hand and visitor sprites match the tracked mod/hooks/pixel-art.ts") {
    let repo = ProcessInfo.processInfo.environment["JEB_REPO"] ?? FileManager.default.currentDirectoryPath
    guard let data = FileManager.default.contents(atPath: repo + "/mod/hooks/pixel-art.ts") else { t.fail("cannot read mod/hooks/pixel-art.ts"); return }
    let tracked = parseTs(String(decoding: data, as: UTF8.self))
    let mine = parseTs(tsText(jebSprites() + blueSprites() + visitorSprites(), font: []))
    t.eq(mine.order.count, 83)
    t.eq(diffTs(mine, tracked, only: ["jeb-", "blue-", "hand-", "opal", "cow", "revenuer", "bear", "turkey", "groundhog", "hen", "pup"]), [])
}

t.test("diff-ts names a changed, a missing and an extra sprite, and honours --only") {
    let a = parseTs("export const PIXEL_SPRITES = {\n  'a-1': { w: 2, h: 1, frames: ['AA==', 'BB=='] },\n  'a-2': { w: 1, h: 1, frames: ['AA=='] },\n  'b-1': { w: 1, h: 1, frames: ['AA=='] },\n}\n")
    let b = parseTs("export const PIXEL_SPRITES = {\n  'a-1': { w: 2, h: 1, frames: ['AA==', 'CC=='] },\n  'b-1': { w: 1, h: 1, frames: ['AA=='] },\n  'a-3': { w: 1, h: 1, frames: ['AA=='] },\n}\n")
    t.eq(a.sprites["a-1"]?.frames, ["AA==", "BB=="])
    t.eq(diffTs(a, b, only: []), ["differs: a-1", "only in first: a-2", "only in second: a-3"])
    t.eq(diffTs(a, b, only: ["b-"]), [])
    t.eq(diffTs(a, a, only: []), [])
    let c = parseTs("// hi\nexport const PIXEL_SPRITES = {\n}\n")
    t.eq(diffTs(c, parseTs("// ho\nexport const PIXEL_SPRITES = {\n}\n"), only: []), ["palette/colour/font lines differ"])
    t.eq(diffTs(c, parseTs("// ho\nexport const PIXEL_SPRITES = {\n}\n"), only: ["x"]), [])
}

farmTests(t)
imageTests(t)
exit(t.report())
