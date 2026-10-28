// The story: which one place the scene shows, and the trips between places. Pure
// model, no drawing: every window and screen renders from the one Story the App
// owns (main.swift), driven by the wall clock, so they all agree. While the scenes
// are paused it still moves on by the clock; a scene that resumes reads the current
// state and never replays a trip.
//
//   places   the homestead (the default), and a camp for each live session
//   home     he acts out the busiest session's record (the lead, held while it talks)
//   calls    the only reasons to leave: each has a priority and a 15 minute life
//   pacing   a home spell before a call may send him (by priority), a few trips an hour
//   visits   they last while the reason does, between 1 and 3 minutes, then home
//   trips    leaving beat, the road (sometimes a wayside encounter), arrival beat
//   thread   one running storyline a day from a fixed pool, one step a trip
//
// No model call and no network: every line is built from the fixed vocabulary in
// this file. The only things taken from a session are its token (for the place
// name), what its record has on, and when it last spoke; the thread state file
// holds the day's thread id and step and nothing else.

import Foundation

enum Place: Equatable {
    case home, camp(String)
    var camp: String? { if case .camp(let t) = self { return t } else { return nil } }
}
enum Reason { case newArea, areaAgain, event, hands, longWork, ship, weather, errand, ended, night, homeward }
enum Priority: Int, Comparable {
    case low, medium, high
    static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
}

/// A reason to go and see a session. The area calls need the record's area key (see `areaKey`).
enum CallKind {
    case newArea, areaAgain, event, hands, longWork, ship, weather, errand
    var priority: Priority {
        switch self {
        case .newArea: return .high
        case .areaAgain, .event: return .medium
        case .hands, .longWork, .ship, .weather, .errand: return .low
        }
    }
    var reason: Reason {
        switch self {
        case .newArea: return .newArea
        case .areaAgain: return .areaAgain
        case .event: return .event
        case .hands: return .hands
        case .longWork: return .longWork
        case .ship: return .ship
        case .weather: return .weather
        case .errand: return .errand
        }
    }
}

struct Call {
    let kind: CallKind, token: String, at: Date, seq: Int
    var priority: Priority { kind.priority }
}

/// Story durations in seconds, divided by JEB_STORY_SCALE (measuring only: a scripted day in minutes).
let storyScale = max(1, Double(env["JEB_STORY_SCALE"] ?? "") ?? 1)
private func secs(_ s: Double) -> Double { s / storyScale }
let minStay = secs(60), capStay = secs(180), defaultStay = secs(90)
let spellLow = secs(900), spellMedium = secs(300), spellHigh = secs(60)
let callLife = secs(900), tripWindow = secs(3600), tripLimit = 4, longWorkSeconds = secs(1800)
let leaveSeconds = secs(5), roadSeconds = secs(12), arriveSeconds = secs(6)
let errandsPerDay = 2, errandHours = [10, 15]
let areaAbsence: TimeInterval = 3 * 86400

private func spell(_ p: Priority) -> Double { p == .high ? spellHigh : p == .medium ? spellMedium : spellLow }
/// A call lasts `callLife` past the home spell its priority needs, so one raised on arrival home still gets its turn.
private func expiry(_ c: Call) -> Date { c.at.addingTimeInterval(spell(c.kind.priority) + callLife) }

struct Trip {
    let id: Int
    let from: Place, to: Place
    let start: Date
    let reason: Reason
    let leave: String, road: String, arrive: String
    let wayside: String?
    var areaLines = false     // the arrival line is one of the camp's area beats
    var leaveEnd: Date { start.addingTimeInterval(leaveSeconds) }
    var end: Date { leaveEnd.addingTimeInterval(roadSeconds) }
    /// The road beat's line is up for the middle third of the walk.
    var lineFrom: Date { leaveEnd.addingTimeInterval(roadSeconds * 0.375) }
    var lineTo: Date { leaveEnd.addingTimeInterval(roadSeconds * 0.667) }
}

enum StoryKind { case home, camp, road }
enum StoryPhase { case stay, leave, road, arrive }

/// What the scenes draw now: one place, the cast's story line, and a few flags.
struct StoryView {
    var kind = StoryKind.home
    var token: String?          // the camp's session
    var phase = StoryPhase.stay
    var line: String?           // the story line up now (leaving, road, arrival beat)
    var goodbye = false         // the leaving beat is a goodbye to an ended session
    var acting: String?         // at home: the session whose record he acts out (the lead)
    var trip: Trip?
    var queue = 0               // calls waiting
    var key: String {
        switch kind {
        case .home: return "home"
        case .camp: return "camp:\(token ?? "")"
        case .road: return "road:\(trip?.id ?? 0)"
        }
    }
    var signature: String { "\(key)|\(phase)|\(line ?? "")|\(goodbye)|\(acting ?? "")" }
    var kindName: String { kind == .home ? "home" : kind == .camp ? "camp" : "road" }
}

/// What a session's record had on at the last look, for the edges that make calls.
private struct Track { var event = false, hands = false, truck = false, weather = false, busySince: Date?, longFired = false, area: String? }

func isBusy(_ r: LiveRecord) -> Bool { r.busy || r.pose != "none" }
func isSomething(_ r: LiveRecord) -> Bool { r.event != nil || r.truck != nil || r.visit != nil }
func isActive(_ r: LiveRecord) -> Bool { isBusy(r) || isSomething(r) }

