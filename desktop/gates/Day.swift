// Day: a scripted day for the desktop's story, on a scratch store, never the real one.
//
// Runs the dev binary (--bin, else JEB_BIN, default JebDesktop.dev) offscreen as a bench (JEB_BENCH, JEB_BENCH_WATCH=1) on
// a scratch store, with the story's durations cut by JEB_STORY_SCALE (30: a 15 minute home spell is 30 s), while this
// writes the store: records come and go and things turn on. The bench prints one `step` line each time the story or the
// store moved the scene: the place, the calls waiting, the cast and the place roots in the tree. Checks, at every step:
// exactly one place root and only that place's strip in the tree, one Jeb and one Blue (also counting layers not shown);
// and over the day: he is home most of the time, acting out the busy session; the places he stops at and the reasons for
// each trip are the expected ones (every trip has a call's reason, a goodbye, or the way home); the pacing holds (the
// home spell a call's priority needs, at most 4 outbound trips an hour, visits between 1 and 3 minutes, night: home
// unless a high call); no unfilled slot or over-long line; and story.json (mode 0600, only the date, thread id and step,
// one step a trip, closed on the evening trip home, surviving a restart).
//     jebgates day [day|kinds|limit|evening|again|night|all]
import Foundation
import CryptoKit

private let SCALE = 30.0
private let MIN_STAY = 60 / SCALE, CAP_STAY = 180 / SCALE
private let SPELL = ["high": 60 / SCALE, "medium": 300 / SCALE, "low": 900 / SCALE]
private let PRIORITY = ["newArea": "high", "areaAgain": "medium", "event": "medium", "hands": "low", "longWork": "low", "ship": "low", "weather": "low",
                        "errand": "low"]
private let WINDOW = 3600 / SCALE, LIMIT = 4
private let HOME_SHARE = 0.6
private let TOL = 0.35

/// Where a scenario's lines go: printed at once, or held (a scenario run beside others prints when all are done).
private final class Out {
    var held: [String]?
    init(held: Bool) { self.held = held ? [] : nil }
    func say(_ s: String) {
        if held != nil { held!.append(s) } else { print(s) }
    }
}

private func wallNow() -> Double { Date().timeIntervalSince1970 }

private func dayRec(_ k: Json...) -> Json {
    var r: Json = ["v": 1, "at": .int(Int(wallNow() * 1000)), "frame": 0]
    for part in k { r = r.updated(part) }
    return r
}

private let BUSY: Json = ["busy": true, "pose": "read", "mood": "working"]
private let QUIET: Json = [:]
private let EVENT: Json = ["event": ["id": "bells", "t": 0, "dur": 60, "v": 0]]
private let HANDS: Json = ["hands": [["plot": "tobacco", "look": 2]]]
private let SHIP: Json = ["truck": ["t": 3, "load": "bale", "sputter": 0, "dog": false]]
private let RAIN: Json = ["weather": ["kind": "rain", "plot": "corn"]]

private func akey(_ tok: String) -> String {
    String(Insecure.MD5.hash(data: Data(tok.utf8)).map { String(format: "%02x", $0) }.joined().prefix(8))
}

/// A read area made and worked today (so it is new), with generic text.
private func areaOf() -> Json {
    let today = Json.string(localDay(wallNow()))
    return ["v": 1, "made": "offline", "day": today, "seen": today, "name": "Test Area", "terrain": "meadow", "palette": "clay", "weather": "clear",
            "mood": "noon", "motif": "light", "props": ["lantern", "birdhouse", "puddle"], "lore": ["Plain test lore one.", "Plain test lore two."],
            "beats": [["line": "Test beat one.", "prop": "lantern", "zone": "yard"], ["line": "Test beat two.", "prop": nil, "zone": "porch"],
                      ["line": "Test beat three.", "prop": "cloud", "zone": "sky"]]]
}

/// One change of a script entry: a session's record, a session gone, or areas made and worked on earlier days
/// ({area key: [made, seen]}, with or without a record naming them).
private enum Change {
    case record(String, Json)
    case gone(String)
    case aged(Json)
}

