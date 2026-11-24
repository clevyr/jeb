// Commands: the small jebctl commands and the --help text. The text is cut to the bundle-only
// command set (plan D1, D4): no `release`, no --mode or --build-from-source, no git-clone layout.
import Foundation

/// What an unknown command (and so --help) prints, before exit 2.
let helpText = #"""
jebctl: install, supervise and update the Jeb desktop.

  install                 install or repair Jeb
  update                  check for a new version now and wait for the result
  status                  is Jeb running, which version, last update
  doctor [--fix]          health check; --fix runs the safe repair steps, then checks again
  start | quit            start or stop the desktop
  screenshot              save what Jeb draws to ~/Pictures/Jeb and print the paths
  emoji [--holiday NAME] [--sprite NAME] [-o FILE]
                          animated GIF of Jeb for a Slack custom emoji
  pause-updates | resume-updates
                          stop or resume automatic updates
  rollback                go back to the previous good release
  retry-update            run the last failed update again
  uninstall [--remove-files] [--purge] [--purge-farm]
                          removes the app, LaunchAgents, plugin registration and settings.json entry.
                          --remove-files also removes ~/.jeb (and an old clone with no local changes);
                          --purge empties JEB_HOME (~/Library/Application Support/Jeb);
                          --purge-farm backs up the farm to ~/.claude/backups/jeb, then removes it

