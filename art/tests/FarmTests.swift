// Unit tests for the farm and nature sprites (art/src/Farm.swift, Nature.swift): the text helper's width and advance,
// the moon phases, and the sprite lists' shape. Their pixels are checked against the tracked pixel-art.ts by
// `jebart build` + `jebart diff-ts` (golden art/generators.txt).
import Foundation

func farmTests(_ t: Tester) {
    func opaque(_ r: Raster) -> Int { r.pixels.filter { $0.a != 0 }.count }

    t.test("drawText returns 4 a character minus the gap, upper-cases and blanks unknown characters") {
        let d = Raster(20, 5)
        t.eq(drawText(d, 0, 0, "ab", "white"), 7)
        t.eq(drawText(d, 0, 0, ""), -1)
        // 'A' is 010 101 111 101 101: the top row has only its middle pixel
        t.eq(d[1, 0], rgb("white")); t.eq(d[0, 0], RGBA.clear); t.eq(d[0, 1], rgb("white"))
        // 'B' starts one advance (4px) later
        t.eq(d[4, 0], rgb("white")); t.eq(d[6, 0], RGBA.clear)
        let e = Raster(8, 5)
        t.eq(drawText(e, 0, 0, "~"), 3)
        t.eq(opaque(e), 0)
    }

    t.test("the font keeps farm.py's order, and every glyph is 15 bits") {
        t.eq(farmFont.first?.0, "A")
        t.eq(farmFont.last?.0, "#")
        t.eq(farmFont.count, 56)
        t.eq(farmFont.filter { $0.1.count != 15 }.count, 0)
    }

    t.test("moon phases: new is grey, full is untouched, crescents erase part of the disc") {
        let full = opaque(moonSprite(4))
        t.eq(moonSprite(0)[4, 4], rgb("grey"))
        t.eq(moonSprite(4)[4, 4], rgb("moon"))
        t.eq(moonSprite(1)[4, 4], RGBA.clear)
        for p in [1, 2, 3, 5, 6, 7] { t.eq(opaque(moonSprite(p)) < full, true, "phase \(p)") }
        t.eq(moonSprite(3)[8, 4], rgb("moon"))   // waxing crescent keeps the right edge
        t.eq(moonSprite(5)[0, 4], rgb("moon"))   // waning keeps the left
    }

    t.test("farm and nature sprites have unique names, equal frame sizes and a duration per frame") {
        let all = farmSprites() + unlockSprites()
        t.eq(Set(all.map { $0.name }).count, all.count)
        for s in all {
            t.eq(s.frames.allSatisfy { $0.width == s.size.w && $0.height == s.size.h }, true, s.name)
            t.eq(s.ms.isEmpty || s.ms.count == s.frames.count, true, s.name)
        }
        t.eq(all.first { $0.name == "moon" }?.frames.count, 8)
        t.eq(all.first { $0.name == "sign" }?.size.w, 46)
    }
}
