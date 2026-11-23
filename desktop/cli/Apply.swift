// Apply: `jebctl apply <bundle> [flags]`, the gate-and-swap child that follow and install spawn. Ported from
// desktop/updater.py (main/update, install_bundle, restore_bundle, swap_dirs, watch_new_build, beats) for a schema 2
// (Python-free) bundle, under the contract in the run_apply docstring of desktop/jebctl and Follow.swift's runApply.
//
// Two wire forms:
//   follow   <ver>/desktop/bin/jebctl apply <ver> --not-final --lock-held [--no-watch] [--gates-only] [--quick]
//   install  <ver>/desktop/bin/jebctl apply <bundle> --lock-held --no-watch
// With --not-final the parent writes the final status line from the exit code and apply writes phase lines only; without
// it (install) apply writes the final line itself ("done"). The phase lines carry source "release" in both forms.
//
// Exit codes: 0 installed (and healthy, unless --no-watch), 2 rejected by a gate (never retried), 3 rolled back after the
// swap (never retried), anything else an error that is retried later: 1 for every error, a usage error included (exit 2 is
// reserved for gate rejection, so a mistyped flag must not read as one; the dev jebctl's --probe usage exits 1 too).
//
// What it does, in order: the bundle's app is checked and gated (smoke, headless start: Gates.swift; parity and the day ran
// at release time, so --quick changes nothing); --gates-only stops there and touches nothing. Then JebDesktop.app is built
// from the bundle's binary (Info.plist, icon, ad-hoc codesign: src/tools/bundle.sh), `current` is pointed at the bundle just
// before the app is installed (renamex_np swap, the old app kept in JEB_HOME/versions/<stamp>.app), and the new build is
// watched unless --no-watch. On ANY failure after that, `current` and the previous app are put back here. It never deletes
// the bundle, never prunes, never touches release-state.json, never reloads LaunchAgents and never takes release.lock when
// --lock-held says the parent holds it. On success ~/.jeb/bin/jebctl (a standalone jebctl) is refreshed from the bundle's.
//
// Test hooks (honoured only when set): JEB_TEST_FAIL_GATE=smoke|start and JEB_TEST_START_SECS (Gates.swift); JEB_TEST_NO_BEAT=1
// makes the watch see no heartbeat at all; JEB_APPLY_WATCH_SECS=<n> (or --watch-secs n) shortens the 600 s watch window.
import Foundation

let applyHelp = #"""
jebctl apply: gate a release bundle's app and swap it in (what follow and install run; not for everyday use).

  apply <bundle> [--not-final] [--lock-held] [--no-watch] [--gates-only] [--quick] [--watch-secs N]

  <bundle>        an unpacked, verified schema 2 bundle folder (~/.jeb/versions/<tag>)
  --not-final     write the phase lines of update-status.json only; the caller writes the final one
  --lock-held     the caller holds release.lock: do not take it
  --no-watch      do not watch the new build after the swap
  --gates-only    run the gates and stop: nothing is installed, `current` and the app stay as they are
  --quick         accepted and a no-op (parity and the day are release-time gates)
  --watch-secs N  the watch window in seconds (default 600; JEB_APPLY_WATCH_SECS sets it too)

