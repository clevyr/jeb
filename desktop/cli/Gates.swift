// Gates: the two gates a release bundle's app passes before it is swapped in (`jebctl apply`, Apply.swift), ported from
// desktop/updater.py: gate_smoke (every parity fixture renders offscreen) and gate_start/_gate_start (twenty seconds
// headless with the store watch on). Parity and the scripted day are release-time gates (the release tool runs them
// before it publishes), so a user's Mac never runs them (plan D2); --quick is therefore a no-op.
//
// The gates depend on Foundation and Json.swift only, so jebgates (desktop/gates/build.sh) compiles this file too and
// exposes them as `jebgates smoke|start`. Every name here starts with "gate" because jebgates has its own helpers
// (isDir, fail, ...) that must not collide.
//
// Isolation (stronger than the Python's clean_env, which kept HOME): a gate's app instance runs with HOME, JEB_HOME,
// JEB_LAUNCHAGENTS, JEB_APP_DIR and TMPDIR inside the gate's scratch folder, JEB_NO_LAUNCHCTL=1, and every other JEB_*
// variable dropped, so it can reach neither the owner's running Jeb (heartbeat folder, quit marker, LaunchAgents) nor the
// real ~/.jeb. The only things it reads from outside are the bundle's own files and, for the start gate, a scratch COPY of
// the live store's farm, areas and live keys.
//
// Test hooks (honoured only when set; never set by the shipped agents):
//   JEB_TEST_FAIL_GATE=smoke|start   that gate rejects ("forced by JEB_TEST_FAIL_GATE") without running anything
//   JEB_TEST_START_SECS=<n>          the start gate runs n seconds headless instead of 20 (the e2e script uses 3)
import Foundation

struct GateResult: Equatable {
    var ok: Bool
    var why: String
}

/// Seconds the start gate runs the app headless (updater.py's JEB_BENCH="20").
let gateStartSeconds = 20

private func gateEnvVar(_ name: String) -> String? {
    guard let v = getenv(name) else { return nil }
    return String(cString: v)
}

/// The last n non-empty lines of a program's output, as one line (updater.py tail()).
func gateTail(_ text: String, _ n: Int = 3) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
    return lines.suffix(n).joined(separator: " | ")
}

/// The environment of a gate's app instance (see the file comment): the parent's, minus every JEB_* variable, with the
/// per-gate ones set and every state folder pointed inside `scratch`. extra wins over everything.
func gateEnv(mod: String, scratch: String, extra: [String: String] = [:]) -> [String: String] {
    var e = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("JEB_") }
    let home = scratch + "/home"
    for d in [home, home + "/.jeb", home + "/LaunchAgents", home + "/Applications", scratch + "/tmp"] {
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    e["HOME"] = home
    e["TMPDIR"] = scratch + "/tmp/"
    e["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
    e["JEB_HOME"] = home + "/.jeb"
    e["JEB_LAUNCHAGENTS"] = home + "/LaunchAgents"
    e["JEB_APP_DIR"] = home + "/Applications"
    e["JEB_NO_LAUNCHCTL"] = "1"
    e["JEB_MOD"] = mod
    for (k, v) in extra { e[k] = v }
    return e
}

/// subprocess.run with a timeout, both outputs captured. A program that cannot start is 127, a timeout 124 (the child is
/// killed). `during` runs once on a background queue `after` seconds in (the start gate's mid-run store write).
func gateRun(_ argv: [String], cwd: String, env: [String: String], timeout: Double,
             after: Double = 0, during: (() -> Void)? = nil) -> (status: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: argv[0])
    p.arguments = Array(argv.dropFirst())
    p.currentDirectoryURL = URL(fileURLWithPath: cwd)
    p.environment = env
    let o = Pipe(), e = Pipe()
    p.standardOutput = o
    p.standardError = e
    p.standardInput = FileHandle.nullDevice
    // The exit is signalled by terminationHandler, set before run(): waitUntilExit on a pool thread (no run loop) can
    // miss a child's exit when several run at once, and the gate then hung for good with the child long gone.
    let exited = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in exited.signal() }
    do { try p.run() } catch { return (127, "", "\(error.localizedDescription)") }
    var od = Data(), ed = Data()
    let readers = DispatchGroup()
    readers.enter(); DispatchQueue.global().async { od = o.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
    readers.enter(); DispatchQueue.global().async { ed = e.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
    if let d = during { DispatchQueue.global().asyncAfter(deadline: .now() + after) { d() } }
    var timedOut = false
    if exited.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        p.terminate()
        if exited.wait(timeout: .now() + 3) == .timedOut { kill(p.processIdentifier, SIGKILL); _ = exited.wait(timeout: .now() + 5) }
    }
    readers.wait()
    let out = String(decoding: od, as: UTF8.self), err = String(decoding: ed, as: UTF8.self)
    return timedOut ? (124, out, "timed out after \(Int(timeout)) s") : (p.terminationStatus, out, err)
}

