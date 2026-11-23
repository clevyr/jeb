// Gif: the animated previews (pixel.py's save_gif, which Pillow's GIF writer turned into bytes). Each sprite with two
// or more frames becomes one GIF at 4x: an exact palette of at most 63 colours plus transparency, disposal 2 (restore to
// background), loop forever, and identical consecutive frames merged with their durations added. What the tests compare
// is the decoded frames (ImageIO), not the file bytes, but the writer follows Pillow's layout (a global palette from the
// first frame, a local palette and a cropped rectangle on the rest, 8-bit minimum code size, 255-byte data blocks) so
// the sizes, and the summary line's gif byte total, come out the same.
import Foundation

struct GifError: Error, CustomStringConvertible {
    var description: String
}

/// GIF-flavoured LZW (variable width from 9 bits, clear code 256, end code 257, table reset when it reaches 4096), as one
/// bit stream, least significant bit first. Not split into data blocks.
func lzwEncode(_ pixels: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var acc: UInt32 = 0, nbits = 0
    func put(_ code: Int, _ width: Int) {
        acc |= UInt32(code) << UInt32(nbits)
        nbits += width
        while nbits >= 8 { out.append(UInt8(acc & 255)); acc >>= 8; nbits -= 8 }
    }
    let clear = 256, end = 257
    var size = 9, next = 258
    var dict: [Int: Int] = [:]
    put(clear, size)
    guard var cur = pixels.first.map(Int.init) else {
        put(end, size)
        if nbits > 0 { out.append(UInt8(acc & 255)) }
        return out
    }
    for p in pixels.dropFirst() {
        let c = Int(p)
        let key = cur << 8 | c
        if let code = dict[key] { cur = code; continue }
        put(cur, size)
        if next < 4096 {
            dict[key] = next
            next += 1
            if next > (1 << size) && size < 12 { size += 1 }
        } else {
            put(clear, size)
            dict.removeAll(keepingCapacity: true)
            size = 9
            next = 258
        }
        cur = c
    }
    put(cur, size)
    // the decoder adds one more entry on reading `cur`, and sizes the end code for it
    var endSize = size
    if next < 4096 && next + 1 > (1 << size) && size < 12 { endSize += 1 }
    put(end, endSize)
    if nbits > 0 { out.append(UInt8(acc & 255)) }
    return out
}

/// An indexed frame: one palette index a pixel, row-major, plus the palette used (in index order).
struct IndexedFrame {
    var width: Int
    var height: Int
    var pixels: [UInt8]
    var palette: [(r: UInt8, g: UInt8, b: UInt8)]
    /// The transparent index, one past the end of `palette` (nil when the frame has none).
    var transparent: Int?
    /// The transparency index the graphic control extension declares. Pillow keeps its transparency=63 for a frame it
    /// does not remap: a frame without transparent pixels has no unused palette entries, and a palette with none never
    /// shrinks (_get_optimize), so the declaration stays.
    var declaredTransparent: Int?

    /// What a viewer sees: colour per pixel, nil where transparent.
    var visible: [UInt32] {
        pixels.map { i in
            if Int(i) == transparent { return 0xFFFF_FFFF }
            let c = palette[Int(i)]
            return UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
        }
    }
}

/// pixel.py's save_gif quantize step for one frame: the 4x enlarged frame through Pillow's median cut (63 colours, every
/// pixel's RGB counted, transparent ones too), pixels under alpha 128 sent to the transparent index, then the writer's
/// optimize step: only the palette entries the opaque pixels use are kept, in median-cut order, the transparent index
/// just past them (the palette stops at the last opaque colour; every decoder reads the index past the end as transparent).
func indexFrame(_ frame: Raster, scale: Int) throws -> IndexedFrame {
    let big = frame.resized(frame.width * scale, frame.height * scale)
    let rgb = big.pixels.map { UInt32($0.r) << 16 | UInt32($0.g) << 8 | UInt32($0.b) }
    let cut = try pillowMedianCut(rgb, colors: 63)
    var used = Set<Int>()
    var hasTransparent = false
    for (i, p) in big.pixels.enumerated() {
        if p.a < 128 { hasTransparent = true } else { used.insert(cut.indices[i]) }
    }
    let kept = used.sorted()
    var slot: [Int: Int] = [:]
    for (n, i) in kept.enumerated() { slot[i] = n }
    var out: [UInt8] = []
    out.reserveCapacity(big.pixels.count)
    for (i, p) in big.pixels.enumerated() { out.append(UInt8(p.a < 128 ? kept.count : slot[cut.indices[i]]!)) }
    let palette = kept.map { i -> (r: UInt8, g: UInt8, b: UInt8) in
        let c = cut.palette[i]
        return (r: UInt8(c >> 16), g: UInt8((c >> 8) & 255), b: UInt8(c & 255))
    }
    return IndexedFrame(width: big.width, height: big.height, pixels: out, palette: palette, transparent: hasTransparent ? kept.count : nil,
                        declaredTransparent: hasTransparent ? kept.count : 63)
}

