// Gates: every gate of DESIGN section 3, in the order the Python runs them, with the same limits and rejection text, and the two
// gate passes. A cheap gate (G3 to G11) accumulates every problem it finds; tsc (G12) and the suite (G13) run only when the
// list is empty. A problem is a string; an empty list means the gate copy may go in.
import Foundation

func allowlistProblems(_ root: String) throws -> [String] {
    var bad: [String] = []
    for e in try walk(root) where !isDirMode(e.st) {
        if !isRegular(e.st) || !C.allowedFiles.contains(where: { rxFull($0, e.rel) }) { bad.append(shown(e.rel)) }
    }
    return bad.isEmpty ? [] : ["files not allowed: " + bad.prefix(5).joined(separator: ", ") + (bad.count > 5 ? " ..." : "")]
}

/// Pinned files byte for byte (absent equal to absent; `news` stands in for hooks/news.ts in the second pass), then the pinned lines.
func pinnedChanges(_ c: Ctx, _ root: String, news: [UInt8]?) -> [String] {
    var changed: [String] = []
    for rel in C.pinnedFiles {
        let want = rel == "hooks/news.ts" && news != nil ? news : readBytes(c.p.mod + "/" + rel)
        if want != readBytes(root + "/" + rel) { changed.append(rel) }
    }
    for (rel, pattern) in C.pinnedLines {
        let pick = { (p: String) in (readText(p).map(pySplitLines) ?? []).filter { rxCount(pattern, $0) > 0 } }
        let old = pick(c.p.mod + "/" + rel), new = pick(root + "/" + rel)
        if old.isEmpty || old != new { changed.append("\(rel) (\(pattern))") }
    }
    return changed
}

