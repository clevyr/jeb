// The install's supervision hooks (phase 6): a heartbeat file per running instance, the
// quit marker, and how a start by launchd tells a login from a watchdog restart.
//
// Everything lives in JEB_HOME (default ~/Library/Application Support/Jeb; an install not yet migrated
// keeps ~/.claude/jeb-desktop, which jebctl, the updater and the watchdog move on their next run):
//   heartbeat/<pid>   rewritten every 2 s by a plain run-loop timer, paused or not: JSON with
//                     the pid, the build stamp, whether this instance is still waiting to
//                     take over from an older one, and the time. Removed on a clean exit.
//   quit              written by the menu's Quit (and `jebctl quit`); the watchdog starts
//                     nothing while it exists.
//   start-reason      written by the watchdog just before it kickstarts the agent.
// The heartbeat is on for a start by launchd (JEB_START set), run-live.sh (JEB_PID_FILE) or
// JEB_HEARTBEAT_DIR; measuring and test runs write none.

import Foundation

let jebHome: String = {
    if let h = env["JEB_HOME"] { return h }
    let new = NSHomeDirectory() + "/Library/Application Support/Jeb"
    let old = NSHomeDirectory() + "/.claude/jeb-desktop"
    let fm = FileManager.default
    if fm.fileExists(atPath: new) { return new }
    // the old folder counts only as a real directory (after a move it is a symlink to the new one)
    if let t = try? fm.attributesOfItem(atPath: old)[.type] as? FileAttributeType, t == .typeDirectory { return old }
    return new
}()
let quitMarkerPath = jebHome + "/quit"
let startReasonPath = jebHome + "/start-reason"
let heartbeatDir = env["JEB_HEARTBEAT_DIR"] ?? jebHome + "/heartbeat"
let heartbeatEnabled = env["JEB_START"] != nil || env["JEB_PID_FILE"] != nil || env["JEB_HEARTBEAT_DIR"] != nil
/// The build stamp the updater put in Info.plist; "dev" for a bare binary.
let buildStamp = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
let heartbeatFile = heartbeatDir + "/\(getpid())"

/// Writes `text` to `path` through a temp file and a rename, mode 0600.
func writePrivate(_ text: String, to path: String) {
    let tmp = path + ".tmp"
    let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    guard fd >= 0 else { return }
    let bytes = Array(text.utf8)
    let ok = write(fd, bytes, bytes.count) == bytes.count
    close(fd)
    if ok { rename(tmp, path) } else { unlink(tmp) }
}

/// Creates the directory and makes it 0700 even when it already existed with looser permissions.
func ensurePrivateDir(_ path: String) {
    mkdir(path, 0o700)
    chmod(path, 0o700)
}

func writeQuitMarker() {
    ensurePrivateDir(jebHome)
    writePrivate("\(getpid())\n", to: quitMarkerPath)
}

/// An older JebDesktop (not this process) with a heartbeat: the one a launchd start takes over from.
func otherInstance() -> Int32? {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: heartbeatDir) else { return nil }
    for name in names {
        guard let pid = Int32(name), pid > 1, pid != getpid(), kill(pid, 0) == 0 else { continue }
        var buffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0, (String(cString: buffer) as NSString).lastPathComponent == "JebDesktop" { return pid }
    }
    return nil
}

/// A start by the launch agent (no handoff): a login or `jebctl start` clears the quit marker;
/// a watchdog start (it leaves start-reason) never does, and gives up if Quit was chosen meanwhile.
func startedByLaunchd() {
    guard env["JEB_START"] == "launchd", env["JEB_HANDOFF_FROM"] == nil else { return }
    let reason = modified(startReasonPath)
    unlink(startReasonPath)
    if let reason, Date().timeIntervalSince(reason) < 120 {
        if access(quitMarkerPath, F_OK) == 0 { log("watchdog start but Quit was chosen; exiting"); exit(0) }
    } else if unlink(quitMarkerPath) == 0 {
        log("start: quit marker cleared")
    }
}

/// The end of the latest pass animation (FarmScene.runPass): the fast frame rate is wanted until then.
var passUntil = Date.distantPast

final class Heartbeat {
    private var timer: Timer?
    private var last = Date()
    private var tRun = 0.0, tPass = 0.0, tCov = 0.0, tPause = 0.0
    /// Running or not, why not (the pause reason), and the sessions shown.
    var state: () -> (running: Bool, reason: String?, sessions: Int) = { (true, nil, 0) }
    private let prefix = "{\"pid\":\(getpid()),\"stamp\":\"\(buildStamp)\","
    /// True while this instance waits for a desktop Space to take over from an older one.
    var waiting: () -> Bool = { false }

    func start() {
        guard heartbeatEnabled else { return }
        ensurePrivateDir(jebHome)
        ensurePrivateDir(heartbeatDir)
        beat()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.beat() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        atexit { unlink(heartbeatFile) }
    }

    private func beat() {
        let now = Date(), dt = now.timeIntervalSince(last)
        last = now
        let s = state()
        if s.running {
            tRun += dt
            tPass += max(0, min(dt, passUntil.timeIntervalSince(now) + dt))
        } else if s.reason == "covered" { tCov += dt } else { tPause += dt }
        let counters = String(format: "\"tRun\":%.1f,\"tPass\":%.1f,\"tCov\":%.1f,\"tPause\":%.1f,\"sessions\":%d", tRun, tPass, tCov, tPause, s.sessions)
        writePrivate(prefix + "\"waiting\":\(waiting()),\"t\":\(Int(now.timeIntervalSince1970)),\(counters)}\n", to: heartbeatFile)
    }
}
