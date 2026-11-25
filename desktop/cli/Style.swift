// Style: the friendly terminal rendering of `jebctl install` and `uninstall` (and the header of the update flow).
// Pretty mode replaces the plain step lines of Env.swift's lead/fin/line/say with a spinner, glyphs and colour; plain output
// (a pipe, NO_COLOR, TERM=dumb, --verbose, --plain) is never touched here, so Claude Code's non-TTY runs read the same text.
// Everything that decides something is a pure function (detectPretty, renderStep, renderError) so the tests need no terminal.
// The PATH shell picker is in Picker.swift. This file stays free of Install.swift so the release tool can build it. Foundation only.
import Foundation

// ---- mode detection ----

/// Whether to draw the pretty output. --verbose and --plain always force plain. JEB_STYLE=plain|pretty overrides the rest of
/// the detection (stdout a tty, NO_COLOR unset, TERM neither empty nor dumb); it exists for the tests.
func detectPretty(env: [String: String], isTTY: Bool, verbose: Bool, plain: Bool) -> Bool {
    if verbose || plain { return false }
    switch env["JEB_STYLE"] {
    case "plain": return false
    case "pretty": return true
    default: break
    }
    if !isTTY || env["NO_COLOR"] != nil { return false }
    let term = env["TERM"] ?? ""
    return !(term.isEmpty || term == "dumb")
}

enum StyleMode: Hashable { case install, update, uninstall }

// ---- pure rendering ----

enum Ansi {
    static let reset = "\u{1b}[0m", dim = "\u{1b}[2m", red = "\u{1b}[31m", green = "\u{1b}[32m", yellow = "\u{1b}[33m", cyan = "\u{1b}[36m"
    static let clearLine = "\r\u{1b}[2K", hideCursor = "\u{1b}[?25l", showCursor = "\u{1b}[?25h"
}

func paint(_ s: String, _ color: String) -> String { color + s + Ansi.reset }

/// A water wheel turning: one column wide in every font, so the \r redraw never shifts the label.
let spinnerFrames = ["◐", "◓", "◑", "◒"]

/// The one table of friendly step names, by mode. A label that is not here is shown as it is.
let stepLabels: [StyleMode: [String: String]] = [
    .install: [
        "fetch": "Fetched the release",
        "checks": "Checked the release is the real thing",
        "signers": "Pinned the signing key",
        "app": "Built the farmhouse",
        "LaunchAgents": "Hired a watchdog",
        "desktop": "Woke Jeb up",
        "jebctl command": "Put jebctl in the toolshed",
        "Claude Code plugin": "Introduced Jeb to Claude Code",
        "verify": "Checked your shells can find jebctl",
        "health": "Gave the farm a once-over",
    ],
    .uninstall: [
        "LaunchAgents and app": "Sent the watchdog and the desktop home",
        "desktop folder": "Cleared out the desktop folder",
        "jebctl command": "Took jebctl out of the toolshed",
        "plugin": "Said goodbye to Claude Code",
        "farm": "Farm",
        "old clone": "Old clone",
        "files": "Files",
    ],
]

func friendlyLabel(_ label: String, mode: StyleMode) -> String { stepLabels[mode]?[label] ?? label }

enum StepOutcome: Equatable {
    case ok(String)         // the detail to show dimmed, "" for none
    case skipped(String)    // the reason
    case failed(String)
}

/// What a fin() text means: done, deliberately not done, or a problem.
func classifyStep(_ text: String) -> StepOutcome {
    let first = text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? text
    if ["ok", "running", "linked", "removed", "purged", "unregistered"].contains(first) {
        let rest = text.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
        return .ok(rest.hasPrefix("(") && rest.hasSuffix(")") ? String(rest.dropFirst().dropLast()) : "")
    }
    if ["skipped", "would", "kept", "already"].contains(first) || ["not installed", "not needed", "none found"].contains(where: { text.hasPrefix($0) }) {
        return .skipped(text)
    }
    return .failed(text)
}

/// A finished step line.
func renderStep(label: String, text: String, mode: StyleMode) -> String {
    let name = friendlyLabel(label, mode: mode)
    switch classifyStep(text) {
    case .ok(let d): return "  " + paint("✓", Ansi.green) + " " + name + (d.isEmpty ? "" : "  " + paint(d, Ansi.dim))
    case .skipped(let why): return "  " + paint("· " + name + "  " + why, Ansi.dim)
    case .failed(let why): return "  " + paint("✗", Ansi.red) + " " + name + "  " + paint(why, Ansi.red)
    }
}

