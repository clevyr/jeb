// Logo (logo.py): the animated SVG, the still PNG and the plugin icon, built from the runtime sprite data the mod
// uses (mod/hooks/pixel-art.ts): Jeb playing the banjo with Blue at his side, and a pixel wordmark beside them. The SVG
// text and both PNGs are byte-identical to what logo.py wrote (docs/logo.svg, docs/logo.png, mod/.claude-plugin/icon.png).
import Foundation

typealias Colour = (r: UInt8, g: UInt8, b: UInt8)
typealias Grid = [[Colour?]]

struct LogoError: Error, CustomStringConvertible {
    var description: String
}

// (sprite, x, ms per frame); both stand on the bottom row.
private let logoCast: [(name: String, x: Int, ms: Int)] = [("blue-wag", 0, 250), ("jeb-banjo", 20, 260)]
private let pngScale = 8
private let logoFill: Colour = (0xE0, 0x9A, 0x34)
private let logoShadow: Colour = (0x5C, 0x38, 0x1C)

// 5x7 letters for the wordmark, drawn 3x.
private let logoLetters: [Character: [String]] = [
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
]
private let letterScale = 3
private let logoGap = 6
private let iconPad = 2
private let iconScale = 12

private func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
    // the patterns are literals in this file; a bad one is a bug
    // swiftlint:disable:next force_try
    let re = try! NSRegularExpression(pattern: pattern)
    return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
}

private func group(_ m: NSTextCheckingResult, _ i: Int, _ text: String) -> String {
    Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
}

