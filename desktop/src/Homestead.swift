// The homestead: the shared farm, one of the places the scene can be, laid out by
// the band's own rules (pixel-scene.ts layoutOf) and drawn by its own code, ported
// line for line into a Strip. What only the farm decides (crops, stack, quilt,
// sign, house, still, the jars and cash, the little things, the drops' decor) is
// one picture repainted on a change. What the sessions bring to the farm: their
// live squares on the line, the stitch flash, a lantern for each other session, and
// the after-rain bursts (farm-wide); and, from the one record he acts out here (the
// session he last left, until it goes quiet), its truck, happenings and visitors,
// with the one Jeb and Blue (Cast.swift). With none, they idle on the desktop's own
// calm clock. The shared drawing (happenings, trucks, visitors) is in Strip.swift.

import AppKit
import QuartzCore

/// pixel-scene.ts layoutOf for a farm `width` pixels wide.
struct BandLayout: Equatable {
    static let stackStep = 11, signW = 46, miniW = 19
    let width: Int
    let houseX, stillX, jebX, blueX: Int
    let plots: [Plot]
    let plotsEnd: Int
    var stackX: Int?, signX: Int?, miniX: Int?
    var midEnd: Int
    struct Plot: Equatable { let crop: String, x: Int, w: Int }

    init(width: Int, columns: Int, farm: Farm) {
        self.width = width
        houseX = width - 51
        stillX = houseX - 40
        jebX = stillX - 22
        blueX = jebX - 20
        let blueX = blueX
        plots = cropNames.enumerated().map { Plot(crop: $0.element, x: 2 + $0.offset * 56, w: $0.element == "apples" ? 46 : 50) }
            .filter { $0.x + $0.w <= blueX - 2 }
        plotsEnd = plots.last.map { $0.x + $0.w } ?? 2
        midEnd = plotsEnd
        let avail = blueX - 4 - plotsEnd
        let stackW = columns * Self.stackStep + (farm.built.contains("smokehouse") ? 20 : 0)
        guard avail >= Self.signW + 6 else { return }
        let hasMini = farm.upgrades.contains("still2") && avail >= Self.signW + Self.miniW + 6 + 8
        let miniW = hasMini ? Self.miniW + 6 : 0
        let pad = min(8, Int((Double(avail - Self.signW - miniW - stackW) / 3).rounded(.down)))
        var signX: Int
        if columns > 0 && pad >= 2 {
            stackX = plotsEnd + pad
            signX = plotsEnd + pad + stackW + pad
        } else {
            signX = plotsEnd + max(2, min(8, Int((Double(avail - Self.signW - miniW) / 2).rounded(.down))))
        }
        self.signX = signX
        midEnd = signX + Self.signW
        if hasMini && signX + Self.signW + 6 + Self.miniW <= blueX - 2 {
            miniX = signX + Self.signW + 6
            midEnd = miniX! + Self.miniW
        }
    }

    var orchardX: Int { plots.first { $0.crop == "apples" }?.x ?? max(0, plotsEnd - 46) }
    var cornX: Int { plots.first { $0.crop == "corn" }?.x ?? max(0, plotsEnd - 50 - 6) }
    /// The little things' yard anchor (drawLooks yx).
    var yx: Int { max(plotsEnd + 1, min(signX != nil ? midEnd + 4 : plotsEnd + 2, blueX - 14)) }
    var jebHead: Box { Box(x: jebX - 1, y: 0, w: 22, h: 21) }
    var anchors: Anchors { Anchors(width: width, houseX: houseX, orchardX: orchardX, cornX: cornX, blueX: blueX, jebX: jebX) }
}

/// The day's calendar flags (almanac.ts dayFlags).
struct DayFlags: Equatable {
    let isPumpkin, isThanksgiving, isChristmas, isGroundhog: Bool
    init(_ now: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .weekday], from: now)
        let m = c.month ?? 1, d = c.day ?? 1
        isPumpkin = m == 10 && d >= 25
        isChristmas = m == 12 && d >= 20 && d <= 26
        isGroundhog = m == 2 && d == 2
        // The fourth Thursday of November.
        var thanks = false
        if m == 11 {
            let first = Calendar.current.date(from: DateComponents(year: c.year, month: 11, day: 1))!
            let wd = Calendar.current.component(.weekday, from: first) // 1 = Sunday
            let firstThursday = 1 + (5 - wd + 7) % 7
            thanks = d == firstThursday + 21
        }
        isThanksgiving = thanks
    }
}

/// A look on show (unlocks.ts looksOf): id and its variant.
struct Look: Equatable { let id: String; let n: Int }