/// The line drawn while a step runs, its label clipped to `width` columns: the spinner redraws with \r, so the line must
/// never wrap.
func renderSpinner(label: String, mode: StyleMode, frame: Int, width: Int = .max) -> String {
    "  " + paint(spinnerFrames[((frame % spinnerFrames.count) + spinnerFrames.count) % spinnerFrames.count], Ansi.cyan) + " "
        + clipLine(friendlyLabel(label, mode: mode), to: width == .max ? .max : width - 4)
}

/// A line cut to fit `cols` columns, ending in … when cut (one column is kept free so the terminal never wraps).
func clipLine(_ s: String, to cols: Int) -> String {
    let room = max(cols - 1, 2)
    return s.count <= room ? s : String(s.prefix(room - 1)) + "…"
}

func ttyColumns(_ fd: Int32) -> Int {
    var w = winsize()
    return ioctl(fd, TIOCGWINSZ, &w) == 0 && w.ws_col > 0 ? Int(w.ws_col) : 80
}


func renderHeader(mode: StyleMode, version: String?) -> String {
    switch mode {
    case .install: return "🌱 Jeb's moving in" + (version.map { " · " + $0 } ?? "")
    case .update: return "🌱 Jeb's checking for news"
    case .uninstall: return "🧺 Packing up Jeb"
    }
}

/// The plain closing line of an install (Claude Code's skill matches it) and its pretty twin.
let plainDone = "Done. Start a new Claude Code session to load Jeb; the desktop fills in once a session has run."
let prettyDone = "🚜 All set. Start a new Claude Code session and Jeb will turn up on your desktop."
let prettyDoneFailed = "Jeb's in, but a step above did not go right. Run jebctl doctor to sort it out."

/// The pretty closing line: "All set" only when no step failed.
func renderDone(failed: Bool) -> String {
    failed ? "  " + paint("⚠ " + prettyDoneFailed, Ansi.yellow) : prettyDone
}

/// A message through say(): the few known shapes get a style, the rest passes unchanged.
func renderSay(_ s: String) -> String {
    s.components(separatedBy: "\n").map { l -> String in
        if l == "Dry run only; nothing was changed." { return paint(l, Ansi.dim) }
        if l.hasPrefix("warning: ") { return "  " + paint("⚠ " + l.dropFirst("warning: ".count), Ansi.yellow) }
        if l.hasPrefix("note: ") { return "  " + paint(String(l.dropFirst("note: ".count)), Ansi.dim) }
        return l
    }.joined(separator: "\n")
}

/// An error as red lines: the problem, then the fix on its own indented line when the message names one ("...; run X").
func renderError(_ msg: String) -> [String] {
    var rows = msg.components(separatedBy: "\n")
    var head = rows.removeFirst()
    if head.hasPrefix("jebctl: ") { head = String(head.dropFirst("jebctl: ".count)) }
    var fix: String?
    if let r = head.range(of: "; ") {
        let rest = String(head[r.upperBound...])
        if ["run ", "check ", "try ", "move ", "see ", "open "].contains(where: { rest.hasPrefix($0) }) {
            fix = rest.prefix(1).uppercased() + rest.dropFirst()
            head = String(head[..<r.lowerBound])
        }
    }
    var out = ["  " + paint("✗ " + head, Ansi.red)]
    if let f = fix { out.append("    " + f) }
    out += rows.filter { !$0.isEmpty }.map { "    " + paint($0, Ansi.dim) }
    return out
}

// ---- the output engine ----

/// Everything pretty mode writes to stdout goes through here, under one lock, so the spinner never interleaves with a line.
enum Style {
    static var pretty = false
    static var mode: StyleMode = .install
    static let lock = NSRecursiveLock()
    private(set) static var openLabel: String?       // the step whose spinner is drawn
    private(set) static var headerDrawn = false      // this process drew the header, so a hand-over passes JEB_HEADER_SHOWN on
    private static var frame = 0
    private static var timer: DispatchSourceTimer?
    private static var began = false
    private static var anyFailed = false      // a step ended in failure, so done() does not say "All set"
    private static var lastBlank = false      // the last line written was empty, so done() adds no second one

    static func configure(plain: Bool) {
        pretty = detectPretty(env: ProcessInfo.processInfo.environment, isTTY: isatty(1) != 0, verbose: verbose, plain: plain)
    }

    static func write(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        fputs(s, stdout)
        fflush(stdout)
        lastBlank = s.hasSuffix("\n\n")
    }

