// Doctor: `jebctl doctor`, the read-only health check (bundle layout). One line per check,
// `ok` or `FIX` with what to do, `note`/`skip` for what is not a fault, then the count; exit 1 when anything needs a fix.
// The bundle ships no Python, so that check is gone (deviation #4 in the goldens README).
import Foundation

func plistAt(_ path: String) -> [String: Any]? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any]
}

func cmdDoctor() -> Int32 {
    let fm = FileManager.default
    var bad = 0
    @discardableResult
    func check(_ good: Bool, _ what: String, _ fix: String = "") -> Bool {
        say(good ? "ok    " + what : "FIX   \(what): \(fix)")
        if !good { bad += 1 }
        return good
    }
    let m = installMode(), live = currentDir()
    let FIX = { (dev: String) in m == "dev" ? dev : "ask Claude to repair Jeb (it re-runs the install)" }
    #if os(macOS)
    check(true, "macOS", "Jeb runs on macOS only")
    #else
    check(false, "macOS", "Jeb runs on macOS only")
    #endif
    check(liveValid(), "\(live) resolves to a Jeb bundle", FIX(""))
    let vd = versionsDir()
    let vs = ((try? fm.contentsOfDirectory(atPath: vd)) ?? []).sorted().filter { isDir(vd + "/" + $0) }
    check(vs.count <= 1, "one version on disk (\(vs.isEmpty ? "none" : vs.joined(separator: ", ")))", "run: jebctl follow (it removes the older folder), or ask Claude to repair Jeb")
    if let lc = loadRState()["legacy_clone"]?.string, !lc.isEmpty, isDir(lc) {
        say("note  the old git clone \(lc) is no longer used; it can be deleted")
    }
    let cl = findClaude()
    say(cl.map { "ok    claude found (\($0))" } ?? "note  claude was not found (Jeb works, but needs Claude Code to show in sessions)")
    let w = which("jebctl")
    if linkState() == "ours" {
        check(true, "jebctl command (\(linkPath()))")
    } else if let w = w {
        if isMe(w) {
            check(true, "jebctl on PATH (\(w))")
        } else {
            check(false, "jebctl on PATH is \(w)", FIX("it runs \(pyRealpath(w)), not this clone's \(liveJebctl); remove it or put \(binDir()) first on PATH"))
        }
    } else {
        check(false, "jebctl command", FIX("open a new terminal, or add \(binDir()) to PATH (./install --add-path)"))
    }
    // An install from before install-mode was recorded runs as dev, like installMode() says.
    say("ok    install mode: \(m)" + (isRegularFile(modeFilePath) ? "" : " (not recorded; dev is assumed)"))
    check(isDir(installedApp), "app bundle \(installedApp)", FIX("run: ./install"))
    let jm = plistAt(installedApp + "/Contents/Info.plist")?["JebMod"] as? String
    check(jm.map { isRegularFile($0 + "/hooks/pixel-art.ts") } ?? false, "app's mod folder (JebMod) has hooks/pixel-art.ts", FIX("reinstall: ./install"))
    for l in labelsFor(m) {
        let p = agentsDir() + "/" + l + ".plist"
        check(isRegularFile(p), "LaunchAgent plist \(l)", FIX("run: ./install"))
        if let pa = plistAt(p) {
            let paths = ((pa["ProgramArguments"] as? [Any]) ?? []).compactMap { $0 as? String }.filter { $0.hasPrefix("/") }
            check(!paths.isEmpty && paths.allSatisfy { fm.fileExists(atPath: $0) }, "\(l) ProgramArguments exist", FIX(""))
            if let jm2 = (pa["EnvironmentVariables"] as? [String: Any])?["JEB_MOD"] {
                check(jm2 as? String == liveMod, "\(l) JEB_MOD is \(liveMod)", FIX(""))
            }
        }
        if noLaunchctl {
            say("skip  LaunchAgent loaded \(l): skipped (sandbox)")
        } else {
            let loaded = run([which("launchctl") ?? "/bin/launchctl", "print", "\(guiDomain)/\(l)"]).status == 0
            check(loaded, "LaunchAgent loaded \(l)", FIX("run: ./install"))
        }
    }
    let procs = running(), beats = beatFiles()
    check(procs.count == 1, "exactly one JebDesktop running (\(procs.count))", "run: jebctl start (more than one: jebctl quit, then jebctl start)")
    for p in procs {
        let b = beats[p.pid]
        check(b.map { $0.age < 10 } ?? false, "heartbeat of pid \(p.pid) fresh" + (b.map { " (\(fixed($0.age, 1)) s)" } ?? ""), "run: jebctl start (or wait a minute; the watchdog restarts a stale one)")
    }
    check(!fm.fileExists(atPath: stateHome + "/quit"), "no quit marker", "Quit was chosen from the menu; run: jebctl start")
    check(!fm.fileExists(atPath: stateHome + "/updates-paused"), "updates not paused", "run: jebctl resume-updates")
    var listed: [String] = []
    do { listed = dirEntries(try currentDirs(loadSettings(settingsPath()))) } catch { say("      \(error)") }
    let viaSettings = listed.contains { sameDir($0, liveMod) }
    if m == "dev" {
        check(viaSettings, "plugin registered in \(settingsPath())", FIX("run: ./install again"))
    } else if cl != nil {
        let info = pluginInfo(), plug = info.plugin, legacy = legacyEntries()
        let want = Json.load(live + "/mod/.claude-plugin/plugin.json")?["version"]
        let moved = "run install (moves Jeb to Claude Code's plugin system)"
        if plug != nil, let l = legacy.first {
            check(false, "Jeb is loaded twice (\(pluginId) and \(l) in \(pluginDirsKey))", FIX(moved))
        } else if let l = legacy.first {
            check(false, "Jeb still loads through \(pluginDirsKey) (\(l))", FIX(moved))
        } else {
            check(plug != nil && plug?["enabled"]?.bool != false, "plugin \(pluginId) installed and enabled in Claude Code", FIX("run: ./install again"))
        }
        if let plug = plug {
            let wanted = want.flatMap { $0.truthy ? $0 : nil }
            check(wanted == nil || plug["version"] == wanted, "plugin version \(pyStr(plug["version"])) matches the mod (\(pyStr(want)))", FIX("run: jebctl follow, or ./install again (claude plugin update jeb@jeb)"))
        }
        if let mkt = info.market {
            let mp = [mkt["path"], mkt["installLocation"]].compactMap { $0?.string }.first { !$0.isEmpty } ?? ""
            check(sameDir(mp, live), "marketplace \"\(pluginMarket)\" points at \(live)", FIX("it points at \(mp); run: claude plugin marketplace remove jeb, then ./install again"))
        } else if plug != nil {
            check(false, "marketplace \"\(pluginMarket)\" is registered", FIX("run: ./install again"))
        }
    } else {
        check(viaSettings, "plugin registered in \(settingsPath())", FIX("install Claude Code, then run: ./install again"))
    }
    let sp = storePath(), newSession = "start a new Claude Code session so the plugin loads"
    if check(fm.fileExists(atPath: sp), "mod store file", newSession) {
        if let data = fm.contents(atPath: sp).flatMap({ try? Json.parse($0) }) {
            let keys = (data.object ?? []).map { $0.0 }
            check(keys.contains("farm"), "mod store parses, has farm, \(keys.filter { $0.hasPrefix("live:") }.count) live key(s)", newSession)
        } else {
            check(false, "mod store parses", newSession)
        }
    }
    let last = Json.load(updaterStatePath)?["last"]?["result"]?.string
    check(!["rolled-back", "rejected", "rollback-failed", "swap-failed"].contains(last ?? ""), "last update result: \(last.flatMap { $0.isEmpty ? nil : $0 } ?? "none")", "see \(updateLogPath); run: jebctl status")
    say("ok    state folder: \(stateHome)" + (stateHome == oldPath() && (envVar("JEB_HOME") ?? "").isEmpty ? " (older location; the next install or update moves it)" : ""))
    if m == "release" {
        let pinned = isRegularFile(pinnedSignersPath)
        check(pinned, "release signers pinned", FIX("run: ./install --repin from a bundle or clone that ships desktop/release-signers (a newer release also replaces it on its own)"))
        if pinned {
            let covers = splitLines(readText(pinnedSignersPath) ?? "").contains { keyLine($0)?.ns?.names.contains("jeb-release") ?? false }
            check(covers, "a pinned signer covers jeb-release", FIX(""))
        }
        do {
            let t = try latestTag(releaseBase(releaseRepo()), timeout: 15)
            check(true, "GitHub releases reachable (newest \(t))")
        } catch let e as FetchError where e.status == nil {
            say("skip  GitHub releases not checked: \(e)")
        } catch {
            check(false, "GitHub releases reachable (\(error))", "open github.com/clevyr/jeb/releases in a browser; a proxy or firewall must allow github.com and release-assets.githubusercontent.com")
        }
    }
    say(bad == 0 ? "all good" : "\(bad) problem(s)")
    return bad == 0 ? 0 : 1
}
