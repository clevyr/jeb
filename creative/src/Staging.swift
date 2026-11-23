// Staging: the copy of the live mod the builder works in, the sanitising of what it leaves (summary, hint), the staging walk,
// the gate copy, and the news file the runner writes.
import Foundation

/// A fresh staging copy of the live mod. Links in the live mod fail loudly (decision 4ii); dot files are copied.
func copyMod(_ c: Ctx, to dest: String) throws {
    rmrf(dest)
    try copyNoFollow(c.p.mod, dest)
}

func cleanHint(_ text: String) -> String {
    let first = pySplitLines(strip(text)).first ?? ""
    let hint = prefixChars(String(String.UnicodeScalarView(first.unicodeScalars.filter { $0.value >= 32 && $0.value < 127 })), 80)
    return hint.isEmpty ? C.defaultHint : hint
}

func cleanSummary(_ text: String) -> String {
    let kept = String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 == "\n" || ($0.value >= 32 && $0.value < 127) }))
    return strip(prefixChars(strip(kept), C.summaryMax))
}

/// Read and remove the builder's summary and hint; returns (summary, hint). Only plain files are read or removed; anything
/// else stays for the staging walk to reject.
func takeCreative(_ stage: String) -> (String, String) {
    var texts: [String: String] = [:]
    for name in C.creativeFiles {
        let path = stage + "/" + name
        texts[name] = readNoFollow(path) ?? ""
        if let st = lstatOf(path), isRegular(st), st.st_nlink == 1 { unlink(path) }
    }
    return (cleanSummary(texts[".creative-summary.md"]!), cleanHint(texts[".creative-hint.txt"]!))
}

/// Dot names allowed: `.claude-plugin/` itself, and anything under its `types/` (replaced from the live mod in the gate copy).
func unexpectedDot(_ parts: [String]) -> Bool {
    for (i, part) in parts.enumerated() where part.hasPrefix(".") {
        if i == 0 && part == ".claude-plugin" { continue }
        if i >= 2 && Array(parts.prefix(2)) == C.typesDir { continue }
        return true
    }
    return false
}

/// The lstat walk of staging: links, special files and unexpected dot names.
func stageProblems(_ stage: String) throws -> [String] {
    var problems: [String] = []
    // The sandbox leaves an empty .claude/.cc-writes in its working folder.
    let dc = stage + "/.claude", writes = dc + "/.cc-writes"
    if lexists(dc) {
        let names = { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? ["?"] }
        let ok = isDirMode(lstatOf(dc)!) && names(dc) == [".cc-writes"] && (lstatOf(writes).map(isDirMode) ?? false) && names(writes).isEmpty
        if !ok { return ["unexpected .claude/ in staging"] }
        rmdir(writes); rmdir(dc)
    }
    // Staging's `.claude-plugin/types/` is not compared: Claude Code rewrites the live copy on its own, so a difference is
    // not an edit. The gate copy always gets the live mod's, and the sync never writes that folder.
    for e in try walk(stage) {
        if isLinkMode(e.st) { problems.append("symlink: \(shown(e.rel))") }
        else if isRegular(e.st) && e.st.st_nlink > 1 { problems.append("hardlink: \(shown(e.rel))") }
        else if !isRegular(e.st) && !isDirMode(e.st) { problems.append("special file: \(shown(e.rel))") }
        if unexpectedDot(e.rel.components(separatedBy: "/")) { problems.append("unexpected dot name: \(shown(e.rel))") }
        if problems.count >= 10 { break }
    }
    return problems
}

/// A fresh runner-owned copy of staging, with the live mod's engine types.
func makeGateCopy(_ c: Ctx, stage: String, dest: String) throws {
    rmrf(dest)
    try copyNoFollow(stage, dest)
    unlink(dest + "/tsconfig.gate.json")
    let types = dest + "/" + C.typesDir.joined(separator: "/")
    rmrf(types)
    try copyNoFollow(c.p.mod + "/" + C.typesDir.joined(separator: "/"), types)
}

/// hooks/news.ts: exactly two lines, each ending in a newline. Returns the bytes written.
func writeNews(_ root: String, id: String, hint: String) throws -> [UInt8] {
    let line = hint.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    let data = Array(("// Written by creative/jeb-creative-build after a creative build.\n"
        + "export const JEB_NEWS: { id: string; line: string } | null = { id: '\(id)', line: '\(line)' }\n").utf8)
    try Data(data).write(to: URL(fileURLWithPath: root + "/hooks/news.ts"))
    return data
}
