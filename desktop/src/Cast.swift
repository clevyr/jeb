// The one Jeb and his Blue, drawn from a live record by the band's own rules
// (pixel-scene.ts jebSpriteFor, drawJebAndBlue, drawBubble) at a strip's jebX and
// blueX. The scene shows exactly one pair, at the one place on screen, acting out
// that place's record (the visited session's, or at home the lead session's).
// Also the band-clock anchoring a record gives, and the bang that goes over Blue
// at the bear and a track.

import AppKit
import QuartzCore

let POSE_SPRITES = ["read": "jeb-book", "draft": "jeb-book", "edit": "jeb-hold", "write": "jeb-hold", "mcp": "jeb-hold", "web": "jeb-wave",
                    "agent": "jeb-wave", "sweep": "jeb-broom", "think": "jeb-think", "still": "jeb-stir", "hoe": "jeb-hoe"]
let EVENT_JEB = ["revenuer": "jeb-salute", "neighbor": "jeb-wave", "hornworm": "jeb-spooked", "applebutter": "jeb-stir", "bees": "jeb-wave",
                 "sorghum": "jeb-stir", "ramps": "jeb-hoe", "sang": "jeb-hoe", "quilting": "jeb-hold"]

/// pixel-scene.ts jebSpriteFor.
func jebSpriteFor(_ r: LiveRecord, night: Bool) -> String {
    if r.gated { return "jeb-hold" }
    if r.fx.contains("sip") { return "jeb-sip" }
    if let posed = POSE_SPRITES[r.pose] { return posed }
    if r.visit?.phase == "deal" { return "jeb-wave" }
    if let e = r.event, let s = EVENT_JEB[e.id] { return s }
    if r.mood == "spooked" { return "jeb-spooked" }
    if r.mood == "pleased" { return "jeb-happy" }
    if r.fx.contains("wink") { return "jeb-wink" }
    if r.mood == "working" { return "jeb-hold" }
    if night { return "jeb-sleep" }
    switch r.act {
    case "banjo": return "jeb-banjo"
    case "sip": return "jeb-sip"
    case "nap": return "jeb-sleep"
    default: return "jeb-idle"
    }
}

// MARK: The lead session

/// How much newer (ms) another record must be to take the lead from an idle one.
let leadSwitchMs = 2000.0

/// The session whose record the one Jeb acts out at home. Busy records (or a tool pose) rank first, then the latest
/// `at`, then the larger token. The current lead stays while it is busy or inside 8 s of its line (isTalking); after
/// that another takes over only if it is busier, or its `at` is newer by 2 s.
func pickLead(_ shown: [String: LiveRecord], current: String?, now: Date) -> String? {
    func active(_ r: LiveRecord) -> Bool { r.busy || r.pose != "none" }
    func ranks(_ a: (String, LiveRecord), over b: (String, LiveRecord)) -> Bool {
        (active(a.1) ? 1 : 0, a.1.at, a.0) > (active(b.1) ? 1 : 0, b.1.at, b.0)
    }
    guard var best = shown.first.map({ ($0.key, $0.value) }) else { return nil }
    for e in shown where ranks((e.key, e.value), over: best) { best = (e.key, e.value) }
    guard let current, let cur = shown[current] else { return best.0 }
    if cur.busy || cur.isTalking(now: now) { return current }
    if best.0 == current { return current }
    return (active(best.1) && !active(cur)) || best.1.at >= cur.at + leadSwitchMs ? best.0 : current
}

/// A record's band clock, kept (in `stable`) while a new record agrees with it so the parts built on it stay put.
func bandClock(for r: LiveRecord, scene: FarmScene, stable: inout FrameClock?) -> FrameClock {
    let fresh = FrameClock(frame0: r.frame, at: scene.worldTime(ofWallMs: r.at), period: r.framePeriod, frozen: r.still)
    if let old = stable, old.period == fresh.period, old.frozen == fresh.frozen, old.frozen || abs(old.frame(scene.worldNow) - fresh.frame(scene.worldNow)) <= 1 {
        return old
    }
    stable = fresh
    return fresh
}

extension LiveRecord {
    /// The bubble is up: while he is talking, but not on the truck's way home.
    func showsBubble(now: Date) -> Bool { isTalking(now: now) && !(truck.map { $0.t >= truckTicks / 2 } ?? false) && !hidden }
    /// The happening's tick now, moved on from the record while it moves.
    func eventTick(_ ev: LiveEvent, nowMs: Double) -> Double {
        restOf(id: ev.id, t: ev.t, dur: ev.dur) != nil ? Double(ev.t) : min(Double(ev.dur), Double(ev.t) + (nowMs - at) / 500)
    }
}

