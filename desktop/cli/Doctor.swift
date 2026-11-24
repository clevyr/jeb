// Doctor: `jebctl doctor`, the read-only health check (bundle layout). Checks are grouped; each line is
// `ok`, `FIX`, `skip` or `note` with a plain-English name. Every FIX records the step that repairs it, and the end of the
// report lists each distinct step once, in a fixed order. Exit 1 when anything needs a fix.
// The bundle ships no Python, so that check is gone (deviation #4 in the goldens README).
import Foundation

func plistAt(_ path: String) -> [String: Any]? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any]
}

/// One repair step. `priority` fixes the order they are listed in; a step with no `reason` is a sentence, not a command.
enum FixID: Hashable {
    case redownload, reinstall, restartAll, start, resume, retry, update, addPath, pathOrder, newSession, network

    /// Whether `doctor --fix` runs it. The rest are sentences for the user, or need a decision (resume-updates).
    var runnable: Bool {
        switch self {
        case .redownload, .reinstall, .restartAll, .start, .retry, .update: return true
        case .resume, .addPath, .pathOrder, .newSession, .network: return false
        }
    }
}

struct FixStep: Equatable {
    let id: FixID
    let priority: Int
    let command: String
    let reason: String

    static func redownload(_ tool: String) -> FixStep { FixStep(id: .redownload, priority: 1, command: "\(tool) install", reason: "downloads the release again") }
    static let reinstall = FixStep(id: .reinstall, priority: 2, command: "jebctl install", reason: "reinstalls the app, background agents and plugin")
    static let restartAll = FixStep(id: .restartAll, priority: 3, command: "jebctl quit, then jebctl start", reason: "stops every copy, then starts one")
    static let start = FixStep(id: .start, priority: 4, command: "jebctl start", reason: "starts the desktop app")
    static let resume = FixStep(id: .resume, priority: 5, command: "jebctl resume-updates", reason: "updates were paused on purpose; check before resuming")
    static let retry = FixStep(id: .retry, priority: 6, command: "jebctl retry-update", reason: "runs the last failed update again")
    static let update = FixStep(id: .update, priority: 7, command: "jebctl update", reason: "updates the plugin to match and removes older version folders")
    static func addPath(_ live: String) -> FixStep { FixStep(id: .addPath, priority: 9, command: "", reason: "Run \(live) install --add-path to link jebctl and add it to your PATH") }
    static func pathOrder(_ other: String, _ bin: String) -> FixStep {
        FixStep(id: .pathOrder, priority: 9, command: "", reason: "Remove \(other), or put \(bin) first on your PATH")
    }
    static let newSession = FixStep(id: .newSession, priority: 10, command: "", reason: "Start a new Claude Code session so the plugin loads")
    static let network = FixStep(id: .network, priority: 11, command: "", reason: "Check the network: a proxy or firewall must allow github.com and release-assets.githubusercontent.com")
}

/// The closing lines: "All good." or the problem count and the numbered, de-duplicated steps in priority order.
/// `jebctl` is how the user can run it: a full path when the bare name is not on their PATH.
func doctorSummary(steps: [FixStep], problems: Int, jebctl: String = "jebctl") -> [String] {
    if problems == 0 && steps.isEmpty { return ["All good."] }
    var seen: [FixStep] = []
    for s in steps.sorted(by: { $0.priority < $1.priority }) where !seen.contains(s) { seen.append(s) }
    let cmd = { (s: FixStep) in s.command.replacingOccurrences(of: "(^|, then )jebctl ", with: "$1" + jebctl + " ", options: .regularExpression) }
    let width = (seen.map { cmd($0).count }.max() ?? 0) + 2
    var out = ["\(problems) problem\(problems == 1 ? "" : "s"). To fix \(problems == 1 ? "it" : "them"), in order:"]
    for (i, s) in seen.enumerated() {
        let c = cmd(s)
        let text = c.isEmpty ? s.reason : c + String(repeating: " ", count: width - c.count) + s.reason
        out.append("  \(i + 1). " + text)
    }
    return out
}

/// A path with the home folder shown as ~.
func shortPath(_ p: String) -> String {
    let h = envVar("HOME") ?? ""
    return !h.isEmpty && (p == h || p.hasPrefix(h + "/")) ? "~" + p.dropFirst(h.count) : p
}

