// Sprite: a named set of frames, and the steps that turn a frame into what the mod composites at runtime: every pixel
// mapped to its nearest palette index, run-length pairs, base64. The bytes must match what the original Python produced, since
// mod/hooks/pixel-art.ts is tracked and compared byte for byte.
import Foundation

/// One or more frames of the same size, plus per-frame durations for previews (the mod times its own frames).
struct Sprite {
    var name: String
    var frames: [Raster]
    var ms: [Int] = []
    /// Where the sprite stands: offset of its "feet" from the bottom-left, used by the scene composer.
    var anchor: (Int, Int) = (0, 0)

    var size: (w: Int, h: Int) { (frames[0].width, frames[0].height) }
}

/// A 1px outline around every opaque pixel, inside the sprite's box. Draws on `image` and returns it.
@discardableResult
func outline(_ image: Raster, color: String = "ink") -> Raster {
    let src = image.copy()
    let w = image.width, h = image.height
    let ink = rgb(color)
    for y in 0..<h {
        for x in 0..<w where src[x, y].a == 0 {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                if nx >= 0 && nx < w && ny >= 0 && ny < h && src[nx, ny].a > 128 {
                    image[x, y] = ink
                    break
                }
            }
        }
    }
    return image
}

/// Every pixel's palette index (nearest colour by squared distance, the first on a tie), 0 for alpha under 128.
func quantize(_ image: Raster) -> [UInt8] {
    var cache: [RGBA: UInt8] = [:]
    var out: [UInt8] = []
    out.reserveCapacity(image.width * image.height)
    for p in image.pixels {
        if p.a < 128 { out.append(0); continue }
        let key = RGBA(p.r, p.g, p.b, 255)
        if let hit = cache[key] { out.append(hit); continue }
        var best = 0, bestDistance = Int.max
        for (i, c) in palette.enumerated() {
            let dr = Int(c.r) - Int(p.r), dg = Int(c.g) - Int(p.g), db = Int(c.b) - Int(p.b)
            let d = dr * dr + dg * dg + db * db
            if d < bestDistance { bestDistance = d; best = i + 1 }
        }
        cache[key] = UInt8(best)
        out.append(UInt8(best))
    }
    return out
}

/// Run-length pairs: (run length 1..255, palette index).
func rle(_ indices: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var i = 0
    while i < indices.count {
        let value = indices[i]
        var run = 1
        while i + run < indices.count && indices[i + run] == value && run < 255 { run += 1 }
        out.append(UInt8(run))
        out.append(value)
        i += run
    }
    return out
}

/// Runtime form for the mod: size and RLE base64 per frame.
func encode(_ sprite: Sprite) -> (w: Int, h: Int, frames: [String]) {
    let (w, h) = sprite.size
    return (w, h, sprite.frames.map { Data(rle(quantize($0))).base64EncodedString() })
}
