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
        t.check(f.dry && f.noAgents && f.verbose && f.repin && f.path.add && f.replaceClone, "every flag is read")
        t.eq(f.bad, nil, "none is bad")
        t.eq(f.forward, ["--dry-run", "--no-agents", "--verbose", "--repin", "--add-path"], "forwarded without --replace-clone")
        t.eq(parseStandaloneFlags([]), StandaloneFlags(), "no flags is the default")
        let g = parseStandaloneFlags(["--add-path=zsh,nu", "--no-agents"])
        t.eq(g.path.shells, ["zsh", "nu"])
        t.eq(g.forward, ["--no-agents", "--add-path=zsh,nu"], "the list is forwarded")
        t.eq(parseStandaloneFlags(["--no-add-path"]).forward, ["--no-add-path"])
        t.check(parseStandaloneFlags(["--add-path", "--no-add-path"]).path.error != nil, "the clash is an error")
        t.check(parseStandaloneFlags(["--add-path=tcsh"]).path.error != nil, "an unknown shell is an error")
        t.eq(parseStandaloneFlags(["--add-path=tcsh"]).bad, nil, "and not an unknown option")
        for gone in ["--dev", "--build-from-source", "--mode"] { t.eq(parseStandaloneFlags(["--dry-run", gone, "--other"]).bad, gone, "\(gone) is unknown (D1)") }
        sandbox("flags") { _ in
            var rc: Int32 = 0
            let out = printed { rc = standaloneInstall(["--dev"], handOff: { _, _ in 99 }) }
            t.eq(rc, 2, "an unknown option exits 2")
            t.eq(out, "jebctl install: unknown option --dev\n" + standaloneUsage + "\n")
        }
    }

    t.test("standalone: update repeats while the installed tag changes, up to three passes, and stops on failure") {
        /// Runs the loop with a scripted update: each call returns the next (rc, tag after) pair.
        func loop(_ steps: [(Int32, String)], start: String = "v1.4.0") -> (rc: Int32, calls: Int, out: String) {
            var tag = start, calls = 0
            var rc: Int32 = 0
            let out = printed { rc = standaloneUpdateLoop(update: { let s = steps[min(calls, steps.count - 1)]; calls += 1; tag = s.1; return s.0 }, readTag: { tag }) }
            return (rc, calls, out)
        }
        var r = loop([(0, "v1.4.0")])
        t.eq(r.calls, 1, "one pass when the tag does not change")
        t.eq(r.out, "", "and nothing extra is said")
        r = loop([(0, "v1.6.0"), (0, "v1.7.0"), (0, "v1.7.0")])
        t.eq(r.calls, 3, "a change twice then none is three passes")
        r = loop([(0, "v1.6.0"), (0, "v1.6.0")])
        t.eq(r.calls, 2, "two passes when the tag changes once")
        t.check(r.out.contains("updated to v1.6.0; checking for a newer release"), "the extra pass is announced")
        r = loop([(0, "v1.5.0"), (0, "v1.6.0"), (0, "v1.7.0"), (0, "v1.8.0")])
        t.eq(r.calls, 3, "it stops at three passes")
        r = loop([(0, "v1.6.0"), (1, "v1.6.0"), (0, "v1.7.0")])
        t.eq(r.calls, 2, "it stops on a failing update")
        t.eq(r.rc, 1, "and returns that exit code")
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

    t.test("standalone: JEB_RELEASE_TAG installs that tag instead of the newest") {
        sandbox("pinned-tag") { home in
            writeFile(home + "/no-releases/latest", "v9.9.9")
            let was = envVar("JEB_RELEASE_TAG")
            setEnvVar("JEB_RELEASE_TAG", "v1.5.0")
            defer { setEnvVar("JEB_RELEASE_TAG", was) }
            var rc: Int32 = 99
            let out = printed { rc = standaloneInstall(["--dry-run", "--no-agents"], handOff: { _, _ in 98 }) }
            t.eq(rc, 0, "a dry run succeeds")
            t.check(out.contains("release (JEB_RELEASE_TAG): v1.5.0") && out.contains("/download/v1.5.0/"), "it names the pinned tag: \(out)")
            t.check(!out.contains("v9.9.9"), "not the newest: \(out)")
        }
    }

    t.test("standalone: a live schema 2 with a dangling older link is relinked, and one that is current is left") {
        sandbox("dangling") { home in
            schema2(home + "/.jeb/versions/v1")
            try? FileManager.default.createSymbolicLink(atPath: home + "/.jeb/current", withDestinationPath: "versions/v1")
            let bin = home + "/bin"
            try? FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            let was = envVar("JEB_BIN_DIR")
            setEnvVar("JEB_BIN_DIR", bin)
            defer { setEnvVar("JEB_BIN_DIR", was) }
            try? FileManager.default.createSymbolicLink(atPath: bin + "/jebctl", withDestinationPath: home + "/jeb/desktop/jebctl")
            t.eq(linkState(), "older", "a link to a clone that is gone is older")
            _ = printed { _ = standaloneInstall([], update: { 0 }, readTag: { "v1" }, latest: { nil }) }
            t.eq(linkState(), "ours", "relinked")
        }
    }

    t.test("standalone: a schema 1 live bundle takes the fresh path") {
        sandbox("schema1") { home in
            schema2(home + "/.jeb/versions/v1")
            writeFile(home + "/.jeb/versions/v1/bundle.json", "{\"schema\":1,\"tag\":\"v1.4.0\"}")
            try? FileManager.default.createSymbolicLink(atPath: home + "/.jeb/current", withDestinationPath: "versions/v1")
            var updated = false
            var fetched: [String] = []
            writeFile(home + "/no-releases/latest", "v9.9.9")
            let out = printed { _ = standaloneInstall(["--dry-run"], update: { updated = true; return 0 }, fetch: { tag, _ in fetched.append(tag); return (nil, nil) }) }
            t.check(!updated, "no update is run on a schema 1 bundle")
            t.check(out.contains("newest release: v9.9.9"), out)
        }
    }

    t.test("standalone: a fake jebctl first on PATH makes the hint name the absolute path") {
        sandbox("hint") { home in
            schema2(home + "/.jeb/versions/v1")
            try? FileManager.default.createSymbolicLink(atPath: home + "/.jeb/current", withDestinationPath: "versions/v1")
            let was = envVar("PATH")
            writeFile(home + "/fakebin/jebctl", "#!/bin/sh\n", mode: 0o755)
            setEnvVar("PATH", home + "/fakebin:" + (was ?? ""))
            defer { setEnvVar("PATH", was) }
            t.check(selfCommand() != "jebctl", "not the bare name: \(selfCommand())")
            t.check(selfCommand().hasPrefix("/"), "an absolute path")
        }
    }

    t.test("standalone: a failed fetch leaves no jebctl- folder behind") {
        sandbox("fetch-clean") { _ in
            let root = t.scratch("tmproot")
            var got: (path: String?, err: BundleError?) = (nil, nil)
            _ = printed { got = standaloneFetch("v9.9.9", tmpRoot: root) }
            t.eq(got.path, nil, "nothing was fetched")
            t.check(got.err != nil, "and it says why")
            let left = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter { $0.hasPrefix("jebctl-") }
            t.eq(left, [], "the temp folder is gone")
        }
    }

    t.test("standalone: an installed Jeb sets up PATH only when the update finished, and add-path's status is the exit code") {
        sandbox("installed-addpath") { home in
            schema2(home + "/.jeb/versions/v1")
            try? FileManager.default.createSymbolicLink(atPath: home + "/.jeb/current", withDestinationPath: "versions/v1")
            t.check(liveValid(), "the live bundle is usable")
            var calls: [[String]] = []
            var rc: Int32 = 9
            var out = printed { rc = standaloneInstall(["--add-path=zsh"], update: { 1 }, addPath: { calls.append($0); return 0 }, readTag: { "v1" }) }
            t.eq(rc, 1, "the update's failure is the exit code")
            t.eq(calls, [], "add-path is not run after a failed update")
            t.check(out.contains("note: PATH setup was skipped because the update did not finish; run `\(selfCommand()) add-path` to set it up"), out)
            out = printed { rc = standaloneInstall(["--add-path=zsh"], update: { 0 }, addPath: { calls.append($0); return 0 }, readTag: { "v1" }) }
            t.eq(rc, 0)
            t.eq(calls, [["zsh"]], "run after a good update, with the shells asked for")
            t.check(!out.contains("skipped"), out)
            _ = printed { rc = standaloneInstall(["--add-path"], update: { 0 }, addPath: { _ in 1 }, readTag: { "v1" }) }
            t.eq(rc, 1, "a failed add-path is folded into the exit code")
            calls = []
            _ = printed { rc = standaloneInstall([], update: { 0 }, addPath: { calls.append($0); return 1 }, readTag: { "v1" }) }
            t.eq(calls, [], "no --add-path: no add-path")
            t.eq(rc, 0)
        }
    }
}
