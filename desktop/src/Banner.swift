// Jeb's own banner, in place of a macOS notification: a small pixel-art card at the top right of the main screen (BannerArt.swift
// draws it). A non-activating panel above the menu bar's level on every Space and over full-screen apps, so it never takes
// focus, never makes Jeb the active app and needs no permission. One shows at a time from a first-in-first-out queue; a click, a
// swipe or a VoiceOver press dismisses it, hovering keeps it, and it waits (never drops) while the screens are asleep or locked, a
// screensaver runs, the session is inactive or a display is mirrored. Sound is Pop, off unless the menu turns it on.
//
// macOS Focus (Do Not Disturb) has no public API without entitlements, so a banner ignores it. Screen sharing cannot be detected
// publicly either, so the panel keeps the default sharing type and a shared screen shows it.
//
// JEB_BANNER_SECONDS sets the dwell; JEB_REDUCE_MOTION=1 forces the fade-only entrance (as the Reduce Motion setting does).
// JEB_BANNER_TEST=1 (testing only) listens for the distributed notification com.jeb.desktop.banner-test, whose object is
// enter | exit | click | swipe | lock | unlock | state: it acts as a hover, a click, a swipe or a lock would and logs the queue,
// the timer, whether Jeb is the active app and which app is frontmost.

import AppKit
import QuartzCore

final class BannerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        worksWhenModal = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false       // the card draws its own hard pixel shadow
        isMovable = false
        isRestorable = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }
}

/// The card's view: a layer for the chrome and one for the sprite; a click, a horizontal swipe or a press dismisses.
final class BannerView: NSView {
    var onDismiss: ((String) -> Void)?
    var onHover: ((Bool) -> Void)?
    var label = ""
    private var swipe: CGFloat = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onDismiss?("click") }
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin { swipe = 0 }
        swipe += event.scrollingDeltaX
        if abs(swipe) > 20 { swipe = 0; onDismiss?("swipe") }
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { label }
    override func accessibilityPerformPress() -> Bool { onDismiss?("press"); return true }
}

final class Banner: NSObject, NSWindowDelegate {
    private let art: () -> Art?
    private let look: () -> BannerLook
    var onIdle: (() -> Void)?

    private var queue: [(note: Note, id: String)] = []
    private var current: (note: Note, id: String)?
    private var panel: BannerPanel?
    private let view = BannerView(frame: NSRect(x: 0, y: 0, width: BannerLayout.winW * BannerLayout.u, height: BannerLayout.winH * BannerLayout.u))
    private let chromeLayer = CALayer(), spriteLayer = CALayer()
    private var screen: NSScreen?
    private var timer: Timer?
    private var deadline = Date()
    private var hovering = false
    private var leaving = false, gap = false
    private var generation = 0
    private var holds = Set<String>()
    private var resume: DispatchWorkItem?
    private let testing = env["JEB_BANNER_TEST"] == "1"
    private static let maxWaiting = 8

    init(art: @escaping () -> Art?, look: @escaping () -> BannerLook) {
        self.art = art
        self.look = look
        super.init()
        view.wantsLayer = true
        view.layer?.addSublayer(chromeLayer)
        view.layer?.addSublayer(spriteLayer)
        for l in [chromeLayer, spriteLayer] { l.magnificationFilter = .nearest; l.minificationFilter = .nearest }
        view.onDismiss = { [weak self] why in self?.dismiss(why) }
        view.onHover = { [weak self] on in self?.hover(on) }
        watchHolds()
        if testing { watchTest() }
    }

    // MARK: Showing

    /// Queues a banner (shows it at once when nothing else is up). The same id as a waiting one replaces it; as the showing one,
    /// redraws it and restarts its timer.
    func show(_ note: Note, id: String) {
        if current?.id == id {
            current = (note, id)
            render(note)
            startTimer(dwell(note))
            log("banner: refresh [\(id)]")
            return
        }
        if let i = queue.firstIndex(where: { $0.id == id }) { queue[i] = (note, id) }
        else {
            if queue.count >= Banner.maxWaiting { log("banner: queue full, dropped [\(queue[0].id)]"); queue.removeFirst() }
            queue.append((note, id))
        }
        pump()
    }

