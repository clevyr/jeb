// Png: a PNG writer over the system zlib (art/CZlib), for the sheets, the scenes, the logo and the plugin icon. 8-bit
// RGBA, every scanline filter 0, one IDAT chunk. docs/logo.png and mod/.claude-plugin/icon.png are tracked and have to
// come out byte for byte what the original Python wrote: zlib.compress(raw, 9) over the same scanlines, which is compress2 at level 9
// on the same system libz. The sheets and scenes are compared by decoded pixels, so their level only decides size.
import CZlib
import Foundation

/// zlib.compress(data, level): the zlib wrapper (RFC 1950) around deflate, default window and memory level.
func zlibCompress(_ data: [UInt8], level: Int32) -> [UInt8] {
    var size = compressBound(uLong(data.count))
    var out = [UInt8](repeating: 0, count: Int(size))
    let status = compress2(&out, &size, data, uLong(data.count), level)
    precondition(status == Z_OK, "zlib compress2 failed (\(status))")
    out.removeLast(out.count - Int(size))
    return out
}

/// zlib.crc32(data).
func crc32Of(_ data: [UInt8]) -> UInt32 {
    UInt32(truncatingIfNeeded: crc32(0, data, uInt(data.count)))
}

private func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }

private func chunk(_ kind: String, _ data: [UInt8]) -> [UInt8] {
    let body = Array(kind.utf8) + data
    return be32(UInt32(data.count)) + body + be32(crc32Of(body))
}

/// A PNG from `scanlines`: height rows of (filter byte 0, then width x 4 RGBA bytes).
func pngEncode(width: Int, height: Int, scanlines: [UInt8], level: Int32 = 6) -> [UInt8] {
    precondition(scanlines.count == height * (1 + width * 4), "scanline data does not match the size")
    let ihdr = be32(UInt32(width)) + be32(UInt32(height)) + [8, 6, 0, 0, 0]
    return [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        + chunk("IHDR", ihdr) + chunk("IDAT", zlibCompress(scanlines, level: level)) + chunk("IEND", [])
}

/// A PNG of a canvas.
func pngEncode(_ image: Raster, level: Int32 = 6) -> [UInt8] {
    var raw: [UInt8] = []
    raw.reserveCapacity(image.height * (1 + image.width * 4))
    for y in 0..<image.height {
        raw.append(0)
        for x in 0..<image.width {
            let p = image.pixels[y * image.width + x]
            raw.append(p.r); raw.append(p.g); raw.append(p.b); raw.append(p.a)
        }
    }
    return pngEncode(width: image.width, height: image.height, scanlines: raw, level: level)
}