/// unlocks.ts looksOf: every look on show at `now`, in draw order.
func looksOf(_ farm: Farm, now: Date, rainbow: Bool, wet: Bool, star: Int) -> [Look] {
    let has = { (id: String) in farm.unlocks.contains(id) }
    let c = Calendar.current.dateComponents([.hour, .minute, .month, .weekday], from: now)
    let hour = c.hour ?? 12, minutes = hour * 60 + (c.minute ?? 0), month = (c.month ?? 1) - 1, weekday = (c.weekday ?? 1) - 1
    let night = isNightHour(hour)
    var out: [Look] = []
    func add(_ id: String, _ n: Int = 0) { out.append(Look(id: id, n: n)) }
    if has("creek") {
        add("creek")
        if weekday == 6 && hour >= 13 && hour < 18 { add("fisher") }
    }
    if has("washday") && weekday == 1 && hour >= 8 && hour < 17 { add("washday") }
    if has("deer") && hour >= 17 && hour < 21 { add("deer", min(7, (minutes - 17 * 60) / 30)) }
    if has("woodpile") { add("woodpile", farm.pile) }
    if has("garden") { add("garden", month >= 6 && month <= 8 ? 3 : month == 5 || month == 9 ? 2 : month == 4 || month == 3 ? 1 : 0) }
    if has("birdhouse") {
        add("birdhouse")
        if month >= 2 && month <= 8 && hour >= 6 && hour < 11 { add("bluebird") }
    }
    if has("cardinal") && !night { add("cardinal") }
    if has("owl") && (hour >= 21 || hour < 5) { add("owl") }
    if has("butterflies") && month >= 4 && month <= 8 && hour >= 12 && hour < 18 { add("butterflies") }
    if has("drift") && !night {
        if month >= 8 && month <= 10 { add("leaves") } else if month == 11 || month <= 1 { add("snow") }
    }
    if has("afterrain") {
        if wet { add("puddles") }
        if rainbow { add("rainbow") }
    }
    if has("shootingstar") && night && star > 0 { add("star", star) }
    if has("mug") && hour >= 5 && hour < 10 { add("mug") }
    if has("midnightcoffee") && hour >= 0 && hour < 5 && farm.coffee == dateKeyOf(now) { add("coffee") }
    if has("lunch") && minutes >= 11 * 60 + 30 && minutes < 13 * 60 + 30 { add("lunch") }
    if has("napchair") && farm.upgrades.contains("chair") && hour >= 13 && hour < 15 { add("nap") }
    if has("porchlight") && hour >= 17 && hour < 23 { add("porchlight") }
    if has("sundayhat") && weekday == 0 && hour >= 6 && hour < 21 { add("sundayhat") }
    if has("postcard") && weekday >= 1 && weekday <= 5 && hour >= 10 && hour < 18 { add("postcard") }
    if has("anniversary") && hour >= 6 && hour < 22 && isDateKey(farm.since) && farm.since.dropFirst(5) == dateKeyOf(now).dropFirst(5)
        && (Int(farm.since.prefix(4)) ?? 9999) < (Calendar.current.component(.year, from: now)) { add("cake") }
    return out
}

let STACK_ICONS = ["lumber": "icon-lumber", "stone": "icon-stone", "straw": "icon-straw", "iron": "icon-iron", "sugar": "icon-sugar",
                   "copper": "icon-copper", "appleButter": "icon-apple_butter", "twists": "icon-twist", "whiskey": "icon-whiskey"]
let TRUCK_SPRITES = ["box": "truck-crate", "jar": "truck-jars", "bale": "truck-bales", "apple": "truck-apples", "corn": "truck-corn",
                     "butter": "truck-crate", "twist": "truck-crate", "whiskey": "truck-crate"]
let TRUCK_ICONS = ["butter": "icon-apple_butter", "twist": "icon-twist", "whiskey": "icon-whiskey"]

/// What the sessions bring to the farm, merged.
struct FarmMoment {
    var lanterns = 0                  // sessions other than the one he acts out here
    var liveSquares: [String] = []
    var stitch: FrameClock?           // a session's clock while its stitch flash is on
    var rainbow = false, wet = false, star = 0
    var starClock: FrameClock?
    var events: [(event: LiveEvent, clock: FrameClock, wall: Double)] = [] // the acted-out record's happening
    var trucks: [(truck: LiveTruck, clock: FrameClock, wall: Double, token: String)] = []
    var puff: FrameClock?
    var chasing = false               // his Blue is chasing the hen
    var lead: LiveRecord?             // the record the one Jeb acts out here
    var leadClock: FrameClock?
    var storyLine: String?            // the story's line, over the record's own
}

final class Homestead {
    let strip: Strip
    let art: Art
    private(set) var band: BandLayout
    private let width: Int
    private var farmRev = 0
    private var lastFarm: Farm?
    unowned let scene: FarmScene
    private lazy var cast = JebBlue(strip: strip, art: art, scene: scene, jebX: band.jebX, blueX: band.blueX)
    var layer: CALayer { strip.layer }

    init(scene: FarmScene, art: Art, width: Int, farm: Farm) {
        self.scene = scene
        self.art = art
        self.width = width
        strip = Strip(art: art, width: width, scene: scene)
        strip.layer.name = "farm-strip" // for the scene's place count
        band = BandLayout(width: width, columns: farm.columns(now: scene.now).count, farm: farm)
    }

    func tearDown() { strip.clearAll() }