/// The bang over Blue at the bear and at a track, `top` the top of what he is; `p` the happening's progress.
func bangLayers(strip: Strip, event ev: LiveEvent, p: Double, x: Int, top: Int, clock: FrameClock) -> [CALayer] {
    switch ev.id {
    case "bear": return [strip.flipbook(clock: clock, count: 2, z: 10.6, { f in f % 2 == 0 ? ("bang", 0, x + 8, top - 8) : nil })].compactMap { $0 }
    case "track": return p < 0.7 ? [strip.sprite("bang", x: x + 8, y: top - 8, z: 10.6)] : []
    default: return []
    }
}

// MARK: Jeb and Blue

final class JebBlue {
    let strip: Strip
    let art: Art
    let jebX: Int, blueX: Int
    unowned let scene: FarmScene
    private var lastBlueX: Int?, lastPupX: Int?

    init(strip: Strip, art: Art, scene: FarmScene, jebX: Int, blueX: Int) {
        self.strip = strip
        self.art = art
        self.scene = scene
        self.jebX = jebX
        self.blueX = blueX
    }

    // MARK: Jeb (drawJebAndBlue, first half)

    func jebLayers(_ r: LiveRecord, night: Bool, nap: Bool, hat: Bool, chair: Bool, clock: FrameClock) -> [CALayer] {
        let away = r.truck != nil
        let isNap = nap && !away && r.pose == "none" && r.mood == "idle" && !r.fx.contains("sip") && r.event == nil && r.visit?.phase != "deal"
        let sprite = isNap ? "jeb-sleep" : jebSpriteFor(r, night: night)
        let sitting = sprite == "jeb-sip" || isNap
        var out: [CALayer] = []
        func add(_ l: CALayer?) { if let l { out.append(l) } }
        if chair && (sitting || away) { add(strip.standing("prop-chair", x: jebX + 5, bottom: FOOT, z: 9)) }
        guard !away else { return out }
        add(strip.flipbook(clock: clock, count: art.frameCount(sprite), z: 10) { f in (sprite, f, self.jebX, FOOT - self.art.height(sprite)) })
        if hat { add(strip.sprite("hat-feather", x: jebX + 12, y: 0, z: 10.5)) }
        if sprite == "jeb-banjo" {
            add(strip.flipbook(clock: clock, count: 2, z: 10.5) { f in ("note", 0, self.jebX - 6 - (f % 2) * 3, 6) })
            add(strip.flipbook(clock: clock, count: 2, z: 10.5) { f in ("note", 0, self.jebX - 12 + (f % 2) * 2, 1) })
        }
        if sprite == "jeb-sleep" { add(strip.flipbook(clock: clock, count: 2, z: 10.5) { f in ("zz", f, self.jebX + 19, 0) }) }
        if sprite == "jeb-spooked" { add(strip.sprite("sweat", x: jebX + 20, y: 8, z: 10.5)) }
        // A settings hook's gate: he holds it up in front of him.
        if r.gated { add(strip.standing("prop-gate", x: jebX + 3, bottom: BOTTOM, z: 12)) }
        return out
    }

    // MARK: Blue (drawJebAndBlue, second half)

    /// Where Blue is now (for the bangs over him and the pup behind him), or nil when he rides in the truck.
    func blueSpot(_ r: LiveRecord, night: Bool, f: Int) -> (x: Int, bottom: Int)? {
        if r.truck?.dog == true { return nil }
        let away = r.truck != nil
        let idleDog = r.pose == "none" && r.mood != "working" && !away
        if r.dogRun > 0 { return (max(0, blueX - r.dogRun * 4), BOTTOM) }
        if idleDog && r.act == "chase" && !night { return (blueX - chaseOffset(f) * 4, BOTTOM) }
        return (blueX, FOOT)
    }

    func blueLayers(_ r: LiveRecord, night: Bool, clock: FrameClock) -> [CALayer] {
        var out = blueBody(r, night: night, clock: clock)
        // The bear's or a track's bang over him, while the truck is not away.
        if let ev = r.event, r.truck == nil, let spot = blueSpot(r, night: night, f: clock.frame(scene.worldNow)) {
            let p = r.eventTick(ev, nowMs: scene.now.timeIntervalSince1970 * 1000) / Double(ev.dur)
            out.append(contentsOf: bangLayers(strip: strip, event: ev, p: p, x: spot.x, top: spot.bottom - 13, clock: clock))
        }
        return out
    }

