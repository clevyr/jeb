// raw2png <in.raw> <out.png> [k]: the band's "W H base64" picture as a PNG, scaled k times (nearest).
import AppKit
let a = CommandLine.arguments
let parts = try! String(contentsOfFile: a[1], encoding: .utf8).split(separator: " ")
let w = Int(parts[0])!, h = Int(parts[1])!, k = a.count > 3 ? Int(a[3])! : 1
let bytes = [UInt8](Data(base64Encoded: String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines))!)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * k, pixelsHigh: h * k, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * k * 4, bitsPerPixel: 32)!
let d = rep.bitmapData!
for y in 0..<(h * k) { for x in 0..<(w * k) {
    let s = ((y / k) * w + x / k) * 4, o = y * w * k * 4 + x * 4
    // Clear pixels on a dark grey, as a terminal would show them.
    if bytes[s + 3] == 0 { d[o] = 40; d[o + 1] = 40; d[o + 2] = 48; d[o + 3] = 255 } else { for c in 0..<4 { d[o + c] = bytes[s + c] } }
} }
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
