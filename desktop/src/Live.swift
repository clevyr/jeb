// One running session's live record (the mod's hooks/live.ts), read strictly:
// every field is checked against its fixed set or range, and a record that does
// not read as version 1 is dropped. A field left out is at its default. The only
// free text is Jeb's line, which is display-only: control characters out, cut to
// 120 characters, and drawn only in the band's own 3x5 font (a character without
// a glyph draws as a space). The cows are numbers; everything else is an enum.
//
// `at` (ms) is when the record was written and `frame` the band's animation
// frame then. Between writes the desktop moves things on from that anchor at the
// band's own rates (a 500 ms tick; see `ticks(at:)`), so a truck or a visitor rolls
// smoothly with no record per step.

import Foundation

let liveTTL = 600.0 // s: a record older than this is not shown
let tickSeconds = 0.5

struct LiveTruck: Equatable { let t: Int, load: String, sputter: Int, dog: Bool }
struct LiveVisit: Equatable { let kind: String, x: Int, facing: String, phase: String }
struct LiveEvent: Equatable { let id: String, t: Int, dur: Int, v: Int; let sprites: [DropSprite]; let custom: [DropArt] }
struct LiveHand: Equatable { let plot: String, look: Int }

struct LiveRecord: Equatable {
    static let poses: Set<String> = ["none", "read", "edit", "write", "still", "web", "agent", "sweep", "mcp", "think", "draft", "hoe"]
    static let moods: Set<String> = ["idle", "working", "pleased", "spooked"]
    static let acts: Set<String> = ["banjo", "sip", "nap", "chase", "smoke"]
    static let loads: Set<String> = ["box", "jar", "bale", "apple", "corn", "butter", "twist", "whiskey"]
    static let visitKinds: Set<String> = ["store", "mill", "tripper", "opal", "mail", "tractor"]
    static let eventIds: Set<String> = ["revenuer", "neighbor", "bear", "whistlepig", "mothman", "bugs", "bells", "storm", "fog", "turkeys",
                                        "parachute", "track", "hornworm", "applebutter", "bees", "sorghum", "ramps", "sang", "quilting", "drop"]
    static let fxNames: Set<String> = ["wag", "wink", "puff", "sip"]
    static let plots: Set<String> = ["tobacco", "corn", "apples"]
    static let buildings: Set<String> = ["app", "hot", "database"]
    static let squares: Set<String> = ["B", "R", "G", "P", "Y", "N"]
    static let talks: Set<String> = ["chatty", "ambient", "silent"]

    var at: Double      // ms
    var frame: Int
    var pose = "none", mood = "idle", act = "banjo"
    var line = "", saidAt = 0.0
    var dim = false, busy = false, still = false, gated = false, stitch = false
    var rainbow = false, wet = false, hidden = false
    var dogRun = 0, mates = 0, star = 0, moreCows = 0
    var truck: LiveTruck?
    var visit: LiveVisit?
    var event: LiveEvent?
    var fx: Set<String> = []
    var weather: (kind: String, plot: String)?
    var building = ""
    var hands: [LiveHand] = []
    var more: [String: Int] = [:]
    var cows: [Int] = []
    var live = "N"
    var talk = "ambient"
    var dropsOff = false    // the plugin's own creative-drops option is off (the desktop menu then shows its item disabled)
    var area: String?   // the project's area key (8 lowercase hex), when the session works in one

