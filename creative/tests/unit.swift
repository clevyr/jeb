// Unit tests (DESIGN 6.4): the pure functions and the goldens of the Python builder, with no model and no `claude`.
// Goldens predate D7; the test applies the D7 transform explicitly (venv allowRead entry, art Bash rule and art command gone).
import Foundation

func goldenText(_ name: String) -> String { readText(Env.golden + "/" + name) ?? "" }
func goldenJSON(_ name: String) -> Json { (try? Json.parse(goldenText(name))) ?? .null }
let venv = "/Users/golden/.claude/venvs/jeb-art"

func unitCases() -> [Case] {
    let golden = Paths(home: "/Users/golden", exeDir: "/x/creative"), stage = golden.stage
    let live = Env.mod
    func u(_ name: String, slow: Bool = false, _ body: @escaping (T) throws -> String) -> Case {
        Case(name: "U\(name)", slow: slow) { t in (t.bad.isEmpty ? "unit" : "UNIT", try body(t)) }
    }
    return [
        u("01 builder-argv (D7 on the golden)") { t in
            for (file, prompt) in [("builder-args.json", C.prompt), ("builder-args-task.json", builderPrompt("Add a scarecrow."))] {
                var want = (goldenJSON(file).array ?? []).compactMap { $0.string }
                want.removeAll { $0.hasPrefix("Bash(\(venv)/bin/python") }
                want = want.map { $0.replacingOccurrences(of: "\"\(venv)\", ", with: "") }
                t.eq(builderArgs(golden, stage: stage, prompt: prompt), want, file)
            }
            t.check(!builderArgs(golden, stage: stage).joined().contains("venvs"), "the venv is still readable")
            return "2 argvs"
        },
        u("02 sandbox-and-commands (D7)") { t in
            let want = goldenText("sandbox-settings.txt").replacingOccurrences(of: "\"\(venv)\", ", with: "").trimmingCharacters(in: .newlines)
            t.eq(sandboxSettings(golden, stage: stage).dumps(), want, "sandbox settings")
            let cmds = goldenText("builder-commands.txt").split(separator: "\n").map(String.init).filter { !$0.contains("venvs") }
            t.eq(golden.builderCommands.map { $0.joined(separator: " ") }, cmds, "builder commands")
            return "settings and commands"
        },
        u("03 locked-tests") { t in
            let g = goldenJSON("mod-counts.json")
            for (name, n) in g["locked_blocks"]?.object ?? [] {
                let blocks = testBlocks(readText(live + "/tests/" + name) ?? "")
                t.eq(blocks.count, n.int ?? -1, "blocks in \(name)")
                t.check(blocks.allSatisfy { testName($0) != nil }, "a block of \(name) has no name")
                // Decision 8: a name with `${` cannot be matched against the output, so none is locked.
                t.check(blocks.allSatisfy { !(testName($0) ?? "").contains("${") }, "a locked test name contains ${ in \(name)")
            }
            t.eq(Set((g["locked_blocks"]?.object ?? []).map { $0.0 }), Set(C.lockedTests), "locked files")
            return "\(C.lockedTests.count) files"
        },
        u("04 mod-counts") { t in
            let g = goldenJSON("mod-counts.json")
            t.eq(testCount(live), g["test_count"]?.int ?? -1, "test count"); t.eq(hooksBytes(live), g["hooks_bytes"]?.int ?? -1, "hooks bytes")
            return "\(testCount(live)) tests"
        },
        u("05 pattern-counts") { t in
            let g = goldenJSON("pattern-counts.json"), text = sourceText(live)
            t.eq(text.unicodeScalars.count, g["files_chars"]?.int ?? -1, "source characters")
            for (p, n) in g["forbidden"]?.object ?? [] { t.eq(rxCount(p, text), n.int ?? -1, "forbidden \(p)") }
            t.eq(C.forbidden, (g["forbidden"]?.object ?? []).map { $0.0 }, "forbidden list")
            for (name, p) in C.counted { t.eq(rxCount(p, text), g["counted"]?[name]?.int ?? -1, "counted \(name)") }
            t.eq(C.counted.map { $0.0 }, (g["counted"]?.object ?? []).map { $0.0 }, "counted list")
            return "\(C.forbidden.count) forbidden, \(C.counted.count) counted"
        },
        u("06 tools-digest") { t in
            let want = rxFirst(#"digest (\w+)"#, goldenText("tools-digest.txt"))?[1] ?? "?"
            t.eq(try treeDigest(Env.realTools), want, "digest of the pinned tools")
            t.eq(readText(Env.realSha).map(strip) ?? "?", want, "recorded digest")
            return String(want.prefix(12))
        },
        u("07 validate-notes") { t in
            let (cats, errors) = parseReport(goldenJSON("validate.json"), root: "<MOD>")
            t.eq(errors, [], "errors")
            t.check(cats.contains { $0.key.hasSuffix("declares on $") && $0.value.isEmpty }, "declares on $ is not empty")
            t.check(cats.contains { $0.key.hasSuffix("declares state") && $0.value.contains("jeb.say") }, "state items")
            t.check(cats.contains { $0.key.hasSuffix("env writes") && $0.value.isEmpty }, "'nothing' is not read as an item")
            let bad = Json.object([("success", .bool(false)), ("manifest", .object([("errors", .array([.string("bad at /r/x")]))]))])
            t.eq(parseReport(bad, root: "/r").1, ["validate failed", "validate error: bad at ./x"], "failing report")
            return "\(cats.count) categories"
        },
        u("08 text-shapes") { t in
            t.eq(printable("a\u{1b}[0m\tb\u{7f}\u{e9}"), "a?[0m?b?\u{e9}", "printable")
            t.eq(shown(String(repeating: "x", count: 200)).count, 120, "shown")
            t.eq(cleanHint("\u{1b}[31mHey\u{1b}[0m there\nsecond"), "[31mHey[0m there", "hint")
            t.eq(cleanHint(" \n\u{1b}"), C.defaultHint, "empty hint"); t.eq(cleanHint(String(repeating: "h", count: 200)).count, 80, "hint cap")
            t.eq(cleanSummary("\u{1b}[2J\(String(repeating: "A", count: 3000))\n").unicodeScalars.count, C.summaryMax, "summary cap")
            t.eq(cleanSummary(" a\u{0}b\n\n"), "ab", "summary strip")
            return "ok"
        },
        u("09 task-and-prompt") { t in
            t.eq(taskProblem("  \n"), "the task is empty", "empty"); t.eq(taskProblem("fine"), nil, "fine")
            t.eq(taskProblem(String(repeating: "a", count: 1001)), "the task is 1001 characters; the limit is 1000", "long")
            t.eq(taskProblem(String(repeating: "a", count: 1000)), nil, "limit")
            t.eq(taskProblem("a\u{1b}b"), "the task has control or unprintable characters", "control")
            t.eq(builderPrompt(), C.prompt, "prompt"); t.check(builderPrompt("x").hasSuffix("\nx\n--- End of the owner's request ---"), "task prompt")
            return "ok"
        },
        u("10 splitItems-testName-flake-dots") { t in
            t.eq(splitItems("a, b (via x, y), c{k=v, w}, "), ["a", "b (via x, y)", "c{k=v, w}"], "splitItems")
            t.eq(testName("test('it\\'s fine', () => {\n})"), "it's fine", "testName escape"); t.eq(testName("test(x)"), nil, "testName none")
            let k = "(fail) the file did not load: \(C.kitFlake)\n"
            t.check(isKitFlake(k), "flake"); t.check(!isKitFlake(k + "(fail) real one\n"), "a real failure mixed in"); t.check(!isKitFlake(""), "no failures")
            t.check(!unexpectedDot([".claude-plugin", "plugin.json"]) && !unexpectedDot([".claude-plugin", "types", ".x"]), "allowed dots")
            t.check(unexpectedDot(["hooks", ".hidden.ts"]) && unexpectedDot([".git"]) && unexpectedDot([".claude-plugin", "x", ".y"]), "dots")
            return "ok"
        },
        u("11 brief-and-news") { t in
            let p = Paths(home: Env.tmp + "/home0", exeDir: Env.creative)
            t.eq(try briefMismatch(p), [], "the brief lists every builder command"); t.check(!(try briefText(p)).contains("__HOME__"), "placeholder")
            let dir = Env.tmp + "/news"; mkdirp(dir + "/hooks")
            let bytes = try writeNews(dir, id: "i1", hint: "it's a \\ test")
            t.eq(readBytes(dir + "/hooks/news.ts") ?? [], bytes, "file equals the returned bytes")
            t.eq(String(decoding: bytes, as: UTF8.self), "// Written by creative/jeb-creative-build after a creative build.\nexport const JEB_NEWS: { id: string; line: string } | null = { id: 'i1', line: 'it\\'s a \\\\ test' }\n", "news text")
            rmrf(dir); return "ok"
        },
        u("12 walk-and-copy") { t in
            let dir = Env.tmp + "/walk"; rmrf(dir); mkdirp(dir + "/a"); try put(dir, "a/f.txt", "x"); try put(dir, "g.txt", "y")
            t.eq(try walk(dir).map { $0.rel }.sorted(), ["a", "a/f.txt", "g.txt"], "walk")
            let m = try manifest(dir); t.eq(m.keys.sorted(), ["a/f.txt", "g.txt"], "manifest keys"); t.eq(m["g.txt"], sha256Hex("y"), "manifest digest")
            t.eq(try treeSize(dir), 2, "size")
            symlink("/etc/hosts", dir + "/l")
            t.check(try walk(dir).contains { isLinkMode($0.st) && $0.rel == "l" }, "a link is reported, not followed")
            let c = Ctx(Paths(home: dir, exeDir: dir + "/bin"), echo: { _ in })
            mkdirp(dir + "/mod"); symlink("/etc/hosts", dir + "/mod/l")
            var failed = false
            do { try copyMod(c, to: dir + "/out") } catch { failed = true }
            t.check(failed, "a link in the live mod must fail the copy"); rmrf(dir)
            return "ok"
        },
    ]
}
