// Spawn: child runs through posix_spawn. Captured runs (validate, tsc, tests, npm) get their own process group, and a timeout
// kills the group (DESIGN decision 4iii); the builder run gets its own session, writes to a file, and its whole group is killed
// after it ends. Environment: the caller's, minus every CLAUDE* variable, with the tool folders first on PATH.
import Foundation

/// No CLAUDE_* from a calling session (it would load the user's mods into the builder), and PATH with no empty entry.
func toolEnv(_ c: Ctx) -> [String: String] {
    var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CLAUDE") }
    env["HOME"] = c.p.home  // the run's own home (the caller's HOME in production); lets concurrent test cases each have theirs
    let base = c.p.home + "/.local/bin:/opt/homebrew/bin:/usr/local/bin"
    env["PATH"] = (ProcessInfo.processInfo.environment["PATH"]).flatMap { $0.isEmpty ? nil : base + ":" + $0 } ?? base
    return env
}

/// Start `argv` in `cwd` with stdin from /dev/null and the given stdout and stderr, in a new session or process group.
/// Returns the pid, or nil and the error text.
func spawnChild(_ argv: [String], cwd: String, env: [String: String], out: Int32, err: Int32, session: Bool) -> (pid_t?, String) {
    var fa: posix_spawn_file_actions_t? = nil, at: posix_spawnattr_t? = nil
    posix_spawn_file_actions_init(&fa); posix_spawnattr_init(&at)
    defer { posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&at) }
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&fa, out, 1); posix_spawn_file_actions_adddup2(&fa, err, 2)
    posix_spawn_file_actions_addchdir(&fa, cwd)
    if session { posix_spawnattr_setflags(&at, Int16(POSIX_SPAWN_SETSID)) }
    else { posix_spawnattr_setpgroup(&at, 0); posix_spawnattr_setflags(&at, Int16(POSIX_SPAWN_SETPGROUP)) }
    let a = argv.map { strdup($0) } + [nil], e = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { a.forEach { free($0) }; e.forEach { free($0) } }
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, argv[0], &fa, &at, a, e)
    return rc == 0 ? (pid, "") : (nil, String(cString: strerror(rc)))
}

/// waitpid result as Python's returncode: the exit status, or minus the signal.
func exitCode(_ status: Int32) -> Int32 { status & 0x7f == 0 ? (status >> 8) & 0xff : -(status & 0x7f) }

/// SIGKILL a whole process group; a missing group is fine, a permission error is logged.
func killGroup(_ c: Ctx, _ pgid: pid_t) {
    if killpg(pgid, SIGKILL) != 0 && errno == EPERM { c.log("warning: could not kill the builder process group: \(String(cString: strerror(errno)))") }
}

/// Captured run: (code, stdout, stderr). A timeout kills the group and returns 124 and `timed out`; a spawn failure 127.
func runSplit(_ c: Ctx, _ argv: [String], cwd: String, timeout: Int) -> (Int32, String, String) {
    var po: [Int32] = [0, 0], pe: [Int32] = [0, 0]
    pipe(&po); pipe(&pe)
    let (pid, why) = spawnChild(argv, cwd: cwd, env: toolEnv(c), out: po[1], err: pe[1], session: false)
    close(po[1]); close(pe[1])
    guard let pid = pid else { close(po[0]); close(pe[0]); return (127, "", why) }
    var bufs: [[UInt8]] = [[], []], open = [po[0], pe[0]], status: Int32 = 0, done = false, timedOut = false
    let deadline = Date().addingTimeInterval(Double(timeout))
    while !done {
        if Date() >= deadline { timedOut = true; break }
        var fds = open.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
        if fds.isEmpty { usleep(20_000) } else { poll(&fds, nfds_t(fds.count), 100) }
        for f in fds where f.revents != 0 {
            var buf = [UInt8](repeating: 0, count: 1 << 16)
            let n = read(f.fd, &buf, buf.count)
            if n > 0 { bufs[f.fd == po[0] ? 0 : 1] += buf[0..<n] } else { close(f.fd); open.removeAll { $0 == f.fd } }
        }
        if open.isEmpty && waitpid(pid, &status, WNOHANG) == pid { done = true }
    }
    open.forEach { close($0) }
    if timedOut { killGroup(c, pid); waitpid(pid, &status, 0); return (124, "", "timed out") }
    return (exitCode(status), utf8Ignore(bufs[0]), utf8Ignore(bufs[1]))
}

func run(_ c: Ctx, _ argv: [String], cwd: String, timeout: Int) -> (Int32, String) {
    let (code, out, err) = runSplit(c, argv, cwd: cwd, timeout: timeout)
    return (code, out + err)
}

/// The builder: in its own session, output to `outPath` (0600, no link followed) rather than a pipe so a leftover child cannot
/// hold the runner, and the whole group killed afterwards. Returns (code, output); 124 on timeout, 127 if it cannot start.
func runBuilder(_ c: Ctx, _ argv: [String], cwd: String, timeout: Int, outPath: String) -> (Int32, String) {
    let fd = open(outPath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
    if fd < 0 { return (127, String(cString: strerror(errno))) }
    let (pid, why) = spawnChild(argv, cwd: cwd, env: toolEnv(c), out: fd, err: fd, session: true)
    close(fd)
    guard let pid = pid else { return (127, why) }
    var status: Int32 = 0, code: Int32 = 124
    let deadline = Date().addingTimeInterval(Double(timeout))
    while Date() < deadline {
        if waitpid(pid, &status, WNOHANG) == pid { code = exitCode(status); break }
        usleep(50_000)
    }
    killGroup(c, pid)
    if code == 124 { waitpid(pid, &status, 0) }
    chmod600(outPath)
    return (code, readText(outPath) ?? "")
}
