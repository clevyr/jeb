// The desktop scene: the valley. A Core Animation layer tree built at native
// pixel size (one layer unit per art pixel) and scaled by a whole number of device
// pixels, every layer filtered .nearest, so pixels stay crisp.
//
//   the sky (its colour by the hour), the sun or moon on its arc, stars, clouds
//   exactly one place root at a time (named place:home, place:camp or place:road),
//   holding its own land, its one stage strip on the road above the Dock, and its
//   actors; a place that is left is torn down and removed from the tree, never hidden
//     home: the homestead (Homestead.swift), the shared farm, with its chimney smoke
//     camp: the camp of the session Jeb is visiting (Camp.swift)
//     road: the walk between two places (Road.swift)
//   the one Jeb and Blue (Cast.swift), at whichever place is on show
//   which place, and the story's lines, come from the App's one Story (Story.swift)
//
// Nothing runs per frame in the app. What stands still is layer contents painted
// once and repainted only when its inputs change (the farm, a live record, the
// minute). Calm motion (clouds, smoke, the band's frame-driven sprites) is
// discrete Core Animation keyframes on one shared 10 Hz step grid; passes (a truck,
// a visitor's rig, a happening that walks) are smooth keyframes. The app wakes only
// for a store or art change, the minute, and the few scene-time callbacks below
// (a bubble going down), and the story's deadlines. Pausing stops the world's clock
// (`speed = 0`): every layer keeps showing where it was, so the window is never empty.

import AppKit
import QuartzCore

let applyLog = env["JEB_APPLY_LOG"] == "1"
func isNightHour(_ hour: Int) -> Bool { hour >= 21 || hour < 6 }

/// The moon's frame (0-7, new to waning) on `date`: its age in the synodic month, in eighths.
func moonPhase(_ date: Date) -> Int {
    let days = date.timeIntervalSince1970 / 86_400 + 2440587.5 - 2451550.1
    let phase = (days.truncatingRemainder(dividingBy: 29.530588853) / 29.530588853 + 1).truncatingRemainder(dividingBy: 1)
    return Int((phase * 8).rounded()) % 8
}