final class Story {
    var onChange: (() -> Void)?
    private(set) var place = Place.home
    private var arrivedAt: Date
    private(set) var calls: [Call] = []
    private(set) var acting: String?
    private var tracks: [String: Track] = [:]
    private var last: [String: LiveRecord] = [:]   // each session's last record (a goodbye plays it once the session is gone)
    private var live: [String: LiveRecord] = [:]
    private var trip: Trip?
    private var tripCall: Call?                    // the call the trip in flight answers
    private var visitCall: Call?                   // the call this visit answers (none: a seeded place, a goodbye)
    private var lastTrip: Trip?
    private var tripCount = 0
    private var tripStarts: [Date] = []            // when each outbound trip started (the hourly limit)
    private var callSeq = 0
    private var errands: (day: String, n: Int) = ("", 0)
    private var areaLast: [String: Date] = [:]     // when each area was last worked (areas data: see noteAreas)
    private var areas = Areas()                    // the areas read from the store (see noteAreas)
    private var thread: (day: String, id: String, step: Int)?
    private let path: String?
    private var timer: Timer?
    private var started = false
    private var lastSignature = ""
    private let seed = env["JEB_PLACE"]

    init(now: Date = nowDate()) {
        arrivedAt = now
        if let p = env["JEB_STORY_PATH"] { path = p } else { path = env["JEB_BENCH"] == nil ? jebHome + "/story.json" : nil }
        load()
    }

    // MARK: Driving

    /// The store changed: take the records in and decide. The caller applies the scenes after this.
    func ingest(live: [String: LiveRecord], now: Date = nowDate()) {
        self.live = live
        sync(now)
        reschedule(now)
        lastSignature = view(now: now).signature
    }

    /// The minute, or a deadline: decide again; the scenes are told if what they draw changed.
    func tick() {
        let now = nowDate()
        sync(now)
        reschedule(now)
        let sig = view(now: now).signature
        if sig != lastSignature { lastSignature = sig; onChange?() }
    }

    /// The areas read from the store, before the next ingest: each area's last worked day (`seen`) is when it was last
    /// worked, and a key with no area yet raises no call. One made and worked today, and not yet visited, is new.
    func noteAreas(_ read: Areas) {
        areas = read
        let today = dateKeyOf(nowDate())
        for (key, area) in read {
            if area.day == today && area.seen == today { continue }
            // The mod moves `seen` to today as a session starts there, often before its record arrives: an area
            // already known keeps its earlier day, so a return after a long absence still reads as one.
            if area.seen == today && areaLast[key] != nil { continue }
            if let seen = dateOfKey(area.seen) { areaLast[key] = max(areaLast[key] ?? seen, seen) }
        }
    }

    /// The look of a camp whose record names this area key, when the area is read (else the camp is plain).
    func theme(forArea key: String?) -> AreaTheme? { key.flatMap { k in areas[k].map { AreaTheme(key: k, area: $0) } } }

    var queueCount: Int { calls.count }
    func record(of token: String) -> LiveRecord? { live[token] ?? last[token] }
    var tripCountToday: Int { thread?.step ?? 0 }
    /// Measuring only: the state for a fixture's or a scripted day's check.
    var debug: String {
        let now = nowDate(), v = view(now: now)
        var to = "-"
        if let t = v.trip { if case .camp(let c) = t.to { to = c } else { to = "home" } }
        let waiting = calls.map { "\($0.kind)@\($0.token)" }.joined(separator: ",")
        let areaKey = (v.trip?.to ?? place).camp.flatMap { areaOf(.camp($0))?.key } ?? "-"
        return "place=\(v.kind == .home ? "home" : v.kind == .camp ? "camp:\(v.token ?? "")" : "road") phase=\(v.phase) queue=\(waiting) to=\(to) reason=\(v.trip.map { "\($0.reason)" } ?? "-") acting=\(v.acting ?? "-") step=\(thread?.step ?? -1) area=\(areaKey) arealines=\(v.trip?.areaLines == true ? 1 : 0) line=\(v.line ?? "-")"
    }

    // MARK: The view

    func view(now: Date) -> StoryView {
        var v = StoryView()
        v.queue = calls.count
        func set(_ p: Place) { if case .camp(let t) = p { v.kind = .camp; v.token = t } else { v.kind = .home; v.acting = acting } }
        if let t = trip {
            v.trip = t
            if now < t.leaveEnd {
                set(t.from); v.phase = .leave; v.line = t.leave; v.goodbye = t.reason == .ended
            } else if now < t.end {
                v.kind = .road; v.phase = .road
                if now >= t.lineFrom && now < t.lineTo { v.line = t.road }
            } else {
                set(t.to); v.phase = .arrive; v.line = t.arrive
            }
            return v
        }
        set(place)
        if let t = lastTrip, now < t.end.addingTimeInterval(arriveSeconds) { v.phase = .arrive; v.line = t.arrive; v.trip = nil }
        return v
    }

    // MARK: Rules

    private var shown: [String: LiveRecord] = [:]
    private func night() -> Bool { isNightHour(Int(hourNow())) }

    private func sync(_ now: Date) {
        shown = live.filter { $0.value.isCurrent(now: now) && !$0.value.hidden }
        for (t, r) in shown { last[t] = r }
        if let t = trip, now >= t.end { arrive(t, now) }
        if !started { started = true; seedPlace(now) }
        track(now)
        pruneCalls(now)
        updateLead()
        errandCall(now)
        if trip == nil, let (to, reason, call) = decide(now) { begin(to, reason, call, now) }
        let keep = Set(shown.keys).union([place, trip?.from, trip?.to].compactMap { p -> String? in if case .camp(let t)? = p { return t } else { return nil } })
        for t in Array(last.keys) where !keep.contains(t) { last[t] = nil }
    }

    private func visiting(_ t: String) -> Bool {
        if place == .camp(t) { return true }
        if let trip, trip.to == .camp(t) { return true }
        return false
    }

    /// The session's area key, when its record carries one.
    private func areaKey(_ token: String, _ r: LiveRecord) -> String? { r.area }

