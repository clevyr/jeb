// The menu-bar item: Jeb's head (from the parsed art) and a small menu to manage
// the desktop. The app stays an accessory (no Dock icon). The menu is built each
// time it opens (menuNeedsUpdate), so nothing runs while it is closed.
//
// "Check for Updates" starts the update agent of the install mode (jebHome/install-mode: release runs
// `jebctl follow`, dev the updater) with `launchctl kickstart`; the agents do the work and keep every gate.
// A click first writes jebHome/check-now (the agents skip the quiet wait for it). Above the item an info line: the last
// result from jebHome/update-status.json ("Up to date · 14:02", "Update failed: ..."), else the last release tag and when it
// was checked (release-state.json), or the build stamp. The item reads "Update in Progress — <phase> (i of n), <elapsed>"
// while that agent's lock is held (a check, a build or the watch after a swap), "Update taking longer than expected" after
// 30 min, "Checking for Updates…" for up to 60 s after a click until a status appears (then "Couldn't start the update"),
// and "Updates Paused" with jebHome/updates-paused. Both lines refresh every second while the menu is open (UpdateStatus.swift
// holds the pure logic). The whole block is left out when the agent's plist is not installed (JEB_LAUNCHAGENTS overrides ~/Library/LaunchAgents).
//
// JEB_MENU_TEST=1 (testing only) also listens for the distributed notification
// "com.jeb.desktop.menu-test" whose object is a menu item's title: the item's
// action runs as if chosen, and the menu's state is logged. "status" only logs;
// "icon" writes the icon over light and dark backgrounds to JEB_MENU_TEST_DIR.

import AppKit

final class StatusMenu: NSObject, NSMenuDelegate {
    private let app: App
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var infoItem: NSMenuItem?
    private var checkItem: NSMenuItem?
    private var agent: (mode: String, label: String, lock: String)?
    private var clickedAt: Double?
    private var refreshTimer: Timer?

    init(app: App) {
        self.app = app
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        setIcon(art: app.art)
        if env["JEB_MENU_TEST"] == "1" {
            DistributedNotificationCenter.default().addObserver(forName: .init("com.jeb.desktop.menu-test"), object: nil, queue: .main) { [weak self] note in
                self?.test(note.object as? String ?? "")
            }
            log("menu test hook on")
        }
    }

    /// Jeb's head, hat to beard: the top 20 rows of his idle sprite (the band's
    /// jebHead box), one point per art pixel, in his own colours. 1x and 2x
    /// bitmaps, both whole-number scaled, so it is crisp either way.
    func setIcon(art: Art) {
        guard let button = item.button else { return }
        let reps = [1, 2].compactMap { k in art.image("jeb-idle", rows: 20, scale: k).map(NSBitmapImageRep.init(cgImage:)) }
        guard reps.count == 2 else {
            button.image = nil
            button.title = "Jeb"
            return
        }
        let image = NSImage(size: NSSize(width: 20, height: 20))
        reps.forEach { $0.size = image.size; image.addRepresentation($0) }
        image.isTemplate = false
        button.image = image
        button.imageScaling = .scaleNone
        button.title = ""
        button.toolTip = "Jeb Desktop"
    }

