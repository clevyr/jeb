// Follow: the release follower and its siblings (desktop/jebctl cmd_follow, follow_bundle, fetch_bundle, run_update/run_apply,
// flip_current, undo_flip, prune_now, heal_plists, ensure_plugin, rollback_bundle, cmd_rollback, cmd_update, retry-update).
// Bundle layout only. A schema 2 bundle is gated and swapped by its own `jebctl apply` (B5); this file downloads, verifies
// and unpacks it, runs that, and owns release-state.json, release.log and the final status. The wire format of the
// apply call is the contract in runApply.
import CryptoKit
import Foundation

/// --no-agents (sandbox only): no post-swap watch, no agent reloads. Set once by main.
var noAgents = false

// ---- is the live bundle usable ----

/// True when ~/.jeb/current resolves to a bundle with its jebctl and app (schema 1, the bundles before 1.6: their Python and
/// Python jebctl). Follow, rollback and doctor ask the same before they trust the link.
func liveValid() -> Bool {
    let live = currentDir()
    let need = readBundle(live)?["schema"]?.int == 2 ? ["bundle.json", "desktop/bin/jebctl", "app/JebDesktop"] : ["bundle.json", "python/bin/python3", "desktop/jebctl"]
    return need.allSatisfy { isRegularFile(live + "/" + $0) }
}

/// nil when every binary of the unpacked app folder (JebDesktop, detect, png2raw) holds this Mac's architecture; they are made
/// executable and stripped of extended attributes. Else the reason.
func bundleAppProblem(_ d: String) -> String? {
    let arch = hostArch()
    for n in ["JebDesktop", "detect", "png2raw"] {
        let f = d + "/" + n
        if !isRegularFile(f) { return "\(n) is missing" }
        let got = machoArchs(f)
        if !got.contains(arch) { return "\(n) is not built for \(arch) (\(got.isEmpty ? "unreadable" : got.sorted().joined(separator: " ")))" }
        chmod(f, 0o755)
        run(["/usr/bin/xattr", "-c", f])
    }
    return nil
}

// ---- `current` ----

struct FlipError: Error, CustomStringConvertible {
    let description: String
}