    /// The read area of the camp a place is, from the session's record (live, else its last).
    private func areaOf(_ p: Place) -> (key: String, area: Area)? {
        guard case .camp(let t) = p, let key = record(of: t)?.area, let area = areas[key] else { return nil }
        return (key, area)
    }

    /// A call joins on an edge (a thing turning on), once per kind and session, never for the place he is at.
    private func raise(_ kind: CallKind, _ t: String, _ now: Date) {
        guard !visiting(t), !calls.contains(where: { $0.kind == kind && $0.token == t }) else { return }
        callSeq += 1
        calls.append(Call(kind: kind, token: t, at: now, seq: callSeq))
    }

    /// Finds the edges in each record: a happening, hands, a truck, test weather turning on; a long busy stretch; an area seen first, or after a long absence.
    private func track(_ now: Date) {
        for t in Array(tracks.keys) where shown[t] == nil { tracks[t] = nil }
        for t in shown.keys.sorted() {
            let r = shown[t]!
            var tr = tracks[t] ?? Track()
            if r.event != nil && !tr.event { raise(.event, t, now) }
            if !r.hands.isEmpty && !tr.hands { raise(.hands, t, now) }
            if r.truck != nil && !tr.truck { raise(.ship, t, now) }
            if r.weather != nil && !tr.weather { raise(.weather, t, now) }
            tr.event = r.event != nil; tr.hands = !r.hands.isEmpty; tr.truck = r.truck != nil; tr.weather = r.weather != nil
            if isBusy(r) {
                if tr.busySince == nil { tr.busySince = now }
                if !tr.longFired, now.timeIntervalSince(tr.busySince!) >= longWorkSeconds { tr.longFired = true; raise(.longWork, t, now) }
            } else {
                tr.busySince = nil; tr.longFired = false
            }
            if let key = areaKey(t, r), areas[key] != nil {
                if tr.area != key {
                    if let seen = areaLast[key] { if now.timeIntervalSince(seen) >= areaAbsence { raise(.areaAgain, t, now) } } else { raise(.newArea, t, now) }
                    tr.area = key
                }
                areaLast[key] = now
            }
            tracks[t] = tr
        }
    }

    /// Whether a call's reason is still on in the session's record (a call for a thing that has gone is dropped).
    private func stillOn(_ k: CallKind, _ r: LiveRecord) -> Bool {
        switch k {
        case .event: return r.event != nil
        case .hands: return !r.hands.isEmpty
        case .ship: return r.truck != nil
        case .weather: return r.weather != nil
        case .longWork: return isBusy(r)
        case .newArea, .areaAgain, .errand: return true
        }
    }

    /// Drops calls that waited their life out, or whose session is gone or is the place he is at. A happening, a ship, hands
    /// or weather is news he goes to hear about after it is over; only a long work stretch ends with the work.
    private func pruneCalls(_ now: Date) {
        calls.removeAll { c in
            guard let r = shown[c.token], !visiting(c.token), now < expiry(c) else { return true }
            return c.kind == .longWork && !stillOn(c.kind, r)
        }
    }

    /// At home he acts out the busiest session's record; the lead holds while busy or talking.
    private func updateLead() {
        guard place == .home else { return }
        acting = pickLead(shown, current: acting, now: nowDate())
    }

    /// A step of the day's thread that needs a place: at most two a day, at set hours, when a session is live and the long home spell is up.
    private func errandCall(_ now: Date) {
        guard place == .home, trip == nil, !shown.isEmpty, !night() else { return }
        let day = dateKeyOf(now)
        if errands.day != day { errands = (day, 0) }
        guard errands.n < errandsPerDay, Int(hourNow()) >= errandHours[errands.n], now.timeIntervalSince(arrivedAt) >= spellLow,
              !calls.contains(where: { $0.kind == .errand }) else { return }
        let toks = shown.keys.sorted()
        raise(.errand, toks[Int(hashOf("\(day)|errand|\(errands.n)") % UInt32(toks.count))], now)
        if calls.contains(where: { $0.kind == .errand }) { errands.n += 1 }
    }

    /// JEB_PLACE=home|<token> (fixtures and scripted days): where he starts, and how long ago he got there.
    private func seedPlace(_ now: Date) {
        guard let seed, !seed.isEmpty else { return }
        let since = Double(env["JEB_PLACE_SINCE"] ?? "")
        if seed == "home" {
            place = .home
            arrivedAt = now.addingTimeInterval(-(since ?? 0))
            acting = shown.keys.sorted().first
        } else {
            place = .camp(seed)
            arrivedAt = now.addingTimeInterval(-(since ?? 60))
        }
    }

    /// The call to answer now: the highest priority, first come first served, that the pacing allows. `direct` is a hop from one visit to
    /// the next call (medium or high only, no home spell); otherwise from home, after the spell its priority needs. Night: high calls only.
    private func nextCall(_ now: Date, direct: Bool) -> Call? {
        guard tripStarts.filter({ now.timeIntervalSince($0) < tripWindow }).count < tripLimit else { return nil }
        let stayed = now.timeIntervalSince(arrivedAt), isNight = night()
        let ok = calls.filter { c in
            if isNight && c.priority != .high { return false }
            return direct ? c.priority >= .medium : stayed >= spell(c.priority)
        }
        return ok.min { ($1.priority, $0.seq) < ($0.priority, $1.seq) }
    }

    /// Whether the visit's reason has run its course (a thing on lasts while it is on; the rest take the default stay).
    private func visitOver(_ t: String, _ r: LiveRecord, stayed: Double) -> Bool {
        if stayed >= capStay { return true }
        guard let c = visitCall, c.token == t else { return stayed >= defaultStay }
        switch c.kind {
        case .event, .hands, .ship, .weather: return !stillOn(c.kind, r)
        case .newArea, .areaAgain, .longWork, .errand: return stayed >= defaultStay
        }
    }

