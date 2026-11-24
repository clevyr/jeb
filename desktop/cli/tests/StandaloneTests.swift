// StandaloneTests: the standalone `jebctl install` (Standalone.swift). HOME and every path are scratch ones, JEB_NO_LAUNCHCTL is
// set by run.sh, and nothing is downloaded: the release is never reached (the old-clone and unknown-option answers come first).
import Foundation

func standaloneTests(_ t: Tester) {
    /// Runs body with stdout pointed at a file; returns what was printed.
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
    /// A scratch HOME (also JEB_SETTINGS and JEB_BACKUPS); body gets it.
    func sandbox(_ name: String, _ body: (String) -> Void) {
        let home = t.scratch(name)
        let names = ["HOME", "JEB_SETTINGS", "JEB_BACKUPS", "JEB_HOME", "JEB_RELEASE_BASE"]
        let was = names.map { envVar($0) }, loud = verbose, dry = dryRun
        for (k, v) in zip(names, [home, home + "/settings.json", home + "/backups", home + "/Library/Application Support/Jeb", "file://" + home + "/no-releases"]) { setEnvVar(k, v) }
        defer {
            for (k, v) in zip(names, was) { setEnvVar(k, v) }
            verbose = loud
            dryRun = dry
        }
        body(home)
    }
    func schema2(_ dir: String, python: Bool = false, drop: String? = nil) {
        let python = python ? ",\"python\":\"python/bin/python3\"" : ""
        writeFile(dir + "/bundle.json", "{\"schema\":2,\"repo\":\"clevyr/jeb\",\"tag\":\"v9.9.9\",\"version\":\"9.9.9\",\"commit\":\"\(String(repeating: "0", count: 40))\",\"arch\":\"arm64\"\(python)}")
        for rel in ["desktop/bin/jebctl", "app/JebDesktop"] where rel != drop { writeFile(dir + "/" + rel, "#!/bin/sh\n", mode: 0o755) }
        for rel in ["desktop/release-signers", "mod/hooks/pixel-art.ts", ".claude-plugin/marketplace.json"] where rel != drop && !(drop == "mod" && rel.hasPrefix("mod/")) { writeFile(dir + "/" + rel, "x") }
    }

    t.test("standalone: flags parse, unknown ones are named, and --replace-clone stays out of what the bundle is told") {
        let f = parseStandaloneFlags(["--dry-run", "--no-agents", "--verbose", "--repin", "--add-path", "--replace-clone"])
        t.check(f.dry && f.noAgents && f.verbose && f.repin && f.addPath && f.replaceClone, "every flag is read")
        t.eq(f.bad, nil, "none is bad")
        t.eq(f.forward, ["--dry-run", "--no-agents", "--verbose", "--repin", "--add-path"], "forwarded without --replace-clone")
        t.eq(parseStandaloneFlags([]), StandaloneFlags(), "no flags is the default")
        for gone in ["--dev", "--build-from-source", "--mode"] { t.eq(parseStandaloneFlags(["--dry-run", gone, "--other"]).bad, gone, "\(gone) is unknown (D1)") }
        sandbox("flags") { _ in
            var rc: Int32 = 0
            let out = printed { rc = standaloneInstall(["--dev"], handOff: { _, _ in 99 }) }
            t.eq(rc, 2, "an unknown option exits 2")
            t.eq(out, "jebctl install: unknown option --dev\n" + standaloneUsage + "\n")
        }
    }

    t.test("standalone: the built-in signers are the jeb-release lines of desktop/release-signers") {
        let file = readFile(NSString(string: envVar("JEB_REPO") ?? ".").expandingTildeInPath + "/desktop/release-signers") ?? ""
        // (principal, key type, key) of the lines whose namespaces include jeb-release
        var want: [[String]] = []
        for line in file.split(separator: "\n") {
            let f = fields(String(line))
            guard f.count >= 4, f[1].hasPrefix("namespaces=\""), f[1].dropFirst(12).dropLast().split(separator: ",").contains("jeb-release") else { continue }
            want.append([f[0], f[2], f[3]])
        }
        t.check(!want.isEmpty, "release-signers has jeb-release lines")
        t.eq(signerLines.map { l -> [String] in let f = fields(l); return [f[0], f[2], f[3]] }, want, "same keys as release-signers")
        for l in signerLines {
            t.eq(fields(l)[1], "namespaces=\"jeb-release\"", "only the jeb-release namespace")
            t.check(!l.contains("clevyr.com"), "no personal key")
        }
    }

    t.test("standalone: a bundle root is bundle.json with desktop/bin/jebctl") {
        let d = t.scratch("root")
        t.check(!isBundleRoot(d), "an empty folder is not one")
        writeFile(d + "/bundle.json", "{}")
        t.check(!isBundleRoot(d), "bundle.json alone is not")
        writeFile(d + "/desktop/bin/jebctl", "#!/bin/sh\n", mode: 0o755)
        t.check(isBundleRoot(d), "both make one")
        let dev = t.scratch("devroot")
        writeFile(dev + "/desktop/bin/jebctl", "#!/bin/sh\n", mode: 0o755)
        t.check(!isBundleRoot(dev), "a dev build (no bundle.json) is standalone")
    }

    t.test("standalone: a schema 2 bundle is accepted; an incomplete, schema 1 or python one is refused") {
        let ok = t.scratch("s2ok")
        schema2(ok)
        t.eq(standaloneBundleProblem(ok), nil, "a complete schema 2 bundle")
        for rel in ["desktop/bin/jebctl", "desktop/release-signers", "mod", ".claude-plugin/marketplace.json", "app/JebDesktop"] {
            let d = t.scratch("s2-" + rel.replacingOccurrences(of: "/", with: "_"))
            schema2(d, drop: rel)
            t.check(standaloneBundleProblem(d)?.contains(rel) == true, "missing \(rel) is named: \(standaloneBundleProblem(d) ?? "accepted")")
        }
        let py = t.scratch("s2py")
        schema2(py, python: true)
        t.check(standaloneBundleProblem(py)?.contains("Python") == true, "a python key is refused")
        let one = t.scratch("s1")
        schema2(one)
        writeFile(one + "/bundle.json", "{\"schema\":1,\"tag\":\"v1.4.0\"}")
        t.check(standaloneBundleProblem(one)?.contains("schema 1") == true, "schema 1 is refused")
        let plain = t.scratch("noexec")
        schema2(plain)
        chmod(plain + "/desktop/bin/jebctl", 0o644)
        t.check(standaloneBundleProblem(plain)?.contains("not executable") == true, "a non-executable jebctl is refused")
        t.check(standaloneBundleProblem(t.scratch("none")) != nil, "no bundle.json is refused")
    }

    t.test("standalone: an old clone is named, with --replace-clone as the way on") {
        sandbox("clone") { home in
            writeFile(home + "/.jeb/repo/desktop/jebctl", "#!/bin/sh\n", mode: 0o755)
            var rc: Int32 = 0
            let out = printed { rc = standaloneInstall([], handOff: { _, _ in 99 }) }
            t.eq(rc, 1, "refused")
            t.eq(out, "an old install is at \(home)/.jeb/repo: run jebctl install --replace-clone\n")
            t.check(isRegularFile(home + "/.jeb/repo/desktop/jebctl"), "the clone is where it was")
            t.check(!lexists(home + "/.jeb/repo.old"), "and nothing moved")
        }
        sandbox("clone-home") { home in
            writeFile(home + "/jeb/desktop/jebctl", "#!/bin/sh\n", mode: 0o755)
            t.eq(oldCloneInstall(), home + "/jeb", "a clone at ~/jeb is found too")
        }
        sandbox("noclone") { _ in t.eq(oldCloneInstall(), nil, "none, none") }
    }

    t.test("standalone: --replace-clone --dry-run changes nothing") {
        sandbox("replace-dry") { home in
            let clone = home + "/.jeb/repo"
            writeFile(clone + "/desktop/jebctl", "#!/bin/sh\n", mode: 0o755)
            let settings = "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"\(clone)/mod\"}}"
            writeFile(home + "/settings.json", settings)
            writeFile(home + "/no-releases/latest", "v9.9.9")      // the dry run reads the newest tag, nothing more
            var rc: Int32 = 99
            let out = printed { rc = standaloneInstall(["--replace-clone", "--dry-run", "--no-agents"], handOff: { _, _ in 98 }) }
            t.eq(rc, 0, "a dry run succeeds")
            t.check(out.contains("would move \(clone) to \(clone).old"), "it says what it would move: \(out)")
            t.check(out.contains("would remove it"), "and the entry: \(out)")
            t.check(isRegularFile(clone + "/desktop/jebctl") && !lexists(clone + ".old"), "the clone did not move")
            t.eq(readFile(home + "/settings.json"), settings, "settings.json is untouched")
            t.check(!lexists(home + "/backups"), "and nothing was backed up")
            t.check(!lexists(home + "/Library"), "no state folder was made")
        }
    }

    t.test("standalone: --replace-clone moves the clone aside and drops its plugin entry, and refuses an existing .old") {
        sandbox("replace") { home in
            let clone = home + "/.jeb/repo"
            writeFile(clone + "/desktop/jebctl", "#!/bin/sh\n", mode: 0o755)
            writeFile(home + "/settings.json", "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"\(clone)/mod:/elsewhere/mod\"}}")
            let rc = printed { t.check(replaceOldClone(clone, parseStandaloneFlags(["--no-agents"])) == nil, "carry on") }
            t.check(rc.contains("moved \(clone) to \(clone).old"), rc)
            t.check(isRegularFile(clone + ".old/desktop/jebctl") && !lexists(clone), "the clone is now <clone>.old")
            let after = readFile(home + "/settings.json") ?? ""
            t.check(!after.contains(clone) && after.contains("/elsewhere/mod"), "only Jeb's entry left settings.json: \(after)")
            t.check(((try? FileManager.default.contentsOfDirectory(atPath: home + "/backups")) ?? []).count == 1, "after one backup")
            writeFile(clone + "/desktop/jebctl", "#!/bin/sh\n", mode: 0o755)
            var again: Int32?
            _ = printed { again = replaceOldClone(clone, parseStandaloneFlags(["--no-agents"])) }
            t.eq(again, 1, "a second one will not overwrite <clone>.old")
            t.check(isRegularFile(clone + "/desktop/jebctl"), "and leaves the clone")
        }
    }
}