private func gateMatch(_ pattern: String, _ s: String, multiline: Bool = false) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: multiline ? [.anchorsMatchLines] : []),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
}

// ---- smoke ----

/// One parity fixture as the smoke gate runs it: its store file and the moment, place and extra environment it renders at.
struct GateFixture {
    var name: String
    var now: Int?
    var place: String?
    var since: Int?
    var env: [String: String]
}

/// The fixtures of a bundle's desktop/src/fixtures: smoke.json (written by `jebgates parity gen`: name, now, place, since,
/// env per fixture) when there, else every *.store.json with no moment (then only the run and its two lines are checked).
func gateFixtures(_ fixtures: String) -> [GateFixture] {
    if let j = Json.load(fixtures + "/smoke.json"), let rows = j.array, !rows.isEmpty {
        return rows.compactMap { r in
            guard let n = r["name"]?.string else { return nil }
            var env: [String: String] = [:]
            for (k, v) in r["env"]?.object ?? [] { if let s = v.string { env[k] = s } }
            return GateFixture(name: n, now: r["now"]?.int, place: r["place"]?.string, since: r["since"]?.int, env: env)
        }
    }
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: fixtures)) ?? []).filter { $0.hasSuffix(".store.json") }.sorted()
    return names.map { GateFixture(name: String($0.dropLast(".store.json".count)), now: nil, place: nil, since: nil, env: [:]) }
}

/// gate_smoke: every fixture renders offscreen without a crash, one place root, no more than one Jeb and one Blue (also
/// in the tree), and exactly 1/1 wherever the scene is at home (Jeb 0/0 while his truck is out). `fixtures` is the bundle's
/// desktop/src/fixtures, `mod` its mod. The app runs in a temporary folder, so `fixtures` is made absolute first.
func gateSmoke(binary: String, fixtures: String, mod: String, scratch: String) -> GateResult {
    if gateEnvVar("JEB_TEST_FAIL_GATE") == "smoke" { return GateResult(ok: false, why: "forced by JEB_TEST_FAIL_GATE") }
    let fixtures = URL(fileURLWithPath: fixtures).standardizedFileURL.path
    let all = gateFixtures(fixtures)
    if all.isEmpty { return GateResult(ok: false, why: "no fixtures in \(fixtures)") }
    var results = [String?](repeating: nil, count: all.count)
    let lock = NSLock()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 4
    for (i, f) in all.enumerated() {
        queue.addOperation {
            let r = gateSmokeOne(f, binary: binary, fixtures: fixtures, mod: mod, scratch: scratch + "/smoke-\(i)")
            lock.lock(); results[i] = r; lock.unlock()
        }
    }
    queue.waitUntilAllOperationsAreFinished()
    let problems = results.compactMap { $0 }
    return GateResult(ok: problems.isEmpty,
                      why: "\(all.count) fixtures, \(problems.count) problems" + problems.prefix(4).map { "; " + $0 }.joined())
}

