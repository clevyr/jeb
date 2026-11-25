// Picker: the interactive choice of shells for the PATH line at the end of a first install, then the check that those shells
// find jebctl and the line that loads it into the open window. The decisions are pure (decodeKeys, pickerStep, renderPicker,
// shouldAskForPath, checkSummary, reloadCommand, reloadShell, reloadKey); askForPath and confirmPath are the thin /dev/tty
// and process shells around them. Foundation only.
import Foundation

// ---- the PATH picker: pure parts ----

enum Key: Equatable { case up, down, toggle, all, enter, esc, quit, interrupt, other }

/// Raw bytes from the terminal to keys. ESC [ A / ESC O A are up, ESC [ B / ESC O B down, any other escape sequence is .other,
/// and an ESC with nothing after it is a lone .esc.
func decodeKeys(_ bytes: [UInt8]) -> [Key] {
    var out: [Key] = [], i = 0
    while i < bytes.count {
        switch bytes[i] {
        case 0x1b:
            if i + 1 < bytes.count, bytes[i + 1] == 0x5b || bytes[i + 1] == 0x4f {
                var j = i + 2
                while j < bytes.count && bytes[j] < 0x40 { j += 1 }     // parameter and intermediate bytes
                if j < bytes.count {
                    out.append(bytes[j] == 0x41 ? .up : bytes[j] == 0x42 ? .down : .other)
                    i = j + 1
                } else {
                    out.append(.other)
                    i = bytes.count
                }
            } else {
                out.append(.esc)
                i += 1
            }
            continue
        case 0x20: out.append(.toggle)
        case UInt8(ascii: "a"): out.append(.all)
        case UInt8(ascii: "k"): out.append(.up)
        case UInt8(ascii: "j"): out.append(.down)
        case UInt8(ascii: "q"): out.append(.quit)
        case 0x0d, 0x0a: out.append(.enter)
        case 0x03: out.append(.interrupt)
        default: out.append(.other)
        }
        i += 1
    }
    return out
}

/// True when the bytes end inside an escape sequence (a lone ESC, or ESC [ / ESC O with no final byte yet): the rest of an arrow
/// key may still be on its way, so the reader polls briefly before it decodes.
func needsMoreKeys(_ bytes: [UInt8]) -> Bool {
    guard let e = bytes.lastIndex(of: 0x1b) else { return false }
    if e == bytes.count - 1 { return true }
    guard bytes[e + 1] == 0x5b || bytes[e + 1] == 0x4f else { return false }
    return !bytes[(e + 2)...].contains { $0 >= 0x40 }
}

/// What the terminal sends for one key press, read from `fd`: after a lone ESC or half an escape sequence, up to `wait` ms
/// for the rest. Empty at end of input.
func readKeyBytes(_ fd: Int32, wait: Int32 = 50) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: 32)
    let n = read(fd, &buf, buf.count)
    if n <= 0 { return [] }
    var bytes = Array(buf[0..<n])
    while needsMoreKeys(bytes) {
        let m = readWithin(fd, &buf, wait: wait)
        if m <= 0 { break }
        bytes += buf[0..<m]
    }
    return bytes
}

/// One read that gives up after about `wait` ms (0 then). A terminal times the read itself (VMIN 0, VTIME in tenths of a
/// second): macOS poll() does not work on tty devices, it reports them ready at once and the read then blocks. Anything else
/// (a pipe, in the tests) is polled.
private func readWithin(_ fd: Int32, _ buf: inout [UInt8], wait: Int32) -> Int {
    var saved = termios()
    if tcgetattr(fd, &saved) == 0 {
        var t = saved
        withUnsafeMutableBytes(of: &t.c_cc) { $0[Int(VMIN)] = 0; $0[Int(VTIME)] = UInt8(max(1, min(255, (wait + 99) / 100))) }
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { return 0 }
        defer { tcsetattr(fd, TCSANOW, &saved) }
        return read(fd, &buf, buf.count)
    }
    var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&p, 1, wait) > 0, p.revents & Int16(POLLIN) != 0 else { return 0 }
    return read(fd, &buf, buf.count)
}

/// aborted: ctrl-c (raw mode has no ISIG), which ends the install like SIGINT would; skipped: esc or q.
enum PickerOutcome: Equatable { case confirmed, skipped, aborted }