/// Point ~/.jeb/current at target (a relative link when it sits in versions/); atomic. Returns the previous target as an absolute
/// path, or nil when there was none.
func flipCurrent(_ target: String) throws -> String? {
    let cur = currentDir(), vd = versionsDir(), fm = FileManager.default
    if lexists(cur) && !isSymlink(cur) { throw FlipError(description: "\(cur) is not a link; left alone") }
    var prev: String?
    if isSymlink(cur), let p = try? fm.destinationOfSymbolicLink(atPath: cur) {
        prev = p.hasPrefix("/") ? p : (cur as NSString).deletingLastPathComponent + "/" + p
    }
    let link = pyRealpath((target as NSString).deletingLastPathComponent) == pyRealpath(vd) ? "versions/" + (target as NSString).lastPathComponent : target
    let tmp = cur + ".new"
    if lexists(tmp) { unlink(tmp) }
    try fm.createDirectory(atPath: (cur as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    if symlink(link, tmp) != 0 { throw posixError("symlink", tmp) }
    if rename(tmp, cur) != 0 { throw posixError("rename", cur) }
    return prev
}

/// After a failed update: current goes back to prev, the new folder goes.
func undoFlip(_ prev: String?, _ new: String) {
    if let p = prev {
        do { _ = try flipCurrent(p) } catch { rlog("COULD NOT point \(currentDir()) back at \(p): \(error)") }
    }
    try? FileManager.default.removeItem(atPath: new)
}

/// The safety net of the apply contract: a failed apply never leaves `current` at the bundle it was applying. Puts it back at
/// `before` (none: removes the link). True when it had to.
@discardableResult
func putBackCurrent(after ver: String, before: String?, rc: Int32) -> Bool {
    let cur = currentDir()
    guard rc != 0, lexists(cur), pyRealpath(cur) == pyRealpath(ver), before != pyRealpath(ver) else { return false }
    rlog("apply left \(cur) at \((ver as NSString).lastPathComponent) (exit \(rc)); putting it back")
    if let b = before {
        do { _ = try flipCurrent(b) } catch { rlog("COULD NOT point \(cur) back at \(b): \(error)") }
    } else {
        unlink(cur + ".new")
        unlink(cur)
    }
    return true
}

/// pruneVersions, then a detached run from the live version that removes this process's own (old) folder once this process has
/// exited (deleting a running binary's folder is avoided), so a finished update leaves exactly one folder.
func pruneNow() {
    pruneVersions()
    guard codeBundle() != nil else { return }
    let me = pyRealpath((codeDir() as NSString).deletingLastPathComponent), live = pyRealpath(currentDir())
    if me != live && isDir(live) && liveValid() {
        _ = spawnDetached([liveJebctl, "prune-versions", "--wait-pid", String(Clock.pid)], env: scrubbedEnv())
    }
}

// ---- download, verify, unpack ----

struct BundleError {
    var why: String
    var permanent: Bool         // a bad signature, tag, hash, size or content: the tag is not retried (a signature rejection is, once the pin changes)
    var kind: String?           // signature, size, sha, content or arch; nil when not permanent
}

/// Download, verify and unpack release `tag` into ~/.jeb/versions/<tag>. Returns (path, nil), or (nil, error): network or a
/// missing asset retries later. Nothing is left half-done: the unpack goes to versions/.<tag>.partial and is renamed last.
/// pin and staging: the standalone install (Standalone.swift) trusts the signers built into jebctl instead of the pin and
/// downloads under a temp folder, since neither the state folder nor a pin exists on a fresh Mac.
func fetchBundle(_ tag: String, log: (String) -> Void, pin: String = pinnedSignersPath, staging: String? = nil) -> (path: String?, err: BundleError?) {
    let arch = hostArch(), base = releaseBase(releaseRepo()), fm = FileManager.default
    let vd = versionsDir()
    let dl = (staging ?? stateHome + "/staging") + "/" + tag + "-dl", part = vd + "/." + tag + ".partial", final = vd + "/" + tag
    let man = "Jeb-\(tag)-manifest.json", zname = "Jeb-\(tag)-macos-\(arch).zip"
    func done(_ res: (path: String?, err: BundleError?)) -> (path: String?, err: BundleError?) {
        for d in [dl, part] { try? fm.removeItem(atPath: d) }
        return res
    }
    func bad(_ why: String, _ kind: String = "content") -> (path: String?, err: BundleError?) {
        done((nil, BundleError(why: why, permanent: true, kind: kind)))
    }
    try? fm.removeItem(atPath: dl)
    try? fm.createDirectory(atPath: dl, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let paths = [dl + "/" + man, dl + "/" + man + ".sig", dl + "/" + zname]
    do {
        for (n, p) in zip([man, man + ".sig"], paths) { _ = try save("\(base)/download/\(tag)/\(n)", to: p, limit: manifestMax) }
    } catch let e as FetchError {
        return e.tooBig ? bad(e.message, "size") : done((nil, BundleError(why: "\(tag): \(e)", permanent: false, kind: nil)))
    } catch {
        return done((nil, BundleError(why: "\(tag): \(error)", permanent: false, kind: nil)))
    }
    if let err = verifyManifest(paths[0], sig: paths[1], tag: tag, pin: pin) { return bad(err.reason, err.kind) }
    let want = readText(paths[0]).flatMap { try? Json.parse($0) }?["bundles"]?[arch]
    guard let w = want, w.object != nil, w["name"]?.string == zname, let size = w["size"]?.int else {
        return bad("\(zname) does not match the signed manifest (hash or size)", "sha")
    }
    do {
        _ = try save("\(base)/download/\(tag)/\(zname)", to: paths[2], limit: size)
    } catch let e as FetchError {
        return e.tooBig ? bad("\(zname) is larger than the signed manifest says", "size") : done((nil, BundleError(why: "\(tag): \(e)", permanent: false, kind: nil)))
    } catch {
        return done((nil, BundleError(why: "\(tag): \(error)", permanent: false, kind: nil)))
    }
    guard let zip = FileHandle(forReadingAtPath: paths[2]) else { return bad("\(zname) does not match the signed manifest (hash or size)", "sha") }
    var hasher = SHA256()
    var total = 0
    while true {
        let chunk = zip.readData(ofLength: 1 << 20)
        if chunk.isEmpty { break }
        total += chunk.count
        hasher.update(data: chunk)
    }
    zip.closeFile()
    let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    if w["sha256"]?.string != hex || size != total { return bad("\(zname) does not match the signed manifest (hash or size)", "sha") }
    try? fm.removeItem(atPath: part)
    try? fm.createDirectory(atPath: vd, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    if run(["/usr/bin/ditto", "-x", "-k", paths[2], part]).status != 0 { return done((nil, BundleError(why: "could not unpack \(zname)", permanent: false, kind: nil))) }
    let root = pyRealpath(part)
    if let en = fm.enumerator(atPath: part) {
        for case let rel as String in en {
            let q = part + "/" + rel
            if isSymlink(q) && !(pyRealpath(q) + "/").hasPrefix(root + "/") {
                return bad("the bundle has a link that leaves its folder (\(rel))")
            }
        }
    }
    guard let b = readBundle(part), b.object?.isEmpty == false, b["tag"]?.string == tag, b["arch"]?.string == arch else {
        return bad("bundle.json does not say \(tag) for \(arch)")
    }
    let schema = b["schema"]?.int ?? 1
    if ![1, 2].contains(schema) { return bad("the bundle's schema (\(pyStr(b["schema"]))) is not one this jebctl knows") }
    let need = schema == 2
        ? ["install", "desktop/bin/jebctl", "mod", ".claude-plugin/marketplace.json", "app/JebDesktop", "app/detect", "app/png2raw"]
        : ["install", "desktop/jebctl", "desktop/updater.py", "mod", "python/bin/python3", "app/JebDesktop"]
    for rel in need where !fm.fileExists(atPath: part + "/" + rel) { return bad("the bundle lacks \(rel)") }
    if schema == 2 {
        let got = machoArchs(part + "/desktop/bin/jebctl")
        if !got.contains(arch) { return bad("desktop/bin/jebctl is not built for \(arch) (\(got.isEmpty ? "not a Mach-O" : got.sorted().joined(separator: " ")))", "arch") }
    }
    run(["/usr/bin/xattr", "-dr", "com.apple.quarantine", part])
    if let why = bundleAppProblem(part + "/app") { return bad(why, why.contains("is not built for") ? "arch" : "content") }
    if lexists(final) {
        if pyRealpath(final) == pyRealpath(currentDir()) { return done((nil, BundleError(why: "\(tag) is the installed version", permanent: false, kind: nil))) }
        try? fm.removeItem(atPath: final)
    }
    if rename(part, final) != 0 { return done((nil, BundleError(why: "could not move \(part) to \(final): \(String(cString: strerror(errno)))", permanent: false, kind: nil))) }
    log("bundle: \(zname) matches the signed manifest; unpacked into \(final)")
    return done((final, nil))
}

/// Why a tar member must not be extracted, or nil when it may be: only regular files and directories, relative names without
/// '..', nothing that resolves outside dest (the git-clone staging check, kept for the day an archive is unpacked again).
func unsafeMemberReason(name n: String, regular: Bool, directory: Bool, dest: String) -> String? {
    if !(regular || directory) { return "member '\(n)' is not a regular file or directory" }
    if n.hasPrefix("/") || n.split(separator: "/", omittingEmptySubsequences: false).contains("..") { return "member '\(n)' has an absolute or '..' name" }
    let root = pyRealpath(dest), target = pyRealpath(root + "/" + n)
    if target != root && !target.hasPrefix(root + "/") { return "member '\(n)' resolves outside the staging folder" }
    return nil
}

// ---- gates and swap ----

/// run_update for a schema 2 bundle: its own native jebctl does the gates and the swap.
///
/// CONTRACT between this follow and `desktop/bin/jebctl apply` of a schema 2 bundle:
///   argv    <ver>/desktop/bin/jebctl apply <ver> --not-final --lock-held [--no-watch] [--gates-only] [--quick]
///           <ver> is the unpacked, verified bundle folder (versions/<tag>). --no-watch: no post-swap watch (sandbox / --no-agents).
///           --gates-only: run the gates and stop before touching `current` or the app. --quick is always implied.
///   env     inherited, plus JEB_HOME (the state folder).
///   lock    the parent holds JEB_HOME/release.lock (--lock-held): apply must not take it, nor wait for it.
///   status  --not-final: apply writes the phase lines of update-status.json (source "release") but never the final one;
///           the parent writes it from the exit code. apply logs to JEB_HOME/update.log.
///   swap    on ANY failure apply restores everything itself (`current` back at the previous target, the previous app back);
///           it never leaves `current` at <ver> when it exits non-zero. It does not delete <ver> (the parent does). It never
///           touches release-state.json and never reloads LaunchAgents.
///   exit    0 installed and healthy; 2 rejected by a gate; 3 rolled back after the swap; anything else: error, retried later.
func runApply(_ ver: String, extra: [String]) -> Int32 {
    let cur = currentDir()
    let before = lexists(cur) ? pyRealpath(cur) : nil
    var cmd = [ver + "/desktop/bin/jebctl", "apply", ver, "--not-final", "--lock-held"]
    if noAgents { cmd.append("--no-watch") }
    cmd += extra.filter { $0 == "--gates-only" || $0 == "--quick" }
    var env = ProcessInfo.processInfo.environment
    env["JEB_HOME"] = stateHome
    var rc = run(cmd, env: env, capture: false).status
    if rc == 127 && !FileManager.default.isExecutableFile(atPath: cmd[0]) { rlog("apply error: \(cmd[0]) cannot be run"); rc = 1 }
    if before != nil { putBackCurrent(after: ver, before: before, rc: rc) }
    return rc
}

/// The gates on the unpacked bundle and, unless --gates-only, the swap. Only schema 2 bundles are applied here.
func runUpdate(_ ver: String, extra: [String]) -> Int32 {
    if readBundle(ver)?["schema"]?.int == 2 { return runApply(ver, extra: extra) }
    rlog("bundle: \((ver as NSString).lastPathComponent) is a schema 1 bundle; this jebctl only applies schema 2")
    return 1
}

// ---- plugin and agents ----

/// After an update (or when current): moves Jeb onto Claude Code's plugin system when it is not there yet, else refreshes
/// jeb@jeb only when its version differs from the mod's. Logged; never fails the follow.
func ensurePlugin() {
    let plug = pluginInfo().plugin
    if !legacyEntries().isEmpty || !(plug?.truthy ?? false) {
        let res = registerPlugin(currentDir(), dry: dryRun, say: rlog)
        rlog("plugin: registering \(pluginId): \(res)")
        return
    }
    let want = Json.load(currentDir() + "/mod/.claude-plugin/plugin.json")?["version"]?.string
    if let w = want, plug?["version"]?.string != w, !syncPlugin(dry: dryRun, say: rlog) {
        rlog("plugin: claude plugin update jeb@jeb did not run clean; run jebctl doctor")
    }
}

/// LaunchAgent plists that differ from plists() (a v1.4.0 install names the bundle's Python) are rewritten in place and the
/// agents reloaded once this run has exited; a leftover dev-mode update agent is booted out. Needs the native launcher in
/// place; skipped in dry runs and under --no-agents.
func healPlists() {
    if dryRun || noAgents || installMode() != "release" { return }
    let native = liveJebctl
    if machoArchs(native).isEmpty { return }
    var stale: [String] = []
    for (label, want) in plists("release") {
        guard let have = plistAt(agentsDir() + "/" + label + ".plist") else { continue }      // not installed (or unreadable): not for this to create
        if !NSDictionary(dictionary: have).isEqual(to: want) { stale.append(label) }
    }
    let strayPath = agentsDir() + "/com.jeb.desktop.update.plist"
    let stray = lexists(strayPath)
    if stale.isEmpty && !stray { return }
    if !stale.isEmpty {
        rlog("agents: \(stale.joined(separator: ", ")) name an older command; rewriting them to use \(native)")
        writePlists(agentsDir(), "release")
        spawnReload(noAgents: noAgents)
    }
    if stray {
        rlog("agents: com.jeb.desktop.update is a dev-mode agent; removing it")
        _ = launchctlRun(["bootout", "\(guiDomain)/com.jeb.desktop.update"])
        unlink(strayPath)
    }
}

// ---- follow ----

func updatesPaused() -> Bool { FileManager.default.fileExists(atPath: stateHome + "/updates-paused") }

func cmdFollow(_ args: [String]) -> Int32 {
    let gatesOnly = args.contains("--gates-only"), quick = args.contains("--quick")
    if !updatesPaused() { migrateHome() }      // before the lock below: migrate takes release.lock itself
    makePrivateDir(stateHome)
    let lock = open(stateHome + "/release.lock", O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if lock >= 0 { _ = fcntl(lock, F_SETFD, FD_CLOEXEC) }
    if lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0 {
        say("another follow is running")
        return 0
    }
    updateStatus.source = "release"
    updateStatus.final = false
    if unlink(stateHome + "/check-now") == 0 { updateStatus.clicked = true }      // the menu's click; nothing to skip here
    func S(_ phase: String, _ detail: String = "", _ result: String? = nil) {
        if !dryRun { updateStatus.status(phase, phase == "done" ? String(detail.prefix(160)) : detail, result: result) }
    }
    S("checking")
    return followBundle(gatesOnly: gatesOnly, quick: quick, S)
}

/// follow for a release bundle: the newest published tag newer than the installed one, downloaded, signature-checked, gated, then
/// `current` flipped before the swap. Every return writes the final status.
func followBundle(gatesOnly: Bool, quick: Bool, _ S: (String, String, String?) -> Void) -> Int32 {
    func stop(_ why: String, _ result: String = "error") { S("done", why, result) }
    pruneVersions()      // the folder a previous run went on from
    if installMode() != "release" { rlog("follow: not in release mode; nothing to do"); stop("not in release mode"); return 0 }
    if updatesPaused() { rlog("follow: updates are paused; skipping"); stop("updates are paused"); return 0 }
    if !FileManager.default.fileExists(atPath: pinnedSignersPath) {
        rlog("follow: no pinned release signers (\(pinnedSignersPath)); not updating"); stop("no pinned release signers"); return 0
    }
    var rs = loadRState()
    guard let cur = installedTag(), let curKey = tagKey(cur) else {
        rlog("follow: cannot tell which release is installed; skipping"); stop("cannot tell the installed release"); return 0
    }
    if !(rs["bridge_reset"]?.truthy ?? false) {
        // v1.4.0 marked a newer tag failed for good when it only passed through (it could not read the new signers); a tag with no
        // recorded reason that is newer than the installed one gets another look, once
        let whyKeys = (rs["failed_why"]?.object ?? []).map { $0.0 }
        let failed = failedList(rs)
        let lost = failed.filter { t in !whyKeys.contains(t) && (tagKey(t).map { $0 > curKey } ?? false) }
        if !lost.isEmpty { rs.set("failed", .array(failed.filter { !lost.contains($0) }.map(Json.string))) }
        if !lost.isEmpty { rlog("follow: giving \(lost.joined(separator: ", ")) another look (rejected without a recorded reason)") }
        rs.set("bridge_reset", .int(1))
        try? saveRState(rs)
    }
    if adoptSigners(&rs, tag: cur, src: currentDir() + "/desktop/release-signers") { try? saveRState(rs) }
    healPlists()
    S("checking GitHub", "", nil)
    let new: [String]
    do { new = try newTags(cur: cur, skip: failedSkip(rs)) } catch {
        rlog("follow: \(error); will try again later"); stop("could not reach GitHub; will retry"); return 0
    }
    rs.set("checked", .int(Clock.epoch))
    try? saveRState(rs)
    if new.isEmpty {
        rlog("follow: \(cur) is current"); ensurePlugin(); stop("\(cur) is current", "up-to-date"); return 0
    }
    if dryRun {
        say("would download \(new[0]) (\(releaseBase(releaseRepo()))), verify its signed manifest, run the gates, point \(currentDir()) at it, then remove \(cur)")
        return 0
    }
    var tag: String?, ver: String?
    for t in new {      // newest first: a bogus far-future tag cannot block the real releases
        S("downloading \(t)", "", nil)
        let (path, err) = fetchBundle(t, log: rlog)
        guard let e = err else { tag = t; ver = path; break }
        if !e.permanent {
            rlog("follow: could not get \(t): \(e.why); will try again later")
            stop("app download failed; will retry")
            return 0
        }
        rlog("follow: \(t) rejected (\(e.kind ?? "content")): \(e.why); " + (e.kind == "signature" ? "it is retried when the pinned signers change" : "it will not be retried"))
        markFailed(&rs, t, kind: e.kind ?? "content")
        try? saveRState(rs)
    }
    guard let tag = tag, let ver = ver else {
        rlog("follow: no verified release newer than \(cur)"); stop("no verified release newer than \(cur)", "up-to-date"); return 0
    }
    let startedAt = Clock.epoch
    let rc = runUpdate(ver, extra: (gatesOnly ? ["--gates-only"] : []) + (quick ? ["--quick"] : []))
    if gatesOnly || rc != 0 { undoFlip(nil, ver) }
    var result = [0: "ok", 2: "rejected", 3: "rolled-back"][Int(rc)] ?? "error"
    if gatesOnly {
        result = "gates-" + result
    } else if rc == 2 || rc == 3 {
        markFailed(&rs, tag, kind: rc == 2 ? "gates" : "rolled-back")
        rlog("follow: \(tag) \(result); it will not be retried")
    } else if rc == 0 {
        rlog("follow: now on \(tag)")
        clearFailed(&rs, tag)
        recordInstalled(&rs, tag)
        rs.set("layout", .string("bundle"))
        adoptSigners(&rs, tag: tag, src: ver + "/desktop/release-signers")      // verified against the old pin and installed: its signers take over
        ensurePlugin()
    } else {
        rlog("follow: \(tag) not installed (updater exit \(rc)); will try again later")
    }
    rs.set("last", .object([("at", .int(Clock.epoch)), ("tag", .string(tag)), ("result", .string(result)), ("app", .string("prebuilt"))]))
    try? saveRState(rs)
    let last = loadUState()["last"]
    let why = (last?["at"]?.int ?? 0) >= (updateStatus.startedAt ?? startedAt) ? last?["why"]?.string : nil      // the updater's reason, if this run recorded one
    if gatesOnly {
        stop("\(tag): gates \(rc == 0 ? "passed" : "failed"); nothing installed", rc == 0 ? "up-to-date" : "failed")
    } else if rc == 0 {
        stop("updated to \(tag)", "updated")
    } else {
        stop("\(tag): \(why ?? "see update.log")", [2: "failed", 3: "rolled-back"][Int(rc)] ?? "error")
    }
    if rc == 0 && !gatesOnly { pruneNow() }
    let staging = stateHome + "/staging"
    for d in (try? FileManager.default.contentsOfDirectory(atPath: staging)) ?? [] { try? FileManager.default.removeItem(atPath: staging + "/" + d) }
    return [0, 2, 3].contains(rc) ? 0 : 1
}

// ---- rollback ----

/// The release to go back to: the last one recorded as installed that is not the current one and not failed.
func rollbackTarget(_ rs: Json, current cur: String?) -> String? {
    let failed = failedList(rs)
    for e in (rs["installed"]?.array ?? []).reversed() {
        if let t = e["tag"]?.string, t != cur, !failed.contains(t) { return t }
    }
    return nil
}

/// Put the previous good release back: it is downloaded again (only one version is kept on disk), gated, and flipped to; the bad
/// one is deleted. When the download fails nothing changes.
func rollbackBundle() {
    var rs = loadRState()
    let cur = installedTag()
    guard let prev = rollbackTarget(rs, current: cur) else { die("no earlier release is recorded to roll back to") }
    if let k = tagKey(prev), k < rollbackFloor {
        die("\(prev) is older than v\(rollbackFloor.0).\(rollbackFloor.1).\(rollbackFloor.2), the oldest release this one can roll back to (older ones predate the key rotation and the Python-free update path); \(cur ?? "None") stays installed.")
    }
    if dryRun {
        say("would roll back \(cur ?? "None") -> \(prev): download \(prev) again, gate it and point \(currentDir()) at it (dry run: nothing changed)")
        return
    }
    makePrivateDir(stateHome)
    let lock = open(stateHome + "/release.lock", O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if lock >= 0 { _ = fcntl(lock, F_SETFD, FD_CLOEXEC) }
    if lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0 { die("an update is running; try again in a few minutes") }
    say("rolling back \(cur ?? "None") -> \(prev): downloading \(prev) again")
    let (path, err) = fetchBundle(prev, log: say)
    guard let ver = path else {
        die("could not download \(prev): \(err?.why ?? "")\nNothing was changed; \(cur ?? "None") is still installed.")
    }
    updateStatus.source = "release"
    let rc = runUpdate(ver, extra: [])
    if rc != 0 {
        undoFlip(nil, ver)
        die("\(prev) failed (updater exit \(rc)); \(cur ?? "None") is still installed. See \(updateLogPath)")
    }
    if let c = cur { markFailed(&rs, c, kind: "rolled-back") }
    recordInstalled(&rs, prev)
    rs.set("last", .object([("at", .int(Clock.epoch)), ("tag", .string(prev)), ("result", .string("rolled-back-manually")), ("app", .string("prebuilt"))]))
    do { try saveRState(rs) } catch { die("could not save \(releaseStatePath): \(error)") }
    pruneNow()
    say("rolled back \(cur ?? "None") -> \(prev); the running app hands over within a few seconds")
}

// ---- update / retry-update ----

let updateWait = 30.0 * 60, updatePoll = 2.0      // seconds: how long `update` waits for the final result, and how often it looks

/// Poll update-status.json for a run that started at t0, printing each distinct phase line, until its final line (0 for updated
/// or up-to-date, else 1) or the deadline (1).
func waitForUpdate(since t0: Int, wait: Double = updateWait, poll: Double = updatePoll) -> Int32 {
    var seen: [String?]?
    let deadline = Clock.now + wait
    while Clock.now < deadline {
        let d = Json.load(updateStatusPath) ?? .object([])
        if (d["at"]?.int ?? 0) >= t0 {
            if d["phase"]?.string == "done" {
                let res = d["result"]?.string, why = d["detail"]?.string ?? ""
                say(why.isEmpty ? (res ?? "None") : why)
                return res == "updated" || res == "up-to-date" ? 0 : 1
            }
            let key: [String?] = [d["phase"]?.string, d["detail"]?.string, d["step"]?.int.map(String.init)]
            if seen == nil || seen! != key, let phase = d["phase"]?.string, !phase.isEmpty {
                seen = key
                var n = ""
                if let s = d["step"]?.int, let ss = d["steps"]?.int, s != 0, ss != 0 { n = " (\(s)/\(ss))" }
                let detail = d["detail"]?.string ?? ""
                say(phase + n + (detail.isEmpty ? "" : ": \(detail)"))
            }
        }
        Clock.sleep(poll)
    }
    say("still running; see jebctl status")
    return 1
}

/// Check for a release now and wait for the result; the release agent does the work in its own environment.
func cmdUpdate() -> Int32 {
    if installMode() != "release" {
        say(dryRun ? "a development install ships from the working tree; would run the updater now" : "a development install ships from the working tree; the dev updater is gone from this jebctl (install a release)")
        return dryRun ? 0 : 1
    }
    if updatesPaused() { say("updates are paused; run: jebctl resume-updates"); return 1 }
    if dryRun {
        say("would start the release agent (launchctl kickstart com.jeb.desktop.release) and wait up to 30 minutes for its result")
        return 0
    }
    let t0 = Clock.epoch
    makePrivateDir(stateHome)
    let click = stateHome + "/check-now"
    FileManager.default.createFile(atPath: click, contents: Data())      // the menu's click: the agent skips the quiet wait for it
    if launchctlRun(["kickstart", "\(guiDomain)/com.jeb.desktop.release"]).status != 0 {
        unlink(click)
        say("the release agent is not loaded; run the install again (or ask Claude to repair Jeb)")
        return 1
    }
    say("checking for a new release")
    return waitForUpdate(since: t0)
}

/// Re-run the last bundle update: the newest failed tag is cleared, then the release agent is restarted so it looks again.
func cmdRetryUpdate() -> Int32 {
    var rs = loadRState()
    if dryRun {
        say("would clear the newest failed release and restart the release agent (launchctl kickstart -k com.jeb.desktop.release)")
        return 0
    }
    let failed = failedList(rs)
    if let newest = failed.max(by: { (tagKey($0) ?? (0, 0, 0)) < (tagKey($1) ?? (0, 0, 0)) }) {
        clearFailed(&rs, newest)
        do { try saveRState(rs) } catch { die("could not save \(releaseStatePath): \(error)") }
    }
    let r = launchctlRun(["kickstart", "-k", "\(guiDomain)/com.jeb.desktop.release"])
    if !r.text.isEmpty { say(r.text) }
    return r.status
}