/// What the checks found: the printed lines, the repair steps, the problem count and how the summary names jebctl.
struct DoctorReport {
    var lines: [String] = []
    var steps: [FixStep] = []
    var problems = 0
    var jebctl = "jebctl"
}

/// Runs every check without printing. checkNetwork false skips the GitHub releases check (the silent passes of --fix).
func diagnose(checkNetwork: Bool = true) -> DoctorReport {
    let fm = FileManager.default
    var bad = 0
    var steps: [FixStep] = []
    var lines: [String] = []
    func out(_ s: String) { lines.append(s) }
    func section(_ name: String) { out(name) }
    /// An `ok` line when good, else a `FIX` line that records its step.
    @discardableResult
    func check(_ good: Bool, ok: String, fix: String, _ step: FixStep) -> Bool {
        out(good ? "  ok    " + ok : "  FIX   " + fix)
        if !good { bad += 1; steps.append(step) }
        return good
    }
    func fix(_ what: String, _ step: FixStep) { check(false, ok: "", fix: what, step) }
    let live = currentDir()

    out("Jeb doctor")
    out("")
    section("Install")
    let tag = readBundle(live)?["tag"]?.string
    if liveValid() {
        out("  ok    Jeb" + (tag.map { " \($0)" } ?? "") + " is installed (\(shortPath(live)))")
    } else {
        fix("Jeb's install folder is missing or damaged (\(shortPath(live)))", .redownload(shortPath(toolsDir() + "/jebctl")))
    }
    let vd = versionsDir()
    let vs = ((try? fm.contentsOfDirectory(atPath: vd)) ?? []).sorted().filter { isDir(vd + "/" + $0) }
    if vs.count > 1 { fix("More than one Jeb version is on disk (\(vs.joined(separator: ", ")))", .update) }
    if let lc = loadRState()["legacy_clone"]?.string, !lc.isEmpty, isDir(lc) {
        out("  note  The old git clone \(shortPath(lc)) is no longer used; it can be deleted")
    }
    if !isRegularFile(modeFilePath) || installMode() != "release" {
        fix("Jeb's install record is missing (\(shortPath(modeFilePath)))", .reinstall)
    }
    if stateHome == oldPath() && (envVar("JEB_HOME") ?? "").isEmpty {
        out("  note  Jeb's data is in the older folder \(shortPath(stateHome)); the next install or update moves it")
    }
    // how the fix list names jebctl: the bare name when it runs this one, else a path that works
    var jebctlName = "jebctl"
    if !(which("jebctl").map(isMe) ?? false) { jebctlName = shortPath(linkState() == "ours" ? linkPath() : liveJebctl) }
    if linkState() == "ours" {
        out("  ok    jebctl command (\(shortPath(linkPath())))")
    } else if let w = which("jebctl") {
        if isMe(w) {
            out("  ok    jebctl command (\(shortPath(w)))")
        } else {
            fix("A different jebctl comes first on your PATH (\(shortPath(w)))", .pathOrder(shortPath(w), shortPath(binDir())))
        }
    } else {
        fix("The jebctl command isn't on your PATH", .addPath(shortPath(liveJebctl)))
    }

    section("Desktop app")
    check(isDir(installedApp), ok: "The desktop app is installed (\(shortPath(installedApp)))", fix: "The desktop app is missing (\(shortPath(installedApp)))", .reinstall)
    if isDir(installedApp) {
        let jm = plistAt(installedApp + "/Contents/Info.plist")?["JebMod"] as? String
        check(jm.map { isRegularFile($0 + "/hooks/pixel-art.ts") } ?? false, ok: "The app finds Jeb's mod files", fix: "The app can't find Jeb's mod files", .reinstall)
    }
    let procs = running(), beats = beatFiles()
    if procs.count > 1 {
        fix("More than one Jeb is running (\(procs.count))", .restartAll)
    } else if procs.isEmpty {
        fix("Jeb isn't running", .start)
    } else {
        out("  ok    Jeb is running")
    }
    for p in procs {
        let b = beats[p.pid]
        check(b.map { $0.age < 10 } ?? false, ok: "Jeb (pid \(p.pid)) is responding" + (b.map { " (heartbeat \(fixed($0.age, 1)) s ago)" } ?? ""),
              fix: "Jeb (pid \(p.pid)) has stopped responding; the watchdog restarts it within a minute", .start)
    }
    if fm.fileExists(atPath: stateHome + "/quit") { fix("Jeb was quit from its menu", .start) }

    section("Background agents")
    let names = ["com.jeb.desktop": "desktop", "com.jeb.desktop.watchdog": "watchdog", "com.jeb.desktop.release": "update", "com.jeb.desktop.update": "update"]
    for l in labelsFor("release") {
        let n = (names[l] ?? l) + " agent", p = agentsDir() + "/" + l + ".plist"
        if !isRegularFile(p) {
            fix("The \(n) isn't set up", .reinstall)
        } else if let pa = plistAt(p) {
            let paths = ((pa["ProgramArguments"] as? [Any]) ?? []).compactMap { $0 as? String }.filter { $0.hasPrefix("/") }
            var ok = !paths.isEmpty && paths.allSatisfy { fm.fileExists(atPath: $0) }
            if !ok { fix("The \(n) points at files that are missing", .reinstall) }
            if let jm = (pa["EnvironmentVariables"] as? [String: Any])?["JEB_MOD"], jm as? String != liveMod {
                fix("The \(n) points at a different Jeb folder", .reinstall)
                ok = false
            }
            if ok { out("  ok    The \(n) is set up") }
        } else {
            fix("The \(n) settings can't be read", .reinstall)
        }
        if !noLaunchctl {
            let loaded = run([which("launchctl") ?? "/bin/launchctl", "print", "\(guiDomain)/\(l)"]).status == 0
            check(loaded, ok: "The \(n) is loaded", fix: "The \(n) isn't loaded", .reinstall)
        }
    }
    if noLaunchctl { out("  skip  Agent status not checked (sandbox)") }

    section("Claude Code")
    let cl = findClaude()
    out(cl.map { "  ok    Claude Code found (\(shortPath($0)))" } ?? "  note  Claude Code was not found (Jeb works, but needs Claude Code to show in sessions)")
    if cl != nil {
        let info = pluginInfo(), plug = info.plugin, legacy = legacyEntries()
        let want = Json.load(live + "/mod/.claude-plugin/plugin.json")?["version"]
        if plug != nil, let l = legacy.first {
            fix("Jeb is loaded twice in Claude Code (as a plugin and through an old setting, \(shortPath(l)))", .reinstall)
        } else if let l = legacy.first {
            fix("Jeb still loads through an old Claude Code setting (\(shortPath(l)))", .reinstall)
        } else {
            check(plug != nil && plug?["enabled"]?.bool != false, ok: "The Jeb plugin is installed in Claude Code", fix: "The Jeb plugin isn't installed in Claude Code", .reinstall)
        }
        if let plug = plug {
            let wanted = want.flatMap { $0.truthy ? $0 : nil }
            check(wanted == nil || plug["version"] == wanted, ok: "The plugin version matches the mod (\(pyStr(plug["version"])))",
                  fix: "The plugin version (\(pyStr(plug["version"]))) differs from the mod (\(pyStr(want)))", .update)
        }
        if let mkt = info.market {
            let mp = [mkt["path"], mkt["installLocation"]].compactMap { $0?.string }.first { !$0.isEmpty } ?? ""
            check(sameDir(mp, live), ok: "Claude Code's Jeb plugin source is this install", fix: "Claude Code's Jeb plugin source points at \(shortPath(mp)), not this install", .reinstall)
        } else if plug != nil {
            fix("Claude Code doesn't know where the Jeb plugin comes from", .reinstall)
        }
    }
    let sp = storePath()
    if fm.fileExists(atPath: sp) {
        if let data = fm.contents(atPath: sp).flatMap({ try? Json.parse($0) }) {
            let keys = (data.object ?? []).map { $0.0 }
            check(keys.contains("farm"), ok: "Farm data found (\(keys.filter { $0.hasPrefix("live:") }.count) live session(s))", fix: "No farm data yet", .newSession)
        } else {
            fix("The farm data file can't be read", .newSession)
        }
    } else {
        fix("No farm data yet", .newSession)
    }

    section("Updates")
    check(!fm.fileExists(atPath: stateHome + "/updates-paused"), ok: "Updates are on", fix: "Updates are paused", .resume)
    // follow records every release check in release-state; updater-state is the bundle updater's own record
    let last = loadRState()["last"]?["result"]?.string ?? Json.load(updaterStatePath)?["last"]?["result"]?.string
    check(!["rolled-back", "rejected", "rollback-failed", "swap-failed"].contains(last ?? ""),
          ok: "Last update result: \(last.flatMap { $0.isEmpty ? nil : $0 } ?? "none")",
          fix: "The last update failed (\(last ?? "")); the log is \(shortPath(updateLogPath))", .retry)
    let pinned = isRegularFile(pinnedSignersPath)
    if check(pinned, ok: "Release signing key pinned", fix: "The release signing key isn't pinned", .reinstall) {
        let covers = splitLines(readText(pinnedSignersPath) ?? "").contains { keyLine($0)?.ns?.names.contains("jeb-release") ?? false }
        check(covers, ok: "The pinned key covers jeb-release", fix: "The pinned key doesn't cover jeb-release", .reinstall)
    }
    if checkNetwork {
        do {
            let t = try latestTag(releaseBase(releaseRepo()), timeout: 15)
            out("  ok    GitHub releases reachable (newest \(t))")
        } catch let e as FetchError where e.status == nil {
            out("  skip  GitHub releases not checked: \(e)")
        } catch {
            fix("GitHub releases can't be reached (\(error))", .network)
        }
    }

    return DoctorReport(lines: lines, steps: steps, problems: bad, jebctl: jebctlName)
}

