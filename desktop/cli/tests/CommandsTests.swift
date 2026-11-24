// CommandsTests: `emoji` and `screenshot` (Commands.swift). JEB_BIN names a stub script that records its environment and
// arguments and writes the output file; HOME, JEB_HOME and JEB_SRC are scratch ones, so nothing outside the scratch
// folders is touched and no app is started.
import Foundation

func commandsTests(_ t: Tester) {
    func printed(_ body: () -> Void) -> String {
        let file = t.scratch("stdout") + ".txt"
        fflush(stdout)
        let saved = dup(1), fd = open(file, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        dup2(fd, 1)
        close(fd)
        body()
        fflush(stdout)
        dup2(saved, 1)
        close(saved)
        return readFile(file) ?? ""
    }

    /// A scratch HOME with a stub binary (JEB_BIN) that logs `env` and its arguments to <home>/stub.log and writes the file
    /// the command asks for (JEB_EMOJI, else JEB_BENCH_PNG) with JEB_STUB_SIZE bytes. body gets (home, log path).
    func sandbox(_ name: String, stub: Bool = true, size: Int = 100, exit code: Int = 0, _ body: (String, String) -> Void) {
        let home = pyAbspath(t.scratch(name))
        let log = home + "/stub.log"
        let bin = home + "/stub-bin"
        if stub {
            writeFile(bin, """
            #!/bin/sh
            { env | sort; echo "ARGS: $*"; } > "\(log)"
            f="${JEB_EMOJI:-$JEB_BENCH_PNG}"
            [ -n "$f" ] && head -c \(size) /dev/zero > "$f"
            echo "stub complaint" >&2
            echo "last line" >&2
            exit \(code)
            """ + "\n", mode: 0o755)
        }
        writeFile(home + "/src/fixtures/smoke.json", """
        [{"name": "farm-day", "now": 1792605600000, "place": "home", "since": null, "env": {}},
         {"name": "camp-x", "now": 5, "place": "camp", "since": 77, "env": {"JEB_EXTRA": "yes"}}]
        """)
        writeFile(home + "/src/fixtures/farm-day.store.json", "{\"farm\": {}}")
        writeFile(home + "/src/fixtures/camp-x.store.json", "{\"farm\": {\"camp\": 1}}")
        let names = ["HOME", "JEB_HOME", "JEB_SRC", "JEB_BIN", "JEB_EMOJI_DELAY", "JEB_TEST_NO_PROCS"]
        let was = names.map { envVar($0) }, dry = dryRun
        for (k, v) in zip(names, [home, home + "/state", home + "/src", stub ? bin : home + "/missing", nil, "1"]) { setEnvVar(k, v) }
        defer {
            for (k, v) in zip(names, was) { setEnvVar(k, v) }
            dryRun = dry
        }
        body(home, log)
    }
    func envOf(_ log: String) -> [String: String] {
        var out: [String: String] = [:]
        for l in (readFile(log) ?? "").split(separator: "\n") {
            if let eq = l.firstIndex(of: "="), !l.hasPrefix("ARGS:") { out[String(l[..<eq])] = String(l[l.index(after: eq)...]) }
        }
        return out
    }
    let usage = "usage: jebctl emoji [--holiday NAME] [--sprite NAME] [--rows N] [-o FILE]\n"

    t.test("emoji: an unknown flag or a flag without a value is a usage error (2)") {
        sandbox("emoji-usage") { _, log in
            for bad in [["--nope", "x"], ["--rows"], ["-o"], ["stray"]] {
                var rc: Int32 = 0
                let out = printed { rc = cmdEmoji(bad) }
                t.eq(rc, 2, "\(bad) exits 2")
                t.eq(out, usage, "\(bad) prints the usage")
            }
            t.check(!FileManager.default.fileExists(atPath: log), "the binary never ran")
        }
    }

    t.test("emoji: --rows takes a whole number") {
        sandbox("emoji-rows") { _, log in
            for bad in ["x", "-1", "2.5", ""] {
                var rc: Int32 = 0
                let out = printed { rc = cmdEmoji(["--rows", bad]) }
                t.eq(rc, 2, "--rows '\(bad)' exits 2")
                t.eq(out, "emoji: --rows takes a whole number (0 for the whole sprite)\n")
            }
            t.check(!FileManager.default.fileExists(atPath: log), "the binary never ran")
        }
    }

    t.test("emoji: a missing or non-executable binary exits 1") {
        sandbox("emoji-nobin", stub: false) { home, _ in
            var rc: Int32 = 0
            var out = printed { rc = cmdEmoji([]) }
            t.eq(rc, 1)
            t.eq(out, "emoji: no binary at \(home)/missing\n")
            writeFile(home + "/missing", "#!/bin/sh\n", mode: 0o644)
            out = printed { rc = cmdEmoji([]) }
            t.eq(rc, 1, "a file without the execute bit is no binary")
            t.eq(out, "emoji: no binary at \(home)/missing\n")
            setEnvVar("JEB_BIN", "")
            out = printed { rc = cmdEmoji(["--dry-run-not-a-flag"]) }
            t.eq(rc, 2, "an empty JEB_BIN does not matter before the flags are read")
        }
    }

    t.test("emoji: the defaults are sprite jeb-sip, 28 rows, a 1.2 s delay and ~/Pictures/Jeb/jeb-emoji.gif") {
        sandbox("emoji-defaults") { home, log in
            var rc: Int32 = 0
            let out = printed { rc = cmdEmoji([]) }
            let dest = home + "/Pictures/Jeb/jeb-emoji.gif"
            t.eq(rc, 0)
            t.eq(out, "export jeb-sip with \(home)/stub-bin to \(dest)\n\(dest)  100 bytes\n")
            let env = envOf(log)
            t.eq(env["JEB_EMOJI"], dest)
            t.eq(env["JEB_EMOJI_SPRITE"], "jeb-sip")
            t.eq(env["JEB_EMOJI_ROWS"], "28")
            t.eq(env["JEB_EMOJI_DELAY"], "1.2")
            t.eq(env["JEB_MOD"], home + "/.jeb/current/mod")
            t.eq(env["JEB_HOLIDAY"], nil, "no holiday: no variable")
            t.check(FileManager.default.fileExists(atPath: dest), "the file is there")
        }
    }

    t.test("emoji: a delay already set stays, and an explicit sprite takes no default rows or delay") {
        sandbox("emoji-explicit") { home, log in
            setEnvVar("JEB_EMOJI_DELAY", "0.5")
            _ = printed { _ = cmdEmoji([]) }
            t.eq(envOf(log)["JEB_EMOJI_DELAY"], "0.5", "the set delay wins")
            setEnvVar("JEB_EMOJI_DELAY", nil)
            var rc: Int32 = 1
            _ = printed { rc = cmdEmoji(["--sprite", "blue-wag", "-o", home + "/out/x.gif"]) }
            let env = envOf(log)
            t.eq(rc, 0)
            t.eq(env["JEB_EMOJI_SPRITE"], "blue-wag")
            t.eq(env["JEB_EMOJI_ROWS"], nil, "no rows unless asked")
            t.eq(env["JEB_EMOJI_DELAY"], nil, "no delay for another sprite")
            t.eq(env["JEB_EMOJI"], home + "/out/x.gif")
            _ = printed { _ = cmdEmoji(["--sprite", "blue-wag", "--rows", "0", "-o", home + "/out/y.gif"]) }
            t.eq(envOf(log)["JEB_EMOJI_ROWS"], "0", "0 is a whole number")
        }
    }

    t.test("emoji: --holiday names the file and sets JEB_HOLIDAY") {
        sandbox("emoji-holiday") { home, log in
            var rc: Int32 = 1
            let out = printed { rc = cmdEmoji(["--holiday", "pumpkin"]) }
            let dest = home + "/Pictures/Jeb/jeb-emoji-pumpkin.gif"
            t.eq(rc, 0)
            t.check(out.hasPrefix("export jeb-sip with \(home)/stub-bin to \(dest)\n"), "the file name carries the holiday")
            t.eq(envOf(log)["JEB_HOLIDAY"], "pumpkin")
            t.check(FileManager.default.fileExists(atPath: dest), "the file is there")
        }
    }

    t.test("emoji: a GIF over 128 KB gets the Slack note, one at the limit does not") {
        sandbox("emoji-big", size: 128 * 1024 + 1) { home, _ in
            var rc: Int32 = 1
            let out = printed { rc = cmdEmoji(["-o", "~/big.gif"]) }
            t.eq(rc, 0, "an oversized file is a warning, not a failure")
            t.eq(out.split(separator: "\n").last.map(String.init), "\(home)/big.gif  \(128 * 1024 + 1) bytes  (over Slack's 128 KB emoji limit)")
        }
        sandbox("emoji-limit", size: 128 * 1024) { home, _ in
            let out = printed { _ = cmdEmoji(["-o", "~/ok.gif"]) }
            t.eq(out.split(separator: "\n").last.map(String.init), "\(home)/ok.gif  \(128 * 1024) bytes")
        }
    }

    t.test("emoji: a failing export exits 1 with the last stderr line") {
        sandbox("emoji-fail", exit: 3) { _, _ in
            var rc: Int32 = 0
            let out = printed { rc = cmdEmoji([]) }
            t.eq(rc, 1)
            t.eq(out.split(separator: "\n").last.map(String.init), "emoji: the export failed (exit 3): last line")
        }
    }

    t.test("emoji: --dry-run prints the export line and runs nothing") {
        sandbox("emoji-dry") { home, log in
            dryRun = true
            var rc: Int32 = 1
            let out = printed { rc = cmdEmoji(["--holiday", "x"]) }
            t.eq(rc, 0)
            t.eq(out, "export jeb-sip with \(home)/stub-bin to \(home)/Pictures/Jeb/jeb-emoji-x.gif\n")
            t.check(!FileManager.default.fileExists(atPath: log), "the binary did not run")
            t.check(!FileManager.default.fileExists(atPath: home + "/Pictures"), "no folder was made")
        }
    }

    t.test("screenshot --list prints the fixture names") {
        sandbox("shot-list") { _, _ in
            var rc: Int32 = 1
            let out = printed { rc = cmdScreenshot(["--list"]) }
            t.eq(rc, 0)
            t.eq(out, "farm-day\ncamp-x\n")
        }
    }

    t.test("screenshot --fixture: a bad --hour or a missing name is a usage error (2)") {
        sandbox("shot-usage") { _, log in
            var rc: Int32 = 0
            var out = printed { rc = cmdScreenshot(["--fixture", "farm-day", "--hour", "abc"]) }
            t.eq(rc, 2)
            t.eq(out, "screenshot: --hour takes a number (0 to 24)\n")
            out = printed { rc = cmdScreenshot(["--fixture"]) }
            t.eq(rc, 2)
            t.eq(out, "screenshot: --fixture needs a name (`jebctl screenshot --list`)\n")
            out = printed { rc = cmdScreenshot(["--hour", "3", "--fixture"]) }
            t.eq(rc, 2, "--fixture last has no name")
            t.check(!FileManager.default.fileExists(atPath: log), "the binary never ran")
        }
    }

    t.test("screenshot --fixture: an unknown fixture and a missing binary exit 1") {
        sandbox("shot-missing", stub: false) { home, _ in
            var rc: Int32 = 0
            var out = printed { rc = cmdScreenshot(["--fixture", "nope"]) }
            t.eq(rc, 1)
            t.eq(out, "screenshot: no fixture 'nope' (`jebctl screenshot --list`)\n")
            out = printed { rc = cmdScreenshot(["--fixture", "farm-day"]) }
            t.eq(rc, 1)
            t.eq(out, "screenshot: no binary at \(home)/missing\n")
        }
    }

    t.test("screenshot --fixture: renders with the fixture's moment, place and env, then prints the PNG path") {
        sandbox("shot-render", size: 10) { home, log in
            var rc: Int32 = 1
            let out = printed { rc = cmdScreenshot(["--fixture", "camp-x", "--out", home + "/shots/../shots", "--hour", "13.5"]) }
            let dest = home + "/shots/camp-x.png"
            t.eq(rc, 0)
            t.eq(out, "render fixture camp-x with \(home)/stub-bin to \(dest)\n\(dest)\n")
            t.check(FileManager.default.fileExists(atPath: dest), "the PNG is there")
            let env = envOf(log)
            t.eq(env["JEB_BENCH"], "0.01")
            t.eq(env["JEB_BENCH_FREEZE"], "1")
            t.eq(env["JEB_BENCH_PNG"], dest)
            t.eq(env["JEB_NOW"], "5")
            t.eq(env["JEB_PLACE"], "camp")
            t.eq(env["JEB_PLACE_SINCE"], "77")
            t.eq(env["JEB_EXTRA"], "yes")
            t.eq(env["JEB_HOUR"], "13.5")
            t.check(env["JEB_HOME"].map { $0 != home + "/state" && $0.contains("jeb-shot-") } ?? false, "the app gets a scratch JEB_HOME")
            t.check(env["JEB_STORE_PATH"].map { $0.hasPrefix(env["JEB_HOME"] ?? "?") } ?? false, "and a scratch store")
            t.check(!FileManager.default.fileExists(atPath: env["JEB_HOME"] ?? home), "the scratch folder is removed")
            _ = printed { _ = cmdScreenshot(["--fixture", "farm-day", "--out", home + "/shots"]) }
            t.eq(envOf(log)["JEB_HOUR"], nil, "no --hour, no JEB_HOUR")
            t.eq(envOf(log)["JEB_PLACE_SINCE"], nil, "no seed time unless the fixture has one")
        }
    }

    t.test("screenshot --fixture: a failed render exits 1, --dry-run runs nothing") {
        sandbox("shot-fail", exit: 4) { home, log in
            var rc: Int32 = 0
            var out = printed { rc = cmdScreenshot(["--fixture", "farm-day", "--out", home + "/o"]) }
            t.eq(rc, 1)
            t.eq(out.split(separator: "\n").last.map(String.init), "screenshot: the render failed (exit 4)")
            try? FileManager.default.removeItem(atPath: log)
            dryRun = true
            out = printed { rc = cmdScreenshot(["--fixture", "farm-day", "--out", home + "/dry"]) }
            t.eq(rc, 0)
            t.eq(out, "render fixture farm-day with \(home)/stub-bin to \(home)/dry/farm-day.png\n")
            t.check(!FileManager.default.fileExists(atPath: log), "nothing ran")
            t.check(!FileManager.default.fileExists(atPath: home + "/dry"), "no folder was made")
        }
    }

    t.test("screenshot (live): with no app running it says so and exits 1; the signal path needs a real app") {
        sandbox("shot-live") { _, _ in
            var rc: Int32 = 0
            let out = printed { rc = cmdScreenshot([]) }
            t.eq(rc, 1)
            t.eq(out, "screenshot: need exactly one running JebDesktop, found 0\n")
        }
    }
}