struct PickerState: Equatable {
    var shells: [String]
    var hints: [String]
    var checked: [Bool]
    var cursor = 0
    var outcome: PickerOutcome?

    /// loginShell and setUp preselect; hints say why ("your login shell", "set up").
    init(shells: [String] = pathShells, loginShell: String?, setUp: Set<String> = [], configured: Set<String> = []) {
        self.shells = shells
        hints = shells.map { s in [s == loginShell ? "your login shell" : nil, setUp.contains(s) ? "set up" : nil].compactMap { $0 }.joined(separator: ", ") }
        checked = shells.map { $0 == loginShell || setUp.contains($0) || configured.contains($0) }
    }
}

/// One key applied. The cursor wraps at both ends; once an outcome is set nothing changes.
func pickerStep(_ s: PickerState, key: Key) -> PickerState {
    var n = s
    guard n.outcome == nil, !n.shells.isEmpty else { return n }
    let c = n.shells.count
    switch key {
    case .up: n.cursor = (n.cursor + c - 1) % c
    case .down: n.cursor = (n.cursor + 1) % c
    case .toggle: n.checked[n.cursor].toggle()
    case .all:
        let on = !n.checked.allSatisfy { $0 }
        n.checked = n.checked.map { _ in on }
    case .enter: n.outcome = .confirmed
    case .esc, .quit: n.outcome = .skipped
    case .interrupt: n.outcome = .aborted
    case .other: break
    }
    return n
}

/// The shells to set up: the checked ones on a confirm, none otherwise.
func pickerSelection(_ s: PickerState) -> [String] {
    s.outcome == .confirmed ? zip(s.shells, s.checked).filter { $0.1 }.map { $0.0 } : []
}

func renderPicker(_ s: PickerState) -> [String] {
    var out = ["Want to type plain `jebctl` in your terminal?",
               "Pick the shells to set up (space to toggle, enter to confirm, esc to skip):"]
    for (i, sh) in s.shells.enumerated() {
        let name = sh == "nu" ? "nushell" : sh
        let hint = s.hints[i].isEmpty ? "" : (name.padding(toLength: max(5, name.count), withPad: " ", startingAt: 0) + " (\(s.hints[i]))")
        out.append((i == s.cursor ? "❯ " : "  ") + (s.checked[i] ? "◉ " : "◯ ") + (hint.isEmpty ? name : hint))
    }
    return out
}

/// The picker is for a person at a terminal on a first install who has not already answered: pretty mode, a fresh install,
/// neither PATH flag, not a dry run, the link folder not on PATH yet, and a terminal to ask on (tested last, so nothing opens
/// /dev/tty when an earlier condition already says no).
func shouldAskForPath(pretty: Bool, fresh: Bool, addFlag: Bool, noFlag: Bool, dry: Bool, onPath: Bool,
                      ttyAvailable: @autoclosure () -> Bool) -> Bool {
    pretty && fresh && !addFlag && !noFlag && !dry && !onPath && ttyAvailable()
}

enum PathChoice: Equatable { case skip, shells([String]), defaults }

/// Set by the install when the PATH question is due; asked by askPathNow after the last install step.
var pathAskPending = false

/// Set by pathStep in pretty mode: the shells that now have Jeb's PATH line, checked by askPathNow.
var pathConfirmPending: [PathTarget]?

func askPathNow() {
    if pathAskPending {
        pathAskPending = false
        say("")
        switch askForPath() {
        case .shells(let s): pathStep(add: true, only: s)
        case .defaults: pathStep(add: true)
        case .skip: pathStep(add: false)
        }
    }
    if let t = pathConfirmPending {
        pathConfirmPending = nil
        confirmPath(t)
    }
}

// ---- the check and the reload line: pure parts ----

enum ShellCheck: Equatable { case found, missing, unchecked }

func shellDisplayName(_ shell: String) -> String { shell == "nu" ? "nushell" : shell }