    // MARK: The menu, built on open

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(action(app.manualPause ? "Resume" : "Pause", #selector(togglePause)))

        let rates = NSMenu()
        for r in Rate.allCases {
            let entry = action(r.rawValue, #selector(chooseRate(_:)))
            entry.state = r == rate ? .on : .off
            entry.representedObject = r.rawValue
            rates.addItem(entry)
        }
        menu.addItem(submenu("Frame rate", rates))

        menu.addItem(.separator())
        agent = updateAgent()
        infoItem = nil
        checkItem = nil
        if let agent = agent {
            let info = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            let check = action("Check for Updates", #selector(checkForUpdates))
            check.representedObject = agent.label
            menu.addItem(check)
            menu.addItem(.separator())
            infoItem = info
            checkItem = check
            refreshUpdateItems()
        }
        menu.addItem(action("Reload art", #selector(reloadArt)))
        menu.addItem(action("Save Screenshot", #selector(saveScreenshot)))
        menu.addItem(action("Restart", #selector(restart)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Jeb Desktop", #selector(quit)))
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshTimer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshUpdateItems() }
        RunLoop.main.add(t, forMode: .common)       // .common includes event tracking: the menu is open
        refreshTimer = t
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self
        return entry
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = sub
        return entry
    }

    private func statusLine() -> String {
        if let reason = app.pauseReason { return "Paused — \(reason)" }
        return rate == .adaptive ? "Running · up to \(calmFps) fps calm, \(fps) passing (adaptive)" : "Running · up to \(fps) fps"
    }

    // MARK: Updates

    /// The install mode's update agent, or nil when its plist is not installed (a bare run-live.sh instance).
    private func updateAgent() -> (mode: String, label: String, lock: String)? {
        let mode = ((try? String(contentsOfFile: jebHome + "/install-mode", encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let release = mode == "release"
        let label = release ? "com.jeb.desktop.release" : "com.jeb.desktop.update"
        let agents = env["JEB_LAUNCHAGENTS"] ?? NSHomeDirectory() + "/Library/LaunchAgents"
        guard FileManager.default.fileExists(atPath: "\(agents)/\(label).plist") else { return nil }
        return (release ? "release" : "dev", label, release ? "release.lock" : "updater.lock")
    }

    /// Re-derives the info and action lines in place (the open menu is never rebuilt).
    private func refreshUpdateItems() {
        guard let agent = agent, let info = infoItem, let check = checkItem else { return }
        let status = (try? Data(contentsOf: URL(fileURLWithPath: jebHome + "/update-status.json"))).flatMap(UpdateStatus.parse)
        let lines = UpdateText.lines(status: status, lockHeld: lockHeld(jebHome + "/" + agent.lock), paused: FileManager.default.fileExists(atPath: jebHome + "/updates-paused"),
                                     clickedAt: clickedAt, now: Date().timeIntervalSince1970)
        info.title = lines.info ?? updateInfoLine(agent.mode)
        check.title = lines.action
        check.isEnabled = lines.enabled
    }

    private func updateInfoLine(_ mode: String) -> String {
        guard mode == "release" else { return "Dev build \(buildStamp)" }
        let state = (try? Data(contentsOf: URL(fileURLWithPath: jebHome + "/release-state.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let last = state?["last"] as? [String: Any]
        let tag = last?["result"] as? String == "ok" ? last?["tag"] as? String : nil
        var line = "Version \(tag ?? "unknown")"
        if let checked = (state?["checked"] as? NSNumber)?.doubleValue {
            let minutes = max(0, Int((Date().timeIntervalSince1970 - checked) / 60))
            line += " · checked " + (minutes < 1 ? "just now" : minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) h ago")
        }
        return line
    }

    /// True when another process holds the lock (a non-blocking flock, released at once; a missing file is not held).
    private func lockHeld(_ path: String) -> Bool {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }

    // MARK: Actions

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }
        let target = "gui/\(getuid())/\(label)"
        log("menu: check for updates (\(label))")
        clickedAt = Date().timeIntervalSince1970
        FileManager.default.createFile(atPath: jebHome + "/check-now", contents: nil, attributes: [.posixPermissions: 0o600])       // the agents skip the quiet wait for it
        if env["JEB_MENU_TEST"] == "1" {
            log("menu: would kickstart \(target)")
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", target]
        task.terminationHandler = { p in log("menu: kickstart \(target) exited \(p.terminationStatus)") }
        do { try task.run() } catch { log("menu: kickstart failed: \(error)") }
    }

    @objc private func togglePause() {
        app.manualPause.toggle()
        log(app.manualPause ? "menu: paused" : "menu: resumed")
    }

    @objc private func chooseRate(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let r = Rate(rawValue: value) else { return }
        rate = r
        app.applyRateToViews()
        log("menu: frame rate \(r.rawValue) (\(fps) moving, \(calmFps) calm)")
    }

    @objc private func reloadArt() {
        if app.artSource.reload() { app.useNewArt(); log("menu: art reloaded") } else { log("menu: art not reloaded (see above)") }
    }

    @objc private func saveScreenshot() {
        do {
            let paths = try app.screenshots()
            log("menu: screenshot saved \(paths.count) file(s)")
            if let last = paths.last { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: last)]) }
        } catch { log("menu: screenshot failed: \(error)") }
    }

    @objc private func restart() {
        app.startSuccessor(because: "menu: restart")
    }

    @objc private func quit() {
        log("menu: quit")
        writeQuitMarker() // the watchdog starts nothing until a login or `jebctl start` clears it
        shutDown() // exit 0: a launch agent with KeepAlive SuccessfulExit=false leaves it quit
    }

    // MARK: Testing

    private func test(_ title: String) {
        menuNeedsUpdate(menu)
        func describe(_ m: NSMenu, _ indent: String = "") -> [String] {
            m.items.flatMap { i -> [String] in
                guard !i.isSeparatorItem else { return [] }
                return ["\(indent)\(i.state == .on ? "✓ " : "")\(i.title)\(i.isEnabled ? "" : " (disabled)")"] + (i.submenu.map { describe($0, indent + "  ") } ?? [])
            }
        }
        log("menu test: \(describe(menu).joined(separator: " | "))")
        log("menu test: item visible \(item.isVisible), button frame on screen \(item.button?.window.map { NSStringFromRect($0.frame) } ?? "none")")
        if title == "icon", let dir = env["JEB_MENU_TEST_DIR"], let image = item.button?.image {
            for (name, colour) in [("light", NSColor(white: 0.93, alpha: 1)), ("dark", NSColor(white: 0.16, alpha: 1))] {
                let out = NSImage(size: NSSize(width: 60, height: 24))
                out.lockFocus()
                colour.setFill()
                NSRect(x: 0, y: 0, width: 60, height: 24).fill()
                NSGraphicsContext.current?.imageInterpolation = .none
                image.draw(in: NSRect(x: 20, y: 2, width: 20, height: 20))
                out.unlockFocus()
                if let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/icon-\(name).png"))
                }
            }
            log("menu test: icon written")
            return
        }
        func find(_ m: NSMenu) -> NSMenuItem? {
            for i in m.items {
                if i.title == title { return i }
                if let hit = i.submenu.flatMap(find) { return hit }
            }
            return nil
        }
        guard let hit = find(menu), let selector = hit.action else { return }
        NSApp.sendAction(selector, to: hit.target, from: hit)
    }
}
