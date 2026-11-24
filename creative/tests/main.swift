// jeb-creative-tests: the creative builder's gates and pure functions, driven with no model (creative/DESIGN.md section 6).
//   jeb-creative-tests [--list] [--skip-slow] [--only NAME...]     NAME is a case id (H03, N07, unit...) or its full name
// Output per case follows hostile_gate.py: `ok  REJECT H03 symlink-to-ssh: reasons [0s]`, `BAD` on a mismatch; ends ALL AS EXPECTED
// or N UNEXPECTED (exit 1). tests/run.sh builds and runs it. Everything written lives under one mktemp folder removed at the end.
import Foundation

final class T {
    var bad: [String] = []
    func check(_ ok: Bool, _ what: @autoclosure () -> String) { if !ok { bad.append(what()) } }
    func eq<V: Equatable>(_ got: V, _ want: V, _ what: String) { if got != want { bad.append("\(what): got \(String(reflecting: got)), want \(String(reflecting: want))") } }
}
struct Case { let name: String; let slow: Bool; let body: (T) throws -> (String, String) }

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

func runTests() -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)
    let argv = Array(CommandLine.arguments.dropFirst())
    var only = Set<String>(), skipSlow = false, listOnly = false, i = 0
    while i < argv.count {
        switch argv[i] {
        case "--list": listOnly = true
        case "--skip-slow": skipSlow = true
        case "--only":
            i += 1
            while i < argv.count, !argv[i].hasPrefix("--") { only.insert(argv[i]); i += 1 }
            continue
        default: print("usage: jeb-creative-tests [--list] [--skip-slow] [--only NAME...]"); exit(2)
        }
        i += 1
    }
    let all = unitCases() + hostileCases()
    if listOnly { all.forEach { print($0.name + ($0.slow ? " (slow)" : "")) }; exit(0) }
    if !FileManager.default.isReadableFile(atPath: Env.realTools + "/node_modules/typescript/bin/tsc") || !lexists(Env.realSha) {
        print("the pinned TypeScript is not installed (\(Env.realTools)); run jeb-creative-build --dry-run once first"); exit(2)
    }
    // No child ever sees the real HOME; each hostile case sets its own.
    mkdirp(Env.tmp + "/home0"); setenv("HOME", Env.tmp + "/home0", 1)
    var unexpected = 0
    for c in all where only.isEmpty || only.contains(c.name) || only.contains(String(c.name.split(separator: " ")[0])) {
        if skipSlow && c.slow { continue }
        let t = T(), start = Date()
        var verdict = "UNIT", detail = ""
        do { (verdict, detail) = try c.body(t) } catch { t.bad.append("threw \(error)") }
        unexpected += t.bad.isEmpty ? 0 : 1
        print("\(t.bad.isEmpty ? "ok " : "BAD") \(verdict.padding(toLength: 6, withPad: " ", startingAt: 0)) \(c.name)\(detail.isEmpty ? "" : ": " + prefixChars(detail, 400)) [\(Int(Date().timeIntervalSince(start)))s]")
        t.bad.forEach { print("      - " + prefixChars($0, 600)) }
    }
    rmrf(Env.tmp)
    print(unexpected == 0 ? "ALL AS EXPECTED" : "\(unexpected) UNEXPECTED")
    exit(unexpected == 0 ? 0 : 1)
}
runTests()
