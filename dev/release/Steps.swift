// Steps: what a release does in the clone, in order: the checks, the
// version, the mod checks, the universal build, the parity and day gates (desktop/gates/jebgates on a snapshot), the
// release commit, the app zip, the universal jebctl and the signed tag. Nothing is written before every check passed,
// and nothing is ever pushed here.
import Foundation

func appZipName(_ tag: String) -> String { "JebDesktop-\(tag)-macos.zip" }

/// The gate helpers the app zip carries beside JebDesktop; not in git, so they are compiled here (cwd = desktop/src or
/// its snapshot; the last argument is the -o target).
let gateTools: [(String, [String])] = [
    ("detect", ["swiftc", "-O", "tools/detect-src/main.swift", "Art.swift", "PixelArt.swift", "Farm.swift", "Holiday.swift", "-o", "tools/detect"]),
    ("png2raw", ["swiftc", "-O", "tools/png2raw.swift", "-o", "tools/png2raw"]),
]

private func strip(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

private func seconds(since t: Double) -> String { String(format: "%.0fs", Clock.now - t) }

/// The last n non-empty lines of a tool's output, on one line.
private func tail(_ text: String, _ n: Int = 3) -> String {
    let lines = splitLines(strip(text)).map(strip).filter { !$0.isEmpty }
    return String(lines.suffix(n).joined(separator: " / ").prefix(500))
}

/// One release step on one line; its output is shown only when it fails (tty: let it talk to the terminal).
func step(_ label: String, _ cmd: [String], cwd: String? = nil, env: [String: String]? = nil, tty: Bool = false) {
    if dryRun {
        say("  \(label): skipped (dry run)")
        return
    }
    if tty { say("  \(label) ...") } else { print("  \(label) ...", terminator: " "); fflush(stdout) }
    let t = Clock.now
    let r = run(absolute(cmd, cwd: cwd), cwd: cwd, env: env, capture: !tty)
    if r.status != 0 {
        if !tty {
            say("failed")
            say(splitLines(r.text).suffix(30).joined(separator: "\n"))
        }
        stop("\(label) failed")
    }
    if !tty { say("ok (\(seconds(since: t)))") }
}

/// The default branch: origin/HEAD, else main.
func baseBranch() -> String {
    let head = strip(git("symbolic-ref", "--short", "-q", "refs/remotes/origin/HEAD").out)
    guard let i = head.firstIndex(of: "/") else { return "main" }
    return String(head[head.index(after: i)...])
}

/// The file that holds jebctl's pinned signers (`let signerLines = [`), relative to the clone.
func signerConstFile() -> String { "desktop/cli/Signers.swift" }

/// The signers the native jebctl pins (signerLines) must be exactly the (principal, key type, key) of the
/// desktop/release-signers lines that cover jeb-release, and each must carry namespaces="jeb-release" and nothing else.
func checkSignerConst() {
    let file = signerConstFile()
    func bad() -> Never {
        stop("the signers in \(file) (signerLines) are not the jeb-release lines of desktop/release-signers; fix one of them, no tag")
    }
    let body = reMatch(#"(?ms)^let signerLines = \[\n(.*?)^\]"#, readText(clone + "/" + file) ?? "")?[1] ?? ""
    var const = Set<[String]>()
    for l in splitLines(body) {
        let s = l.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s.hasPrefix("//") { continue }
        guard let q = reMatch(#"^\s*"((?:[^"\\]|\\.)*)",?\s*$"#, l) else { bad() }
        let t = fields(q[1].replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression))
        if t.count != 4 || t[1] != "namespaces=\"jeb-release\"" { bad() }
        const.insert([t[0], t[2], t[3]])
    }
    var want = Set<[String]>()
    for l in splitLines(readText(signersPath) ?? "") {
        let t = fields(l)
        guard let k = keyLine(l), let ns = k.ns, ns.names.contains("jeb-release"), let i = t.firstIndex(of: k.blob), i > 0 else { continue }
        want.insert([t[0], t[i - 1], t[i]])
    }
    if const.isEmpty || const != want { bad() }
}

/// Release side: compiles each gate helper for arm64 and x86_64 from desktop/src and lipos them into dest/<name>.
/// An error text, or nil.
func buildUniversalTools(_ src: String, _ dest: String) -> String? {
    try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
    for (n, cmd) in gateTools {
        var parts: [String] = []
        for arch in ["arm64", "x86_64"] {
            let out = "\(dest)/\(n).\(arch)"
            let r = run(absolute(cmd.dropLast() + [out, "-target", "\(arch)-apple-macos12"]), cwd: src)
            if r.status != 0 { return "\(n) (\(arch)): \(tail(r.err.isEmpty ? r.out : r.err))" }
            parts.append(out)
        }
        let r = run([tool("lipo"), "-create", "-output", dest + "/" + n] + parts, cwd: src)
        if r.status != 0 { return "\(n) (lipo): \(tail(r.err.isEmpty ? r.out : r.err))" }
        for p in parts { unlink(p) }
    }
    return nil
}

// ---- the gates ----

/// A copy of desktop/src for the gates, so the tracked fixtures stay untouched: the sources, build.sh, tools/ (no
/// pictures), the band's picture and the binary just built.
private func snapshot(_ src: String, _ dest: String) throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: dest + "/fixtures", withIntermediateDirectories: true)
    for n in try fm.contentsOfDirectory(atPath: src) where n.hasSuffix(".swift") || n == "build.sh" || n == "JebDesktop.dev" {
        try fm.copyItem(atPath: src + "/" + n, toPath: dest + "/" + n)
    }
    try fm.copyItem(atPath: src + "/tools", toPath: dest + "/tools")
    for case let n as String in fm.enumerator(atPath: dest + "/tools") ?? .init() where n.hasSuffix(".png") || (n as NSString).lastPathComponent == "__pycache__" {
        try? fm.removeItem(atPath: dest + "/tools/" + n)
    }
    try fm.copyItem(atPath: src + "/fixtures/band-out.txt", toPath: dest + "/fixtures/band-out.txt")
}

