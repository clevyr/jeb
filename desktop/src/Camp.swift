// A session's camp, the place the scene is while Jeb visits it: its hired hands in
// a three-crop patch with the test weather over it, its Compose building, its loose
// cows (#N), its live square on the tent pole, a lantern, and the still's embers
// (its fire and steam while he runs a command). The one Jeb and Blue stand here and
// act out the session's record (Cast.swift), and its truck, happenings and visitors
// play here through the shared drawing (Strip.swift). Everything comes from the
// session's live record (Live.swift) and the farm; the band's own rules decide each
// sprite (pixel-scene.ts drawHands, drawWeather, drawCows), placed against the
// camp's anchors instead of the farm's. The strip is as wide as the homestead's and
// Jeb stands where he stands at home. Laid out like the band's right-hand cluster:
//
//   [patch: tobacco corn apples] [yard: cows, building behind] [Blue] [Jeb] [fire] [tent]

import AppKit
import QuartzCore

struct CampLayout {
    let width: Int
    let secX: [String: Int]
    let secW = 20
    let patchEnd: Int
    let houseX, stillX, jebX, blueX, tentX, buildingX, yardLeft: Int
    init(width w: Int) {
        width = w
        secX = ["tobacco": 4, "corn": 24, "apples": 44]
        patchEnd = 64
        houseX = w - 51   // where the homestead's house stands; the tent is set there
        stillX = houseX - 40
        jebX = stillX - 22
        blueX = jebX - 20 // where the lane's visitors and the neighbor come up to
        tentX = houseX + 8
        buildingX = patchEnd + 6
        yardLeft = patchEnd + 4
    }
    var anchors: Anchors { Anchors(width: width, houseX: houseX, orchardX: secX["apples"] ?? 44, cornX: secX["corn"] ?? 24, blueX: blueX, jebX: jebX) }
}

final class Camp {
    let token: String
    let strip: Strip
    let art: Art
    let g: CampLayout
    /// The session's band clock, kept while new records agree with it (so its parts stay put).
    private var stable: FrameClock?
    unowned let scene: FarmScene
    private lazy var cast = JebBlue(strip: strip, art: art, scene: scene, jebX: g.jebX, blueX: g.blueX)

    init(token: String, width: Int, scene: FarmScene, art: Art) {
        self.token = token
        self.scene = scene
        self.art = art
        g = CampLayout(width: width)
        strip = Strip(art: art, width: width, scene: scene)
        strip.layer.name = "camp-strip" // for the scene's place count
    }

    func tearDown() { strip.clearAll() }

    /// How many sprites the camp's area stands in it (measuring only).
    private(set) var areaPlaced = 0

