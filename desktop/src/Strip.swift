// A strip: one 48-row band-shaped piece of the valley (the homestead, or one
// session's camp), addressed exactly as the terminal band is (x to the right, row
// 0 at the top, GROUND 39, FOOT 40, the road the bottom rows), so the band's
// drawing ports line for line. A strip is a container layer in the scene; what it
// shows is grouped in parts (a part is a few layers built from one key), and a
// part is rebuilt only when its key changes.
//
// Frame-driven things follow the band's own frame clock (register.tsx snapshot):
// the frame turns every 500 ms tick while something moves, every 3 s otherwise,
// and not at all while the session is still. A frame-driven layer is one set of
// discrete keyframes (contents and position for each frame of its cycle) played
// by Core Animation from the record's `frame`/`at` anchor, on the scene's 10 Hz
// step grid: nothing in the app runs per frame.

import AppKit
import QuartzCore

let bandHeight = 48
let GROUND = 39, FOOT = 40, ROAD_TOP = 41, BOTTOM = 48

/// The band's frame clock, anchored: `frame0` was the frame at world time `at`.
struct FrameClock {
    let frame0: Int
    let at: CFTimeInterval
    let period: Double
    let frozen: Bool
    func frame(_ t: CFTimeInterval) -> Int { frozen ? frame0 : frame0 + Int(((t - at) / period).rounded(.down)) }
    /// World time when frame `f` began.
    func start(of f: Int) -> CFTimeInterval { at + Double(f - frame0) * period }
}

final class Strip {
    let art: Art
    let layer = CALayer()
    let width: Int
    private var parts: [String: (key: String, layers: [CALayer])] = [:]
    weak var scene: FarmScene?