    private func decide(_ now: Date) -> (Place, Reason, Call?)? {
        let stayed = now.timeIntervalSince(arrivedAt)
        switch place {
        case .camp(let t):
            guard let r = shown[t] else { // ended: the goodbye, then home (or on to a call of medium or more)
                let next = nextCall(now, direct: true)
                return (next.map { .camp($0.token) } ?? .home, .ended, next)
            }
            guard stayed >= minStay else { return nil }
            if night() && visitCall?.priority != .high { return (.home, .night, nil) }
            guard visitOver(t, r, stayed: stayed) else { return nil }
            if let next = nextCall(now, direct: true) { return (.camp(next.token), next.kind.reason, next) }
            return (.home, .homeward, nil)
        case .home:
            guard let c = nextCall(now, direct: false) else { return nil }
            return (.camp(c.token), c.kind.reason, c)
        }
    }

    private func begin(_ to: Place, _ reason: Reason, _ call: Call?, _ now: Date) {
        if case .camp(let n) = to {
            calls.removeAll { $0.token == n }
            tripStarts.append(now)
        }
        tripStarts.removeAll { now.timeIntervalSince($0) >= tripWindow }
        tripCall = call
        tripCount += 1
        trip = makeTrip(from: place, to: to, reason: reason, now: now)
    }

    private func arrive(_ t: Trip, _ now: Date) {
        place = t.to
        arrivedAt = t.end
        lastTrip = t
        trip = nil
        visitCall = t.to == .home ? nil : tripCall
        tripCall = nil
        acting = nil
        if t.to == .home { updateLead() }
    }

    // MARK: Timer: one wake at the next deadline