/// The fin() text for the check: ok with the shells that found jebctl, a failure naming the ones that did not, or skipped
/// when none could be run.
func checkSummary(_ results: [(shell: String, check: ShellCheck)]) -> String {
    let names = { (c: ShellCheck) in results.filter { $0.check == c }.map { shellDisplayName($0.shell) }.joined(separator: ", ") }
    let found = names(.found), missing = names(.missing), unchecked = names(.unchecked)
    if !missing.isEmpty { return "not found by " + missing }
    if !found.isEmpty { return "ok (" + found + (unchecked.isEmpty ? "" : "; could not run " + unchecked) + ")" }
    return "skipped (could not run " + unchecked + ")"
}

/// `p` with the home folder written as ~.
func tildePath(_ p: String, home: String) -> String {
    p == home ? "~" : p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p
}

/// The command that puts jebctl's folder on PATH in an open shell: just the PATH line (not `source <profile>`, which would
/// run the whole profile again). zsh and bash get an export, with a non-default folder shell-quoted; fish and nushell get
/// their own pathLine.
func reloadCommand(_ shell: String) -> String? {
    switch shell {
    case "zsh", "bash": return exportLine()
    case "fish", "nu": return pathLine(shell)
    default: return nil
    }
}

/// A process name from ps as one of pathShells ("-zsh", "/bin/bash" and "zsh" are all zsh), or nil.
func shellFromComm(_ comm: String) -> String? {
    var c = comm.trimmingCharacters(in: .whitespaces)
    if c.hasPrefix("-") { c.removeFirst() }
    let name = (c as NSString).lastPathComponent
    return pathShells.contains(name) ? name : nil
}

/// The shell to give the reload line for: the nearest shell among jebctl's ancestors (the window the install runs in),
/// else the login shell; and only when that shell now has the line.
func reloadShell(ancestors: [String], loginShell: String?, ready: [String]) -> String? {
    let s = ancestors.lazy.compactMap(shellFromComm).first ?? loginShell
    return s.flatMap { ready.contains($0) ? $0 : nil }
}

enum ReloadAction: Equatable { case copy, done }

/// A key at the reload prompt: c copies, enter, esc, q and ctrl-c finish, anything else is ignored (nil).
func reloadKey(_ bytes: [UInt8]) -> ReloadAction? {
    guard let b = bytes.first else { return nil }
    switch b {
    case UInt8(ascii: "c"), UInt8(ascii: "C"): return .copy
    case 0x0d, 0x0a, 0x1b, 0x03, UInt8(ascii: "q"): return .done
    default: return nil
    }
}

func renderReload(_ cmd: String) -> [String] {
    ["", "  To use it in this window right away:", "    " + paint(cmd, Ansi.cyan)]
}

let reloadPrompt = "c copy it · enter done"

func renderCopied(_ ok: Bool) -> String {
    ok ? "  " + paint("✓", Ansi.green) + " Copied. Paste it in once the install is done."
       : "  " + paint("Could not copy it; type it in instead.", Ansi.yellow)
}

/// `jebctl preview-ui [--fail]`: plays the install's pretty output with pretend steps and the PATH picker, and changes
/// nothing (the picker's choice is only printed). --fail shows a failed step and an error. For trying the look in a terminal.
func cmdPreviewUI(_ args: [String]) -> Int32 {
    let fail = args.contains("--fail")
    Style.announce(plain: "Installing Jeb (preview; nothing is changed)", mode: .install, version: "preview")
    for l in ["fetch", "checks", "signers", "app", "LaunchAgents", "desktop"] {
        lead(l)
        Clock.sleep(0.4)
        fin("ok")
    }
    line("jebctl command", "ok")
    lead("Claude Code plugin")
    Clock.sleep(0.4)
    fin(fail ? "not registered" : "ok")
    if fail { warn("jebctl: could not reach GitHub; check your network, VPN or proxy") }
    if Style.pretty && canOpenTTY() {
        say("")
        var picked: [String] = []
        switch askForPath() {
        case .shells(let s): picked = s; say("  You picked " + s.joined(separator: ", ") + " (preview: nothing was written)")
        case .defaults: picked = [loginShellName()].compactMap { $0 }; say("  You said yes (preview: nothing was written)")
        case .skip: say("  Skipped (preview: nothing was written)")
        }
        if !picked.isEmpty {
            lead("verify")
            Clock.sleep(0.4)
            fin(checkSummary(picked.map { ($0, .found) }))
            if let sh = reloadShell(ancestors: ancestorComms(), loginShell: loginShellName(), ready: picked),
               let cmd = reloadCommand(sh) {
                offerReload(cmd)
            }
        }
    }
    lead("health")
    Clock.sleep(0.4)
    fin("ok")
    sayDone()
    return 0
}