    /// Hide the cursor and arm its restore (exit, SIGINT, SIGTERM).
    static func begin() {
        guard pretty, !began else { return }
        began = true
        installTerminalGuards()
        cursorHidden = true
        write(Ansi.hideCursor)
    }

    /// The opening line of a run: plain text as it always was, or the pretty header. A header already shown by the process
    /// that handed over to this one (JEB_HEADER_SHOWN, set by the hand-over alone) is not drawn twice.
    static func announce(plain: String, mode m: StyleMode, version: String? = nil) {
        guard pretty else { say(plain); return }
        mode = m
        begin()
        if envVar("JEB_HEADER_SHOWN") == nil {
            write(renderHeader(mode: m, version: version) + "\n\n")
            headerDrawn = true
        }
    }

    private static func draw() {
        guard let l = openLabel else { return }
        fputs(Ansi.clearLine + renderSpinner(label: l, mode: mode, frame: frame, width: ttyColumns(1)), stdout)
        fflush(stdout)
    }

    private static func erase() {
        if openLabel != nil { fputs(Ansi.clearLine, stdout) }
    }

    static func lead(_ label: String) {
        lock.lock(); defer { lock.unlock() }
        openLine = true
        openLabel = label
        frame = 0
        draw()
        if timer == nil {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            t.schedule(deadline: .now() + .milliseconds(150), repeating: .milliseconds(150))
            t.setEventHandler { lock.lock(); frame += 1; draw(); lock.unlock() }
            t.resume()
            timer = t
        }
    }

    static func fin(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        let label = openLabel
        noteOutcome(text)
        erase()
        openLabel = nil
        openLine = false
        if let l = label { fputs(renderStep(label: l, text: text, mode: mode) + "\n", stdout); fflush(stdout); lastBlank = false }
    }

    /// A whole step in one go (line()).
    static func step(_ label: String, _ text: String) {
        noteOutcome(text)
        emit(renderStep(label: label, text: text, mode: mode))
    }

    private static func noteOutcome(_ text: String) {
        if case .failed = classifyStep(text) { anyFailed = true }
    }

    static func plainSay(_ s: String) { emit(renderSay(s)) }

    /// A line printed above the spinner, which is drawn again below it.
    private static func emit(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        erase()
        fputs(s + "\n", stdout)
        lastBlank = s.isEmpty || s.hasSuffix("\n")
        draw()
        fflush(stdout)
    }

    /// An error above the spinner. The open step keeps its label (a warning in the middle of a step does not end it), so the
    /// spinner is drawn again below the message and the later fin() still prints the step.
    static func error(_ msg: String) {
        lock.lock(); defer { lock.unlock() }
        erase()
        fflush(stdout)
        for l in renderError(msg) { fputs(l + "\n", stderr) }
        fflush(stderr)
        draw()
    }

    /// The spinner line erased and the open step dropped: for an exit with a step still open (die).
    static func abandonStep() {
        lock.lock(); defer { lock.unlock() }
        erase()
        openLabel = nil
        openLine = false
        fflush(stdout)
    }

    static func done() {
        if !lastBlank { emit("") }
        emit(renderDone(failed: anyFailed))
    }
}

/// The closing line of a finished install.
func sayDone() {
    if Style.pretty { Style.done() } else { say(plainDone) }
}

/// A "  label ... text" line that shows in plain and verbose runs too (line() is for the non-verbose steps only).
func stepSay(_ label: String, _ text: String) {
    if Style.pretty { Style.step(label, text) } else { say("  \(label) ... \(text)") }
}

// ---- terminal guards ----

var cursorHidden = false
var savedTermios: termios?
var savedTermiosFd: Int32 = -1
private var guardsInstalled = false

/// Put the terminal back: the saved line settings and a visible cursor. Safe to call twice.
func restoreTerminal() {
    if var t = savedTermios {
        tcsetattr(savedTermiosFd, TCSANOW, &t)
        savedTermios = nil
    }
    if cursorHidden {
        cursorHidden = false
        let s = Array(Ansi.showCursor.utf8)
        _ = s.withUnsafeBufferPointer { Foundation.write(1, $0.baseAddress, $0.count) }
    }
}

func installTerminalGuards() {
    guard !guardsInstalled else { return }
    guardsInstalled = true
    atexit { restoreTerminal() }
    for sig in [SIGINT, SIGTERM] {
        signal(sig) { s in
            restoreTerminal()
            signal(s, SIG_DFL)
            raise(s)
        }
    }
}