    init?(_ d: [String: Any]) {
        func num(_ key: String) -> Double? { (d[key] as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } }
        func int(_ key: String, _ range: ClosedRange<Int>, in dict: [String: Any]? = nil) -> Int? {
            guard let n = ((dict ?? d)[key] as? NSNumber)?.doubleValue, n.isFinite, n == n.rounded() else { return nil }
            return range.contains(Int(n)) ? Int(n) : nil
        }
        func pick(_ key: String, _ set: Set<String>, in dict: [String: Any]? = nil) -> String? {
            guard let s = (dict ?? d)[key] as? String, set.contains(s) else { return nil }
            return s
        }
        func flag(_ key: String) -> Bool { (d[key] as? Bool) == true }
        guard (d["v"] as? NSNumber)?.intValue == 1, let at = num("at"), at > 0, let frame = int("frame", 0...5039) else { return nil }
        self.at = at
        self.frame = frame
        pose = pick("pose", Self.poses) ?? "none"
        mood = pick("mood", Self.moods) ?? "idle"
        act = pick("act", Self.acts) ?? "banjo"
        if let said = d["line"] as? String, let when = num("saidAt") {
            line = cleanLine(said)
            saidAt = when
        }
        dim = flag("dim"); busy = flag("busy"); still = flag("still"); gated = flag("gated"); stitch = flag("stitch")
        rainbow = flag("rainbow"); wet = flag("wet"); hidden = flag("hidden")
        dogRun = int("dogRun", 0...64) ?? 0
        mates = int("mates", 0...2) ?? 0
        star = int("star", 0...10) ?? 0
        moreCows = int("moreCows", 0...999) ?? 0
        if let t = d["truck"] as? [String: Any], let tt = int("t", 0...15, in: t), let load = pick("load", Self.loads, in: t) {
            truck = LiveTruck(t: tt, load: load, sputter: int("sputter", 0...8, in: t) ?? 0, dog: (t["dog"] as? Bool) == true)
        }
        if let v = d["visit"] as? [String: Any], let kind = pick("kind", Self.visitKinds, in: v), let x = int("x", 0...60, in: v),
           let facing = pick("facing", ["in", "out"], in: v), let phase = pick("phase", ["arrive", "deal", "leave"], in: v) {
            visit = LiveVisit(kind: kind, x: x, facing: facing, phase: phase)
        }
        if let e = d["event"] as? [String: Any], let id = pick("id", Self.eventIds, in: e), let dur = int("dur", 1...600, in: e),
           let t = int("t", 0...600, in: e), let v = int("v", 0...1_000_000, in: e) {
            var sprites: [DropSprite] = [], custom: [DropArt] = []
            if id == "drop", let art = e["art"] as? [String: Any] {
                sprites = ((art["sprites"] as? [Any]) ?? []).prefix(3).compactMap(DropSprite.init)
                custom = ((art["custom"] as? [Any]) ?? []).prefix(2).compactMap(DropArt.init)
            }
            event = LiveEvent(id: id, t: min(t, dur), dur: dur, v: v, sprites: sprites, custom: custom)
        }
        fx = Set(((d["fx"] as? [Any]) ?? []).prefix(4).compactMap { $0 as? String }.filter(Self.fxNames.contains))
        if let w = d["weather"] as? [String: Any], let kind = pick("kind", ["rain", "dry"], in: w), let plot = pick("plot", Self.plots.union(["all"]), in: w) {
            weather = (kind, plot)
        }
        building = pick("building", Self.buildings) ?? ""
        hands = ((d["hands"] as? [Any]) ?? []).prefix(3).compactMap { item in
            guard let h = item as? [String: Any], let plot = pick("plot", Self.plots, in: h), let look = int("look", 0...5, in: h) else { return nil }
            return LiveHand(plot: plot, look: look)
        }
        if let m = d["more"] as? [String: Any] {
            for crop in Self.plots { if let n = int(crop, 1...9999, in: m) { more[crop] = n } }
        }
        cows = ((d["cows"] as? [Any]) ?? []).prefix(3).compactMap { item in
            guard let n = (item as? NSNumber)?.doubleValue, n.isFinite, n == n.rounded(), n >= 0, n <= 99_999 else { return nil }
            return Int(n)
        }
        live = pick("live", Self.squares) ?? "N"
        talk = pick("talk", Self.talks) ?? "ambient"
        dropsOff = (d["drops"] as? String) == "off"
        if let key = d["area"] as? String, isAreaKey(key) { area = key }
    }

    /// Fresh enough to show: written in the last ten minutes (and not from the future).
    func isCurrent(now: Date) -> Bool {
        let age = now.timeIntervalSince1970 - at / 1000
        return age < liveTTL && age > -liveTTL
    }

    /// The bubble is up for 8 s after the line was said.
    func isTalking(now: Date) -> Bool { !line.isEmpty && now.timeIntervalSince1970 * 1000 - saidAt < 8000 }

    // The band's frame clock (register.tsx snapshot): every tick while anything
    // moves, every second for the crawling tractor alone, else every 3 s.
    var restingEvent: Bool {
        guard let e = event else { return false }
        return restOf(id: e.id, t: e.t, dur: e.dur) != nil
    }
    var isCrawl: Bool { visit?.kind == "tractor" }
    var isMoving: Bool {
        truck != nil || dogRun > 0 || (event != nil && !restingEvent) || !fx.isEmpty || gated || weather != nil || stitch || star > 0
            || (visit != nil && !isCrawl && visit?.phase != "deal")
    }
    /// Seconds per band frame.
    var framePeriod: Double { isMoving ? tickSeconds : isCrawl ? 2 * tickSeconds : 6 * tickSeconds }

