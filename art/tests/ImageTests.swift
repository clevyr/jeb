// Unit tests for the image writers (art/src/Png.swift, Gif.swift): PNG chunks, CRC and zlib round trip, the GIF LZW
// encoder against a reference decoder, and the GIF writer's frame merging.
import CZlib
import Foundation

/// A reference GIF LZW decoder (minimum code size 8), independent of the encoder.
private func lzwDecode(_ data: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var table: [[UInt8]] = (0..<256).map { [UInt8($0)] } + [[], []]
    var size = 9, bitPos = 0
    var previous: [UInt8]?
    func read() -> Int? {
        guard bitPos + size <= data.count * 8 else { return nil }
        var v = 0
        for i in 0..<size { v |= Int((data[(bitPos + i) / 8] >> UInt8((bitPos + i) % 8)) & 1) << i }
        bitPos += size
        return v
    }
    while let code = read() {
        if code == 256 { table = Array(table.prefix(258)); size = 9; previous = nil; continue }
        if code == 257 { break }
        var entry: [UInt8]
        if code < table.count { entry = table[code] } else if let p = previous { entry = p + [p[0]] } else { break }
        out += entry
        if let p = previous, table.count < 4096 {
            table.append(p + [entry[0]])
            if table.count == (1 << size) && size < 12 { size += 1 }
        }
        previous = entry
        entry = []
    }
    return out
}

