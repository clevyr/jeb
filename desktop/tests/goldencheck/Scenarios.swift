// Scenarios.swift: every golden scenario, in the order the goldens were captured. Each group names the golden prefixes it
// produces so --only can skip it. The goldens were captured from the Python implementation (frozen at v1.6.0); the Swift tools
// are the subject now.
import Foundation

// ======================================================================================================================
// usage texts
func usage() {
    let sb = plainSB("usage")
    write("runtime/usage/jebctl-help.txt", sb.snapshot(sb.jc(["--help"]), plists: false))
    write("runtime/usage/jebctl-perf-bad-args.txt", sb.snapshot(sb.jc(["perf", "--days"]), plists: false))
    SKIPPED.append("runtime/usage/jebctl-install-bad-mode: retired; install has no --mode (plan 3.3)")
    write("runtime/usage/jebctl-no-agents-wrong-command.txt", sb.snapshot(sb.jc(["status", "--no-agents"]), plists: false))
    SKIPPED.append("runtime/usage/jebctl-release-from-bundle: retired; release left jebctl for dev/release (D4, plan 3.3)")
    // the dev jebctl outside a bundle is the standalone install (Standalone.swift)
    write("runtime/usage/install-bad-flag.txt", sb.snapshot(sb.jc(["install", "--bogus"]), plists: false))
    write("runtime/usage/uninstall-bad-flag.txt", sb.snapshot(sb.jc(["uninstall", "--bogus"]), plists: false))
    write("runtime/usage/updater-help.txt", sb.snapshot(sb.script("", ["--help"], tool: .updater), plists: false))
    write("runtime/usage/watchdog-help.txt", sb.snapshot(sb.script("", ["--help"], tool: .watchdog), plists: false))
    let rel = config.root + "/release"
    // no `./release` without a command: that is `release auto`, a real release (it unlocks the owner's signing key via git config)
    write("release/usage/release-bad-command.txt", sb.snapshot(sb.script(rel, ["bogus"], tool: .release), plists: false))
    write("release/usage/release-bundle-bad-args.txt", sb.snapshot(sb.script(rel, ["bundle", "--tag", "1.2"], tool: .release), plists: false))
    write("release/usage/release-bundle-no-app.txt", sb.snapshot(sb.script(rel, ["bundle", "--tag", "v9.9.9", "--out", sb.root + "/out", "--app", sb.root + "/nope"], tool: .release), plists: false))
    write("release/usage/release-smoke-bad-tag.txt", sb.snapshot(sb.script(rel, ["smoke", "1.2.3", "--dry-run"], tool: .release), plists: false))
    write("release/usage/release-smoke-too-old.txt", sb.snapshot(sb.script(rel, ["smoke", "v1.4.0", "--dry-run"], tool: .release), plists: false))
}

// ======================================================================================================================
// Retired layouts
/// The Swift jebctl is bundle-layout only (plan D1): a git-clone golden is not produced, and is listed as skipped instead of
/// missing.
func retiredClone(_ rel: String) {
    SKIPPED.append("\(rel): retired; the git-clone layout is gone (plan D1: bundle layout only)")
}


// ======================================================================================================================
// status, perf, doctor
let TELEMETRY_HEADER = "epoch,stamp,pid,dt,cpu,rss,fp,sessions,class\n"

struct TRow {
    let epoch: Int, stamp: String, cpu: Double, rss: Int, fp: String, cls: String
}

func telemetry(_ sb: SB, _ rows: [TRow], dayOffset: Int = 0) {
    let d = sb.state + "/telemetry"
    mkdirs(d)
    let p = d + "/" + chicagoDay(NOW - dayOffset * 86400) + ".csv"
    var text = readText(p) ?? ""
    if text.isEmpty { text = TELEMETRY_HEADER }
    for r in rows { text += "\(r.epoch),\(r.stamp),777,1.0,\(pyFloatRepr(r.cpu)),\(r.rss),\(r.fp),2,\(r.cls)\n" }
    writeText(p, text)
}

func statusFixtures(_ sb: SB) {
    var rows = (0..<10).map { i in TRow(epoch: NOW - 600 + i * 30, stamp: "20260527-190000", cpu: 0.3 + 0.1 * Double(i % 3), rss: 40 + i, fp: String(80 + i), cls: "calm") }
    rows += (0..<5).map { i in TRow(epoch: NOW - 300 + i * 30, stamp: "20260527-190000", cpu: 5.0 + Double(i), rss: 70 + i, fp: "", cls: "passing") }
    rows.append(TRow(epoch: NOW - 5000, stamp: "20260526-120000", cpu: 0.05, rss: 30, fp: "50", cls: "covered"))
    telemetry(sb, rows)
    telemetry(sb, (0..<4).map { i in TRow(epoch: NOW - 86400 - 100 + i * 10, stamp: "20260526-120000", cpu: 9.0, rss: 100, fp: "200", cls: "calm") }, dayOffset: 1)
    telemetry(sb, [TRow(epoch: NOW - 5 * 86400, stamp: "20260522-120000", cpu: 1.0, rss: 10, fp: "10", cls: "calm")], dayOffset: 5)
    writeText(sb.state + "/updater-state.json", obj(("last", obj(("result", "ok"), ("stamp", "20260527-190000"), ("at", .int(NOW - 7200)), ("why", "smoke and start passed"))),
                                                    ("rejected", ["20260520-010101", "20260521-020202"])).dumps())
    for v in ["20260527-190000.app", "20260520-010101.app", "notes.txt"] { mkdirs(sb.state + "/versions/" + v) }
}

