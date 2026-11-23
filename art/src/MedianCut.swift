// MedianCut: Pillow's median-cut quantizer (src/libImaging/Quant.c, `quantize` with kmeans 0 and no dither), which
// pixel.py's save_gif calls as quantize(colors=63, method=MEDIANCUT). What matters to the GIF bytes is the palette ORDER
// (Pillow only writes a whole-frame rectangle when two frames' palette bytes are equal), so this follows the C closely:
// the colour hash table's iteration order seeds three merge-sorted lists, boxes are split off a heap by pixel count,
// the palette is the leaves read left to right, and a pixel takes the nearest entry searched from its own box's.
import Foundation

private struct Entry {
    var key: UInt32          // r << 16 | g << 8 | b
    var r: Int, g: Int, b: Int
    var count: Int
    func v(_ axis: Int) -> Int { axis == 0 ? r : axis == 1 ? g : b }
}

private final class Box {
    var lists: [[Int]]       // entry ids per axis, each sorted descending by that axis' value
    var pixelCount: UInt32
    var volume = -1
    var l: Box?, r: Box?
    init(lists: [[Int]], pixelCount: UInt32) { self.lists = lists; self.pixelCount = pixelCount }
}

private func pixelHash(_ k: UInt32) -> UInt32 {
    let r = (k >> 16) & 255, g = (k >> 8) & 255, b = k & 255
    return (r &* 463) ^ ((g << 8) &* 10069) ^ ((b << 16) &* 64997)
}

/// QuantHash.c's table length after `count` distinct inserts: 11, growing to the next "prime" (its test is a no-op:
/// any number whose low nibble is 1, 3, 7, 9, 11 or 13) above twice the length once length * 3 < count.
private func hashTableLength(forCount count: Int) -> UInt32 {
    let unit = [0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0]
    var length = 11
    for n in 1...max(count, 1) where length * 3 < n {
        var start = length * 2 + 1
        while start > 1 && unit[start & 15] == 0 { start += 1 }
        length = start
    }
    return UInt32(length)
}

/// mergesort_pixels: descending by value, a tie taking the right-hand element first, split at (n + 1) / 2.
private func mergesort(_ ids: [Int], _ entries: [Entry], _ axis: Int) -> [Int] {
    if ids.count < 2 { return ids }
    let mid = (ids.count + 1) / 2
    let a = mergesort(Array(ids[..<mid]), entries, axis)
    let b = mergesort(Array(ids[mid...]), entries, axis)
    var out: [Int] = []
    out.reserveCapacity(ids.count)
    var i = 0, j = 0
    while i < a.count && j < b.count {
        if entries[a[i]].v(axis) > entries[b[j]].v(axis) { out.append(a[i]); i += 1 } else { out.append(b[j]); j += 1 }
    }
    out += a[i...]
    out += b[j...]
    return out
}

private func boxVolume(_ b: Box, _ e: [Entry]) -> Int {
    if b.volume >= 0 { return b.volume }
    guard let rh = b.lists[0].first else { b.volume = 0; return 0 }
    let rl = b.lists[0].last!, gh = b.lists[1].first!, gl = b.lists[1].last!, bh = b.lists[2].first!, bl = b.lists[2].last!
    b.volume = (e[rh].r - e[rl].r + 1) * (e[gh].g - e[gl].g + 1) * (e[bh].b - e[bl].b + 1)
    return b.volume
}