private func writeStore(_ at: Places, _ path: String, _ records: Json, _ aged: Json) {
    guard let farm = Json.load(at.fixtures + "/farm-day.store.json")?["farm"] else { fail("could not read \(at.fixtures)/farm-day.store.json") }
    var store: Json = ["farm": farm]
    var areas: Json = [:]
    for (tok, r) in records.object ?? [] {
        store.set("live:" + tok, r)
        if let a = r["area"]?.string, !a.isEmpty { areas.set(a, areaOf()) }
    }
    for (k, v) in aged.object ?? [] {
        guard let pair = v.array, pair.count == 2 else { continue }
        areas.set(k, areaOf().updated(["day": pair[0], "seen": pair[1]]))
    }
    if !(areas.object ?? []).isEmpty { store.set("areas", areas) }
    let tmp = path + ".tmp"
    writeFile(tmp, store.dumps())
    if rename(tmp, path) != 0 { fail("could not write \(path)") }
}

private let STEP = try! NSRegularExpression(pattern: #"^step t=(\S+) (\S+) cast=(\d+)/(\d+) tree=(\d+)/(\d+) roots=(\d+) farm=(\d+) camp=(\d+) road=(\d+) sessions=(\d+) place=(\S+) phase=(\S+) queue=(\S*) to=(\S+) reason=(\S+) acting=(\S+) step=(-?\d+) area=(\S+) arealines=(\d) line=(.*)"#)
private let KEYS = ["t", "tag", "jeb", "blue", "jebAll", "blueAll", "roots", "farm", "camp", "road", "sessions", "place", "phase", "queue", "to", "reason", "acting",
                    "step", "area", "arealines", "line"]

/// The bench's step lines as they come, and when the first one came.
private final class Steps {
    private let lock = NSLock()
    private var rows: [[String: String]] = []
    private var first: Double?
    private var rest = Data()

    var origin: Double? { lock.lock(); defer { lock.unlock() }; return first }
    var all: [[String: String]] { lock.lock(); defer { lock.unlock() }; return rows }

    func feed(_ d: Data) {
        rest.append(d)
        while let nl = rest.firstIndex(of: 10) {
            take(String(decoding: rest[rest.startIndex..<nl], as: UTF8.self))
            rest = Data(rest[rest.index(after: nl)...])
        }
    }

    func finish() {
        if !rest.isEmpty { take(String(decoding: rest, as: UTF8.self)) }
        rest = Data()
    }

    private func take(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = STEP.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return }
        var row: [String: String] = [:]
        for (i, k) in KEYS.enumerated() { row[k] = Range(m.range(at: i + 1), in: line).map { String(line[$0]) } ?? "" }
        lock.lock()
        if first == nil { first = wallNow() }
        rows.append(row)
        lock.unlock()
    }
}

private struct Run {
    var name: String
    var hour: Int
    var seconds: Int
    /// [(t, changes)]; the first entry is the store before the start.
    var script: [(Double, [Change])]
    var stops: [String]
    var reasons: [String]
    var step: Int?
    var extra: [String: String] = [:]
    var night = false
    var homeShare: Double?
    /// (t from, t to, token) he acts out at home.
    var lead: (Double, Double, String)?
    var awayOk = false
}

private func apply(_ changes: [Change], _ live: inout Json, _ aged: inout Json, fresh: Bool) {
    for c in changes {
        switch c {
        case let .aged(a): aged = aged.updated(a)
        case let .gone(tok): live.remove(tok)
        case let .record(tok, r):
            var r = r
            if fresh { r.set("at", .int(Int(wallNow() * 1000))) }
            live.set(tok, r)
        }
    }
}

