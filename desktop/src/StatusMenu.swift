// The menu-bar item: Jeb's head (from the parsed art) and a small menu to manage
// the desktop. The app stays an accessory (no Dock icon). The menu is built each
// time it opens (menuNeedsUpdate), so nothing runs while it is closed.
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
        menu.addItem(action("Reload art", #selector(reloadArt)))
        menu.addItem(action("Save Screenshot", #selector(saveScreenshot)))
        menu.addItem(action("Restart", #selector(restart)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Jeb Desktop", #selector(quit)))
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

    // MARK: Actions

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
