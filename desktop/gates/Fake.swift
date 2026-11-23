// Fake: writes a scratch store the way the mod does (ported from desktop/src/tools/fake.py).
//
// fake <store> <sessions> [busy|idle] [seconds]: a fixture farm and N made-up sessions' live records, written through a
// temp file and a rename, changing as a session's would: idle ones turn their idle act every 12 s; busy ones change pose
// every ~2 s, say a line every ~8 s and send the truck out now and then (t every 500 ms). Every write's wall time goes
// to <store>.writes (for the latency check).
//
// Not the Python's random numbers: fake.py drew from random.Random(7) (a Mersenne Twister); this draws from a SplitMix64
// seeded with 7, so a busy run sends its trucks and says its lines at other moments (an idle run draws nothing and is
// the same store byte for byte).
import Foundation

/// SplitMix64: a small seeded generator, the same sequence on every run.
struct FakeRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// random.random(): a double in [0, 1).
    mutating func random() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    /// random.choice(a).
    mutating func choice(_ a: [String]) -> String { a[min(a.count - 1, Int(random() * Double(a.count)))] }
}

func fakeMain(_ at: Places, _ args: [String]) -> Int32 {
    guard args.count >= 2, let n = Int(args[1]) else {
        errLine("usage: jebgates fake <store> <sessions> [busy|idle] [seconds]")
        return 2
    }
    let store = args[0]
    let mode = args.count > 2 ? args[2] : "idle"
    let dur = args.count > 3 ? Double(args[3]) ?? 1e9 : 1e9
    guard let farm = Json.load(at.fixtures + "/farm-day.store.json")?["farm"] else { fail("could not read \(at.fixtures)/farm-day.store.json") }
    let acts = ["banjo", "sip", "nap", "chase", "smoke"]
    let poses = ["none", "read", "edit", "still", "think", "draft", "hoe"]
    let lines = ["Fine day for it.", "Corn's comin' on.", "Still's a-bubblin'.", "Lord willin' and the creek don't rise.", "Hand's out in the tobacco."]
    var rnd = FakeRandom(seed: 7)
    let t0 = GateClock.now
    let logPath = store + ".writes"
    if !FileManager.default.fileExists(atPath: logPath) { writeFile(logPath, "") }
    guard let log = FileHandle(forWritingAtPath: logPath) else { fail("could not open \(logPath)") }
    log.seekToEndOfFile()

    struct Session {
        var tick = 0
        var truck: Int?
        var truckAt: Double?
        var line: String?
        var said = 0.0
    }
    var state = [Session](repeating: Session(), count: n)

    func record(_ i: Int, _ now: Double) -> Json {
        let s = state[i]
        var r: Json = ["v": 1, "at": .int(Int(now * 1000)), "frame": .int(s.tick % 5040)]
        let idleAct = acts[Int((now - t0) / 12 + Double(i)) % 5]
        if idleAct != "banjo" { r.set("act", .string(idleAct)) }
        if mode == "busy" {
            r.set("busy", true)
            r.set("mood", "working")
            let pose = poses[Int((now - t0) / 2 + Double(i)) % poses.count]
            if pose != "none" { r.set("pose", .string(pose)) }
            if let t = s.truck { r.set("truck", ["t": .int(t), "load": "jar", "sputter": 0, "dog": false]) }
            if now - s.said < 8, let line = s.line, !line.isEmpty {
                r.set("line", .string(line))
                r.set("saidAt", .int(Int(s.said * 1000)))
            }
            r.set("hands", [["plot": "corn", "look": .int(i % 6)]])
        }
        r.set("live", .string(String(Array("BGRPYN")[i % 6])))
        return r
    }

    var last: String?
    while GateClock.now - t0 < dur {
        let now = GateClock.now
        for i in state.indices {
            state[i].tick = Int((now - t0) * 2)
            if mode == "busy" {
                if state[i].truck == nil && rnd.random() < 0.004 {
                    state[i].truck = 0
                } else if state[i].truck != nil {
                    state[i].truck = state[i].truckAt.map { Int((now - $0) * 2) } ?? 0
                    if state[i].truckAt == nil { state[i].truckAt = now }
                    if state[i].truck! >= 16 { state[i].truck = nil; state[i].truckAt = nil }
                }
                let roll = rnd.random()       // drawn every tick, as the Python's `rnd.random() < 0.06 and ...` did
                if roll < 0.06 && now - state[i].said > 8 { state[i].line = rnd.choice(lines); state[i].said = now }
            }
        }
        var body: Json = ["farm": farm]
        var key: Json = [:]
        for i in 0..<n {
            let r = record(i, now)
            body.set("live:fake\(i)", r)
            var k = r
            k.remove("at")
            k.remove("frame")
            key.set("live:fake\(i)", k)
        }
        let k = key.dumps()
        if k != last {
            last = k
            let tmp = store + ".tmp"
            writeFile(tmp, body.dumps())
            if rename(tmp, store) != 0 { fail("could not write \(store)") }
            log.write(Data((fixed(GateClock.now * 1000, 1) + "\n").utf8))
        }
        GateClock.sleep(0.5)
    }
    return 0
}
