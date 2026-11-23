// ApplyTests: `jebctl apply` (Apply.swift) with the gates, the app build and the watch swapped for stand-ins, so the whole
// run goes through its real argv parsing, status lines, `current` flips, renamex_np app swaps and restores in a scratch
// HOME. Seam: return values and the files left in the scratch folders (update-status.json, updater-state.json, the app
// folder, the `current` link). The real gates and app run in tests/apply-e2e.sh, not here.
import Foundation

func applyTests(_ t: Tester) {
    let fm = FileManager.default

    /// A scratch world: HOME with ~/.jeb/versions/{v1,v2}, `current` -> v1, an installed app stamped "old-stamp", the state
    /// folder under it. body gets the home folder; every global it changes is put back.
    func world(_ name: String, currentLink: Bool = true, installedApp: Bool = true, _ body: (String) throws -> Void) throws {
        let home = t.scratch(name)
        let names = ["HOME", "JEB_HOME", "JEB_APP_DIR", "JEB_TOOLS_DIR", "JEB_TEST_NO_BEAT", "JEB_APPLY_WATCH_SECS"]
        let was = names.map { envVar($0) }, oldHome = stateHome, loud = verbose, dry = dryRun
        for (k, v) in zip(names, [home, home + "/state", home + "/apps", home + "/.jeb/bin", nil, nil]) { setEnvVar(k, v) }
        setHome(home + "/state")
        verbose = false
        dryRun = false
        defer {
            for (k, v) in zip(names, was) { setEnvVar(k, v) }
            setHome(oldHome)
            verbose = loud
            dryRun = dry
        }
        for v in ["v1", "v2"] {
            writeFile(home + "/.jeb/versions/\(v)/bundle.json", #"{"schema": 2, "repo": "x/y", "tag": "\#(v)", "version": "1", "commit": "\#(v)abcdef0123456789", "arch": "arm64"}"#)
            writeFile(home + "/.jeb/versions/\(v)/desktop/bin/jebctl", "#!/bin/sh\n", mode: 0o755)
        }
        if currentLink { try? fm.createSymbolicLink(atPath: home + "/.jeb/current", withDestinationPath: "versions/v1") }
        if installedApp { writeFile(home + "/apps/JebDesktop.app/Contents/Info.plist", infoPlist(stamp: "old-stamp", mod: "", icon: false)) }
        try body(home)
    }

    /// Hooks that pass (or fail as told) and leave a fake app whose Info.plist carries the stamp; calls are recorded.
    final class Calls { var log: [String] = []; var refreshed: String? }
    func hooks(_ calls: Calls, smoke: GateResult = GateResult(ok: true, why: "fine"), start: GateResult = GateResult(ok: true, why: "fine"),
               watch: String? = nil) -> ApplyHooks {
        var h = ApplyHooks()
        h.check = { _ in nil }
        h.smoke = { _, _, _ in calls.log.append("smoke"); return smoke }
        h.start = { _, _, _ in calls.log.append("start"); return start }
        h.build = { _, out, stamp, _, _ in
            calls.log.append("build")
            writeFile(out + "/Contents/Info.plist", infoPlist(stamp: stamp, mod: "", icon: false))
            return nil
        }
        h.watch = { _, _, _ in calls.log.append("watch"); return watch }
        h.refresh = { calls.refreshed = $0 }
        return h
    }
    func options(_ home: String, _ flags: [String]) -> ApplyOptions {
        guard case let .run(o) = parseApply([home + "/.jeb/versions/v2"] + flags) else { fatalError("flags did not parse: \(flags)") }
        return o
    }
    func link(_ home: String) -> String? { try? fm.destinationOfSymbolicLink(atPath: home + "/.jeb/current") }
    func appStamp(_ home: String) -> String? { bundleStamp(home + "/apps/JebDesktop.app") }
    func status() -> Json? { Json.load(updateStatusPath) }

    t.test("parseApply: both wire forms, --watch-secs, the env override, and nothing else") {
        let follow = ["/v/v2", "--not-final", "--lock-held", "--no-watch", "--gates-only", "--quick"]
        guard case let .run(f) = parseApply(follow) else { return t.fail("follow form did not parse") }
        t.eq(f, ApplyOptions(bundle: "/v/v2", notFinal: true, lockHeld: true, noWatch: true, gatesOnly: true, quick: true, watchSecs: 600))
        guard case let .run(i) = parseApply(["/v/v2", "--lock-held", "--no-watch"]) else { return t.fail("install form did not parse") }
        t.eq(i, ApplyOptions(bundle: "/v/v2", notFinal: false, lockHeld: true, noWatch: true, gatesOnly: false, quick: false, watchSecs: 600))
        guard case let .run(w) = parseApply(["--watch-secs", "4", "/v/v2"]) else { return t.fail("--watch-secs did not parse") }
        t.eq(w.watchSecs, 4)
        setEnvVar("JEB_APPLY_WATCH_SECS", "7")
        defer { setEnvVar("JEB_APPLY_WATCH_SECS", nil) }
        guard case let .run(e) = parseApply(["/v/v2"]) else { return t.fail("env form did not parse") }
        t.eq(e.watchSecs, 7, "env override")
        guard case let .run(e2) = parseApply(["/v/v2", "--watch-secs", "3"]) else { return t.fail("flag over env did not parse") }
        t.eq(e2.watchSecs, 3, "the flag wins over the env")
        guard case let .run(rel) = parseApply(["rel/v2"]) else { return t.fail("relative bundle did not parse") }
        t.check(rel.bundle.hasPrefix("/") && rel.bundle.hasSuffix("/rel/v2"), "a relative bundle becomes absolute")
        t.eq(parseApply(["--help"]), .help)
        t.eq(parseApply(["/v/v2", "-h"]), .help)
        for bad in [["/v/v2", "--bogus"], [], ["--not-final"], ["/a", "/b"], ["/a", "--watch-secs"], ["/a", "--watch-secs", "x"], ["/a", "--watch-secs", "-1"]] {
            guard case .usage = parseApply(bad) else { t.fail("\(bad) should be a usage error"); continue }
        }
    }

    t.test("apply --gates-only: both gates run, status shows them, and nothing is touched") {
        try world("gates-only") { home in
            let calls = Calls()
            let rc = applyRun(options(home, ["--not-final", "--lock-held", "--no-watch", "--gates-only"]), hooks: hooks(calls))
            t.eq(rc, 0)
            t.eq(calls.log, ["smoke", "start"], "gates only: no build")
            t.eq(link(home), "versions/v1", "current untouched")
            t.eq(appStamp(home), "old-stamp", "app untouched")
            t.check(!fm.fileExists(atPath: home + "/state/versions"), "no saved app")
            t.eq(status()?["phase"]?.string, "gate start", "last phase line")
            t.eq(status()?["source"]?.string, "release")
            t.eq(fileMode(updateStatusPath), "0o600")
            t.eq(calls.refreshed, nil, "no refresh")
        }
    }

    t.test("apply, follow form: swaps in, never writes done, keeps the old app, refreshes jebctl") {
        try world("follow") { home in
            let calls = Calls()
            let rc = applyRun(options(home, ["--not-final", "--lock-held", "--no-watch"]), hooks: hooks(calls))
            t.eq(rc, 0)
            t.eq(calls.log, ["smoke", "start", "build"], "no watch with --no-watch")
            t.eq(link(home), "versions/v2", "current at the bundle")
            let stamp = appStamp(home)
            t.check(stamp != nil && stamp != "old-stamp" && stamp!.hasSuffix("-v2abcdef"), "new app installed (\(stamp ?? "nil"))")
            t.check(fm.fileExists(atPath: home + "/state/versions/old-stamp.app/Contents/Info.plist"), "the old app is kept")
            t.eq(status()?["phase"]?.string, "swapping")
            t.eq(status()?["result"], .null)
            t.eq(status()?["source"]?.string, "release")
            t.eq(fileMode(updateStatusPath), "0o600")
            t.eq(calls.refreshed, home + "/.jeb/versions/v2/desktop/bin/jebctl")
            t.eq(loadUState()["last"]?["result"]?.string, "ok")
            t.check(fm.fileExists(atPath: home + "/.jeb/versions/v2/bundle.json"), "the bundle stays")
            t.check(!fm.fileExists(atPath: home + "/state/build/" + (stamp ?? "")), "the scratch snapshot is gone")
        }
    }

    t.test("apply, install form: the final status line is written, and the watch phase is not") {
        try world("install") { home in
            let calls = Calls()
            let rc = applyRun(options(home, ["--lock-held", "--no-watch"]), hooks: hooks(calls))
            t.eq(rc, 0)
            t.eq(status()?["phase"]?.string, "done")
            t.eq(status()?["result"]?.string, "updated")
            t.eq(status()?["source"]?.string, "release")
            t.eq(fileMode(updateStatusPath), "0o600")
            t.eq(link(home), "versions/v2")
        }
    }

    t.test("apply with the watch: healthy keeps the swap; the window comes from the options") {
        try world("watch-ok") { home in
            let calls = Calls()
            var h = hooks(calls)
            var asked: (Int, Int)?
            h.watch = { _, secs, offset in asked = (secs, offset); return nil }
            writeFile(home + "/state/run.log", "12345")
            let rc = applyRun(options(home, ["--not-final", "--lock-held", "--watch-secs", "9"]), hooks: h)
            t.eq(rc, 0)
            t.check(asked?.0 == 9 && asked?.1 == 5, "watched 9 s from run.log offset 5 (\(String(describing: asked)))")
            t.eq(status()?["phase"]?.string, "watching the new build")
            t.eq(link(home), "versions/v2")
        }
    }

    t.test("apply, a gate rejects: exit 2, current and the app untouched, the reason recorded") {
        try world("reject") { home in
            for (which, smoke, start) in [("smoke", GateResult(ok: false, why: "f1: 2 place roots"), GateResult(ok: true, why: "")),
                                          ("start", GateResult(ok: true, why: ""), GateResult(ok: false, why: "exit 134"))] {
                let calls = Calls()
                let rc = applyRun(options(home, ["--not-final", "--lock-held", "--no-watch"]), hooks: hooks(calls, smoke: smoke, start: start))
                t.eq(rc, 2, which)
                t.eq(link(home), "versions/v1", "\(which): current untouched")
                t.eq(appStamp(home), "old-stamp", "\(which): app untouched")
                t.check(!calls.log.contains("build"), "\(which): nothing built")
                t.eq(loadUState()["last"]?["result"]?.string, "rejected", which)
                t.check(loadUState()["last"]?["why"]?.string?.hasPrefix(which + ": ") == true, "\(which): why names the gate")
                t.check(status()?["phase"]?.string != "done", "\(which): the parent writes the final line")
            }
            t.eq(loadUState()["rejected"]?.array?.count, 2)
            // the install form writes its own final line: failed
            let calls = Calls()
            t.eq(applyRun(options(home, ["--lock-held", "--no-watch"]), hooks: hooks(calls, smoke: GateResult(ok: false, why: "no"))), 2)
            t.eq(status()?["phase"]?.string, "done")
            t.eq(status()?["result"]?.string, "failed")
        }
    }

    t.test("apply, the bundle's app is unusable or cannot be built: exit 2, nothing flipped") {
        try world("badapp") { home in
            let calls = Calls()
            var h = hooks(calls)
            h.check = { _ in "detect is missing" }
            t.eq(applyRun(options(home, ["--not-final", "--lock-held", "--no-watch"]), hooks: h), 2)
            t.eq(calls.log, [], "no gate ran")
            h = hooks(calls)
            h.build = { _, _, _, _, _ in "codesign failed" }
            t.eq(applyRun(options(home, ["--not-final", "--lock-held", "--no-watch"]), hooks: h), 2)
            t.eq(link(home), "versions/v1")
            t.eq(appStamp(home), "old-stamp")
            t.eq(loadUState()["last"]?["why"]?.string, "bundle: codesign failed")
        }
    }

    t.test("apply, the watch fails: exit 3, current and the previous app are back") {
        try world("rollback") { home in
            let calls = Calls()
            let rc = applyRun(options(home, ["--not-final", "--lock-held"]), hooks: hooks(calls, watch: "no heartbeat from the new build"))
            t.eq(rc, 3)
            t.eq(link(home), "versions/v1", "current restored")
            t.eq(appStamp(home), "old-stamp", "previous app restored")
            t.check(!fm.fileExists(atPath: home + "/apps/.JebDesktop.staging"), "no staging folder left")
            t.eq(loadUState()["last"]?["result"]?.string, "rolled-back")
            t.eq(loadUState()["last"]?["why"]?.string, "no heartbeat from the new build")
            t.eq(calls.refreshed, nil, "no refresh after a rollback")
            t.check(status()?["phase"]?.string != "done", "--not-final: no done")
            t.check(fm.fileExists(atPath: home + "/.jeb/versions/v2/bundle.json"), "the bundle is not deleted")
        }
    }

    t.test("apply, the watch fails with no earlier app or link: the bad app and the link go") {
        try world("rollback-fresh", currentLink: false, installedApp: false) { home in
            let calls = Calls()
            let rc = applyRun(options(home, ["--lock-held"]), hooks: hooks(calls, watch: "pid 1 of the new build died without a clean exit"))
            t.eq(rc, 3)
            t.check(!lexists(home + "/.jeb/current"), "no current link")
            t.check(!fm.fileExists(atPath: home + "/apps/JebDesktop.app"), "no bad app left behind")
            t.eq(status()?["result"]?.string, "rolled-back", "install form: the final line says so")
        }
    }

    t.test("apply, `current` cannot be switched: exit 1 and the app stays") {
        try world("noflip", currentLink: false) { home in
            try fm.createDirectory(atPath: home + "/.jeb/current", withIntermediateDirectories: true)     // a real folder, not a link
            let calls = Calls()
            let rc = applyRun(options(home, ["--not-final", "--lock-held", "--no-watch"]), hooks: hooks(calls))
            t.eq(rc, 1)
            t.eq(appStamp(home), "old-stamp")
            t.eq(loadUState()["last"]?["result"]?.string, "before-swap-failed")
        }
    }

    t.test("apply, not a schema 2 bundle: exit 1") {
        try world("schema1") { home in
            writeFile(home + "/.jeb/versions/v2/bundle.json", #"{"schema": 1}"#)
            let calls = Calls()
            t.eq(applyRun(options(home, ["--not-final", "--lock-held"]), hooks: hooks(calls)), 1)
            t.eq(calls.log, [])
            t.eq(link(home), "versions/v1")
        }
    }

    t.test("apply without --lock-held takes release.lock, and stops when another holds it") {
        try world("lock") { home in
            makePrivateDir(home + "/state")
            let other = open(home + "/state/release.lock", O_WRONLY | O_CREAT, 0o644)
            defer { close(other) }
            t.check(flock(other, LOCK_EX | LOCK_NB) == 0, "the test holds the lock")
            let calls = Calls()
            t.eq(applyRun(options(home, ["--no-watch"]), hooks: hooks(calls)), 1, "busy")
            t.eq(calls.log, [])
            // with --lock-held it does not even look
            t.eq(applyRun(options(home, ["--lock-held", "--no-watch", "--gates-only"]), hooks: hooks(calls)), 0)
            flock(other, LOCK_UN)
            t.eq(applyRun(options(home, ["--no-watch", "--gates-only"]), hooks: hooks(calls)), 0, "free again")
        }
    }

    t.test("watchNewBuild: healthy after the quiet spell, and the four reasons to roll back") {
        try world("watch") { home in
            Clock.reload()
            func beat(_ stamp: String?, waiting: Bool = false, age: Double = 1, pid: Int32 = getpid()) -> [Int32: Beat] {
                [pid: Beat(stamp: stamp, waiting: waiting, age: age)]
            }
            t.eq(watchNewBuild(stamp: "S", secs: 600, offset: 0, beats: { beat("S") }), nil, "healthy for \(Int(applyHealthySecs)) s")
            t.eq(watchNewBuild(stamp: "S", secs: 600, offset: 0, beats: { [:] }), "no heartbeat from the new build after 240 s")
            t.eq(watchNewBuild(stamp: "S", secs: 10, offset: 0, beats: { [:] }), "no heartbeat from the new build", "short window, never seen")
            t.eq(watchNewBuild(stamp: "S", secs: 10, offset: 0, beats: { beat("OTHER") }), "no heartbeat from the new build", "another stamp's beat is not ours")
            t.eq(watchNewBuild(stamp: "S", secs: 10, offset: 0, beats: { beat("S", age: 30) }), "heartbeat of pid \(getpid()) stale 30 s")
            t.eq(watchNewBuild(stamp: "S", secs: 10, offset: 0, beats: { beat("S", pid: 2_000_000_000) }), "pid 2000000000 of the new build died without a clean exit")
            t.eq(watchNewBuild(stamp: "S", secs: 10, offset: 0, beats: { beat("S", waiting: true) }), nil, "waiting to take over: seen, never healthy, window ends")
            setEnvVar("JEB_TEST_NO_BEAT", "1")
            t.eq(watchNewBuild(stamp: "S", secs: 10, offset: 0, beats: { beat("S") }), "no heartbeat from the new build", "JEB_TEST_NO_BEAT")
            setEnvVar("JEB_TEST_NO_BEAT", nil)
            writeFile(home + "/state/run.log", "old line: new binary (pid 1) exited with 9\n")
            t.eq(watchNewBuild(stamp: "S", secs: 10, offset: 0, beats: { beat("S") }), "the new binary exited non-zero (run.log)")
            let off = (try? fm.attributesOfItem(atPath: home + "/state/run.log")[.size] as? Int) ?? 0
            t.eq(watchNewBuild(stamp: "S", secs: 600, offset: off, beats: { beat("S") }), nil, "an exit before the swap is not ours")
            let h = FileHandle(forWritingAtPath: home + "/state/run.log")!
            h.seekToEndOfFile(); h.write(Data("new binary (pid 7) exited with 0\nnew binary (pid 8) exited with -9\n".utf8)); h.closeFile()
            t.eq(watchNewBuild(stamp: "S", secs: 600, offset: off, beats: { beat("S") }), "the new binary exited non-zero (run.log)")
        }
    }

    t.test("infoPlist, swapDirs, installApp: the plist is escaped, directories swap, one spare app is kept") {
        try world("app") { home in
            let p = infoPlist(stamp: "S&1", mod: "/a<b>/mod", icon: true)
            t.check(p.contains("<string>S&amp;1</string>") && p.contains("<key>JebMod</key><string>/a&lt;b&gt;/mod</string>") && p.contains("CFBundleIconFile"), "escaped, with icon and mod")
            t.check(!infoPlist(stamp: "S", mod: "", icon: false).contains("JebMod"), "no mod, no key")
            let a = home + "/swap-a", b = home + "/swap-b"
            writeFile(a + "/x", "a"); writeFile(b + "/y", "b")
            try swapDirs(a, b)
            t.check(fm.fileExists(atPath: a + "/y") && fm.fileExists(atPath: b + "/x"), "swapped")
            let vd = home + "/state/versions"
            var olds: [String] = []
            for s in ["s1", "s2", "s3"] {
                writeFile(home + "/new-\(s)/Contents/Info.plist", infoPlist(stamp: s, mod: "", icon: false))
                olds.append(try installApp(home + "/new-\(s)", appDir: home + "/apps", versionsDir: vd) ?? "nil")
            }
            t.eq(olds, ["old-stamp", "s1", "s2"], "each install returns the stamp it replaced")
            t.eq(appStamp(home), "s3")
            t.eq(((try? fm.contentsOfDirectory(atPath: vd)) ?? []).sorted(), ["s2.app"], "one spare app")
            try restoreApp(oldStamp: "s2", appDir: home + "/apps", versionsDir: vd)
            t.eq(appStamp(home), "s2")
            t.eq(((try? fm.contentsOfDirectory(atPath: vd)) ?? []).sorted(), [], "the bad build is deleted")
        }
    }
}
