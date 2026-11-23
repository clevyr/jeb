// Snapshot.swift: the golden file of one run (SB.snapshot in drive.py) and the writer that collects produced goldens under OUT.
import Foundation

var COUNTS: [String: Int] = [:]
var SKIPPED: [String] = []

/// Write one produced golden (rel like runtime/status/bundle-fresh.txt). A trailing newline is added like Python's write().
/// With --only, files outside the prefix are dropped.
func write(_ rel: String, _ text: String) {
    if !config.only.isEmpty && !rel.hasPrefix(config.only) { return }
    writeText(config.out + "/" + rel, text.hasSuffix("\n") ? text : text + "\n")
    let parts = rel.split(separator: "/")
    let group = parts.prefix(2).joined(separator: "/")
    COUNTS[group, default: 0] += 1
}

/// Does any golden under one of `prefixes` fall inside --only? (skips whole scenario groups that cannot contribute)
func wanted(_ prefixes: [String]) -> Bool {
    if config.only.isEmpty { return true }
    return prefixes.contains { $0.hasPrefix(config.only) || config.only.hasPrefix($0) }
}

/// plistlib.dumps(plistlib.load(p)): the canonical XML form (plutil writes the same sorted-key XML, plus a trailing newline).
func plistXML(_ path: String) -> String {
    let r = runProcess(["/usr/bin/plutil", "-convert", "xml1", "-o", "-", path])
    if r.rc != 0 { return "(plutil failed: \(r.stderr))" }
    return r.stdout
}

extension SB {
    /// rc, stdout, stderr, then whatever state files the run touched.
    func snapshot(_ r: Result, plists: Bool = true) -> String {
        var out = section("rc", String(r.rc)) + section("stdout", norm(r.stdout, self)) + section("stderr", norm(r.stderr, self))
        for (label, p) in [("release-state.json", state + "/release-state.json"), ("update-status.json", state + "/update-status.json"),
                           ("updater-state.json", state + "/updater-state.json")] {
            if let t = readText(p) { out += section(label, prettyJSON(t, self)) }
        }
        if let t = readText(state + "/release.log"), !t.isEmpty { out += section("release.log", norm(t, self)) }
        if let t = readText(stublog), !t.isEmpty {
            let keep = t.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var lines = keep
            if lines.last == "" { lines.removeLast() }    // str.splitlines drops the final empty piece
            lines = lines.filter { !$0.contains(" prune-versions ") && !$0.contains(" reload-agents") }
            out += section("stub.log (argv of every native binary the run executed; detached prune-versions/reload-agents calls filtered)", norm(lines.joined(separator: "\n"), self))
        }
        if let t = readText(fake), !t.isEmpty { out += section("fake.log (claude, gh, launchctl calls)", norm(t, self)) }
        if let cur = try? FileManager.default.destinationOfSymbolicLink(atPath: jeb + "/current") { out += section("~/.jeb/current", norm(cur, self)) }
        if plists {
            for (d, label) in [(agents, "LaunchAgents"), (state + "/launchd", "JEB_HOME/launchd")] {
                for n in listDir(d) where n.hasSuffix(".plist") {
                    out += section("\(label)/\(n)", norm(plistXML(d + "/" + n), self))
                }
            }
        }
        return out
    }
}

/// rc/stdout/stderr only (the probes and the release steps).
func rcOutErr(_ r: Result, _ sb: SB? = nil) -> String {
    section("rc", String(r.rc)) + section("stdout", norm(r.stdout, sb)) + section("stderr", norm(r.stderr, sb))
}