/// Runs one scenario and prints its line (and its problems). Returns whether it passed and what story.json held.
private func run(_ at: Places, _ out: Out, _ storyPath: String, _ q: Run) -> (Bool, Json?) {
    let tmp = makeTempDir("jebday")
    let store = tmp + "/store.json"
    var live: Json = [:], aged: Json = [:]
    apply(q.script[0].1, &live, &aged, fresh: false)
    writeStore(at, store, live, aged)
    var env = environWith(["JEB_BENCH": String(q.seconds), "JEB_BENCH_WATCH": "1", "JEB_BENCH_STORY": "1", "JEB_STORE_PATH": store,
                           "JEB_STORY_SCALE": String(Int(SCALE)), "JEB_HOUR": String(q.hour), "JEB_STORY_PATH": storyPath])
    env["JEB_PLACE"] = nil
    env["JEB_PLACE_SINCE"] = nil
    for (k, v) in q.extra { env[k] = v }
    let bin = at.binary(default: "JebDesktop.dev")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: bin)
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { fail("could not run \(bin)") }
    let seen = Steps()
    let reading = DispatchGroup()
    reading.enter()
    DispatchQueue.global().async {
        while true {
            let d = pipe.fileHandleForReading.availableData
            if d.isEmpty { break }
            seen.feed(d)
        }
        seen.finish()
        reading.leave()
    }
    while seen.origin == nil && p.isRunning { usleep(20_000) }
    if let origin = seen.origin {
        for (t, changes) in q.script.dropFirst() {
            let wait = origin + t - wallNow()
            if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
            apply(changes, &live, &aged, fresh: true)
            writeStore(at, store, live, aged)
        }
    }
    p.waitUntilExit()
    reading.wait()

    var problems: [String] = []
    let steps = seen.all
    func v(_ s: [String: String], _ k: String) -> String { s[k] ?? "" }
    if steps.isEmpty { problems.append("no step lines") }
    var seq: [(String, Double)] = []
    var reasons: [(reason: String, t: Double, place: String, to: String)] = []
    var prev: [String: String]?
    var homeAt = -(Double(q.extra["JEB_PLACE_SINCE"] ?? "0") ?? 0)   // when he last got home (the home spell counts from there)
    var outbound: [Double] = []                                      // times an outbound trip started
    for s in steps {
        let place = v(s, "place"), phase = v(s, "phase"), ts = v(s, "t")
        let kind = place.components(separatedBy: ":")[0]
        let want = ["home": [1, 1, 0, 0], "camp": [1, 0, 1, 0], "road": [1, 0, 0, 1]][kind] ?? []
        if [Int(v(s, "roots")) ?? -1, Int(v(s, "farm")) ?? -1, Int(v(s, "camp")) ?? -1, Int(v(s, "road")) ?? -1] != want {
            problems.append("t=\(ts): roots \(v(s, "roots")) farm \(v(s, "farm")) camp \(v(s, "camp")) road \(v(s, "road")) at \(place)")
        }
        // (a happening's truck takes Jeb away for its trip: none shown then, never two)
        let jebs = q.awayOk ? ["0", "1"] : ["1"]
        if !jebs.contains(v(s, "jeb")) || !jebs.contains(v(s, "jebAll")) || v(s, "blue") != "1" || v(s, "blueAll") != "1" {
            problems.append("t=\(ts): cast \(v(s, "jeb"))/\(v(s, "blue")) (tree \(v(s, "jebAll"))/\(v(s, "blueAll"))) at \(place) \(phase)")
        }
        let line = v(s, "line")
        if line != "-" && (line.contains("{") || line.unicodeScalars.count > 60) { problems.append("t=\(ts): bad line \(pyRepr(line))") }
        let t = Double(ts) ?? 0
        if place != "road" && (seq.isEmpty || seq[seq.count - 1].0 != place) { seq.append((place, t)) }
        if place == "home" && phase == "arrive" { homeAt = t }
        let r = v(s, "reason")
        if phase == "leave" && r != "-" && (prev == nil || v(prev!, "phase") != "leave" || v(prev!, "place") != place) {
            reasons.append((r, t, place, v(s, "to")))
            if place == "home" {
                outbound.append(t)
                if let need = PRIORITY[r].flatMap({ SPELL[$0] }) {
                    if t - homeAt < need - TOL { problems.append("t=\(ts): \(r) left \(fixed(t - homeAt, 1)) s after getting home, needs \(fixed(need, 1)) s") }
                } else {
                    problems.append("t=\(ts): trip from home for \(r)")
                }
                if q.night && r != "newArea" { problems.append("t=\(ts): night trip for \(r)") }
            } else if PRIORITY[r] == nil && !["ended", "homeward", "night"].contains(r) {
                problems.append("t=\(ts): trip with reason \(r)")
            } else if let pr = PRIORITY[r] {
                outbound.append(t)
                if pr == "low" { problems.append("t=\(ts): hop to a \(r) call (low) without going home") }
            }
        }
        prev = s
    }
    for t in outbound {
        let n = outbound.filter { t - WINDOW < $0 && $0 <= t }.count
        if n > LIMIT { problems.append("t=\(fixed(t, 1)): \(n) outbound trips in an hour") }
    }
    let stops = seq.map { $0.0 }
    if stops != q.stops { problems.append("stops \(pyRepr(stops)) want \(pyRepr(q.stops))") }
    let gotReasons = reasons.map { $0.reason }
    if gotReasons != q.reasons { problems.append("reasons \(pyRepr(gotReasons)) want \(pyRepr(q.reasons))") }
    // visits: at least a minute (a goodbye leaves at once), at most three
    let camps = seq.filter { $0.0 != "home" }
    let leaves = reasons.filter { $0.place != "home" }
    for ((place, t0), leave) in zip(camps, leaves) {
        let stay = leave.t - t0
        if leave.reason != "ended" && stay < MIN_STAY - TOL { problems.append("stay at \(place) \(fixed(stay, 1)) s < \(fixed(MIN_STAY, 1)) s") }
        if stay > CAP_STAY + TOL { problems.append("stay at \(place) \(fixed(stay, 1)) s > \(fixed(CAP_STAY, 1)) s") }
    }
    // time at home: the place, from step to step (a leaving beat from home counts as home)
    var athome = 0.0
    let ends = steps.dropFirst().map { Double(v($0, "t")) ?? 0 } + [Double(q.seconds)]
    for (s, e) in zip(steps, ends) where v(s, "place") == "home" { athome += e - (Double(v(s, "t")) ?? 0) }
    let share = athome / Double(q.seconds)
    if let want = q.homeShare, share < want { problems.append("home \(fixed(100 * share, 0))% of the time, want \(fixed(100 * want, 0))%") }
    if let (t0, t1, tok) = q.lead {
        let got = steps.filter { s in
            let t = Double(v(s, "t")) ?? 0
            return t0 <= t && t <= t1 && v(s, "place") == "home" && v(s, "phase") == "stay"
        }.map { v($0, "acting") }
        if got.isEmpty || got.contains(where: { $0 != tok }) { problems.append("acting \(pyRepr(got)) between \(Json.pyFloat(t0)) and \(Json.pyFloat(t1)) s, want \(tok)") }
    }
    var st: Json?
    if FileManager.default.fileExists(atPath: storyPath) {
        var info = stat()
        let mode = stat(storyPath, &info) == 0 ? Int(info.st_mode) & 0o777 : 0
        st = Json.load(storyPath)
        if mode != 0o600 { problems.append("story.json mode 0o\(String(mode, radix: 8))") }
        let keys = (st?.object ?? []).map { $0.0 }
        if Set(keys) != ["d", "id", "step"] { problems.append("story.json keys \(pyRepr(keys.sorted()))") }
        if let want = q.step, st?["step"]?.int != want { problems.append("story step \(pyRepr(st?["step"])) want \(want)") }
    } else if q.stops != ["home"] {
        problems.append("no story.json")
    }
    out.say("\(problems.isEmpty ? "PASS" : "FAIL") \(q.name): \(steps.count) steps, home \(fixed(100 * share, 0))%, stops \(stops.joined(separator: " > ")); "
            + "reasons \(gotReasons.joined(separator: ",")); story \(pyRepr(st))")
    for pr in problems.prefix(12) { out.say("    " + pr) }
    return (problems.isEmpty, st)
}