The app is gated with a smoke render of every fixture and 20 s headless. `current` is pointed at the bundle just before the
app is installed. On any failure `current` and the previous app are put back.
Exit: 0 installed, 2 rejected by a gate, 3 rolled back after the swap, 1 any other error (usage included).
"""#

// ---- the command line ----

struct ApplyOptions: Equatable {
    var bundle: String
    var notFinal = false
    var lockHeld = false
    var noWatch = false
    var gatesOnly = false
    var quick = false
    var watchSecs = 600
}

enum ApplyParse: Equatable {
    case run(ApplyOptions)
    case help
    case usage(String)
}

let applyUsage = "usage: jebctl apply <bundle> [--not-final] [--lock-held] [--no-watch] [--gates-only] [--quick] [--watch-secs N]"

/// Both wire forms, nothing else: one bundle path and the six flags. --watch-secs falls back to JEB_APPLY_WATCH_SECS, then 600.
func parseApply(_ args: [String]) -> ApplyParse {
    var o = ApplyOptions(bundle: "")
    if let s = envVar("JEB_APPLY_WATCH_SECS").flatMap(Int.init), s >= 0 { o.watchSecs = s }
    var path: String?
    var i = 0
    while i < args.count {
        let a = args[i]
        i += 1
        switch a {
        case "-h", "--help": return .help
        case "--not-final": o.notFinal = true
        case "--lock-held": o.lockHeld = true
        case "--no-watch": o.noWatch = true
        case "--gates-only": o.gatesOnly = true
        case "--quick": o.quick = true
        case "--watch-secs":
            guard i < args.count, let n = Int(args[i]), n >= 0 else { return .usage("jebctl apply: --watch-secs needs a number of seconds\n" + applyUsage) }
            o.watchSecs = n
            i += 1
        default:
            if a.hasPrefix("-") { return .usage("jebctl apply: unknown option \(a)\n" + applyUsage) }
            if path != nil { return .usage("jebctl apply: one bundle only (got \(path!) and \(a))\n" + applyUsage) }
            path = a
        }
    }
    guard let p = path else { return .usage("jebctl apply: a bundle folder is required\n" + applyUsage) }
    o.bundle = p.hasPrefix("/") ? p : FileManager.default.currentDirectoryPath + "/" + p
    return .run(o)
}

// ---- the app: build, install, restore ----

/// Atomically exchange two directories (APFS renamex_np with RENAME_SWAP).
func swapDirs(_ a: String, _ b: String) throws {
    if renamex_np(a, b, 2) != 0 { throw posixError("swap \(a) <->", b) }
}

/// The Info.plist of bundle.sh: stamp is CFBundleVersion, mod the folder the app reads its art from (JebMod; omitted when
/// empty), icon whether Resources/Jeb.icns exists. Values are XML-escaped.
func infoPlist(stamp: String, mod: String, icon: Bool) -> String {
    func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key><string>com.jeb.desktop</string>
      <key>CFBundleName</key><string>JebDesktop</string>
      <key>CFBundleExecutable</key><string>JebDesktop</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleVersion</key><string>\(esc(stamp))</string>
      <key>CFBundleShortVersionString</key><string>\(esc(stamp))</string>
      <key>LSUIElement</key><true/>
      <key>LSMinimumSystemVersion</key><string>12.0</string>
      <key>NSAppSleepDisabled</key><true/>
      \(icon ? "<key>CFBundleIconFile</key><string>Jeb</string>" : "")
      \(mod.isEmpty ? "" : "<key>JebMod</key><string>\(esc(mod))</string>")
    </dict>
    </plist>

    """
}