    /// Draws the homestead for this farm and these sessions; parts whose inputs did not change stay.
    func update(farm: Farm, moment m: FarmMoment, home: FrameClock) {
        let now = scene.now
        if lastFarm != farm { farmRev += 1; lastFarm = farm }
        let columns = farm.columns(now: now)
        band = BandLayout(width: width, columns: columns.count, farm: farm)
        let night = scene.isNight
        let day = DayFlags(now)
        let looks = looksOf(farm, now: now, rainbow: m.rainbow, wet: m.wet, star: m.star)
        let tint = farm.festivalTint(now: now)
        let tarp = m.events.contains { $0.event.id == "revenuer" && Double($0.event.t) / Double($0.event.dur) < 0.85 }
        let placed = farm.dropLooks(now: now)
        let g = band
        let fire = m.lead?.pose == "still" // the still's fire and steam replace its embers while Jeb runs a command
        var taken: [Box] = []
        let drops = placements(placed, taken: &taken)
        placedTaken = taken

        // The farm as one picture.
        let staticKey = "\(farmRev)|\(night)|\(day.isPumpkin)\(day.isChristmas)|\(looks.map { "\($0.id)\($0.n)" })|\(tint)|\(tarp)|\(columns.map { "\($0.id)\($0.count)" })|\(placed.map { $0.sprite.sprite + $0.sprite.zone })|\(m.lead?.pose == "still")"
        strip.part("farm", key: staticKey) { [self] in
            var c = Pix(w: width, h: bandHeight)
            paintFarm(&c, farm: farm, columns: columns, looks: looks, day: day, tarp: tarp, night: night, drops: drops.filter { $0.frames != 2 }, fire: fire)
            guard day.isGroundhog else { return [strip.picture(c, z: 8)] }
            // Groundhog Day: he pops up by the house five frames in eight, under the still.
            var up = Pix(w: width, h: bandHeight)
            paintFarm(&up, farm: farm, columns: columns, looks: looks, day: day, tarp: tarp, night: night, drops: drops.filter { $0.frames != 2 }, groundhog: true, fire: fire)
            return [strip.indexedBook([c, up], count: 8, clock: home, y: 0, z: 8) { f in f % 8 < 5 ? 1 : 0 }].compactMap { $0 }
        }

        // A lantern over the sign for each other session; past four, a count.
        strip.part("lanterns", key: "\(m.lanterns)|\(g.signX ?? -1)") { [self] in
            guard let signX = g.signX, m.lanterns > 0 else { return [] }
            var out: [CALayer] = []
            for i in 0..<min(4, m.lanterns) {
                if let l = strip.flipbook(clock: home, count: 2, z: 9, { f in ("lantern", f + i, signX + 14 + i * 8, 1) }) { out.append(l) }
            }
            if m.lanterns > 4 {
                var t = Pix(w: textWidth("x\(m.lanterns)") + 1, h: 5)
                art.text("x\(m.lanterns)", into: &t, x: 0, y: 0, colour: art.colour("yellow"))
                out.append(strip.painted(t, x: BandLayout.signW + signX + 2, y: 2, z: 9))
            }
            return out
        }

        // The quilt line's live squares (one per session, dim) and the stitch flash.
        strip.part("quilt", key: "\(farmRev)|\(m.liveSquares)|\(m.stitch != nil)|\(columns.count)") { [self] in
            guard let line = quiltLine(farm: farm) else { return [] }
            var out: [CALayer] = []
            // The band: n - 1 stitched squares and this session's own, dim. Here one dim square a session.
            let k = min(line.n - 1, m.liveSquares.count)
            let stitched = Array(farm.quilt.suffix(k == 0 ? line.n - 1 : line.n - k))
            let lives = Array(m.liveSquares.prefix(k))
            var c = Pix(w: width, h: bandHeight)
            for (i, code) in stitched.enumerated() where !(i == stitched.count - 1 && m.stitch != nil) {
                art.blit("quilt-\(code)", into: &c, x: line.x0 + i * 6, y: 5)
            }
            for (j, code) in lives.enumerated() {
                art.blit("quilt-\(code)", into: &c, x: line.x0 + (stitched.count + j) * 6, y: 5, dim: true)
            }
            out.append(strip.picture(c, z: 8.5))
            if let clock = m.stitch, let newest = stitched.last {
                // The newest stitched square flickers dim and bright, frame by frame.
                if let l = strip.flipbook(clock: clock, count: 2, z: 8.6, { f in f % 2 == 0 ? nil : ("quilt-\(newest)", 0, line.x0 + (stitched.count - 1) * 6, 5) }) { out.append(l) }
                if let l = strip.flipbook(clock: clock, count: 2, z: 8.6, dim: true, { f in f % 2 == 0 ? ("quilt-\(newest)", 0, line.x0 + (stitched.count - 1) * 6, 5) : nil }) { out.append(l) }
            }
            return out
        }

        // The little things that move with the frame.
        strip.part("looks", key: "\(looks.map { "\($0.id)\($0.n)" })|\(g.houseX)|\(g.plotsEnd)|\(g.blueX)") { [self] in movingLooks(looks, clock: home, starClock: m.starClock) }

        // The calendar's animals and the sky snow of Christmas week.
        strip.part("calendar", key: "\(day.isThanksgiving)\(day.isGroundhog)\(day.isChristmas)|\(g.stillX)|\(g.houseX)|\(night)") { [self] in
            var out: [CALayer] = []
            if day.isThanksgiving, let l = strip.flipbook(clock: home, count: 2, z: 10, { f in ("turkey", f, g.stillX + 16, BOTTOM - 13) }) { out.append(l) }
            if day.isChristmas {
                // A little snow over the sky: a dot in column i where (i*5 + frame) % 7 == 0, at row
                // (i*3 + frame*2) % 30. Columns alike mod 7 show on the same frames: one layer each.
                for k in 0..<7 {
                    let fk = ((-5 * k) % 7 + 7) % 7
                    var pics: [Pix] = []
                    for m in 0..<15 {
                        var p = Pix(w: width, h: 30)
                        let f = fk + 7 * m
                        for i in stride(from: k, to: width, by: 7) { p.dot(i, (i * 3 + f * 2) % 30, art.colour("white")) }
                        pics.append(p)
                    }
                    if let l = strip.indexedBook(pics, count: 105, clock: home, y: 0, z: 2.5, { f in (f - fk) % 7 == 0 ? ((f - fk) / 7) % 15 : nil }) { out.append(l) }
                }
            }
            if night {
                // The band's night fireflies, at their fixed spots.
                for fx in [18, 64, 110, 170] where fx + 3 < g.blueX - 8 {
                    // Under the farm's picture: whatever stands there covers them, as on the band.
                    if let l = strip.flipbook(clock: home, count: 2, z: 7.9, { f in ("firefly", f + (fx >> 2), fx, 18 + (fx % 3) * 3) }) { out.append(l) }
                }
            }
            return out
        }

        // The creative drops' decor with two frames bobs a pixel, frame by frame.
        strip.part("decor", key: "\(placed.map { $0.sprite.sprite + $0.sprite.zone + "\($0.sprite.frames)" })|\(staticKey)") { [self] in
            drops.filter { $0.frames == 2 }.compactMap { p in
                strip.flipbook(clock: home, count: 2, z: 8.4) { f in (p.name, f, p.x, p.y - f % 2) }
            }
        }

        // Home: the hen, and with no record acted out, the calm Jeb, Blue and pup.
        let hat = looks.contains { $0.id == "sundayhat" }
        strip.part("home", key: "\(m.lead != nil)|\(night)|\(farm.upgrades.sorted())|\(m.chasing)|\(hat)|\(g.jebX)") { [self] in
            if m.lead != nil { scene.homeRest() }
            return homeLayers(farm: farm, lead: m.lead != nil, night: night, chasing: m.chasing, clock: home, hat: hat)
        }

        // The one Jeb and Blue, from the lead's record, by the same rules a camp's Jeb and Blue had.
        if let r = m.lead, let clock = m.leadClock {
            let ck = "\(clock.frame0)|\(Int(clock.at * 10))|\(clock.period)|\(clock.frozen)"
            let nap = looks.contains { $0.id == "nap" }, chair = farm.upgrades.contains("chair")
            strip.part("jeb", key: "\(ck)|\(jebSpriteFor(r, night: night))|\(r.truck != nil)|\(nap)|\(hat)|\(chair)|\(r.gated)|\(r.pose)|\(night)|\(g.jebX)") { [self] in
                cast.jebLayers(r, night: night, nap: nap, hat: hat, chair: chair, clock: clock)
            }
            let blueKey = "\(ck)|\(r.dogRun)|\(r.act)|\(r.pose)|\(r.mood)|\(r.truck?.dog ?? false)|\(r.truck != nil)|\(r.visit?.phase ?? "")|\(r.visit?.kind ?? "")|\(r.fx.sorted())|\(night)|\(r.event?.id ?? "")|\(r.event.map { restOf(id: $0.id, t: $0.t, dur: $0.dur) == nil ? -1 : $0.t } ?? 0)|\(g.blueX)"
            strip.part("blue", key: blueKey) { [self] in cast.blueLayers(r, night: night, clock: clock) }
            if farm.upgrades.contains("pup") {
                strip.part("pup", key: blueKey) { [self] in cast.pupLayers(r, night: night, clock: clock) }
            } else {
                strip.clear("pup")
            }
            // The still's fire and steam while Jeb runs a command.
            strip.part("fire", key: "\(ck)|\(fire)|\(g.stillX)") { [self] in
                guard fire else { return [] }
                return [strip.flipbook(clock: clock, count: 2, z: 9) { f in ("fire", f, g.stillX + 3, GROUND - 6) },
                        strip.flipbook(clock: clock, count: 2, z: 9) { f in ("steam", f, g.stillX + 7, 0) }].compactMap { $0 }
            }
            // A visitor on the lane.
            let visitKey = r.visit.map { v in "\(v.kind).\(v.facing).\(v.phase).\(v.x).\(Int(r.at))" } ?? ""
            strip.part("visit", key: "\(ck)|\(visitKey)|\(g.blueX)") { [self] in strip.visitLayers(r, clock: clock, anchors: g.anchors) }
        } else {
            for name in ["jeb", "blue", "pup", "fire", "visit"] { strip.clear(name) }
        }
        // His bubble: the story's line, else the record's own while he is talking.
        let talking = m.lead?.showsBubble(now: now) ?? false
        let said = m.storyLine ?? (talking ? m.lead?.line : nil)
        strip.part("bubble", key: "\(said ?? "")|\(m.storyLine == nil ? (m.lead?.dim ?? false) : false)|\(g.jebX)") { [self] in
            said.map { strip.bubble($0, jebX: g.jebX, dim: m.storyLine == nil && (m.lead?.dim ?? false)) } ?? []
        }

        // The happenings at the farm.
        let eventKey = m.events.map { "\($0.event.id).\($0.event.dur).\($0.event.v).\(Int($0.wall - Double($0.event.t) * 500))/\($0.clock.period)" }.joined(separator: ",")
        strip.part("events", key: "\(eventKey)|\(g.houseX)") { [self] in
            m.events.flatMap { e in
                strip.eventLayers(e.event, clock: e.clock, wall: e.wall, anchors: g.anchors) {
                    let list = e.event.sprites.map { s in (sprite: s, art: e.event.custom.first { $0.id == s.sprite }) }
                    return self.dropLayers(list, clock: e.clock, statics: true, avoid: [])
                }
            }
        }

        // The trucks on the road, and the truck warming up at the house.
        let truckKey = m.trucks.map { "\($0.token).\($0.truck.load).\($0.truck.dog).\($0.truck.sputter > 0).\(Int(($0.wall - Double($0.truck.t) * 500) / 250))" }.joined(separator: ",")
        strip.part("trucks", key: "\(truckKey)|\(m.puff != nil)|\(g.houseX)") { [self] in
            var out = m.trucks.flatMap { strip.truckLayers($0.truck, clock: $0.clock, wall: $0.wall, houseX: g.houseX) }
            if let puff = m.puff, m.trucks.isEmpty {
                let x0 = g.houseX + 4
                if let t = strip.flipbook(clock: puff, count: 2, z: 12, { f in ("truck-empty", f, x0, BOTTOM - 22) }) { out.append(t) }
                if let d = strip.flipbook(clock: puff, count: 2, z: 12, { f in ("dust", f, x0 + truckW, BOTTOM - 8) }) { out.append(d) }
            }
            return out
        }
    }

