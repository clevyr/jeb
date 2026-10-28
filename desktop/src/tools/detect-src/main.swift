// detect <art.ts> <image> <queries>: finds sprites (and text labels) in a picture by
// exact colour, for the parity check. The picture is a PNG (the desktop's offscreen
// render) or a raw file "W H base64-rgba" (the band's composeScene output, as the
// mod's test printed it). Each query is a sprite name (every frame, both ways) or
// text:<colour>:<string>. Prints one line per match: name frame flip x y score,
// top-left in picture pixels (row 0 at the top). A match needs 85% of the
// sprite's opaque pixels to agree, so a little overlap still counts; overlapping
// matches of the same sprite keep the best.
import AppKit

let env = ProcessInfo.processInfo.environment
func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

let a = CommandLine.arguments
guard a.count >= 4 else { print("usage: detect art.ts image queries..."); exit(2) }
let artText = try! String(contentsOfFile: a[1], encoding: .utf8)
let parsed = try! parsePixelArt(artText)
let art = Art(parsed)

// The picture as colour words, top-down.
var W = 0, H = 0
var px: [UInt32] = []
if a[2].hasSuffix(".png") {
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[2])))!
    W = rep.pixelsWide; H = rep.pixelsHigh
    px = Array(repeating: 0, count: W * H)
    let data = rep.bitmapData!, row = rep.bytesPerRow, spp = rep.samplesPerPixel
    for y in 0..<H { for x in 0..<W {
        let o = y * row + x * spp
        let alpha = spp >= 4 ? Int(data[o + 3]) : 255
        px[y * W + x] = alpha < 128 ? 0 : word(Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
    } }
} else {
    let parts = try! String(contentsOfFile: a[2], encoding: .utf8).split(separator: " ")
    W = Int(parts[0])!; H = Int(parts[1])!
    let bytes = Data(base64Encoded: String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines))!
    px = Array(repeating: 0, count: W * H)
    bytes.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
        for i in 0..<(W * H) { px[i] = b[i * 4 + 3] < 128 ? 0 : word(Int(b[i * 4]), Int(b[i * 4 + 1]), Int(b[i * 4 + 2])) }
    }
}

/// A pattern: opaque pixels (dx, dy, colour).
struct Pattern { let name: String, frame: Int, flip: Bool, w: Int, h: Int; let pts: [(Int, Int, UInt32)] }

func patterns(_ q: String) -> [Pattern] {
    if q.hasPrefix("text:") {
        let bits = q.split(separator: ":", maxSplits: 2).map(String.init)
        let ink = art.colour(bits[1]), message = bits[2]
        var pts: [(Int, Int, UInt32)] = []
        for (i, ch) in message.enumerated() {
            for (b, bit) in art.glyph(ch).enumerated() where bit == "1" { pts.append((i * 4 + b % 3, b / 3, ink)) }
        }
        return [Pattern(name: q, frame: 0, flip: false, w: message.count * 4, h: 5, pts: pts)]
    }
    guard let s = art.sprite(q) else { return [] }
    var out: [Pattern] = []
    for f in 0..<s.frames.count { for flip in [false, true] {
        var pts: [(Int, Int, UInt32)] = []
        for y in 0..<s.h { for x in 0..<s.w {
            let i = s.frames[f][y * s.w + (flip ? s.w - 1 - x : x)]
            if i != 0 { pts.append((x, y, art.paletteWord(Int(i)))) }
        } }
        out.append(Pattern(name: q, frame: f, flip: flip, w: s.w, h: s.h, pts: pts))
    } }
    return out
}

/// Equal colours, give or take 2 a channel (the compositor's rounding on a moving layer).
@inline(__always) func near(_ a: UInt32, _ b: UInt32) -> Bool {
    if a == b { return true }
    if a == 0 || b == 0 { return false }
    for s: UInt32 in [0, 8, 16] { if abs(Int(a >> s & 255) - Int(b >> s & 255)) > 2 { return false } }
    return true
}

let need = Double(env["DETECT_NEED"] ?? "") ?? 0.85
for q in a.dropFirst(3) {
    var found: [(p: Pattern, x: Int, y: Int, score: Double)] = []
    for p in patterns(q) where p.pts.count >= 4 {
        let allowed = Int(Double(p.pts.count) * (1 - need))
        for y in -p.h / 3..<(H - p.h * 2 / 3) { for x in -p.w / 3..<(W - p.w * 2 / 3) {
            var miss = 0, inside = 0
            for (dx, dy, c) in p.pts {
                let X = x + dx, Y = y + dy
                guard X >= 0, X < W, Y >= 0, Y < H else { continue }
                inside += 1
                if !near(px[Y * W + X], c) { miss += 1; if miss > allowed { break } }
            }
            guard miss <= allowed, inside >= p.pts.count * 2 / 3 else { continue }
            let score = Double(inside - miss) / Double(p.pts.count)
            // Keep the best of overlapping matches of this query.
            if let k = found.firstIndex(where: { abs($0.x - x) < max(2, p.w / 2) && abs($0.y - y) < max(2, p.h / 2) }) {
                if score > found[k].score { found[k] = (p, x, y, score) }
            } else {
                found.append((p, x, y, score))
            }
        } }
    }
    for m in found.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
        print("\(q) \(m.p.frame) \(m.p.flip ? 1 : 0) \(m.x) \(m.y) \(String(format: "%.2f", m.score))")
    }
}