/// bundle.sh with a prebuilt binary: <out>/Contents/{MacOS/JebDesktop, Resources/Jeb.icns, Info.plist}, ad-hoc signed and
/// verified. The icon is made by the binary itself (JEB_ICONSET, then iconutil) and only warns when it cannot be. artMod is
/// where the art is now (the bundle's mod), jebMod what the app should remember (`current`'s mod, which outlives the bundle's
/// folder). Returns nil, or the reason the bundle could not be built.
func buildApp(binary: String, out: String, stamp: String, artMod: String, jebMod: String, scratch: String) -> String? {
    let fm = FileManager.default
    try? fm.removeItem(atPath: out)
    let exe = out + "/Contents/MacOS/JebDesktop"
    do {
        try fm.createDirectory(atPath: out + "/Contents/MacOS", withIntermediateDirectories: true)
        try fm.copyItem(atPath: binary, toPath: exe)
    } catch { return "cannot copy the app binary: \(error.localizedDescription)" }
    chmod(exe, 0o755)
    let iconTmp = scratch + "/icon"
    try? fm.createDirectory(atPath: iconTmp, withIntermediateDirectories: true)
    var icon = false
    let r = gateRun([exe], cwd: iconTmp, env: gateEnv(mod: artMod, scratch: scratch + "/icon-env", extra: ["JEB_ICONSET": iconTmp + "/Jeb.iconset"]), timeout: 60)
    if r.status == 0, (try? fm.createDirectory(atPath: out + "/Contents/Resources", withIntermediateDirectories: true)) != nil,
       run(["/usr/bin/iconutil", "-c", "icns", iconTmp + "/Jeb.iconset", "-o", out + "/Contents/Resources/Jeb.icns"]).status == 0 {
        icon = true
    } else {
        warn("apply: warning: no app icon (\(gateTail(r.err, 1)))")
        try? fm.removeItem(atPath: out + "/Contents/Resources/Jeb.icns")
    }
    do { try Data(infoPlist(stamp: stamp, mod: jebMod, icon: icon).utf8).write(to: URL(fileURLWithPath: out + "/Contents/Info.plist")) }
    catch { return "cannot write Info.plist: \(error.localizedDescription)" }
    let sign = run(["/usr/bin/codesign", "--force", "-s", "-", out])
    if sign.status != 0 { return gateTail(sign.text) }
    let check = run(["/usr/bin/codesign", "--verify", out])
    return check.status == 0 ? nil : gateTail(check.text)
}

/// install_bundle: newApp goes to appDir/JebDesktop.app and the old one to versions/<its stamp>.app (one spare kept: a
/// release bundle keeps one version on disk). Returns the old stamp, or nil when there was no app.
func installApp(_ newApp: String, appDir: String, versionsDir: String, keep: Int = 1) throws -> String? {
    let fm = FileManager.default
    try fm.createDirectory(atPath: appDir, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: versionsDir, withIntermediateDirectories: true)
    let cur = appDir + "/JebDesktop.app", stage = appDir + "/.JebDesktop.staging"
    try? fm.removeItem(atPath: stage)
    let d = run(["/usr/bin/ditto", newApp, stage])
    if d.status != 0 { throw FlipError(description: "ditto: " + gateTail(d.text, 1)) }
    var old: String?
    if isDir(cur) {
        let s = bundleStamp(cur) ?? "unknown-" + Clock.strftime("%Y%m%d-%H%M%S")
        try swapDirs(stage, cur)                       // cur is the new build now, stage the old
        let dest = versionsDir + "/" + s + ".app"
        try? fm.removeItem(atPath: dest)
        try fm.moveItem(atPath: stage, toPath: dest)
        old = s
    } else {
        try fm.moveItem(atPath: stage, toPath: cur)
    }
    let olds = ((try? fm.contentsOfDirectory(atPath: versionsDir)) ?? []).filter { $0.hasSuffix(".app") }.sorted(by: >)
    for n in olds.dropFirst(keep) { try? fm.removeItem(atPath: versionsDir + "/" + n) }
    return old
}

/// restore_bundle: versions/<oldStamp>.app goes back to appDir/JebDesktop.app; the bad build is deleted.
func restoreApp(oldStamp: String, appDir: String, versionsDir: String) throws {
    let fm = FileManager.default
    let cur = appDir + "/JebDesktop.app", old = versionsDir + "/" + oldStamp + ".app", stage = appDir + "/.JebDesktop.staging"
    try? fm.removeItem(atPath: stage)
    try fm.moveItem(atPath: old, toPath: stage)
    try swapDirs(stage, cur)
    try? fm.removeItem(atPath: stage)
}

/// `current` back to where it was, or removed when there was no link before.
func restoreCurrent(_ prev: String?) {
    let cur = currentDir()
    if let p = prev {
        do { _ = try flipCurrent(p) } catch { ulog("apply: COULD NOT point \(cur) back at \(p): \(error)") }
    } else {
        unlink(cur + ".new")
        unlink(cur)
    }
}

// ---- the watch ----