/// The full report, printed. Exit 1 when anything needs a fix.
func printDoctor() -> Int32 {
    let r = diagnose()
    r.lines.forEach(say)
    say("")
    doctorSummary(steps: r.steps, problems: r.problems, jebctl: r.jebctl).forEach(say)
    return r.problems == 0 ? 0 : 1
}

/// The first step, in priority order, that `--fix` can run and has not run yet; nil when none is left.
/// While updates are paused, update and retry-update would only refuse, so they are left for after resume-updates.
func nextFixStep(_ steps: [FixStep], tried: Set<FixID>) -> FixStep? {
    let paused = steps.contains { $0.id == .resume }
    return steps.sorted { $0.priority < $1.priority }.first {
        $0.id.runnable && !tried.contains($0.id) && !(paused && ($0.id == .update || $0.id == .retry))
    }
}

/// The commands that run a step, as argv lists run in order (restartAll is two). Always the live install's own
/// jebctl, except redownload, which uses the standalone tool that fetches a fresh release.
func fixCommands(_ s: FixStep) -> [[String]] {
    switch s.id {
    case .redownload: return [[toolsDir() + "/jebctl", "install"]]
    case .reinstall: return [[liveJebctl, "install"]]
    case .restartAll: return [[liveJebctl, "quit"], [liveJebctl, "start"]]
    case .start: return [[liveJebctl, "start"]]
    case .retry: return [[liveJebctl, "retry-update"]]
    case .update: return [[liveJebctl, "update"]]
    case .resume, .addPath, .pathOrder, .newSession, .network: return []
    }
}