    // MARK: The farm picture (composeScene's farm parts)

    private func paintFarm(_ c: inout Pix, farm: Farm, columns: [(id: String, count: Int)], looks: [Look], day: DayFlags, tarp: Bool, night: Bool,
                           drops: [(name: String, x: Int, y: Int, frames: Int)], groundhog: Bool = false, fire: Bool = false) {
        let g = band
        let white = art.colour("white"), yellow = art.colour("yellow"), cloud = art.colour("cloud")
        let soil = art.colour("soil")
        // Plots.
        for plot in g.plots {
            if plot.crop == "apples" {
                for i in 0..<4 {
                    let stage = farm.stage("apples", i)
                    art.stand(day.isPumpkin && stage >= 3 && i % 2 == 1 ? "apple-pumpkin" : "apple-\(stage)", into: &c, x: plot.x + i * 11, bottom: GROUND)
                }
            } else {
                c.rect(plot.x, GROUND - 2, plot.w, 3, soil)
                for i in 0..<8 { art.stand("\(plot.crop)-\(farm.stage(plot.crop, i))", into: &c, x: plot.x + 1 + i * 6, bottom: GROUND) }
            }
            art.text("\(cropLabels[plot.crop] ?? "") \(abbrevCount(farm.barn[plot.crop] ?? 0))", into: &c, x: plot.x + 2, y: ROAD_TOP, colour: white)
        }
        if farm.built.contains("fencedFields") {
            for plot in g.plots { var x = plot.x; while x + 8 <= plot.x + plot.w + 2 { art.stand("prop-fence", into: &c, x: x, bottom: GROUND + 3); x += 8 } }
        }
        // The stack.
        if let stackX = g.stackX {
            for (i, column) in columns.enumerated() {
                let x = stackX + i * BandLayout.stackStep
                let height = column.count >= 10 ? 3 : column.count >= 3 ? 2 : column.count >= 1 ? 1 : 0
                for level in 0..<height { art.blit(STACK_ICONS[column.id] ?? "icon-lumber", into: &c, x: x + 1, y: GROUND - 8 - level * 8) }
                art.text(column.count > 99 ? "99+" : String(column.count), into: &c, x: x, y: ROAD_TOP, colour: cloud)
            }
            if farm.built.contains("smokehouse") { art.stand("prop-smokehouse", into: &c, x: stackX + columns.count * BandLayout.stackStep + 2, bottom: FOOT) }
        }
        // The quilt's rail (its squares are their own part).
        if let line = quiltLine(farm: farm) { c.rect(line.x0 - 2, 4, line.n * 6 + 3, 1, art.colour("wood_dark")) }
        // The sign, the pumpkin, the second still.
        if let signX = g.signX {
            art.stand(farm.upgrades.contains("coat") ? "sign-coat" : night ? "sign-night" : "sign", into: &c, x: signX, bottom: FOOT)
            if day.isPumpkin { art.stand("prop-pumpkin", into: &c, x: signX - 9, bottom: FOOT) }
            if let miniX = g.miniX { art.standHalf("still", into: &c, x: miniX, bottom: GROUND) }
        }
        // The house and its fittings.
        art.stand("house\(farm.upgrades.contains("coat") ? "-coat" : "")\(night ? "-night" : "")", into: &c, x: g.houseX, bottom: FOOT)
        if farm.upgrades.contains("mailbox") { art.stand("prop-mailbox", into: &c, x: g.houseX + 2, bottom: FOOT) }
        if day.isChristmas { art.stand("prop-xmas", into: &c, x: g.houseX - 14, bottom: FOOT) }
        if groundhog { art.stand("groundhog", into: &c, x: g.houseX - 11, bottom: FOOT) }
        // The still (under a tarp while the revenuer is about) and its embers.
        let worm = farm.built.contains("copperWorm"), keg = farm.built.contains("thumpKeg")
        art.stand(tarp ? "still-tarp" : worm ? "still-worm" : keg ? "still-keg" : "still", into: &c, x: g.stillX, bottom: GROUND)
        if worm && keg && !tarp { art.stand("prop-keg", into: &c, x: g.stillX + 28, bottom: GROUND) }
        if !fire { art.stand("embers", into: &c, x: g.stillX + 3, bottom: GROUND) }
        // The jars on the shelf and the cash in hand, on the road under the still.
        var x = g.stillX + 2
        if farm.jars > 0 {
            art.blit("icon-jar", into: &c, x: x, y: bandHeight - 8)
            x += 10 + art.text("x\(farm.jars)", into: &c, x: x + 10, y: ROAD_TOP, colour: white) + 4
        }
        let cash = "$\(abbrevCount(farm.cash))"
        if x + 10 + textWidth(cash) <= g.houseX + 40 {
            art.blit("icon-cash", into: &c, x: x, y: bandHeight - 8)
            art.text(cash, into: &c, x: x + 10, y: ROAD_TOP, colour: white)
        }
        _ = yellow
        // The little things that stand still (drawLooks), kept out of Jeb's head.
        paintLooks(&c, looks: looks)
        // The drops' decor and structures that stand still.
        for p in drops { art.blit(p.name, into: &c, x: p.x, y: p.y, avoid: [band.jebHead]) }
    }