    /// Draws the camp for the record `r` (and the story's line, if one is up); only the parts whose inputs changed are rebuilt.
    /// `theme` is the area the record names, when it is read: its props and beats' sprites stand in the camp (the land is the scene's).
    func update(farm: Farm, record r: LiveRecord, line: String?, theme: AreaTheme? = nil) {
        let night = scene.isNight, now = scene.now
        let clock = bandClock(for: r, scene: scene, stable: &stable)
        let ck = "\(clock.frame0)|\(Int(clock.at * 10))|\(clock.period)|\(clock.frozen)"
        let looks = looksOf(farm, now: now, rainbow: false, wet: false, star: 0)
        let nap = looks.contains { $0.id == "nap" }, hat = looks.contains { $0.id == "sundayhat" }, chair = farm.upgrades.contains("chair")
        let fire = r.pose == "still"

        // The camp itself: patch, building, tent, lantern post and the session's square.
        let dry = r.weather?.kind == "dry" ? r.weather?.plot ?? "" : ""
        strip.part("camp", key: "\(farm.crops)|\(dry)|\(r.building)|\(r.live)|\(r.more)|\(night)|\(r.cows)|\(r.moreCows)|\(fire)") { [self] in
            var c = Pix(w: g.width, h: bandHeight)
            paintCamp(&c, farm: farm, r: r, dry: dry, night: night, fire: fire)
            return [strip.picture(c, z: 8)]
        }
        if let theme {
            strip.part("area", key: "\(theme.tag)|\(r.building)|\(r.cows)|\(r.moreCows)") { [self] in areaLayers(theme, r) }
        } else {
            strip.clear("area")
            areaPlaced = 0
        }
        strip.part("lantern", key: ck) { [self] in
            [strip.flipbook(clock: clock, count: 2, z: 8.5) { f in ("lantern", f, g.tentX - 6, 17) }].compactMap { $0 }
        }
        // The hired hands, one to a crop, and the teammates.
        strip.part("hands", key: "\(ck)|\(r.hands)|\(r.mates)") { [self] in
            var out: [CALayer] = []
            for hand in r.hands {
                guard let x = g.secX[hand.plot] else { continue }
                if let l = strip.flipbook(clock: clock, count: 2, z: 10, { f in ("hand-work-\(hand.look)", f, x + 2, FOOT - 28) }) { out.append(l) }
            }
            for i in 0..<r.mates {
                out.append(strip.standing(i % 2 == 0 ? "opal" : "hand-work", x: g.patchEnd + 2 + i * 16, bottom: FOOT, z: 10))
            }
            return out
        }
        // The test run's rain over its crop (or all three).
        strip.part("weather", key: "\(ck)|\(r.weather?.kind ?? "")|\(r.weather?.plot ?? "")") { [self] in
            guard let w = r.weather, w.kind == "rain" else { return [] }
            var out: [CALayer] = []
            for crop in cropNames where w.plot == "all" || w.plot == crop {
                guard let x = g.secX[crop] else { continue }
                out.append(strip.sprite("cloud-dark", x: x + ((g.secW - 22) >> 1), y: 0, z: 11))
                var k = 0
                while k * 7 + 3 < g.secW {
                    let kk = k
                    if let l = strip.flipbook(clock: clock, count: 8, z: 11, { f in ("drop-px", 0, x + 3 + kk * 7 + (kk % 2) * 2, 10 + ((f * 3 + kk * 11) % 24)) }) { out.append(l) }
                    k += 1
                }
            }
            return out
        }
        // The loose cows on the lane, each with its neighbor's number.
        strip.part("cows", key: "\(ck)|\(r.cows)|\(r.moreCows)") { [self] in cowLayers(r, clock: clock) }

        // The one Jeb and Blue, from the record, by the band's own rules.
        let jebKey = "\(ck)|\(jebSpriteFor(r, night: night))|\(r.truck != nil)|\(nap)|\(hat)|\(chair)|\(r.gated)|\(r.pose)|\(night)"
        strip.part("jeb", key: jebKey) { [self] in cast.jebLayers(r, night: night, nap: nap, hat: hat, chair: chair, clock: clock) }
        let blueKey = "\(ck)|\(r.dogRun)|\(r.act)|\(r.pose)|\(r.mood)|\(r.truck?.dog ?? false)|\(r.truck != nil)|\(r.visit?.phase ?? "")|\(r.visit?.kind ?? "")|\(r.fx.sorted())|\(night)|\(r.event?.id ?? "")|\(r.event.map { restOf(id: $0.id, t: $0.t, dur: $0.dur) == nil ? -1 : $0.t } ?? 0)"
        strip.part("blue", key: blueKey) { [self] in cast.blueLayers(r, night: night, clock: clock) }
        if farm.upgrades.contains("pup") {
            strip.part("pup", key: blueKey) { [self] in cast.pupLayers(r, night: night, clock: clock) }
        } else {
            strip.clear("pup")
        }
        // The still's fire and steam while Jeb runs a command.
        strip.part("fire", key: "\(ck)|\(fire)") { [self] in
            guard fire else { return [] }
            return [strip.flipbook(clock: clock, count: 2, z: 9) { f in ("fire", f, g.stillX + 3, GROUND - 6) },
                    strip.flipbook(clock: clock, count: 2, z: 9) { f in ("steam", f, g.stillX + 7, 0) }].compactMap { $0 }
        }
        // His bubble: the story's line, else the record's own while he is talking.
        let said = line ?? (r.showsBubble(now: now) ? r.line : nil)
        strip.part("bubble", key: "\(said ?? "")|\(line == nil ? r.dim : false)") { [self] in
            said.map { strip.bubble($0, jebX: g.jebX, dim: line == nil && r.dim) } ?? []
        }

        // A visitor on the lane.
        let visitKey = r.visit.map { v in "\(v.kind).\(v.facing).\(v.phase).\(v.x).\(Int(r.at))" } ?? ""
        strip.part("visit", key: "\(ck)|\(visitKey)") { [self] in strip.visitLayers(r, clock: clock, anchors: g.anchors) }
        // The happening.
        let ev = r.event
        strip.part("events", key: "\(ck)|\(ev?.id ?? "")|\(ev?.dur ?? 0)|\(ev?.v ?? 0)|\(ev.map { Int(r.at - Double($0.t) * 500) } ?? 0)") { [self] in
            ev.map { strip.eventLayers($0, clock: clock, wall: r.at, anchors: g.anchors) } ?? []
        }
        // The truck on the road, and warming up at the tent.
        let truckKey = r.truck.map { "\($0.load).\($0.dog).\($0.sputter > 0).\(Int((r.at - Double($0.t) * 500) / 250))" } ?? ""
        strip.part("truck", key: "\(truckKey)|\(r.fx.contains("puff"))") { [self] in
            if let t = r.truck { return strip.truckLayers(t, clock: clock, wall: r.at, houseX: g.houseX) }
            guard r.fx.contains("puff") else { return [] }
            let x0 = g.houseX + 4
            return [strip.flipbook(clock: clock, count: 2, z: 12, { f in ("truck-empty", f, x0, BOTTOM - 22) }),
                    strip.flipbook(clock: clock, count: 2, z: 12, { f in ("dust", f, x0 + truckW, BOTTOM - 8) })].compactMap { $0 }
        }
    }