/// QuantHeap.c: a max-heap on pixel count, 1-based, with its exact sift order (ties matter).
private struct BoxHeap {
    var heap: [Box?] = [nil]
    var count: Int { heap.count - 1 }
    static func cmp(_ a: Box, _ b: Box) -> Int { Int(Int32(truncatingIfNeeded: a.pixelCount)) - Int(Int32(truncatingIfNeeded: b.pixelCount)) }
    mutating func add(_ v: Box) {
        heap.append(nil)
        var k = count
        while k != 1 {
            if BoxHeap.cmp(v, heap[k / 2]!) <= 0 { break }
            heap[k] = heap[k / 2]
            k >>= 1
        }
        heap[k] = v
    }
    mutating func remove() -> Box? {
        guard count > 0 else { return nil }
        let top = heap[1]!
        let v = heap[count]
        heap.removeLast()
        let n = count
        var k = 1
        while k * 2 <= n {
            var l = k * 2
            if l < n && BoxHeap.cmp(heap[l]!, heap[l + 1]!) < 0 { l += 1 }
            if BoxHeap.cmp(v!, heap[l]!) > 0 { break }
            heap[k] = heap[l]
            k = l
        }
        if n >= 1 { heap[k] = v }
        return top
    }
}

/// Splits `node` (Quant.c's split and splitlists); returns the two halves, the left holding the larger values' complement.
private func split(_ node: Box, _ e: [Entry]) -> (Box, Box) {
    let rh = e[node.lists[0].first!].r, rl = e[node.lists[0].last!].r
    let gh = e[node.lists[1].first!].g, gl = e[node.lists[1].last!].g
    let bh = e[node.lists[2].first!].b, bl = e[node.lists[2].last!].b
    let f = [(rh - rl) * 77, (gh - gl) * 150, (bh - bl) * 29]
    var axis = 0, best = f[0]
    for i in 1..<3 where best < f[i] { best = f[i]; axis = i }
    let list = node.lists[axis]
    var right = Set<Int>()                      // the entries flagged 1
    var counts: [UInt32] = [0, 0]
    var ci = 0
    var left: UInt32 = 0
    while ci < list.count {
        left &+= UInt32(e[list[ci]].count)
        counts[0] &+= UInt32(e[list[ci]].count)
        ci += 1
        if left &* 2 > node.pixelCount { break }
    }
    if ci < list.count {
        let splitVal = e[list[ci - 1]].v(axis)
        while ci < list.count, e[list[ci]].v(axis) == splitVal {
            counts[0] &+= UInt32(e[list[ci]].count)
            ci += 1
        }
    }
    while ci < list.count {
        right.insert(list[ci])
        counts[1] &+= UInt32(e[list[ci]].count)
        ci += 1
    }
    if right.isEmpty {
        let splitVal = e[list.last!].v(axis)
        var k = list.count - 1
        while k >= 0, e[list[k]].v(axis) == splitVal {
            right.insert(list[k])
            counts[0] &-= UInt32(e[list[k]].count)
            counts[1] &+= UInt32(e[list[k]].count)
            k -= 1
        }
    }
    var ll: [[Int]] = [], rl2: [[Int]] = []
    for i in 0..<3 {
        ll.append(node.lists[i].filter { !right.contains($0) })
        rl2.append(node.lists[i].filter { right.contains($0) })
    }
    node.lists = [[], [], []]
    let lb = Box(lists: ll, pixelCount: counts[0]), rb = Box(lists: rl2, pixelCount: counts[1])
    node.l = lb
    node.r = rb
    return (lb, rb)
}

struct MedianCutResult {
    /// The palette in Pillow's order (RGB as r << 16 | g << 8 | b).
    var palette: [UInt32]
    /// The palette index of every input pixel.
    var indices: [Int]
}