/// A sprite's frames from pixel-art.ts: the palette, then the RLE (run, index) pairs of each frame, as grids of colours.
func loadFrames(_ ts: String, _ name: String) throws -> [Grid] {
    guard let pm = matches(#"PIXEL_PALETTE[^=]*=\s*\[([^\]]*)\]"#, in: ts).first else { throw LogoError(description: "no PIXEL_PALETTE in the sprite data") }
    let palette = group(pm, 1, ts).split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    let escaped = NSRegularExpression.escapedPattern(for: name)
    guard let sm = matches("'\(escaped)':\\s*\\{\\s*w:\\s*(\\d+),\\s*h:\\s*(\\d+),\\s*frames:\\s*\\[([^\\]]*)\\]", in: ts).first,
          let w = Int(group(sm, 1, ts)), let h = Int(group(sm, 2, ts)) else {
        throw LogoError(description: "no sprite named \(name) in the sprite data")
    }
    let list = group(sm, 3, ts)
    var frames: [Grid] = []
    for fm in matches("'([A-Za-z0-9+/=]*)'", in: list) {
        guard let raw = Data(base64Encoded: group(fm, 1, list)) else { throw LogoError(description: "bad base64 in \(name)") }
        let bytes = [UInt8](raw)
        var flat: [Colour?] = []
        var i = 0
        while i + 1 < bytes.count {
            let run = Int(bytes[i]), index = Int(bytes[i + 1])
            let c = palette[index]
            let colour: Colour? = index == 0 ? nil : (UInt8((c >> 16) & 255), UInt8((c >> 8) & 255), UInt8(c & 255))
            flat += Array(repeating: colour, count: run)
            i += 2
        }
        frames.append((0..<h).map { y in Array(flat[(y * w)..<((y + 1) * w)]) })
    }
    return frames
}

private func blankGrid(_ w: Int, _ h: Int) -> Grid { Array(repeating: Array(repeating: nil, count: w), count: h) }

private func paste(_ grid: inout Grid, _ sprite: Grid, _ x0: Int, _ y0: Int) {
    for (y, row) in sprite.enumerated() {
        for (x, c) in row.enumerated() where c != nil { grid[y0 + y][x0 + x] = c }
    }
}

private struct Composed {
    var width: Int
    var height: Int
    var word: Grid
    var layers: [(grids: [Grid], ms: Int)]
}

private func compose(_ ts: String) throws -> Composed {
    let cast = try logoCast.map { (frames: try loadFrames(ts, $0.name), x: $0.x, ms: $0.ms) }
    let height = cast.map { $0.frames[0].count }.max() ?? 0
    let castW = cast.map { $0.x + $0.frames[0][0].count }.max() ?? 0
    let wordW = logoLetters.count * 5 * letterScale + (logoLetters.count - 1) * letterScale
    let wordH = 7 * letterScale
    let width = castW + logoGap + wordW + 2
    var word = blankGrid(width, height)
    let x0 = castW + logoGap, y0 = (height - wordH) / 2
    for (d, colour) in [(2, logoShadow), (0, logoFill)] {
        for (i, ch) in "JEB".enumerated() {
            let lx = x0 + i * 6 * letterScale
            for (r, bits) in (logoLetters[ch] ?? []).enumerated() {
                for (c, bit) in bits.enumerated() where bit == "1" {
                    for yy in 0..<letterScale {
                        for xx in 0..<letterScale {
                            word[y0 + d + r * letterScale + yy][lx + d + c * letterScale + xx] = colour
                        }
                    }
                }
            }
        }
    }
    var layers: [(grids: [Grid], ms: Int)] = []
    for (frames, x, ms) in cast {
        var grids: [Grid] = []
        for f in frames {
            var g = blankGrid(width, height)
            paste(&g, f, x, height - f.count)
            grids.append(g)
        }
        layers.append((grids, ms))
    }
    return Composed(width: width, height: height, word: word, layers: layers)
}

private func hex2(_ v: UInt8) -> String { String(format: "%02x", v) }

private func rects(_ grid: Grid) -> [String] {
    var out: [String] = []
    for (y, row) in grid.enumerated() {
        var x = 0
        while x < row.count {
            guard let c = row[x] else { x += 1; continue }
            var end = x
            while end < row.count, let e = row[end], e == c { end += 1 }
            out.append("<rect x=\"\(x)\" y=\"\(y)\" width=\"\(end - x)\" height=\"1\" fill=\"#\(hex2(c.r))\(hex2(c.g))\(hex2(c.b))\"/>")
            x = end
        }
    }
    return out
}

/// Python's format(x, "g").
private func g(_ v: Double) -> String { String(format: "%g", v) }

private func svgText(_ c: Composed) -> String {
    // Each frame is a group shown for its share of the loop (step timing, so frames swap cleanly).
    var style = "", groups: [String] = []
    for (i, layer) in c.layers.enumerated() {
        let n = layer.grids.count
        for (k, grid) in layer.grids.enumerated() {
            let name = "s\(i)f\(k)"
            if n > 1 {
                let start = 100 * Double(k) / Double(n), end = 100 * Double(k + 1) / Double(n)
                var keys = ["0%{opacity:\(k == 0 ? 1 : 0)}"]
                if k > 0 { keys.append("\(g(start))%{opacity:1}") }
                if end < 100 { keys.append("\(g(end))%{opacity:0}") }
                style += "@keyframes \(name){\(keys.joined())}"
                    + ".\(name){\(k == 0 ? "" : "opacity:0;")animation:\(name) \(layer.ms * n)ms step-end infinite}"
            }
            groups.append("<g class=\"\(name)\">\n" + rects(grid).joined(separator: "\n") + "\n</g>")
        }
    }
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(c.width) \(c.height)\" width=\"\(c.width * pngScale)\" "
        + "height=\"\(c.height * pngScale)\" shape-rendering=\"crispEdges\">\n<title>Jeb</title>\n"
        + "<style>\(style)</style>\n" + groups.joined(separator: "\n") + "\n" + rects(c.word).joined(separator: "\n") + "\n</svg>\n"
}

/// logo.py's png(): every grid cell becomes k x k pixels; None is transparent.
private func logoPng(_ grid: Grid, _ k: Int) -> [UInt8] {
    let h = grid.count, w = grid[0].count
    var raw: [UInt8] = []
    raw.reserveCapacity(h * k * (1 + w * k * 4))
    for row in grid {
        var line: [UInt8] = [0]
        for c in row {
            let px: [UInt8] = c.map { [$0.r, $0.g, $0.b, 255] } ?? [0, 0, 0, 0]
            for _ in 0..<k { line += px }
        }
        for _ in 0..<k { raw += line }
    }
    return pngEncode(width: w * k, height: h * k, scanlines: raw, level: 9)
}

/// The cast alone (first frame), centred on a square with `iconPad` around it.
private func iconGrid(_ ts: String) throws -> Grid {
    let cast = try logoCast.map { (frame: try loadFrames(ts, $0.name)[0], x: $0.x) }
    let w = cast.map { $0.x + $0.frame[0].count }.max() ?? 0
    let h = cast.map { $0.frame.count }.max() ?? 0
    let side = max(w, h) + 2 * iconPad
    var grid = blankGrid(side, side)
    let x0 = (side - w) / 2, y0 = (side - h) / 2
    for (f, x) in cast { paste(&grid, f, x0 + x, y0 + h - f.count) }
    return grid
}

/// logo.py's main: `<outDir>/logo.svg` and `<outDir>/logo.png`, and with `iconPath` the plugin icon.
func writeLogo(tsPath: String, outDir: String, iconPath: String?) throws {
    let ts = try String(contentsOfFile: tsPath, encoding: .utf8)
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let c = try compose(ts)
    try Data(svgText(c).utf8).write(to: URL(fileURLWithPath: outDir + "/logo.svg"))
    var still = blankGrid(c.width, c.height)
    for layer in c.layers { paste(&still, layer.grids[0], 0, 0) }
    paste(&still, c.word, 0, 0)
    try Data(logoPng(still, pngScale)).write(to: URL(fileURLWithPath: outDir + "/logo.png"))
    if let iconPath {
        try Data(logoPng(try iconGrid(ts), iconScale)).write(to: URL(fileURLWithPath: iconPath))
    }
}