    init(art: Art, width: Int, scene: FarmScene) {
        self.art = art
        self.width = width
        self.scene = scene
        layer.anchorPoint = .zero
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: bandHeight)
        layer.masksToBounds = false
    }

    // MARK: Parts

    /// Rebuilds part `name` with `build` only if `key` changed; returns whether it did.
    @discardableResult
    func part(_ name: String, key: String, _ build: () -> [CALayer]) -> Bool {
        if let old = parts[name], old.key == key { return false }
        let fresh = build()
        parts[name]?.layers.forEach { $0.removeFromSuperlayer() }
        fresh.forEach { if $0.superlayer == nil { layer.addSublayer($0) } }
        parts[name] = (key, fresh)
        return true
    }

    func clear(_ name: String) {
        parts[name]?.layers.forEach { $0.removeFromSuperlayer() }
        parts[name] = nil
    }

    func clearAll() { for name in Array(parts.keys) { clear(name) } }

    // MARK: Layers in band coordinates

    /// y (layer, from the strip's bottom) of a box whose top is band row `top` and that is `h` tall.
    func ly(_ top: Int, _ h: Int) -> CGFloat { CGFloat(bandHeight - top - h) }

    /// A static picture of the whole strip (band coordinates inside), as one layer.
    func picture(_ pix: Pix, z: CGFloat) -> CALayer {
        let l = CALayer()
        l.contents = pix.image()
        l.magnificationFilter = .nearest
        l.minificationFilter = .nearest
        l.anchorPoint = .zero
        l.bounds = CGRect(x: 0, y: 0, width: pix.w, height: pix.h)
        l.position = CGPoint(x: 0, y: CGFloat(bandHeight - pix.h))
        l.zPosition = z
        return l
    }

    /// A sprite layer with its top-left at band (x, y).
    func sprite(_ name: String, x: Int, y: Int, frame: Int = 0, flip: Bool = false, z: CGFloat, dim: Bool = false) -> CALayer {
        let l = CALayer()
        l.name = name // for the cast count (FarmScene.castCount)
        let image = art.image(name, frame)
        l.contents = image
        l.magnificationFilter = .nearest
        l.minificationFilter = .nearest
        l.anchorPoint = .zero
        l.bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        l.position = CGPoint(x: CGFloat(x), y: ly(y, image.height))
        l.zPosition = z
        if flip { l.anchorPoint = CGPoint(x: 0.5, y: 0); l.position.x += CGFloat(image.width) / 2; l.transform = CATransform3DMakeScale(-1, 1, 1) }
        if dim { l.opacity = 0.5 } // the band mixes a dim pixel half and half with what is under it
        return l
    }

    /// A sprite standing on band row `bottom`.
    func standing(_ name: String, x: Int, bottom: Int, frame: Int = 0, flip: Bool = false, z: CGFloat, dim: Bool = false) -> CALayer {
        sprite(name, x: x, y: bottom - art.height(name), frame: frame, flip: flip, z: z, dim: dim)
    }

    /// A frame-driven layer: for each frame f of a cycle of `count` frames from the
    /// clock's current frame, `look(f)` gives the sprite, its frame and its top-left
    /// (nil: hidden that frame). Discrete keyframes from the anchor, looping; a
    /// frozen clock or a one-frame cycle is a plain static layer.
    func flipbook(clock: FrameClock, count: Int, z: CGFloat, flip: Bool = false, dim: Bool = false,
                  _ look: (Int) -> (name: String, frame: Int, x: Int, y: Int)?) -> CALayer? {
        guard let world = scene?.world else { return nil }
        let now = world.convertTime(CACurrentMediaTime(), from: nil)
        let f0 = clock.frame(now)
        let n = clock.frozen ? 1 : max(1, min(count, 720))
        var images: [Any] = [], spots: [NSValue] = [], hidden: [NSNumber] = []
        var first: (name: String, frame: Int, x: Int, y: Int)?
        for i in 0..<n {
            if let v = look(f0 + i) {
                let image = art.image(v.name, v.frame)
                images.append(image)
                spots.append(NSValue(point: CGPoint(x: CGFloat(v.x) + (flip ? CGFloat(image.width) / 2 : 0), y: ly(v.y, image.height))))
                hidden.append(0)
                if first == nil { first = v }
            } else {
                images.append(images.last ?? art.image("note"))
                spots.append(spots.last ?? NSValue(point: .zero))
                hidden.append(1)
            }
        }
        guard let first else { return nil }
        let l = sprite(first.name, x: first.x, y: first.y, frame: first.frame, flip: flip, z: z, dim: dim)
        // The layer's own values are those of frame f0 (in case an animation is dropped).
        l.contents = images[0]
        l.position = spots[0].pointValue
        l.isHidden = hidden[0] == 1
        guard n > 1 else { return l }
        let begin = scene?.snapTime(clock.start(of: f0)) ?? clock.start(of: f0)
        let keyTimes = (0...n).map { NSNumber(value: Double($0) / Double(n)) }
        func discrete(_ path: String, _ values: [Any]) -> CAKeyframeAnimation? {
            // Only animate what changes over the cycle.
            if path == "position", Set(spots.map(\.pointValue.x)).count == 1, Set(spots.map(\.pointValue.y)).count == 1 { return nil }
            if path == "hidden", Set(hidden).count == 1 { return nil }
            if path == "contents", Set(images.map { ObjectIdentifier($0 as AnyObject) }).count == 1 { return nil }
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values
            a.keyTimes = keyTimes
            a.calculationMode = .discrete
            a.duration = clock.period * Double(n)
            a.repeatCount = .infinity
            a.beginTime = begin
            return a
        }
        if let a = discrete("contents", images) { scene?.runCalm(a, on: l, key: "frames") }
        if let a = discrete("position", spots) { scene?.runCalm(a, on: l, key: "spot") }
        if let a = discrete("hidden", hidden) { scene?.runCalm(a, on: l, key: "hide") }
        return l
    }

    /// A pass: a layer whose top-left x (band) follows `x(s)` for s seconds from now,
    /// as smooth linear keyframes (ten a second), then holds; its frames by the clock.
    func pass(_ l: CALayer, seconds: Double, y: Int? = nil, _ x: (Double) -> Double) {
        guard seconds > 0.05 else { return }
        let steps = max(2, Int(seconds * 10))
        let w = l.bounds.width
        let offset = l.anchorPoint.x * w
        let a = CAKeyframeAnimation(keyPath: "position.x")
        a.values = (0...steps).map { CGFloat(x(seconds * Double($0) / Double(steps))) + offset }
        a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        a.calculationMode = .linear
        a.duration = seconds
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        l.position.x = CGFloat(x(0)) + offset
        scene?.runPass(a, on: l, key: "pass")
    }

    /// A painted text or shape layer at band (x, y) of the given picture.
    func painted(_ pix: Pix, x: Int, y: Int, z: CGFloat) -> CALayer {
        let l = CALayer()
        l.contents = pix.image()
        l.magnificationFilter = .nearest
        l.minificationFilter = .nearest
        l.anchorPoint = .zero
        l.bounds = CGRect(x: 0, y: 0, width: pix.w, height: pix.h)
        l.position = CGPoint(x: CGFloat(x), y: ly(y, pix.h))
        l.zPosition = z
        return l
    }
}

