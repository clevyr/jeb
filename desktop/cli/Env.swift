// Env: the process environment, the clock, the output helpers and the child-process runner shared by every jebctl
// command. One clock type (plan D8):
// JEB_TEST_NOW pins time, JEB_TEST_PID the pid, and Clock.sleep advances the pinned clock instead of waiting,
// as the golden capture did. Foundation only; nothing here touches AppKit.
import Foundation

/// The environment at call time (libc getenv), so a test may change a variable between calls.
func envVar(_ name: String) -> String? {
    guard let v = getenv(name) else { return nil }
    return String(cString: v)
}

func setEnvVar(_ name: String, _ value: String?) {
    if let v = value { setenv(name, v, 1) } else { unsetenv(name) }
}

/// ~ for this process: $HOME when set (the sandboxes point it elsewhere), else the account's folder.
func homeDir() -> String { envVar("HOME") ?? NSHomeDirectory() }

/// os.path.expanduser for a leading "~/".
func expandUser(_ p: String) -> String { p == "~" ? homeDir() : p.hasPrefix("~/") ? homeDir() + p.dropFirst(1) : p }

func appDir() -> String { envVar("JEB_APP_DIR") ?? expandUser("~/Applications") }
func agentsDir() -> String { envVar("JEB_LAUNCHAGENTS") ?? expandUser("~/Library/LaunchAgents") }
/// Sandbox only: no launchctl, no Notification Center; doctor skips the launchctl queries and follow only logs the reload.
var noLaunchctl: Bool { envVar("JEB_NO_LAUNCHCTL") == "1" }

let sysPath = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"

// ---- clock ----

/// Wall-clock seconds and the pid, pinned by JEB_TEST_NOW / JEB_TEST_PID for the goldens. The pinned clock only moves when
/// something sleeps, so step timings stay at 0 s while a fake-store loop still ends.
enum Clock {
    private static var pinned: Double? = envVar("JEB_TEST_NOW").flatMap(Double.init)
    static var now: Double { pinned ?? Date().timeIntervalSince1970 }
    static var epoch: Int { Int(now) }
    static var pid: Int32 { envVar("JEB_TEST_PID").flatMap(Int32.init) ?? getpid() }
    static var isPinned: Bool { pinned != nil }

    static func sleep(_ seconds: Double) {
        if let t = pinned { pinned = t + seconds } else { usleep(useconds_t(max(0, seconds) * 1_000_000)) }
    }

    /// Tests only: re-read JEB_TEST_NOW after a change.
    static func reload() { pinned = envVar("JEB_TEST_NOW").flatMap(Double.init) }

    /// Seconds that do not care about the pin: deadlines on real downloads (time.monotonic in the Python).
    static var monotonic: Double { ProcessInfo.processInfo.systemUptime }

    /// time.strftime(fmt) in the local zone (TZ) at the clock's time.
    static func strftime(_ fmt: String, _ t: Double? = nil) -> String {
        var secs = time_t((t ?? now).rounded(.down))
        var tm = tm()
        localtime_r(&secs, &tm)
        var buf = [CChar](repeating: 0, count: 256)
        let n = Foundation.strftime(&buf, buf.count, fmt, &tm)
        return String(cString: Array(buf[0..<n]) + [0])
    }

    /// datetime.date.today() as (year, month, day) in the local zone, by the clock.
    static var today: (Int, Int, Int) {
        var secs = time_t(now.rounded(.down))
        var tm = tm()
        localtime_r(&secs, &tm)
        return (Int(tm.tm_year) + 1900, Int(tm.tm_mon) + 1, Int(tm.tm_mday))
    }
}

// ---- output ----

var dryRun = false
var verbose = true      // main turns it off for install/uninstall unless --verbose; every other command keeps its output
var openLine = false    // a step line ("  app ... ") is waiting for its result

func say(_ s: String) {
    if Style.pretty { Style.plainSay(s); return }
    if openLine { print(""); openLine = false }
    print(s)
    fflush(stdout)
}

/// Today's full output: shown only with --verbose (install/uninstall); say() is for what always shows.
func detail(_ s: String) { if verbose { say(s) } }

/// Default install/uninstall: open one step line, closed by fin() (or by whatever say() prints meanwhile).
func lead(_ label: String) {
    if Style.pretty { Style.lead(label); return }
    if !verbose { print("  \(label) ... ", terminator: ""); fflush(stdout); openLine = true }
}

func fin(_ text: String) {
    if Style.pretty { Style.fin(text); return }
    if !verbose { print(text); fflush(stdout); openLine = false }
}

