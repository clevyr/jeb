// Install: `jebctl install` and `jebctl uninstall` for an unpacked release bundle (~/.jeb/versions/<tag>), with the
// jebctl link, the PATH line of the shell profile and the state-folder move.
// One command does the whole install and uninstall; the git-clone layout and dev mode are gone (plan D1). The app is never
// compiled: the bundle's own `jebctl apply` gates the prebuilt one and swaps it in.
import Foundation

let installUsage = "usage: jebctl install [--repin] [--add-path] [--no-agents] [--dry-run] [--verbose]"
let uninstallUsage = "usage: jebctl uninstall [--purge] [--purge-farm] [--remove-files] [--dry-run] [--verbose]"

/// The folder this jebctl's bundle is unpacked in (<root>/desktop/bin/jebctl); it holds bundle.json when this is one.
func bundleRoot() -> String { (codeDir() as NSString).deletingLastPathComponent }

/// An install that cannot go on: the open step line is closed with "failed", then the reason on stderr.
func installFail(_ msg: String) -> Never {
    if openLine { fin("failed") }
    die(msg)
}

// ---- the state folder ----

/// Move the old state folder to ~/Library/Application Support/Jeb (once), then follow it. Returns the status.
@discardableResult
func migrateHome() -> String {
    let r = migrate(log: { say($0) }, dry: dryRun)
    if r == "moved" || r == "failed" { setHome(resolveHome()) }
    return r
}

// ---- the jebctl link and PATH ----

let pathMark = "# added by Jeb's ./install"

func binDir() -> String { envVar("JEB_BIN_DIR").flatMap { $0.isEmpty ? nil : $0 } ?? expandUser("~/.local/bin") }
func linkPath() -> String { binDir() + "/jebctl" }

func isSymlink(_ p: String) -> Bool {
    var st = stat()
    return lstat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
}

func isDir(_ p: String) -> Bool {
    var st = stat()
    return stat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
}

/// Same file as the live jebctl (the stable ~/.jeb/current path), however the path is spelled.
func isMe(_ path: String) -> Bool {
    var a = stat(), b = stat()
    return stat(path, &a) == 0 && stat(liveJebctl, &b) == 0 && a.st_dev == b.st_dev && a.st_ino == b.st_ino
}

/// none | ours | older (a link to another Jeb clone's or bundle's jebctl) | foreign (anything else: leave it).
func linkState() -> String {
    let p = linkPath()
    if !lexists(p) { return "none" }
    if !isSymlink(p) { return "foreign" }
    let r = pyRealpath(p)
    if pyRealpath(liveJebctl) == r || isMe(p) { return "ours" }
    let dir = (r as NSString).deletingLastPathComponent
    let d = (dir as NSString).lastPathComponent, up = ((dir as NSString).deletingLastPathComponent as NSString).lastPathComponent
    return (r as NSString).lastPathComponent == "jebctl" && (d == "desktop" || (d == "bin" && up == "desktop")) ? "older" : "foreign"
}