// MARK: - The speech bubble (pixel-scene.ts bubbleLines / bubbleBox / drawBubble)

/// The words wrapped to at most two lines of `chars`; a word too long is cut with two dots.
func bubbleLines(_ line: String, chars: Int) -> [String] {
    var queue = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    let cut = { (word: String) in String(word.prefix(max(0, chars - 2))) + ".." }
    var lines = [""]
    while !queue.isEmpty {
        let word = queue.removeFirst()
        let current = lines[lines.count - 1]
        if lines.count == 1 && current.isEmpty && word.count > chars {
            lines[0] = String(word.prefix(chars))
            queue.insert(String(word.dropFirst(chars)), at: 0)
            lines.append("")
            continue
        }
        let next = current.isEmpty ? word : "\(current) \(word)"
        if next.count <= chars {
            lines[lines.count - 1] = next
        } else if lines.count < 2 {
            lines.append(word.count > chars ? cut(word) : word)
            if word.count > chars { break }
        } else if current.isEmpty {
            lines[1] = cut(word)
            break
        } else {
            let kept = current.count + 2 <= chars ? current : String(current.prefix(chars - 2))
            lines[1] = kept.trimmingCharacters(in: .whitespaces) + ".."
            break
        }
    }
    return lines.filter { !$0.isEmpty }
}

struct BubbleBox { let x: Int, y: Int, w: Int, h: Int; let lines: [String] }

/// The bubble left of Jeb's head: its right edge at jebX - 1, at most 30 characters
/// a line, its left edge no further left than `leftLimit`; nil with under 8 characters of room.
func bubbleBox(line: String, jebX: Int, leftLimit: Int) -> BubbleBox? {
    var said = line
    if said.hasPrefix("Jeb: ") { said = String(said.dropFirst(5)) }
    guard !said.isEmpty else { return nil }
    let right = jebX - 1
    let left = max(leftLimit, right - (30 * 4 + 6))
    let chars = min(30, (right - left - 6) / 4)
    guard chars >= 8 else { return nil }
    let lines = bubbleLines(said, chars: chars)
    guard !lines.isEmpty else { return nil }
    let w = (lines.map(textWidth).max() ?? 0) + 6, h = lines.count * 6 + 5
    return BubbleBox(x: right - w, y: 1, w: w, h: h, lines: lines)
}

extension Art {
    /// The bubble picture: box plus tail (w + 3 wide), in its own Pix.
    func bubblePix(_ box: BubbleBox, dim: Bool) -> Pix {
        var c = Pix(w: box.w + 3, h: box.h)
        let edge = colour(dim ? "stone" : "ink"), fill = colour("white"), ink = colour(dim ? "grey" : "ink")
        let w = box.w, h = box.h
        c.rect(1, 0, w - 2, h, edge)
        c.rect(0, 1, w, h - 2, edge)
        c.rect(1, 1, w - 2, h - 2, fill)
        let ty = h - 6
        c.rect(w - 1, ty, 1, 4, fill)
        c.rect(w, ty + 1, 1, 3, fill)
        c.rect(w + 1, ty + 2, 1, 2, fill)
        c.rect(w + 2, ty + 3, 1, 1, fill)
        for (i, l) in box.lines.enumerated() {
            // Only the font's own glyphs: anything else is a space.
            text(String(l.map { hasGlyph($0) ? $0 : " " }), into: &c, x: 3, y: 3 + i * 6, colour: ink)
        }
        return c
    }
}