// ---- the scenarios ----

private func day(_ at: Places, _ out: Out, _ story: String) -> (Bool, Json?) {
    let A = "ax", B = "bx"
    let script: [(Double, [Change])] = [
        (0, [.record(A, dayRec(QUIET))]),
        (2, [.record(B, dayRec(BUSY))]),            // busy B: he acts it out at home, no trip
        (4, [.record(A, dayRec(EVENT))]),           // a happening at A: a medium call, after the 5 minute spell
        (13, [.gone(A)]),                           // A's session ends while he is there: goodbye, home
        (50, [.record(B, dayRec(BUSY, HANDS))]),    // hands start at B: a low call, after the long spell
        (82, [.record(B, dayRec(BUSY))]),           // the hands go home: so does he
    ]
    // the day's errand (a low call, at 14:00 with the long spell up) goes to B at about 44 s
    return run(at, out, story, Run(name: "day", hour: 14, seconds: 90, script: script,
                                   stops: ["home", "camp:ax", "home", "camp:bx", "home", "camp:bx", "home"],
                                   reasons: ["event", "ended", "errand", "homeward", "hands", "homeward"], step: 6, homeShare: HOME_SHARE, lead: (1.9, 3.9, B)))
}

private func kinds(_ at: Places, _ out: Out, _ story: String) -> (Bool, Json?) {
    let A = "ax", B = "bx"
    let script: [(Double, [Change])] = [
        (0, [.record(A, dayRec(BUSY)), .record(B, dayRec(QUIET))]),
        (2, [.record(B, dayRec(SHIP))]),            // a ship: low call, the long spell is already up
        (8, [.record(B, dayRec(QUIET))]),
        (12, [.record(A, dayRec(BUSY, RAIN))]),     // test weather at A
        (44, [.record(A, dayRec(BUSY))]),
    ]
    // A busy from the start: a long work stretch (30 minutes) calls him at about 60 s
    return run(at, out, story, Run(name: "kinds", hour: 9, seconds: 85, script: script,
                                   stops: ["home", "camp:bx", "home", "camp:ax", "home", "camp:ax", "home"],
                                   reasons: ["ship", "homeward", "weather", "homeward", "longWork", "homeward"],
                                   extra: ["JEB_PLACE": "home", "JEB_PLACE_SINCE": "100"], homeShare: HOME_SHARE, awayOk: true))
}