    // MARK: The area's sprites

    /// Where the area's zones are in the camp's strip (the homestead's drop zones, against the camp's own anchors).
    private func zoneBox(_ zone: String) -> (x0: Int, x1: Int, top: Int?, bottom: Int?) {
        switch zone {
        case "sky": return (4, max(12, g.blueX - 8), 13, nil)
        case "yard": return (g.yardLeft, g.blueX - 6, nil, FOOT)
        case "porch": return (g.tentX + 28, g.width - 2, nil, FOOT)
        case "field": return (2, max(10, g.patchEnd - 2), nil, GROUND)
        default: return (g.yardLeft, g.stillX - 4, nil, BOTTOM - 1)
        }
    }

    /// The area's props and beats' sprites through the shared drop placement (8 at most), clear of the cast, the still,
    /// the building and the loose cows.
    private func areaLayers(_ theme: AreaTheme, _ r: LiveRecord) -> [CALayer] {
        var avoid = [Box(x: g.jebX - 1, y: 0, w: 22, h: bandHeight), Box(x: g.blueX, y: 28, w: 20, h: bandHeight - 28), Box(x: g.stillX, y: 0, w: 40, h: bandHeight)]
        if !r.building.isEmpty { avoid.append(Box(x: g.buildingX, y: 0, w: 22, h: bandHeight)) }
        for spot in cowSpots(r) { avoid.append(Box(x: spot.x, y: 26, w: spot.w, h: bandHeight - 26)) }
        var taken: [Box] = []
        let placed = placeDrops(theme.drops.map { (sprite: $0, art: nil) }, art: art, box: zoneBox, avoid: avoid, taken: &taken)
        areaPlaced = placed.count
        return placed.map { strip.sprite($0.name, x: $0.x, y: $0.y, z: 8.4) }
    }

    // MARK: The camp picture