/// A small whole-number hash for scattered things (pixel-scene.ts scatter).
func scatter(_ a: Int, _ b: Int) -> Int { abs((a &* 7919 &+ b &* 104729 &+ a &* b &* 31) % 9973) }

/// The band's string hash (pixel-scene.ts hashOf).
func hashOf(_ s: String) -> UInt32 {
    var h: UInt32 = 0
    for u in s.utf16 { h = h &* 31 &+ UInt32(u) }
    return h
}

/// Blue's chase offset (0..6 and back) over twelve frames.
func chaseOffset(_ frame: Int) -> Int { let s = ((frame % 12) + 12) % 12; return s <= 6 ? s : 12 - s }

// MARK: - Drawing shared by every place (the homestead and the camps)

/// The x positions a place gives the shared drawing (a happening, a truck, a visitor, the bubble), in strip pixels.
struct Anchors: Equatable { let width, houseX, orchardX, cornX, blueX, jebX: Int }

let RIG_SPRITES = ["store": "rig-store", "mill": "rig-mill", "tripper": "rig-tripper", "mail": "rig-mail", "tractor": "rig-tractor"]

extension Strip {
    /// A speech bubble left of a Jeb at `jebX`.
    func bubble(_ line: String, jebX: Int, dim: Bool) -> [CALayer] {
        guard let box = bubbleBox(line: line, jebX: jebX, leftLimit: 2) else { return [] }
        return [painted(art.bubblePix(box, dim: dim), x: box.x, y: box.y, z: 20)]
    }

    /// Pictures shown by frame: `pick(f)` names the picture for frame f (nil: none), over a cycle of `count` frames.
    func indexedBook(_ pics: [Pix], count: Int, clock: FrameClock, y: Int, z: CGFloat, _ pick: (Int) -> Int?) -> CALayer? {
        guard !pics.isEmpty, let scene else { return nil }
        let images = pics.map { $0.image() }
        let l = painted(pics[0], x: 0, y: y, z: z)
        let f0 = clock.frame(scene.worldNow)
        let norm = { (f: Int) in ((f % count) + count) % count }
        let first = pick(norm(f0))
        l.contents = first.map { images[$0] } ?? images[0]
        l.isHidden = first == nil
        guard !clock.frozen, count > 1 else { return l }
        let picks = (0..<count).map { pick(norm(f0 + $0)) }
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = picks.map { images[$0 ?? 0] }
        let h = CAKeyframeAnimation(keyPath: "hidden")
        h.values = picks.map { NSNumber(value: $0 == nil) }
        for anim in [a, h] {
            anim.keyTimes = (0...count).map { NSNumber(value: Double($0) / Double(count)) }
            anim.calculationMode = .discrete
            anim.duration = clock.period * Double(count)
            anim.repeatCount = .infinity
            anim.beginTime = scene.snapTime(clock.start(of: f0))
        }
        scene.runCalm(a, on: l, key: "frames")
        scene.runCalm(h, on: l, key: "hide")
        return l
    }

    /// A list of whole-strip-width pictures (top at band row y) shown one a frame.
    func pixFlipbook(_ frames: [Pix], clock: FrameClock, y: Int, z: CGFloat) -> CALayer? {
        guard !frames.isEmpty, let scene else { return nil }
        let images = frames.map { $0.image() }
        let l = painted(frames[0], x: 0, y: y, z: z)
        let f0 = clock.frame(scene.worldNow)
        let n = images.count
        let ordered = (0..<n).map { images[((f0 + $0) % n + n) % n] }
        l.contents = ordered[0]
        guard !clock.frozen, n > 1 else { return l }
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = ordered
        a.keyTimes = (0...n).map { NSNumber(value: Double($0) / Double(n)) }
        a.calculationMode = .discrete
        a.duration = clock.period * Double(n)
        a.repeatCount = .infinity
        a.beginTime = scene.snapTime(clock.start(of: f0))
        scene.runCalm(a, on: l, key: "frames")
        return l
    }

    // MARK: Happenings (drawEvent)