/// desktop/gates/jebgates, built when missing or older than a source of it. Nil when it cannot be built.
private func gatesTool() -> String? {
    let dir = desk + "/gates", bin = dir + "/jebgates"
    func mtime(_ p: String) -> Double {
        var st = stat()
        return stat(p, &st) == 0 ? Double(st.st_mtimespec.tv_sec) : 0
    }
    let sources = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".swift") || $0 == "build.sh" }.map { dir + "/" + $0 }
    if !isExecutableFile(bin) || (sources + [desk + "/cli/Json.swift"]).contains(where: { mtime($0) > mtime(bin) }) {
        if run(["/bin/sh", dir + "/build.sh"]).status != 0 { return nil }
    }
    return isExecutableFile(bin) ? bin : nil
}

/// The parity gate, then the scripted day, on a snapshot of desktop/src with the binary just built. Either failing
/// stops the release.
private func gates() {
    print("  parity ...", terminator: " "); fflush(stdout)
    let base = envVar("TMPDIR") ?? NSTemporaryDirectory()
    var tmpl = Array(((base as NSString).appendingPathComponent("jeb-release-check-XXXXXX")).utf8CString)
    guard mkdtemp(&tmpl) != nil else { say("failed"); stop("could not make a folder for the parity snapshot") }
    let snap = String(cString: tmpl) + "/src"
    scratch.append(String(cString: tmpl))
    defer { cleanScratch(String(cString: tmpl)) }
    do { try snapshot(srcDir, snap) } catch { say("failed"); stop("could not snapshot desktop/src for the gates: \(error.localizedDescription)") }
    for (n, cmd) in gateTools where !FileManager.default.fileExists(atPath: "\(snap)/tools/\(n)") {
        let r = run(absolute(cmd), cwd: snap)
        if r.status != 0 { say("failed"); stop("could not build the parity helpers: \(n): \(tail(r.err.isEmpty ? r.out : r.err))") }
    }
    guard let jg = gatesTool() else { say("failed"); stop("could not build the gates (desktop/gates)") }
    // no JEB_* from outside but the mod: the gates read this clone's art
    var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("JEB_") }
    env["JEB_MOD"] = clone + "/mod"
    let at = ["--src", snap, "--bin", "JebDesktop.dev"]
    var r = run([jg, "parity", "gen"] + at, cwd: snap, env: env)
    var ok = r.status == 0
    var why = ok ? "" : "gen failed: " + tail(r.err)
    if ok {
        r = run([jg, "parity", "compare"] + at, cwd: snap, env: env)
        if r.status == 0, let m = reMatch(#"-- (\d+) of (\d+) fixtures pass"#, r.out) {
            ok = m[1] == m[2] && (Int(m[2]) ?? 0) > 0
            why = "\(m[1]) of \(m[2]) fixtures pass" + splitLines(r.out).filter { $0.hasPrefix("FAIL") }.prefix(3).map { "; " + $0.prefix(200) }.joined()
        } else {
            ok = false
            why = "compare failed: " + tail(r.err.isEmpty ? r.out : r.err)
        }
    }
    say("\(ok ? "ok" : "failed") (\(why))")
    if !ok { stop("parity gate failed; no tag") }
    print("  day ...", terminator: " "); fflush(stdout)
    r = run([jg, "day", "all"] + at, cwd: snap, env: env)
    ok = r.status == 0 && r.out.contains("scripted day: all good")
    let told = splitLines(r.out).filter { $0.contains("FAIL") || $0.hasPrefix("    ") }.joined(separator: "\n")
    say(ok ? "ok (scripted day all good)" : "failed (\(tail(told.isEmpty ? (r.err.isEmpty ? r.out : r.err) : told)))")
    if !ok { stop("day gate failed; no tag") }
}