private func limit(_ at: Places, _ out: Out, _ story: String) -> (Bool, Json?) {
    let toks = ["ax", "bx", "cx", "dx", "ex", "fx"]
    let script: [(Double, [Change])] = [(0, toks.map { .record($0, dayRec(QUIET, ["area": .string(akey($0))])) })]
    // six new areas at once (high calls): the fifth trip of the hour is refused and the rest expire
    return run(at, out, story, Run(name: "limit", hour: 14, seconds: 36, script: script, stops: ["home", "camp:ax", "camp:bx", "camp:cx", "camp:dx", "home"],
                                   reasons: ["newArea", "newArea", "newArea", "newArea", "homeward"]))
}

private func evening(_ at: Places, _ out: Out, _ story: String) -> (Bool, Json?) {
    let script: [(Double, [Change])] = [(0, [.record("ax", dayRec(BUSY, ["area": .string(akey("ax"))]))])]
    return run(at, out, story, Run(name: "evening", hour: 18, seconds: 16, script: script, stops: ["home", "camp:ax", "home"], reasons: ["newArea", "homeward"],
                                   step: 90))
}

private func again(_ at: Places, _ out: Out, _ story: String) -> (Bool, Json?) {
    let k = akey("ax")
    func ago(_ n: Double) -> Json { .string(localDay(wallNow() - n * 86400)) }
    // an area last worked 5 days ago; a session starts there, and the same write moves its `seen` to today (as the mod does)
    let script: [(Double, [Change])] = [
        (0, [.aged(.object([(k, [ago(10), ago(5)])]))]),
        (2, [.aged(.object([(k, [ago(10), ago(0)])])), .record("ax", dayRec(QUIET, ["area": .string(k)]))]),
    ]
    return run(at, out, story, Run(name: "again", hour: 14, seconds: 20, script: script, stops: ["home", "camp:ax", "home"], reasons: ["areaAgain", "homeward"],
                                   extra: ["JEB_PLACE": "home", "JEB_PLACE_SINCE": "100"]))
}