    private func reschedule(_ now: Date) {
        timer?.invalidate()
        timer = nil
        guard fixedNow == nil, let at = nextWake(now) else { return }
        let t = Timer(timeInterval: max(0.05, at.timeIntervalSince(now) + 0.05), repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func nextWake(_ now: Date) -> Date? {
        var c: [Date] = []
        if let t = trip {
            c += [t.leaveEnd, t.lineFrom, t.lineTo, t.end]
        } else {
            if let t = lastTrip { c.append(t.end.addingTimeInterval(arriveSeconds)) }
            switch place {
            case .home:
                for k in calls { c += [expiry(k), arrivedAt.addingTimeInterval(spell(k.kind.priority))] }
                if !shown.isEmpty { c.append(arrivedAt.addingTimeInterval(spellLow)) }
                if let a = acting, let r = shown[a], !r.line.isEmpty { c.append(Date(timeIntervalSince1970: r.saidAt / 1000 + 8)) }
            case .camp:
                c += [arrivedAt.addingTimeInterval(minStay), arrivedAt.addingTimeInterval(defaultStay), arrivedAt.addingTimeInterval(capStay)]
                for k in calls { c.append(expiry(k)) }
            }
            if calls.count > 0 || place == .home, let oldest = tripStarts.min() { c.append(oldest.addingTimeInterval(tripWindow)) }
            for tr in tracks.values { if let b = tr.busySince, !tr.longFired { c.append(b.addingTimeInterval(longWorkSeconds)) } }
        }
        return c.filter { $0 > now }.min()
    }

    // MARK: Thread state (story.json: the day's thread id and step, and the date)

    private func load() {
        guard let path, let data = FileManager.default.contents(atPath: path), data.count < 1024,
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let day = d["d"] as? String, isDateKey(day), let id = d["id"] as? String, THREADS.contains(where: { $0.id == id }),
              let step = (d["step"] as? NSNumber)?.intValue, (0...CLOSED_STEP).contains(step) else { return }
        thread = (day, id, step)
    }

    private func persist() {
        guard let path, let t = thread else { return }
        let body = "{\"d\":\"\(t.day)\",\"id\":\"\(t.id)\",\"step\":\(t.step)}\n"
        let tmp = path + ".tmp"
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if dir == jebHome { chmod(dir, 0o700) } // the desktop's own state folder only
        guard FileManager.default.createFile(atPath: tmp, contents: Data(body.utf8), attributes: [.posixPermissions: 0o600]) else { return }
        rename(tmp, path) // one rename: a reader never sees half a file
    }

    // MARK: Making a trip

    private func makeTrip(from: Place, to: Place, reason: Reason, now: Date) -> Trip {
        let day = dateKeyOf(now)
        if thread?.day != day {
            let previous = thread?.id
            var i = Int(hashOf(day) % UInt32(THREADS.count))
            if THREADS[i].id == previous { i = (i + 1) % THREADS.count }
            thread = (day, THREADS[i].id, 0)
        }
        var th = thread!
        let def = THREADS.first { $0.id == th.id } ?? THREADS[0]
        let evening = Int(hourNow()) >= 17
        var step: StepDef
        if th.step >= CLOSED_STEP {
            step = CODA[tripCount % CODA.count]
        } else if th.step == 0 {
            step = def.open
        } else if to == .home && evening && th.step >= 2 && calls.isEmpty {
            step = def.close
            th.step = CLOSED_STEP - 1
        } else {
            step = def.mid[(th.step - 1) % def.mid.count]
        }
        th.step = min(CLOSED_STEP, th.step + 1)
        thread = th
        persist()

        let seed = hashOf("\(day)|\(th.id)|\(th.step)|\(tripCount)")
        let month = Calendar.current.component(.month, from: now)
        let toArea = areaOf(to)?.area
        let slots = Slots(place: name(of: to), from: name(of: from), carry: def.carry, tod: todWord(), season: seasonWord(month),
                          weather: weatherWord(seed: seed, month: month), dog: "Blue", reason: pick(REASONS[reason]!, seed))
        let wayside = seed % 3 == 0 ? pickWayside(seed: seed, night: night()) : nil
        let leave = reason == .ended ? expand(pick(GOODBYES, seed), slots) : expand(step.leave, slots)
        var road = wayside.map { expand(pick($0.lines, seed >> 3), slots) } ?? expand(step.road, slots)
        var arrive = expand(step.arrive, slots)
        var fromArea = false
        // A camp with a read area: the arrival is one of its beats, and the road (when no one is met on it) sometimes its lore.
        if reason != .ended, let a = toArea {
            if let l = fitLine(a.beats.map(\.line), seed >> 7) { arrive = l; fromArea = true }
            if wayside == nil, (seed >> 11) % 2 == 0, let l = fitLine(a.lore, seed >> 9) { road = l }
        }
        return Trip(id: tripCount, from: from, to: to, start: now, reason: reason, leave: leave, road: road, arrive: arrive, wayside: wayside?.sprite, areaLines: fromArea)
    }

    private func name(of p: Place) -> String {
        if case .camp(let t) = p { return areaOf(p)?.area.name ?? placeName(t) }
        return "home"
    }

    /// One of the lines, picked by the seed from those that wrap into two bubble lines at most; nil if none does.
    private func fitLine(_ lines: [String], _ seed: UInt32) -> String? {
        let fit = lines.filter { l in
            let w = bubbleLines(l, chars: 30)
            return w.count <= 2 && !(w.last?.hasSuffix("..") ?? true)
        }
        return fit.isEmpty ? nil : pick(fit, seed)
    }

    private func todWord() -> String {
        let h = Int(hourNow())
        return h < 5 || h >= 21 ? "tonight" : h < 11 ? "this mornin'" : h < 17 ? "this afternoon" : "this evenin'"
    }

    private func seasonWord(_ month: Int) -> String {
        (3...5).contains(month) ? "spring" : (6...8).contains(month) ? "summer" : (9...11).contains(month) ? "fall" : "winter"
    }

    /// Weather from what the sessions show (a storm, fog, wet ground), else a word for the season.
    private func weatherWord(seed: UInt32, month: Int) -> String {
        if shown.values.contains(where: { $0.event?.id == "storm" }) { return "stormy" }
        if shown.values.contains(where: { $0.event?.id == "fog" }) { return "foggy" }
        if shown.values.contains(where: { $0.wet }) { return "damp" }
        let words = [["frosty", "bitter", "gray"], ["damp", "clear", "breezy"], ["muggy", "hot", "clear"], ["crisp", "clear", "windy"]]
        let i = (3...5).contains(month) ? 1 : (6...8).contains(month) ? 2 : (9...11).contains(month) ? 3 : 0
        return words[i][Int(seed % 3)]
    }

    private func pickWayside(seed: UInt32, night: Bool) -> Wayside? {
        let ok = WAYSIDES.filter { night ? $0.night : $0.day }
        return ok.isEmpty ? nil : ok[Int((seed >> 5) % UInt32(ok.count))]
    }
}

// MARK: - Words

struct Slots { let place, from, carry, tod, season, weather, dog, reason: String }

func pick(_ list: [String], _ seed: UInt32) -> String { list[Int(seed % UInt32(list.count))] }

/// Fills the {slots} of a line.
func expand(_ template: String, _ s: Slots) -> String {
    var out = template
    for (k, v) in [("{reason}", s.reason), ("{place}", s.place), ("{from}", s.from), ("{carry}", s.carry), ("{tod}", s.tod),
                   ("{season}", s.season), ("{weather}", s.weather), ("{dog}", s.dog)] {
        out = out.replacingOccurrences(of: k, with: v)
    }
    return out
}

struct StepDef { let leave: String, road: String, arrive: String }
struct ThreadDef { let id: String, carry: String, open: StepDef, mid: [StepDef], close: StepDef }
struct Wayside { let sprite: String, day: Bool, night: Bool, lines: [String] }

/// After the thread has closed for the day: plain wanderings.
let CLOSED_STEP = 90

private func S(_ l: String, _ r: String, _ a: String) -> StepDef { StepDef(leave: l, road: r, arrive: a) }

let REASONS: [Reason: [String]] = [
    .newArea: ["Somethin' new yonder", "Never seen that holler", "A new trail's opened up"],
    .areaAgain: ["Been a spell since last", "Time I checked back in", "Ain't seen it in ages"],
    .event: ["Somethin's afoot yonder", "Heard a ruckus up there", "Reckon I best look in"],
    .hands: ["Hired hands are at it", "Help's arrived yonder", "Hands are workin' there"],
    .longWork: ["Been at it a long while", "Hard worker, that one", "Not a break in sight"],
    .ship: ["Truck's headed out", "A load's off to market", "Shippin' day yonder"],
    .weather: ["Skies are a-turnin'", "Rain's a-comin' yonder", "Weather's on the move"],
    .errand: ["Got an errand to run", "Errand's a-callin' me", "Need to run an errand"],
    .ended: ["That one's all done"],
    .night: ["Night's a-settlin' in", "Dark's comin' down", "The whippoorwills are up"],
    .homeward: ["Supper's a-waitin'", "My porch is callin'", "Time I headed home", "Home's callin' me"],
]

let GOODBYES = ["So long, {from}. Fine company.", "{from} has packed it in. Fare thee well.", "Wave goodbye, {dog}. That's {from} done.",
                "Fire's out at {from}. So long, friend."]

let WAYSIDES: [Wayside] = [
    Wayside(sprite: "deer", day: true, night: false, lines: ["A deer's watchin' me. I'm watchin' it.", "That doe don't scare easy."]),
    Wayside(sprite: "turkey", day: true, night: false, lines: ["Them turkeys own this road.", "Turkey crossin'. I'll wait."]),
    Wayside(sprite: "hen", day: true, night: false, lines: ["That hen's far from her coop.", "A loose hen. Not mine, I swear."]),
    Wayside(sprite: "groundhog", day: true, night: true, lines: ["Whistle pig says it's {season}.", "Whistle pig's out sunnin' himself."]),
    Wayside(sprite: "cardinal", day: true, night: false, lines: ["A cardinal's singin'. Good luck, that.", "Red bird on the fence. Fair omen."]),
    Wayside(sprite: "owl", day: false, night: true, lines: ["Hoot owl asks who walks so late.", "That owl knows my business."]),
    Wayside(sprite: "opal", day: true, night: false, lines: ["Miss Opal's wavin' from her gate.", "Miss Opal says tell {place} hello."]),
    Wayside(sprite: "cow", day: true, night: false, lines: ["A cow in the road. Moo to you too.", "Whose cow is that, I wonder."]),
    Wayside(sprite: "bear", day: true, night: true, lines: ["Bear! Easy now. He's gone.", "A black bear. We'll step around."]),
]

let CODA = [
    S("{reason}. Just stretchin' my legs.", "Nothin' like a walk in the {season}.", "Here I am. Nothin' much to report."),
    S("{reason}. Time to see what's what.", "{weather} {tod}, and the road's mine.", "All quiet here. Mostly."),
    S("{reason}. {dog}'s itchin' to roam.", "Whistle a tune and the miles pass.", "A fine spot. We'll bide a while."),
    S("{reason}. Another mile or two.", "The ridge looks right pretty now.", "Home away from home, this."),
]

let THREADS: [ThreadDef] = [
    ThreadDef(id: "plow", carry: "a plow point",
        open: S("{reason}. Got {carry} to see to.", "Vern's {carry} ain't gettin' lighter.", "Reckon this is the stop for {carry}."),
        mid: [S("{reason}. {dog}, fetch {carry}.", "Vern swore it'd cut like butter.", "Not the right one. On we go, {dog}."),
              S("{reason}. Still haulin' {carry}.", "A plow point's heavy company.", "Somebody here sharpened one like it."),
              S("{reason}. {place} may have one.", "Hard {season} dirt breaks a good point.", "Right plow, wrong field. Hmm.")],
        close: S("{reason}. Vern gets {carry} back.", "Home by dark, plow point in hand.", "Vern's got his point. Supper's mine.")),
    ThreadDef(id: "pie", carry: "Miss Opal's pie",
        open: S("{reason}. Opal sent along a pie.", "Don't you dare peek, {dog}.", "Special delivery, fresh from the oven."),
        mid: [S("{reason}. The pie's still warm.", "Smells like cinnamon the whole way.", "That's the wrong table. Hmm."),
              S("{reason}. {carry} must travel.", "{dog} keeps eyein' that pie.", "Left a slice. Fair is fair."),
              S("{reason}. Last of the pie.", "One bite wouldn't hurt. Would it?", "Only crumbs left. Don't tell Opal.")],
        close: S("{reason}. Tell Opal it kept.", "Home with a clean plate and a story.", "Opal's pie made it. So did I.")),
    ThreadDef(id: "fiddle", carry: "the old fiddle",
        open: S("{reason}. {carry} needs new strings.", "{tod} is good for tunin'.", "A string for the fiddle, if you please."),
        mid: [S("{reason}. Strings are comin'.", "Hummin' scales to keep time.", "That string's too thick. Next."),
              S("{reason}. Rehearsin' for Saturday.", "Little Liza Jane, one more time.", "Played a reel. Folks clapped some."),
              S("{reason}. Nearly in tune.", "{dog} howls on the high notes.", "The fiddle sings. Mostly.")],
        close: S("{reason}. Social's all set.", "A reel for the whole holler tomorrow.", "{carry} is tuned. Time to rest.")),
    ThreadDef(id: "mule", carry: "a lead rope",
        open: S("{reason}. Hannah's slipped her rope.", "Mule tracks, headin' that way.", "Seen a mule? Answers to Hannah."),
        mid: [S("{reason}. Follow them hoofprints.", "{dog} has the scent, I'd bet.", "No mule. Just a good view."),
              S("{reason}. Hannah's a stubborn one.", "A mule goes where a mule pleases.", "She was here? Figures."),
              S("{reason}. Hot on her trail.", "Fresh droppings. Gettin' close.", "There she is, chewin' the clover.")],
        close: S("{reason}. Leadin' Hannah home.", "Hannah walks and I don't say a word.", "Hannah's in her stall. Bless her.")),
    ThreadDef(id: "revenuer", carry: "a jar of cider",
        open: S("{reason}. Hear a revenuer's about.", "Walkin' casual. Nothin' to see, {dog}.", "Just cider here. Honest cider."),
        mid: [S("{reason}. Hidin' the good stuff.", "I whistle so I look innocent.", "Tarp's over the still. Move along."),
              S("{reason}. Checkin' for strangers.", "Is that a hat behind the pine?", "Nobody here but us, thank goodness."),
              S("{reason}. Watchin' the watcher.", "He ain't half as sneaky as he thinks.", "He's gone. Pour a cup for luck.")],
        close: S("{reason}. All clear, I reckon.", "Home free, {carry} and all.", "No revenuer. Moonshine's a rumor.")),
    ThreadDef(id: "frost", carry: "a wool blanket",
        open: S("{reason}. Frost's a-comin'.", "Feel that bite {tod}?", "Cover the crops. Frost won't wait."),
        mid: [S("{reason}. More blankets needed.", "{weather} out, and gettin' colder.", "Tucked 'em in. Sleep tight, corn."),
              S("{reason}. Checkin' the apples.", "My breath's a-smokin' now.", "Apples are fine. Tough little fellers."),
              S("{reason}. Wood for the stove.", "Cold comin' down off the ridge.", "Stacked some kindlin'. Warm hands.")],
        close: S("{reason}. Blanket for the porch.", "Frost on the fence by mornin', mark me.", "All tucked in. Good night, {season}.")),
    ThreadDef(id: "bees", carry: "news for the bees",
        open: S("{reason}. Bees need {carry}.", "Ya always tell the bees first.", "Bees, I've got news. Settle down."),
        mid: [S("{reason}. Bees gettin' restless.", "Hush now, they hear everything.", "Told 'em. They hummed. Good sign."),
              S("{reason}. Honey owed to Opal.", "{season} honey's the sweetest.", "A comb for Opal. Don't tell the bees."),
              S("{reason}. Checkin' the hives.", "Buzz of the bees, a fine tune.", "Hives are humming. All's well.")],
        close: S("{reason}. Last word for the bees.", "Dusk, and the hives gone quiet.", "Bees are told. Sweet dreams to all.")),
    ThreadDef(id: "sorghum", carry: "a sorghum skimmer",
        open: S("{reason}. Sorghum's boilin' down.", "The whole holler smells sweet.", "Who's got a skimmer? Mine's lost."),
        mid: [S("{reason}. Fetch more cane juice.", "A good boil takes patience.", "Cane's in the pot. Stir, stir, stir."),
              S("{reason}. Foam wants skimmin'.", "Stir slow and don't scorch it.", "Skimmed it clean. Honest work."),
              S("{reason}. Almost thick enough.", "Test it on a spoon, as Granny said.", "Thick as molasses. That's the stuff.")],
        close: S("{reason}. Jars for the shelf.", "Home with warm jars and sticky hands.", "Sorghum's put up. That'll do.")),
    ThreadDef(id: "letter", carry: "a letter",
        open: S("{reason}. Got {carry} for someone.", "No name on it, just a smudge.", "Anyone expectin' a letter?"),
        mid: [S("{reason}. Somebody's expectin' it.", "I won't peek. Much.", "Not for you? Pity."),
              S("{reason}. Askin' around some more.", "A letter's a burden of hope.", "They pointed me elsewhere. Odd."),
              S("{reason}. Maybe the postmaster knows.", "The smudge looks like a fox, kinda.", "A fox on the seal! That's Granny's.")],
        close: S("{reason}. Letter's goin' home.", "It was for me all along. Imagine.", "Granny wrote it. I'll read by lamplight.")),
    ThreadDef(id: "fence", carry: "a coil of wire",
        open: S("{reason}. Fence needs mendin'.", "Deer love a gap in the wire.", "Spare wire? The fence won't mend itself."),
        mid: [S("{reason}. Fetchin' more staples.", "{dog} checks every post.", "Got a handful. They'll hold."),
              S("{reason}. Posts gone soft.", "Rot gets in come {season}.", "New posts, sound as an oak."),
              S("{reason}. Last stretch of wire.", "Hammer and a prayer, that's all.", "Fence is tight. Let the deer try.")],
        close: S("{reason}. Fence is finished.", "I'll count the posts. One, two, three.", "Fence stands. Even the deer approve.")),
    ThreadDef(id: "ramps", carry: "a sack for ramps",
        open: S("{reason}. Ramps are up, I hear.", "Wild leeks in the shade, {tod}.", "Anyone know a ramp patch?"),
        mid: [S("{reason}. Follow the oniony smell.", "Dig 'em gentle, leave some be.", "Found a patch. Wild as can be."),
              S("{reason}. Fry 'em with taters.", "{dog} sneezes at the stink.", "Cleaned a mess of 'em. Lord, the smell."),
              S("{reason}. Share with the neighbors.", "Smellin' like a ramp, and proud.", "Everybody's hungry for ramps.")],
        close: S("{reason}. Ramps for supper.", "Home to a skillet and a good tale.", "Ramps and taters. Supper's blessed.")),
    ThreadDef(id: "light", carry: "a lantern",
        open: S("{reason}. Somethin's up in the sky.", "A light over the ridge, {tod}.", "Anybody else see that light yonder?"),
        mid: [S("{reason}. Chasin' that glow.", "Hush, {dog}. We ain't scared.", "They saw it too. Moth-winged, they say."),
              S("{reason}. Moth-man talk's spreadin'.", "Red eyes in the pines. Or fireflies.", "Fireflies, I'd wager. Mostly."),
              S("{reason}. One more look.", "Wings on the wind, or a hoot owl.", "Nothin' but moonlight. Pity.")],
        close: S("{reason}. Lantern's done its job.", "The glow's gone. Home's a lamp away.", "Mystery's mine to keep. Good night.")),
    ThreadDef(id: "butter", carry: "Granny's recipe",
        open: S("{reason}. Apple butter day's here.", "Cider and cinnamon, that's the way.", "Granny's recipe says stir all day."),
        mid: [S("{reason}. More apples, if you please.", "{weather} out, perfect for stirrin'.", "Peeled a bushel. My hands are pruney."),
              S("{reason}. Kettle wants cinnamon.", "A pinch for luck, a pinch for taste.", "Cinnamon's in. Now we wait."),
              S("{reason}. Jars need scaldin'.", "Pop and hiss, the jars are ready.", "Scalded. Not one cracked.")],
        close: S("{reason}. Butter's put up.", "Home with sticky fingers and cinnamon.", "Apple butter's done. Granny'd approve.")),
    ThreadDef(id: "leaf", carry: "a bundle of leaf",
        open: S("{reason}. Leaf needs hangin'.", "Sweet smell of curin' leaf, {tod}.", "The barn's ready. Hang it high."),
        mid: [S("{reason}. Another bundle to hang.", "{season} sun's good for the crop.", "Hung 'em up. Look at that color."),
              S("{reason}. Barn needs a fire.", "Low and slow, that's the way.", "Smoke's seepin' nice. Don't rush it."),
              S("{reason}. Test the leaf.", "Feel it between two fingers, soft.", "Leaf is cured. Gold as a coin.")],
        close: S("{reason}. Barn's shut for the night.", "Home to a pipe and a porch step.", "Crop's in. Time to rest the hands.")),
    ThreadDef(id: "quilt", carry: "a quilt square",
        open: S("{reason}. Square for the quilt bee.", "Needle and thread, stitch by stitch.", "Brought a square. Where does it go?"),
        mid: [S("{reason}. Run short on blue cloth.", "Scraps make the finest quilts.", "Blue scraps! Bless this quilt."),
              S("{reason}. Stitches need countin'.", "Granny counts in her sleep.", "Fourteen stitches to the inch."),
              S("{reason}. Almost to the border.", "{dog} naps on the finished part.", "Border's on. Look at her shine.")],
        close: S("{reason}. Quilt for the cold nights.", "Wrapped warm, home by lantern light.", "Quilt's done. First one under it's me.")),
]

// MARK: Place names

private let NAME_FIRST = ["Sawmill", "Possum", "Laurel", "Hickory", "Buzzard", "Tarkiln", "Ramp", "Dogwood", "Sourwood", "Wolf", "Pawpaw", "Pine",
                          "Elk", "Mulberry", "Ginseng", "Crawdad", "Corncrib", "Cold", "Raccoon", "Gander", "Tinker", "Shady", "Hog", "Sulphur"]
private let NAME_LAST = ["Holler", "Ridge", "Branch", "Knob", "Gap", "Run", "Fork", "Bottom", "Spring", "Hollow", "Bend", "Camp"]

/// A stable made-up name for a session's camp, from its token alone.
func placeName(_ token: String) -> String {
    let h = hashOf("place:" + token)
    return "\(NAME_FIRST[Int(h % UInt32(NAME_FIRST.count))]) \(NAME_LAST[Int((h / 31) % UInt32(NAME_LAST.count))])"
}

// MARK: Audit (measuring only, JEB_BENCH with JEB_STORY_AUDIT=1)

extension Story {
    /// Expands every line with the longest value of each slot and checks it wraps into two bubble lines of the font's own glyphs.
    static func audit(art: Art, areas: Areas = [:]) {
        func longest(_ l: [String]) -> String { l.max { $0.count < $1.count } ?? "" }
        let reasons = REASONS.values.flatMap { $0 }
        var lines = 0, bad = 0, lengthMax = 0
        func check(_ t: String, carry: String, tag: String) {
            let s = Slots(place: "Sourwood Bottom", from: "Sourwood Bottom", carry: carry, tod: "this afternoon", season: "winter", weather: "stormy",
                          dog: "Blue", reason: longest(reasons))
            let out = expand(t, s)
            lines += 1
            lengthMax = max(lengthMax, out.count)
            let wrapped = bubbleLines(out, chars: 30)
            let glyphs = out.allSatisfy { art.hasGlyph($0) }
            if wrapped.count > 2 || wrapped.contains(where: { $0.hasSuffix("..") }) || !glyphs || out.contains("{") {
                bad += 1
                print("audit: \(tag): \(out.count) chars \(glyphs ? "" : "(glyph) ")\(out)")
            }
        }
        for th in THREADS {
            for (i, st) in ([th.open] + th.mid + [th.close]).enumerated() {
                check(st.leave, carry: th.carry, tag: "\(th.id)#\(i) leave"); check(st.road, carry: th.carry, tag: "\(th.id)#\(i) road"); check(st.arrive, carry: th.carry, tag: "\(th.id)#\(i) arrive")
            }
        }
        for (i, st) in CODA.enumerated() { for t in [st.leave, st.road, st.arrive] { check(t, carry: "", tag: "coda#\(i)") } }
        for g in GOODBYES { check(g, carry: "", tag: "goodbye") }
        for w in WAYSIDES { for t in w.lines { check(t, carry: "", tag: "wayside \(w.sprite)") } }
        for r in reasons { check(r, carry: "", tag: "reason") }
        // The areas read from the store: each name, lore line and beat line fits the bubble and the font (a line that does not is never used).
        var areaLines = 0, areaBad = 0
        for (key, a) in areas.sorted(by: { $0.key < $1.key }) {
            let texts = [a.name] + a.lore + a.beats.map(\.line)
            for t in texts {
                areaLines += 1
                let wrapped = bubbleLines(t, chars: 30)
                let glyphs = t.allSatisfy { art.hasGlyph($0) }
                if wrapped.count > 2 || wrapped.contains(where: { $0.hasSuffix("..") }) || !glyphs || t.count > 64 {
                    areaBad += 1
                    print("audit: area \(key): \(t.count) chars \(glyphs ? "" : "(glyph) ")\(t)")
                }
            }
        }
        let names = Set((0..<2000).map { placeName("tok\($0)") })
        let longName = names.map(\.count).max() ?? 0
        print("audit: \(THREADS.count) threads, \(lines) lines, longest \(lengthMax) chars, \(bad) too long or off-font; \(names.count) distinct place names in 2000 tokens (longest \(longName)); \(WAYSIDES.count) waysides; \(areas.count) areas, \(areaLines) area lines, \(areaBad) too long or off-font")
    }
}