func line(_ label: String, _ text: String) {
    if Style.pretty { Style.step(label, text); return }
    if !verbose { say("  \(label) ... \(text)") }
}

func warn(_ s: String) {
    if Style.pretty && isatty(2) != 0 { Style.error(s); return }
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

func die(_ s: String, _ code: Int32 = 1) -> Never {
    if Style.pretty { Style.abandonStep() }     // no spinner is left turning under the message
    warn(s)
    exit(code)
}

// ---- processes ----

struct RunResult {
    var status: Int32
    var out: String
    var err: String
    var text: String { (out + err).trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Runs a program and collects its output (subprocess.run with capture_output). capture false: stdout and stderr are
/// inherited (the installs talk to the terminal). stdin names a file to feed it. A program that cannot start is status 127.
@discardableResult
func run(_ argv: [String], cwd: String? = nil, env: [String: String]? = nil, capture: Bool = true, stdin: String? = nil) -> RunResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: argv[0])
    p.arguments = Array(argv.dropFirst())
    if let c = cwd { p.currentDirectoryURL = URL(fileURLWithPath: c) }
    if let e = env { p.environment = e }
    let o = Pipe(), e = Pipe()
    if capture { p.standardOutput = o; p.standardError = e }
    if let s = stdin { p.standardInput = FileHandle(forReadingAtPath: s) }
    do { try p.run() } catch { return RunResult(status: 127, out: "", err: "\(error.localizedDescription)") }
    var od = Data(), ed = Data()
    if capture {
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { ed = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        od = o.fileHandleForReading.readDataToEndOfFile()
        g.wait()
    }
    p.waitUntilExit()
    return RunResult(status: p.terminationStatus, out: String(decoding: od, as: UTF8.self), err: String(decoding: ed, as: UTF8.self))
}

/// jebctl's sh(): the command is echoed with --verbose, skipped on a dry run, its output shown with --verbose or when a
/// checked command fails. check: a failure exits with "failed: <cmd>", as the Python's SystemExit did.
@discardableResult
func sh(_ argv: [String], check: Bool = false, cwd: String? = nil, env: [String: String]? = nil) -> Int32 {
    detail("$ " + argv.joined(separator: " "))
    if dryRun { return 0 }
    let r = run(argv, cwd: cwd, env: env)
    if !r.text.isEmpty && (verbose || (check && r.status != 0)) { say(r.text) }
    if check && r.status != 0 { die("failed: " + argv.joined(separator: " ")) }
    return r.status
}

/// shlex.quote: a word safe inside a sh command line.
func shQuote(_ s: String) -> String {
    if s.isEmpty { return "''" }
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_")
    if s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
    return "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

// ---- regular expressions ----

/// re.search: the whole match and its groups (an unmatched group is ""), or nil. Anchor with ^ and $ for fullmatch.
func reMatch(_ pattern: String, _ s: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
}

/// re.findall with groups: every match as [whole, group1, ...].
func reFindAll(_ pattern: String, _ s: String) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
        (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
    }
}

// ---- the --no-agents guard ----

/// --no-agents skips every LaunchAgent and launchctl step, so it only runs where HOME is not the real home and the
/// app, agents and state folder all sit under it. The reason to refuse, or nil.
func checkSandbox(_ cmd: String) -> String? {
    let me = pyRealpath(homeDir())
    let real = pyRealpath(getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory())
    if !["install", "follow", "reload-agents", "rollback"].contains(cmd) {
        return "--no-agents is for `install`, `follow`, `reload-agents` and `rollback` only"
    }
    if me == real { return "--no-agents needs a HOME other than the real one (\(real)); it exists for sandboxes (./release smoke)" }
    for (what, p) in [("JEB_APP_DIR", appDir()), ("JEB_LAUNCHAGENTS", agentsDir()), ("the state folder", stateHome)] {
        let r = pyRealpath(p)
        if r != me && !r.hasPrefix(me + "/") { return "--no-agents: \(what) (\(p)) is outside the sandbox HOME \(me)" }
    }
    return nil
}

/// A clean environment for children: PATH pinned to the system folders, GIT_TERMINAL_PROMPT off.
func childEnv(_ extra: [String: String] = [:]) -> [String: String] {
    var e = ProcessInfo.processInfo.environment
    e["PATH"] = sysPath
    e["GIT_TERMINAL_PROMPT"] = "0"
    for (k, v) in extra { e[k] = v }
    return e
}
