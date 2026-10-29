// The mod's pixel art (parsed from hooks/pixel-art.ts as text, see PixelArt.swift)
// as CGImages at one pixel per art pixel, cached by name and frame, for layer
// contents (the layers scale them with nearest filtering); plus the 3x5 font and
// hand-painted layers.

import AppKit

/// A colour as a 32-bit word whose bytes are R, G, B, A in memory order.
func word(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> UInt32 {
    UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | UInt32(a) << 24
}

/// Two colour words mixed, `t` of the way from `a` to `b`.
func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    let ch = { (c: UInt32, s: UInt32) in Double(c >> s & 255) }
    let m = { (s: UInt32) in Int(ch(a, s) + (ch(b, s) - ch(a, s)) * t) }
    return word(m(0), m(8), m(16))
}

func makeImage(width: Int, height: Int, pixels: [UInt32]) -> CGImage {
    let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

/// A fixed speckle per pixel, the same hash the band uses for its ridges and road.
func speckle(_ x: Int, _ y: Int) -> Int {
    Int((UInt32(truncatingIfNeeded: x &* 73856093) ^ UInt32(truncatingIfNeeded: y &* 19349663)) % 100)
}

/// A hand-painted layer (sky, ridges, ground), addressed y-up like the layers.
struct Canvas {
    let w: Int, h: Int
    var px: [UInt32]
    init(w: Int, h: Int) { self.w = w; self.h = h; px = Array(repeating: 0, count: w * h) }
    mutating func set(_ x: Int, _ y: Int, _ c: UInt32) {
        if x >= 0, x < w, y >= 0, y < h { px[(h - 1 - y) * w + x] = c }
    }
    func image() -> CGImage { makeImage(width: w, height: h, pixels: px) }
}

final class Art {
    private let palette: [UInt32]
    private let colours: [String: Int]
    private let font: [String: String]
    private let sprites: [String: Sprite]
    private var cache: [String: CGImage] = [:]

    /// The holiday whose `<base>--<holiday>` variants stand in for their base sprites (Holiday.swift). Read at most once a
    /// minute; a test can set it and call refreshHoliday().
    var holidayName: () -> String? = { Holiday.current() }
    private var activeHoliday: String?
    private var variants: [String: String] = [:]
    private var holidayChecked = -Double.infinity
    /// How many rows taller than its base a holiday variant may be.
    static let variantHeadroom = 8

    init(_ data: PixelArt) {
        palette = data.palette
        colours = data.colours
        font = data.font
        // One synthesized sprite: a raindrop (1x3 of `drop`), as the band's rect.
        var all = data.sprites
        let drop = UInt8(clamping: data.colours["drop"] ?? 0)
        all["drop-px"] = Sprite(w: 1, h: 3, frames: [[drop, drop, drop]])
        sprites = all
    }

    /// Re-reads the holiday and rebuilds the base-to-variant map; true when the holiday changed. A variant stands in only
    /// when its width and frame count match its base and it is at most `variantHeadroom` rows taller (a costume's tall
    /// hat); every draw anchors a sprite at its feet, so a taller one grows upward. Otherwise it is skipped, quietly.
    @discardableResult
    func refreshHoliday() -> Bool {
        holidayChecked = CFAbsoluteTimeGetCurrent()
        let now = holidayName()
        guard now != activeHoliday else { return false }
        activeHoliday = now
        variants = [:]
        if let h = now {
            for (key, v) in sprites where key.hasSuffix("--" + h) {
                let base = String(key.dropLast(h.count + 2))
                if let b = sprites[base], b.w == v.w, v.h >= b.h, v.h <= b.h + Art.variantHeadroom, b.frames.count == v.frames.count { variants[base] = key }
            }
        }
        return true
    }

    /// The name a sprite is looked up under: its active-holiday variant if the art has a usable one, else itself.
    private func resolve(_ name: String) -> String {
        if abs(CFAbsoluteTimeGetCurrent() - holidayChecked) >= 60 { refreshHoliday() }
        return variants[name] ?? name
    }

    func colour(_ name: String) -> UInt32 { palette[colours[name] ?? 0] }
    func paletteWord(_ index: Int) -> UInt32 { palette.indices.contains(index) ? palette[index] : 0 }
    func colourIndex(_ name: String) -> Int { colours[name] ?? 0 }
    func sprite(_ name: String) -> Sprite? {
        let name = resolve(name)
        if let s = sprites[name] { return s }
        if let s = custom[name] { return s }
        log("art has no sprite \(name)")
        return nil
    }
    func has(_ name: String) -> Bool { let name = resolve(name); return sprites[name] != nil || custom[name] != nil }
    /// A glyph's 15 bits; a character the font lacks draws as a space.
    func glyph(_ ch: Character) -> String { font[String(ch)] ?? font[String(ch).uppercased()] ?? font[" "] ?? "" }
    func hasGlyph(_ ch: Character) -> Bool { font[String(ch)] != nil || font[String(ch).uppercased()] != nil }

    /// Custom pictures from the drops (surprise.ts artFrames): legend letters to
    /// palette indices, one pixel bigger on every side, with the ink outline round
    /// every opaque pixel. Kept by `art:<id>`, at most 16; a changed picture replaces itself.
    private(set) var custom: [String: Sprite] = [:]
    private var customSig: [String: [String]] = [:]
    func useArt(_ a: DropArt) -> String {
        let name = "art:\(a.id)"
        if customSig[name] == a.rows { return name }
        let ink = UInt8(clamping: colours["ink"] ?? 0)
        let w = a.w + 2, h = a.h + 2
        var frames: [[UInt8]] = []
        for f in 0..<a.frames {
            func at(_ x: Int, _ y: Int) -> UInt8 {
                guard x >= 0, y >= 0, x < a.w, y < a.h else { return 0 }
                let row = Array(a.rows[f * a.h + y])
                guard let name = DropArt.legend[row[x]], let i = colours[name] else { return 0 }
                return UInt8(clamping: i)
            }
            var out = [UInt8](repeating: 0, count: w * h)
            for y in 0..<h { for x in 0..<w {
                let own = at(x - 1, y - 1)
                if own != 0 { out[y * w + x] = own }
                else if at(x - 2, y - 1) != 0 || at(x, y - 1) != 0 || at(x - 1, y - 2) != 0 || at(x - 1, y) != 0 { out[y * w + x] = ink }
            } }
            frames.append(out)
        }
        if custom.count >= 16, custom[name] == nil, let drop = custom.keys.sorted().first { custom[drop] = nil; customSig[drop] = nil }
        custom[name] = Sprite(w: w, h: h, frames: frames)
        customSig[name] = a.rows
        for key in cache.keys where key.hasPrefix(name + "#") { cache[key] = nil }
        return name
    }

    func cgColor(_ name: String) -> CGColor {
        let c = colour(name)
        return CGColor(srgbRed: CGFloat(c & 255) / 255, green: CGFloat(c >> 8 & 255) / 255, blue: CGFloat(c >> 16 & 255) / 255, alpha: 1)
    }

    func frameCount(_ name: String) -> Int { let name = resolve(name); return (sprites[name] ?? custom[name])?.frames.count ?? 1 }

    /// One frame of a sprite, one pixel per art pixel (shared by every layer showing it).
    func image(_ name: String, _ frame: Int = 0) -> CGImage {
        let name = resolve(name) // the variant's own name is the cache key, so a variant and its base never share an entry
        let key = "\(name)#\(frame)"
        if let hit = cache[key] { return hit }
        guard let s = sprites[name] ?? custom[name] else {
            // A sprite the art no longer has draws as nothing rather than stopping the app.
            log("art has no sprite \(name)")
            cache[key] = makeImage(width: 1, height: 1, pixels: [0])
            return cache[key]!
        }
        let f = s.frames[frame % s.frames.count]
        let image = makeImage(width: s.w, height: s.h, pixels: f.map { palette[Int($0)] })
        cache[key] = image
        return image
    }

    func images(_ name: String) -> [CGImage] { (0..<frameCount(name)).map { image(name, $0) } }

    /// The top `rows` rows of a sprite's first frame, each pixel `scale` x `scale`
    /// (whole-number scaling, so it stays crisp), or nil if the art lacks it.
    func image(_ name: String, rows: Int, scale: Int) -> CGImage? {
        guard let s = sprites[resolve(name)], rows <= s.h else { return nil }
        let w = s.w * scale, h = rows * scale
        let pixels = (0..<(w * h)).map { i in palette[Int(s.frames[0][(i / w / scale) * s.w + (i % w) / scale])] }
        return makeImage(width: w, height: h, pixels: pixels)
    }

    /// The rows to crop from the top of `name` so the crop keeps `rows` rows of the base sprite plus any rows its active
    /// holiday variant adds on top (a tall hat stays in frame). `rows` itself when no taller variant is active.
    func headRows(_ name: String, _ rows: Int) -> Int {
        let resolved = resolve(name)
        guard let v = sprites[resolved], let b = sprites[name] else { return rows }
        return rows + max(0, v.h - b.h)
    }

    /// Paints a sprite frame into a canvas with its bottom-left at (x, y); `half`
    /// takes every other pixel, as the band's standHalf does. Clear pixels are skipped.
    func paint(_ name: String, frame: Int = 0, into c: inout Canvas, x: Int, y: Int, half: Bool = false) {
        guard let s = sprites[resolve(name)] else { log("art has no sprite \(name)"); return }
        let f = s.frames[frame % s.frames.count], step = half ? 2 : 1
        let w = s.w / step, h = s.h / step
        for row in 0..<h {
            for col in 0..<w {
                let index = f[row * step * s.w + col * step]
                if index != 0 { c.set(x + col, y + h - 1 - row, palette[Int(index)]) }
            }
        }
    }

    /// Paints text in the 3x5 font with its bottom-left at (x, y).
    func paintText(_ message: String, colour name: String, into c: inout Canvas, x: Int, y: Int) {
        let ink = colour(name)
        for (i, ch) in message.enumerated() {
            let bits = font[String(ch)] ?? font[String(ch).uppercased()] ?? font[" "] ?? ""
            for (b, bit) in bits.enumerated() where bit == "1" { c.set(x + i * 4 + b % 3, y + 4 - b / 3, ink) }
        }
    }

    func height(_ name: String) -> Int { let name = resolve(name); return (sprites[name] ?? custom[name])?.h ?? 0 }
    func width(_ name: String) -> Int { let name = resolve(name); return (sprites[name] ?? custom[name])?.w ?? 0 }
}

/// The band's short counts: 999, then 1.2k, 13k, 1.5M.
func abbrevCount(_ n: Int, room: Int = 5) -> String {
    let value = max(0, n)
    if value < 1000 { return String(value) }
    let unit = value >= 1_000_000 ? 1_000_000 : 1000
    let suffix = unit == 1000 ? "k" : "M"
    let tenths = value / (unit / 10)
    if tenths < 100 {
        let text = "\(tenths / 10)\(tenths % 10 == 0 ? "" : ".\(tenths % 10)")\(suffix)"
        if text.count <= room { return text }
    }
    return "\(tenths / 10)\(suffix)"
}

// MARK: - Band-style drawing (top-down, as the band's own canvas)

/// A box in a picture, top-down.
struct Box { var x: Int, y: Int, w: Int, h: Int
    func has(_ px: Int, _ py: Int) -> Bool { px >= x && px < x + w && py >= y && py < y + h }
    func hits(_ o: Box) -> Bool { !(x + w <= o.x || o.x + o.w <= x || y + h <= o.y || o.y + o.h <= y) }
}

/// A picture addressed top-down like the band's canvas (row 0 at the top), so the
/// band's drawing code ports line for line. Clear pixels are 0.
struct Pix {
    let w: Int, h: Int
    var px: [UInt32]
    init(w: Int, h: Int) { self.w = max(1, w); self.h = max(1, h); px = Array(repeating: 0, count: max(1, w) * max(1, h)) }
    func image() -> CGImage { makeImage(width: w, height: h, pixels: px) }
    var isEmpty: Bool { !px.contains { $0 != 0 } }

    mutating func dot(_ x: Int, _ y: Int, _ c: UInt32) { if x >= 0, x < w, y >= 0, y < h { px[y * w + x] = c } }
    mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: UInt32) {
        for yy in max(0, y)..<min(h, y + rh) where max(0, x) < min(w, x + rw) { for xx in max(0, x)..<min(w, x + rw) { px[yy * w + xx] = c } }
    }
    /// Mixes a pixel `parts` quarters of the way toward a colour (the band's `mix`).
    mutating func mixPx(_ x: Int, _ y: Int, _ c: UInt32, parts: UInt32 = 2) {
        guard x >= 0, x < w, y >= 0, y < h else { return }
        let o = px[y * w + x], keep = 4 - parts
        let ch = { (v: UInt32, s: UInt32) in v >> s & 255 }
        let m = { (s: UInt32) in (ch(o, s) * keep + ch(c, s) * parts) >> 2 }
        px[y * w + x] = m(0) | m(8) << 8 | m(16) << 16 | (o == 0 ? 255 : ch(o, 24)) << 24
    }
}

