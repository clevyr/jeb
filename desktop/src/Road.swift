// The road between two places: what the scene is while Jeb is travelling. A fence
// along the lane, Jeb walking in from the left to where he stands at the next place
// with Blue at his heels, a pause in the middle of the walk for the road beat's
// line (and, now and then, a wayside encounter standing there). One pass for each
// of them, played by Core Animation from the trip's own clock, so a scene that
// resumes mid-trip draws from where the walk has got to and never replays it.

import AppKit
import QuartzCore

final class Road {
    let strip: Strip
    let art: Art
    let width: Int
    unowned let scene: FarmScene
    private var built: Int?

    init(width: Int, scene: FarmScene, art: Art) {
        self.width = width
        self.scene = scene
        self.art = art
        strip = Strip(art: art, width: width, scene: scene)
        strip.layer.name = "road-strip" // for the scene's place count
    }

    func tearDown() { strip.clearAll() }

    /// Where Jeb stands `p` of the way through the road beat: in from the edge, a pause mid-lane, on to his spot.
    private func x(at p: Double, to jebX: Int) -> Double {
        let mid = Double(width / 2 - 20)
        if p < 0.375 { return -24 + (mid + 24) * p / 0.375 }
        if p < 0.667 { return mid }
        return mid + (Double(jebX) - mid) * min(1, (p - 0.667) / 0.333)
    }

    /// Draws the road for `trip` as of `now`; its parts are built once a trip and again only when the line changes.
    func update(trip: Trip, line: String?, now: Date, jebX: Int) {
        let night = scene.isNight
        let rem = max(0, trip.end.timeIntervalSince(now)), p0 = max(0, min(1, 1 - rem / roadSeconds))
        strip.part("fence", key: "\(night)") { [self] in
            var c = Pix(w: width, h: bandHeight)
            var fx = 14
            while fx + 8 < width { art.stand("prop-fence", into: &c, x: fx, bottom: GROUND + 3); fx += 40 }
            return [strip.picture(c, z: 8)]
        }
        let mid = Int(x(at: 0.5, to: jebX))
        strip.part("walk", key: "\(trip.id)") { [self] in
            let jeb = strip.standing("jeb-idle", x: Int(x(at: p0, to: jebX)), bottom: FOOT, z: 10)
            strip.pass(jeb, seconds: rem) { s in self.x(at: p0 + s / roadSeconds, to: jebX).rounded() }
            let clock = FrameClock(frame0: 0, at: scene.worldNow, period: 0.2, frozen: false)
            var out = [jeb]
            if let dog = strip.flipbook(clock: clock, count: 2, z: 10, { f in ("blue-run", f, 0, BOTTOM - 13) }) {
                strip.pass(dog, seconds: rem) { s in self.x(at: p0 + s / roadSeconds, to: jebX).rounded() - 22 }
                dog.position.x = CGFloat(x(at: p0, to: jebX).rounded() - 22)
                out.append(dog)
            }
            return out
        }
        strip.part("wayside", key: "\(trip.id)|\(trip.wayside ?? "")") { [self] in
            guard let name = trip.wayside else { return [] }
            return [strip.standing(name, x: mid + 34, bottom: FOOT, z: 9.5)]
        }
        strip.part("bubble", key: "\(line ?? "")|\(trip.id)") { [self] in
            line.map { strip.bubble($0, jebX: mid, dim: false) } ?? []
        }
    }
}