    /// The clothesline's place (drawQuilt): its left x and how many squares fit.
    func quiltLine(farm: Farm) -> (x0: Int, n: Int)? {
        let g = band
        guard let signX = g.signX else { return nil }
        let left = g.stackX.map { $0 - 2 } ?? g.plotsEnd + 2, right = signX - 4
        let n = min(10, (right - left - 2) / 6)
        guard n >= 1 else { return nil }
        return (g.stackX != nil ? left + 2 : right - n * 6, n)
    }

    private func tintPix(_ c: inout Pix, _ rgb: (Int, Int, Int)) {
        // The festival: the farm a quarter of the way toward the day's colour (the backdrop is tinted with it).
        for i in c.px.indices where c.px[i] != 0 {
            let p = c.px[i]
            let r = (Int(p & 255) * 3 + rgb.0) >> 2, gg = (Int(p >> 8 & 255) * 3 + rgb.1) >> 2, b = (Int(p >> 16 & 255) * 3 + rgb.2) >> 2
            c.px[i] = word(r, gg, b)
        }
    }

    // MARK: Looks

    private var lookAvoid: [Box] { [band.jebHead] }

    private func paintLooks(_ c: inout Pix, looks: [Look]) {
        let g = band, hx = g.houseX, yx = g.yx, avoid = lookAvoid
        let wood = art.colour("wood_dark")
        func pole(_ x: Int, _ y: Int, _ h: Int) { for yy in y..<(y + h) where !avoid.contains(where: { $0.has(x, yy) }) { c.dot(x, yy, wood) } }
        for look in looks {
            switch look.id {
            case "washday":
                pole(yx, 22, 18); pole(yx + 13, 22, 18)
                for x in yx...(yx + 13) where !avoid.contains(where: { $0.has(x, 23) }) { c.dot(x, 23, wood) }
                art.blit("laundry-shirt", into: &c, x: yx + 1, y: 24, avoid: avoid)
                art.blit("laundry-overalls", into: &c, x: yx + 7, y: 24, avoid: avoid)
            case "deer":
                let reach = max(0, g.blueX - 16 - yx)
                art.stand("deer", into: &c, x: yx + look.n * reach / 7, bottom: GROUND + 1, avoid: avoid)
            case "woodpile":
                art.stand("woodpile-\(max(1, min(4, look.n)))", into: &c, x: hx + 29, bottom: FOOT, avoid: avoid)
            case "garden": art.stand("garden-\(max(0, min(3, look.n)))", into: &c, x: hx + 10, bottom: FOOT, avoid: avoid)
            case "birdhouse": art.blit("birdhouse", into: &c, x: hx, y: 16, avoid: avoid)
            case "cardinal": art.stand("cardinal", into: &c, x: hx + 12, bottom: 9, avoid: avoid)
            case "rainbow": art.blit("rainbow", into: &c, x: max(2, (g.plotsEnd >> 1) - 16), y: 6, avoid: avoid)
            case "puddles":
                for x in [14, width >> 2, width >> 1] { art.blit("puddle", into: &c, x: min(x, width - 10), y: bandHeight - 2, avoid: avoid) }
            case "lunch": art.blit("lunch", into: &c, x: hx + 32, y: 22, avoid: avoid)
            case "porchlight": art.blit("porch-light", into: &c, x: hx + 29, y: 17, avoid: avoid)
            case "postcard": art.blit("postcard", into: &c, x: hx + 2, y: 22, avoid: avoid)
            default: break
            }
        }
    }