// ---- the check and the reload line: the process and tty shell ----

func loginShellName() -> String? {
    let sh = ((envVar("SHELL") ?? "") as NSString).lastPathComponent
    return pathShells.contains(sh) ? sh : nil
}

/// Each shell, started as a login shell from a bare PATH, looks for jebctl. Shells that are not installed, cannot start or
/// take longer than five seconds are unchecked.
func confirmPath(_ targets: [PathTarget]) {
    lead("verify")
    let results = targets.map { t in (shell: t.shell, check: checkShell(t)) }
    let summary = checkSummary(results)
    fin(summary)
    for r in results where r.check == .missing {
        let f = targets.first { $0.shell == r.shell }.map { tildePath($0.file, home: expandUser("~")) } ?? ""
        say("  \(shellDisplayName(r.shell)) did not pick up \(f); open a new terminal, and run `\(selfCommand()) doctor` if it still cannot find jebctl")
    }
    let ready = results.filter { $0.check != .missing }.map(\.shell)
    guard let sh = reloadShell(ancestors: ancestorComms(), loginShell: loginShellName(), ready: ready),
          let cmd = reloadCommand(sh) else { return }
    offerReload(cmd)
}

func shellExecutable(_ shell: String) -> String? {
    let fm = FileManager.default
    let dirs = (envVar("PATH") ?? "").split(separator: ":").map(String.init)
        + ["/bin", "/opt/homebrew/bin", "/usr/local/bin", expandUser("~/.cargo/bin")]
    return dirs.map { $0 + "/" + shell }.first { fm.isExecutableFile(atPath: $0) }
}

func checkShell(_ t: PathTarget) -> ShellCheck {
    guard let exe = shellExecutable(t.shell) else { return .unchecked }
    let argv: [String]
    switch t.shell {
    case "fish": argv = [exe, "-l", "-c", "command -q jebctl"]
    case "nu": argv = [exe, "--env-config", t.file, "-c", "if (which jebctl | is-empty) { exit 1 }"]
    default: argv = [exe, "-l", "-c", "command -v jebctl >/dev/null"]
    }
    var env = ["HOME": expandUser("~"), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "dumb"]
    for k in ["USER", "LOGNAME", "ZDOTDIR", "XDG_CONFIG_HOME"] { if let v = envVar(k) { env[k] = v } }
    guard let status = runQuiet(argv, env: env, timeout: 5) else { return .unchecked }
    return status == 0 ? .found : .missing
}

/// A program run with no input or output; its exit status, or nil when it cannot start or outlives `timeout` seconds.
func runQuiet(_ argv: [String], env: [String: String], timeout: Double) -> Int32? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: argv[0])
    p.arguments = Array(argv.dropFirst())
    p.environment = env
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let end = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < end { usleep(20_000) }
    if p.isRunning { p.terminate(); p.waitUntilExit(); return nil }
    return p.terminationStatus
}

/// The names of jebctl's parent processes, nearest first (at most five).
func ancestorComms() -> [String] {
    var out: [String] = [], pid = getppid()
    for _ in 0..<5 where pid > 1 {
        let r = run(["/bin/ps", "-o", "ppid=,comm=", "-p", String(pid)])
        let parts = r.out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1)
        guard r.status == 0, parts.count == 2, let pp = Int32(parts[0]) else { break }
        out.append(String(parts[1]))
        pid = pp
    }
    return out
}

/// The reload line, and on a terminal "c copy it · enter done": c puts it on the clipboard with pbcopy.
func offerReload(_ cmd: String) {
    for l in renderReload(cmd) { say(l) }
    defer { say("") }
    let fd = open("/dev/tty", O_RDWR)
    guard fd >= 0 else { return }
    defer { close(fd) }
    let action: ReloadAction? = withRawTTY(fd) {
        Style.write("  " + paint(clipLine(reloadPrompt, to: ttyColumns(fd) - 2), Ansi.dim))
        var buf = [UInt8](repeating: 0, count: 16)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return .done }
            if let a = reloadKey(Array(buf[0..<n])) { return a }
        }
    }
    guard let a = action else { return }
    Style.write("\r" + Ansi.clearLine)
    if a == .copy { Style.write(renderCopied(copyToClipboard(cmd)) + "\n") }
}