    func dismiss(_ why: String) {
        guard let c = current, !leaving else { return }
        log("banner: dismiss [\(c.id)] (\(why))")
        timer?.invalidate()
        spriteLayer.removeAllAnimations()
        current = nil
        leaving = true
        generation += 1
        let mine = generation
        guard let panel = panel else { finishLeaving(mine); return }
        let to = panel.frame.offsetBy(dx: reduceMotion ? 0 : 24, dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.15 : 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if !reduceMotion { panel.animator().setFrame(to, display: true) }
        }, completionHandler: { [weak self] in self?.finishLeaving(mine) })
    }

    private func finishLeaving(_ mine: Int) {
        guard mine == generation else { return }
        panel?.orderOut(nil)
        leaving = false
        gap = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            self.gap = false
            if self.queue.isEmpty { self.onIdle?() } else { self.pump() }
        }
    }

    private func pump() {
        guard current == nil, !leaving, !gap, holds.isEmpty, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        guard art() != nil else { log("banner: no art, skipped [\(next.id)]"); pump(); return }
        guard let target = NSScreen.main ?? NSScreen.screens.first else {
            log("banner: no screen, will retry")
            queue.insert(next, at: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.pump() }
            return
        }
        current = next
        screen = target
        hovering = false
        let p = panel ?? BannerPanel(size: view.frame.size)
        if panel == nil { panel = p; p.contentView = view; p.delegate = self }
        let backing = render(next.note)
        let frame = place(on: target)
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        generation += 1
        if reduceMotion {
            log("banner: reduce motion, fade only")
            p.setFrame(frame, display: false)
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15; p.animator().alphaValue = 1 }
        } else {
            p.setFrame(frame.offsetBy(dx: 24, dy: 0), display: false)
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().setFrame(frame, display: true)
                p.animator().alphaValue = 1
            }
        }
        log("banner: show [\(next.id)] screen \(target.localizedName) frame \(NSStringFromRect(frame)) backing \(backing) k \(BannerLayout.u * backing)")
        if testing { log("banner test: frontmost \(before) -> \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"), NSApp.isActive \(NSApp.isActive)") }
        if next.note.sound, NotifyPrefsFile.load().sound, !activeSpaceIsFullScreen(target) { NSSound(named: "Pop")?.play() }
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: view.label, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        startTimer(dwell(next.note))
    }

    /// Draws the chrome and the sprite for `note` at the current screen's backing scale; returns that scale.
    @discardableResult
    private func render(_ note: Note) -> Int {
        guard let a = art() else { return 1 }
        let backing = max(1, Int((panel?.backingScaleFactor ?? screen?.backingScaleFactor ?? 2).rounded()))
        let look = self.look()
        let dark = look.dark(NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let c = BannerArt.chrome(note, art: a, backing: backing, dark: dark, contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast, look: look)
        view.label = [note.title, note.subtitle, note.body.replacingOccurrences(of: "\n", with: " ")].filter { !$0.isEmpty }.joined(separator: ". ")
        let scale = CGFloat(backing)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chromeLayer.frame = view.bounds
        chromeLayer.contentsScale = scale
        chromeLayer.contents = c.image
        let s = BannerArt.sprite(note.sprite, art: a, still: reduceMotion)
        spriteLayer.removeAllAnimations()
        if let first = s.frames.first {
            spriteLayer.isHidden = false
            spriteLayer.frame = BannerLayout.spriteRect(width: first.width, rows: s.rows)
            spriteLayer.contentsScale = scale
            spriteLayer.contents = first
            if s.frames.count > 1 && s.seconds.count == s.frames.count {
                let total = s.seconds.reduce(0, +)
                var t = 0.0
                let anim = CAKeyframeAnimation(keyPath: "contents")
                anim.values = s.frames
                anim.keyTimes = [NSNumber(value: 0)] + s.seconds.map { t += $0; return NSNumber(value: t / total) }
                anim.calculationMode = .discrete
                anim.duration = total
                anim.repeatCount = .infinity
                spriteLayer.add(anim, forKey: "flipbook")
            }
        } else { spriteLayer.isHidden = true }
        CATransaction.commit()
        return backing
    }

    /// The card's top-right 16 pt in from the screen's usable right edge and 10 pt below its top, on whole points.
    private func place(on screen: NSScreen) -> NSRect {
        let vis = screen.visibleFrame, size = view.frame.size, card = CGFloat(BannerLayout.cardW * BannerLayout.u)
        return NSRect(x: (vis.maxX - 16 - card).rounded(), y: (vis.maxY - 10 - size.height).rounded(), width: size.width, height: size.height)
    }

    func windowDidChangeBackingProperties(_ notification: Notification) { if let c = current { render(c.note) } }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || env["JEB_REDUCE_MOTION"] == "1" }

    // MARK: Timer and hover

    /// 5 s plus 1 s per 30 characters, at most 10 s, plus 4 s with VoiceOver on; JEB_BANNER_SECONDS overrides.
    private func dwell(_ note: Note) -> TimeInterval {
        if let s = env["JEB_BANNER_SECONDS"].flatMap(Double.init) { return s }
        return min(10, 5 + Double((note.subtitle + note.body).count) / 30) + (NSWorkspace.shared.isVoiceOverEnabled ? 4 : 0)
    }

    private func startTimer(_ seconds: TimeInterval) {
        timer?.invalidate()
        deadline = Date().addingTimeInterval(seconds)
        guard !hovering else { return }
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.dismiss("timeout") }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Hovering holds the banner; on exit it stays at least 2 s more.
    private func hover(_ on: Bool) {
        guard current != nil else { return }
        hovering = on
        if on { timer?.invalidate(); timer = nil }
        else { startTimer(max(2, deadline.timeIntervalSinceNow)) }
    }

    // MARK: Holds

    private func setHold(_ name: String, _ on: Bool) {
        if on {
            guard holds.insert(name).inserted else { return }
            log("banner: hold (\(name))")
            resume?.cancel()
            putAway()
        } else {
            guard holds.remove(name) != nil else { return }
            log("banner: release (\(name))")
            guard holds.isEmpty else { return }
            resume?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.pump() }
            resume = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    /// A showing banner goes off the screen at once and back to the front of the queue.
    private func putAway() {
        guard let c = current else { return }
        timer?.invalidate()
        spriteLayer.removeAllAnimations()
        generation += 1
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        current = nil
        queue.insert(c, at: 0)
    }

    private func watchHolds() {
        let ws = NSWorkspace.shared.notificationCenter, dc = DistributedNotificationCenter.default()
        func on(_ center: NotificationCenter, _ name: NSNotification.Name, _ hold: String, _ value: Bool) {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.setHold(hold, value) }
        }
        on(ws, NSWorkspace.screensDidSleepNotification, "screens asleep", true)
        on(ws, NSWorkspace.screensDidWakeNotification, "screens asleep", false)
        on(ws, NSWorkspace.sessionDidResignActiveNotification, "session inactive", true)
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification, "session inactive", false)
        on(dc, .init("com.apple.screenIsLocked"), "locked", true)
        on(dc, .init("com.apple.screenIsUnlocked"), "locked", false)
        on(dc, .init("com.apple.screensaver.didstart"), "screensaver", true)
        on(dc, .init("com.apple.screensaver.didstop"), "screensaver", false)
        if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true { holds.insert("locked") }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.screensChanged() }
        screensChanged()
    }

    /// Mirroring holds; a showing banner whose screen is gone moves to the new main screen, else it is placed again.
    private func screensChanged() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        setHold("mirrored display", ids.prefix(Int(n)).contains { CGDisplayIsInMirrorSet($0) != 0 })
        guard current != nil, let p = panel else { return }
        if let s = screen, !NSScreen.screens.contains(s) { screen = NSScreen.main ?? NSScreen.screens.first }
        if let s = screen { p.setFrame(place(on: s), display: true) }
    }

    // MARK: Testing

    private func watchTest() {
        DistributedNotificationCenter.default().addObserver(forName: .init("com.jeb.desktop.banner-test"), object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            switch note.object as? String {
            case "enter": self.hover(true)
            case "exit": self.hover(false)
            case "click": self.dismiss("click")
            case "swipe": self.dismiss("swipe")
            case "lock": self.setHold("locked", true)
            case "unlock": self.setHold("locked", false)
            default: break
            }
            log("banner test: showing \(self.current?.id ?? "none") waiting \(self.queue.map { $0.id }) timer \(self.timer?.isValid == true) hovering \(self.hovering) holds \(self.holds.sorted()) NSApp.isActive \(NSApp.isActive) frontmost \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")")
        }
        log("banner test hook on")
    }
}