private func gateSmokeOne(_ f: GateFixture, binary: String, fixtures: String, mod: String, scratch: String) -> String? {
    var extra = ["JEB_BENCH": "0.01", "JEB_BENCH_FREEZE": "1", "JEB_BENCH_SCALE": "1", "JEB_BENCH_STORY": "1",
                 "JEB_STORE_PATH": fixtures + "/" + f.name + ".store.json"]
    if let n = f.now { extra["JEB_NOW"] = String(n) }
    if let p = f.place { extra["JEB_PLACE"] = p }
    if let s = f.since { extra["JEB_PLACE_SINCE"] = String(s) }
    for (k, v) in f.env { extra[k] = v }
    // A missing store would render an empty farm and pass every check: refuse it instead.
    guard FileManager.default.fileExists(atPath: extra["JEB_STORE_PATH"]!) else { return "\(f.name): no store file" }
    let r = gateRun([binary], cwd: NSTemporaryDirectory(), env: gateEnv(mod: mod, scratch: scratch, extra: extra), timeout: 90)
    defer { try? FileManager.default.removeItem(atPath: scratch) }
    if r.status != 0 { return "\(f.name): exit \(r.status) \(gateTail(r.err, 1))" }
    guard let g = gateMatch(#"place (\S+) roots (\d+) farm (\d+) camp (\d+) road (\d+)"#, r.out),
          let st = gateMatch(#"step t=\S+ start cast=(\d+)/(\d+) tree=(\d+)/(\d+) roots=(\d+)"#, r.out) else {
        return "\(f.name): no geometry/step line"
    }
    if f.now == nil { return nil }       // no manifest: the run and its lines are all there is to check
    let kind = g[1], roots = Int(g[2]) ?? -1
    let c = (1...4).map { Int(st[$0]) ?? 99 }
    if roots != 1 { return "\(f.name): \(roots) place roots" }
    if c.max()! > 1 { return "\(f.name): cast \(c[0])/\(c[1]) tree \(c[2])/\(c[3])" }
    // At home: Jeb and Blue exactly once each, except that Jeb is out of the scene entirely (0 in cast and tree) while
    // a live record has the truck out; Blue stays home either way.
    let away = kind == "home" && gateTruckOut(extra["JEB_STORE_PATH"]!) && c == [0, 1, 0, 1]
    if kind == "home" && c != [1, 1, 1, 1] && !away { return "\(f.name): at home cast \(c[0])/\(c[1]) tree \(c[2])/\(c[3])" }
    return nil
}

/// Whether any live:* record in the store file has the truck out (Jeb then drives it, off the home scene).
private func gateTruckOut(_ store: String) -> Bool {
    guard let j = Json.load(store), case .object(let pairs) = j else { return false }
    return pairs.contains { $0.0.hasPrefix("live:") && $0.1["truck"] != nil }
}

// ---- start ----

/// gate_start: `secs` seconds headless with the store watch on, over a scratch copy of the live store's farm, live and
/// areas keys only (liveStore nil or missing: an empty one, as on a fresh machine; unreadable: empty, said in the reason).
/// scratch is wiped on every path.
func gateStart(binary: String, mod: String, liveStore: String?, scratch: String, secs: Int? = nil) -> GateResult {
    if gateEnvVar("JEB_TEST_FAIL_GATE") == "start" { return GateResult(ok: false, why: "forced by JEB_TEST_FAIL_GATE") }
    let n = secs ?? gateEnvVar("JEB_TEST_START_SECS").flatMap(Int.init) ?? gateStartSeconds
    let dir = scratch + "/scratch-store"
    try? FileManager.default.removeItem(atPath: dir)
    do { try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) } catch {
        return GateResult(ok: false, why: "cannot make \(dir): \(error.localizedDescription)")
    }
    defer { try? FileManager.default.removeItem(atPath: dir) }       // every path: pass, fail, timeout
    let store = dir + "/store.json"
    var keep: [(String, Json)] = []
    var note = ""
    if let live = liveStore, FileManager.default.fileExists(atPath: live) {
        if let j = Json.load(live), let kv = j.object {
            keep = kv.filter { $0.0 == "farm" || $0.0 == "areas" || $0.0.hasPrefix("live:") }
        } else {
            note = "; store unreadable, ran with an empty store"
        }
    }
    func put() { try? writePrivate(Data(Json.object(keep).dumps().utf8), to: store) }
    put()
    let env = gateEnv(mod: mod, scratch: scratch, extra: ["JEB_BENCH": String(n), "JEB_BENCH_WATCH": "1", "JEB_BENCH_STORY": "1",
                                                          "JEB_STORE_PATH": store, "JEB_STORY_PATH": dir + "/story.json"])
    let r = gateRun([binary], cwd: NSTemporaryDirectory(), env: env, timeout: Double(n) + 40, after: min(6, Double(n) / 3), during: put)
    if r.status == 124 { return GateResult(ok: false, why: "did not finish in \(n + 40) s") }
    if r.status != 0 || gateMatch("^bench .*\(n) s", r.out, multiline: true) == nil {
        return GateResult(ok: false, why: "exit \(r.status) \(gateTail(r.err.isEmpty ? r.out : r.err, 2))")
    }
    return GateResult(ok: true, why: "\(n) s headless run, no crash" + note)
}