More commands and flags: docs/reference.md
"""#

func cmdPauseUpdates() {
    guard FileManager.default.createFile(atPath: stateHome + "/updates-paused", contents: Data()) else { die("jebctl: cannot write \(stateHome)/updates-paused") }
    say("updates paused")
}

func cmdResumeUpdates() {
    unlink(stateHome + "/updates-paused")
    say("updates on")
}

/// Clears the quit marker and starts the desktop agent unless one already runs.
func cmdStart() {
    unlink(stateHome + "/quit")
    if !running().isEmpty { say("already running") } else { launchctl(["kickstart", "\(guiDomain)/com.jeb.desktop"]) }
}

func cmdQuit() {
    writeQuitMarker()
    terminateAll()
    say("quit; `jebctl start` (or the next login) brings it back")
}

// ---- screenshot and emoji ----

/// os.path.abspath: relative to the working folder, "." and ".." folded, symlinks left alone.
func pyAbspath(_ p: String) -> String {
    let full = p.hasPrefix("/") ? p : FileManager.default.currentDirectoryPath + "/" + p
    var parts: [Substring] = []
    for c in full.split(separator: "/") {
        if c == "." { continue }
        if c == ".." { _ = parts.popLast(); continue }
        parts.append(c)
    }
    return "/" + parts.joined(separator: "/")
}

/// The binary the app-side commands drive: JEB_BIN (when not empty), else the installed app's executable.
private func appBinary() -> String { pyAbspath(envVar("JEB_BIN").flatMap { $0.isEmpty ? nil : $0 } ?? installedExe) }

/// The parity fixtures of the live source folder (desktop/src/fixtures: smoke.json, else the store files).
private func screenshotFixtures() -> (dir: String, list: [GateFixture]) {
    let dir = liveSrc + "/fixtures"
    return (dir, gateFixtures(dir))
}

/// A signal to the one running app asks it to save its screens; the answer is JEB_HOME/screenshot-last.
private func screenshotLive() -> Int32 {
    let procs = running()
    guard procs.count == 1 else {
        say("screenshot: need exactly one running JebDesktop, found \(procs.count)")
        return 1
    }
    let pid = procs[0].pid
    if beatFiles()[pid]?.waiting ?? false {
        say("screenshot: pid \(pid) is still waiting to take over; try again in a moment")
        return 1
    }
    let has = FileManager.default.contents(atPath: procs[0].path).map { $0.range(of: Data("screenshot-last".utf8)) != nil } ?? false
    if !has {    // an older build has no SIGUSR2 handler, and the signal would end it
        say("screenshot: pid \(pid) runs a build without screenshots (not signalled); it will after the next update")
        return 1
    }
    let last = stateHome + "/screenshot-last"
    say("signal pid \(pid) (SIGUSR2) and wait up to 10 s for \(last)")
    if dryRun { return 0 }
    let t0 = Date().timeIntervalSince1970
    kill(pid, SIGUSR2)
    while Date().timeIntervalSince1970 - t0 < 10 {
        var st = stat()
        if stat(last, &st) == 0, Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9 > t0,
           let text = readText(last) {
            say(text.trimmingCharacters(in: .whitespacesAndNewlines))
            return 0
        }
        usleep(100_000)
    }
    say("screenshot: no answer within 10 s (see the app's log for `signal: screenshot failed`)")
    return 1
}

private func screenshotFixture(_ name: String, out: String?, hour: String?) -> Int32 {
    let (dir, all) = screenshotFixtures()
    guard let f = all.first(where: { $0.name == name }) else {
        say("screenshot: no fixture '\(name)' (`jebctl screenshot --list`)")
        return 1
    }
    let exe = appBinary()
    guard access(exe, X_OK) == 0 else {
        say("screenshot: no binary at \(exe)")
        return 1
    }
    let dest = pyAbspath(out ?? ".") + "/" + name + ".png"
    say("render fixture \(name) with \(exe) to \(dest)")
    if dryRun { return 0 }
    let store = dir + "/" + name + ".store.json"
    guard FileManager.default.fileExists(atPath: store) else {
        say("screenshot: no store file for fixture \(name) at \(store)")
        return 1
    }
    try? FileManager.default.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    var template = Array((NSTemporaryDirectory() + "/jeb-shot-XXXXXX").utf8CString)
    guard mkdtemp(&template) != nil else {
        say("screenshot: cannot make a scratch folder")
        return 1
    }
    let tmp = String(cString: template)
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    let scratchStore = tmp + "/store.json"
    guard (try? FileManager.default.copyItem(atPath: store, toPath: scratchStore)) != nil else {
        say("screenshot: cannot read \(store)")
        return 1
    }
    var env = ProcessInfo.processInfo.environment
    for (k, v) in [("JEB_BENCH", "0.01"), ("JEB_BENCH_FREEZE", "1"), ("JEB_BENCH_SCALE", "1"), ("JEB_BENCH_PNG", dest), ("JEB_STORE_PATH", scratchStore),
                   ("JEB_HOME", tmp), ("JEB_HEARTBEAT_DIR", tmp + "/heartbeat"), ("JEB_MOD", liveMod)] { env[k] = v }
    if let n = f.now { env["JEB_NOW"] = String(n) }
    if let p = f.place { env["JEB_PLACE"] = p }
    for (k, v) in f.env { env[k] = v }
    if let s = f.since { env["JEB_PLACE_SINCE"] = String(s) }
    if let h = hour { env["JEB_HOUR"] = h }
    let r = run([exe], env: env)
    if r.status != 0 || !FileManager.default.fileExists(atPath: dest) {
        say("screenshot: the render failed (exit \(r.status))")
        return 1
    }
    say(dest)
    return 0
}

func cmdScreenshot(_ args: [String]) -> Int32 {
    if args.contains("--list") {
        say(screenshotFixtures().list.map { $0.name }.joined(separator: "\n"))
        return 0
    }
    guard args.contains("--fixture") else { return screenshotLive() }
    func opt(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    let name = opt("--fixture"), hour = opt("--hour")
    if let h = hour, Double(h.trimmingCharacters(in: .whitespaces)) == nil {
        say("screenshot: --hour takes a number (0 to 24)")
        return 2
    }
    guard let n = name, !n.isEmpty else {
        say("screenshot: --fixture needs a name (`jebctl screenshot --list`)")
        return 2
    }
    return screenshotFixture(n, out: opt("--out"), hour: hour)
}

/// The animated GIF for a Slack custom emoji, made by the app binary's export mode (it exits before the app starts).
func cmdEmoji(_ args: [String]) -> Int32 {
    var opts: [String: String] = [:]
    var i = 0
    while i < args.count {
        guard ["--holiday", "--sprite", "--rows", "-o"].contains(args[i]), i + 1 < args.count else {
            say("usage: jebctl emoji [--holiday NAME] [--sprite NAME] [--rows N] [-o FILE]")
            return 2
        }
        opts[args[i]] = args[i + 1]
        i += 2
    }
    if let rows = opts["--rows"], rows.isEmpty || !rows.allSatisfy({ $0.isASCII && $0.isNumber }) {
        say("emoji: --rows takes a whole number (0 for the whole sprite)")
        return 2
    }
    let exe = appBinary()
    guard access(exe, X_OK) == 0 else {
        say("emoji: no binary at \(exe)")
        return 1
    }
    var env = ProcessInfo.processInfo.environment
    if opts["--sprite"] == nil {    // the default: Jeb sipping moonshine, the jar in frame both up and down
        opts["--sprite"] = "jeb-sip"
        if opts["--rows"] == nil { opts["--rows"] = "28" }
        if envVar("JEB_EMOJI_DELAY") == nil { setEnvVar("JEB_EMOJI_DELAY", "1.2"); env["JEB_EMOJI_DELAY"] = "1.2" }
    }
    let holiday = opts["--holiday"].flatMap { $0.isEmpty ? nil : $0 }
    let dest = pyAbspath(expandUser(opts["-o"].flatMap { $0.isEmpty ? nil : $0 } ?? "~/Pictures/Jeb/jeb-emoji" + (holiday.map { "-" + $0 } ?? "") + ".gif"))
    say("export \(opts["--sprite"]!) with \(exe) to \(dest)")
    if dryRun { return 0 }
    try? FileManager.default.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    env["JEB_EMOJI"] = dest
    env["JEB_MOD"] = liveMod
    for (flag, name) in [("--holiday", "JEB_HOLIDAY"), ("--sprite", "JEB_EMOJI_SPRITE"), ("--rows", "JEB_EMOJI_ROWS")] {
        if let v = opts[flag] { env[name] = v }
    }
    let r = run([exe], env: env)
    if r.status != 0 || !FileManager.default.fileExists(atPath: dest) {
        let last = r.err.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        say("emoji: the export failed (exit \(r.status)): " + last)
        return 1
    }
    let size = ((try? FileManager.default.attributesOfItem(atPath: dest))?[.size] as? Int) ?? 0
    say("\(dest)  \(size) bytes" + (size > 128 * 1024 ? "  (over Slack's 128 KB emoji limit)" : ""))
    return 0
}
