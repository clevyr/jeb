// Procs: the running JebDesktop processes, their heartbeat files, the quit marker, and the detached helpers that
// outlive a jebctl run. Ported from desktop/jebctl (ours, running, terminate_all, beat_files, write_quit_marker,
// wait_pid, prune_versions, cmd_prune_versions). JEB_TEST_NO_PROCS=1 answers "none running" without asking ps, as
// the golden capture patched running() (plan 3.1).
import Foundation

struct Proc: Equatable {
    var pid: Int32
    var start: Double       // epoch seconds, from ps lstart
    var path: String
}

/// The installed app's executable, or a binary under the live source folder: the only JebDesktops signalled.
func ours(_ path: String) -> Bool {
    let p = pyRealpath(path)
    return p == pyRealpath(installedExe) || p.hasPrefix(pyRealpath(liveSrc) + "/")
}

/// One line of `ps -axo pid=,uid=,lstart=,comm=` as (pid, uid, start, path), or nil for a line of another shape.
func parsePsLine(_ l: String) -> (pid: Int32, uid: uid_t, start: Double, path: String)? {
    guard let m = reMatch(#"^\s*(\d+)\s+(\d+)\s+(\w{3} \w{3}\s+\d+ [\d:]{8} \d{4})\s+(.*)$"#, l),
          let pid = Int32(m[1]), let uid = uid_t(m[2]) else { return nil }
    let stamp = m[3].split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    var tm = tm()
    guard strptime(stamp, "%a %b %d %H:%M:%S %Y", &tm) != nil else { return nil }
    tm.tm_isdst = -1
    return (pid, uid, Double(mktime(&tm)), m[4])
}

struct FakeProcsError: Error, CustomStringConvertible { let description: String }

/// The JebDesktop processes (ours, owned by this uid), oldest first. fake ("pid:start:path,...") replaces ps;
/// installedOnly (the watchdog) signals nothing but the installed app. JEB_TEST_NO_PROCS=1 is an empty ps (the sandboxes).
func runningProcs(fake: String? = nil, installedOnly: Bool = false) throws -> [Proc] {
    var out: [Proc] = []
    if let fake = fake {
        for x in fake.split(separator: ",") {
            let f = x.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard f.count == 3, let pid = Int32(f[0]), let start = Double(f[1]) else { throw FakeProcsError(description: "bad --fake-procs entry '\(x)'") }
            out.append(Proc(pid: pid, start: start, path: String(f[2])))
        }
    } else if envVar("JEB_TEST_NO_PROCS") != "1" {
        for l in run(["/bin/ps", "-axo", "pid=,uid=,lstart=,comm="]).out.split(separator: "\n") {
            guard let p = parsePsLine(String(l)), p.uid == getuid(), (p.path as NSString).lastPathComponent == "JebDesktop" else { continue }
            out.append(Proc(pid: p.pid, start: p.start, path: p.path))
        }
    }
    let mine = installedOnly ? pyRealpath(installedExe) : nil
    return out.filter { proc in mine.map { pyRealpath(proc.path) == $0 } ?? ours(proc.path) }.sorted { ($0.start, $0.pid) < ($1.start, $1.pid) }
}

func running() -> [Proc] { (try? runningProcs()) ?? [] }

func terminateAll() {
    for p in running() { kill(p.pid, SIGTERM) }
}

struct Beat: Equatable {
    var stamp: String?
    var waiting: Bool
    var age: Double         // seconds since the file was written
}

/// JEB_HOME/heartbeat/<pid>: the stamp each running app wrote, whether it waits to take over, and the file's age.
/// liveOnly skips the file of a pid that no longer exists (signal 0 only asks); reap also deletes it.
func beatFiles(liveOnly: Bool = false, reap: Bool = false) -> [Int32: Beat] {
    let d = stateHome + "/heartbeat"
    var out: [Int32: Beat] = [:]
    for n in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] {
        guard !n.isEmpty, n.allSatisfy({ $0.isASCII && $0.isNumber }), let pid = Int32(n) else { continue }
        if liveOnly && kill(pid, 0) != 0 && errno == ESRCH {
            if reap { unlink(d + "/" + n) }
            continue
        }
        guard let j = Json.load(d + "/" + n), j.object != nil else { continue }
        var st = stat()
        guard stat(d + "/" + n, &st) == 0 else { continue }
        let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        out[pid] = Beat(stamp: j["stamp"]?.string, waiting: j["waiting"]?.truthy ?? false, age: Clock.now - mtime)
    }
    return out
}