func copyToClipboard(_ s: String) -> Bool {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
    p.standardInput = pipe
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    pipe.fileHandleForWriting.write(Data(s.utf8))
    pipe.fileHandleForWriting.closeFile()
    p.waitUntilExit()
    return p.terminationStatus == 0
}

/// `body` with the terminal in raw mode (no echo, no line editing, no signals), restored on the way out; nil when raw mode
/// cannot be set.
func withRawTTY<T>(_ fd: Int32, _ body: () -> T) -> T? {
    installTerminalGuards()
    var orig = termios()
    guard tcgetattr(fd, &orig) == 0 else { return nil }
    var raw = orig
    raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG | IEXTEN)
    raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
    withUnsafeMutableBytes(of: &raw.c_cc) { $0[Int(VMIN)] = 1; $0[Int(VTIME)] = 0 }
    guard tcsetattr(fd, TCSANOW, &raw) == 0 else { return nil }
    savedTermios = orig
    savedTermiosFd = fd
    defer { restoreTerminalSettings() }
    return body()
}

// ---- the PATH picker: the tty shell ----

func canOpenTTY() -> Bool {
    let fd = open("/dev/tty", O_RDWR)
    if fd >= 0 { close(fd) }
    return fd >= 0
}

/// The login shell and the shells already set up or configured, as the picker's starting state.
func initialPickerState() -> PickerState {
    let sh = ((envVar("SHELL") ?? "") as NSString).lastPathComponent
    let hasLine = Set(pathShells.filter { s in pathTargets([s]).first?.has == true })
    return PickerState(loginShell: pathShells.contains(sh) ? sh : nil, setUp: hasLine, configured: Set(pathShells.filter(shellConfigured)))
}

/// Ask on /dev/tty (stdin may be the curl pipe). The checkbox picker in raw mode; a single [y/N] when raw mode is not
/// available. The terminal and cursor are restored on every way out.
func askForPath() -> PathChoice {
    let fd = open("/dev/tty", O_RDWR)
    guard fd >= 0 else { return .skip }
    defer { close(fd) }
    return withRawTTY(fd) { pickInRawMode(fd) } ?? askYesNo(fd)
}

private func pickInRawMode(_ fd: Int32) -> PathChoice {
    var state = initialPickerState()
    // each line is clipped to the terminal's width: a wrapped line would throw off the cursor-up count of the redraw
    let fit = { (s: PickerState) in renderPicker(s).map { clipLine($0, to: ttyColumns(fd)) } }
    var rows = fit(state).count
    Style.write(fit(state).joined(separator: "\n") + "\n")
    while state.outcome == nil {
        let bytes = readKeyBytes(fd)
        if bytes.isEmpty { state.outcome = .skipped; break }
        for k in decodeKeys(bytes) where state.outcome == nil { state = pickerStep(state, key: k) }
        let lines = fit(state)
        Style.write("\u{1b}[\(rows)A" + lines.map { Ansi.clearLine + $0 + "\n" }.joined())
        rows = lines.count
    }
    Style.write("\u{1b}[\(rows)A\r\u{1b}[J")        // the picker leaves the screen
    if state.outcome == .aborted {      // ctrl-c: the terminal and cursor back, then out the way SIGINT would end it
        restoreTerminal()
        exit(130)
    }
    let chosen = pickerSelection(state)
    return chosen.isEmpty ? .skip : .shells(chosen)
}

private func restoreTerminalSettings() {
    if var t = savedTermios { tcsetattr(savedTermiosFd, TCSANOW, &t) }
    savedTermios = nil
}

/// The fallback when raw mode cannot be set: y sets up the default targets.
private func askYesNo(_ fd: Int32) -> PathChoice {
    Style.write("Want to type plain `jebctl` in your terminal? [y/N] ")
    var answer: [UInt8] = [], b: UInt8 = 0
    while read(fd, &b, 1) == 1 && b != 0x0a { answer.append(b) }
    Style.write("\n")
    return ["y", "yes"].contains(String(decoding: answer, as: UTF8.self).trimmingCharacters(in: .whitespaces).lowercased()) ? .defaults : .skip
}