let applyHealthySecs = 180.0, applyNoBeatSecs = 240.0, applyStaleSecs = 10.0      // updater.py's HEALTHY_SECS, NO_BEAT_SECS, STALE

/// watch_new_build: nil when the new build is healthy, else the reason to roll back. offset is run.log's size before the
/// swap (only what the new build wrote is read). beats is injectable; JEB_TEST_NO_BEAT=1 makes it see none.
func watchNewBuild(stamp: String, secs: Int, offset: Int, poll: Double = 2,
                   beats: () -> [Int32: Beat] = { beatFiles() }) -> String? {
    let t0 = Clock.now
    var seen = false
    var healthySince: Double?
    let runlog = stateHome + "/run.log"
    while Clock.now - t0 < Double(secs) {
        Clock.sleep(poll)
        if let f = FileHandle(forReadingAtPath: runlog) {
            f.seek(toFileOffset: UInt64(offset))
            let text = String(decoding: f.readDataToEndOfFile(), as: UTF8.self)
            f.closeFile()
            if reFindAll(#"new binary \(pid \d+\) exited with (-?\d+)"#, text).contains(where: { $0[1] != "0" }) {
                return "the new binary exited non-zero (run.log)"
            }
        }
        let mine = envVar("JEB_TEST_NO_BEAT") == "1" ? [] : beats().filter { $0.value.stamp == stamp }.sorted { $0.key < $1.key }
        if !mine.isEmpty { seen = true }
        func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno != ESRCH }
        if let dead = mine.first(where: { !alive($0.key) }) { return "pid \(dead.key) of the new build died without a clean exit" }
        if let stale = mine.first(where: { $0.value.age > applyStaleSecs }) {
            return "heartbeat of pid \(stale.key) stale \(Int(stale.value.age.rounded())) s"
        }
        if !mine.isEmpty && !mine.contains(where: { $0.value.waiting }) {
            healthySince = healthySince ?? Clock.now
            if Clock.now - healthySince! >= applyHealthySecs { return nil }
        } else {
            healthySince = nil
        }
        if !seen && Clock.now - t0 > applyNoBeatSecs { return "no heartbeat from the new build after \(Int(applyNoBeatSecs)) s" }
    }
    return seen ? nil : "no heartbeat from the new build"
}

// ---- the run ----

/// What applyRun asks of the outside world; the defaults are the real gates, build and watch, tests substitute their own.
struct ApplyHooks {
    /// A reason the bundle's app cannot be gated at all (missing or wrong-arch files), or nil.
    var check: (_ appFolder: String) -> String? = bundleAppProblem
    var smoke: (_ binary: String, _ bundle: String, _ scratch: String) -> GateResult = { bin, ver, scratch in
        gateSmoke(binary: bin, fixtures: ver + "/desktop/src/fixtures", mod: ver + "/mod", scratch: scratch)
    }
    var start: (_ binary: String, _ bundle: String, _ scratch: String) -> GateResult = { bin, ver, scratch in
        gateStart(binary: bin, mod: ver + "/mod", liveStore: storePath(), scratch: scratch)
    }
    /// Builds the .app at `out`; the reason it could not be, or nil.
    var build: (_ binary: String, _ out: String, _ stamp: String, _ bundle: String, _ scratch: String) -> String? = { bin, out, stamp, ver, scratch in
        buildApp(binary: bin, out: out, stamp: stamp, artMod: ver + "/mod", jebMod: liveMod, scratch: scratch)
    }
    var watch: (_ stamp: String, _ secs: Int, _ offset: Int) -> String? = { stamp, secs, offset in watchNewBuild(stamp: stamp, secs: secs, offset: offset) }
    /// Refreshes the standalone jebctl after a successful apply.
    var refresh: (_ from: String) -> Void = { refreshStandalone(from: $0) }

    static let real = ApplyHooks()
}