    /// The looks that move with the frame, each its own flipbook.
    private func movingLooks(_ looks: [Look], clock: FrameClock, starClock: FrameClock?) -> [CALayer] {
        let g = band, hx = g.houseX, yx = g.yx
        var out: [CALayer] = []
        func add(_ l: CALayer?) { if let l { out.append(l) } }
        // A flipbook kept out of Jeb's head: the sprite is drawn into a small Pix per frame when it reaches the box.
        for look in looks {
            switch look.id {
            case "creek": add(strip.flipbook(clock: clock, count: 2, z: 8.2) { f in ("creek", f, yx, GROUND) })
            case "fisher": add(strip.flipbook(clock: clock, count: 2, z: 8.3) { f in ("fisher", f, yx + 1, GROUND + 1 - 13) })
            case "woodpile": add(strip.flipbook(clock: clock, count: 8, z: 8.3) { f in ("axe-stump", f % 8 == 0 ? 1 : 0, hx + 42, FOOT - 11) })
            case "bluebird": add(strip.flipbook(clock: clock, count: 2, z: 8.3) { f in ("bluebird", f, hx, 12) })
            case "owl": add(strip.flipbook(clock: clock, count: 7, z: 8.3) { f in ("owl", f % 7 == 0 ? 1 : 0, hx + 3, 14 - 11) })
            case "butterflies":
                let room = max(8, g.plotsEnd - 12)
                for i in 0..<3 {
                    add(strip.flipbook(clock: clock, count: lcm(room / gcd(room, 2), 4), z: 8.3) { f in ("butterfly", f + i, 4 + ((i * 41 + f * 2) % room), 12 + ((i * 5 + f) % 4) * 2) })
                }
            case "leaves":
                let room = max(8, g.blueX - 8)
                for i in 0..<7 {
                    add(strip.flipbook(clock: clock, count: 14, z: 8.3) { f in
                        let y = 5 + ((scatter(i, 9) % 30) + f * 2) % 28
                        let x = 3 + scatter(i, 3) % room
                        return g.jebHead.hits(Box(x: x, y: y, w: 3, h: 3)) ? nil : ("drift-leaf-\(i % 3)", 0, x, y)
                    })
                }
            case "snow":
                let room = max(8, width - 8)
                for i in 0..<16 {
                    add(strip.flipbook(clock: clock, count: 18, z: 8.3) { f in
                        let x = 2 + scatter(i, 6) % room, y = (scatter(i, 4) + f * 2) % 36
                        return g.jebHead.hits(Box(x: x, y: y, w: 3, h: 3)) ? nil : ("drift-flake", 0, x, y)
                    })
                }
            case "star":
                // The shooting star's streak: ten ticks across, from the session's own count.
                if let sc = starClock {
                    let left = look.n
                    add(strip.flipbook(clock: FrameClock(frame0: 0, at: sc.at, period: tickSeconds, frozen: false), count: 40, z: 2.6) { f in
                        let ticksLeft = left - f
                        guard ticksLeft > 0 else { return nil }
                        let p = max(0, 10 - ticksLeft)
                        return ("star-streak", 0, max(4, g.blueX - 100) + p * 5, 2 + p)
                    })
                }
            case "mug", "coffee": add(strip.flipbook(clock: clock, count: 2, z: 8.3) { f in ("mug", f, hx + 10, 22) })
            case "cake": add(strip.flipbook(clock: clock, count: 2, z: 8.3) { f in ("cake", f, hx + 21, 28) })
            default: break
            }
        }
        return out
    }