/// The marker the watchdog honours: quit stays quit until a login or `jebctl start`.
func writeQuitMarker() {
    makePrivateDir(stateHome)
    let fd = open(stateHome + "/quit", O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    guard fd >= 0 else { die("jebctl: cannot write \(stateHome)/quit") }
    _ = "jebctl\n".withCString { write(fd, $0, 7) }
    close(fd)
}

// ---- detached helpers ----

/// Starts argv in a new session with stdin from /dev/null and both outputs appended to output (default /dev/null),
/// and does not wait for it (subprocess.Popen(..., start_new_session=True)). False when it could not start.
@discardableResult
func spawnDetached(_ argv: [String], env: [String: String], output: String? = nil) -> Bool {
    var actions: posix_spawn_file_actions_t?
    var attr: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attr)
    defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attr) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, output ?? "/dev/null", O_WRONLY | O_CREAT | O_APPEND, 0o644)
    posix_spawn_file_actions_adddup2(&actions, 1, 2)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var cargv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
    var cenv: [UnsafeMutablePointer<CChar>?] = env.map { strdup($0.key + "=" + $0.value) } + [nil]
    defer { for p in cargv + cenv { free(p) } }
    var pid: pid_t = 0
    return posix_spawn(&pid, argv[0], &actions, &attr, &cargv, &cenv) == 0
}

/// Wait for --wait-pid to exit, at most 120 s. True once it is gone (or none was given).
func waitPid(_ args: [String]) -> Bool {
    var pid: Int32 = 0
    if let i = args.firstIndex(of: "--wait-pid"), i + 1 < args.count {
        guard let p = Int32(args[i + 1]) else { die("jebctl: --wait-pid takes a pid") }
        pid = p
    }
    if pid == 0 { return true }
    for _ in 0..<240 {
        if kill(pid, 0) != 0 && errno == ESRCH { return true }
        Clock.sleep(0.5)
    }
    return false
}

// ---- the one-version rule ----

/// Only the folder `current` points to stays in ~/.jeb/versions, and no .*.partial leftover. The folder this process
/// runs from stays until the next run (follow starts with this); nothing goes while current does not resolve.
func pruneVersions() {
    let vd = versionsDir(), fm = FileManager.default
    var isDir: ObjCBool = false
    let live = fm.fileExists(atPath: currentDir(), isDirectory: &isDir) && isDir.boolValue ? pyRealpath(currentDir()) : nil
    let me = codeBundle() != nil ? pyRealpath((codeDir() as NSString).deletingLastPathComponent) : nil
    for n in ((try? fm.contentsOfDirectory(atPath: vd)) ?? []).sorted() {
        let p = vd + "/" + n
        if n.hasPrefix(".") && n.hasSuffix(".partial") {
            // a download that never finished: always goes
        } else if live == nil || pyRealpath(p) == live {
            continue
        } else if pyRealpath(p) == me {
            detail("versions: \(n) is this process's own folder; it goes once this run exits")
            continue
        }
        detail("versions: removing \(n)")
        if !dryRun { try? fm.removeItem(atPath: p) }
    }
}

/// Hidden: pruneVersions once --wait-pid has exited; a process still running from an old folder keeps it for the next run.
func cmdPruneVersions(_ args: [String]) {
    if waitPid(args) { pruneVersions() }
}