/// The build stamp of an applied bundle (CFBundleVersion): UTC time, then the bundle's commit (or its folder name).
func applyStamp(_ ver: String, bundle: Json?) -> String {
    let id = bundle?["commit"]?.string.map { String($0.prefix(8)) } ?? (ver as NSString).lastPathComponent
    var secs = time_t(Clock.now.rounded(.down))
    var t = tm()
    gmtime_r(&secs, &t)
    var buf = [CChar](repeating: 0, count: 32)
    let n = Foundation.strftime(&buf, buf.count, "%Y%m%d-%H%M%S", &t)
    return String(cString: Array(buf[0..<n]) + [0]) + "-" + id
}

/// updater.py's main()+update() for a schema 2 bundle. Returns the exit code (see the file comment).
func applyRun(_ o: ApplyOptions, hooks: ApplyHooks = .real) -> Int32 {
    let fm = FileManager.default
    updateStatus.source = "release"
    updateStatus.final = !o.notFinal
    let ver = o.bundle
    guard let meta = readBundle(ver), meta["schema"]?.int == 2 else {
        let why = "\(ver) is not an unpacked schema 2 bundle"
        warn("jebctl apply: " + why)
        ulog("apply: " + why)
        updateStatus.finish("error", why)
        return 1
    }
    makePrivateDir(stateHome)
    var lockFd: Int32 = -1
    if !o.lockHeld {
        lockFd = open(stateHome + "/release.lock", O_WRONLY | O_CREAT, 0o644)
        if lockFd >= 0 { _ = fcntl(lockFd, F_SETFD, FD_CLOEXEC) }
        if lockFd < 0 || flock(lockFd, LOCK_EX | LOCK_NB) != 0 { say("an update is running; try again in a few minutes"); return 1 }
    }
    defer { if lockFd >= 0 { close(lockFd) } }

    let stamp = applyStamp(ver, bundle: meta)
    let hash = meta["commit"]?.string ?? (ver as NSString).lastPathComponent
    let scratch = stateHome + "/build/" + stamp
    try? fm.removeItem(atPath: scratch)
    makePrivateDir(scratch)
    defer { try? fm.removeItem(atPath: scratch) }
    let steps = 1 + 2 + (o.gatesOnly ? 0 : 1 + (o.noWatch ? 0 : 1))       // the check, two gates, swap, watch
    var st = loadUState()
    ulog("apply \(stamp): bundle \((ver as NSString).lastPathComponent)")
    updateStatus.status("using the prebuilt binary", step: 1, steps: steps)

    func reject(_ gate: String, _ why: String) -> Int32 {
        ulog("apply \(stamp): REJECTED at \(gate): \(why)")
        say("rejected at \(gate): \(why)")
        var rej = st["rejected"]?.array ?? []
        rej.append(.string(hash))
        st.set("rejected", .array(Array(rej.suffix(50))))
        try? recordUState(&st, result: "rejected", why: "\(gate): \(why)", stamp: stamp, hash: hash)
        updateStatus.finish("failed", "\(gate): \(why)")
        return 2
    }
    func fail(_ log: String, result: String, why: String) -> Int32 {
        ulog("apply \(stamp): \(log)")
        say(log)
        try? recordUState(&st, result: result, why: why, stamp: stamp, hash: hash)
        updateStatus.finish("error", log)
        return 1
    }

    if let why = hooks.check(ver + "/app") { return reject("app", why) }
    let binary = ver + "/app/JebDesktop"
    let gates: [(String, () -> GateResult)] = [("smoke", { hooks.smoke(binary, ver, scratch + "/smoke") }),
                                               ("start", { hooks.start(binary, ver, scratch + "/start") })]
    for (i, g) in gates.enumerated() {
        updateStatus.status("gate " + g.0, step: 2 + i, steps: steps)
        let t = Clock.now
        let r = g.1()
        ulog("apply \(stamp): gate \(g.0) \(r.ok ? "ok" : "FAILED") (\(Int(Clock.now - t)) s): \(r.why)")
        if !r.ok { return reject(g.0, r.why) }
    }
    ulog("apply \(stamp): gate parity skipped (release time)")
    ulog("apply \(stamp): gate day skipped (release time)")

    if o.gatesOnly {
        ulog("apply \(stamp): gates passed (gates-only: nothing installed)")
        updateStatus.finish("up-to-date", "gates passed; nothing installed")
        return 0
    }
    updateStatus.status("swapping", step: steps - (o.noWatch ? 0 : 1), steps: steps)
    let newApp = scratch + "/JebDesktop.app"
    if let why = hooks.build(binary, newApp, stamp, ver, scratch) { return reject("bundle", why) }

    // `current` moves just before the app does; from here every failure puts both back
    let prev: String?
    do { prev = try flipCurrent(ver) } catch {
        return fail("before-swap step failed, current app kept: could not switch \(currentDir()): \(error)", result: "before-swap-failed", why: "\(error)")
    }
    ulog("apply \(stamp): \(currentDir()) now points at \((ver as NSString).lastPathComponent)")
    let runlogSize = (try? fm.attributesOfItem(atPath: stateHome + "/run.log")[.size] as? Int) ?? 0
    let apps = appDir(), vers = appVersionsPath
    let hadApp = isDir(apps + "/JebDesktop.app")
    let oldStamp: String?
    do { oldStamp = try installApp(newApp, appDir: apps, versionsDir: vers) } catch {
        restoreCurrent(prev)
        return fail("swap failed, current app kept: \(error)", result: "swap-failed", why: "\(error)")
    }
    st.set("built", .string(hash)); st.set("stamp", .string(stamp))
    ulog("apply \(stamp): swapped in (previous \(oldStamp ?? "None"))")
    try? recordUState(&st, result: "swapped", why: "previous \(oldStamp ?? "None")", stamp: stamp, hash: hash)

    if !o.noWatch {
        updateStatus.status("watching the new build", step: steps, steps: steps)
        if let why = hooks.watch(stamp, o.watchSecs, runlogSize) {
            ulog("apply \(stamp): ROLLBACK: \(why)")
            say("rolling back: \(why)")
            var restored = true
            if let old = oldStamp, isDir(vers + "/" + old + ".app") {
                do { try restoreApp(oldStamp: old, appDir: apps, versionsDir: vers) } catch {
                    restored = false
                    ulog("apply \(stamp): rollback failed: \(error)")
                    try? recordUState(&st, result: "rollback-failed", why: "\(error)", stamp: stamp, hash: hash)
                }
            } else if !hadApp {
                try? fm.removeItem(atPath: apps + "/JebDesktop.app")      // there was no app before: the bad one goes
            }
            restoreCurrent(prev)
            if !restored { updateStatus.finish("error", "rollback failed"); return 1 }
            var rej = st["rejected"]?.array ?? []
            rej.append(.string(hash))
            st.set("rejected", .array(Array(rej.suffix(50))))
            st.set("built", .null); st.set("stamp", oldStamp.map(Json.string) ?? .null)
            try? recordUState(&st, result: "rolled-back", why: why, stamp: stamp, hash: hash)
            updateStatus.finish("rolled-back", why)
            return 3
        }
        ulog("apply \(stamp): healthy")
        try? recordUState(&st, result: "ok", why: "healthy", stamp: stamp, hash: hash)
    } else {
        try? recordUState(&st, result: "ok", why: "installed", stamp: stamp, hash: hash)
    }
    hooks.refresh(ver + "/desktop/bin/jebctl")
    updateStatus.finish("updated", "updated to \(stamp)")
    say("applied \((ver as NSString).lastPathComponent) (\(stamp))")
    return 0
}

/// `jebctl apply ...`
func cmdApply(_ args: [String]) -> Int32 {
    switch parseApply(args) {
    case .help:
        say(applyHelp)
        return 0
    case let .usage(msg):
        warn(msg)
        return 1
    case let .run(o):
        return applyRun(o)
    }
}