    static func == (a: LiveRecord, b: LiveRecord) -> Bool {
        a.at == b.at && a.frame == b.frame && a.pose == b.pose && a.mood == b.mood && a.act == b.act && a.line == b.line && a.saidAt == b.saidAt
            && a.dim == b.dim && a.busy == b.busy && a.still == b.still && a.gated == b.gated && a.stitch == b.stitch && a.rainbow == b.rainbow
            && a.wet == b.wet && a.hidden == b.hidden && a.dogRun == b.dogRun && a.mates == b.mates && a.star == b.star && a.moreCows == b.moreCows
            && a.truck == b.truck && a.visit == b.visit && a.event == b.event && a.fx == b.fx && a.weather?.kind == b.weather?.kind
            && a.weather?.plot == b.weather?.plot && a.building == b.building && a.hands == b.hands && a.more == b.more && a.cows == b.cows
            && a.live == b.live && a.talk == b.talk && a.area == b.area && a.dropsOff == b.dropsOff
    }

    /// Everything that changes what the camp draws, apart from the anchors (at, frame) that move with every write.
    func sameShow(_ b: LiveRecord) -> Bool {
        var c = b
        c.at = at
        c.frame = frame
        return self == c
    }
}

/// Jeb's line as display-only text: control characters to spaces, trimmed, 120 characters at most.
func cleanLine(_ s: String) -> String {
    let mapped = String(s.unicodeScalars.prefix(480).map { $0.value < 0x20 || $0.value == 0x7F ? " " : Character($0) })
    return String(mapped.trimmingCharacters(in: .whitespaces).prefix(120))
}

// ---- happenings: their rest windows (events.ts REST) ----

let eventRest: [String: [(Double, Double)]] = [
    "revenuer": [], "neighbor": [(0.5, 0.8)], "bear": [(0, 1)], "whistlepig": [(0, 1)], "mothman": [(0, 1)], "bugs": [(0, 1)],
    "bells": [(0, 1)], "storm": [], "fog": [(0, 1)], "turkeys": [], "parachute": [], "track": [(0, 1)], "hornworm": [(0, 1)],
    "applebutter": [(0, 1)], "bees": [(0, 1)], "sorghum": [(0, 1)], "ramps": [(0, 1)], "sang": [(0, 1)], "quilting": [(0, 1)], "drop": [(0, 1)],
]

/// The tick a happening's standing stretch began, or nil while it moves.
func restOf(id: String, t: Int, dur: Int) -> Int? {
    let p = Double(t) / Double(dur)
    guard let w = (eventRest[id] ?? []).first(where: { p >= $0.0 && p < $0.1 }) else { return nil }
    return Int((w.0 * Double(dur)).rounded(.up))
}

/// Mothman's eyes are hidden one sub-frame in eight after the opening (events.ts isMothHidden).
func isMothHidden(t: Int, dur: Int, v: Int) -> Bool {
    Double(t) / Double(dur) >= 0.2 && (v * 31 + (t / 6) * 17) % 8 == 0
}

// ---- visits: how they move (visits.ts VISIT_SPECS) ----

let visitSpecs: [String: (step: Int, reach: Int, every: Int)] = [
    "store": (2, 32, 1), "mill": (2, 32, 1), "tripper": (2, 32, 1), "mail": (2, 32, 1), "opal": (1, 20, 1), "tractor": (1, 60, 2),
]

/// Where a visit is between `from` and `stop` for progress `x` along its reach (visitAt).
func visitAt(kind: String, x: Double, from: Double, stop: Double) -> Double {
    from + (stop - from) * x / Double(visitSpecs[kind]?.reach ?? 32)
}

// ---- the truck (pixel-scene.ts truckPx) ----

let truckTicks = 16
let truckW = 42
func truckPx(_ t: Double, x0: Double) -> Double {
    let half = Double(truckTicks / 2), reach = x0 + Double(truckW)
    return t < half ? x0 - reach * t / half : -Double(truckW) + reach * (t - half) / half
}