    private func blueBody(_ r: LiveRecord, night: Bool, clock: FrameClock) -> [CALayer] {
        if r.truck?.dog == true { return [] }
        let away = r.truck != nil
        let idleDog = r.pose == "none" && r.mood != "working" && !away
        let home = blueX
        var out: [CALayer] = []
        func add(_ l: CALayer?) { if let l { out.append(l) } }
        let wag = r.fx.contains("wag")
        if r.dogRun > 0 {
            // Out on his errand: 4 cells (16 px) a tick, out to 36 and back; moved on from the record.
            // Each record says where he is; he runs there from where he was over a tick.
            let to = Double(max(0, home - r.dogRun * 4)), from = Double(lastBlueX ?? Int(to))
            if let l = strip.flipbook(clock: clock, count: 2, z: 10, { f in ("blue-run", f, 0, BOTTOM - 13) }) {
                strip.pass(l, seconds: tickSeconds) { s in (from + (to - from) * min(1, s / tickSeconds)).rounded() }
                add(l)
            }
            lastBlueX = Int(to)
            if wag { add(strip.flipbook(clock: clock, count: 2, z: 10.5) { f in ("heart", 0, max(0, home - r.dogRun * 4) + 8 + (f % 2) * 2, BOTTOM - 13 - 6) }) }
            return out
        }
        if idleDog && r.act == "chase" && !night {
            add(strip.flipbook(clock: clock, count: 12, z: 10) { f in ("blue-run", f, home - chaseOffset(f) * 4, BOTTOM - 13) })
            add(strip.flipbook(clock: clock, count: 12, z: 10) { f in ("hen", f, home - chaseOffset(f) * 4 - 14, BOTTOM - 10) })
            if wag { add(strip.flipbook(clock: clock, count: 12, z: 10.5) { f in ("heart", 0, home - chaseOffset(f) * 4 + 8 + (f % 2) * 2, BOTTOM - 13 - 6) }) }
            return out
        }
        lastBlueX = nil
        let top = FOOT - 13
        if away || (r.visit?.phase == "deal" && r.visit?.kind != "tractor") {
            add(strip.flipbook(clock: clock, count: 2, z: 10) { f in ("blue-bark", f, home, top) })
            add(strip.sprite("bang", x: home + 8, y: top - 8, z: 10.5))
        } else if night || (idleDog && r.act == "nap") {
            add(strip.standing("blue-nap", x: home, bottom: FOOT, z: 10))
            add(strip.flipbook(clock: clock, count: 2, z: 10.5) { f in ("zz", f, home + 10, top - 9) })
        } else {
            add(strip.flipbook(clock: clock, count: 2, z: 10) { f in ("blue-wag", wag ? f : 0, home, top) })
        }
        if wag { add(strip.flipbook(clock: clock, count: 2, z: 10.5) { f in ("heart", 0, home + 8 + (f % 2) * 2, FOOT - 13 - 6) }) }
        return out
    }

    /// The pup (3.11): 14 px left of wherever Blue is drawn, on his ground; none while Blue rides in the truck.
    func pupLayers(_ r: LiveRecord, night: Bool, clock: FrameClock) -> [CALayer] {
        let f0 = clock.frame(scene.worldNow)
        guard let spot = blueSpot(r, night: night, f: f0) else { lastPupX = nil; return [] }
        let away = r.truck != nil
        if r.pose == "none" && r.mood != "working" && !away && r.act == "chase" && r.dogRun == 0 && !night {
            lastPupX = nil
            return [strip.flipbook(clock: clock, count: 12, z: 10) { f in ("pup", 0, self.blueX - chaseOffset(f) * 4 - 14, BOTTOM - 9) }].compactMap { $0 }
        }
        let l = strip.standing("pup", x: spot.x - 14, bottom: spot.bottom, z: 10)
        if r.dogRun > 0, let from = lastPupX { strip.pass(l, seconds: tickSeconds) { s in Double(from) + Double(spot.x - 14 - from) * min(1, s / tickSeconds) } }
        lastPupX = r.dogRun > 0 ? spot.x - 14 : nil
        return [l]
    }

    // MARK: Bubble (drawBubble)

    /// The bubble left of Jeb's head, with the room the strip gives it.
    func bubbleLayers(_ r: LiveRecord) -> [CALayer] {
        strip.bubble(r.line, jebX: jebX, dim: r.dim)
    }
}
