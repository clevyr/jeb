// Smoke: ./release smoke [TAG], the sandboxed end-to-end check of a published release. It downloads the release the
// way a new user does: the release's install.sh (which fetches jebctl-macos and runs `jebctl install`) with
// --no-agents under a fake HOME, then checks what it left; jebctl-macos is also checked against the signed manifest.
// Never touches the real install.
import Foundation

let smokeMin = (1, 5, 0)      // the first release whose jebctl-macos installs without gh

private func strip(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

/// Where releases are read: $JEB_RELEASE_BASE, else github.com/<origin's repo>/releases.
private func smokeBase() -> String {
    let m = reMatch(#"github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?$"#, strip(git("remote", "get-url", "origin").out))
    return releaseBase(m?[1] ?? repo)
}

/// Every child's environment: the owner's PATH but a fake HOME, no JEB_* from outside (but JEB_RELEASE_BASE) and no launchctl.
private func smokeEnv(_ home: String, _ extra: [String: String] = [:]) -> [String: String] {
    var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("JEB_") && $0.key != "CLAUDE_CODE_PLUGIN_DIRS" }
    for (k, v) in ["HOME": home, "CLAUDE_CONFIG_DIR": home + "/.claude", "JEB_APP_DIR": home + "/Applications", "JEB_LAUNCHAGENTS": home + "/Library/LaunchAgents",
                   "JEB_SETTINGS": home + "/.claude/settings.json", "JEB_BACKUPS": home + "/.claude/backups/jeb", "JEB_STORE_DIR": home + "/.claude/plugins/store",
                   "JEB_BIN_DIR": home + "/.local/bin", "JEB_PROFILE": home + "/.zprofile", "JEB_NO_LAUNCHCTL": "1"] { env[k] = v }
    if let b = envVar("JEB_RELEASE_BASE"), !b.isEmpty { env["JEB_RELEASE_BASE"] = b }
    for (k, v) in extra { env[k] = v }
    return env
}

private func fileSize(_ path: String) -> Int {
    var st = stat()
    return stat(path, &st) == 0 ? Int(st.st_size) : -1
}

/// Download the release's jebctl-macos: its SHA-256 and size equal the signed manifest's. The path, or why not.
private func smokeJebctl(_ dl: String, _ tag: String, _ base: String, _ want: Json) -> (path: String?, why: String) {
    let p = dl + "/jebctl-macos"
    do { try save("\(base)/download/\(tag)/jebctl-macos", to: p, limit: want["size"]?.int ?? 0) } catch { return (nil, "jebctl-macos download failed: \(error)") }
    if want["sha256"]?.string != sha256Hex(FileManager.default.contents(atPath: p) ?? Data()) || want["size"]?.int != fileSize(p) {
        return (nil, "jebctl-macos does not match the signed manifest")
    }
    chmod(p, 0o755)
    return (p, "")
}

/// Download, install with --no-agents, check. pinned: the tag was named, so the binary is told it (else it finds the
/// newest itself). (passed, text)
private func smokeCase(_ sandbox: String, _ home: String, _ tag: String, _ base: String, pinned: Bool) -> (Bool, String) {
    let fm = FileManager.default
    let t0 = Date()
    let arch = hostArch()
    let state = home + "/Library/Application Support/Jeb"
    let env = smokeEnv(home, pinned ? ["JEB_RELEASE_TAG": tag] : [:])
    func bad(_ why: String) -> (Bool, String) { (false, "FAIL: " + why) }
    let dl = sandbox + "/download"
    do {
        try fm.createDirectory(atPath: home + "/Library", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dl, withIntermediateDirectories: true)
    } catch { return bad("could not make the sandbox: \(error.localizedDescription)") }
    let man = "Jeb-\(tag)-manifest.json"
    do {
        for n in [man, man + ".sig"] { try save("\(base)/download/\(tag)/\(n)", to: dl + "/" + n, limit: 64 << 10) }
    } catch { return bad("download failed: \(error)") }
    if !signedBy(dl + "/" + man, dl + "/" + man + ".sig", signers: signersPath) {
        return bad("the manifest signature does not verify against desktop/release-signers (jeb-release)")
    }
    guard let doc = Json.load(dl + "/" + man), doc["tag"]?.string == tag, let want = doc["jebctl"], want.object != nil else {
        return bad("the signed manifest names another tag or lists no jebctl")
    }
    let got = smokeJebctl(dl, tag, base, want)
    guard let ctl = got.path else { return bad(got.why) }
    let v = run([ctl, "--version"], env: env)
    if v.status != 0 || !v.out.contains(tag) { return bad("jebctl-macos --version said '\(strip(v.out))', not \(tag)") }
    let ver = home + "/.jeb/versions/" + tag
    // The way a user installs: the release's install.sh, which fetches the newest jebctl-macos and runs its install.
    // A named tag (which may not be the newest; JEB_RELEASE_TAG makes this tag's jebctl install it) and a release older than
    // install.sh (v1.7.0) install with this tag's jebctl directly. From v1.7.0 on, a missing install.sh fails the smoke.
    let script = dl + "/install.sh"
    var r: (status: Int32, text: String)
    if !pinned, let k = tagKey(tag), k >= (1, 7, 0) {
        do { try save("\(base)/download/\(tag)/install.sh", to: script, limit: 64 << 10) }
        catch { return bad("install.sh download failed: \(error)") }
        var viaScript = env
        viaScript["JEB_RELEASE_BASE"] = base
        let s = run([tool("sh"), script, "--no-agents"], cwd: sandbox, env: viaScript)
        r = (s.status, s.text)
    } else {
        let s = run([ctl, "install", "--no-agents"], cwd: sandbox, env: env)
        r = (s.status, s.text)
    }
    try? (r.text + "\n").write(toFile: sandbox + "/install.log", atomically: false, encoding: .utf8)
    if r.status != 0 { return bad("install exit \(r.status): " + String(splitLines(r.text).suffix(3).joined(separator: " | ").prefix(400))) }
    let app = home + "/Applications/JebDesktop.app"
    if !isRealDir(app) && !fm.fileExists(atPath: app + "/Contents") { return bad("\(app) was not installed") }
    if run([tool("codesign"), "--verify", app]).status != 0 { return bad("codesign --verify failed on the installed app") }
    let cur = home + "/.jeb/current"
    if (try? fm.destinationOfSymbolicLink(atPath: cur)) == nil || pyRealpath(cur) != pyRealpath(ver) { return bad("\(cur) does not point at \(ver)") }
    let info = fm.contents(atPath: app + "/Contents/Info.plist").flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
    let jm = info?["JebMod"] as? String
    if jm != cur + "/mod" { return bad("Info.plist JebMod is \(jm.map { "'\($0)'" } ?? "None"), not \(cur)/mod") }
    guard let ulog = readText(state + "/update.log") else { return bad("no update.log in \(state)") }
    if !ulog.contains("using the prebuilt binary") { return bad("the app was not the release's prebuilt one") }
    let dirs = Json.load(home + "/.claude/settings.json")?["env"]?["CLAUDE_CODE_PLUGIN_DIRS"]?.string ?? ""
    if dirs.split(separator: ":").contains(where: { $0.contains("/.jeb/") }) { return bad("settings.json still lists a ~/.jeb entry in CLAUDE_CODE_PLUGIN_DIRS") }
    let listed = (try? Json.parse(run(absolute(["claude", "plugin", "list", "--json"]), env: env).out))?.array ?? []
    let plug = listed.first { $0["id"]?.string == "jeb@jeb" }
    guard let path = plug?["installPath"]?.string, pyRealpath(path).hasPrefix(pyRealpath(home)) else {
        return bad("`claude plugin list` does not show jeb@jeb installed under the sandbox")
    }
    let left = (try? fm.contentsOfDirectory(atPath: (ver as NSString).deletingLastPathComponent)) ?? []
    if left != [tag] { return bad("versions/ holds " + left.joined(separator: ", ")) }
    return (true, "ok (prebuilt \(tag), \(arch), \(String(format: "%.0f", Date().timeIntervalSince(t0)))s)")
}

/// ./release smoke [TAG] [--dry-run]
func smoke(_ named: String?) -> Int32 {
    let base = smokeBase()
    let pinned = named != nil
    var tag = named ?? ""
    if let t = named {
        if tagKey(t) == nil { fail("\(t) is not a release tag (vX.Y.Z)") }
    } else if dryRun {
        tag = "<newest published>"
    } else {
        do { tag = try latestTag(base) } catch { fail("could not read the newest release of \(base): \(error)") }
    }
    if let k = tagKey(tag), k < smokeMin {
        fail("\(tag) is older than v\(smokeMin.0).\(smokeMin.1).\(smokeMin.2): their jebctl-macos installs with gh")
    }
    let root = gitPath("jeb-smoke")
    let sandbox = root + "/" + tag
    say("smoke \(tag) from \(base)\n  sandbox \(sandbox) (fake HOME inside; an earlier one is moved to \(root)/old-<time>)\n"
        + "  HTTPS download of the manifest, signature and jebctl-macos, verify, then the release's install.sh --no-agents (it runs jebctl install, which downloads this Mac's zip,\n"
        + "  unpacks into <home>/.jeb/versions/<tag> and runs the bundle's own install); then jebctl follow --dry-run and jebctl doctor (JEB_NO_LAUNCHCTL=1)")
    if dryRun {
        say("dry run: nothing was created.")
        return 0
    }
    let fm = FileManager.default
    try? fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    if lexists(sandbox) {
        let aside = "\(root)/old-\(Clock.strftime("%Y%m%d-%H%M%S"))-\(tag)"
        if rename(sandbox, aside) != 0 { fail("could not move the previous sandbox \(sandbox) aside") }
        say("  moved the previous sandbox to \(aside)")
    }
    if (try? fm.createDirectory(atPath: sandbox, withIntermediateDirectories: true)) == nil { fail("could not make \(sandbox)") }
    let home = sandbox + "/home"
    let (ok, text) = smokeCase(sandbox, home, tag, base, pinned: pinned)
    say("smoke fresh install: \(text)")
    var passed = ok
    if ok {
        let ctl = home + "/.jeb/current/desktop/bin/jebctl"
        var r = run([ctl, "follow", "--no-agents", "--dry-run"], cwd: sandbox, env: smokeEnv(home))
        say("smoke follow --dry-run: " + String((splitLines(r.text).last ?? "(no output)").prefix(200)))
        if r.status != 0 || r.text.contains("could not reach") || reMatch("is current|would download", r.text) == nil {
            say("smoke follow --dry-run: FAIL")
            passed = false
        }
        r = run([ctl, "doctor"], cwd: sandbox, env: smokeEnv(home))
        let lines = splitLines(r.text)
        say("smoke doctor (agents are not loaded in a sandbox; those FIX lines are expected):\n" + lines.map { "  " + $0 }.joined(separator: "\n"))
        let crit = lines.filter { $0.hasPrefix("FIX") && reMatch("app bundle|mod folder|signers|state folder|bundle|version", $0) != nil }
        if !crit.isEmpty {
            say("smoke doctor: FAIL: " + crit.map { String($0.prefix(120)) }.joined(separator: "; "))
            passed = false
        }
    }
    say("sandbox: \(sandbox)\n" + (passed ? "smoke passed" : "smoke FAILED"))
    return passed ? 0 : 1
}