/// Image.quantize(colors:, method: MEDIANCUT, dither: NONE) on RGB pixels (r << 16 | g << 8 | b each).
func pillowMedianCut(_ pixels: [UInt32], colors: Int) throws -> MedianCutResult {
    guard colors >= 1, !pixels.isEmpty else { throw GifError(description: "median cut needs pixels and at least one colour") }
    // 1. hash the colours (a collision in the 32-bit hash merges two colours, as in the C: the first keeps the slot)
    var slots: [UInt32: Int] = [:]              // hash -> entry id
    var entries: [Entry] = []
    for k in pixels {
        let h = pixelHash(k)
        if let id = slots[h] { entries[id].count += 1; continue }
        slots[h] = entries.count
        entries.append(Entry(key: k, r: Int(k >> 16 & 255), g: Int(k >> 8 & 255), b: Int(k & 255), count: 1))
    }
    if entries.count > 65536 { throw GifError(description: "a frame has more than 65536 colours") }
    // 2. the lists, built from the table's iteration order (bucket, then ascending hash within it) by pushing at the head
    let length = hashTableLength(forCount: entries.count)
    let order = entries.indices.sorted {
        let ha = pixelHash(entries[$0].key), hb = pixelHash(entries[$1].key)
        let ba = ha % length, bb = hb % length
        return ba != bb ? ba < bb : ha < hb
    }
    let initial = Array(order.reversed())
    let root = Box(lists: (0..<3).map { mergesort(initial, entries, $0) }, pixelCount: UInt32(pixels.count))
    // 3. median cut
    var heap = BoxHeap()
    heap.add(root)
    var remaining = colors
    cut: while true {
        remaining -= 1
        if remaining == 0 { break }
        var node: Box
        repeat {
            guard let n = heap.remove() else { break cut }
            node = n
        } while boxVolume(node, entries) == 1
        let (l, r) = split(node, entries)
        heap.add(l)
        heap.add(r)
    }
    // 4. leaves left to right are the palette entries
    var boxOf: [UInt32: Int] = [:]              // hash -> palette entry
    var leaves = 0
    func annotate(_ n: Box) {
        if let l = n.l, let r = n.r { annotate(l); annotate(r); return }
        for id in n.lists[0] { boxOf[pixelHash(entries[id].key)] = leaves }
        if !n.lists[0].isEmpty { leaves += 1 }
    }
    annotate(root)
    // 5. each entry is the rounded mean of its pixels
    var sum = [[Int]](repeating: [0, 0, 0], count: leaves), cnt = [Int](repeating: 0, count: leaves)
    for k in pixels {
        let p = boxOf[pixelHash(k)]!
        sum[p][0] += Int(k >> 16 & 255); sum[p][1] += Int(k >> 8 & 255); sum[p][2] += Int(k & 255)
        cnt[p] += 1
    }
    func mean(_ s: Int, _ c: Int) -> Int { Int(0.5 + Double(s) / Double(c)) }
    let pal = (0..<leaves).map { (mean(sum[$0][0], cnt[$0]), mean(sum[$0][1], cnt[$0]), mean(sum[$0][2], cnt[$0])) }
    func dist(_ p: (Int, Int, Int), _ k: UInt32) -> Int {
        let a = p.0 - Int(k >> 16 & 255), b = p.1 - Int(k >> 8 & 255), c = p.2 - Int(k & 255)
        return a * a + b * b + c * c
    }
    // 6. each pixel: the nearest entry, searched outward from its box's entry in order of distance between entries
    var between = [[Int]](repeating: [Int](repeating: 0, count: leaves), count: leaves)
    for i in 0..<leaves {
        for j in 0..<leaves {
            let a = pal[i].0 - pal[j].0, b = pal[i].1 - pal[j].1, c = pal[i].2 - pal[j].2
            between[i][j] = a * a + b * b + c * c
        }
    }
    let byDistance = (0..<leaves).map { i in (0..<leaves).sorted { between[i][$0] != between[i][$1] ? between[i][$0] < between[i][$1] : $0 < $1 } }
    var memo: [UInt32: Int] = [:]
    var indices: [Int] = []
    indices.reserveCapacity(pixels.count)
    for k in pixels {
        if let m = memo[k] { indices.append(m); continue }
        let start = boxOf[pixelHash(k)]!
        var bestMatch = start
        var bestDist = dist(pal[start], k)
        let limit = bestDist << 2
        for idx in byDistance[start] {
            if between[start][idx] > limit { break }
            let d = dist(pal[idx], k)
            if d < bestDist { bestDist = d; bestMatch = idx }
        }
        memo[k] = bestMatch
        indices.append(bestMatch)
    }
    return MedianCutResult(palette: pal.map { UInt32($0.0) << 16 | UInt32($0.1) << 8 | UInt32($0.2) }, indices: indices)
}
