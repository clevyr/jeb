// Commands: the small jebctl commands and the --help text. The text is cut to the bundle-only
// command set (plan D1, D4): no `release`, no --mode or --build-from-source, no git-clone layout.
import Foundation

/// What an unknown command (and so --help) prints, before exit 2.
let helpText = #"""
jebctl: install, supervise and update the desktop (phase 6). Exactly one JebDesktop at all times.

  status                  process, stamp, heartbeat age, last update result, versions
  migrate                 move the state folder from ~/.claude/jeb-desktop to ~/Library/Application Support/Jeb
                          (install, follow and the updater do this on their own; the old path stays as a link)
  doctor                  read-only health check: one line per check (ok / FIX with the fix), exit 1 on a problem
                          (JEB_NO_LAUNCHCTL=1 skips the launchctl queries: `skipped (sandbox)`)
  install [--repin] [--add-path] [--no-agents] [--dry-run] [--verbose]
                          one short line per step (--verbose: every command and detail). Run from a release bundle
                          (<root>/bundle.json exists: ~/.jeb/versions/<tag>/ unpacked from a release zip): no git and no
                          compile. The bundle's app is gated (smoke, headless start; refuses if one fails) and swapped in,
                          ~/.jeb/current is pointed at the bundle, and the plists, the plugin entry and the ~/.local/bin
                          link name only ~/.jeb/current paths. Then the LaunchAgents, hand over from a running instance,
                          then bootstrap; com.jeb.desktop.release runs `follow` every 6 h.
                          The install pins the signers: desktop/release-signers (ssh allowed_signers format, in the
                          bundle) is copied to JEB_HOME/release-signers (0600) when that file does not exist yet (trust
                          on first install). --repin replaces the pin by hand. Later releases' files are followed: once a
                          release is verified against the pin (and at the start of each follow, from the installed
                          release) its desktop/release-signers replaces the pin when that release is newer than the one
                          the pin came from (release-state signers_from).
                          Last, `jebctl` is linked into ~/.local/bin (JEB_BIN_DIR); a different file already at that
                          path is left alone. The PATH is optional: one line says to run ~/.local/bin/jebctl, and
                          --add-path adds that folder to the shell profile (zsh ~/.zprofile, bash ~/.bash_profile,
                          else ~/.profile; JEB_PROFILE; backup first).
                          --no-agents (sandbox only, used by ./release smoke): everything above up to the install-mode file and
                          the plists in JEB_HOME/launchd, but no hand-over, no copy into LaunchAgents, no launchctl,
                          no wait for the desktop, no jebctl link (each prints `skipped (--no-agents)`). Refused
                          unless HOME differs from the account's real home and the app, LaunchAgents and state
                          folders are under HOME. `follow`, `reload-agents` and `rollback` take it too (sandbox tests).
  uninstall [--purge] [--remove-files] [--purge-farm] [--dry-run] [--verbose]
                          one short line per step (--verbose: every command and detail). Bootout, remove the
                          plists and the app; versions and logs stay unless --purge (removes everything in JEB_HOME);
                          also the ~/.local/bin/jebctl link (only if it points here) and the PATH lines install added.
                          --remove-files and --purge-farm run the bundle's `uninstall` script with all the flags (it also takes
                          the plugin out of Claude Code (jeb@jeb and the "jeb" marketplace) and deletes ~/.jeb); see ./uninstall
  follow [--gates-only] [--quick] [--dry-run]
                          the newest published release (github.com/<repo>/releases/latest, a web redirect, not the API)
                          newer than the installed one (when that one was rejected, the older ones from releases.atom) is
                          downloaded (manifest, signature, this Mac's zip), verified against the pinned signers
                          (JEB_HOME/release-signers; none pinned: nothing happens) for the `jeb-release` namespace,
                          unpacked beside the live version, gated, then ~/.jeb/current is switched and the older folder
                          removed (one version on disk). --gates-only stops after the gates. Log: JEB_HOME/release.log
                          Progress and the final result (and why a check did nothing) go to JEB_HOME/update-status.json,
                          which the menu bar shows; the menu's click file JEB_HOME/check-now is cleared at the start.
  rollback                put the previous good release (release-state `installed`) back: it is downloaded again, gated
                          and switched to, and the bad one is deleted; a failed download changes nothing
  reload-agents [--wait-pid PID]
                          hidden: wait for PID to exit, then bootout and bootstrap the release LaunchAgents
  prune-versions [--wait-pid PID]  hidden: once PID exits, delete every ~/.jeb/versions folder except the one ~/.jeb/current points to
  watchdog [args]         hidden: what the watchdog agent runs (through desktop/bin/jebctl) every 30 s; see `watchdog --help`
  screenshot [--dry-run]  save what the running app draws (SIGUSR2; one PNG per screen into ~/Pictures/Jeb, or
                          JEB_SHOT_DIR) and print the paths (from JEB_HOME/screenshot-last). Needs exactly one
                          running JebDesktop whose build has it; waits up to 10 s
  screenshot --fixture NAME [--out DIR] [--hour H]
                          headless, never touches the running app: the parity fixture NAME rendered by the
                          installed binary (JEB_BIN overrides) with the bench, to <DIR>/NAME.png (default: the
                          current directory); --hour fixes the hour of day. screenshot --list: the fixture names
  emoji [--holiday NAME] [--sprite NAME] [--rows N] [-o FILE]
                          animated GIF of a sprite for a Slack custom emoji (128 x 128, transparent, looping), made by
                          the installed binary (JEB_BIN overrides) in its export mode, which exits before the app
                          starts, so the running instance is never touched. --sprite default jeb-sip (Jeb taking a pull
                          from his moonshine jar, 28 rows so the lowered jar stays in frame, 1.2 s a frame like the
                          farm); --rows the top rows kept (default 20, the menu bar's head, or 28 for the default
                          sprite; 0 the whole sprite); --holiday NAME uses that
                          holiday's variant (the base when it has none). Default file ~/Pictures/Jeb/jeb-emoji[-NAME].gif.
                          Prints the path and size; warns past Slack's 128 KB limit
  pause-updates | resume-updates
  start | quit            quit writes the marker the watchdog honours; start clears it
  update | update-now     check for a release now and wait for the result: starts the release agent (as the menu's Check for
                          Updates does), prints each phase on one line, then `updated to vX`, `vX is current` or the reason;
                          exit 0 for updated or current, 1 otherwise or when updates are paused or the agent is not loaded;
                          gives up waiting after 30 minutes (the update goes on; see status). --dry-run starts nothing
  retry-update            run the last bundle update again: clears the newest failed release, then restarts the
                          release agent (launchctl kickstart -k), which looks for a release at once
  plists                  (re)write the LaunchAgent plists into launchd/ only
  perf [--days N] [--stamp S]
                          the watchdog's telemetry (telemetry/*.csv, a row per ~30 s): per stamp and class
                          (calm, passing, covered, ...) the samples, median and p95 CPU %, max RSS and
                          footprint, flagged OVER past the targets (median CPU: calm 0.5, passing 4,
                          covered 0.1; RSS 60 MB; footprint 120 MB). Default: the last day, all stamps

JEB_HOME (state root), JEB_APP_DIR (default ~/Applications), JEB_LAUNCHAGENTS (default ~/Library/LaunchAgents),
JEB_BIN_DIR (default ~/.local/bin), JEB_PROFILE and JEB_BACKUPS and JEB_TOOLS_DIR (the standalone jebctl, default
~/.jeb/bin) override the defaults, and JEB_RELEASE_BASE (where releases are read; a test server), mostly for tests.
JEB_NO_LAUNCHCTL=1 (sandbox) skips the launchctl calls.
The mod path rendered into the plists (JEB_MOD) is ~/.jeb/current/mod: the agents only ever name `current`.

"""#

/// (Re)write the LaunchAgent plists into JEB_HOME/launchd only.
func cmdPlists() { writePlists(stateHome + "/launchd") }

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
