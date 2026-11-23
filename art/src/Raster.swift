// Raster: an RGBA canvas whose drawing calls land on the same pixels as Pillow 11's ImageDraw on an RGBA image (the
// art was drawn against Pillow, and the frames, not the code, are what has to stay the same). Each primitive follows
// libImaging/Draw.c step for step, quirks included: rectangle (inclusive corners), point, line (Bresenham; width > 1 as
// the four-edge polygon built from the line's normal), ellipse (the quadrant walker on a half-pixel grid), arc and
// chord (that ellipse clipped by a tree of half-planes), polygon (scanline fill with Draw.c's edge rule), plus
// Image.alpha_composite, Image.resize(NEAREST), putpixel and pixel reads. The fill is written verbatim, never blended
// (ImageDraw on RGBA), so a fill with alpha 0 erases. desktop/tests/golden/art/raster-cases.json holds what Pillow drew;
// `jebart raster-check` replays it. Foundation only.
import Foundation

struct RGBA: Hashable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }

    static let clear = RGBA(0, 0, 0, 0)

    /// rrggbbaa, the way the raster fixture writes a pixel.
    var hex: String { String(format: "%02x%02x%02x%02x", r, g, b, a) }
}

final class Raster {
    let width: Int
    let height: Int
    private(set) var pixels: [RGBA]     // row-major

    init(_ width: Int, _ height: Int, fill: RGBA = .clear) {
        precondition(width >= 0 && height >= 0, "a canvas cannot have a negative size")
        self.width = width
        self.height = height
        pixels = Array(repeating: fill, count: width * height)
    }

