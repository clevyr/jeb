// up <in.png> <out.png> <k> [x y w h]: nearest-neighbour upscale (optionally a crop first), for looking at renders.
import AppKit
let a = CommandLine.arguments
let k = Int(a[3])!
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!
var cx = 0, cy = 0, cw = src.pixelsWide, ch = src.pixelsHigh
if a.count >= 8 { cx = Int(a[4])!; cy = Int(a[5])!; cw = Int(a[6])!; ch = Int(a[7])! }
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw * k, pixelsHigh: ch * k, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: cw * k * 4, bitsPerPixel: 32)!
for y in 0..<ch { for x in 0..<cw {
    let c = src.colorAt(x: cx + x, y: cy + y) ?? .clear
    for dy in 0..<k { for dx in 0..<k { out.setColor(c, atX: x * k + dx, y: y * k + dy) } }
} }
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
