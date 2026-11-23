// PluginTests: the one write Jeb makes to settings.json, removing its own CLAUDE_CODE_PLUGIN_DIRS entry. Every path is a
// scratch one (JEB_SETTINGS, JEB_BACKUPS); the real ~/.claude is never read or written.
import Foundation

func pluginTests(_ t: Tester) {
    /// A scratch settings file and backups folder; body gets (settings path, backups folder, the mod folder to remove).
    func sandbox(_ name: String, _ text: String?, _ body: (String, String, String) throws -> Void) rethrows {
        let d = t.scratch(name)
        let settings = d + "/claude/settings.json", backups = d + "/claude/backups", mod = d + "/jeb/current/mod"
        try? FileManager.default.createDirectory(atPath: mod, withIntermediateDirectories: true)
        if let s = text { writeFile(settings, s.replacingOccurrences(of: "$MOD", with: mod), mode: 0o640) }
        let was = (envVar("JEB_SETTINGS"), envVar("JEB_BACKUPS"))
        setEnvVar("JEB_SETTINGS", settings)
        setEnvVar("JEB_BACKUPS", backups)
        defer { setEnvVar("JEB_SETTINGS", was.0); setEnvVar("JEB_BACKUPS", was.1) }
        try body(settings, backups, mod)
    }
    func backupsIn(_ dir: String) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() }

    t.test("plugin: the removal plan") {
        let mod = t.scratch("plan") + "/mod"
        func plan(_ v: String?) -> [String?] { let p = planRemoval(v, mod); return [p.action, p.new] }
        t.eq(plan(nil), ["absent", nil], "no value")
        t.eq(plan(""), ["absent", ""], "empty")
        t.eq(plan(mod), ["drop", nil], "only ours")
        t.eq(plan(mod + "/"), ["drop", nil], "ours with a slash")
        t.eq(plan("/x/other"), ["absent", "/x/other"], "only another")
        t.eq(plan("/x/a:" + mod + ":/x/b"), ["remove", "/x/a:/x/b"], "ours in the middle")
        t.eq(plan(" " + mod + " :/x/b"), ["remove", "/x/b"], "ours with blanks around it")
    }

    t.test("plugin: removing the entry backs up first, keeps the other entries, keys and their order") {
        let before = "{\n  \"zeta\": 1,\n  \"env\": {\n    \"B\": \"2\",\n    \"CLAUDE_CODE_PLUGIN_DIRS\": \"/x/other:$MOD\",\n    \"A\": \"1\"\n  },\n  \"alpha\": [\n    \"caf\u{e9}\",\n    \"tab\\there\"\n  ]\n}\n"
        try sandbox("remove", before) { settings, backups, mod in
            let original = readFile(settings)!, stamp = Clock.strftime("%Y%m%d-%H%M%S")
            var said: [String] = []
            // the backup exists, with the old content, by the time the file changes: checked from the say callback
            let action = try removeDirsEntry(mod, dry: false) { line in
                said.append(line)
                if line.hasPrefix("  backup: ") {
                    t.eq(readFile(String(line.dropFirst(10))), original, "the backup holds the old content")
                    t.eq(readFile(settings), original, "nothing is written before the backup")
                }
            }
            t.eq(action, "remove")
            t.eq(said.count, 2, "said the action and the backup")
            t.eq(said.first, "settings \(settings): CLAUDE_CODE_PLUGIN_DIRS remove -> /x/other")
            t.eq(backupsIn(backups), ["settings.\(stamp).json"], "one backup, named by the clock")
            t.eq(readFile(settings), original.replacingOccurrences(of: "/x/other:" + mod, with: "/x/other"), "only the entry went")
            t.eq(fileMode(settings), "0o640", "the mode is kept")
            t.eq(fileMode(backups), "0o700", "the backups folder is private")
            t.check(!FileManager.default.fileExists(atPath: settings + ".jeb-tmp"), "no temp file left")
        }
    }

    t.test("plugin: the last entry takes the key with it, and an empty env goes too") {
        try sandbox("drop", "{\"a\": {\"k\": true}, \"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"$MOD\"}, \"b\": null}") { settings, backups, mod in
            t.eq(try removeDirsEntry(mod, dry: false) { _ in }, "drop")
            t.eq(readFile(settings), "{\n  \"a\": {\n    \"k\": true\n  },\n  \"b\": null\n}\n")
            t.eq(backupsIn(backups).count, 1, "backed up")
        }
        try sandbox("drop-keep-env", "{\"env\": {\"X\": \"1\", \"CLAUDE_CODE_PLUGIN_DIRS\": \"$MOD\"}}") { settings, _, mod in
            t.eq(try removeDirsEntry(mod, dry: false) { _ in }, "drop")
            t.eq(readFile(settings), "{\n  \"env\": {\n    \"X\": \"1\"\n  }\n}\n")
        }
    }

    t.test("plugin: nothing is written for an absent entry, a dry run or a missing file") {
        let text = "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"/x/other\"}}"
        try sandbox("absent", text) { settings, backups, mod in
            t.eq(try removeDirsEntry(mod, dry: false) { _ in }, "absent")
            t.eq(readFile(settings), text, "untouched")
            t.eq(backupsIn(backups), [], "no backup")
        }
        try sandbox("dry", "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"$MOD\"}}") { settings, backups, mod in
            let original = readFile(settings)
            var said: [String] = []
            t.eq(try removeDirsEntry(mod, dry: true) { said.append($0) }, "drop")
            t.eq(said.last, "  (dry run: not written)")
            t.eq(readFile(settings), original, "untouched")
            t.eq(backupsIn(backups), [], "no backup")
        }
        try sandbox("missing", nil) { settings, backups, mod in
            t.eq(try removeDirsEntry(mod, dry: false) { _ in }, "absent")
            t.check(!FileManager.default.fileExists(atPath: settings), "no file created")
            t.eq(backupsIn(backups), [], "no backup")
        }
    }

    t.test("plugin: two edits in one second keep both backups") {
        try sandbox("twice", "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"$MOD:/x/b\"}}") { settings, backups, mod in
            let stamp = Clock.strftime("%Y%m%d-%H%M%S")
            try removeDirsEntry(mod, dry: false) { _ in }
            writeFile(settings, "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"\(mod)\"}}")
            try removeDirsEntry(mod, dry: false) { _ in }
            t.eq(backupsIn(backups), ["settings.\(stamp)-2.json", "settings.\(stamp).json"])
        }
    }

    t.test("plugin: a settings file that is not an object is refused, unchanged") {
        for (text, want) in [("[1]", "is not a JSON object; nothing changed"), ("{nope", "is not valid JSON"), ("{\"env\": 3}", "settings \"env\" is not an object; nothing changed"),
                             ("{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": 7}}", "CLAUDE_CODE_PLUGIN_DIRS is not a string in settings; nothing changed")] {
            sandbox("bad", text) { settings, backups, mod in
                do {
                    try removeDirsEntry(mod, dry: false) { _ in }
                    t.fail("no error for \(text)")
                } catch { t.check("\(error)".contains(want), "\(error) lacks \(want)") }
                t.eq(readFile(settings), text, "untouched")
                t.eq(backupsIn(backups), [], "no backup")
            }
        }
    }

    t.test("plugin: a symlinked settings.json stays a link") {
        try sandbox("link", nil) { settings, _, mod in
            let real = (settings as NSString).deletingLastPathComponent + "/real.json"
            writeFile(real, "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"\(mod)\", \"K\": \"v\"}}")
            symlink(real, settings)
            t.eq(try removeDirsEntry(mod, dry: false) { _ in }, "drop")
            t.eq(try? FileManager.default.destinationOfSymbolicLink(atPath: settings), real, "still a link")
            t.eq(readFile(real), "{\n  \"env\": {\n    \"K\": \"v\"\n  }\n}\n")
        }
    }

    t.test("plugin: store names and legacy entries") {
        t.eq(storeName("jeb@jeb"), "jeb_jeb-8dcd56be8054.json")
        t.eq(storeName("a@b@c"), "a_b_c-2b5ed2699e7f.json")
        t.eq(normPath("/a/b/../c/./d/"), "/a/c/d")
        let under = jebDir() + "/versions/v1/mod"
        sandbox("legacy", "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"/x/dev/mod: \(under) :$MOD\"}}") { _, _, mod in
            t.eq(legacyEntries(), [under], "only the entry under ~/.jeb, trimmed")
            t.eq(presentEntries([mod, "/x/none", mod]), [mod], "listed entries, once")
        }
    }
}
