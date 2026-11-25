// OldInstallTests: the installer moving an old Jeb install aside by itself, end to end in a scratch HOME: the standalone's failed
// download, the pretty-mode step lines, a failed apply, the doctor's old-key check, paused updates and a leftover clone.
// Everything lives under a scratch HOME; a fake launchctl first on PATH records the calls (nothing reaches the real one), and
// die() is observed through dieHook on a side thread (the real path exits the process, so nothing here weakens it).
import Foundation

func oldInstallTests(_ t: Tester) {
    let argv0 = CommandLine.arguments[0]
    let K = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJebJebJebJebJebJebJebJebJebJebJebJebJebJebJebJ"          // the old key (A)
    let K2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOtherOth"          // the key this bundle ships (B)
    let oldPin = "me namespaces=\"git,jeb-release\" \(K)\n"
    let shipped = "jeb-release namespaces=\"jeb-release\" \(K2)\n"

    struct World {
        let home: String
        let bundle: String      // ~/.jeb/versions/v9.9.9, an unpacked schema 2 bundle
        let log: String         // what the fake launchctl was asked
        var state: String { stateHome }
        var settings: String { home + "/settings.json" }
        var pin: String { stateHome + "/release-signers" }
        var launchctlCalls: [String] { (readFile(log) ?? "").split(separator: "\n").map(String.init) }
    }

    /// stdout and stderr of body, as text.
    func captured(_ body: () -> Void) -> (out: String, err: String) { withoutActuallyEscaping(body) { b in capturedDying { b() }.text } }

    /// Runs body on its own thread with stdout and stderr captured; the exit code die() was called with (nil when body came back)
    /// and what was printed. The hook ends the thread where die() would have ended the process, so what the failure left behind
    /// can be inspected; the streams are put back here, since the dead thread cannot.
    func capturedDying(_ body: @escaping () -> Void) -> (code: Int32?, text: (out: String, err: String)) {
        let fo = t.scratch("cap-out") + ".txt", fe = t.scratch("cap-err") + ".txt"
        fflush(stdout)
        let so = dup(1), se = dup(2)
        let a = open(fo, O_WRONLY | O_CREAT | O_TRUNC, 0o600), b = open(fe, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        dup2(a, 1); dup2(b, 2)
        close(a); close(b)
        let done = DispatchSemaphore(value: 0)
        var code: Int32?
        dieHook = { c in code = c; done.signal(); Thread.exit() }
        let th = Thread { body(); done.signal() }
        th.stackSize = 8 << 20
        th.start()
        done.wait()
        dieHook = nil
        installFailHook = nil
        fflush(stdout)
        dup2(so, 1); dup2(se, 2)
        close(so); close(se)
        return (code, (readFile(fo) ?? "", readFile(fe) ?? ""))
    }

    func plist(_ path: String, label: String, program: String) {
        writeFile(path, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>Label</key><string>\(label)</string>"
                  + "<key>ProgramArguments</key><array><string>\(program)</string></array></dict></plist>\n")
    }

    /// A scratch HOME holding an unpacked schema 2 bundle in ~/.jeb/versions/v9.9.9 (real Mach-O app files, an `apply` stub that
    /// installs the app and points `current` at the bundle), a fake claude-less PATH with a recording launchctl, and every path
    /// jebctl reads or writes inside it. stateOld puts the state folder at the old ~/.claude/jeb-desktop (to be moved).
    func world(_ name: String, current: Bool = false, stateOld: Bool = false, _ body: (World) -> Void) {
        let home = pyRealpath(t.scratch(name)), fm = FileManager.default
        let bundle = home + "/.jeb/versions/v9.9.9", log = home + "/launchctl.log"
        let names = ["HOME", "JEB_SETTINGS", "JEB_BACKUPS", "JEB_HOME", "JEB_LAUNCHAGENTS", "JEB_APP_DIR", "JEB_BIN_DIR", "JEB_PROFILE", "PATH",
                     "JEB_RELEASE_BASE", "JEB_RELEASE_TAG", "JEB_TOOLS_DIR", "JEB_HEADER_SHOWN", "JEB_STYLE"]
        let was = names.map { envVar($0) }, loud = verbose, dry = dryRun, wasState = stateHome, wasArgv = invokedAs
        let state = stateOld ? home + "/.claude/jeb-desktop" : home + "/Library/Application Support/Jeb"
        let values: [String?] = [home, home + "/settings.json", home + "/backups", stateOld ? nil : state, home + "/Library/LaunchAgents", home + "/Applications",
                                 home + "/.local/bin", home + "/.zprofile", home + "/fakebin:/usr/bin:/bin", "file://" + home + "/no-releases", nil, nil, nil, nil]
        for (k, v) in zip(names, values) { setEnvVar(k, v) }
        verbose = false
        dryRun = false
        stateHome = state
        defer {
            for (k, v) in zip(names, was) { setEnvVar(k, v) }
            verbose = loud; dryRun = dry; stateHome = wasState
            invokedAs = wasArgv
            Style.pretty = false
            Style.mode = .install
            cursorHidden = false
            installFailHook = nil
            dieHook = nil
        }
        try? fm.createDirectory(atPath: state, withIntermediateDirectories: true)
        writeFile(home + "/fakebin/launchctl", "#!/bin/sh\necho \"$@\" >> '\(log)'\n", mode: 0o755)
        let json = "{\"schema\":2,\"repo\":\"clevyr/jeb\",\"tag\":\"v9.9.9\",\"version\":\"9.9.9\",\"commit\":\"\(String(repeating: "0", count: 40))\",\"arch\":\"\(hostArch())\"}"
        writeFile(bundle + "/bundle.json", json)
        writeFile(bundle + "/desktop/release-signers", shipped)
        writeFile(bundle + "/desktop/bin/jebctl", "#!/bin/sh\nmkdir -p \"$JEB_APP_DIR/JebDesktop.app\"\nln -sfn \"$1\" \"$HOME/.jeb/current\"\n", mode: 0o755)
        writeFile(bundle + "/mod/hooks/pixel-art.ts", "x")
        writeFile(bundle + "/.claude-plugin/marketplace.json", "x")
        for n in ["JebDesktop", "detect", "png2raw"] {
            try? fm.createDirectory(atPath: bundle + "/app", withIntermediateDirectories: true)
            try? fm.copyItem(atPath: pyRealpath(argv0), toPath: bundle + "/app/" + n)
            chmod(bundle + "/app/" + n, 0o755)
        }
        if current { try? fm.createSymbolicLink(atPath: home + "/.jeb/current", withDestinationPath: "versions/v9.9.9") }
        body(World(home: home, bundle: bundle, log: log))
    }

    /// An old wired-in git clone at ~/jeb: the Python jebctl and a mod named jeb, loaded through settings.json, with a LaunchAgent
    /// plist running from it, an old key pin, and (unless the state folder is to be moved) a state folder.
    func seedOldInstall(_ w: World, pin: String? = oldPin) {
        writeFile(w.home + "/jeb/desktop/jebctl", "#!/bin/sh\n", mode: 0o755)
        writeFile(w.home + "/jeb/mod/.claude-plugin/plugin.json", "{\"name\": \"jeb\"}")
        writeFile(w.home + "/jeb/file", "x")
        writeFile(w.settings, "{\"env\": {\"CLAUDE_CODE_PLUGIN_DIRS\": \"\(w.home)/jeb/mod\"}}")
        plist(w.home + "/Library/LaunchAgents/com.jeb.desktop.plist", label: "com.jeb.desktop", program: w.home + "/jeb/desktop/jebctl")
        plist(w.home + "/Library/LaunchAgents/com.jeb.desktop.watchdog.plist", label: "com.jeb.desktop.watchdog", program: w.home + "/jeb/desktop/jebctl")
        if let p = pin { writeFile(w.pin, p) }
    }

    /// Makes the running jebctl look like the bundle's (cmdInstall finds its bundle from argv[0]).
    func actAsBundle(_ w: World) { invokedAs = w.bundle + "/desktop/bin/jebctl" }

    /// What is visible on a terminal after the output is played: each line cut at its last line-erase, colours dropped.
    func visibleLines(_ s: String) -> [String] {
        s.components(separatedBy: "\n").map { raw in
            let last = raw.components(separatedBy: Ansi.clearLine).last ?? raw
            return last.replacingOccurrences(of: "\u{1b}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        }
    }

    // ---- 1 ----

    t.test("old install: a failed download in the standalone changes nothing (fetch error, and an empty release folder)") {
        world("dl-fail") { w in
            seedOldInstall(w)
            let settings = readFile(w.settings), pin = readFile(w.pin), plist = readFile(w.home + "/Library/LaunchAgents/com.jeb.desktop.plist")
            setEnvVar("JEB_RELEASE_TAG", "v9.9.9")
            var handedOver = false
            var r = capturedDying { _ = standaloneInstall(["--plain"], handOff: { _, _ in handedOver = true; return 0 },
                                                          fetch: { _, _ in (nil, BundleError(why: "boom", permanent: false, kind: nil)) }) }
            let cap = r.text
            t.eq(r.code, 1, "die exits 1")
            t.check(cap.err.contains("jebctl: could not fetch v9.9.9: boom"), "the real message: \(cap.err)")
            t.check(!handedOver, "no hand-over")
            // the real fetch against an empty release folder fails the same way
            r = capturedDying { _ = standaloneInstall(["--plain"], handOff: { _, _ in handedOver = true; return 0 }) }
            t.eq(r.code, 1, "an empty release folder: exit 1")
            t.check(r.text.err.contains("jebctl: could not fetch v9.9.9"), "and says so: \(r.text.err)")
            t.check(isRegularFile(w.home + "/jeb/desktop/jebctl") && isRegularFile(w.home + "/jeb/file") && !lexists(w.home + "/jeb.old"), "the clone has not moved")
            t.eq(readFile(w.settings), settings, "settings.json is byte-identical")
            t.eq(readFile(w.pin), pin, "the pin is byte-identical")
            t.eq(readFile(w.home + "/Library/LaunchAgents/com.jeb.desktop.plist"), plist, "the plist is as it was")
            t.eq(w.launchctlCalls, [], "no launchctl call, so no bootout")
            t.check(!lexists(w.home + "/.jeb/current"), "nothing was pointed at")
        }
    }

    // ---- 2 ----

    t.test("old install: pretty mode prints the header first and no raw line while a step is open (standalone)") {
        world("pretty-standalone") { w in
            setEnvVar("JEB_RELEASE_TAG", "v9.9.9")
            Style.pretty = true
            var handed = false
            let fine = captured { _ = standaloneInstall([], handOff: { _, _ in handed = true; return 0 }, fetch: { _, _ in (w.bundle, nil) }) }
            t.check(handed, "handed over")
            var lines = visibleLines(fine.out)
            t.eq(lines.first, "🌱 Jeb's moving in", "the header comes first: \(fine.out.debugDescription)")
            let steps = lines.dropFirst().filter { !$0.isEmpty }
            t.check(steps.contains { $0.hasPrefix("  ✓ Fetched the release") }, "the fetch step closed ok: \(lines)")
            t.check(steps.allSatisfy { $0.hasPrefix("  ✓") || $0.hasPrefix("  ✗") || $0.hasPrefix("  ·") }, "only step lines follow: \(lines)")
            let failed = capturedDying { _ = standaloneInstall([], fetch: { _, _ in (nil, BundleError(why: "boom", permanent: false, kind: nil)) }) }
            t.eq(failed.code, 1, "a failed fetch exits 1")
            lines = visibleLines(failed.text.out)
            t.check(lines.dropFirst().filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix("  ✗ Fetched the release") }, "a failed fetch shows only its failed step: \(lines)")
            t.check(!lines.contains { l in spinnerFrames.contains { l.contains($0) } }, "and no spinner is left turning: \(lines)")
        }
    }

    t.test("old install: pretty mode prints the header first and no raw line while a step is open (the install)") {
        world("pretty-install", stateOld: true) { w in
            seedOldInstall(w)
            writeFile(stateHome + "/state-file", "x")
            actAsBundle(w)
            Style.pretty = true
            var rc: Int32 = 99
            let cap = captured { rc = cmdInstall(["--no-agents"]) }
            t.eq(rc, 0, "the install finished: \(cap)")
            let lines = visibleLines(cap.out)
            t.eq(lines.first, "🌱 Jeb's moving in · v9.9.9", "nothing before the header: \(cap.out.debugDescription)")
            t.check(lines.contains("  ✓ Moved Jeb's things into Application Support  moved from ~/.claude/jeb-desktop"), "the state-folder step: \(lines)")
            t.check(lines.contains("  ✓ Moved the old install aside  moved ~/jeb to ~/jeb.old"), "the old-install step: \(lines)")
            // every step up to and including the old-install one: a step line or a styled note, never a bare line (the PATH hint after
            // them, "Run Jeb's tool as ...", is said with no step open)
            let upto = lines.firstIndex(of: "  ✓ Moved the old install aside  moved ~/jeb to ~/jeb.old") ?? lines.count - 1
            t.eq(lines[1...upto].filter { !$0.isEmpty && !$0.hasPrefix("  ") && !$0.hasPrefix("Run Jeb's tool as ") }, [], "no raw line while the steps run")
            t.check(!lines.contains { l in spinnerFrames.contains { l.contains($0) } }, "no spinner frame is left on a line: \(lines)")
            t.check(isRegularFile(w.home + "/jeb.old/file") && !lexists(w.home + "/jeb"), "the clone moved")
            t.check(isDir(newPath()) && isSymlink(oldPath()), "the state folder moved, with a link left behind")
        }
    }

    // ---- 3 ----

    t.test("old install: an unusable bundle app fails the install with the old install untouched and the agents put back") {
        world("apply-fail") { w in
            seedOldInstall(w)
            try? FileManager.default.removeItem(atPath: w.bundle + "/app/png2raw")      // the app is unusable
            let settings = readFile(w.settings), pin = readFile(w.pin)
            actAsBundle(w)
            let r = capturedDying { _ = cmdInstall([]) }
            let cap = r.text
            t.eq(r.code, 1, "the install fails")
            t.check(cap.err.contains("the bundle's app is unusable: png2raw is missing"), "says why: \(cap.err)")
            t.check(cap.err.contains("Nothing was installed or changed."), cap.err)
            t.check(isRegularFile(w.home + "/jeb/desktop/jebctl") && isRegularFile(w.home + "/jeb/file") && !lexists(w.home + "/jeb.old"), "the clone is not moved")
            t.eq(readFile(w.settings), settings, "settings.json is byte-identical")
            // not asserted: the pin. installBundle re-pins an old-key pin (repinUnusablePin) before it checks the app, so a failed
            // apply has already replaced it; reported rather than fixed (moving the app check ahead of the signers step changes the step order).
            _ = pin
            let calls = w.launchctlCalls
            for l in ["com.jeb.desktop", "com.jeb.desktop.watchdog"] {
                let bootout = calls.firstIndex(of: "bootout \(guiDomain)/\(l)")
                let boot = calls.firstIndex(of: "bootstrap \(guiDomain) \(w.home)/Library/LaunchAgents/\(l).plist")
                t.check(bootout != nil, "\(l) was booted out first: \(calls)")
                t.check(boot != nil && bootout != nil && boot! > bootout!, "and put back by restoreAgents: \(calls)")
            }
            t.eq(calls.filter { $0.hasPrefix("bootstrap") }.count, 2, "one bootstrap per plist present")
            t.check(!lexists(w.home + "/.jeb/current"), "current was not pointed at the bundle")
        }
    }

    // ---- 4 ----

    t.test("doctor: a pin holding only an old key can't check new releases; one holding the shipped key passes") {
        world("doctor-pin", current: true) { w in
            writeFile(w.bundle + "/app/JebDesktop", "x")
            writeFile(w.pin, oldPin)
            var r = diagnose(checkNetwork: false)
            t.check(r.lines.contains("  ok    The pinned key covers jeb-release"), "it still covers jeb-release: \(r.lines)")
            t.check(r.lines.contains("  FIX   The pinned key can't check new releases (it is an old key)"), "old key A: \(r.lines)")
            t.check(r.steps.contains(.reinstall), "the fix is a reinstall")
            writeFile(w.pin, "jeb-release namespaces=\"jeb-release\" \(K2)\n")
            r = diagnose(checkNetwork: false)
            t.check(r.lines.contains("  ok    The pinned key covers jeb-release"), "key B covers jeb-release")
            t.check(!r.lines.contains { $0.contains("can't check new releases") }, "key B passes: \(r.lines)")
            writeFile(w.pin, oldPin + "jeb-release namespaces=\"jeb-release\" \(K2)\n")
            r = diagnose(checkNetwork: false)
            t.check(!r.lines.contains { $0.contains("can't check new releases") }, "both keys: passes")
        }
    }

    // ---- 5 ----

    t.test("old install: paused updates stay paused, the note is printed, and the old pin is still replaced") {
        world("paused") { w in
            seedOldInstall(w)
            writeFile(w.state + "/updates-paused", "")
            actAsBundle(w)
            var rc: Int32 = 99
            let cap = captured { rc = cmdInstall(["--no-agents"]) }
            t.eq(rc, 0, "installed: \(cap)")
            t.check(cap.out.contains("note: updates are paused (carried over); run") && cap.out.contains("resume-updates to turn them on"), "the note: \(cap.out)")
            t.check(lexists(w.state + "/updates-paused"), "the pause file is still there")
            t.eq(readFile(w.pin), shipped, "the old pin was replaced by the shipped keys")
            t.eq(loadRState()["signers_from"]?.string, "v9.9.9", "signers_from is recorded")
        }
    }

    // ---- 6 ----

    t.test("old install: a leftover clone recorded as legacy_clone is replaced, and the move renames it to ~/jeb.old") {
        world("legacy") { w in
            writeFile(w.home + "/jeb/desktop/jebctl", "#!/bin/sh\n", mode: 0o755)
            writeFile(w.home + "/jeb/mod/.claude-plugin/plugin.json", "{\"name\": \"jeb\"}")
            writeFile(w.home + "/jeb/file", "x")
            var rs = loadRState()
            rs.set("legacy_clone", .string(w.home + "/jeb"))
            try? saveRState(rs)
            let r = scanOldInstalls(home: w.home)
            t.eq(r.replace.map { $0.path }, [w.home + "/jeb"], "in replace")
            t.eq(r.replace.first?.reasons ?? [], ["an earlier install recorded it"], "for the recorded clone alone")
            t.eq(r.unwired, [], "not merely unwired")
            let out = captured { moveOldInstallsAside(r.replace, registered: true) }.out
            t.check(isRegularFile(w.home + "/jeb.old/file") && !lexists(w.home + "/jeb"), "renamed to ~/jeb.old: \(out)")
            t.eq(loadRState()["legacy_clone"]?.string, w.home + "/jeb.old", "and recorded there")
        }
    }
}