    /// The happening's layers at this place. `drop` draws the creative drops (the homestead's own decor; a camp has none).
    func eventLayers(_ ev: LiveEvent, clock: FrameClock, wall: Double, anchors a: Anchors, drop: (() -> [CALayer])? = nil) -> [CALayer] {
        guard let scene else { return [] }
        let nowWall = scene.now.timeIntervalSince1970 * 1000
        // The happening's tick now, moved on from the record while it moves.
        let resting = restOf(id: ev.id, t: ev.t, dur: ev.dur) != nil
        let tNow = resting ? Double(ev.t) : min(Double(ev.dur), Double(ev.t) + (nowWall - wall) / 500)
        let remain = max(0, (Double(ev.dur) - tNow) * tickSeconds)
        let p0 = tNow / Double(ev.dur)
        let dur = Double(ev.dur)
        let width = a.width
        var out: [CALayer] = []
        func add(_ l: CALayer?) { if let l { out.append(l) } }
        switch ev.id {
        case "revenuer":
            if let l = flipbook(clock: clock, count: 2, z: 11, { f in ("revenuer", f, 0, BOTTOM - 15) }) {
                pass(l, seconds: remain) { s in (-32 + (tNow + s / tickSeconds) / dur * Double(a.houseX - 4)).rounded() }
                if remain < 0.05 { l.position.x = CGFloat(-32 + p0 * Double(a.houseX - 4)) }
                add(l)
            }
        case "neighbor":
            // Miss Opal walks over to Blue, stands a spell, and walks home.
            let target = Double(a.blueX + 2)
            let xAt = { (p: Double) -> Double in p < 0.5 ? (p / 0.5 * target).rounded() : p < 0.8 ? target : (target * (1 - (p - 0.8) / 0.2)).rounded() }
            let l = standing("opal", x: Int(xAt(p0)), bottom: BOTTOM - 1, z: 11)
            if !resting {
                // To the end of this moving stretch (the rest begins at 0.5; the walk home ends at 1).
                let end = p0 < 0.5 ? 0.5 : 1.0
                let secs = max(0, (end * dur - tNow) * tickSeconds)
                pass(l, seconds: secs) { s in xAt(min(end, (tNow + s / tickSeconds) / dur)) }
            }
            out.append(l)
        case "bear": add(standing("bear", x: a.orchardX + 14, bottom: FOOT, z: 9))
        case "whistlepig": add(standing("groundhog", x: a.cornX + 4 + (ev.v % 4) * 10, bottom: FOOT, z: 9))
        case "mothman":
            add(flipbook(clock: FrameClock(frame0: ev.t / 6, at: clock.at, period: clock.period, frozen: clock.frozen), count: 8, z: 9) { f in
                isMothHidden(t: f * 6, dur: ev.dur, v: ev.v) ? nil : ("mothman", 0, a.orchardX + 16, 8)
            })
        case "bugs":
            let room = max(8, a.blueX - 6)
            for i in 0..<5 {
                // Positions move with t (every 6 and 12 ticks), the blink with the frame.
                add(flipbook(clock: clock, count: 12, z: 9) { f in
                    let t = ev.t + (f - clock.frame0) * (resting ? 6 : 1)
                    return ("firefly", f + i, scatter(ev.v + i, t / 6 + i * 3) % room, 8 + ((i + t / 12) % 3) * 8)
                })
            }
        case "bells":
            add(sprite("prop-bell", x: a.houseX - 12, y: 6, z: 9))
            add(flipbook(clock: clock, count: 2, z: 9) { f in ("note", 0, a.houseX - 4 + (f % 2) * 3, 1) })
        case "storm":
            add(sprite("cloud-dark", x: a.houseX - 30, y: 0, z: 9))
            // Rain over the whole width, a drop every 6 px: top 10 + ((x*7 + frame*4) % 24).
            var frames: [Pix] = []
            for f in 0..<6 {
                var p = Pix(w: width, h: 40)
                for x in stride(from: 0, to: width, by: 6) { p.rect(x, 10 + ((x * 7 + f * 4) % 24), 1, 3, art.colour("drop")) }
                frames.append(p)
            }
            add(pixFlipbook(frames, clock: clock, y: 0, z: 9.5))
        case "fog":
            var p = Pix(w: width, h: 24)
            let mist = word(215, 222, 232)
            for y in 2..<24 { for x in 0..<width where (x + y + ev.t / 8) % 3 != 0 { p.dot(x, y, mist) } }
            let l = painted(p, x: 0, y: 0, z: 13)
            l.opacity = 0.5
            add(l)
        case "turkeys":
            let w = Double(width)
            for (k, dx) in [(0, 0), (1, -18)] {
                if let l = flipbook(clock: clock, count: 2, z: 11, { f in ("turkey", f + k, 0, BOTTOM - 13) }) {
                    pass(l, seconds: remain) { s in ((tNow + s / tickSeconds) / dur * (w + 28)).rounded() - 14 + Double(dx) }
                    add(l)
                }
            }
        case "parachute":
            let l = sprite("prop-parachute", x: a.orchardX + 6, y: 0, z: 9)
            let steps = max(2, Int(remain * 10))
            let anim = CAKeyframeAnimation(keyPath: "position")
            anim.values = (0...steps).map { i -> NSValue in
                let p = (tNow + Double(i) / Double(steps) * remain / tickSeconds) / dur
                let x = Double(a.orchardX + 6) + (p * 24).rounded(), y = (p * Double(GROUND - 14)).rounded()
                return NSValue(point: CGPoint(x: x, y: Double(ly(Int(y), 14))))
            }
            anim.duration = max(0.1, remain)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            l.position = (anim.values?.first as? NSValue)?.pointValue ?? l.position
            if remain > 0.05 { scene.runPass(anim, on: l, key: "drift") }
            add(l)
        case "drop":
            if let drop { out.append(contentsOf: drop()) }
        default: break
        }
        return out
    }

