// jeb-creative-tests: the creative builder's gates and pure functions, driven with no model (creative/DESIGN.md section 6).
//   jeb-creative-tests [--list] [--skip-slow] [--real] [-j N] [--only NAME...]     NAME is a case id (H03, N07, unit...) or its full name
// Output per case follows hostile_gate.py: `ok  REJECT H03 symlink-to-ssh: reasons [0s]`, `BAD` on a mismatch; ends ALL AS EXPECTED
// or N UNEXPECTED (exit 1).
// Default: fast. Every case that reaches the suite gate uses the stand-in `claude` (see hostile.swift); N12 and H30 need the real mod suite to
// fail, so they are skipped with one line (`skipped N12, H30: need --real (the real mod suite)`). --real: H01, N12 and H30 run on the real
// suite (minutes each), one at a time after the others, since the real kit is load sensitive. Cases run concurrently on -j N workers
// (default min(6, active CPUs)); results print in case order. Each case lives in its own folder under Env.tmp with its own HOME (passed to
// children through toolEnv, never setenv), so nothing mutable is shared. tests/run.sh builds and runs it. Everything written lives under one mktemp folder removed at the end.
import Foundation

final class T {
    var bad: [String] = []
    func check(_ ok: Bool, _ what: @autoclosure () -> String) { if !ok { bad.append(what()) } }
    func eq<V: Equatable>(_ got: V, _ want: V, _ what: String) { if got != want { bad.append("\(what): got \(String(reflecting: got)), want \(String(reflecting: want))") } }
}
/// `real`: needs the real mod suite (skipped without --real; with it, run alone after the concurrent cases).
struct Case { let name: String; let slow: Bool; var real = false; let body: (T) throws -> (String, String) }

enum Env {
    static let creative = ((#filePath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    static let mod = (creative as NSString).deletingLastPathComponent + "/mod"
    static let golden = creative + "/tests/golden"
    static let realHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? "/"
    static let tmp: String = {
        var t = Array((NSTemporaryDirectory() + "/jeb-creative-tests.XXXXXX").utf8CString)
        guard mkdtemp(&t) != nil else { return "/nonexistent" }
        // The canonical path: `claude plugin validate` reports real paths, and the gate rewrites its own root out of them.
        return realpath(String(cString: t), nil).map { let s = String(cString: $0); free($0); return s } ?? String(cString: t)
    }()
    /// The live mod as it will be after the cutover deletes art/src (D7): the base of every case.
    static let base: String = {
        let b = tmp + "/base-mod"
        try? FileManager.default.copyItem(atPath: mod, toPath: b)
        rmrf(b + "/art/src")
        return b
    }()
    static var realTools: String { realHome + "/Library/Caches/jeb-creative/tools" }
    static var realSha: String { realHome + "/.claude/jeb-creative/tools.sha256" }
}

var realSuite = false

func runTests() -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)
    let argv = Array(CommandLine.arguments.dropFirst())
    var only = Set<String>(), skipSlow = false, listOnly = false, i = 0, jobs = min(6, ProcessInfo.processInfo.activeProcessorCount)
    let usage = "usage: jeb-creative-tests [--list] [--skip-slow] [--real] [-j N] [--only NAME...]"
    while i < argv.count {
        switch argv[i] {
        case "--list": listOnly = true
        case "--skip-slow": skipSlow = true
        case "--real": realSuite = true
        case "-j":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n >= 1 else { print(usage); exit(2) }
            jobs = n
        case "--only":
            i += 1
            while i < argv.count, !argv[i].hasPrefix("-") { only.insert(argv[i]); i += 1 }
            continue
        default: print(usage); exit(2)
        }
        i += 1
    }
    let all = unitCases() + hostileCases()
    if listOnly { all.forEach { print($0.name + ($0.slow ? " (slow)" : "") + ($0.real ? " (real)" : "")) }; exit(0) }
    if !FileManager.default.isReadableFile(atPath: Env.realTools + "/node_modules/typescript/bin/tsc") || !lexists(Env.realSha) {
        print("the pinned TypeScript is not installed (\(Env.realTools)); run jeb-creative-build --dry-run once first"); exit(2)
    }
    // No child ever sees the real HOME. This is the only setenv: each case's HOME reaches its children through toolEnv.
    mkdirp(Env.tmp + "/home0"); setenv("HOME", Env.tmp + "/home0", 1)
    var picked = all.filter { c in (only.isEmpty || only.contains(c.name) || only.contains(String(c.name.split(separator: " ")[0]))) && !(skipSlow && c.slow) }
    let skipped = picked.filter { $0.real && !realSuite }
    if !skipped.isEmpty {
        picked.removeAll { $0.real && !realSuite }
        print("skipped \(skipped.map { String($0.name.split(separator: " ")[0]) }.joined(separator: ", ")): need --real (the real mod suite)")
    }
    // Concurrent cases first (in order), then the real-suite cases one at a time. Output is in `picked` order within each group.
    let groups = [picked.filter { !$0.real }, picked.filter { $0.real }]
    var unexpected = 0
    let started = Date()
    for (g, group) in groups.enumerated() where !group.isEmpty {
        let lock = NSCondition()
        var results = [String?](repeating: nil, count: group.count), bads = [[String]](repeating: [], count: group.count), next = 0
        for _ in 0..<(g == 0 ? min(jobs, group.count) : 1) {
            let th = Thread {
                while true {
                    lock.lock(); let k = next; next += 1; lock.unlock()
                    if k >= group.count { return }
                    let c = group[k], t = T(), start = Date()
                    var verdict = "UNIT", detail = ""
                    do { (verdict, detail) = try c.body(t) } catch { t.bad.append("threw \(error)") }
                    let line = "\(t.bad.isEmpty ? "ok " : "BAD") \(verdict.padding(toLength: 6, withPad: " ", startingAt: 0)) \(c.name)\(detail.isEmpty ? "" : ": " + prefixChars(detail, 400)) [\(Int(Date().timeIntervalSince(start)))s]"
                    lock.lock(); results[k] = line; bads[k] = t.bad; lock.broadcast(); lock.unlock()
                }
            }
            th.stackSize = 16 << 20
            th.start()
        }
        for k in 0..<group.count {
            lock.lock()
            while results[k] == nil { lock.wait() }
            let line = results[k]!, bad = bads[k]
            lock.unlock()
            unexpected += bad.isEmpty ? 0 : 1
            print(line)
            bad.forEach { print("      - " + prefixChars($0, 600)) }
        }
    }
    print("total \(Int(Date().timeIntervalSince(started)))s, \(jobs) workers")
    rmrf(Env.tmp)
    print(unexpected == 0 ? "ALL AS EXPECTED" : "\(unexpected) UNEXPECTED")
    exit(unexpected == 0 ? 0 : 1)
}
runTests()
