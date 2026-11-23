// The unit-test runner's bones: named tests, checks that record instead of abort, and scratch folders under $TMPDIR
// (tests/run.sh points it at a throwaway folder; the real ~/.jeb and the LaunchAgents are never touched).
import Foundation

final class Tester {
    var failures: [String] = []
    var count = 0
    private var current = ""

    func test(_ name: String, _ body: () throws -> Void) {
        current = name
        count += 1
        do { try body() } catch { fail("threw \(error)") }
    }

    func fail(_ what: String) { failures.append("\(current): \(what)") }

    func check(_ ok: Bool, _ what: String) { if !ok { fail(what) } }

    func eq<T: Equatable>(_ got: T, _ want: T, _ what: String = "") {
        if got != want { fail("\(what)\(what.isEmpty ? "" : ": ")got \(String(reflecting: got)), want \(String(reflecting: want))") }
    }

    /// A fresh folder for one test, under TMPDIR.
    func scratch(_ name: String) -> String {
        let d = NSTemporaryDirectory() + "/jebctl-tests-\(name)-\(getpid())"
        try? FileManager.default.removeItem(atPath: d)
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    func report() -> Int32 {
        for f in failures { print("FAIL " + f) }
        print("\(count - failures.count) of \(count) tests passed")
        return failures.isEmpty ? 0 : 1
    }
}

func writeFile(_ path: String, _ text: String, mode: Int? = nil) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: path, contents: Data(text.utf8), attributes: mode.map { [.posixPermissions: $0] })
}

func readFile(_ path: String) -> String? {
    FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }
}

/// A Python-style str(set) for the probes: {'arm64'} / set(); several members sorted (Python's order is hash-dependent).
func pySet(_ s: Set<String>) -> String {
    s.isEmpty ? "set()" : "{" + s.sorted().map { "'\($0)'" }.joined(separator: ", ") + "}"
}