/// Link ~/.local/bin/jebctl to the live jebctl. True when it is (or, in a dry run, would be) ours.
func linkJebctl() -> Bool {
    let p = linkPath(), st = linkState()
    if st == "ours" {
        detail("\(p) already points here")
        return true
    }
    if st == "foreign" {
        say("warning: \(p) exists and is not a link to a Jeb jebctl; left alone, so `jebctl` is not set up (run \(liveJebctl))")
        return false
    }
    detail("link \(p) -> \(liveJebctl)" + (st == "older" ? " (replaces the link to \(pyRealpath(p)))" : ""))
    if !dryRun {
        try? FileManager.default.createDirectory(atPath: binDir(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let tmp = p + ".tmp"
        unlink(tmp)
        guard symlink(liveJebctl, tmp) == 0, rename(tmp, p) == 0 else { installFail("cannot link \(p): \(String(cString: strerror(errno)))") }
    }
    return true
}

func onPath(_ d: String) -> Bool {
    let want = pyRealpath(d)
    return (envVar("PATH") ?? "").split(separator: ":").contains { pyRealpath(expandUser(String($0))) == want }
}

/// The login profile of the user's shell: zsh ~/.zprofile, bash ~/.bash_profile, else ~/.profile (JEB_PROFILE overrides).
func profilePath() -> String {
    if let p = envVar("JEB_PROFILE"), !p.isEmpty { return p }
    switch ((envVar("SHELL") ?? "") as NSString).lastPathComponent {
    case "zsh": return expandUser("~/.zprofile")
    case "bash": return expandUser("~/.bash_profile")
    default: return expandUser("~/.profile")
    }
}

func exportLine() -> String {
    let d = binDir()
    return d == expandUser("~/.local/bin") ? "export PATH=\"$HOME/.local/bin:$PATH\"" : "export PATH=\"\(d):$PATH\""
}

/// The profile's lines with their newlines kept (str.splitlines(keepends=True) for "\n").
func profileLines(_ text: String) -> [String] {
    var out: [String] = [], cur = ""
    for c in text {
        cur.append(c)
        if c == "\n" { out.append(cur); cur = "" }
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

func bare(_ l: String) -> String { l.hasSuffix("\n") ? String(l.dropLast()) : l }

func backupProfile(_ prof: String) {
    let dest = backupName((prof as NSString).lastPathComponent + "." + Clock.strftime("%Y%m%d-%H%M%S"), "bak")
    do { try copyFile2(prof, dest) } catch { installFail("cannot back up \(prof): \(error.localizedDescription)") }
    detail("  backup: " + dest)
}

func writeProfile(_ prof: String, _ text: String) {
    // in place (not a rename): a profile that is a link into a dotfiles folder stays one
    guard let h = FileHandle(forWritingAtPath: prof) ?? (FileManager.default.createFile(atPath: prof, contents: nil) ? FileHandle(forWritingAtPath: prof) : nil) else {
        installFail("cannot write \(prof)")
    }
    h.truncateFile(atOffset: 0)
    h.write(Data(text.utf8))
    h.closeFile()
}

func addToProfile() {
    let prof = profilePath(), text = readText(prof) ?? ""
    if profileLines(text).contains(where: { bare($0) == pathMark }) {
        say("\(prof) already has the PATH line; open a new terminal")
        return
    }
    detail("add to \(prof): \(pathMark) / \(exportLine())")
    if dryRun { return }
    if !text.isEmpty { backupProfile(prof) }
    writeProfile(prof, text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + pathMark + "\n" + exportLine() + "\n")
    say("open a new terminal for `jebctl` to work")
}

func removeFromProfile() {
    let prof = profilePath(), lines = profileLines(readText(profilePath()) ?? "")
    guard lines.contains(where: { bare($0) == pathMark }) else { return }
    var out: [String] = [], i = 0
    while i < lines.count {
        if bare(lines[i]) == pathMark {
            i += i + 1 < lines.count && lines[i + 1].hasPrefix("export PATH=") ? 2 : 1
        } else {
            out.append(lines[i])
            i += 1
        }
    }
    detail("remove the PATH lines from \(prof)")
    if !dryRun {
        backupProfile(prof)
        writeProfile(prof, out.joined())
    }
}

func pathStep(add: Bool) {
    let d = binDir()
    if onPath(d) {
        detail("\(d) is on PATH")
        return
    }
    if add {
        addToProfile()
    } else {
        let home = expandUser("~")
        say("Run Jeb's tool as " + (d.range(of: home).map { d.replacingCharacters(in: $0, with: "~") } ?? d) + "/jebctl")
    }
}

func unlinkJebctl() {
    let p = linkPath()
    if isSymlink(p) && isMe(p) {
        detail("remove \(p)")
        if !dryRun { unlink(p) }
        line("jebctl command", dryRun ? "would remove" : "removed")
    } else if lexists(p) {
        say("\(p) is not a link to this jebctl; left alone")
    } else {
        line("jebctl command", "not installed")
    }
    removeFromProfile()
}

/// An existing standalone jebctl (JEB_TOOLS_DIR, default ~/.jeb/bin: what the README's curl line fetched) becomes this
/// bundle's desktop/bin/jebctl, copied beside it and renamed over. Only a Mach-O replaces it and nothing is created.
/// from: the jebctl to copy (default: this bundle's own; `apply` names the bundle it just installed).
func refreshStandalone(from: String? = nil) {
    let src = from ?? codeDir() + "/bin/jebctl", dst = toolsDir() + "/jebctl"
    if !isRegularFile(dst) || isSymlink(dst) || machoArchs(src).isEmpty || pyRealpath(src) == pyRealpath(dst) { return }
    (dryRun ? say : detail)("\(dryRun ? "would refresh" : "refresh") \(dst) from \(src)")
    if dryRun { return }
    do {
        try? FileManager.default.removeItem(atPath: dst + ".new")
        try FileManager.default.copyItem(atPath: pyRealpath(src), toPath: dst + ".new")
        chmod(dst + ".new", 0o755)
        if rename(dst + ".new", dst) != 0 { throw posixError("rename", dst) }
    } catch { say("warning: could not refresh \(dst): \(error)") }
}

// ---- the bundle's app ----

/// JEB_MOD of the loaded desktop agent's plist: where the mod loaded from before this install.
func agentMod() -> String? {
    (plistAt(agentsDir() + "/com.jeb.desktop.plist")?["EnvironmentVariables"] as? [String: Any])?["JEB_MOD"] as? String
}

/// Gates and first start through the bundle's own `jebctl apply` (it points `current` at the bundle and swaps the
/// app in, and puts both back when a gate fails). This process holds release.lock for it.
func applyBundle(_ clone: String, tag: String) {
    let cmd = [clone + "/desktop/bin/jebctl", "apply", clone, "--lock-held", "--no-watch"]
    if dryRun {
        detail("$ " + cmd.joined(separator: " "))
        detail("\(currentDir()) -> versions/\(tag)")
        return
    }
    let lock = open(stateHome + "/release.lock", O_WRONLY | O_CREAT, 0o644)
    if lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0 { installFail("an update is running; try again in a few minutes") }
    defer { close(lock) }
    let cur = currentDir()
    let before = lexists(cur) ? pyRealpath(cur) : nil
    var env = scrubbedEnv()
    env["JEB_HOME"] = stateHome
    env["JEB_APP_DIR"] = appDir()
    let r = run(cmd, env: env, capture: !verbose)
    if r.status == 0 && isDir(installedApp) { return }
    var tail = Array(splitLines(readText(updateLogPath) ?? "").suffix(6))
    if tail.isEmpty && !verbose { tail = Array(splitLines(r.text).suffix(6)) }
    // the safety net of the apply contract: `current` never stays at a bundle that was not installed
    putBackCurrent(after: clone, before: before, rc: r.status == 0 ? 1 : r.status)      // a zero exit with no app installed counts as failed
    installFail("a gate failed; nothing installed.\n" + tail.joined(separator: "\n"))
}

// ---- install ----

/// A JebDesktop that is not the installed app (an older install, a manual start) hands the desktop to the installed one.
func handOver() {
    guard let old = running().first?.pid else { return }
    detail("handing over from pid \(old)")
    if dryRun {
        detail("$ JEB_HANDOFF_FROM=\(old) JEB_START=manual \(installedExe)")
        return
    }
    var env = ProcessInfo.processInfo.environment
    env["JEB_HANDOFF_FROM"] = String(old)
    env["JEB_START"] = "manual"
    var actions: posix_spawn_file_actions_t?
    var attr: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attr)
    defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attr) }
    posix_spawn_file_actions_addopen(&actions, 1, stateHome + "/run.log", O_WRONLY | O_CREAT | O_APPEND, 0o644)
    posix_spawn_file_actions_adddup2(&actions, 1, 2)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var cargv: [UnsafeMutablePointer<CChar>?] = [strdup(installedExe), nil]
    var cenv: [UnsafeMutablePointer<CChar>?] = env.map { strdup($0.key + "=" + $0.value) } + [nil]
    defer { for p in cargv + cenv { free(p) } }
    var child: pid_t = 0
    guard posix_spawn(&child, installedExe, &actions, &attr, &cargv, &cenv) == 0 else {
        installFail("the installed app did not start (\(String(cString: strerror(errno)))); nothing was loaded, the old instance runs on")
    }
    for _ in 0..<120 {
        Clock.sleep(1)
        if kill(old, 0) != 0 && errno == ESRCH {
            detail("pid \(child) took over; pid \(old) is gone")
            return
        }
        var status: Int32 = 0
        if waitpid(child, &status, WNOHANG) == child {
            let rc = status & 0x7f == 0 ? (status >> 8) & 0xff : -(status & 0x7f)
            installFail("the installed app exited (\(rc)) before taking over; nothing was loaded, the old instance runs on")
        }
    }
    kill(child, SIGTERM)
    installFail("no takeover within 120 s (waiting for a desktop Space?); stopped the new one, the old instance runs on. Nothing was loaded.")
}

/// Plists, the LaunchAgents, the desktop wait and the jebctl link.
func finishInstall(noAgents: Bool, addPath: Bool) {
    let mode = "release", fm = FileManager.default
    lead("LaunchAgents")
    detail("2. plists")
    writePlists(stateHome + "/launchd", mode)
    if !dryRun { unlink(stateHome + "/quit") }
    if noAgents {
        detail("3-5. hand-over, LaunchAgents (copy, bootout, bootstrap), waiting for the desktop and the jebctl link: skipped (--no-agents)")
        fin("skipped (--no-agents)")
        lead("desktop")
        fin("skipped (--no-agents)")
        line("jebctl command", "skipped (--no-agents)")
        return
    }
    detail("3. hand the desktop over from any running instance")
    handOver()
    detail("4. LaunchAgents")
    let mine = labelsFor(mode), agents = agentsDir()
    for l in mine {
        let src = stateHome + "/launchd/" + l + ".plist", dst = agents + "/" + l + ".plist"
        if dryRun {
            detail("$ cp \(src) \(dst)")
            continue
        }
        try? fm.createDirectory(atPath: agents, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: dst)
        do { try fm.copyItem(atPath: src, toPath: dst) } catch { installFail("cannot copy \(src) to \(dst): \(error.localizedDescription)") }
    }
    for l in allLabels {
        launchctl(["bootout", "\(guiDomain)/\(l)"])     // a re-install: "not loaded" is ignored
        if !mine.contains(l) {                          // an agent of the old dev mode goes
            detail("remove \(agents)/\(l).plist (not part of \(mode) mode)")
            if !dryRun { unlink(agents + "/" + l + ".plist") }
        }
    }
    for l in ["com.jeb.desktop.update", "com.jeb.desktop.watchdog", "com.jeb.desktop", "com.jeb.desktop.release"] where mine.contains(l) {
        let a = ["bootstrap", guiDomain, agents + "/" + l + ".plist"]
        if launchctl(a) != 0 { installFail("failed: launchctl " + a.joined(separator: " ")) }
    }
    fin(dryRun ? "skipped (dry run)" : "ok")
    lead("desktop")
    var up = false
    if !dryRun {
        for _ in 0..<60 {
            Clock.sleep(1)
            let procs = running()
            if procs.count == 1 && procs[0].path.hasPrefix(installedApp) {
                up = true
                break
            }
        }
        if verbose { cmdStatus() }
    }
    fin(dryRun ? "skipped (dry run)" : up ? "running" : "not running yet; see `jebctl status`")
    detail("5. jebctl on PATH")
    let st = linkState()
    let ok = linkJebctl()
    line("jebctl command", !ok ? "not set up" : dryRun && st != "ours" ? "would link" : "ok")
    if ok { pathStep(add: addPath) }
}

/// Install from the unpacked bundle this jebctl sits in: signers pinned, the prebuilt app gated and swapped in with
/// ~/.jeb/current pointed at the bundle, then the plists, the LaunchAgents and the jebctl link, all on that one path.
func installBundle(_ clone: String, repin: Bool, noAgents: Bool, addPath: Bool) {
    let vd = versionsDir()
    guard let tag = codeBundle()?["tag"]?.string, pyRealpath((clone as NSString).deletingLastPathComponent) == pyRealpath(vd) else {
        installFail("run install from the unpacked bundle in \(vd)/<tag>, as the README says")
    }
    lead("signers")
    migrateHome()
    makePrivateDir(stateHome)
    pinSigners(repin: repin)
    widenSigners(repoSignersPath())
    fin("ok")
    lead("app")
    if !dryRun, let why = bundleAppProblem(clone + "/app") {
        installFail("the bundle's app is unusable: \(why)\nNothing was installed or changed.")
    }
    detail("1. gates and first start through the bundle's jebctl apply (prebuilt app, never compiled)")
    let t0 = Clock.now
    let oldMod = agentMod()
    applyBundle(clone, tag: tag)
    fin(dryRun ? "skipped (dry run)" : "ok (prebuilt \(tag), \(fixed(Clock.now - t0, 0))s)")
    if !dryRun {
        FileManager.default.createFile(atPath: modeFilePath, contents: Data("release\n".utf8))
        var rs = loadRState()
        rs.set("layout", .string("bundle"))
        rs.set("last", .object([("at", .int(Clock.epoch)), ("tag", .string(tag)), ("result", .string("ok")), ("app", .string("prebuilt"))]))
        if !(rs["installed"]?.array ?? []).contains(where: { $0["tag"]?.string == tag }) { recordInstalled(&rs, tag) }
        if let m = oldMod, pyRealpath(m) != pyRealpath(liveMod) { rs.set("legacy_mod", .string(m)) }
        do { try saveRState(rs) } catch { installFail("jebctl: \(error)") }
    }
    finishInstall(noAgents: noAgents, addPath: addPath)
    refreshStandalone()
    if !dryRun { pruneVersions() }
}

/// `jebctl install [--repin] [--add-path] [--no-agents]`: checks, the bundle install, then the mod registered through
/// Claude Code's plugin system (Jeb's own CLAUDE_CODE_PLUGIN_DIRS entry leaves settings.json, backup first) and the
/// doctor. The exit code.
func cmdInstall(_ flags: [String]) -> Int32 {
    if let bad = flags.first(where: { !["--repin", "--add-path", "--no-agents"].contains($0) }) {
        say("jebctl install: unknown option \(bad)\n" + installUsage)
        return 2
    }
    let clone = bundleRoot(), noAgents = flags.contains("--no-agents")
    if verbose {
        say("Jeb install (release mode\(dryRun ? ", dry run" : "")) from \(clone)")
    } else {
        say("Installing Jeb (release mode\(dryRun ? ", dry run" : ""))")
        lead("checks")
    }
    if !isDir(clone + "/mod") { installFail("install: \(clone)/mod not found; the bundle is incomplete") }
    fin("ok")
    if findClaude() == nil {
        say("note: Claude Code was not found on this Mac; Jeb installs anyway, but it needs Claude Code to show up in sessions")
    }
    installBundle(clone, repin: flags.contains("--repin"), noAgents: noAgents, addPath: flags.contains("--add-path"))

    lead("Claude Code plugin")
    var msgs: [String] = []
    let old = loadRState()["legacy_mod"]?.string ?? ""      // a git clone's entry from before this bundle
    let res = registerPlugin(currentDir(), dry: dryRun, say: { verbose ? say($0) : msgs.append($0) }, extra: [old])
    if res == "ok" {
        fin("ok")
    } else {
        fin("not registered")
        if !verbose { msgs.forEach { say("  " + $0) } }
        switch res {
        case "no-claude": say("note: Claude Code is not installed, so Jeb is not registered yet; run ./install again after installing it")
        case "conflict": say("note: a Claude Code marketplace named \"jeb\" already points elsewhere; Jeb was left as it was (run jebctl doctor)")
        default: say("note: Claude Code refused the plugin install; Jeb was left as it was (run ./install again, or jebctl doctor)")
        }
    }
    for m in msgs where m.hasPrefix("moved") { say("  " + m) }
    if dryRun {
        if !verbose { say("Dry run only; nothing was changed.") }
        return 0
    }
    if !noAgents {      // a sandbox has no agents loaded; ./release smoke runs the doctor itself
        say("Health check (jebctl doctor):")
        _ = cmdDoctor()     // its result does not fail the install
    }
    say("Done. Start a new Claude Code session to load Jeb; the desktop fills in once a session has run.")
    return 0
}

// ---- uninstall ----

/// The desktop part: the LaunchAgents, the running app and the app bundle go; --purge empties the state folder too.
func uninstallDesktop(purge: Bool) {
    let fm = FileManager.default
    if purge && ["/", "~", "~/.claude", "~/Library/Application Support"].map({ pyRealpath(expandUser($0)) }).contains(pyRealpath(stateHome)) {
        die("refusing to purge \(stateHome): JEB_HOME must be the desktop's own folder")       // purge empties it whole
    }
    lead("LaunchAgents and app")
    for l in ["com.jeb.desktop.release", "com.jeb.desktop.update", "com.jeb.desktop.watchdog", "com.jeb.desktop"] {
        launchctl(["bootout", "\(guiDomain)/\(l)"])
    }
    for l in allLabels {
        let p = agentsDir() + "/" + l + ".plist"
        detail("remove \(p)")
        if !dryRun { unlink(p) }
    }
    if !dryRun {
        writeQuitMarker()
        terminateAll()
    }
    detail("remove \(installedApp)")
    if !dryRun {
        try? fm.removeItem(atPath: installedApp)
        unlink(stateHome + "/quit")
    }
    fin(dryRun ? "would remove" : "removed")
    if purge {
        lead("desktop folder")
        // everything in the state folder (the desktop's own 0700 folder), then the folder if it is empty; a symlink is
        // unlinked, never followed
        for n in isDir(stateHome) ? ((try? fm.contentsOfDirectory(atPath: stateHome)) ?? []).sorted() : [] {
            let p = stateHome + "/" + n
            detail("purge \(p)")
            if dryRun { continue }
            if isRealDir(p) { try? fm.removeItem(atPath: p) } else { unlink(p) }
        }
        detail("purge \(stateHome)")
        if !dryRun { rmdir(stateHome) }
        fin(dryRun ? "would purge" : "purged")
    } else {
        detail("kept versions and logs")
    }
    let old = oldPath()
    if isSymlink(old) && pyRealpath(old) == pyRealpath(stateHome) {
        detail("remove the link \(old)")
        if !dryRun { unlink(old) }
    }
    unlinkJebctl()
}

/// True when path is a git clone with no local changes (so deleting it loses nothing).
func cleanGitClone(_ path: String) -> Bool {
    guard isDir(path + "/.git"), let git = which("git") ?? (isExecutableFile("/usr/bin/git") ? "/usr/bin/git" : nil) else { return false }
    let r = run([git, "-C", path, "status", "--porcelain"])
    return r.status == 0 && r.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// --remove-files, the last step: ~/.jeb goes entirely (this program runs from it, but is loaded by now), plus an old
/// git clone named in release-state when it is clean.
func removeFiles(legacyClone: String?) {
    let jd = jebDir()
    if let old = legacyClone, !old.isEmpty, isDir(old), pyRealpath(old) != pyRealpath(jd), !isSymlink(old) {
        if cleanGitClone(old) {
            say("  old clone ... " + (dryRun ? "would remove " : "removed ") + old)
            if !dryRun { try? FileManager.default.removeItem(atPath: old) }
        } else {
            say("  old clone ... kept: \(old) has local changes or is not a git clone")
        }
    }
    say("  files ... " + (dryRun ? "would remove " : "removed ") + jd)
    if !dryRun { try? FileManager.default.removeItem(atPath: jd) }
}

/// `jebctl uninstall [--purge] [--purge-farm] [--remove-files]`: the desktop part, then the plugin leaves Claude Code
/// (its farm kept unless --purge-farm, backed up first) and Jeb's CLAUDE_CODE_PLUGIN_DIRS entries leave settings.json.
func cmdUninstall(_ flags: [String]) -> Int32 {
    if let bad = flags.first(where: { !["--purge", "--purge-farm", "--remove-files", "--remove-clone"].contains($0) }) {
        say("jebctl uninstall: unknown option \(bad)\n" + uninstallUsage)
        return 2
    }
    let farm = flags.contains("--purge-farm")
    // the bundle this jebctl sits in; a standalone copy speaks for the live one
    let clone = codeBundle() != nil ? bundleRoot() : pyRealpath(currentDir())
    say(verbose ? "Jeb uninstall\(dryRun ? " (dry run)" : "") from \(clone)" : "Uninstalling Jeb\(dryRun ? " (dry run)" : "")")
    let rs = Json.load(releaseStatePath)        // read before the desktop part runs (--purge deletes it)
    uninstallDesktop(purge: flags.contains("--purge"))
    let note: (String) -> Void = { if verbose { say($0) } }
    unregisterPlugin(purgeFarm: farm, dry: dryRun, say: note, source: currentDir())
    removeEntry(liveMod, dry: dryRun, say: note)        // settings.json only ever named the stable path
    for k in ["legacy_clone", "legacy_mod"] {
        if let old = rs?[k]?.string, !old.isEmpty { removeEntry(old.hasSuffix("/mod") ? old : old + "/mod", dry: dryRun, say: note) }
    }
    line("plugin", dryRun ? "would unregister" : "unregistered from Claude Code")
    let files = storeFiles()
    if farm {
        for f in files {
            detail("farm \(f): back up, then remove")
            if dryRun { continue }
            do { detail("  backup: " + (try backupStoreFile(f))) } catch { die("cannot back up \(f): \(error.localizedDescription)") }
            unlink(f)
        }
        if files.isEmpty {
            say(verbose ? "no farm file found" : "  farm ... none found")
        } else {
            line("farm", dryRun ? "would remove (backup first)" : "removed (backed up first)")
        }
    } else if verbose {
        say("farm kept (\(files.count) file(s) in \(storeDir())); --purge-farm removes it")
    } else {
        say("  farm ... kept (\(files.count) file(s)); --purge-farm removes it")
    }
    if flags.contains("--remove-files") || flags.contains("--remove-clone") {
        removeFiles(legacyClone: rs?["legacy_clone"]?.string)
    } else {
        say("the files at \(clone) were not removed")
    }
    return 0
}