func cleanScratch(_ d: String) {
    try? FileManager.default.removeItem(atPath: d)
    scratch.removeAll { $0 == d }
}

// ---- the steps ----

/// The release in this clone, up to the signed local tag: (tag, base branch). args: --parity, --bump <level>.
/// wrapped: ./release goes on to the bundles and the push itself, so the hints about them are left out.
func releaseSteps(_ args: [String], wrapped: Bool) -> (tag: String, base: String) {
    if !lexists(clone + "/.git") { stop("releases are cut from a development clone with ./release") }
    if git("rev-parse", "--git-dir").status != 0 { stop("not a git clone: " + clone) }
    if !strip(git("status", "--porcelain").out).isEmpty { stop("the tree is not clean (commit or stash first)") }
    let base = baseBranch()
    if cfg("user.signingkey").isEmpty {
        stop("no signing key configured: releases are signed tags. Set user.signingkey (and `git config gpg.format ssh` for an SSH key), then run again")
    }
    let cur = strip(git("branch", "--show-current").out)
    if cur != base { stop("releases are cut from \(base); this clone is on \(cur.isEmpty ? "a detached HEAD" : cur)") }
    var bump = "auto"
    if let i = args.firstIndex(of: "--bump") { bump = i + 1 < args.count ? args[i + 1] : "" }
    if !["auto", "patch", "minor", "major"].contains(bump) { stop("--bump takes auto, patch, minor or major") }
    let runner: GitRunner = { git($0) }
    let atHead = headTags(git: runner)
    if !atHead.isEmpty { stop("HEAD already carries a release tag: " + atHead.joined(separator: ", ")) }
    guard let plugin = Json.load(pluginJson), plugin.object != nil else { stop("cannot read \(pluginJson): not a JSON object") }
    let fileVersion = plugin["version"]?.string
    var notes: String
    let version: String
    let last = releaseTags(git: runner).last
    if let last = last, let key = tagKey(last) {
        let p = releasePlan(last)
        notes = p.notes
        if bump == "auto" {
            guard let level = p.level else {
                stop("no feat, fix, perf, revert or breaking commits since \(last), so nothing to release "
                     + "(commit subjects follow Conventional Commits; pass patch, minor or major to release anyway)")
            }
            say("bump: \(level) (from the commits since \(last))")
            bump = level
        } else {
            say("bump: \(bump) (forced)")
        }
        switch bump {
        case "major": version = "\(key.0 + 1).0.0"
        case "minor": version = "\(key.0).\(key.1 + 1).0"
        default: version = "\(key.0).\(key.1).\(key.2 + 1)"
        }
    } else {
        version = initialVersion
        notes = "First release."
        say("no release tag yet: starting at \(version)" + (bump == "auto" ? "" : " (--bump \(bump) applies from the next release)"))
    }
    let tag = "v" + version
    say("releasing \(tag)" + (last.map { " (last release \($0))" } ?? " (first release)"))
    checkSignerConst()
    step("validate plugin", ["claude", "plugin", "validate", "mod"], cwd: clone)
    step("validate marketplace", ["claude", "plugin", "validate", "."], cwd: clone)
    step("test plugin", ["claude", "plugin", "test", "mod"], cwd: clone)
    step("release build", ["./build.sh"], cwd: srcDir, env: environ(["JEB_OUT": "JebDesktop.dev", "JEB_UNIVERSAL": "1"]))
    if args.contains("--parity") {
        if dryRun { say("  parity: skipped (dry run)") } else { gates() }
    }
    if version != fileVersion {
        if !dryRun {
            let text = readText(pluginJson) ?? ""
            var new = text
            if let re = try? NSRegularExpression(pattern: #"("version"\s*:\s*")[^"]*(")"#), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let whole = Range(m.range, in: text), let a = Range(m.range(at: 1), in: text), let b = Range(m.range(at: 2), in: text) {
                new.replaceSubrange(whole, with: String(text[a]) + version + String(text[b]))
            }
            guard (try? Json.parse(new))?["version"]?.string == version, (try? new.write(toFile: pluginJson, atomically: false, encoding: .utf8)) != nil else {
                stop("could not write the version into \(pluginJson); no commit, no tag")
            }
        }
        step("commit chore(release): \(tag)", ["git", "-C", clone, "commit", "-q", "-m", "chore(release): \(tag)", "--", pluginJson])
        stage = 2
    }
    let name = appZipName(tag)
    var message = "Jeb \(tag)"
    if dryRun {
        say("  app zip: skipped (dry run); would attach \(name)")
    } else {
        let fm = FileManager.default
        let adir = gitPath("jeb-release-\(tag)")
        let staged = adir + "/stage"        // the zip holds JebDesktop and the gate helpers, no parent folder
        try? fm.removeItem(atPath: adir)
        do {
            try fm.createDirectory(atPath: staged, withIntermediateDirectories: true)
            try fm.copyItem(atPath: srcDir + "/JebDesktop.dev", toPath: staged + "/JebDesktop")
        } catch { stop("could not stage the app in \(staged): \(error.localizedDescription)") }
        print("  gate helpers (universal) ...", terminator: " "); fflush(stdout)
        let t = Clock.now
        if let why = buildUniversalTools(srcDir, staged) {
            say("failed")
            stop("could not build the gate helpers: " + why)
        }
        say("ok (\(seconds(since: t)))")
        let zp = adir + "/" + name
        step("app zip", ["ditto", "-c", "-k", staged, zp])
        guard let zip = FileManager.default.contents(atPath: zp) else { stop("cannot read the app zip \(zp)") }
        message = "Jeb \(tag)\n\napp-sha256: \(sha256Hex(zip)) \(name)"
        // after the zip, so the app zip stays as it was; the stage folder is what the bundles are built from
        step("jebctl (universal)", ["./build.sh"], cwd: desk + "/cli", env: environ(["JEB_UNIVERSAL": "1", "JEB_OUT": staged + "/jebctl", "JEB_VERSION": tag]))
        step("jebctl signature", ["codesign", "--verify", staged + "/jebctl"])
    }
    step("sign tag \(tag)" + (wrapped ? "" : " (asks for the key's passphrase)"), ["git", "-C", clone, "tag", "-s", tag, "-m", message], tty: true)
    if notes.isEmpty { notes = "Maintenance release." }
    if dryRun {
        say("release notes:\n" + notes)
    } else {
        try? (notes + "\n").write(toFile: gitPath("jeb-release-notes-\(tag).md"), atomically: false, encoding: .utf8)
    }
    if !wrapped {
        say("\(dryRun ? "would tag" : "tagged") \(tag) (local only; never pushed by jebctl). To publish it, run:\n  git push origin \(base) \(tag)")
    }
    return (tag, base)
}