/// Whether two frames have the same palette. Pillow compares the palette bytes: the same colours in the same order (and
/// both, or neither, with the transparent entry).
private func samePalette(_ a: IndexedFrame, _ b: IndexedFrame) -> Bool {
    func key(_ f: IndexedFrame) -> [UInt32] { f.palette.map { UInt32($0.r) << 16 | UInt32($0.g) << 8 | UInt32($0.b) } }
    return key(a) == key(b) && (a.transparent == nil) == (b.transparent == nil)
}

private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }

/// Pillow's colour table size field: the table is padded to a power of two (four entries at the least).
private func colourTableField(_ colours: Int) -> Int {
    if colours <= 2 { return 1 }
    var bits = 0
    while (1 << bits) < colours { bits += 1 }
    return bits - 1
}

private func paddedPalette(_ palette: [(r: UInt8, g: UInt8, b: UInt8)]) -> [UInt8] {
    var bytes = palette.flatMap { [$0.r, $0.g, $0.b] }
    let entries = 2 << colourTableField(palette.count)
    bytes += [UInt8](repeating: 0, count: (entries - palette.count) * 3)
    return bytes
}

private func dataBlocks(_ data: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var i = 0
    while i < data.count {
        let n = min(255, data.count - i)
        out.append(UInt8(n))
        out += data[i..<(i + n)]
        i += n
    }
    out.append(0)
    return out
}

/// The animated GIF for a sprite's frames: frames with the same picture next to each other are merged (durations
/// added), then written with disposal 2 and an endless loop. Returns nil for a single-frame sprite (no GIF is made).
func gifBytes(frames: [Raster], ms: [Int], scale: Int = 4) throws -> [UInt8]? {
    guard frames.count >= 2 else { return nil }
    let durations = ms.isEmpty ? Array(repeating: 200, count: frames.count) : ms
    // identical consecutive frames, by pixel data (pixel.py), then again by what shows once quantized (Pillow's writer)
    var kept: [(frame: Raster, ms: Int)] = []
    var previousBytes: [UInt8]?
    for (frame, d) in zip(frames, durations) {
        let bytes = frame.bytes
        if bytes == previousBytes, !kept.isEmpty { kept[kept.count - 1].ms += d; continue }
        previousBytes = bytes
        kept.append((frame, d))
    }
    var indexed: [IndexedFrame] = []
    var shows: [[UInt32]] = []
    var delays: [Int] = []
    for (frame, d) in kept {
        let f = try indexFrame(frame, scale: scale)
        let v = f.visible
        if let last = shows.last, last == v { delays[delays.count - 1] += d; continue }
        indexed.append(f)
        shows.append(v)
        delays.append(d)
    }
    guard indexed.count >= 2 else { throw GifError(description: "a sprite whose frames are all the same needs the single-frame GIF path") }
    let first = indexed[0]
    var out: [UInt8] = Array("GIF89a".utf8) + le16(first.width) + le16(first.height)
    out.append(UInt8(128 + colourTableField(first.palette.count)))
    out += [0, 0]
    out += paddedPalette(first.palette)
    out += [0x21, 0xFF, 0x0B] + Array("NETSCAPE2.0".utf8) + [3, 1, 0, 0, 0]       // loop forever
    for (n, f) in indexed.enumerated() {
        // the rectangle: the whole frame first; later frames only the opaque pixels' bounding box
        var x0 = 0, y0 = 0, x1 = f.width, y1 = f.height
        // Pillow measures the rectangle against a background frame in the first frame's palette; with the very same
        // palette it compares palette indices, the transparent index never matches the background's, and the
        // rectangle is the whole frame
        if n > 0 && !samePalette(f, first) {
            x0 = f.width; y0 = f.height; x1 = 0; y1 = 0
            for y in 0..<f.height {
                for x in 0..<f.width where Int(f.pixels[y * f.width + x]) != f.transparent {
                    x0 = min(x0, x); x1 = max(x1, x + 1); y0 = min(y0, y); y1 = max(y1, y + 1)
                }
            }
            if x1 <= x0 { throw GifError(description: "a frame has nothing opaque to draw") }
        }
        let flagTransparent = f.declaredTransparent != nil
        out += [0x21, 0xF9, 4, UInt8((flagTransparent ? 1 : 0) | (2 << 2))] + le16(delays[n] / 10)
        out += [UInt8(f.declaredTransparent ?? 0), 0]
        let local = n > 0
        out += [0x2C] + le16(x0) + le16(y0) + le16(x1 - x0) + le16(y1 - y0)
        out.append(local ? UInt8(128 + colourTableField(f.palette.count)) : 0)
        if local { out += paddedPalette(f.palette) }
        out.append(8)
        var rect: [UInt8] = []
        rect.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 { rect += f.pixels[(y * f.width + x0)..<(y * f.width + x1)] }
        out += dataBlocks(lzwEncode(rect))
    }
    out.append(0x3B)
    return out
}