extension Art {
    /// A sprite frame with its top-left at (x, y) (the band's blit): flipped,
    /// dimmed (mixed half with what is beneath) or kept out of `avoid`.
    @discardableResult
    func blit(_ name: String, into c: inout Pix, x: Int, y: Int, frame: Int = 0, flip: Bool = false, dim: Bool = false, avoid: [Box] = []) -> Int {
        guard let s = sprite(name) else { return 0 }
        let f = s.frames[((frame % s.frames.count) + s.frames.count) % s.frames.count]
        for sy in 0..<s.h {
            let dy = y + sy
            guard dy >= 0, dy < c.h else { continue }
            for sx in 0..<s.w {
                let index = f[sy * s.w + (flip ? s.w - 1 - sx : sx)]
                guard index != 0 else { continue }
                let dx = x + sx
                guard dx >= 0, dx < c.w, !avoid.contains(where: { $0.has(dx, dy) }) else { continue }
                if dim { c.mixPx(dx, dy, paletteWord(Int(index))) } else { c.px[dy * c.w + dx] = paletteWord(Int(index)) }
            }
        }
        return s.w
    }

    /// A sprite standing on `bottom` (the row under its feet).
    @discardableResult
    func stand(_ name: String, into c: inout Pix, x: Int, bottom: Int, frame: Int = 0, flip: Bool = false, dim: Bool = false, avoid: [Box] = []) -> Int {
        blit(name, into: &c, x: x, y: bottom - height(name), frame: frame, flip: flip, dim: dim, avoid: avoid)
    }

    /// Half size (every other pixel), standing on `bottom` (the band's standHalf).
    func standHalf(_ name: String, into c: inout Pix, x: Int, bottom: Int) {
        guard let s = sprite(name) else { return }
        let hw = s.w >> 1, hh = s.h >> 1
        for sy in 0..<hh { for sx in 0..<hw {
            let index = s.frames[0][sy * 2 * s.w + sx * 2]
            if index != 0 { c.dot(x + sx, bottom - hh + sy, paletteWord(Int(index))) }
        } }
    }

    /// The 3x5 font, top-left at (x, y); lower case reads as capitals. Returns the width drawn.
    @discardableResult
    func text(_ message: String, into c: inout Pix, x: Int, y: Int, colour: UInt32) -> Int {
        var cx = x
        for ch in message {
            let bits = glyph(ch)
            for (b, bit) in bits.enumerated() where bit == "1" { c.dot(cx + b % 3, y + b / 3, colour) }
            cx += 4
        }
        return cx - x - 1
    }
}

func textWidth(_ s: String) -> Int { s.isEmpty ? 0 : s.count * 4 - 1 }