func status() {
    var sb = bundleSB("status-fresh")
    write("runtime/status/bundle-fresh.txt", sb.snapshot(sb.jc(["status"]), plists: false))
    sb = bundleSB("status-full")
    statusFixtures(sb)
    writeText(sb.state + "/updates-paused", "")
    writeText(sb.state + "/quit", "")
    sb.saveRS(obj(("failed", ["v1.5.0", "v1.5.1"]), ("checked", .int(NOW - 3600)),
                  ("last", obj(("at", .int(NOW - 3600)), ("tag", "v1.5.1"), ("result", "gates-rejected"), ("app", "prebuilt"))),
                  ("layout", "bundle"), ("installed", [obj(("tag", "v1.4.0"), ("stamp", nil), ("at", 1))]), ("bridge_reset", 1)))
    mkdirs(sb.agents)
    writeText(sb.agents + "/com.jeb.desktop.plist", "<plist/>")
    write("runtime/status/bundle-full.txt", sb.snapshot(sb.jc(["status"]), plists: false))
    write("runtime/status/perf-default.txt", sb.snapshot(sb.jc(["perf"]), plists: false))
    write("runtime/status/perf-days-2.txt", sb.snapshot(sb.jc(["perf", "--days", "2"]), plists: false))
    write("runtime/status/perf-days-7-stamp.txt", sb.snapshot(sb.jc(["perf", "--days", "7", "--stamp", "20260526-120000"]), plists: false))
    write("runtime/status/perf-stamp-none.txt", sb.snapshot(sb.jc(["perf", "--stamp", "nope"]), plists: false))
    write("runtime/status/pause-updates.txt", sb.snapshot(sb.jc(["pause-updates"]), plists: false))
    write("runtime/status/resume-updates.txt", sb.snapshot(sb.jc(["resume-updates"]), plists: false))
    for m in ["dev", "release"] { retiredClone("runtime/status/clone-" + m) }
    // doctor
    sb = bundleSB("doctor-bundle")
    write("runtime/doctor/bundle-no-app.txt", sb.snapshot(sb.jc(["doctor"]), plists: false))
    sb = bundleSB("doctor-bundle-agents")
    _ = sb.jc([], probe: "write-plists")
    for n in listDir(sb.state + "/launchd") where n.hasSuffix(".plist") { copyFile(sb.state + "/launchd/" + n, sb.agents + "/" + n) }
    let app = sb.home + "/Applications/JebDesktop.app/Contents/MacOS"
    mkdirs(app)
    copyFile(config.stub, app + "/JebDesktop")
    statusFixtures(sb)
    write("runtime/doctor/bundle-with-app-and-agents.txt", sb.snapshot(sb.jc(["doctor"]), plists: false))
    sb = bundleSB("doctor-bundle-nopin", pin: nil)
    removeAll(sb.rel + "/latest")
    write("runtime/doctor/bundle-no-signers-no-release.txt", sb.snapshot(sb.jc(["doctor"]), plists: false))
    sb = bundleSB("doctor-bundle-paused")
    writeText(sb.state + "/updates-paused", "")
    sb.saveRS(obj(("failed", ["v1.5.0"]), ("checked", .int(NOW - 100)), ("last", obj(("at", .int(NOW - 100)), ("tag", "v1.5.0"), ("result", "rejected"), ("app", "prebuilt"))),
                  ("layout", "bundle"), ("installed", [obj(("tag", "v1.4.0"), ("stamp", nil), ("at", 1))])))
    write("runtime/doctor/bundle-paused-failed.txt", sb.snapshot(sb.jc(["doctor"]), plists: false))
    for m in ["dev", "release"] { retiredClone("runtime/doctor/clone-" + m) }
}

// ======================================================================================================================
// follow / rollback / update on an installed schema 1 bundle with schema 2 releases (the native apply is the stub)
func installedTags(_ sb: SB, _ tags: [String]) {
    let inst = tags.enumerated().map { i, t in obj(("tag", .string(t)), ("stamp", nil), ("at", .int(i + 1))) }
    sb.saveRS(obj(("failed", []), ("checked", nil), ("last", nil), ("layout", "bundle"), ("installed", .array(inst)), ("bridge_reset", 1)))
}