private func night(_ at: Places, _ out: Out, _ story: String) -> (Bool, Json?) {
    let A = "ax"
    let script: [(Double, [Change])] = [(0, [.record(A, dayRec(QUIET))]), (3, [.record(A, dayRec(EVENT))]), (9, [.record(A, dayRec(BUSY))])]
    return run(at, out, story, Run(name: "night", hour: 23, seconds: 16, script: script, stops: ["home"], reasons: [], night: true, homeShare: 0.99))
}

private func nightHigh(_ at: Places, _ out: Out, _ story: String) -> (Bool, Json?) {
    let script: [(Double, [Change])] = [(0, [.record("ax", dayRec(QUIET, ["area": .string(akey("ax"))]))])]
    return run(at, out, story, Run(name: "night-high", hour: 23, seconds: 12, script: script, stops: ["home", "camp:ax", "home"], reasons: ["newArea", "homeward"],
                                   night: true))
}

/// day, then evening on its story.json: the thread must survive the restart.
private func thread(_ at: Places, _ story: String) -> [String: (Bool, [String])] {
    let first = Out(held: true)
    let good = day(at, first, story).0
    let before = Json.load(story)
    let second = Out(held: true)
    var (good2, st2) = evening(at, second, story)
    if let b = before, let s = st2, (s["id"], s["d"]) != (b["id"], b["d"]) {
        second.say("FAIL evening: the thread changed across the restart \(pyRepr(b)) \(pyRepr(s))")
        good2 = false
    }
    return ["day": (good, first.held ?? []), "evening": (good2, second.held ?? [])]
}

/// jebgates day [which]: 0 when every scenario asked for passed.
func dayMain(_ at: Places, _ which: String) -> Int32 {
    let tmp = makeTempDir("jebstory")
    let sp = tmp + "/story.json"
    func p(_ n: String) -> String { tmp + "/" + n + "-story.json" }
    let out = Out(held: false)
    var ok = true
    switch which {
    case "all":
        var done: [String: (Bool, [String])] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        func start(_ work: @escaping () -> [String: (Bool, [String])]) {
            group.enter()
            DispatchQueue.global().async {
                let r = work()
                lock.lock(); done.merge(r) { $1 }; lock.unlock()
                group.leave()
            }
        }
        start { thread(at, sp) }
        for (n, f) in [("kinds", kinds), ("limit", limit), ("again", again), ("night", night), ("night-high", nightHigh)] {
            start {
                let held = Out(held: true)
                let good = f(at, held, p(n)).0
                return [n: (good, held.held ?? [])]
            }
        }
        group.wait()
        for n in ["day", "kinds", "limit", "evening", "again", "night", "night-high"] {
            let (good, lines) = done[n] ?? (false, [])
            ok = ok && good
            for l in lines { print(l) }
        }
    case "day": ok = day(at, out, sp).0
    case "kinds": ok = kinds(at, out, p("kinds")).0
    case "limit": ok = limit(at, out, p("limit")).0
    case "evening": ok = evening(at, out, sp).0
    case "again": ok = again(at, out, p("again")).0
    case "night":
        ok = night(at, out, p("night")).0
        ok = nightHigh(at, out, p("night2")).0 && ok
    default: break
    }
    print("scripted day: " + (ok ? "all good" : "FAILED"))
    return ok ? 0 : 1
}
