// StyleTests: the pure parts of Style.swift (mode detection, step rendering, key decoding, the PATH picker reducer and its
// gate). Nothing here opens /dev/tty or touches a real profile.
import Foundation

func styleTests(_ t: Tester) {
    func plainText(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1b}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
    }
    let tty = ["TERM": "xterm-256color"]

    t.test("style: pretty only on a tty with colour allowed, never with --verbose or --plain") {
        t.check(detectPretty(env: tty, isTTY: true, verbose: false, plain: false), "a tty")
        t.check(!detectPretty(env: tty, isTTY: false, verbose: false, plain: false), "a pipe")
        t.check(!detectPretty(env: tty.merging(["NO_COLOR": "1"]) { $1 }, isTTY: true, verbose: false, plain: false), "NO_COLOR")
        t.check(!detectPretty(env: ["TERM": "dumb"], isTTY: true, verbose: false, plain: false), "TERM=dumb")
        t.check(!detectPretty(env: [:], isTTY: true, verbose: false, plain: false), "no TERM")
        t.check(!detectPretty(env: tty, isTTY: true, verbose: true, plain: false), "--verbose")
        t.check(!detectPretty(env: tty, isTTY: true, verbose: false, plain: true), "--plain")
    }

    t.test("style: JEB_STYLE overrides the detection but not --verbose or --plain") {
        t.check(detectPretty(env: ["JEB_STYLE": "pretty"], isTTY: false, verbose: false, plain: false), "forced on")
        t.check(!detectPretty(env: tty.merging(["JEB_STYLE": "plain"]) { $1 }, isTTY: true, verbose: false, plain: false), "forced off")
        t.check(!detectPretty(env: ["JEB_STYLE": "pretty"], isTTY: true, verbose: true, plain: false), "verbose wins")
        t.check(!detectPretty(env: ["JEB_STYLE": "pretty"], isTTY: true, verbose: false, plain: true), "plain wins")
    }

    t.test("style: friendly labels come from one table, unknown ones stay as they are") {
        t.eq(friendlyLabel("checks", mode: .install), "Checked the release is the real thing")
        t.eq(friendlyLabel("signers", mode: .install), "Pinned the signing key")
        t.eq(friendlyLabel("app", mode: .install), "Built the farmhouse")
        t.eq(friendlyLabel("LaunchAgents", mode: .install), "Hired a watchdog")
        t.eq(friendlyLabel("desktop", mode: .install), "Woke Jeb up")
        t.eq(friendlyLabel("jebctl command", mode: .install), "Put jebctl in the toolshed")
        t.eq(friendlyLabel("Claude Code plugin", mode: .install), "Introduced Jeb to Claude Code")
        t.eq(friendlyLabel("jebctl command", mode: .uninstall), "Took jebctl out of the toolshed")
        t.eq(friendlyLabel("something else", mode: .install), "something else")
    }

    t.test("style: fin text picks the glyph") {
        let ok = renderStep(label: "app", text: "ok (prebuilt v1.8.0, 3s)", mode: .install)
        t.eq(plainText(ok), "  ✓ Built the farmhouse  prebuilt v1.8.0, 3s")
        t.check(ok.contains(Ansi.green + "✓"), "green tick")
        t.eq(plainText(renderStep(label: "desktop", text: "running", mode: .install)), "  ✓ Woke Jeb up")
        let skip = renderStep(label: "desktop", text: "skipped (--no-agents)", mode: .install)
        t.eq(plainText(skip), "  · Woke Jeb up  skipped (--no-agents)")
        t.check(skip.contains(Ansi.dim), "dimmed")
        t.eq(plainText(renderStep(label: "jebctl command", text: "not installed", mode: .uninstall)), "  · Took jebctl out of the toolshed  not installed")
        let bad = renderStep(label: "desktop", text: "not running yet; see `jebctl status`", mode: .install)
        t.eq(plainText(bad), "  ✗ Woke Jeb up  not running yet; see `jebctl status`")
        t.check(bad.contains(Ansi.red + "✗"), "red cross")
        t.eq(plainText(renderStep(label: "mystery", text: "failed", mode: .install)), "  ✗ mystery  failed")
    }

    t.test("style: header, closing line and errors") {
        t.eq(renderHeader(mode: .install, version: "v1.8.0"), "🌱 Jeb's moving in · v1.8.0")
        t.eq(renderHeader(mode: .install, version: nil), "🌱 Jeb's moving in")
        t.eq(renderHeader(mode: .update, version: nil), "🌱 Jeb's checking for news")
        t.eq(renderHeader(mode: .uninstall, version: nil), "🧺 Packing up Jeb")
        t.eq(plainDone, "Done. Start a new Claude Code session to load Jeb; the desktop fills in once a session has run.")
        t.eq(prettyDone, "🚜 All set. Start a new Claude Code session and Jeb will turn up on your desktop.")
        t.eq(renderDone(failed: false), prettyDone)
        t.eq(plainText(renderDone(failed: true)), "  ⚠ Jeb's in, but a step above did not go right. Run jebctl doctor to sort it out.")
        t.eq(renderSay("Dry run only; nothing was changed."), Ansi.dim + "Dry run only; nothing was changed." + Ansi.reset)
        t.eq(renderSay("Health check"), "Health check")
        let e = renderError("jebctl: could not reach GitHub (timeout); check the network and run jebctl install again").map(plainText)
        t.eq(e, ["  ✗ could not reach GitHub (timeout)", "    Check the network and run jebctl install again"])
        t.eq(renderError("a gate failed; nothing installed.").map(plainText), ["  ✗ a gate failed; nothing installed."])
    }

    t.test("style: keys decode, an arrow sequence is not a lone escape") {
        t.eq(decodeKeys([0x1b, 0x5b, 0x41]), [.up])
        t.eq(decodeKeys([0x1b, 0x5b, 0x42]), [.down])
        t.eq(decodeKeys([0x1b, 0x4f, 0x41]), [.up], "application mode")
        t.eq(decodeKeys([0x1b]), [.esc], "lone escape")
        t.eq(decodeKeys([0x1b, 0x5b, 0x43]), [.other], "right arrow")
        t.eq(decodeKeys(Array("kj a".utf8)), [.up, .down, .toggle, .all])
        t.eq(decodeKeys([0x20]), [.toggle])
        t.eq(decodeKeys([0x0d]), [.enter])
        t.eq(decodeKeys([0x0a]), [.enter])
        t.eq(decodeKeys(Array("q".utf8)), [.quit])
        t.eq(decodeKeys([0x03]), [.interrupt])
        t.eq(decodeKeys([0x1b, 0x5b, 0x42, 0x20]), [.down, .toggle], "a sequence then a key")
    }

    t.test("style: an arrow key split across reads is not an escape; the reader waits briefly for the rest") {
        t.check(needsMoreKeys([0x1b]), "a lone ESC may be the start of one")
        t.check(needsMoreKeys([0x1b, 0x5b]), "ESC [")
        t.check(needsMoreKeys([0x1b, 0x4f]), "ESC O")
        t.check(needsMoreKeys([0x1b, 0x5b, 0x31, 0x3b]), "ESC [ 1 ;")
        t.check(!needsMoreKeys([0x1b, 0x5b, 0x42]), "a whole arrow")
        t.check(!needsMoreKeys(Array("kj".utf8)), "plain keys")
        t.check(!needsMoreKeys([0x1b, 0x78]), "ESC then a letter is not a sequence")
        t.check(needsMoreKeys([0x6a, 0x1b]), "a key then a trailing ESC")
        t.eq(decodeKeys([0x1b] + [0x5b, 0x42]), [.down], "the joined bytes are one arrow")
        var fds: [Int32] = [0, 0]
        pipe(&fds)
        defer { close(fds[0]); close(fds[1]) }
        var esc: UInt8 = 0x1b
        write(fds[1], &esc, 1)
        let rest: [UInt8] = [0x5b, 0x42]
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(15)) { _ = rest.withUnsafeBufferPointer { write(fds[1], $0.baseAddress, 2) } }
        t.eq(decodeKeys(readKeyBytes(fds[0], wait: 500)), [.down], "ESC, then [B a moment later")
        write(fds[1], &esc, 1)
        t.eq(decodeKeys(readKeyBytes(fds[0], wait: 20)), [.esc], "a lone ESC is Esc once nothing follows")
    }

    t.test("style: a warning in the middle of a step keeps the step's label for its fin") {
        let file = t.scratch("err") + ".txt"
        fflush(stdout)
        let so = dup(1), se = dup(2), fd = open(file, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        dup2(fd, 1)
        dup2(fd, 2)
        close(fd)
        Style.pretty = true
        Style.lead("checks")
        Style.error("jebctl: something small went wrong")
        let kept = Style.openLabel
        Style.fin("ok")
        let after = Style.openLabel
        Style.pretty = false
        fflush(stdout)
        dup2(so, 1)
        dup2(se, 2)
        close(so)
        close(se)
        t.eq(kept, "checks", "the label survives the error")
        t.eq(after, nil, "and fin closes it")
        let out = readFile(file) ?? ""
        t.check(out.contains("something small went wrong"), "the error is shown")
        t.check(out.contains("✓") && out.contains("Checked the release is the real thing"), "the step line is still printed: \(out)")
    }

    func state() -> PickerState { PickerState(loginShell: "zsh", setUp: ["fish"]) }

    t.test("style: the picker starts with the login shell and set-up shells checked") {
        let s = state()
        t.eq(s.checked, [true, false, true, false])
        t.eq(s.cursor, 0)
        t.eq(PickerState(loginShell: nil).checked, [false, false, false, false])
        t.eq(PickerState(loginShell: "zsh", configured: ["bash"]).checked, [true, true, false, false])
    }

    t.test("style: the cursor wraps, space toggles, a toggles all") {
        var s = state()
        s = pickerStep(s, key: .up)
        t.eq(s.cursor, 3, "up from the top wraps")
        s = pickerStep(s, key: .down)
        t.eq(s.cursor, 0, "down from the bottom wraps")
        s = pickerStep(s, key: .down)
        s = pickerStep(s, key: .toggle)
        t.eq(s.checked, [true, true, true, false])
        s = pickerStep(s, key: .toggle)
        t.eq(s.checked, [true, false, true, false])
        s = pickerStep(s, key: .all)
        t.eq(s.checked, [true, true, true, true], "some on: all on")
        s = pickerStep(s, key: .all)
        t.eq(s.checked, [false, false, false, false], "all on: all off")
        s = pickerStep(s, key: .other)
        t.eq(s.outcome, nil)
    }

    t.test("style: enter confirms the checked shells, esc and q skip, ctrl-c aborts, an empty confirm selects nothing") {
        let done = pickerStep(pickerStep(state(), key: .toggle), key: .enter)
        t.eq(done.outcome, .confirmed)
        t.eq(pickerSelection(done), ["fish"], "zsh was unchecked by the toggle")
        t.eq(pickerStep(done, key: .down), done, "nothing moves after the outcome")
        for k in [Key.esc, .quit] {
            let s = pickerStep(state(), key: k)
            t.eq(s.outcome, .skipped)
            t.eq(pickerSelection(s), [])
        }
        let hit = pickerStep(state(), key: .interrupt)
        t.eq(hit.outcome, .aborted, "ctrl-c aborts the install, it is not a skip")
        t.eq(pickerSelection(hit), [])
        let none = pickerStep(pickerStep(state(), key: .all), key: .all)
        t.eq(pickerSelection(pickerStep(none, key: .enter)), [], "an empty selection is a skip")
    }

    t.test("style: the picker renders the layout") {
        t.eq(renderPicker(state()), [
            "Want to type plain `jebctl` in your terminal?",
            "Pick the shells to set up (space to toggle, enter to confirm, esc to skip):",
            "❯ ◉ zsh   (your login shell)",
            "  ◯ bash",
            "  ◉ fish  (set up)",
            "  ◯ nushell",
        ])
        t.check(renderPicker(pickerStep(state(), key: .down))[3].hasPrefix("❯ ◯ bash"), "the marker follows the cursor")
    }

    t.test("style: the picker is asked only when every condition holds") {
        func ask(pretty: Bool = true, fresh: Bool = true, add: Bool = false, no: Bool = false, dry: Bool = false, onPath: Bool = false, tty: Bool = true) -> Bool {
            shouldAskForPath(pretty: pretty, fresh: fresh, addFlag: add, noFlag: no, dry: dry, onPath: onPath, ttyAvailable: tty)
        }
        t.check(ask(), "all conditions")
        t.check(!ask(pretty: false), "plain output")
        t.check(!ask(fresh: false), "an update")
        t.check(!ask(add: true), "--add-path")
        t.check(!ask(no: true), "--no-add-path")
        t.check(!ask(dry: true), "dry run")
        t.check(!ask(onPath: true), "already on PATH")
        t.check(!ask(tty: false), "no terminal")
        var opened = false
        _ = shouldAskForPath(pretty: false, fresh: true, addFlag: false, noFlag: false, dry: false, onPath: false, ttyAvailable: { opened = true; return true }())
        t.check(!opened, "the terminal is not probed when an earlier condition says no")
    }

    t.test("style: --plain is accepted and forwarded by the standalone install") {
        let f = parseStandaloneFlags(["--plain", "--dry-run"])
        t.check(f.plain && f.bad == nil, "accepted")
        t.eq(f.forward, ["--dry-run", "--plain"])
    }

    t.test("picker: lines are clipped to the terminal width so the redraw never wraps") {
        t.eq(clipLine("short", to: 80), "short")
        t.eq(clipLine("abcdefghij", to: 11), "abcdefghij", "fits with a column to spare")
        t.eq(clipLine("abcdefghij", to: 10), "abcdefgh…")
        t.eq(clipLine("❯ ◉ zsh   (your login shell)", to: 12), "❯ ◉ zsh   …")
        t.check(renderPicker(PickerState(loginShell: "zsh")).map { clipLine($0, to: 40) }.allSatisfy { $0.count <= 39 }, "a 40-column picker")
    }

    t.test("health: the steps every first install leaves are not listed") {
        t.check(expectedAfterInstall.contains(.newSession) && expectedAfterInstall.contains(.addPath), "expected ones")
        t.check(!expectedAfterInstall.contains(.reinstall) && !expectedAfterInstall.contains(.start), "real problems stay")
        t.eq(friendlyLabel("health", mode: .install), "Gave the farm a once-over")
    }

    t.test("style: the spinner line is clipped so its \\r redraw never wraps") {
        let narrow = plainText(renderSpinner(label: "checks", mode: .install, frame: 0, width: 40))
        t.check(narrow.count <= 39, "fits 40 columns: \(narrow)")
        t.check(narrow.hasSuffix("…"), "cut")
        t.eq(plainText(renderSpinner(label: "checks", mode: .install, frame: 0)), "  ◐ Checked the release is the real thing")
    }

    t.test("check: the summary names the shells that found jebctl, and fails on any that did not") {
        t.eq(checkSummary([("zsh", .found), ("fish", .found)]), "ok (zsh, fish)")
        t.eq(checkSummary([("zsh", .found), ("nu", .unchecked)]), "ok (zsh; could not run nushell)")
        t.eq(checkSummary([("zsh", .found), ("fish", .missing)]), "not found by fish")
        t.eq(checkSummary([("nu", .unchecked)]), "skipped (could not run nushell)")
        t.eq(plainText(renderStep(label: "verify", text: "ok (zsh, fish)", mode: .install)), "  ✓ Checked your shells can find jebctl  zsh, fish")
        if case .failed = classifyStep("not found by fish") {} else { t.check(false, "a miss is a failure") }
        if case .skipped = classifyStep("skipped (could not run nushell)") {} else { t.check(false, "unchecked is skipped") }
    }

    t.test("reload: just the PATH line per shell, not the whole profile") {
        let names = ["HOME", "JEB_BIN_DIR"]
        let was = names.map { envVar($0) }
        defer { for (k, v) in zip(names, was) { setEnvVar(k, v) } }
        setEnvVar("HOME", "/Users/x")
        setEnvVar("JEB_BIN_DIR", nil)
        t.eq(reloadCommand("zsh"), "export PATH=\"$HOME/.local/bin:$PATH\"")
        t.eq(reloadCommand("bash"), "export PATH=\"$HOME/.local/bin:$PATH\"")
        t.eq(reloadCommand("fish"), "fish_add_path -g ~/.local/bin")
        t.eq(reloadCommand("nu"), "$env.PATH = ($env.PATH | split row (char esep) | prepend (\"~/.local/bin\" | path expand) | uniq)")
        t.eq(reloadCommand("sh"), nil)
        setEnvVar("JEB_BIN_DIR", "/opt/my bin")
        t.eq(reloadCommand("zsh"), "export PATH='/opt/my bin':\"$PATH\"", "a folder that needs it is shell-quoted")
        t.eq(reloadCommand("fish"), "fish_add_path -g '/opt/my bin'")
        setEnvVar("JEB_BIN_DIR", "/opt/bin")
        t.eq(reloadCommand("bash"), "export PATH=/opt/bin:\"$PATH\"")
        t.eq(reloadCommand("nu"), pathLine("nu"), "nushell's is the line pathLine writes")
    }

    t.test("reload: the shell is the nearest shell the install runs under, else the login shell, if it has the line") {
        t.eq(shellFromComm("-zsh"), "zsh")
        t.eq(shellFromComm("/opt/homebrew/bin/fish"), "fish")
        t.eq(shellFromComm("sh"), nil)
        t.eq(reloadShell(ancestors: ["sh", "-zsh", "login"], loginShell: "bash", ready: ["zsh", "bash"]), "zsh")
        t.eq(reloadShell(ancestors: ["sh", "fish"], loginShell: "zsh", ready: ["zsh"]), nil, "this window's shell was not set up")
        t.eq(reloadShell(ancestors: ["sh", "launchd"], loginShell: "zsh", ready: ["zsh"]), "zsh")
        t.eq(reloadShell(ancestors: [], loginShell: nil, ready: ["zsh"]), nil)
    }

    t.test("reload: c copies, enter, esc, q and ctrl-c finish, other keys wait") {
        t.eq(reloadKey([UInt8(ascii: "c")]), .copy)
        t.eq(reloadKey([UInt8(ascii: "C")]), .copy)
        for b: UInt8 in [0x0d, 0x0a, 0x1b, 0x03, UInt8(ascii: "q")] { t.eq(reloadKey([b]), .done) }
        t.eq(reloadKey([UInt8(ascii: "x")]), nil)
        t.eq(reloadKey([]), nil)
        t.eq(renderReload("source ~/.zprofile").map(plainText), ["", "  To use it in this window right away:", "    source ~/.zprofile"])
    }

    t.test("reload: a quiet run gives the exit status, and nil for a timeout or a missing program") {
        t.eq(runQuiet(["/usr/bin/true"], env: [:], timeout: 5), 0)
        t.eq(runQuiet(["/usr/bin/false"], env: [:], timeout: 5), 1)
        t.eq(runQuiet(["/bin/sleep", "5"], env: [:], timeout: 0.2), nil)
        t.eq(runQuiet(["/no/such/program"], env: [:], timeout: 1), nil)
    }
}
