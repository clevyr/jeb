// pixcheck <png> <k> [other.png]: crispness of a window capture at k device pixels per
// scene pixel: the share of k x k cells (grid from the bottom-left) holding one colour,
// the share whose colours are not all found among their 4 neighbours' cells (a sign of
// filtering: in-between colours), and with a second capture, how many cells differ.
import AppKit
func load(_ p: String) -> (Int, Int, [UInt32]) {
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: p)))!
    let w = rep.pixelsWide, h = rep.pixelsHigh
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: w, height: h))
    let buf = ctx.data!.bindMemory(to: UInt32.self, capacity: w * h)
    return (w, h, Array(UnsafeBufferPointer(start: buf, count: w * h)))
}
let a = CommandLine.arguments
let (w, h, px) = load(a[1]); let k = Int(a[2])!
let cw = w / k, ch = h / k
func at(_ x: Int, _ y: Int) -> UInt32 { px[(h - 1 - y) * w + x] } // y up
var uniform = 0, odd = 0, total = 0
func cell(_ cx: Int, _ cy: Int) -> Set<UInt32> { var s = Set<UInt32>(); for y in cy*k..<(cy+1)*k { for x in cx*k..<(cx+1)*k { s.insert(at(x, y)) } }; return s }
var cells = [[Set<UInt32>]](repeating: [], count: ch)
for cy in 0..<ch { for cx in 0..<cw { cells[cy].append(cell(cx, cy)) } }
for cy in 0..<ch { for cx in 0..<cw {
    total += 1
    let c = cells[cy][cx]
    if c.count == 1 { uniform += 1; continue }
    var near = Set<UInt32>()
    for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,1),(-1,1),(1,-1)] { let x = cx+dx, y = cy+dy; if x >= 0, y >= 0, x < cw, y < ch { near.formUnion(cells[y][x]) } }
    if !c.isSubset(of: near) { odd += 1 }
} }
print(String(format: "%@: %dx%d, %d cells of %dx%d: %.2f%% one colour, %d mixed cells with colours not in a neighbour", (a[1] as NSString).lastPathComponent, w, h, total, k, k, 100 * Double(uniform) / Double(total), odd))
if a.count > 3 {
    let (_, _, p2) = load(a[3]); var diff = 0
    for cy in 0..<ch { for cx in 0..<cw { var d = false; for y in cy*k..<(cy+1)*k where !d { for x in cx*k..<(cx+1)*k where px[(h-1-y)*w+x] != p2[(h-1-y)*w+x] { d = true; break } }; if d { diff += 1 } } }
    print("cells differing from \((a[3] as NSString).lastPathComponent): \(diff)")
}
