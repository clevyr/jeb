// png2raw <in.png> <out.rgba>: the picture's pixels as RGBA bytes, top row first.
import AppKit
let a = CommandLine.arguments
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!
var out = [UInt8](repeating: 0, count: rep.pixelsWide * rep.pixelsHigh * 4)
let d = rep.bitmapData!, spp = rep.samplesPerPixel
for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide { for c in 0..<4 {
    out[(y * rep.pixelsWide + x) * 4 + c] = c < spp ? d[y * rep.bytesPerRow + x * spp + c] : 255
} } }
try! Data(out).write(to: URL(fileURLWithPath: a[2]))