func follow() {
    runInBundle = true
    defer { runInBundle = false }
    func fcase(_ name: String, _ sb: SB, _ opts: [String] = [], _ env: [String: String] = [:]) {
        write("runtime/follow/\(name).txt", sb.snapshot(sb.jc(["follow"] + opts, extra: env)))
    }
    fcase("up-to-date", bundleSB("f-current"))
    var sb = bundleSB("f-ok"); sb.release("v1.5.0"); fcase("ok", sb)
    sb = bundleSB("f-ok-quick"); sb.release("v1.5.0"); fcase("ok-quick", sb, ["--quick"])
    sb = bundleSB("f-gates"); sb.release("v1.5.0"); fcase("gates-rejected", sb, [], ["JEB_STUB_RC": "2"])
    sb = bundleSB("f-rolled"); sb.release("v1.5.0"); fcase("rolled-back", sb, [], ["JEB_STUB_RC": "3"])
    sb = bundleSB("f-error"); sb.release("v1.5.0"); fcase("apply-error", sb, [], ["JEB_STUB_RC": "7"])
    sb = bundleSB("f-gates-only"); sb.release("v1.5.0"); fcase("gates-only-pass", sb, ["--gates-only"])
    sb = bundleSB("f-gates-only-fail"); sb.release("v1.5.0"); fcase("gates-only-fail", sb, ["--gates-only"], ["JEB_STUB_RC": "2"])
    sb = bundleSB("f-net"); removeAll(sb.rel + "/latest"); fcase("network-error", sb)
    sb = bundleSB("f-net-dl"); sb.release("v1.5.0"); removeAll(sb.rel + "/download"); fcase("download-missing", sb)
    sb = bundleSB("f-sig"); sb.release("v1.5.0", key: "other"); fcase("signature-rejected", sb)
    sb = bundleSB("f-nopin", pin: nil); sb.release("v1.5.0"); fcase("no-pinned-signers", sb)
    sb = bundleSB("f-adopt", pin: .some(OLD), signersFrom: "v1.3.0"); sb.release("v1.5.0"); fcase("adopt-signers-then-ok", sb)
    sb = bundleSB("f-adopt-same", pin: .some(NEW3), signersFrom: "v1.4.0"); sb.release("v1.5.0"); fcase("adopt-signers-already-match", sb)
    sb = bundleSB("f-adopt-bad", signers: "# nothing usable\n", pin: .some(OLD), signersFrom: "v1.3.0"); sb.release("v1.5.0"); fcase("adopt-signers-unusable", sb)
    for flaw in ["sha", "size", "content", "arch", "json"] {
        sb = bundleSB("f-" + flaw); sb.release("v1.5.0", flaw: flaw); fcase("flaw-" + flaw, sb)
    }
    sb = bundleSB("f-replay"); sb.release("v1.5.0", manifestTag: "v1.4.9"); fcase("flaw-replayed-manifest", sb)
    sb = bundleSB("f-paused"); writeText(sb.state + "/updates-paused", ""); sb.release("v1.5.0"); fcase("paused", sb)
    sb = bundleSB("f-dev"); sb.mode("dev"); sb.release("v1.5.0"); fcase("not-release-mode", sb)
    sb = bundleSB("f-dry"); sb.release("v1.5.0"); fcase("dry-run", sb, ["--dry-run"])
    fcase("dry-run-current", bundleSB("f-dry-cur"), ["--dry-run"])
    sb = bundleSB("f-noagents"); sb.release("v1.5.0"); fcase("ok-no-agents", sb, ["--no-agents"])
    // a failed tag stays skipped; the feed supplies the older candidate
    sb = bundleSB("f-skip"); sb.release("v1.5.0"); sb.release("v1.6.0", key: "other")
    sb.saveRS(obj(("failed", ["v1.6.0"]), ("failed_why", obj(("v1.6.0", obj(("why", "gates"), ("pin", "x"))))), ("checked", nil), ("last", nil), ("layout", "bundle"),
                  ("installed", [obj(("tag", "v1.4.0"), ("stamp", nil), ("at", 1))]), ("bridge_reset", 1)))
    writeText(sb.rel + ".atom", "<feed><entry><link href=\"https://x/releases/tag/v1.6.0\"/></entry><entry><link href=\"https://x/releases/tag/v1.5.0\"/></entry><entry><link href=\"https://x/releases/tag/v1.4.0\"/></entry></feed>")
    fcase("failed-skipped-feed-fallback", sb)
    // straggler: rejected under the old code without a recorded reason (bridge_reset absent) gets another look
    sb = bundleSB("f-straggler"); sb.release("v1.5.0")
    sb.saveRS(obj(("failed", ["v1.5.0"]), ("checked", nil), ("last", nil), ("layout", "bundle"), ("installed", [obj(("tag", "v1.4.0"), ("stamp", nil), ("at", 1))])))
    fcase("straggler-reset", sb)
    // a signature rejection under a different pin gets another look once the pin changes
    sb = bundleSB("f-repin"); sb.release("v1.5.0")
    sb.saveRS(obj(("failed", ["v1.5.0"]), ("failed_why", obj(("v1.5.0", obj(("why", "signature"), ("pin", .string(String(repeating: "0", count: 64))))))), ("checked", nil),
                  ("last", nil), ("layout", "bundle"), ("installed", [obj(("tag", "v1.4.0"), ("stamp", nil), ("at", 1))]), ("bridge_reset", 1)))
    fcase("signature-retry-after-repin", sb)
    // stale LaunchAgents (older command) are healed
    sb = bundleSB("f-heal")
    _ = sb.jc([], probe: "write-plists")
    for n in listDir(sb.state + "/launchd") where n.hasSuffix(".plist") {
        let p = sb.state + "/launchd/" + n
        guard let data = readBytes(p), var d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { fail("plist \(p)") }
        if let label = d["Label"] as? String, ["com.jeb.desktop.release", "com.jeb.desktop.watchdog"].contains(label), let args = d["ProgramArguments"] as? [String] {
            d["ProgramArguments"] = [sb.jeb + "/current/python/bin/python3", "-I", sb.jeb + "/current/desktop/jebctl", args[args.count - 1]]
        }
        guard let out = try? PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0) else { fail("plist dump \(p)") }
        FileManager.default.createFile(atPath: sb.agents + "/" + n, contents: out)
    }
    writeText(sb.stublog, "")
    fcase("heal-plists", sb)
    // rollback (runs on the installed schema 1 bundle, before any handoff; the target is a published schema 2 release
    // whose native jebctl (the stub) gates and swaps)
    sb = bundleSB("rb-floor", tag: "v1.7.1", pin: .some(NEW3)); installedTags(sb, ["v1.6.0", "v1.7.1"])
    write("runtime/rollback/floor.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundleSB("rb-ok", tag: "v1.7.1", pin: .some(NEW3)); sb.release("v1.7.0"); sb.latest("v1.7.1"); installedTags(sb, ["v1.7.0", "v1.7.1"])
    write("runtime/rollback/ok.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundleSB("rb-gates", tag: "v1.7.1", pin: .some(NEW3)); sb.release("v1.7.0"); sb.latest("v1.7.1"); installedTags(sb, ["v1.7.0", "v1.7.1"])
    write("runtime/rollback/gates-rejected.txt", sb.snapshot(sb.jc(["rollback"], extra: ["JEB_STUB_RC": "2"])))
    sb = bundleSB("rb-dl", tag: "v1.7.1", pin: .some(NEW3)); installedTags(sb, ["v1.7.0", "v1.7.1"])
    write("runtime/rollback/download-fails.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundleSB("rb-skip-failed", tag: "v1.7.2", pin: .some(NEW3)); sb.release("v1.7.0"); sb.latest("v1.7.2"); installedTags(sb, ["v1.7.0", "v1.7.1", "v1.7.2"])
    sb.saveRS(sb.loadRS().setting("failed", ["v1.7.1"]))
    write("runtime/rollback/skips-failed-tag.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundleSB("rb-none"); installedTags(sb, [])
    write("runtime/rollback/nothing-recorded.txt", sb.snapshot(sb.jc(["rollback"])))
    sb = bundleSB("rb-dry", tag: "v1.7.1", pin: .some(NEW3)); sb.release("v1.7.0"); sb.latest("v1.7.1"); installedTags(sb, ["v1.7.0", "v1.7.1"])
    write("runtime/rollback/dry-run.txt", sb.snapshot(sb.jc(["rollback", "--dry-run"])))
    // update / retry
    sb = bundleSB("u-dry")
    write("runtime/update/bundle-dry-run.txt", sb.snapshot(sb.jc(["update", "--dry-run"]), plists: false))
    writeText(sb.state + "/updates-paused", "")
    write("runtime/update/bundle-paused.txt", sb.snapshot(sb.jc(["update"]), plists: false))
    retiredClone("runtime/update/clone-dev-dry-run")
    sb = bundleSB("u-retry")
    sb.saveRS(obj(("failed", ["v1.5.0", "v1.6.0"]), ("failed_why", obj(("v1.5.0", obj(("why", "gates"), ("pin", "x"))), ("v1.6.0", obj(("why", "gates"), ("pin", "x"))))),
                  ("checked", nil), ("last", nil), ("layout", "bundle"), ("installed", [obj(("tag", "v1.4.0"), ("stamp", nil), ("at", 1))]), ("bridge_reset", 1)))
    write("runtime/update/bundle-retry-update.txt", sb.snapshot(sb.jc(["retry-update"]), plists: false))
}

// ======================================================================================================================
// install / uninstall dry runs
func installs() {
    // bundle layout: the repo's install/uninstall scripts inside an unpacked bundle at ~/.jeb/versions/<tag>
    var sb = bundleSB("i-bundle", pin: nil, scripts: true)
    sb.saveRS(obj())
    var v = sb.jeb + "/versions/v1.4.0"
    for (flags, name) in [(["--dry-run"], "bundle-dry-run"), (["--dry-run", "--verbose"], "bundle-dry-run-verbose"), (["--dry-run", "--no-agents", "--verbose"], "bundle-dry-run-no-agents"),
                          (["--dry-run", "--dev"], "bundle-dev-refused"), (["--dry-run", "--build-from-source"], "bundle-build-refused"),
                          (["--dry-run", "--repin", "--add-path", "--verbose"], "bundle-dry-run-repin-add-path")] {
        write("runtime/install/\(name).txt", sb.snapshot(sb.script(v + "/install", flags, tool: .install), plists: false))
    }
    // `jebctl install`/`uninstall` only work from the bundle's own desktop/bin/jebctl, so they run as the scripts do
    write("runtime/install/jebctl-bundle-dry-run-verbose.txt", sb.snapshot(sb.script(v + "/install", ["--dry-run", "--verbose", "--no-agents"], tool: .install), plists: false))
    SKIPPED.append("runtime/install/jebctl-bundle-mode-dev-refused: retired; install has no --mode (plan D1: release mode only)")
    // a bundle unpacked somewhere else is refused
    let sb2 = SB("i-bundle-elsewhere")
    sb2.bundleTree(sb2.root + "/Downloads/v1.4.0", "v1.4.0", schema: 1, scripts: true)
    write("runtime/install/bundle-wrong-location.txt", sb2.snapshot(sb2.script(sb2.root + "/Downloads/v1.4.0/install", ["--dry-run", "--verbose"], tool: .install), plists: false))
    for (flags, name) in [(["--dry-run"], "bundle-dry-run"), (["--dry-run", "--verbose"], "bundle-dry-run-verbose"), (["--dry-run", "--purge", "--verbose"], "bundle-dry-run-purge"),
                          (["--dry-run", "--remove-files", "--purge-farm", "--verbose"], "bundle-dry-run-remove-files-purge-farm")] {
        sb = bundleSB("un-" + name, scripts: true)
        v = sb.jeb + "/versions/v1.4.0"
        mkdirs(sb.home + "/.claude/plugins/data")
        writeText(sb.home + "/.claude/plugins/data/jeb_jeb-abc123.json", "{}")
        write("runtime/uninstall/\(name).txt", sb.snapshot(sb.script(v + "/uninstall", flags, tool: .uninstall), plists: false))
    }
    sb = bundleSB("un-jebctl")
    v = sb.jeb + "/versions/v1.4.0"
    write("runtime/uninstall/jebctl-bundle-dry-run-verbose.txt", sb.snapshot(sb.script(v + "/uninstall", ["--dry-run", "--verbose"], tool: .uninstall), plists: false))
    write("runtime/uninstall/jebctl-bundle-dry-run-purge-verbose.txt", sb.snapshot(sb.script(v + "/uninstall", ["--purge", "--dry-run", "--verbose"], tool: .uninstall), plists: false))
    // git-clone layout: gone
    for g in ["install/clone-dev-dry-run", "install/clone-dev-dry-run-verbose", "install/clone-release-dry-run-verbose", "install/clone-release-dry-run",
              "install/clone-release-dry-run-pinned-no-tags", "uninstall/clone-dry-run-verbose", "uninstall/clone-dry-run-remove-clone", "install/clone-release-dirty"] {
        retiredClone("runtime/" + g)
    }
}

// ======================================================================================================================
// watchdog (dry run, fake process list)
func watchdog() {
    func wcase(_ name: String, _ sb: SB, _ argv: [String]) {
        write("runtime/watchdog/\(name).txt", sb.snapshot(sb.jc(argv, tool: .watchdog, patches: [("running", false), ("notify", false)]), plists: false))
    }
    func appExe(_ sb: SB) -> String {
        let exe = sb.home + "/Applications/JebDesktop.app/Contents/MacOS/JebDesktop"
        mkdirs((exe as NSString).deletingLastPathComponent)
        copyFile(config.stub, exe)
        return exe
    }
    var sb = bundleSB("wd-none")
    wcase("none-running-start", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", ""])
    sb = bundleSB("wd-marker"); writeText(sb.state + "/quit", "")
    wcase("none-running-quit-marker", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", ""])
    sb = bundleSB("wd-one")
    var exe = appExe(sb)
    wcase("one-running", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", "100:\(NOW - 500):\(exe)"])
    sb = bundleSB("wd-two")
    exe = appExe(sb)
    wcase("two-running", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", "100:\(NOW - 500):\(exe),200:\(NOW - 50):\(exe)"])
    sb = bundleSB("wd-fresh")
    exe = appExe(sb)
    mkdirs(sb.state + "/heartbeat")
    writeText(sb.state + "/heartbeat/1", "{\"waiting\": false, \"stamp\": \"20260527-190000\"}")    // pid 1 always exists (launchd)
    wcase("one-running-fresh-heartbeat", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", "1:\(NOW - 500):\(exe)"])
    sb = bundleSB("wd-kick"); writeText(sb.state + "/watchdog.kick", "")
    wcase("recent-kick-skipped", sb, ["--dry-run", "--no-recheck-wait", "--fake-procs", ""])
}

// ======================================================================================================================
// probes of pure functions: `jebctl --probe <name>` (desktop/cli/probes/Probes.swift)

/// Probes the Swift jebctl does not answer (golden/README.md, "Probes the Swift jebctl does not answer"): reported as
/// skipped, not as missing.
let SWIFT_PROBE_SKIPS: [String: String] = [
    "release-tags-canned": "retired; the canned git runner is a unit test (desktop/cli/tests/TagsTests.swift)",
]

func probes() {
    let sb = bundleSB("probe")
    sb.release("v1.5.0"); sb.release("v1.6.0")
    writeText(sb.rel + ".atom", "<feed><entry><link href=\"https://github.com/clevyr/jeb/releases/tag/v1.6.0\"/></entry>"
              + "<entry><link href=\"https://github.com/clevyr/jeb/releases/tag/v1.5.0\"/></entry><entry><link href=\"https://github.com/clevyr/jeb/releases/tag/v1.4.0\"/></entry>"
              + "<entry><link href=\"https://github.com/clevyr/jeb/releases/tag/v1.6.0\"/></entry><entry><link href=\"https://github.com/clevyr/jeb/releases/tag/v1.2\"/></entry></feed>")

    func probe(_ name: String, extra: [(String, JSON)] = [], patches: [(String, JSON)] = [], sandbox: SB? = nil) {
        if let why = SWIFT_PROBE_SKIPS[name] {
            SKIPPED.append("runtime/probes/\(name): \(why)")
            return
        }
        let s = sandbox ?? sb
        let fixed: [(String, JSON)] = [("sb", .string(s.root)), ("pub", .string(FAKE_KEY)), ("stub", .string(config.stub))]
        // release-plan is the release tool's (dev/release), not jebctl's
        let r = s.jc([], tool: name == "release-plan" ? .release : .jebctl, patches: patches, probe: name, specExtra: fixed + extra)
        write("runtime/probes/\(name).txt", rcOutErr(r, s))
    }

    probe("tag-order")
    probe("release-tags-canned", patches: [("git", obj(("tag --list v*", [0, "v1.10.0\nv1.2.0\nfoo\nv1.9.3\nv2.0.0\nv1.2\n", ""]),
                                                       ("tag --list v* --points-at HEAD", [0, "v1.9.3\nv1.2\n", ""])))])
    probe("failed-skip")
    probe("signers-parse")
    probe("new-tags")
    probe("check-sandbox")
    probe("constants")
    probe("updater-status")
    probe("jebhome")
    probe("plugdirs", sandbox: bundleSB("probe-plugdirs"))
    let logs = obj(
        ("feat-and-fix", "abc1234\0feat: add the still\0\u{1e}def5678\0fix(desktop): no more leaks\0\u{1e}"),
        ("fix-only", "abc1234\0fix: leak\0\u{1e}"),
        ("bang-major", "abc1234\0feat!: drop the old store\0\u{1e}def5678\0fix: tidy\0\u{1e}"),
        ("breaking-footer", "abc1234\0refactor: new layout\0Moves things.\n\nBREAKING CHANGE: the store moved\0\u{1e}"),
        ("breaking-change-dash", "abc1234\0chore: deps\0BREAKING-CHANGE: node 22\0\u{1e}"),
        ("nothing", "abc1234\0chore: deps\0\u{1e}def5678\0docs: readme\0\u{1e}9999999\0Update stuff\0\u{1e}"),
        ("perf-revert-scoped", "a1\0perf(scene): fewer layers\0\u{1e}b2\0revert: feat: add the still\0\u{1e}c3\0fix(mod)!: hooks\0body\0\u{1e}d4\0feat(desktop): night sky\0\u{1e}"),
        ("empty", ""),
        ("odd-shapes", "a1\0feat:no space\0\u{1e}b2\0FEAT: upper\0\u{1e}c3\0feat (x): spaced scope\0\u{1e}d4\0feat: \0\u{1e}"))
    probe("release-plan", extra: [("logs", logs)])
    // verify_manifest outcomes on real signed files
    let vs = bundleSB("probe-verify", pin: .some(NEW3))
    let good = vs.release("v1.5.0")
    let other = vs.release("v1.5.1", key: "other")
    let replay = vs.release("v1.5.2", manifestTag: "v1.5.0")
    let badjson = vs.release("v1.5.3", flaw: "json")
    let cases = obj(("good", strs([good.0, good.1, "v1.5.0"])), ("unknown-signer", strs([other.0, other.1, "v1.5.1"])), ("replayed-tag", strs([replay.0, replay.1, "v1.5.2"])),
                    ("invalid-json", strs([badjson.0, badjson.1, "v1.5.3"])), ("wrong-sig-for-manifest", strs([good.0, other.1, "v1.5.0"])), ("missing-sig", strs([good.0, good.1 + ".nope", "v1.5.0"])))
    probe("verify-manifest", extra: [("cases", cases)], sandbox: vs)
    let vs2 = bundleSB("probe-verify-nopin", pin: nil)
    let g = vs2.release("v1.5.0")
    let r = vs2.jc([], probe: "verify-manifest",
                   specExtra: [("sb", .string(vs2.root)), ("pub", .string(FAKE_KEY)), ("stub", .string(config.stub)), ("cases", obj(("good-but-no-pin", strs([g.0, g.1, "v1.5.0"]))))])
    write("runtime/probes/verify-manifest-no-pin.txt", rcOutErr(r, vs2))
}

// ======================================================================================================================
// ./release: version bump and notes (jebctl release --dry-run in a throwaway repo), constants, smoke --dry-run, bundle
func gitEnv(_ home: String) -> [String: String] {
    var e = BASE_ENV
    for (k, v) in ["HOME": home, "PATH": "\(config.tmp)/bin:/usr/bin:/bin", "GIT_AUTHOR_NAME": "Golden", "GIT_AUTHOR_EMAIL": "golden@example.com", "GIT_COMMITTER_NAME": "Golden",
                   "GIT_COMMITTER_EMAIL": "golden@example.com", "GIT_AUTHOR_DATE": "2026-05-01T12:00:00Z", "GIT_COMMITTER_DATE": "2026-05-01T12:00:00Z", "GIT_CONFIG_NOSYSTEM": "1"] { e[k] = v }
    return e
}

/// A throwaway repo: the commit ids depend only on the fixtures.
func makeRepo(_ name: String, _ commits: [(String, String)], tagAt: Int? = nil, signingkey: Bool = true, branch: String = "main") -> (String, [String: String]) {
    let d = config.tmp + "/repos/" + name
    mkdirs(d + "/desktop/cli")
    mkdirs(d + "/mod/.claude-plugin")
    let env = gitEnv(config.tmp + "/repos/home")
    mkdirs(env["HOME"]!)
    func g(_ a: String...) { must(["/usr/bin/git", "-C", d] + a, env: env) }
    g("init", "-q", "-b", branch)
    g("config", "commit.gpgsign", "false")
    if signingkey { g("config", "user.signingkey", "~/.ssh/jeb-release.pub") }
    // kept as captured: the file is part of the first commit, so the commit ids in the goldens depend on it
    writeText(d + "/.gitignore", "desktop/jebctl\ndesktop/*.py\n__pycache__/\n")
    writeText(d + "/desktop/release-signers", "jeb-release namespaces=\"jeb-release\" \(FAKE_KEY)\n")
    writeText(d + "/desktop/cli/Signers.swift", "let signerLines = [\n    \"jeb-release namespaces=\\\"jeb-release\\\" " + FAKE_KEY + "\",\n]\n")
    writeText(d + "/mod/.claude-plugin/plugin.json", obj(("name", "jeb"), ("version", "1.2.0")).dumps())
    g("add", "-A")
    g("commit", "-q", "-m", "chore: fixtures")
    for (i, (subject, body)) in commits.enumerated() {
        if tagAt == i { g("tag", "v1.2.0") }
        writeText(d + "/f\(i).txt", subject + "\n")
        g("add", "-A")
        g("commit", "-q", "-m", subject + (body.isEmpty ? "" : "\n\n" + body))
    }
    if tagAt == commits.count { g("tag", "v1.2.0") }
    return (d, env)
}

func releaseSteps() {
    func scase(_ name: String, _ repo: String, _ env: [String: String], _ args: [String]) {
        var sbEnv = env
        sbEnv["JEB_HOME"] = config.tmp + "/repos/state-" + name
        sbEnv["JEB_APP_DIR"] = config.tmp + "/repos/apps"
        sbEnv["JEB_LAUNCHAGENTS"] = config.tmp + "/repos/agents"
        sbEnv["JEB_NO_LAUNCHCTL"] = "1"
        mkdirs(sbEnv["JEB_HOME"]!)
        writeText(sbEnv["JEB_HOME"]! + "/install-mode", "dev\n")
        let argv = ["release", "--dry-run", "--parity"] + args
        // the release tool's steps alone (`release steps`), told the throwaway clone
        let r: Result
        if let full = swiftArgv(.release, ["steps"] + argv.dropFirst(), scriptPath: nil) {
            for (k, v) in swiftTestEnv(noProcs: true) { sbEnv[k] = v }
            sbEnv["JEB_RELEASE_CLONE"] = repo
            r = runProcess(full, env: sbEnv, cwd: repo)
        } else { r = notBuilt(.release) }
        write("release/steps/\(name).txt", rcOutErr(r))
    }

    let featFix = [("feat: add the still", ""), ("fix(desktop): no more leaks", ""), ("docs: readme", ""), ("Update stuff", "")]
    var (d, env) = makeRepo("feat-fix", featFix, tagAt: 0)
    scase("auto-minor", d, env, [])
    scase("forced-patch", d, env, ["--bump", "patch"])
    scase("forced-major", d, env, ["--bump", "major"])
    scase("bad-bump", d, env, ["--bump", "bogus"])
    scase("bad-bump-missing", d, env, ["--bump"])
    (d, env) = makeRepo("fix-only", [("fix: leak", "")], tagAt: 0)
    scase("auto-patch", d, env, [])
    (d, env) = makeRepo("bang", [("feat!: drop the old store", ""), ("fix: tidy", "")], tagAt: 0)
    scase("auto-major-bang", d, env, [])
    (d, env) = makeRepo("footer", [("refactor: new layout", "Moves things.\n\nBREAKING CHANGE: the store moved")], tagAt: 0)
    scase("auto-major-footer", d, env, [])
    (d, env) = makeRepo("nothing", [("chore: deps", ""), ("docs: readme", "")], tagAt: 0)
    scase("nothing-to-release", d, env, [])
    scase("nothing-forced-patch", d, env, ["--bump", "patch"])
    (d, env) = makeRepo("mixed", [("perf(scene): fewer layers", ""), ("revert: feat: add the still", ""), ("fix(mod)!: hooks", "body"), ("feat(desktop): night sky", ""), ("chore(release): v1.2.1", "")], tagAt: 0)
    scase("mixed-groups", d, env, [])
    (d, env) = makeRepo("no-tags", [("feat: first", "")])
    scase("first-release", d, env, [])
    scase("first-release-forced-minor", d, env, ["--bump", "minor"])
    (d, env) = makeRepo("head-tagged", [("feat: x", "")], tagAt: 1)
    scase("head-already-tagged", d, env, [])
    (d, env) = makeRepo("no-key", [("feat: x", "")], tagAt: 0, signingkey: false)
    scase("no-signing-key", d, env, [])
    (d, env) = makeRepo("branch", [("feat: x", "")], tagAt: 0, branch: "work")
    scase("wrong-branch", d, env, [])
    (d, env) = makeRepo("dirty", [("feat: x", "")], tagAt: 0)
    writeText(d + "/f0.txt", (readText(d + "/f0.txt") ?? "") + "dirty\n")
    scase("dirty-tree", d, env, [])
    (d, env) = makeRepo("signer-mismatch", [("feat: x", "")], tagAt: 0)
    writeText(d + "/desktop/release-signers", "other namespaces=\"jeb-release\" \(FAKE_KEY)\n")
    must(["/usr/bin/git", "-C", d, "commit", "-qam", "chore: change the signers"], env: env)
    scase("signer-constant-mismatch", d, env, [])
}

/// glob(3) under `dir`: does `pattern` match anything? (no braces, dotfiles hidden)
func globMatches(_ dir: String, _ pattern: String) -> Bool {
    var g = glob_t()
    defer { globfree(&g) }
    let rc = glob(dir + "/" + pattern, 0, nil, &g)
    return rc == 0 && g.gl_matchc > 0
}

func releaseTool() {
    let rel = config.root + "/release"
    let sb = plainSB("release-tool")
    let r = sb.jc([], tool: .release, patches: nil, probe: "constants")
    write("release/tool/constants.txt", rcOutErr(r, sb))
    write("release/tool/smoke-dry-run.txt", sb.snapshot(sb.script(rel, ["smoke", "--dry-run"], tool: .release), plists: false))
    write("release/tool/smoke-dry-run-tag.txt", sb.snapshot(sb.script(rel, ["smoke", "v1.5.0", "--dry-run"], tool: .release), plists: false))
    SKIPPED.append("release/tool/check-notices: retired; schema 2 bundles ship no Python, so there is no notices line to check")
    // the bundles, offline (schema 2: no Python in the bundle, so nothing is downloaded)
    let consts = r.rc == 0 ? ((try? JSON.parse(r.stdout)) ?? obj()) : obj()
    let stage = sb.root + "/stage"
    mkdirs(stage)
    for n in ["JebDesktop", "detect", "png2raw", "jebctl"] { copyFile(config.stub, stage + "/" + n) }
    runProcess(["/usr/bin/codesign", "-s", "-", "-f", stage + "/jebctl"])
    let signers = sb.root + "/signers"
    writeText(signers, ONLY_NEW)
    let out = sb.root + "/out"
    var env = BASE_ENV
    for (k, v) in ["HOME": config.realHome, "PATH": "\(config.tmp)/bin:/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": sb.root] { env[k] = v }
    let args = ["bundle", "--tag", "v9.9.9", "--out", out, "--ref", "HEAD", "--app", stage, "--key", config.keys["new"]!, "--signers", signers]
    let br: Result
    if let full = swiftArgv(.release, args, scriptPath: nil) {
        for (k, v) in swiftTestEnv(noProcs: true) { env[k] = v }
        br = runProcess(full, env: env, cwd: sb.root)
    } else { br = notBuilt(.release) }
    var text = rcOutErr(br, sb)
    let man = out + "/Jeb-v9.9.9-manifest.json"
    if let mt = readText(man), var m = try? JSON.parse(mt) {
        m = m.setting("created", "$CREATED")
        if case .object(var bundles)? = m["bundles"] {
            for i in bundles.indices where bundles[i].1["size"] != nil { bundles[i].1 = bundles[i].1.setting("size", "$SIZE") }
            m = m.setting("bundles", .object(bundles))
        }
        if let j = m["jebctl"], j["size"] != nil { m = m.setting("jebctl", j.setting("size", "$SIZE")) }
        text += section("manifest (created/size/sha256/commit normalized)", norm(m.dumps(indent: 1, sortKeys: true), sb))
        text += section("files made", norm(listDir(out).joined(separator: "\n"), sb))
    }
    let prune = consts["PRUNE"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    for arch in ["arm64", "x86_64"] {
        let zp = out + "/Jeb-v9.9.9-macos-\(arch).zip"
        if !isFile(zp) { continue }
        let ex = sb.root + "/unz-" + arch
        must(["/usr/bin/ditto", "-x", "-k", zp, ex])
        let names = walkFiles(ex)
        let rest = names
        text += section("\(arch) bundle.json", prettyJSON(readText(ex + "/bundle.json") ?? "", sb))
        text += section("\(arch): repo files in the bundle (git archive HEAD of TREE, plus app/, desktop/bin/jebctl, bundle.json; tied to $HEAD)", rest.joined(separator: "\n"))
        let required = consts["REQUIRED"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        text += section("\(arch): required files", required.map { "\($0): \(isFile(ex + "/" + $0) || isDir(ex + "/" + $0) ? "present" : "missing")" }.joined(separator: "\n"))
        text += section("\(arch): PRUNE globs present in the bundle?", prune.map { "\($0): \(globMatches(ex, $0) ? "present" : "absent")" }.joined(separator: "\n"))
    }
    write("release/bundle/v9.9.9.txt", text)
}

// ======================================================================================================================
// the gates: jebgates parity gen and fake
func tools() {
    let toolsSrc = config.desk + "/src/tools"       // the working folder of the render compare
    let p = config.tmp + "/ptools/src"
    mkdirs(p + "/fixtures")
    // the tracked fixtures and band-out.txt were generated under America/New_York (the band's ms() uses mktime): the one TZ exception
    var env = BASE_ENV
    for (k, v) in ["TZ": "America/New_York", "PATH": "/usr/bin:/bin", "HOME": config.tmp + "/ptools/home", "JEB_MOD": config.root + "/mod"] { env[k] = v }
    func parityGen() -> Result {
        // jebgates parity gen, writing <scratch>/src/fixtures (--src stands in for the scratch copy's own folder)
        guard let full = swiftArgv(.parity, ["gen", "--src", p], scriptPath: nil) else { return notBuilt(.parity) }
        var e = env
        for (k, v) in swiftTestEnv(noProcs: true) { e[k] = v }
        return runProcess(full, env: e, cwd: config.tmp + "/ptools")
    }
    var r = parityGen()
    var text = section("invocation", "JEB_MOD=$REPO/mod TZ=America/New_York /usr/bin/python3 -I <copy of desktop/src/tools/parity.py at <scratch>/src/tools/parity.py> gen\n(writes <scratch>/src/fixtures/<name>.store.json; no modcopy, so no band test)")
    text += rcOutErr(r)
    var rows: [String] = []
    for f in listDir(p + "/fixtures") {
        let mine = readBytes(p + "/fixtures/" + f) ?? Data()
        let tracked = config.desk + "/src/fixtures/" + f
        let same = isFile(tracked) && readBytes(tracked) == mine
        rows.append("\(f)  sha256 \(sha256Hex(mine))  \(mine.count) bytes  tracked desktop/src/fixtures/\(f): \(same ? "same bytes" : (isFile(tracked) ? "DIFFERENT" : "not tracked"))")
    }
    text += section("stores written (every one must equal the tracked fixture byte for byte)", rows.joined(separator: "\n"))
    write("release/parity/gen.txt", text)
    // with a modcopy: the band's scratch test
    mkdirs(p + "/modcopy/tests")
    r = parityGen()
    let tsx = p + "/modcopy/tests/zz-parity.test.tsx"
    let body = readText(tsx) ?? ""
    text = rcOutErr(r)
    text += section("modcopy/tests/zz-parity.test.tsx", "sha256 \(sha256Hex(Data(body.utf8)))  \(body.unicodeScalars.count) bytes  \(body.filter { $0 == "\n" }.count) lines")
    if body.unicodeScalars.count <= 65536 { text += section("zz-parity.test.tsx text", norm(body)) }
    write("release/parity/gen-with-modcopy.txt", text)
    if config.render {
        let jb = config.desk + "/src/JebDesktop"
        if isFile(jb) {
            var e = env
            e["JEB_BIN"] = "JebDesktop"
            let argv = ["compare", config.desk + "/src/fixtures/band-out.txt"]
            // jebgates parity compare, on the repo's desktop/src
            let cr: Result
            if let full = swiftArgv(.parity, argv + ["--src", config.desk + "/src"], scriptPath: nil) { cr = runProcess(full, env: e, cwd: toolsSrc) } else { cr = notBuilt(.parity) }
            write("release/parity/compare.txt", rcOutErr(cr))
        } else {
            SKIPPED.append("release/parity/compare: --render asked but desktop/src/JebDesktop is not built")
        }
    }
    // fake.py: the scratch store writer, with the clock advancing only through its sleeps
    for mode in ["idle", "busy"] {
        let d = config.tmp + "/fake-" + mode
        mkdirs(d)
        let store = d + "/store.json"
        var fe = BASE_ENV
        fe["PATH"] = "/usr/bin:/bin"
        fe["HOME"] = d
        // jebgates fake <store> 3 <mode> 6 with JEB_TEST_NOW (sleeps advance the pinned clock by 0.5 s)
        let fr: Result
        if let full = swiftArgv(.fake, [store, "3", mode, "6"], scriptPath: nil) {
            for (k, v) in swiftTestEnv(noProcs: true) { fe[k] = v }
            fr = runProcess(full, env: fe, cwd: d)
        } else { fr = notBuilt(.fake) }
        var text = section("invocation", "fake.py <store> 3 \(mode) 6  (clock pinned at \(NOW), advancing 0.5 s per sleep; random.seed(7); the module's own random.Random(7))")
        text += rcOutErr(fr)
        if let s = readText(store) { text += section("final store.json", prettyJSON(s)) }
        if let w = readText(store + ".writes") { text += section("store.json.writes (ms wall time of each write)", w) }
        write("release/tools/fake-\(mode).txt", text)
    }
}

// art (exact bytes and decoded-frame hashes) lives in Art.swift.

/// Every group with the golden prefixes it produces, in the capture's order.
let GROUPS: [(name: String, prefixes: [String], run: () -> Void)] = [
    ("usage", ["runtime/usage", "release/usage"], usage),
    ("status", ["runtime/status", "runtime/doctor"], status),
    ("follow", ["runtime/follow", "runtime/rollback", "runtime/update"], follow),
    ("installs", ["runtime/install", "runtime/uninstall"], installs),
    ("watchdog", ["runtime/watchdog"], watchdog),
    ("probes", ["runtime/probes"], probes),
    ("release-steps", ["release/steps"], releaseSteps),
    ("release-tool", ["release/tool", "release/bundle"], releaseTool),
    ("tools", ["release/parity", "release/tools"], tools),
]