    init(_ width: Int, _ height: Int, pixels: [RGBA]) {
        precondition(pixels.count == width * height, "pixel count does not match the size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func copy() -> Raster { Raster(width, height, pixels: pixels) }

    /// Image.load()[x, y] and putpixel: in-range coordinates only, as in Pillow.
    subscript(x: Int, y: Int) -> RGBA {
        get {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel (\(x), \(y)) is outside the canvas")
            return pixels[y * width + x]
        }
        set {
            precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel (\(x), \(y)) is outside the canvas")
            pixels[y * width + x] = newValue
        }
    }

    /// Image.tobytes(): four bytes a pixel, row-major.
    var bytes: [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(pixels.count * 4)
        for p in pixels { out.append(p.r); out.append(p.g); out.append(p.b); out.append(p.a) }
        return out
    }

    // ---- the two writers everything else goes through (Draw.c point32 / hline32) ----

    private func put(_ x: Int, _ y: Int, _ ink: RGBA) {
        if x >= 0 && x < width && y >= 0 && y < height { pixels[y * width + x] = ink }
    }

    private func hline(_ x0: Int, _ y: Int, _ x1: Int, _ ink: RGBA) {
        guard y >= 0 && y < height else { return }
        var a = x0, b = x1
        if a < 0 { a = 0 } else if a >= width { return }
        if b < 0 { return } else if b >= width { b = width - 1 }
        var i = y * width + a
        while a <= b { pixels[i] = ink; i += 1; a += 1 }
    }

    /// The ValueError ImageDraw raises for a box whose second corner is before its first; nil when the box is fine.
    static func boxError(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> String? {
        if x1 < x0 { return "x1 must be greater than or equal to x0" }
        if y1 < y0 { return "y1 must be greater than or equal to y0" }
        return nil
    }

    private static func checkBox(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        if let why = boxError(x0, y0, x1, y1) { preconditionFailure(why) }
    }

    // ---- point, rectangle ----

    /// ImageDraw.point: off-canvas points are dropped.
    func point(_ x: Int, _ y: Int, fill: RGBA) { put(x, y, fill) }

    func points(_ xy: [(Int, Int)], fill: RGBA) { for (x, y) in xy { put(x, y, fill) } }

    /// ImageDraw.rectangle: both corners are inside the box. The fill goes first, then a one-pixel outline when it is
    /// given and differs from the fill.
    func rectangle(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, fill: RGBA? = nil, outline: RGBA? = nil) {
        Raster.checkBox(x0, y0, x1, y1)
        if let fill = fill {
            var a = y0, b = y1
            var skip = false
            if a < 0 { a = 0 } else if a >= height { skip = true }
            if b < 0 { skip = true } else if b > height { b = height }
            if !skip && a <= b { for y in a...b { hline(x0, y, x1, fill) } }
        }
        if let ink = outline, ink != fill {
            hline(x0, y0, x1, ink)
            hline(x0, y1, x1, ink)
            bresenham(x1, y0 + 1, x1, y1, ink)
            bresenham(x0, y0 + 1, x0, y1, ink)
        }
    }

    // ---- line ----

    /// ImageDraw.line through the points in order. width 0 or 1 is Bresenham; wider lines are one polygon a segment.
    func line(_ xy: [(Int, Int)], fill: RGBA, width: Int = 0) {
        guard xy.count >= 2 else { return }
        for i in 0..<(xy.count - 1) {
            let (x0, y0) = xy[i], (x1, y1) = xy[i + 1]
            if width <= 1 { bresenham(x0, y0, x1, y1, fill) } else { wideLine(x0, y0, x1, y1, fill, width) }
        }
        if width <= 1, let last = xy.last { put(last.0, last.1, fill) }
    }

    func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, fill: RGBA, width: Int = 0) {
        line([(x0, y0), (x1, y1)], fill: fill, width: width)
    }

    /// Draw.c line32: every pixel from the first point up to, but not including, the second.
    private func bresenham(_ ax: Int, _ ay: Int, _ x1: Int, _ y1: Int, _ ink: RGBA) {
        var x0 = ax, y0 = ay
        var dx = x1 - x0, dy = y1 - y0
        let xs = dx < 0 ? -1 : 1, ys = dy < 0 ? -1 : 1
        dx = abs(dx); dy = abs(dy)
        if dx == 0 {
            for _ in 0..<dy { put(x0, y0, ink); y0 += ys }
        } else if dy == 0 {
            for _ in 0..<dx { put(x0, y0, ink); x0 += xs }
        } else if dx > dy {
            let n = dx
            dy += dy
            var e = dy - dx
            dx += dx
            for _ in 0..<n {
                put(x0, y0, ink)
                if e >= 0 { y0 += ys; e -= dx }
                e += dy
                x0 += xs
            }
        } else {
            let n = dy
            dx += dx
            var e = dx - dy
            dy += dy
            for _ in 0..<n {
                put(x0, y0, ink)
                if e >= 0 { x0 += xs; e -= dy }
                e += dx
                y0 += ys
            }
        }
    }

    // Draw.c ROUND_UP / ROUND_DOWN: to the nearest whole number, a half going away from zero or towards it.
    private static func roundUp(_ f: Float) -> Int { Int(f >= 0 ? (f + 0.5).rounded(.down) : -((abs(f) + 0.5).rounded(.down))) }
    private static func roundDown(_ f: Float) -> Int { Int(f >= 0 ? (f - 0.5).rounded(.up) : -((abs(f) - 0.5).rounded(.up))) }
    private static func roundUp(_ f: Double) -> Int { Int(f >= 0 ? (f + 0.5).rounded(.down) : -((abs(f) + 0.5).rounded(.down))) }
    private static func roundDown(_ f: Double) -> Int { Int(f >= 0 ? (f - 0.5).rounded(.up) : -((abs(f) - 0.5).rounded(.up))) }

    /// Draw.c ImagingDrawWideLine: the line pushed out along its normal, as a four-edge polygon. (width - 1) / 2 is
    /// rounded up for one side and down for the other, so an even width leans to one side.
    private func wideLine(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ ink: RGBA, _ width: Int) {
        let dx = x1 - x0, dy = y1 - y0
        if dx == 0 && dy == 0 { put(x0, y0, ink); return }
        let big = hypot(Double(dx), Double(dy))
        let small = Double(width - 1) / 2.0
        let ratioMax = Double(Raster.roundUp(small)) / big, ratioMin = Double(Raster.roundDown(small)) / big
        let dxmin = Raster.roundDown(ratioMin * Double(dy)), dxmax = Raster.roundDown(ratioMax * Double(dy))
        let dymin = Raster.roundDown(ratioMin * Double(dx)), dymax = Raster.roundDown(ratioMax * Double(dx))
        let v = [(x0 - dxmin, y0 + dymax), (x1 - dxmin, y1 + dymax), (x1 + dxmax, y1 - dymin), (x0 + dxmax, y0 - dymin)]
        fillEdges((0..<4).map { Edge(v[$0].0, v[$0].1, v[($0 + 1) % 4].0, v[($0 + 1) % 4].1) }, ink)
    }

    // ---- polygon ----

    /// Draw.c Edge / add_edge.
    private struct Edge {
        let x0: Int, y0: Int
        let xmin: Int, ymin: Int, xmax: Int, ymax: Int
        let dx: Float

        init(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            self.x0 = x0; self.y0 = y0
            xmin = min(x0, x1); xmax = max(x0, x1)
            ymin = min(y0, y1); ymax = max(y0, y1)
            dx = y0 == y1 ? 0 : Float(x1 - x0) / Float(y1 - y0)
        }

        /// Where the edge crosses scanline y. The C is `(y - y0) * dx + x0` in float, which clang contracts into one
        /// fused multiply-add on arm64, the build the art was drawn with. The fused form is used here on every
        /// architecture; the unfused one lands a few crossings on the other side of a half and moves a pixel.
        func at(_ y: Int) -> Float { Float(x0).addingProduct(Float(y - y0), dx) }
    }

    /// ImageDraw.polygon: scanline fill, then a one-pixel outline when it is given and differs from the fill.
    func polygon(_ xy: [(Int, Int)], fill: RGBA? = nil, outline: RGBA? = nil) {
        precondition(xy.count >= 2, "coordinate list must contain at least 2 coordinates")
        let n = xy.count
        if let fill = fill {
            // Draw.c also merges a horizontal edge into the horizontal edge before it; that only matters when
            // blending, since both are drawn as plain runs here.
            var edges: [Edge] = []
            for i in 0..<(n - 1) { edges.append(Edge(xy[i].0, xy[i].1, xy[i + 1].0, xy[i + 1].1)) }
            if xy[n - 1].0 != xy[0].0 || xy[n - 1].1 != xy[0].1 { edges.append(Edge(xy[n - 1].0, xy[n - 1].1, xy[0].0, xy[0].1)) }
            fillEdges(edges, fill)
        }
        if let ink = outline, ink != fill {
            for i in 0..<(n - 1) { bresenham(xy[i].0, xy[i].1, xy[i + 1].0, xy[i + 1].1, ink) }
            bresenham(xy[n - 1].0, xy[n - 1].1, xy[0].0, xy[0].1, ink)
        }
    }

    /// Draw.c polygon_generic without blending: horizontal edges are drawn as they are, the rest are intersected
    /// with every scanline, and the sorted crossings are filled in pairs.
    private func fillEdges(_ e: [Edge], _ ink: RGBA) {
        guard !e.isEmpty else { return }
        var table: [Edge] = []
        var ymin = height - 1, ymax = 0
        for edge in e {
            if ymin > edge.ymin { ymin = edge.ymin }
            if ymax < edge.ymax { ymax = edge.ymax }
            if edge.ymin == edge.ymax {
                hline(edge.xmin, edge.ymin, edge.xmax, ink)
                continue
            }
            table.append(edge)
        }
        if ymin < 0 { ymin = 0 }
        if ymax > height { ymax = height }
        guard ymin <= ymax else { return }

        var xx = [Float](repeating: 0, count: table.count * 2)
        for y in ymin...ymax {
            var j = 0
            for (i, current) in table.enumerated() where y >= current.ymin && y <= current.ymax {
                xx[j] = current.at(y)
                j += 1
                if y == current.ymax && y < ymax {
                    // "needed to draw consistent polygons": an edge ending here counts twice
                    xx[j] = xx[j - 1]
                    j += 1
                } else if (y == current.ymin || y == current.ymax) && current.dx != 0 {
                    // "connect discontiguous corners": where this edge meets an earlier one on this row and both
                    // run off sideways by more than a pixel on the next row, the crossing is pulled out to meet them
                    for k in 0..<i {
                        let other = table[k]
                        if (y != other.ymin && y != other.ymax) || other.dx == 0 { continue }
                        guard xx[j - 1].rounded() == other.at(y).rounded() else { continue }
                        let next = y + (y == current.ymax ? -1 : 1)
                        guard next >= other.ymin && next <= other.ymax else { continue }
                        let mine = current.at(next), theirs = other.at(next)
                        if xx[j - 1] > mine + 1 && xx[j - 1] > theirs + 1 {
                            xx[j - 1] = max(mine, theirs).rounded() + 1
                        } else if xx[j - 1] < mine - 1 && xx[j - 1] < theirs - 1 {
                            xx[j - 1] = min(mine, theirs).rounded() - 1
                        }
                        break
                    }
                }
            }
            let sorted = xx[0..<j].sorted()
            var i = 1
            while i < j {
                hline(Raster.roundUp(sorted[i - 1]), y, Raster.roundDown(sorted[i]), ink)
                i += 2
            }
        }
    }

    // ---- ellipse, arc, chord ----

    /// One quarter of an ellipse outline, walked from (a, b % 2) to (a % 2, b) on a grid of half pixels (step 2).
    /// Draw.c quarter_state.
    private struct Quarter {
        var a = 0, b = 0, cx = 0, cy = 0, ex = 0, ey = 0
        var a2: Int64 = 0, b2: Int64 = 0, a2b2: Int64 = 0
        var finished = true

        init(_ a: Int, _ b: Int) {
            guard a >= 0 && b >= 0 else { return }
            self.a = a; self.b = b
            cx = a; cy = b % 2
            ex = a % 2; ey = b
            a2 = Int64(a * a); b2 = Int64(b * b); a2b2 = a2 * b2
            finished = false
        }

        func delta(_ x: Int, _ y: Int) -> Int64 { abs(a2 * Int64(y) * Int64(y) + b2 * Int64(x) * Int64(x) - a2b2) }

        mutating func next() -> (Int, Int)? {
            if finished { return nil }
            let ret = (cx, cy)
            if cx == ex && cy == ey {
                finished = true
            } else {
                var nx = cx, ny = cy + 2
                var nd = delta(nx, ny)
                if nx > 1 {
                    var d = delta(cx - 2, cy + 2)
                    if nd > d { nx = cx - 2; ny = cy + 2; nd = d }
                    d = delta(cx - 2, cy)
                    if nd > d { nx = cx - 2; ny = cy }
                }
                cx = nx; cy = ny
            }
            return ret
        }
    }

    /// The four quarters of an outer and an inner ellipse joined into horizontal runs (x0, y, x1), still on the
    /// half-pixel grid. Draw.c ellipse_state.
    private struct Ring {
        var outer: Quarter, inner = Quarter(-1, -1)
        var py = 0, pl = 0, pr = 0
        var buffer: [(Int, Int, Int)] = []
        var finished: Bool
        let leftmost: Int

        init(_ a: Int, _ b: Int, _ w: Int) {
            leftmost = a % 2
            outer = Quarter(a, b)
            if w < 1 { finished = true; return }
            guard let first = outer.next() else { finished = true; return }
            pr = first.0; py = first.1
            finished = false
            inner = Quarter(a - 2 * (w - 1), b - 2 * (w - 1))
            pl = leftmost
        }

        mutating func next() -> (Int, Int, Int)? {
            if buffer.isEmpty {
                if finished { return nil }
                let y = py, r = pr
                var l = pl
                var step = outer.next()
                while let s = step, s.1 <= y { step = outer.next() }
                if let s = step { pr = s.0; py = s.1 } else { finished = true }
                step = inner.next()
                while let s = step, s.1 <= y { l = s.0; step = inner.next() }
                pl = step?.0 ?? leftmost
                // the right and left halves of the row below the centre, then of the row above it
                let right = l > 0 || l < r, ll = l == 0 ? 2 : l
                if right && y > 0 { buffer.append((ll, y, r)) }
                if y > 0 { buffer.append((-r, y, -l)) }
                if right { buffer.append((ll, -y, r)) }
                buffer.append((-r, -y, -l))
            }
            return buffer.removeLast()
        }
    }

    /// ImageDraw.ellipse inside the inclusive bounding box. The fill goes first (nothing at all for a box of one
    /// pixel, as in Pillow), then a one-pixel outline when it is given and differs from the fill.
    func ellipse(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, fill: RGBA? = nil, outline: RGBA? = nil) {
        Raster.checkBox(x0, y0, x1, y1)
        let a = x1 - x0, b = y1 - y0
        if let fill = fill { ring(x0, y0, a, b, a + b, fill) }
        if let ink = outline, ink != fill { ring(x0, y0, a, b, 1, ink) }
    }

    private func ring(_ x0: Int, _ y0: Int, _ a: Int, _ b: Int, _ w: Int, _ ink: RGBA) {
        var st = Ring(a, b, w)
        while let (l, y, r) = st.next() { hline(x0 + (l + a) / 2, y0 + (y + b) / 2, x0 + (r + a) / 2, ink) }
    }

    /// A half-plane a*x + b*y + c >= 0 on the half-pixel grid, or two trees joined. Draw.c clip_node.
    private indirect enum Clip {
        case plane(Double, Double, Double)
        case and(Clip, Clip)
        case or(Clip, Clip)

        /// Mirrored about y = x (clip_tree_transpose).
        var transposed: Clip {
            switch self {
            case let .plane(a, b, c): return .plane(b, a, c)
            case let .and(l, r): return .and(l.transposed, r.transposed)
            case let .or(l, r): return .or(l.transposed, r.transposed)
            }
        }

        /// The parts of the run x0...x1 on row y that survive, as open (+1) and close (-1) events sorted by x
        /// (clip_tree_do_clip).
        func events(_ x0: Int, _ y: Int, _ x1: Int) -> [(x: Int, type: Int)] {
            switch self {
            case let .plane(a, b, c):
                var lo = x0, hi = x1
                let eps = 1e-9
                let by = b * Double(y) + c
                if abs(a) < eps {
                    if by < -eps { lo = 1; hi = 0 }
                } else {
                    let ix = -by / a
                    if a * Double(x0) + by < eps { lo = Int(max(Double(x0), ix).rounded()) }
                    if a * Double(x1) + by < eps { hi = Int(min(Double(x1), ix).rounded()) }
                }
                return lo <= hi ? [(lo, 1), (hi, -1)] : []
            case let .and(l, r): return Clip.merge(l.events(x0, y, x1), r.events(x0, y, x1), isOr: false)
            case let .or(l, r): return Clip.merge(l.events(x0, y, x1), r.events(x0, y, x1), isOr: true)
            }
        }

        private static func merge(_ l1: [(x: Int, type: Int)], _ l2: [(x: Int, type: Int)], isOr: Bool) -> [(x: Int, type: Int)] {
            var out: [(x: Int, type: Int)] = []
            var i = 0, j = 0, k1 = 0, k2 = 0
            while i < l1.count || j < l2.count {
                let t: (x: Int, type: Int)
                if j >= l2.count || (i < l1.count && (l1[i].x < l2[j].x || (l1[i].x == l2[j].x && l1[i].type > l2[j].type))) {
                    t = l1[i]; k1 += t.type; i += 1
                } else {
                    t = l2[j]; k2 += t.type; j += 1
                }
                let tail = out.last?.type
                let keep: Bool
                if isOr {
                    keep = (t.type == 1 && (tail == nil || tail == -1)) || (t.type == -1 && k1 == 0 && k2 == 0)
                } else {
                    keep = (t.type == 1 && (tail == nil || tail == -1) && k1 > 0 && k2 > 0)
                        || (t.type == -1 && tail == 1 && (k1 == 0 || k2 == 0))
                }
                if keep { out.append(t) }
            }
            return out
        }
    }

    /// Draw.c arc_init: the clip tree for the part of an ellipse between two angles. Each end is cut along the
    /// ellipse's normal at that angle; a tall ellipse is handled as a wide one mirrored about y = x.
    private static func arcClip(_ a: Int, _ b: Int, _ start: Float, _ end: Float) -> Clip? {
        if a < b { return arcClip(b, a, 90 - end, 90 - start)?.transposed }
        let (al, ar) = normalize(start, end)
        if ar == al + 360 { return nil }
        let fa = Double(a), fb = Double(b), focal = Double(a * a - b * b)
        let l = Double(al), r = Double(ar)
        let lc = Clip.plane(-fa * sin(l * .pi / 180.0), fb * cos(l * .pi / 180.0), focal * sin(l * .pi / 90.0) / 2.0)
        let rc = Clip.plane(fa * sin(r * .pi / 180.0), -fb * cos(r * .pi / 180.0), -focal * sin(r * .pi / 90.0) / 2.0)
        let narrow = ar - al < 180
        if fmod(l, 180) == 0 || fmod(r, 180) == 0 {
            return narrow ? .and(lc, rc) : .or(lc, rc)
        }
        // the ends are on opposite sides of the horizontal axis: each cut only counts on its own side
        if (Int(al / 180) + Int(ar / 180)) % 2 == 1 {
            return .or(.and(.plane(0, Int(al / 180) % 2 == 0 ? 1 : -1, 0), lc),
                       .and(.plane(0, Int(ar / 180) % 2 == 0 ? 1 : -1, 0), rc))
        }
        let side = Clip.plane(0, ar < 180 || ar > 540 ? 1 : -1, 0)
        return narrow ? .and(.and(lc, rc), side) : .or(.or(lc, rc), side)
    }

    /// Draw.c normalize_angles: 0 <= start < 360 and start <= end <= start + 360.
    private static func normalize(_ start: Float, _ end: Float) -> (Float, Float) {
        if end - start >= 360 { return (0, 360) }
        let s = Float(fmod(start < 0 ? 360 - fmod(Double(-start), 360) : Double(start), 360))
        let e = Float(Double(s) + fmod(end < s ? 360 - fmod(Double(s - end), 360) : Double(end - s), 360))
        return (s, e)
    }

    private func clippedRing(_ x0: Int, _ y0: Int, _ a: Int, _ b: Int, _ w: Int, _ clip: Clip?, _ ink: RGBA) {
        var st = Ring(a, b, w)
        while let (l, y, r) = st.next() {
            guard let clip = clip else { hline(x0 + (l + a) / 2, y0 + (y + b) / 2, x0 + (r + a) / 2, ink); continue }
            let ev = clip.events(l, y, r)
            var i = 0
            while i + 1 < ev.count {
                hline(x0 + (ev[i].x + a) / 2, y0 + (y + b) / 2, x0 + (ev[i + 1].x + a) / 2, ink)
                i += 2
            }
        }
    }

    /// ImageDraw.arc: the outline of the ellipse in the box from `start` to `end` degrees (0 at 3 o'clock, clockwise).
    func arc(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, start: Float, end: Float, fill: RGBA, width: Int = 1) {
        Raster.checkBox(x0, y0, x1, y1)
        let (s, e) = Raster.normalize(start, end)
        let a = x1 - x0, b = y1 - y0
        if s + 360 == e { ring(x0, y0, a, b, width, fill); return }
        if s == e { return }
        clippedRing(x0, y0, a, b, width, Raster.arcClip(a, b, s, e), fill)
    }

    /// ImageDraw.chord, filled: the ellipse in the box on one side of the straight line between the two angles.
    func chord(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, start: Float, end: Float, fill: RGBA) {
        Raster.checkBox(x0, y0, x1, y1)
        let (s, e) = Raster.normalize(start, end)
        let a = x1 - x0, b = y1 - y0
        if s + 360 == e { ring(x0, y0, a, b, a + b, fill); return }
        if s == e { return }
        let fa = Double(a), fb = Double(b)
        let xl = fa * cos(Double(s) * .pi / 180), xr = fa * cos(Double(e) * .pi / 180)
        let yl = fb * sin(Double(s) * .pi / 180), yr = fb * sin(Double(e) * .pi / 180)
        let ca = yr - yl, cb = xl - xr
        clippedRing(x0, y0, a, b, a + b + 1, .plane(ca, cb, -(ca * xl + cb * yl)), fill)
    }

    // ---- whole-image operations ----

    /// Image.alpha_composite(src, (x, y)) in place: src over this canvas, clipped to it. libImaging/AlphaComposite.c's
    /// integer arithmetic; a source pixel with alpha 0 leaves the canvas pixel as it is, whatever its RGB.
    func alphaComposite(_ src: Raster, at dx: Int, _ dy: Int) {
        for sy in 0..<src.height {
            let y = dy + sy
            guard y >= 0 && y < height else { continue }
            for sx in 0..<src.width {
                let x = dx + sx
                guard x >= 0 && x < width else { continue }
                let s = src.pixels[sy * src.width + sx]
                if s.a == 0 { continue }
                let d = pixels[y * width + x]
                let sa = UInt32(s.a), da = UInt32(d.a)
                let blend = da * (255 - sa)
                let outa255 = sa * 255 + blend
                let coef1 = sa * 255 * 255 * 128 / outa255
                let coef2 = 255 * 128 - coef1
                func div255(_ v: UInt32) -> UInt32 { ((v >> 8) + v) >> 8 }
                func mix(_ p: UInt8, _ q: UInt8) -> UInt8 { UInt8(truncatingIfNeeded: div255(UInt32(p) * coef1 + UInt32(q) * coef2 + (0x80 << 7)) >> 7) }
                pixels[y * width + x] = RGBA(mix(s.r, d.r), mix(s.g, d.g), mix(s.b, d.b), UInt8(truncatingIfNeeded: div255(outa255 + 0x80)))
            }
        }
    }

    /// Image.resize((w, h), Image.NEAREST): libImaging/Geometry.c ImagingScaleAffine, which steps a running source
    /// coordinate from half a step in.
    func resized(_ w: Int, _ h: Int) -> Raster {
        precondition(w >= 0 && h >= 0, "height and width must be > 0")
        if w == width && h == height { return copy() }
        let out = Raster(w, h)
        guard w > 0 && h > 0 else { return out }
        let ax = Double(width) / Double(w), ay = Double(height) / Double(h)
        var xo = ax * 0.5
        var xin = [Int](repeating: -1, count: w)
        for x in 0..<w {
            let v = xo < 0 ? -1 : Int(xo)
            if v >= 0 && v < width { xin[x] = v }
            xo += ax
        }
        var yo = ay * 0.5
        for y in 0..<h {
            let v = yo < 0 ? -1 : Int(yo)
            if v >= 0 && v < height {
                for x in 0..<w where xin[x] >= 0 { out.pixels[y * w + x] = pixels[v * width + xin[x]] }
            }
            yo += ay
        }
        return out
    }
}