/// A step's commands as the user would type them.
func fixDisplay(_ s: FixStep) -> String {
    fixCommands(s).map { ([shortPath($0[0])] + $0.dropFirst()).joined(separator: " ") }.joined(separator: ", then ")
}

/// `doctor --fix`: run the safe repair steps one at a time, each at most once, re-checking in between, then print the full report.
/// Steps run as subprocesses so an install hand-over or exec cannot end the doctor.
/// With --dry-run, one pass lists what would run and changes nothing: the checks cannot be repeated without running the steps.
func cmdDoctorFix() -> Int32 {
    var tried = Set<FixID>()
    if dryRun {
        let steps = diagnose(checkNetwork: false).steps
        while let s = nextFixStep(steps, tried: tried) { say("would run: " + fixDisplay(s)); tried.insert(s.id) }
        if tried.isEmpty { say("nothing to fix automatically") }
        say("")
        return printDoctor()
    }
    var first = true
    while let s = nextFixStep(diagnose(checkNetwork: false).steps, tried: tried) {
        first = false
        say("fixing: " + fixDisplay(s))
        var rc: Int32 = 0
        for argv in fixCommands(s) {
            let r = run(argv, capture: false).status
            if r != 0 { rc = r }
        }
        say(rc == 0 ? "  done" : "  failed (exit \(rc))")
        tried.insert(s.id)
    }
    if first { say("nothing to fix automatically") }
    say("")
    return printDoctor()
}

func cmdDoctor(_ rest: [String]) -> Int32 {
    if let bad = rest.first(where: { $0 != "--fix" }) {
        say("jebctl doctor: unknown option \(bad)")
        return 2
    }
    return rest.contains("--fix") ? cmdDoctorFix() : printDoctor()
}