    // MARK: Trucks (drawTruck)

    func truckLayers(_ truck: LiveTruck, clock: FrameClock, wall: Double, houseX: Int) -> [CALayer] {
        guard let scene else { return [] }
        let x0 = Double(houseX + 4)
        let nowWall = scene.now.timeIntervalSince1970 * 1000
        let tNow = min(Double(truckTicks), Double(truck.t) + (nowWall - wall) / 500)
        var out: [CALayer] = []
        // Out it heads left (turned), home it faces the house; each leg its own layers.
        for leg in [true, false] {
            let from = leg ? 0.0 : Double(truckTicks / 2), to = leg ? Double(truckTicks / 2) : Double(truckTicks)
            guard tNow < to else { continue }
            let startIn = max(0, (from - tNow) * tickSeconds), span = (to - max(tNow, from)) * tickSeconds
            let name = leg ? (TRUCK_SPRITES[truck.load] ?? "truck-crate") : "truck-empty"
            let group = CALayer()
            group.anchorPoint = .zero
            group.bounds = CGRect(x: 0, y: 0, width: truckW + 20, height: 22)
            group.zPosition = 12
            group.position = CGPoint(x: 0, y: 0)
            if let f = flipbook(clock: clock, count: 2, z: 0, flip: leg, { f in (name, f, 10, BOTTOM - 22) }) { group.addSublayer(f) }
            let icon = leg ? TRUCK_ICONS[truck.load] : "icon-cash"
            if let icon { group.addSublayer(sprite(icon, x: leg ? 10 + truckW - 16 : 10 + 8, y: BOTTOM - 20, z: 1)) }
            if truck.dog, let dog = flipbook(clock: clock, count: 2, z: 1, { f in ("blue-wag", f, leg ? 10 + truckW - 24 : 10 + 4, BOTTOM - 10 - 13) }) { group.addSublayer(dog) }
            if let dust = flipbook(clock: clock, count: 2, z: 1, { f in ("dust", f, leg ? 10 + truckW : 0, BOTTOM - 8) }) { group.addSublayer(dust) }
            // The group moves as the truck: its x is the truck's x minus the 10 px dust margin.
            group.isHidden = startIn > 0
            let a = CAKeyframeAnimation(keyPath: "position.x")
            let steps = max(2, Int(span * 10))
            a.values = (0...steps).map { i in
                let t = max(tNow, from) + (to - max(tNow, from)) * Double(i) / Double(steps)
                return CGFloat(truckPx(t, x0: x0).rounded() - 10)
            }
            a.duration = span
            a.beginTime = scene.worldNow + startIn
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            group.position.x = CGFloat(truckPx(max(tNow, from), x0: x0).rounded() - 10)
            scene.runPass(a, on: group, key: "drive")
            if startIn > 0 {
                let show = CAKeyframeAnimation(keyPath: "hidden")
                show.values = [1, 0]; show.keyTimes = [0, NSNumber(value: startIn / (startIn + span)), 1]
                show.calculationMode = .discrete
                show.duration = startIn + span
                show.fillMode = .forwards; show.isRemovedOnCompletion = false
                group.isHidden = false
                scene.runPass(show, on: group, key: "show")
            }
            if span > 0 {
                // Gone at the end of its leg (home: the record takes the truck off as it arrives).
                let hide = CAKeyframeAnimation(keyPath: "hidden")
                hide.values = [0, 1]; hide.keyTimes = [0, 1, 1]
                hide.calculationMode = .discrete
                hide.duration = span
                hide.fillMode = .forwards; hide.isRemovedOnCompletion = false
                scene.runPass(hide, on: group, key: "gone")
            }
            if truck.sputter > 0 && leg, let s = flipbook(clock: clock, count: 2, z: 1, { f in ("dust", f + 1, 10 + 20 + (truck.sputter % 2) * 3, BOTTOM - 8) }) { group.addSublayer(s) }
            out.append(group)
        }
        return out
    }