    // MARK: Drops (the creative sprites: placement rule 9.9)

    private func dropBox(_ zone: String) -> (x0: Int, x1: Int, top: Int?, bottom: Int?) {
        let g = band
        switch zone {
        case "sky": return (4, max(12, g.blueX - 8), 13, nil)
        case "yard": return (max(g.plotsEnd + 1, g.signX != nil ? g.midEnd + 4 : g.plotsEnd + 2), g.blueX - 6, nil, FOOT)
        case "porch": return (g.houseX + 2, g.width - 2, nil, FOOT)
        case "field": return (2, max(10, g.plotsEnd - 2), nil, GROUND)
        default: return (g.signX ?? g.plotsEnd + 2, g.stillX - 4, nil, BOTTOM - 1)
        }
    }

    private var reserved: [Box] {
        let g = band
        var out = [Box(x: g.jebX - 1, y: 0, w: 22, h: bandHeight), Box(x: g.blueX, y: 28, w: 20, h: bandHeight - 28), Box(x: g.stillX, y: 0, w: 40, h: bandHeight)]
        if let signX = g.signX {
            out.append(Box(x: signX - 1, y: 0, w: BandLayout.signW + 2, h: bandHeight))
            let left = g.stackX ?? g.plotsEnd
            out.append(Box(x: left - 2, y: 0, w: signX - left + 2, h: g.stackX != nil ? bandHeight : 13))
        }
        return out
    }