    private func paintCamp(_ c: inout Pix, farm: Farm, r: LiveRecord, dry: String, night: Bool, fire: Bool) {
        let soil = art.colour("soil"), soilDry = art.colour("soil_dry")
        let shade = night ? 0.5 : 0.0
        func tone(_ w: UInt32) -> UInt32 { shade > 0 ? mix(w, word(18, 22, 44), shade) : w }
        // The patch: three plants of tobacco and of corn, two apple trees, as the farm's own rows stand.
        for crop in cropNames {
            guard let x = g.secX[crop] else { continue }
            let isDry = dry == "all" || dry == crop
            if crop == "apples" {
                if isDry { c.rect(x, GROUND - 2, g.secW, 3, soilDry) }
                for i in 0..<2 { art.stand("apple-\(farm.stage("apples", i))", into: &c, x: x + i * 10, bottom: GROUND) }
            } else {
                c.rect(x, GROUND - 2, g.secW, 3, isDry ? soilDry : soil)
                for i in 0..<3 { art.stand("\(crop)-\(farm.stage(crop, i))", into: &c, x: x + 1 + i * 6, bottom: GROUND) }
            }
            // Hands that did not fit, as on the band's plot labels.
            if let n = r.more[crop], n > 0 {
                let more = "+\(min(99, n))"
                art.text(more, into: &c, x: x + g.secW - textWidth(more), y: ROAD_TOP, colour: art.colour("yellow"))
            }
        }
        // The Compose service's building, set back in the yard.
        let bx = g.buildingX, back = GROUND - 2
        switch r.building {
        case "app": art.standHalf(night ? "house-night" : "house", into: &c, x: bx, bottom: back)
        case "hot":
            art.stand("garden-3", into: &c, x: bx, bottom: back)
            art.stand("garden-2", into: &c, x: bx + 10, bottom: back)
            art.stand("prop-fence", into: &c, x: bx + 2, bottom: back + 1)
            art.stand("prop-fence", into: &c, x: bx + 10, bottom: back + 1)
        case "database":
            // A root cellar: a stone mound with a plank door.
            let stone = tone(art.colour("stone")), dark = tone(art.colour("grey")), door = art.colour("wood_dark")
            for row in 0..<8 {
                let half = Int((sqrt(Double(64 - (8 - row) * (8 - row)))).rounded()) + 1
                c.rect(bx + 9 - half, back - 8 + row, half * 2, 1, row % 3 == 0 ? dark : stone)
            }
            c.rect(bx + 7, back - 5, 5, 5, door)
            c.dot(bx + 10, back - 3, art.colour("amber"))
        default: break
        }
        // The tent, back on the shelf, its pole flying the session's square so far.
        let tx = g.tentX, base = GROUND - 1, top = base - 17
        let canvas = tone(art.colour("cloud")), side = tone(art.colour("stone")), ink = art.colour("ink"), pole = art.colour("wood_dark")
        for row in 0..<17 {
            let half = 1 + row * 12 / 16
            for x in (13 - half)...(13 + half) {
                let edge = x == 13 - half || x == 13 + half
                c.dot(tx + x, top + row, edge ? ink : x < 13 ? canvas : side)
            }
            if row >= 9 { let d = (row - 8) / 2; c.rect(tx + 13 - d, top + row, 2 * d + 1, 1, night ? art.colour("amber") : ink) }
        }
        c.rect(tx + 13, top - 6, 1, 6, pole)
        art.blit("quilt-\(r.live)", into: &c, x: tx + 14, y: top - 6, dim: true)
        // The lantern's post.
        c.rect(g.tentX - 4, 25, 1, base - 25 + 1, pole)
        // The still's embers (its fire and steam replace them while Jeb runs a command).
        if !fire { art.stand("embers", into: &c, x: g.stillX + 3, bottom: GROUND) }
        // The cows' numbers over them (drawCows).
        for spot in cowSpots(r) {
            art.text(spot.key, into: &c, x: spot.x + ((spot.w - textWidth(spot.key)) >> 1), y: BOTTOM - 15 - 7, colour: art.colour("white"))
        }
        let shown = cowSpots(r)
        let more = r.moreCows + (r.cows.count - shown.count)
        if more > 0 { art.text("+\(min(99, more))", into: &c, x: (shown.last.map { $0.x + $0.w + 4 } ?? g.yardLeft), y: BOTTOM - 8, colour: art.colour("yellow")) }
    }

    /// The cows that fit in the yard: their x, slot width and label.
    private func cowSpots(_ r: LiveRecord) -> [(x: Int, w: Int, key: String)] {
        let left = g.yardLeft, room = g.blueX - 4 - left
        var out: [(x: Int, w: Int, key: String)] = []
        var x = left, used = 0
        for n in r.cows {
            let key = String("#\(n)".prefix(10)), w = max(22, textWidth(key))
            guard used + w + 4 <= room else { break }
            out.append((x, w, key))
            used += w + 4
            x += w + 4
        }
        return out
    }

    private func cowLayers(_ r: LiveRecord, clock: FrameClock) -> [CALayer] {
        cowSpots(r).compactMap { spot in strip.flipbook(clock: clock, count: 2, z: 10) { f in ("cow", f, spot.x + ((spot.w - 22) >> 1), BOTTOM - 15) } }
    }
}