    // MARK: Visitors (drawVisit), moved on from the record at the band's pace

    func visitLayers(_ r: LiveRecord, clock: FrameClock, anchors g: Anchors) -> [CALayer] {
        guard let scene, let v = r.visit, let spec = visitSpecs[v.kind] else { return [] }
        let nowMs = scene.now.timeIntervalSince1970 * 1000
        let ticks = max(0, (nowMs - r.at) / 500)
        let rate = Double(spec.step) / Double(spec.every) // progress per tick
        let dir: Double = v.phase == "arrive" ? 1 : v.phase == "leave" ? -1 : 0
        let x0 = Double(v.x) + dir * rate * ticks
        // How long until it stops (at its reach, or back off the edge).
        let limit = dir > 0 ? Double(spec.reach) : 0
        let travel = dir == 0 ? 0 : max(0, abs(limit - x0) / rate * tickSeconds)
        let progress = { (s: Double) in dir == 0 ? x0 : max(0, min(Double(spec.reach), x0 + dir * rate * s / tickSeconds)) }
        let out = v.facing == "out"
        var layers: [CALayer] = []
        if v.kind == "opal" {
            let stop = Double(max(0, g.blueX - 14 - 6))
            if let l = flipbook(clock: clock, count: 2, z: 11, flip: out, { f in ("opal", f, 0, FOOT - 28) }) {
                l.position.x = CGFloat(visitAt(kind: v.kind, x: x0, from: -14, stop: stop).rounded()) + (out ? 7 : 0)
                pass(l, seconds: travel) { s in visitAt(kind: v.kind, x: progress(s), from: -14, stop: stop).rounded() }
                layers.append(l)
            }
            return layers
        }
        let stop = v.kind == "tractor" ? Double(g.width) : Double(max(0, g.blueX - 40 - 6))
        let moving = v.phase != "deal"
        guard let rig = RIG_SPRITES[v.kind] else { return [] }
        // The rig and its dust ride together in one group.
        let group = CALayer()
        group.anchorPoint = .zero
        group.bounds = CGRect(x: 0, y: 0, width: 60, height: 20)
        group.zPosition = 11
        if let l = flipbook(clock: moving ? clock : FrameClock(frame0: 0, at: 0, period: 1, frozen: true), count: 2, z: 0, flip: out, { f in (rig, moving ? f : 0, 10, BOTTOM - 20) }) { group.addSublayer(l) }
        if moving, let d = flipbook(clock: clock, count: 2, z: 0, { f in ("dust", f, out ? 50 : 0, BOTTOM - 8) }) { group.addSublayer(d) }
        group.position = CGPoint(x: CGFloat(visitAt(kind: v.kind, x: x0, from: -40, stop: stop).rounded() - 10), y: 0)
        pass(group, seconds: travel) { s in visitAt(kind: v.kind, x: progress(s), from: -40, stop: stop).rounded() - 10 }
        layers.append(group)
        return layers
    }
}