func imageTests(_ t: Tester) {
    t.test("crc32 matches the standard check value") {
        t.eq(crc32Of(Array("123456789".utf8)), 0xCBF4_3926)
    }

    t.test("a PNG has the signature, an IHDR for the size, and an IDAT that inflates to the scanlines") {
        let img = Raster(3, 2, pixels: (0..<6).map { RGBA(UInt8($0), UInt8($0 * 2), 7, $0 == 0 ? 0 : 255) })
        let png = pngEncode(img, level: 9)
        t.eq(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        func be(_ at: Int) -> Int { png[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
        t.eq(Array(png[12..<16]), Array("IHDR".utf8))
        t.eq(be(16), 3); t.eq(be(20), 2)
        t.eq(Array(png[24..<29]), [8, 6, 0, 0, 0])
        t.eq(UInt32(be(29)), crc32Of(Array(png[12..<29])))
        let idatLen = be(33)
        t.eq(Array(png[37..<41]), Array("IDAT".utf8))
        let z = Array(png[41..<(41 + idatLen)])
        t.eq(UInt32(be(41 + idatLen)), crc32Of(Array(png[37..<(41 + idatLen)])))
        var raw = [UInt8](repeating: 0, count: 2 * (1 + 12))
        var size = uLongf(raw.count)
        t.eq(uncompress(&raw, &size, z, uLong(z.count)), Z_OK)
        var want: [UInt8] = []
        for y in 0..<2 {
            want.append(0)
            for x in 0..<3 { let p = img.pixels[y * 3 + x]; want += [p.r, p.g, p.b, p.a] }
        }
        t.eq(raw, want)
        t.eq(Array(png.suffix(12)), [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    }

    t.test("LZW: the encoder starts with a clear code and ends with the end code, and round-trips") {
        // [256, 1, 257] at 9 bits, least significant bit first
        t.eq(hex(lzwEncode([1])), "00030404")
        t.eq(lzwDecode(lzwEncode([])), [])
        let cases: [[UInt8]] = [
            [5, 5, 5, 5, 5, 5, 5, 5, 5],
            Array("TOBEORNOTTOBEORTOBEORNOT".utf8),
            (0..<600).map { UInt8($0 % 7) },
            (0..<20000).map { UInt8(truncatingIfNeeded: ($0 &* 2654435761) >> 7) },     // forces table resets
        ]
        for c in cases { t.eq(lzwDecode(lzwEncode(c)) == c, true, "round trip of \(c.count) pixels") }
    }

    t.test("median cut: Pillow's palette order and pixel mapping (values from Pillow 11.3 quantize, MEDIANCUT, no dither)") {
        func rgb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 { UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
        let cols = [(200, 30, 30), (30, 200, 30), (30, 30, 200), (250, 250, 250), (10, 10, 10), (120, 60, 20), (240, 200, 40),
                    (90, 90, 90), (200, 30, 60), (30, 200, 90), (255, 0, 255)]
        var px: [UInt32] = []
        for (i, c) in cols.enumerated() { px += Array(repeating: rgb(c.0, c.1, c.2), count: i + 2) }
        px += Array(repeating: rgb(1, 2, 3), count: 3)
        guard let r = try? pillowMedianCut(px, colors: 63) else { t.fail("median cut threw"); return }
        let want = [(250, 250, 250), (240, 200, 40), (30, 200, 90), (30, 200, 30), (90, 90, 90), (120, 60, 20), (255, 0, 255),
                    (200, 30, 60), (200, 30, 30), (30, 30, 200), (10, 10, 10), (1, 2, 3)]
        t.eq(r.palette, want.map { rgb($0.0, $0.1, $0.2) })
        t.eq(r.indices, [8, 8, 3, 3, 3, 9, 9, 9, 9, 0, 0, 0, 0, 0, 10, 10, 10, 10, 10, 10, 5, 5, 5, 5, 5, 5, 5, 1, 1, 1, 1, 1, 1, 1, 1,
                         4, 4, 4, 4, 4, 4, 4, 4, 4, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2] + Array(repeating: 6, count: 12) + [11, 11, 11])
        // more colours than entries: boxes merge, and a pixel maps to its nearest entry
        let many = (0..<80).map { rgb($0 * 4 % 256, ($0 * 37) % 256, ($0 * 91) % 256) }
        guard let m = try? pillowMedianCut(many, colors: 63) else { t.fail("median cut threw on 80 colours"); return }
        t.eq(m.palette.count, 63)
        t.eq(Array(m.palette.prefix(4)), [rgb(234, 245, 76), rgb(192, 240, 16), rgb(244, 209, 175), rgb(188, 203, 181)])
        t.eq(m.palette.last, rgb(0, 0, 0))
        t.eq(Array(m.indices.prefix(16)), [62, 59, 54, 50, 29, 25, 16, 61, 60, 55, 47, 25, 15, 9, 60, 58])
        t.eq(Array(m.indices.suffix(8)), [48, 25, 26, 9, 11, 58, 52, 49])
    }

    t.test("GIF: identical consecutive frames merge, durations add, disposal 2, loop forever") {
        let a = Raster(2, 2, fill: RGBA(200, 0, 0, 255))
        let b = Raster(2, 2, fill: RGBA(0, 0, 200, 255))
        guard let gif = try gifBytes(frames: [a, a, b], ms: [100, 100, 300], scale: 1) else { t.fail("no gif"); return }
        t.eq(Array(gif.prefix(6)), Array("GIF89a".utf8))
        t.eq(gif.last, 0x3B)
        // graphic control extensions: 21 F9 04 flags delay(2) transparent 00
        var delays: [Int] = [], flags: [UInt8] = []
        for i in 0..<(gif.count - 7) where gif[i] == 0x21 && gif[i + 1] == 0xF9 && gif[i + 2] == 4 && gif[i + 7] == 0 {
            flags.append(gif[i + 3]); delays.append(Int(gif[i + 4]) | Int(gif[i + 5]) << 8)
        }
        t.eq(delays, [20, 30])
        t.eq(flags.map { ($0 >> 2) & 7 }, [2, 2])
        t.eq(gifBytes_loop(gif), true, "NETSCAPE loop block, count 0")
        t.eq(try gifBytes(frames: [a], ms: [100]) == nil, true)
    }
}

private func gifBytes_loop(_ gif: [UInt8]) -> Bool {
    let marker = [0x21, 0xFF, 0x0B] + Array("NETSCAPE2.0".utf8) + [3, 1, 0, 0, 0] as [UInt8]
    return (0..<(gif.count - marker.count)).contains { Array(gif[$0..<($0 + marker.count)]) == marker }
}
