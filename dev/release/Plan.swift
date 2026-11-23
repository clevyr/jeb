// Plan: the bump and the release notes from the Conventional Commits since the last tag (desktop/jebctl CC_RE,
// NOTE_GROUPS, release_plan), as release-please reads them: a `!` or a BREAKING CHANGE footer is major, feat is minor,
// fix/perf/revert are patch, anything else releases nothing.
import Foundation

let initialVersion = "1.0.0"                            // the first release, as release-please starts
/// Conventional Commits subject: type(scope)!: text. Matched against the whole subject, so `feat (x): y` (a space
/// before the scope) and `feat: ` (no text) are not release commits.
let ccPattern = #"(\w+)(?:\([^)]*\))?(!)?:\s*(.+)"#
/// Conventional Commits types that make a release note, and their headings, in the notes' order.
let noteGroups: [(String, String)] = [("breaking", "Breaking changes"), ("feat", "Features"), ("fix", "Fixes"), ("perf", "Performance"), ("revert", "Reverts")]

/// The format release_plan reads: short hash, subject and body, NUL between them and a record separator after each commit.
let planLogFormat = "--format=%h%x00%s%x00%b%x1e"

private func strip(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

/// (level or nil, notes markdown) from a `git log --format=%h%x00%s%x00%b%x1e` output.
func plan(fromLog out: String) -> (level: String?, notes: String) {
    var groups: [String: [String]] = [:]
    var level: String?
    let rank = ["patch": 1, "minor": 2, "major": 3]
    for raw in out.components(separatedBy: "\u{1e}") {
        let entry = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        if entry.isEmpty { continue }
        let f = entry.components(separatedBy: "\u{0}") + ["", ""]
        let sha = f[0], subject = strip(f[1]), body = f[2]
        // m[0] == subject: fullmatch ($ alone also matches before a trailing newline)
        guard let m = reMatch("^(?:" + ccPattern + ")$", subject), m[0] == subject else { continue }
        let kind = m[1].lowercased(), bang = !m[2].isEmpty, text = m[3]
        let footer = reMatch(#"(?m)^BREAKING[ -]CHANGE:\s*(.+)"#, body)
        let breaking = bang || footer != nil
        let this = breaking ? "major" : ["feat": "minor", "fix": "patch", "perf": "patch", "revert": "patch"][kind]
        if let t = this, level == nil || rank[t]! > rank[level!]! { level = t }
        if breaking { groups["breaking", default: []].append("- \(footer.map { strip($0[1]) } ?? text) (\(sha))") }
        if noteGroups.contains(where: { $0.0 == kind }) { groups[kind, default: []].append("- \(text) (\(sha))") }
    }
    let notes = noteGroups.compactMap { k, title in groups[k].map { "### \(title)\n\n" + $0.joined(separator: "\n") } }.joined(separator: "\n\n")
    return (level, notes)
}

/// The plan for the commits since tag `last`.
func releasePlan(_ last: String) -> (level: String?, notes: String) {
    plan(fromLog: git("log", "--no-merges", planLogFormat, "\(last)..HEAD").out)
}

/// --probe release-plan: {"logs": {name: git log output}} in JEB_PROBE_SPEC -> {name: {"level", "notes"}}.
func releasePlanProbe(_ spec: Json) -> Json {
    .object((spec["logs"]?.object ?? []).map { name, log in
        let p = plan(fromLog: log.string ?? "")
        return (name, .object([("level", p.level.map(Json.string) ?? .null), ("notes", .string(p.notes))]))
    })
}