    /// Where each placed sprite stands: the first free spot from a start hashed by its name.
    func placements(_ list: [(sprite: DropSprite, art: DropArt?)], taken: inout [Box]) -> [(name: String, x: Int, y: Int, frames: Int)] {
        placeDrops(list, art: art, box: dropBox, avoid: [band.jebHead] + reserved, taken: &taken)
    }

    private var placedTaken: [Box] = []

    /// Two-frame drop sprites: each bobs a pixel and turns its frame with the clock.
    func dropLayers(_ list: [(sprite: DropSprite, art: DropArt?)], clock: FrameClock, statics: Bool, avoid: [Box]) -> [CALayer] {
        var taken = placedTaken
        return placements(list, taken: &taken).compactMap { p in
            strip.flipbook(clock: clock, count: 2, z: 8.4) { f in (p.name, p.frames == 2 ? f : 0, p.x, p.y - (p.frames == 2 ? f % 2 : 0)) }
        }
    }

    // MARK: Home: the hen, and with no session the calm Jeb, Blue and pup (the lead's are drawn by Cast.swift)

    private func homeLayers(farm: Farm, lead: Bool, night: Bool, chasing: Bool, clock: FrameClock, hat: Bool) -> [CALayer] {
        let g = band
        var out: [CALayer] = []
        if !lead {
            let (jeb, blue) = scene.homeLayers(in: strip, jebX: g.jebX, blueX: g.blueX, chair: farm.upgrades.contains("chair"))
            out.append(contentsOf: jeb)
            out.append(contentsOf: blue)
            if hat { out.append(strip.sprite("hat-feather", x: g.jebX + 12, y: 0, z: 10.5)) }
        }
        if farm.upgrades.contains("hen") && !night && !chasing {
            if let hen = strip.flipbook(clock: clock, count: 16, z: 10, { f in
                let wander = abs((f / 2) % 8 - 4)
                return ("hen", f, max(0, g.blueX - 14 - wander * 2), FOOT - 10)
            }) { out.append(hen) }
        }
        if !lead && farm.upgrades.contains("pup") { out.append(strip.standing("pup", x: g.blueX - 14, bottom: FOOT, z: 10)) }
        return out
    }
}

func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? max(1, abs(a)) : gcd(b, a % b) }
func lcm(_ a: Int, _ b: Int) -> Int { max(1, a / gcd(a, b) * b) }

/// Where each placed sprite stands in a strip: the first free spot from a start hashed by its name, inside the zone's box,
/// clear of `avoid` and of what is already `taken` (placement rule 9.9; the homestead's and a camp's own).
func placeDrops(_ list: [(sprite: DropSprite, art: DropArt?)], art: Art, box boxOf: (String) -> (x0: Int, x1: Int, top: Int?, bottom: Int?),
                avoid: [Box], taken: inout [Box]) -> [(name: String, x: Int, y: Int, frames: Int)] {
    var out: [(name: String, x: Int, y: Int, frames: Int)] = []
    for (i, one) in list.enumerated() {
        let name: String
        if let a = one.art { name = art.useArt(a) } else if let builtin = dropSpriteNames[one.sprite.sprite] { name = builtin } else { continue }
        guard art.has(name) else { continue }
        let w = art.width(name), h = art.height(name)
        let box = boxOf(one.sprite.zone)
        let span = box.x1 - box.x0 - w
        guard span >= 0 else { continue }
        let y = box.bottom.map { $0 - h } ?? (box.top ?? 13)
        let start = Int(hashOf("\(one.sprite.sprite)\(i)") % UInt32(span + 1))
        var k = 0
        while k <= span {
            let x = box.x0 + (start + k) % (span + 1)
            let r = Box(x: x, y: y, w: w, h: h)
            if !avoid.contains(where: { $0.hits(r) }) && !taken.contains(where: { $0.hits(r) }) {
                taken.append(r)
                out.append((name, x, y, one.sprite.frames))
                break
            }
            k += 3
        }
    }
    return out
}