/// Top-level tests: from `test(` at column 0 to the next line that is exactly `})`.
func testBlocks(_ text: String) -> [String] { rxAll(#"^test\(.*?^\}\)$"#, text, [.anchorsMatchLines, .dotMatchesLineSeparators]).map { $0[0]! } }

func testName(_ block: String) -> String? {
    guard let m = rxFirst(#"^test\((['"])((?:\\.|(?!\1).)*)\1"#, block), let name = m[2] else { return nil }
    return rxReplace(#"\\(.)"#, name, "$1")
}

/// Every top-level test in a locked file must still be there, word for word; the story's own tests are the builder's.
func testProblems(_ c: Ctx, _ root: String) -> [String] {
    var problems: [String] = []
    for name in C.lockedTests {
        guard let live = readText(c.p.mod + "/tests/" + name) else { continue }
        guard let mine = readText(root + "/tests/" + name) else { problems.append("safety test file removed: \(name)"); continue }
        let changed = testBlocks(live).filter { !mine.contains($0) }
        if !changed.isEmpty {
            problems.append("\(changed.count) safety test(s) changed in \(name): \(prefixChars(shown(testName(changed[0]) ?? "?"), 80))")
        }
    }
    return problems
}

/// `a, b (via x, y), c{k=v}` -> items, splitting only on top-level commas.
func splitItems(_ text: String) -> [String] {
    var items: [String] = [], depth = 0, cur = String.UnicodeScalarView()
    for ch in text.unicodeScalars {
        if "({[".unicodeScalars.contains(ch) { depth += 1 } else if ")}]".unicodeScalars.contains(ch) { depth -= 1 }
        if ch == "," && depth == 0 { items.append(String(cur)); cur = .init() } else { cur.append(ch) }
    }
    items.append(String(cur))
    return items.map(strip).filter { !$0.isEmpty }
}

/// `claude plugin validate --json`: (category -> items, errors).
func structure(_ c: Ctx, _ root: String) -> ([String: Set<String>], [String]) {
    let (code, out, err) = runSplit(c, [c.p.claude, "plugin", "validate", "--json", "."], cwd: root, timeout: 300)
    guard let report = try? Json.parse(out) else { return ([:], ["validate gave no report (exit \(code)): \(shown(strip(suffixChars(strip(err), 200))))"]) }
    return parseReport(report, root: root)
}

/// The report's errors and its notes folded into category -> items (the part of `structure` that needs no `claude`).
func parseReport(_ report: Json, root: String) -> ([String: Set<String>], [String]) {
    var errors = report["success"]?.bool == true ? [] : ["validate failed"], cats: [String: Set<String>] = [:]
    var parts: [Json] = []
    if let m = report["manifest"], m.truthy { parts.append(m) }
    parts += report["contents"]?.array ?? []
    for part in parts {
        for e in part["errors"]?.array ?? [] {
            let message = e.object != nil ? (e["message"]?.string ?? "") : (e.string ?? "")
            errors.append("validate error: \(shown(message.replacingOccurrences(of: root, with: ".")))")
        }
        for note in part["notes"]?.array ?? [] {
            let text = note.object != nil ? (note["message"]?.string ?? "") : (note.string ?? "")
            guard let m = rxFirst(#"^(\S+) (.+?): (.*)$"#, text), let cat = m[2], let rest = m[3] else { continue }
            let body = strip(rxReplace(#"\s*\(via [^)]*\)"#, rest, ""))
            cats[cat, default: []].formUnion(rxCount(#"^nothing\b"#, body) > 0 ? [] : Set(splitItems(body)))
        }
    }
    return (cats, errors)
}

func structureProblems(_ c: Ctx, _ root: String) -> [String] {
    let (new, errors) = structure(c, root)
    if !errors.isEmpty { return errors }
    let (old, oldErrors) = structure(c, c.p.mod)
    if !oldErrors.isEmpty { return ["live mod does not validate: \(oldErrors[0])"] }
    var problems: [String] = []
    for cat in sortedBytes(new.keys) {
        let added = new[cat]!.subtracting(old[cat] ?? [])
        if added.isEmpty { continue }
        if C.guarded.contains(cat) || cat.hasSuffix("declares on $") || (old[cat] == nil && !C.openCategories.contains(cat)) {
            problems.append("new \(shown(cat)): \(shown(sortedBytes(added).joined(separator: ", ")))")
        }
    }
    return problems
}

func tscProblems(_ c: Ctx, _ root: String) throws -> [String] {
    try verifyTools(c)
    let file = root + "/tsconfig.gate.json"
    try Data(C.gateTsconfig.dumps().utf8).write(to: URL(fileURLWithPath: file))
    let (code, out) = run(c, c.p.tscCmd, cwd: root, timeout: 300)
    unlink(file)
    return code == 0 ? [] : ["tsc failed: \(shown(prefixChars(strip(out), 300)))"]
}

/// Claude Code 2.1.309/2.1.310's test kit sometimes kills a whole file as "passed 600000 ms" on mocked time, a race in its
/// watchdog. Only a run whose every failure is that kill is run again; any real test failure still rejects.
func isKitFlake(_ out: String) -> Bool {
    let fails = rxAll(#"^\(fail\) (.*)$"#, out, .anchorsMatchLines).map { $0[1]! }
    return !fails.isEmpty && fails.allSatisfy { $0.hasPrefix("the file did not load") } && out.components(separatedBy: C.kitFlake).count - 1 == fails.count
}

/// The suite twice with 0 failures, and every locked safety test reported passing.
func suiteProblems(_ c: Ctx, _ root: String) -> [String] {
    var names = Set<String>()
    for f in C.lockedTests { for b in testBlocks(readText(c.p.mod + "/tests/" + f) ?? "") { if let n = testName(b), !n.contains("${") { names.insert(n) } } }
    for i in 1...2 {
        var code: Int32 = 0, out = ""
        for attempt in 0...C.kitFlakeRetries {
            (code, out) = run(c, c.p.testCmd, cwd: root, timeout: C.testTimeout)
            if !isKitFlake(out) || attempt == C.kitFlakeRetries { break }
            c.log("tests run \(i): the test kit killed a file on mocked time; running it again")
        }
        let failed = rxFirst(#"(\d+) fail"#, out)?[1].flatMap { Int($0) }
        if code != 0 || rxFirst(#"(\d+) pass"#, out) == nil || failed == nil || failed! != 0 {
            let fails = rxAll(#"^\(fail\) (.{1,80})"#, out, .anchorsMatchLines).prefix(5).map { $0[1]! }.joined(separator: "; ")
            return ["tests run \(i) failed (\(failed.map(String.init) ?? "?") fail)" + (fails.isEmpty ? "" : ": " + shown(fails))]
        }
        let passed = Set(rxAll(#"^\(pass\) (.*?)(?: \[[\d.]+m?s\])?$"#, out, .anchorsMatchLines).map { $0[1]! })
        let missing = sortedBytes(names.filter { !passed.contains($0) })
        if !missing.isEmpty { return ["tests run \(i): \(missing.count) existing test(s) did not pass: \(prefixChars(shown(missing[0]), 80))"] }
    }
    return []
}

/// The concatenated text of hooks/**/*.ts* and types/**/*.ts* (sorted by path, invalid UTF-8 dropped; tests are not scanned).
func sourceText(_ root: String) -> String {
    var files: [[String]] = []
    for top in ["hooks", "types"] {
        for e in (try? walk(root + "/" + top)) ?? [] where isRegular(e.st) && (e.rel as NSString).lastPathComponent.contains(".ts") {
            files.append([top] + e.rel.components(separatedBy: "/"))
        }
    }
    files.sort { a, b in
        for (x, y) in zip(a, b) where x != y { return x.utf8.lexicographicallyPrecedes(y.utf8) }
        return a.count < b.count
    }
    return files.map { readText(root + "/" + $0.joined(separator: "/")) ?? "" }.joined(separator: "\n")
}

func testCount(_ root: String) -> Int {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root + "/tests")) ?? []
    return names.filter { $0.contains(".test.ts") }.reduce(0) { n, f in
        n + (readText(root + "/tests/" + f) ?? "").components(separatedBy: "\n").filter { $0.hasPrefix("test(") }.count
    }
}

func hooksBytes(_ root: String) -> Int {
    ((try? FileManager.default.contentsOfDirectory(atPath: root + "/hooks")) ?? []).reduce(0) { n, f in
        var st = stat(); return n + (stat(root + "/hooks/" + f, &st) == 0 ? Int(st.st_size) : 0)
    }
}

/// Every reason the gate copy may not go in; empty means it passes. `news` pins hooks/news.ts to what the runner just wrote.
func gate(_ c: Ctx, _ root: String, requireChange: Bool, news: [UInt8]? = nil) throws -> [String] {
    var problems = try allowlistProblems(root)
    problems += pinnedChanges(c, root, news: news).map { "pinned code changed: \($0)" }
    problems += testProblems(c, root)
    problems += structureProblems(c, root)
    let staged = sourceText(root), current = sourceText(c.p.mod)
    for pattern in C.forbidden where rxCount(pattern, staged) > 0 { problems.append("forbidden pattern: \(pattern)") }
    for (name, pattern) in C.counted where rxCount(pattern, staged) > rxCount(pattern, current) { problems.append("new \(name)") }
    if hooksBytes(root) > hooksBytes(c.p.mod) + 400_000 { problems.append("hooks grew by more than 400 KB") }
    if try treeSize(root) > 50_000_000 { problems.append("mod larger than 50 MB") }
    if requireChange && news == nil && staged == current && testCount(root) == testCount(c.p.mod) { problems.append("nothing changed") }
    if !problems.isEmpty { return problems }
    let t = try tscProblems(c, root)
    return t.isEmpty ? suiteProblems(c, root) : t
}

/// First pass: walk staging, copy it to `dest`, gate the copy.
func gateStaging(_ c: Ctx, stage: String, dest: String, requireChange: Bool) throws -> [String] {
    var problems = try stageProblems(stage)
    if !problems.isEmpty { return problems }
    do { try makeGateCopy(c, stage: stage, dest: dest) } catch { return ["could not copy staging: \(shown((error as? Abort)?.msg ?? "\(error)"))"] }
    let before = try manifest(dest)
    problems = try gate(c, dest, requireChange: requireChange)
    if problems.isEmpty, try manifest(dest) != before { problems.append("the gate copy changed while it was gated") }
    return problems
}

/// Second pass: write the news into the gate copy and gate it all again. Returns the problems and the manifest the swap must still match.
func gateWithNews(_ c: Ctx, dest: String, id: String, hint: String, requireChange: Bool = true) throws -> ([String], [String: String]) {
    let news = try writeNews(dest, id: id, hint: hint)
    let before = try manifest(dest)
    var problems = try gate(c, dest, requireChange: requireChange, news: news)
    if problems.isEmpty, try manifest(dest) != before { problems.append("the gate copy changed while it was gated") }
    return (problems, before)
}

/// Both gate passes, as the build runs them (no swap).
func checkBuild(_ c: Ctx, stage: String, dest: String, requireChange: Bool, id: String, hint: String) throws -> ([String], [String: String]) {
    let problems = try gateStaging(c, stage: stage, dest: dest, requireChange: requireChange)
    return problems.isEmpty ? try gateWithNews(c, dest: dest, id: id, hint: hint, requireChange: requireChange) : (problems, [:])
}