/// The clock: the real one, or a fixed moment for a fixture render (JEB_NOW, ms since the epoch).
let fixedNow: Date? = env["JEB_NOW"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
func nowDate() -> Date { fixedNow ?? Date() }

func hourNow() -> Double {
    if let fixed = ProcessInfo.processInfo.environment["JEB_HOUR"].flatMap(Double.init) { return fixed }
    let c = Calendar.current.dateComponents([.hour, .minute], from: nowDate())
    return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
}

/// Sky colours by time of day (top, horizon), between fixed keyframes.
let skyKeys: [(hour: Double, top: UInt32, low: UInt32)] = [
    (0, word(11, 16, 38), word(27, 36, 71)), (5, word(11, 16, 38), word(27, 36, 71)),
    (6.5, word(58, 63, 116), word(242, 160, 107)), (8.5, word(77, 143, 214), word(169, 212, 242)),
    (17.5, word(77, 143, 214), word(169, 212, 242)), (19.5, word(59, 63, 122), word(240, 138, 93)),
    (21, word(11, 16, 38), word(27, 36, 71)), (24, word(11, 16, 38), word(27, 36, 71)),
]

func skyColours(hour: Double) -> (top: UInt32, low: UInt32) {
    let i = skyKeys.lastIndex { $0.hour <= hour } ?? 0
    let a = skyKeys[i], b = skyKeys[min(i + 1, skyKeys.count - 1)]
    let t = b.hour > a.hour ? (hour - a.hour) / (b.hour - a.hour) : 0
    return (mix(a.top, b.top, t), mix(a.low, b.low, t))
}

/// The scene's size and where the Dock and menu bar sit, in scene pixels.
struct Layout: Equatable {
    let width: Int, height: Int, scale: Int // scene pixels; device pixels per scene pixel
    let bottom: Int, left: Int, right: Int, top: Int // insets: the Dock (one of the first three) and menu bar

    init(screen: NSScreen) { self.init(frame: screen.frame, visible: screen.visibleFrame, backing: screen.backingScaleFactor) }

    init(frame f: CGRect, visible v: CGRect, backing s: CGFloat) {
        let pxW = f.width * s, pxH = f.height * s
        // About 270 scene rows on any screen, but never narrower than the farm needs.
        var n = max(1, Int(pxH / 270))
        while n > 1 && pxW / CGFloat(n) < 320 { n -= 1 }
        scale = n
        width = Int((pxW / CGFloat(n)).rounded(.up))
        height = Int((pxH / CGFloat(n)).rounded(.up))
        let px = { (points: CGFloat) in Int((points * s / CGFloat(n)).rounded(.up)) }
        bottom = px(v.minY - f.minY)
        left = px(v.minX - f.minX)
        right = px(f.maxX - v.maxX)
        top = px(f.maxY - v.maxY)
    }
}

/// Measuring only: JEB_ANIMS=clouds,smoke,leaves,stars (default all) limits the
/// desktop's own calm ambience.
let animKinds = Set((env["JEB_ANIMS"] ?? "clouds,smoke,leaves,stars,band").split(separator: ",").map(String.init))
func animOn(_ kind: String) -> Bool { animKinds.contains(kind) }

/// Scene-time callbacks on one main-thread timer, read from the scene's own layer
/// clock, so a pause holds them exactly where they were.
final class SceneClock {
    private var events: [(at: CFTimeInterval, seq: Int, key: String?, block: () -> Void)] = []
    private var timer: Timer?
    private var seq = 0
    private let now: () -> CFTimeInterval
    var running = true { didSet { reschedule() } }
    private(set) var fired = 0

    init(now: @escaping () -> CFTimeInterval) { self.now = now }

    func after(_ seconds: Double, key: String? = nil, _ block: @escaping () -> Void) {
        if let key { events.removeAll { $0.key == key } }
        seq += 1
        events.append((now() + seconds, seq, key, block))
        reschedule()
    }

    func stop() { timer?.invalidate(); timer = nil; events = [] }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard running, let next = events.map(\.at).min() else { return }
        let t = Timer(timeInterval: max(0.001, next - now()), repeats: false) { [weak self] _ in self?.fire() }
        t.tolerance = 0.03
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fire() {
        fired += 1
        let t = now() + 0.002
        let due = events.filter { $0.at <= t }.sorted { ($0.at, $0.seq) < ($1.at, $1.seq) }
        let ids = Set(due.map(\.seq))
        events.removeAll { ids.contains($0.seq) }
        for e in due { e.block() }
        reschedule()
    }
}

/// Changes to layers without Core Animation's implicit fades and slides.
func quiet<T>(_ body: () -> T) -> T {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    return body()
}

final class FarmScene {
    let art: Art
    let layout: Layout
    let valley: Valley
    let isNight: Bool
    private(set) var farm: Farm
    private(set) var live: [String: LiveRecord]

    let world = CALayer()
    private lazy var clock = SceneClock { [unowned self] in self.worldNow }
    private(set) var running = true
    private let tick = 1 / calmHz // the calm step clock: every calm change on a tick (a tenth of a second, adaptive)
    private let calmRange = CAFrameRateRange(minimum: Float(min(10, calmFps)), maximum: Float(calmFps), preferred: Float(calmFps))
    private let passRange = CAFrameRateRange(minimum: Float(min(30, fps)), maximum: Float(fps), preferred: Float(fps))

    private let sky = CALayer(), sunOrMoon = CALayer()
    private var skyKey: (UInt32, UInt32)?
    let story: Story
    /// The one place in the tree: its root, its land, and whichever of the three it is.
    private var placeRoot: CALayer?
    private var land: CALayer?
    private var landKey = ""
    private var placeKey = ""
    private var homestead: Homestead?
    private var camp: Camp?
    private var road: Road?
    private var homeClock: FrameClock!
    private var actingStable: FrameClock?
    private var actingToken: String?
    private var homeActing = false
    private(set) var sessionCount = 0
    private(set) var placeKind = "home"
    private(set) var queueLength = 0
    private let month = Calendar.current.component(.month, from: nowDate())
    private(set) var updates = 0

    // Home Jeb and Blue (no session out at camp): the desktop's own calm idle.
    private let homeJeb = CALayer(), homeBlue = CALayer()
    private var homeExtras: [CALayer] = []
    private var act = 0

    init(art: Art, layout: Layout, farm: Farm, live: [String: LiveRecord], story: Story, in host: CALayer) {
        self.art = art
        self.layout = layout
        self.farm = farm
        self.live = live
        self.story = story
        valley = Valley(layout: layout)
        isNight = isNightHour(Int(hourNow()))
        quiet {
            world.anchorPoint = .zero
            world.bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
            world.position = .zero
            world.masksToBounds = true
            host.addSublayer(world)
            // A fixture (JEB_BENCH_FREEZE) holds world time still from the start, so a frame or a pass
            // never depends on how long the build took (the bench pauses the scene after it anyway).
            if env["JEB_BENCH_FREEZE"] == "1" {
                world.timeOffset = world.convertTime(CACurrentMediaTime(), from: nil)
                world.speed = 0
            }
            homeClock = FrameClock(frame0: 0, at: worldNow, period: 6 * tickSeconds, frozen: false)
            build()
            applyNow(farm: farm, live: live, arriving: false)
        }
        if animOn("band") { clock.after(40) { [weak self] in self?.actLoop() } }
    }

    // MARK: Time

    var worldNow: CFTimeInterval { world.convertTime(CACurrentMediaTime(), from: nil) }
    var now: Date { nowDate() }
    /// The world time of a wall-clock moment (ms since the epoch).
    func worldTime(ofWallMs ms: Double) -> CFTimeInterval { worldNow - (now.timeIntervalSince1970 - ms / 1000) }
    func snapTime(_ t: CFTimeInterval) -> CFTimeInterval { (t / tick).rounded(.down) * tick }
    func after(_ seconds: Double, _ block: @escaping () -> Void) { clock.after(seconds, block) }
    var wakes: Int { clock.fired }

    /// A refresh of everything that depends on the clock, `seconds` from now (one pending at a time, the soonest).
    private var refreshAt: CFTimeInterval?
    func refresh(after seconds: Double) {
        let at = worldNow + seconds
        if let r = refreshAt, r <= at + 0.02, r > worldNow { return }
        refreshAt = at
        clock.after(seconds, key: "refresh") { [weak self] in
            guard let self else { return }
            refreshAt = nil
            quiet { self.applyNow(farm: self.farm, live: self.live, arriving: true) }
        }
    }

    /// A calm animation: on the step grid, at the calm frame rate.
    func runCalm(_ a: CAAnimation, on layer: CALayer, key: String) {
        a.preferredFrameRateRange = calmRange
        if a.beginTime == 0 { a.beginTime = snapTime(worldNow) }
        layer.add(a, forKey: key)
    }

    /// A pass: smooth, at the full frame rate.
    func runPass(_ a: CAAnimation, on layer: CALayer, key: String) {
        a.preferredFrameRateRange = passRange
        passUntil = max(passUntil, Date().addingTimeInterval(min(a.duration * Double(max(a.repeatCount, 1)), 600)))
        layer.add(a, forKey: key)
    }

    var animatedLayers: Int {
        var n = 0
        func walk(_ l: CALayer) { if !(l.animationKeys() ?? []).isEmpty { n += 1 }; l.sublayers?.forEach(walk) }
        walk(world)
        return n
    }
    /// Jeb's and Blue's sprites in the scene: shown (not hidden, nor under a hidden layer) and in the tree at all.
    /// The scene has exactly one of each shown; applyNow logs any update that shows more.
    var castCount: (jeb: Int, blue: Int, jebAll: Int, blueAll: Int) {
        var c = (jeb: 0, blue: 0, jebAll: 0, blueAll: 0)
        func walk(_ l: CALayer, shown: Bool) {
            let shown = shown && !l.isHidden && l.opacity > 0
            if let n = l.name {
                if n.hasPrefix("jeb-") { c.jebAll += 1; if shown { c.jeb += 1 } }
                if n.hasPrefix("blue-") { c.blueAll += 1; if shown { c.blue += 1 } }
            }
            l.sublayers?.forEach { walk($0, shown: shown) }
        }
        walk(world, shown: true)
        return c
    }
    /// What the tree holds of places: the place roots (always one), and the strips of each kind (at most the one place's).
    var placeCount: (roots: Int, farm: Int, camp: Int, road: Int) {
        var c = (roots: 0, farm: 0, camp: 0, road: 0)
        func walk(_ l: CALayer) {
            if let n = l.name {
                if n.hasPrefix("place:") { c.roots += 1 }
                if n == "farm-strip" { c.farm += 1 }
                if n == "camp-strip" { c.camp += 1 }
                if n == "road-strip" { c.road += 1 }
            }
            l.sublayers?.forEach(walk)
        }
        walk(world)
        return c
    }

    func tearDown() { clock.stop() }

    // MARK: Running and paused

    func setRunning(_ run: Bool) {
        guard run != running else { return }
        running = run
        quiet {
            if run {
                let pausedAt = world.timeOffset
                world.speed = 1
                world.timeOffset = 0
                world.beginTime = 0
                world.beginTime = world.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
            } else {
                let now = world.convertTime(CACurrentMediaTime(), from: nil)
                world.speed = 0
                world.timeOffset = now
            }
        }
        clock.running = run
        // Resumed after a pause: the world clock stood still while the wall clock did not.
        if run { quiet { applyNow(farm: farm, live: live, arriving: true, reanchor: true) } }
    }

    // MARK: The store

    func apply(farm: Farm, live: [String: LiveRecord]) {
        let t0 = CACurrentMediaTime()
        quiet { applyNow(farm: farm, live: live, arriving: true) }
        if applyLog { log(String(format: "apply %.2f ms (%@)", (CACurrentMediaTime() - t0) * 1000, placeKind)) }
    }

    private func applyNow(farm: Farm, live: [String: LiveRecord], arriving: Bool, reanchor: Bool = false) {
        updates += 1
        if reanchor {
            // Back from a pause: the world's clock stood still while the wall clock ran on. Redraw from the records.
            homestead?.tearDown(); camp?.tearDown(); road?.tearDown()
        }
        self.farm = farm
        self.live = live
        let now = self.now
        let shown = live.filter { $0.value.isCurrent(now: now) && !$0.value.hidden }

        sessionCount = shown.count
        let view = story.view(now: now)
        placeKind = view.kindName
        queueLength = view.queue
        showPlace(view, arriving: arriving && !reanchor)
        switch view.kind {
        case .home: updateHome(view, shown: shown, now: now)
        case .camp: updateCamp(view, shown: shown, now: now)
        case .road: updateRoad(view, now: now)
        }
        // Clock-driven things the records do not rewrite: a record going stale.
        if let oldest = shown.values.map(\.at).min() {
            refresh(after: max(1, oldest / 1000 + liveTTL - now.timeIntervalSince1970 + 0.5))
        }
        let cast = castCount, places = placeCount
        if cast.jeb > 1 || cast.blue > 1 {
            log("cast: \(cast.jeb) Jeb and \(cast.blue) Blue shown (\(cast.jebAll)/\(cast.blueAll) in the tree), \(shown.count) records")
        }
        if places.roots != 1 { log("place: \(places.roots) place roots in the tree (farm \(places.farm), camp \(places.camp), road \(places.road))") }
    }

    // MARK: The one place

    /// Makes the tree hold only the place the story says: a new place's root is built whole (its land, its strip) and
    /// the old one is torn down and removed in the same transaction.
    private func showPlace(_ v: StoryView, arriving: Bool) {
        guard v.key != placeKey || placeRoot == nil else { return }
        let old = placeRoot
        homestead?.tearDown(); camp?.tearDown(); road?.tearDown()
        homestead = nil; camp = nil; road = nil
        homeRest()
        homeActing = false
        actingStable = nil; actingToken = nil
        old?.removeFromSuperlayer()
        placeKey = v.key
        let root = CALayer()
        root.name = "place:\(v.kindName)"
        root.anchorPoint = .zero
        root.bounds = world.bounds
        root.position = .zero
        root.zPosition = 4
        let ground = CALayer()
        ground.anchorPoint = .zero
        ground.position = .zero
        ground.zPosition = 0
        ground.magnificationFilter = .nearest
        ground.minificationFilter = .nearest
        root.addSublayer(ground)
        placeRoot = root
        land = ground
        landKey = ""
        let theme = v.kind == .camp ? v.token.flatMap { story.theme(forArea: (live[$0] ?? story.record(of: $0))?.area) } : nil
        paintLandNow(variant: v.kind == .home ? 0 : v.kind == .road ? 1 : 2 + Int(hashOf(v.token ?? "") % 4), theme: theme)
        let strip: CALayer
        switch v.kind {
        case .home:
            let h = Homestead(scene: self, art: art, width: valley.farmWidth, farm: farm)
            homestead = h
            strip = h.layer
            let g = BandLayout(width: valley.farmWidth, columns: farm.columns(now: now).count, farm: farm)
            if animOn("smoke") { smoke(at: CGPoint(x: CGFloat(valley.farmX + g.houseX + 36), y: CGFloat(valley.road + bandHeight - 2)), colour: "smoke", rate: 2.5, in: root) }
        case .camp:
            let c = Camp(token: v.token ?? "", width: valley.farmWidth, scene: self, art: art)
            camp = c
            strip = c.strip.layer
            c.strip.layer.addSublayer(screenLayer(width: valley.farmWidth))
        case .road:
            let r = Road(width: valley.farmWidth, scene: self, art: art)
            road = r
            strip = r.strip.layer
        }
        strip.position = CGPoint(x: valley.farmX, y: valley.road)
        strip.zPosition = 4
        strip.masksToBounds = false
        if v.kind == .camp {
            // Clip to the band, but leave the rows above it a taller holiday variant of Jeb grows into.
            let clip = CALayer()
            clip.anchorPoint = .zero
            clip.backgroundColor = CGColor(gray: 0, alpha: 1)
            clip.frame = CGRect(x: 0, y: 0, width: valley.farmWidth, height: bandHeight + Art.variantHeadroom)
            strip.mask = clip
        }
        root.addSublayer(strip)
        world.addSublayer(root)
        if arriving {
            // The new place comes up over a second.
            let a = CAKeyframeAnimation(keyPath: "opacity")
            a.values = [0, 0.34, 0.67, 1]
            a.keyTimes = [0, 0.34, 0.67, 1]
            a.calculationMode = .discrete
            a.duration = 0.9
            a.beginTime = snapTime(worldNow)
            a.fillMode = .backwards
            runCalm(a, on: root, key: "arrive")
        }
    }

    /// The homestead: farm-wide things from every session (their squares, the stitch, the after-rain), a lantern for each
    /// other one, and, from the lead's record (the session he acts out), its truck, happenings and visitors, with the one Jeb and Blue.
    private func updateHome(_ v: StoryView, shown: [String: LiveRecord], now: Date) {
        guard let homestead else { return }
        var m = FarmMoment()
        let ordered = shown.sorted { ($0.value.at, $0.key) < ($1.value.at, $1.key) }
        let acting = v.acting.flatMap { shown[$0] }
        m.lanterns = shown.count - (acting == nil ? 0 : 1)
        m.liveSquares = ordered.map { $0.value.live }
        for (_, r) in ordered {
            let ck = FrameClock(frame0: r.frame, at: worldTime(ofWallMs: r.at), period: r.framePeriod, frozen: r.still)
            if r.stitch && m.stitch == nil { m.stitch = ck }
            if r.rainbow { m.rainbow = true }
            if r.wet { m.wet = true }
            if r.star > m.star { m.star = r.star; m.starClock = ck }
        }
        if let r = acting, let token = v.acting {
            if actingToken != token { actingStable = nil; actingToken = token }
            let ck = bandClock(for: r, scene: self, stable: &actingStable)
            m.lead = r
            m.leadClock = ck
            if let e = r.event { m.events.append((e, ck, r.at)) }
            if let t = r.truck { m.trucks.append((t, ck, r.at, token)) }
            if r.fx.contains("puff") { m.puff = ck }
            if r.act == "chase" && r.pose == "none" && r.mood != "working" && r.truck == nil && !isNight { m.chasing = true }
        } else {
            actingStable = nil; actingToken = nil
        }
        m.storyLine = v.line
        homeActing = acting != nil
        homestead.update(farm: farm, moment: m, home: homeClock)
        // His line is up for 8 s: look again when it goes.
        if v.line == nil, let r = acting, r.isTalking(now: now) { refresh(after: max(0.05, (r.saidAt + 8000 - now.timeIntervalSince1970 * 1000) / 1000)) }
    }

    /// The camp of the session he is visiting; once it has ended, its last record, waving him off.
    private func updateCamp(_ v: StoryView, shown: [String: LiveRecord], now: Date) {
        guard let camp, let token = v.token else { return }
        var r = shown[token] ?? story.record(of: token) ?? LiveRecord(["v": 1, "at": now.timeIntervalSince1970 * 1000, "frame": 0])!
        if v.goodbye || shown[token] == nil { r = goodbyeRecord(r) }
        let theme = story.theme(forArea: r.area)
        paintLandNow(variant: landVariant, theme: theme) // the area may have been read since he arrived
        camp.update(farm: farm, record: r, line: v.line, theme: theme)
        if v.line == nil, r.isTalking(now: now) { refresh(after: max(0.05, (r.saidAt + 8000 - now.timeIntervalSince1970 * 1000) / 1000)) }
    }

    /// A session's last record as it is when he waves goodbye: the camp as it stood, nothing going on, Jeb waving.
    private func goodbyeRecord(_ last: LiveRecord) -> LiveRecord {
        var r = last
        r.pose = "web"; r.mood = "idle"; r.busy = false; r.gated = false; r.line = ""; r.dogRun = 0
        r.event = nil; r.truck = nil; r.visit = nil; r.weather = nil; r.fx = []; r.stitch = false
        return r
    }

    private func updateRoad(_ v: StoryView, now: Date) {
        guard let road, let trip = v.trip else { return }
        road.update(trip: trip, line: v.line, now: now, jebX: CampLayout(width: valley.farmWidth).jebX)
    }

    /// A clump of pines at a camp's left edge, in front of what drives in from there.
    private func screenLayer(width: Int) -> CALayer {
        var c = Pix(w: 9, h: bandHeight)
        let pine = art.colour(isNight ? "ridge_mid_night" : "pine"), dark = art.colour("green_dark")
        for (cx, top) in [(3, 22), (6, 27)] {
            for row in top..<(GROUND + 2) {
                let half = min(4, (row - top) / 3 + 1)
                for x in (cx - half)...(cx + half) where (row - top) % 3 != 2 || abs(x - cx) < half { c.dot(x, row, (x + row) % 4 == 0 ? dark : pine) }
            }
            c.rect(cx, GROUND + 2, 1, 6, art.colour("wood_dark"))
        }
        let l = CALayer()
        l.contents = c.image()
        l.magnificationFilter = .nearest
        l.anchorPoint = .zero
        l.bounds = CGRect(x: 0, y: 0, width: c.w, height: c.h)
        l.position = .zero
        l.zPosition = 30
        return l
    }

    // MARK: Building the sky and the land

    private func build() {
        let w = layout.width, h = layout.height
        for (layer, z) in [(sky, 0.0)] {
            layer.anchorPoint = .zero
            layer.position = .zero
            layer.zPosition = CGFloat(z)
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            world.addSublayer(layer)
        }
        sunOrMoon.zPosition = 2
        sunOrMoon.anchorPoint = .zero
        sunOrMoon.magnificationFilter = .nearest
        world.addSublayer(sunOrMoon)
        refreshSky()
        let horizon = landTop()

        if isNight && animOn("stars") {
            var stars = Canvas(w: w, h: h)
            for i in 0..<(w * h / 900) {
                stars.set(speckle(i, 1) * 9973 % w, horizon + speckle(i, 2) * 7919 % max(1, h - horizon), art.colour("night_star"))
            }
            place(image: stars.image(), x: 0, bottom: 0, z: 1)
            for i in 0..<8 {
                let star = CALayer()
                star.backgroundColor = art.cgColor("night_star")
                star.anchorPoint = .zero
                star.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
                star.position = CGPoint(x: speckle(i, 31) * w / 100, y: horizon + 10 + speckle(i, 32) * max(1, h - horizon - 20) / 100)
                star.zPosition = 1
                world.addSublayer(star)
                let wait = Double(2 + i % 4)
                runCalm(level("opacity", duration: wait + 1.6, step: 0.125) { t in
                    t < wait ? 1 : t < wait + 0.8 ? 1 - 0.8 * (t - wait) / 0.8 : 0.2 + 0.8 * (t - wait - 0.8) / 0.8
                }, on: star, key: "twinkle")
            }
        }

        // Clouds drifting a few pixels a second over the hills, each wrapping round.
        if animOn("clouds") {
            let cloudImage = art.image(isNight ? "cloud-dark" : "cloud")
            func drift(_ x0: CGFloat, _ y: CGFloat, _ vx: CGFloat, alpha: Float) {
                let node = place(image: cloudImage, x: x0, bottom: y, z: 3)
                node.opacity = alpha
                let cw = CGFloat(cloudImage.width), span = CGFloat(w) + cw
                let period = Double(span / vx)
                runCalm(path(duration: period) { t in
                    CGPoint(x: (x0 + cw + vx * CGFloat(t)).truncatingRemainder(dividingBy: span) - cw, y: y)
                }, on: node, key: "drift")
            }
            let skyRoom = max(10, h - layout.top - horizon - 12)
            for i in 0..<4 { drift(CGFloat(speckle(i, 9) * w / 100), CGFloat(horizon + 2 + (i * 37) % skyRoom), CGFloat(2 + i), alpha: isNight ? 0.5 : 1) }
        }

        // Leaves in autumn, snow in winter, over the whole valley, once Jeb has noticed the drift.
        let leaves = (9...11).contains(month), snow = month == 12 || month <= 2
        if animOn("leaves") && farm.unlocks.contains("drift") && !isNight && (leaves || snow) {
            let floor = CGFloat(valley.road + 8)
            for i in 0..<(snow ? 30 : 10) {
                let name = snow ? "drift-flake" : "drift-leaf-\(i % 3)"
                let top = CGFloat(h - layout.top)
                let vx = Double(1 + i % 3), vy = Double(4 + i % 4), phase = Double(i)
                let fall = Double(top - floor) / vy
                let start = floor + CGFloat(speckle(i, 42)) * (top - floor) / 100, first = Double(top - start) / vy
                let xs = (0..<3).map { k in CGFloat(speckle(i * 3 + k, 41) * w / 100) }
                let node = place(image: art.image(name), x: xs[0], bottom: start, z: 25)
                let period = 3 * fall
                runCalm(path(duration: period) { t in
                    let tt = (t + first).truncatingRemainder(dividingBy: period)
                    let k = min(2, Int(tt / fall)), u = tt - Double(k) * fall
                    return CGPoint(x: xs[k] + CGFloat(vx / 0.7 * (cos(phase) - cos(0.7 * u + phase))), y: top - CGFloat(vy * u))
                }, on: node, key: "fall")
            }
        }
    }

    /// Where the land ends and the open sky begins (scene y).
    private func landTop() -> Int {
        valley.road + bandHeight + 36
    }

    @discardableResult
    private func place(image: CGImage, x: CGFloat, bottom: CGFloat, z: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.contents = image
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.anchorPoint = .zero
        layer.bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        layer.position = CGPoint(x: x, y: bottom)
        layer.zPosition = z
        world.addSublayer(layer)
        return layer
    }

    /// The land as one picture: far hills in the sky's haze, the hillside, the stage's grass
    /// and road (a place's own, so `variant` tells them apart). Its colours follow
    /// the season (the band's ridges), the night, and a festival's tint.
    private func paintLand(low: UInt32, variant: Int, theme: AreaTheme?) -> Canvas {
        let w = layout.width, h = layout.height
        var c = Canvas(w: w, h: h)
        let fall = (9...11).contains(month), winter = month == 12 || month <= 2, spring = (3...5).contains(month)
        var far = art.colour(isNight ? "ridge_far_night" : "ridge_far"), mid = art.colour(isNight ? "ridge_mid_night" : "ridge_mid")
        // A camp with a read area: its palette leans the ridges and the hillside, its terrain speckles and lifts the hillside.
        let pal = theme.flatMap { AreaTheme.paletteColour[$0.area.palette] }.map(art.colour)
        let accent = theme.flatMap { AreaTheme.terrainColour[$0.area.terrain] }.map { mix(art.colour($0), low, 0.25) }
        let rise = theme.flatMap { AreaTheme.terrainRise[$0.area.terrain] } ?? 0
        if let pal { far = mix(far, pal, 0.14); mid = mix(mid, pal, 0.18) }
        let foliage = ["foliage_orange", "foliage_red", "foliage_gold"].map(art.colour)
        let haze = mix(far, low, 0.45)
        let road = valley.road, grassY = road + 8
        let top = landTop()
        let hour = hourNow()
        // The hillside stands back from the farm and the camps: the near ridge's colour
        // in a little of the sky's haze, with a light speckle of the season.
        // Each camp's ground is a little its own: the hillside leans toward another colour.
        let lean = pal ?? (variant >= 2 ? [art.colour("leaf"), art.colour("pine"), art.colour("stone"), art.colour("dirt")][(variant - 2) % 4] : nil)
        let base = mix(mid, low, isNight ? 0.2 : 0.38)
        let hill = lean.map { mix(base, $0, pal == nil ? 0.18 : 0.32) } ?? base, hillDark = mix(hill, mid, 0.55)
        func speck(_ x: Int, _ y: Int) -> UInt32 {
            let roll = speckle(x + variant * 17, y)
            if isNight { return roll < 6 ? hillDark : hill }
            if fall && roll < (month == 10 ? 7 : 4) { return mix(foliage[roll % 3], low, 0.25) }
            if spring && roll < 5 { return mix(art.colour("leaf"), low, 0.25) }
            if !winter && !fall && roll < 5 { return mix(art.colour("pine"), low, 0.25) }
            if winter && roll < 5 { return mix(art.colour("snowcap"), low, 0.2) }
            if let accent, roll >= 12 && roll < 22 { return accent }
            return roll < 12 ? hillDark : hill
        }
        for x in 0..<w {
            let d = Double(x)
            // The farthest hills, in the haze, then the far ridge.
            let hazeTop = top + 18 + Int(9 * sin(d / 53 + 0.7) + 5 * sin(d / 19 + 2.1) + 2 * sin(d / 7))
            for y in grassY..<min(h, hazeTop) { c.set(x, y, haze) }
            let farTop = top + 6 + Int(7 * sin(d / 37) + 5 * sin(d / 13 + 1.3) + 3 * sin(d / 71 + 0.4))
            for y in grassY..<min(h, farTop) { c.set(x, y, !isNight && y >= farTop - 2 && speckle(x, y) < 60 ? mix(far, word(255, 255, 255), 0.12) : far) }
            if winter && farTop > top + 8 { c.set(x, farTop - 1, art.colour("snowcap")) }
            // The hillside: a low rise just behind the stage, higher toward the sides of the valley,
            // kept under the far ridge's lowest crest so the ridges read whole (tools/parity.py "ridges").
            let edge = abs(d - Double(w) / 2) / (Double(w) / 2)
            let hillTop = road + bandHeight + 2 + rise + Int(5 * edge) + Int(2 * sin(d / 23 + 2) + sin(d / 9))
            for y in grassY..<hillTop { c.set(x, y, speck(x, y)) }
            // A few pine tips along the hill's crest.
            if speckle(x, 7) < 10 { c.set(x, hillTop, isNight ? mid : winter ? art.colour("snowcap") : art.colour("pine")) }
            if !isNight && hour >= 6 && hour < 9 && (x + x / 9) % 3 != 0 { c.set(x, grassY + 2, art.colour("fog")) }
        }
        // The stage: plain grass behind the Dock, then the band's road, the grass line and tufts.
        let grass = art.colour("grass"), dirt = art.colour("dirt"), dirtLight = art.colour("dirt_light"), dirtDark = art.colour("dirt_dark")
        let leaf = art.colour("leaf")
        let greenDark = art.colour("green_dark")
        for x in 0..<w {
            for y in 0..<road {
                let roll = speckle(x, y + 400)
                c.set(x, y, roll < 8 ? leaf : roll < 14 ? greenDark : grass)
            }
            for y in road..<(road + 8) {
                let roll = speckle(x, y + 200)
                c.set(x, y, roll < 9 ? dirtLight : roll < 15 ? dirtDark : dirt)
            }
            c.set(x, road + 5 + rut(x, 0), dirtDark)
            c.set(x, road + 1 + rut(x, 1), dirtDark)
            if speckle(x, 77) < 3 { c.set(x, road + speckle(x, 78) % 8, art.colour("pebble")) }
            c.set(x, road + 8, grass)
            if speckle(x, 5) < 8 { c.set(x, road + 9, grass); if speckle(x, 6) < 50 { c.set(x, road + 10, leaf) } }
        }
        if isNight { // moonlit: the grass and roads toward the night sky
            let night = word(18, 22, 44)
            c.px = c.px.map { $0 == 0 ? 0 : mix($0, night, 0.4) }
        }
        if let theme { paintWeather(&c, theme.area, from: road + 8, to: road + bandHeight + 10) }
        // A festival day: the land a quarter of the way toward its colour (pixel-scene.ts tintLayer).
        let tint = farm.festivalTint(now: now)
        if let rgb = Farm.tints[tint] {
            c.px = c.px.map { p in p == 0 ? 0 : word((Int(p & 255) * 3 + rgb.0) >> 2, (Int(p >> 8 & 255) * 3 + rgb.1) >> 2, (Int(p >> 16 & 255) * 3 + rgb.2) >> 2) }
        }
        return c
    }

    /// An area's weather over the hillside and its mood over the whole land, from the existing colours.
    private func paintWeather(_ c: inout Canvas, _ area: Area, from y0: Int, to y1: Int) {
        let fogC = art.colour("fog"), white = art.colour("white"), snow = art.colour("snowcap"), drop = art.colour("drop")
        for y in y0..<min(y1, c.h) {
            for x in 0..<c.w {
                let i = (c.h - 1 - y) * c.w + x
                let p = c.px[i]
                guard p != 0 else { continue }
                switch area.weather {
                case "fog": if (x + 2 * y) % 3 != 0 { c.px[i] = mix(p, fogC, 0.4) }
                case "hazy": c.px[i] = mix(p, fogC, 0.22)
                case "drizzle": if speckle(x, y + 900) < 7 { c.px[i] = mix(p, drop, 0.6) }
                case "snowy": if speckle(x, y + 700) < 12 { c.px[i] = snow }
                case "breeze": if (x / 3 + 2 * y) % 11 == 0 { c.px[i] = mix(p, white, 0.2) }
                default: break
                }
            }
        }
        if let (name, t) = AreaTheme.moodMix[area.mood] {
            let m = art.colour(name)
            c.px = c.px.map { $0 == 0 ? 0 : mix($0, m, t) }
        }
    }

    private func rut(_ x: Int, _ k: Int) -> Int {
        max(-1, min(1, Int((sin(Double(x) / 7 + Double(k) * 2.1) + 0.6 * sin(Double(x) / 3.3 + Double(k))).rounded())))
    }

    // MARK: Sky refresh (once a minute) and the sun or moon

    private var landTint = ""
    private var landVariant = 0
    private var landTheme: AreaTheme?
    /// Measuring only: whether the land is an area's, and how many of its sprites the camp stands.
    var areaThemed: Bool { landTheme != nil }
    /// What the banner takes from an area camp's look (BannerArt.swift); nil anywhere else.
    var areaLook: AreaLook? { landTheme.map { AreaLook(palette: $0.area.palette, weather: $0.area.weather, mood: $0.area.mood) } }
    var areaPlaced: Int { camp?.areaPlaced ?? 0 }

    /// Paints the current place's land (its own variant) if the sky's colours, the tint or the variant changed.
    private func paintLandNow(variant: Int, theme: AreaTheme? = nil) {
        let (_, low) = skyColours(hour: hourNow())
        let key = "\(low)|\(farm.festivalTint(now: now))|\(variant)" + (theme.map { "|" + $0.tag } ?? "")
        landVariant = variant
        landTheme = theme
        guard let land, key != landKey else { return }
        landKey = key
        let picture = paintLand(low: low, variant: variant, theme: theme)
        land.contents = picture.image()
        land.bounds = CGRect(x: 0, y: 0, width: picture.w, height: picture.h)
    }
    func refreshSky() { quiet { refreshSkyNow() } }

    private func refreshSkyNow() {
        let (top, low) = skyColours(hour: hourNow())
        let h = layout.height, g = valley.road + 8
        let tint = farm.festivalTint(now: now)
        if skyKey.map({ $0 != (top, low) }) ?? true || tint != landTint {
            skyKey = (top, low)
            landTint = tint
            var c = Canvas(w: 1, h: h)
            for y in 0..<h { c.set(0, y, mix(low, top, min(1, Double(max(0, (y - g) / 6 * 6)) / Double(max(1, h - g))))) }
            sky.contents = c.image()
            sky.bounds = CGRect(x: 0, y: 0, width: layout.width, height: h)
            paintLandNow(variant: landVariant, theme: landTheme)
        }
        let hour = hourNow()
        let span = CGFloat(layout.width - layout.left - layout.right - 30)
        var frac: CGFloat
        let image: CGImage
        if isNight {
            image = art.image("moon", moonPhase(now))
            frac = CGFloat(((hour < 21 ? hour + 24 : hour) - 21) / 9)
        } else {
            image = art.image("sun")
            frac = CGFloat((hour - 6) / 15)
        }
        frac = max(0, min(1, frac))
        // Up from behind the far hills and across, never under the menu bar.
        let high = CGFloat(layout.height - layout.top - 14), horizon = CGFloat(landTop())
        let spot = CGPoint(x: (CGFloat(layout.left + 15) + span * frac).rounded(), y: (horizon + (high - horizon) * sin(.pi * frac)).rounded())
        if sunOrMoon.contents.map({ ($0 as! CGImage) !== image }) ?? true { sunOrMoon.contents = image }
        sunOrMoon.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
        if sunOrMoon.position != spot { sunOrMoon.position = spot }
    }

    /// The minute: the sky, and whatever the clock decides on the farm (looks, the stack's whiskey, the calendar).
    func minute() {
        refreshSky()
        quiet { applyNow(farm: farm, live: live, arriving: true) }
    }

    // MARK: Home: Jeb and Blue while no session is out at camp (the desktop's own idle; nothing on the farm changes)

    func homeLayers(in strip: Strip, jebX: Int, blueX: Int, chair: Bool) -> ([CALayer], [CALayer]) {
        quiet {
            for (l, name, x) in [(homeJeb, "jeb-idle", jebX), (homeBlue, "blue-wag", blueX)] {
                let image = art.image(name)
                l.name = name
                l.contents = image
                l.magnificationFilter = .nearest
                l.anchorPoint = .zero
                l.bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                l.position = CGPoint(x: CGFloat(x), y: strip.ly(FOOT - image.height, image.height))
                l.zPosition = 10
            }
        }
        homeStrip = strip
        homeAt = (jebX, blueX, chair)
        homeIdle(attach: true)
        return ([homeJeb] + homeExtras, [homeBlue])
    }
    /// A record has the one Jeb (or the place is not the homestead): the calm home Jeb and Blue are put away.
    func homeRest() {
        homeStrip = nil
        homeIdle(attach: false)
    }
    private weak var homeStrip: Strip?
    private var homeAt = (0, 0, false)
    private var homeChair: CALayer?

    private func homeIdle(attach: Bool? = nil) {
        let attach = attach ?? (homeJeb.superlayer != nil && !homeActing)
        quiet {
            homeJeb.removeAllAnimations()
            homeBlue.removeAllAnimations()
            homeExtras.forEach { $0.removeFromSuperlayer() }
            homeExtras = []
            homeChair?.removeFromSuperlayer()
            homeChair = nil
            guard let strip = homeStrip, attach else { return }
            if isNight {
                homeJeb.contents = art.image("jeb-sleep")
                homeBlue.contents = art.image("blue-nap")
                for l in [strip.flipbook(clock: homeClock, count: 2, z: 10.5) { f in ("zz", f, self.homeAt.0 + 19, 0) },
                          strip.flipbook(clock: homeClock, count: 2, z: 10.5) { f in ("zz", f, self.homeAt.1 + 10, FOOT - 13 - 9) }].compactMap({ $0 }) {
                    strip.layer.addSublayer(l); homeExtras.append(l)
                }
                return
            }
            homeBlue.contents = art.image("blue-wag")
            homeJeb.contents = art.image("jeb-idle")
            guard animOn("band") else { return }
            // Eyes open 2.7 s, a 0.2 s blink (the art's own frame timings).
            let f = art.images("jeb-idle")
            let blink = CAKeyframeAnimation(keyPath: "contents")
            blink.values = [f[0], f[min(3, f.count - 1)]]
            blink.keyTimes = [0, NSNumber(value: 2.7 / 2.9), 1]
            blink.calculationMode = .discrete
            blink.duration = 2.9
            blink.repeatCount = .infinity
            runCalm(blink, on: homeJeb, key: "act")
        }
    }

    private func actLoop() { nextAct(); clock.after(40) { [weak self] in self?.actLoop() } }

    /// Now and then at home, the banjo or a sip (cosmetic: no jar is taken).
    private func nextAct() {
        guard !isNight, !homeActing, homeStrip != nil, homeJeb.superlayer != nil else { return }
        act = (act + 1) % 3
        quiet {
            switch act {
            case 1:
                runCalm(frames("jeb-banjo", every: 0.4), on: homeJeb, key: "act")
                if let strip = homeStrip {
                    for l in [strip.flipbook(clock: FrameClock(frame0: 0, at: worldNow, period: 0.4, frozen: false), count: 2, z: 10.5) { f in ("note", 0, self.homeAt.0 - 6 - (f % 2) * 3, 6) },
                              strip.flipbook(clock: FrameClock(frame0: 0, at: worldNow, period: 0.4, frozen: false), count: 2, z: 10.5) { f in ("note", 0, self.homeAt.0 - 12 + (f % 2) * 2, 1) }].compactMap({ $0 }) {
                        strip.layer.addSublayer(l); homeExtras.append(l)
                    }
                }
                clock.after(10, key: "actEnd") { [weak self] in self?.homeIdle() }
            case 2:
                runCalm(frames("jeb-sip", every: 1.2), on: homeJeb, key: "act")
                if homeAt.2, let strip = homeStrip {
                    let chair = strip.standing("prop-chair", x: homeAt.0 + 5, bottom: FOOT, z: 9)
                    strip.layer.addSublayer(chair)
                    homeChair = chair
                }
                clock.after(12, key: "actEnd") { [weak self] in self?.act = 0; self?.homeIdle() }
            default:
                homeIdle()
            }
        }
    }

    // MARK: Calm motion helpers (the desktop's own ambience)

    private func frames(_ name: String, every seconds: Double) -> CAKeyframeAnimation {
        let images = art.images(name)
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = images
        a.keyTimes = (0...images.count).map { NSNumber(value: Double($0) / Double(images.count)) }
        a.calculationMode = .discrete
        a.duration = snap(seconds) * Double(images.count)
        a.repeatCount = .infinity
        return a
    }

    private func snap(_ t: Double) -> Double { max(tick, (t / tick).rounded() * tick) }

    /// A calm path, read on each tick of the step clock and rounded to the device pixel, as discrete keyframes.
    private func path(duration: Double, _ p: (Double) -> CGPoint) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: "position")
        var values: [NSValue] = [], times: [NSNumber] = []
        let q = 1 / CGFloat(layout.scale)
        let d = snap(duration)
        let n = Int((d / tick).rounded())
        var last: CGPoint?
        for i in 0..<n {
            let t = Double(i) * tick, v = p(t)
            let s = CGPoint(x: (v.x / q).rounded(.down) * q, y: (v.y / q).rounded(.down) * q)
            if s != last { values.append(NSValue(point: s)); times.append(NSNumber(value: t / d)); last = s }
        }
        times.append(1)
        a.calculationMode = .discrete
        a.values = values
        a.keyTimes = times
        a.duration = d
        a.repeatCount = .infinity
        return a
    }

    private func level(_ keyPath: String, duration: Double, step: Double, _ f: (Double) -> Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        var values: [NSNumber] = [], times: [NSNumber] = []
        let d = snap(duration)
        var last: Double?
        for i in 0..<Int((d / tick).rounded()) {
            let t = Double(i) * tick, v = (f(t) / step).rounded() * step
            if v != last { values.append(NSNumber(value: v)); times.append(NSNumber(value: t / d)); last = v }
        }
        times.append(1)
        a.calculationMode = .discrete
        a.values = values
        a.keyTimes = times
        a.duration = d
        a.repeatCount = .infinity
        return a
    }

    /// Smoke or steam: puffs rising from `point`, `rate` a second, each living 5 s,
    /// growing and fading as they drift right (a fixed set of looping puffs).
    private func smoke(at point: CGPoint, colour: String, rate: Double, in parent: CALayer) {
        let life = 5.0, count = max(1, Int((rate * life).rounded()))
        let ink = art.cgColor(colour)
        for i in 0..<count {
            let puff = CALayer()
            puff.backgroundColor = ink
            puff.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            puff.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            puff.position = point
            puff.zPosition = 9
            puff.opacity = 0
            parent.addSublayer(puff)
            let speed = 4 + Double(speckle(i, 61)) / 50, angle = .pi / 2 + (Double(speckle(i, 62)) / 100 - 0.5) * 0.4
            let vx = speed * cos(angle), vy = speed * sin(angle)
            let move = path(duration: life) { t in CGPoint(x: point.x + CGFloat(vx * t + 0.6 * t * t), y: point.y + CGFloat(vy * t)) }
            let size = level("transform.scale", duration: life, step: 0.25) { t in 2 + 0.35 * t }
            let alpha = level("opacity", duration: life, step: 0.125) { t in 0.85 - 0.17 * t }
            let offset = (life * Double(i) / Double(count) / tick).rounded() * tick
            for (key, anim) in [("rise", move), ("grow", size), ("fade", alpha)] {
                anim.timeOffset = offset
                runCalm(anim, on: puff, key: key)
            }
        }
    }
}
