// JebDesktop (Core Animation): Jeb's farm as a live desktop "wallpaper".
//
// One borderless window per screen and desktop Space, at the desktop window level,
// each holding a layer-hosting view with the scene's layer tree (FarmScene.swift).
// Each window belongs to its own Space (it does not join all Spaces), so it slides
// in and out with that Space exactly as the wallpaper does: macOS does not draw an
// all-Spaces window during a Space switch until the switch is over, which showed
// the real wallpaper for about half a second on every switch to the desktop
// (measured in the desktop-dive, phase 1). A desktop Space gets its windows on its
// first visit; full-screen Spaces get none. The scene is built at the art's native
// pixel size and scaled by a whole number, every layer filtered .nearest, so pixels
// stay crisp. Everything that moves is a Core Animation animation, played by the
// window server: the app does no per-frame work at all, and only wakes for a
// store or art change, the minute (the sky), a pass or one of Jeb's acts starting,
// a menu action or a notification.
//
// The data keeps it in step with the terminal band: the sprites, palette and font
// are parsed from the mod's hooks/pixel-art.ts as text (never executed;
// PixelArt.swift), and the farm and the running sessions from Jeb's store, of which
// only the `farm` and `live:*` keys are ever decoded (Store.swift, Farm.swift,
// Live.swift). All of it reloads on its own: the store within milliseconds of a
// write (a kqueue watch), the art when its file changes, and the app itself when
// its binary is rebuilt.
//
// Files: main.swift (entry point, windows, the one Story, pausing, reloads, stats),
// Store.swift, Farm.swift, Live.swift, Story.swift (which place, the trips and their
// lines), FarmScene.swift (the valley), Valley.swift, Strip.swift, Homestead.swift,
// Camp.swift, Road.swift, Cast.swift, Broadcast.swift (the Broadcast Window), Holiday.swift, Art.swift, PixelArt.swift, StatusMenu.swift, UpdateStatus.swift, JebLines.swift, BannerArt.swift and Banner.swift (Jeb's own notification banner), UpdateNotifier.swift, IconExport.swift, EmojiExport.swift,
// Heartbeat.swift (install hooks), Probe.swift, Bench.swift (also Save Screenshot's renderer; JEB_SHOT_DIR its folder).   Build: ./build.sh   Dev run: dev/run start
// JEB_MOD the mod folder (default the bundle's JebMod, else mod/ beside desktop/ from the executable); JEB_ART_PATH the art file (default the mod's); JEB_ICONSET=<dir> writes the app icon's .iconset PNGs there and exits (tools/bundle.sh; nothing else starts); JEB_EMOJI=<out.gif> writes a 128 px animated GIF of a sprite for a Slack custom emoji and exits (JEB_EMOJI_SPRITE default jeb-idle, JEB_EMOJI_ROWS top rows kept, default 20, 0 = all, JEB_EMOJI_DELAY seconds per frame, default jeb-idle's blink timing, else 0.5; JEB_HOLIDAY picks a variant; jebctl emoji); JEB_PID_FILE a file the running
// instance keeps its pid in. Banners (Banner.swift): JEB_NOTIFY_PREVIEW=1 shows one of every kind and exits (nothing else starts; no bundle needed); JEB_BANNER_CHECK=1 renders them all offscreen, checks the numbers and exits 0 or 1 (JEB_HOLIDAY adds the greeting and costumes); JEB_BANNER_SECONDS the dwell; JEB_BANNER_TEST=1 a test hook; JEB_BANNER=1 lets a raw binary show banners; JEB_REDUCE_MOTION=1 forces the fade-only entrance. JEB_NO_PAUSE=1 turns off the occlusion pause (for
// measuring); JEB_IDLE_SECONDS sets the idle pause (default 120 s without a change
// to what the farm shows); JEB_FPS the frame rate asked for while something passes
// on the road or in the sky (default 60), JEB_CALM_FPS otherwise (default 30);
// measuring only: JEB_FORCE_PAUSE=1; JEB_HOUR fixes the hour, JEB_NOW the clock (ms);
// JEB_HOLIDAY=<name>[,<name>...]|none forces holidays (a comma list for several at once) and their sprite variants (or turns them off; Holiday.swift; always off under JEB_BENCH unless forced);
// JEB_STORE_PATH another store (fixtures, the latency test); JEB_PLACE=home|<token> (with
// JEB_PLACE_SINCE seconds) where the story starts, JEB_STORY_SCALE=N story durations N times
// shorter, JEB_STORY_PATH another story.json (none is written under JEB_BENCH unless set). JEB_BROADCAST_ROWS the scene rows the Broadcast Window's view holds (default 96), JEB_BROADCAST_PAD the scene px kept clear around everything on stage (default 6), JEB_BROADCAST_LOG=1 logs its framing. JEB_SPACES=all goes back to one window
// joining every Space (the old behaviour, for comparison); JEB_PROBE=1 logs every
// Space, activation, occlusion, screen, sleep and lock notification with the
// render state (Probe.swift).

import AppKit
import QuartzCore

let env = ProcessInfo.processInfo.environment
let noPause = env["JEB_NO_PAUSE"] == "1"
// The mod: JEB_MOD, else the bundle's own JebMod (tools/bundle.sh writes it, so a hand-over started
// without launchd's environment finds it too), else mod/ beside desktop/ for a build in desktop/src.
let modDir = env["JEB_MOD"] ?? (Bundle.main.object(forInfoDictionaryKey: "JebMod") as? String).flatMap { $0.hasPrefix("/") ? $0 : nil }
    ?? (Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        .appendingPathComponent("../../mod").standardizedFileURL.path ?? "mod")
let artPath = env["JEB_ART_PATH"] ?? modDir + "/hooks/pixel-art.ts"
// The menu's settings, kept in UserDefaults ("com.jeb.desktop"); the env vars override.
// (as a bundle the suite name is the app's own id, which gives nil: the standard domain is the same one; JEB_DEFAULTS_SUITE names another suite, see Defaults.swift)
let settings = defaultsSuite(bundleId: Bundle.main.bundleIdentifier, env: env).flatMap { UserDefaults(suiteName: $0) } ?? UserDefaults.standard
enum Rate: String, CaseIterable { case adaptive = "Adaptive", sixty = "60 fps", thirty = "30 fps" }
var rate = Rate(rawValue: settings.string(forKey: "rate") ?? "") ?? .adaptive { didSet { settings.set(rate.rawValue, forKey: "rate"); applyRate() } }
var fps = 60, calmFps = 30 // while something passes / otherwise
var calmHz = 10.0 // the calm step clock's ticks a second
func applyRate() {
    fps = Int(env["JEB_FPS"] ?? "") ?? (rate == .thirty ? 30 : 60)
    calmFps = min(fps, Int(env["JEB_CALM_FPS"] ?? "") ?? (rate == .sixty ? 60 : 30))
    // Adaptive: calm motion steps ten times a second (the art's own frame timings
    // are tenths), passes at 60; otherwise everything at the chosen rate.
    calmHz = min(Double(calmFps), Double(env["JEB_CALM_HZ"] ?? "") ?? (rate == .adaptive ? 10 : Double(calmFps)))
}
applyRate()
let idleSeconds = Double(env["JEB_IDLE_SECONDS"] ?? "") ?? 120
let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
// Dive knobs (A/B variants): JEB_LEVEL = desktop (default) | desktop-1 | desktop+1 | desktopIcon-1 | backstop;
// JEB_SPACES = all (default: one window joining every Space) | all-nostationary | per (one window per
// desktop Space, created on first visit and kept there); JEB_REORDER = none (default) | front | back on
// each Space change; JEB_ANIM_NONE=1 animationBehavior .none.
let desktopLevel: NSWindow.Level = {
    let d = Int(CGWindowLevelForKey(.desktopWindow))
    switch env["JEB_LEVEL"] ?? "desktop" {
    case "desktop-1": return NSWindow.Level(rawValue: d - 1)
    case "desktop+1": return NSWindow.Level(rawValue: d + 1)
    case "desktopIcon-1": return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
    case "backstop": return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))
    default: return NSWindow.Level(rawValue: d)
    }
}()
let spacesMode = env["JEB_SPACES"] ?? "per"
let reorderMode = env["JEB_REORDER"] ?? "none"

func log(_ message: String) {
    FileHandle.standardError.write("[JebDesktop \(getpid())] \(message)\n".data(using: .utf8)!)
}

func modified(_ path: String) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
}

/// Whether the Space showing on a screen (any screen if nil) is a full-screen one:
/// the WindowManager's full-screen backdrop is on screen there. Measured: on the
/// owner's Mac the backdrop is on screen exactly while a full-screen Space shows.
func activeSpaceIsFullScreen(_ screen: NSScreen? = nil) -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return list.contains { w in
        guard (w[kCGWindowOwnerName as String] as? String) == "WindowManager", (w[kCGWindowName as String] as? String) == "Fullscreen Backdrop" else { return false }
        guard let screen, let b = w[kCGWindowBounds as String] as? [String: Double] else { return true }
        let f = screen.frame // CG bounds are top-left based, in the primary screen's coordinates
        let cg = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).intersects(cg.insetBy(dx: 1, dy: 1))
    }
}

// MARK: - Windows: one per screen and desktop Space, at the desktop level.

final class DesktopWindow {
    let screen: NSScreen
    let window: NSWindow
    let host: NSView
    let root = CALayer()
    var scene: FarmScene
    var stale = false // the store changed since this scene last heard (its Space is not showing)

    init(screen: NSScreen, art: Art, farm: Farm, live: [String: LiveRecord], story: Story) {
        self.screen = screen
        let layout = Layout(screen: screen)
        let sky = skyColours(hour: hourNow()).low
        let skyColour = NSColor(srgbRed: CGFloat(sky & 255) / 255, green: CGFloat(sky >> 8 & 255) / 255, blue: CGFloat(sky >> 16 & 255) / 255, alpha: 1)

        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        // Set before the window is first ordered in.
        switch spacesMode {
        case "per": window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenDisallowsTiling]
        case "all-nostationary": window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        default: window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        }
        if env["JEB_ANIM_NONE"] == "1" { window.animationBehavior = .none }
        window.isRestorable = false
        window.level = desktopLevel
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = skyColour // never the real wallpaper, even for a moment
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false

        // A layer-hosting view: the app owns the layer tree and AppKit never draws
        // into it. The root is the sky colour; the scene sits on it bottom-left.
        root.backgroundColor = skyColour.cgColor // not on screen yet: no implicit fade
        root.isOpaque = true
        host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.layer = root
        host.wantsLayer = true
        window.contentView = host
        scene = FarmScene(art: art, layout: layout, farm: farm, live: live, story: story, in: root)
        fit(layout)
        log("screen \(Int(screen.frame.width))x\(Int(screen.frame.height))pt @\(Int(screen.backingScaleFactor))x \(screen.maximumFramesPerSecond) Hz: scene \(layout.width)x\(layout.height) at \(layout.scale)x, insets bottom \(layout.bottom) left \(layout.left) right \(layout.right) top \(layout.top)")
        window.orderFrontRegardless()
    }

    /// Scales the scene into the window: layout.scale device pixels per scene
    /// pixel (a whole number), anchored bottom-left; the last part pixel at the
    /// top and right edges falls outside the window. Every layer samples its
    /// pixels .nearest, so the compositor keeps them crisp.
    func fit(_ layout: Layout) {
        let p = CGFloat(layout.scale) / screen.backingScaleFactor // points per scene pixel
        quiet {
            root.frame = NSRect(origin: .zero, size: screen.frame.size)
            scene.world.position = .zero
            scene.world.transform = CATransform3DMakeScale(p, p, 1)
        }
    }

    /// A new scene for new art, a moved Dock, the night or a new frame rate: built
    /// whole, then swapped in one transaction, so no frame is ever empty.
    func replaceScene(art: Art, layout: Layout? = nil) {
        let old = scene
        // One transaction: the new world goes in over the old and the old comes out
        // in the same frame.
        CATransaction.begin()
        scene = FarmScene(art: art, layout: layout ?? old.layout, farm: old.farm, live: old.live, story: old.story, in: root)
        if !old.running { scene.setRunning(false) }
        old.tearDown()
        quiet { old.world.removeFromSuperlayer() }
        fit(scene.layout)
        CATransaction.commit()
    }

    /// Rebuilds the scene if the Dock or menu bar moved (the visible frame changed).
    func relayoutIfNeeded(art: Art) {
        let layout = Layout(screen: screen)
        guard layout != scene.layout else { return }
        log("visible frame changed: insets bottom \(layout.bottom) left \(layout.left) right \(layout.right) top \(layout.top)")
        replaceScene(art: art, layout: layout)
    }

    /// Paused, the scene's clock stops and it keeps showing where it was.
    func setRunning(_ run: Bool) { scene.setRunning(run) }

    /// Back on its screen and level, only if it actually left them: it is
    /// stationary on its Space, so a Space change alone needs nothing (and
    /// re-ordering on every change could blink it).
    func reassertIfNeeded() {
        guard window.frame != screen.frame || window.level != desktopLevel || !window.isVisible else { return }
        log("window moved or hidden: re-asserting")
        window.setFrame(screen.frame, display: false)
        window.level = desktopLevel
        window.orderFrontRegardless()
    }

    var isShown: Bool { window.occlusionState.contains(.visible) }

    /// The Space changed: the ordering policy under test.
    func spaceChanged() {
        switch reorderMode {
        case "front": window.orderFrontRegardless()
        case "back": window.orderBack(nil)
        default: break
        }
    }

    /// Gone for good: the scene's callbacks stop, the layers go, the window closes.
    func tearDown() {
        scene.tearDown()
        quiet { scene.world.removeFromSuperlayer() }
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }
}

// MARK: - App: store and art polling, pausing, re-layout, self-reload, stats.

final class App {
    private(set) var art: Art
    let artSource: ArtSource
    private let source = StoreSource()
    /// The one story every window and screen draws from (Story.swift).
    let story = Story()
    private var watcher: StoreWatcher?
    private var latencyLog = env["JEB_LATENCY_LOG"] == "1"
    private(set) var windows: [DesktopWindow] = []
    private(set) var broadcast: BroadcastWindow?
    private(set) var pauseReason: String? // nil while running
    var manualPause = settings.bool(forKey: "paused") {
        didSet { settings.set(manualPause, forKey: "paused"); lastChange = Date(); updatePause() }
    }
    var broadcastFollow = settings.object(forKey: "broadcastFollow") == nil ? true : settings.bool(forKey: "broadcastFollow") {
        didSet { settings.set(broadcastFollow, forKey: "broadcastFollow"); broadcast?.follows = broadcastFollow }
    }
    private var lastChange = Date()
    private var asleep = false, locked = false
    private(set) var isRunning = true
    private var lastNight = isNightHour(Int(hourNow()))
    private var timers: [Timer] = []
    private var statsSince = Date()
    private var pausedSeconds = 0.0, pausedSince: Date?
    private var shownSeconds = 0.0, shownSince: Date? // for the stats: time the desktop was in view
    private let builtAt = modified(executablePath)
    private var seenBinary: Date?, triedBinary: Date?
    private var tookOver = false
    private let heartbeat = Heartbeat()
    /// The older instance this one takes over from: the one that started it, or (a start by the
    /// launch agent while another instance runs) the one with a heartbeat.
    private lazy var handoffFrom: Int32? = {
        if let from = env["JEB_HANDOFF_FROM"].flatMap(Int32.init), from > 1 { return from }
        return env["JEB_START"] == "launchd" ? otherInstance() : nil
    }()

    init(artSource: ArtSource, art: Art) { self.artSource = artSource; self.art = art }

    func start() {
        _ = source.refresh()
        story.noteAreas(source.areas)
        heartbeat.waiting = { [weak self] in !(self?.tookOver ?? true) }
        heartbeat.state = { [weak self] in (self?.isRunning ?? true, self?.pauseReason, self?.windows.map { $0.scene.sessionCount }.max() ?? 0) }
        heartbeat.start()
        story.ingest(live: source.live)
        story.onChange = { [weak self] in self?.storyChanged() }
        watcher = StoreWatcher(path: storePath) { [weak self] in self?.storeChanged(by: "watch") }
        watcher?.start()
        // Started while the screen is locked: the notifications only report changes.
        locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        if locked { log("screen is locked") }
        buildWindows()
        takeOver()
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            log("screen parameters changed")
            self?.buildWindows()
        }
        center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            // Shown again: resume first, then everything else.
            let shown = windows.contains(where: \.isShown)
            if shown { lastChange = Date() }
            updatePause()
            if shown, shownSince == nil { shownSince = Date() }
            if !shown, let since = shownSince { shownSeconds += Date().timeIntervalSince(since); shownSince = nil }
            log("occlusion: \(windows.map { $0.isShown ? "visible" : "occluded" }.joined(separator: ", "))")
        }
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            windows.forEach { $0.reassertIfNeeded(); $0.spaceChanged() }
            for w in windows where w.stale && w.window.isOnActiveSpace { w.scene.apply(farm: source.farm, live: source.live); w.stale = false }
            if spacesMode == "per" { addWindowsForActiveSpace() }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = true; self?.updatePause()
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = false; self?.lastChange = Date(); self?.updatePause()
        }
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = true; self?.updatePause()
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = false; self?.lastChange = Date(); self?.updatePause()
        }

        // Every 2 s: the store as a fallback to the watch (its mtime; re-read only on
        // change), the art file, and the app's own binary.
        every(2) { [self] in
            storeChanged(by: "poll")
            if artSource.refresh() { useNewArt() }
            // Waiting to take over and the older instance is gone (quit): so is this one.
            if !tookOver, let from = handoffFrom, kill(from, 0) != 0 {
                if env["JEB_HANDOFF_FROM"] == nil { // found by the launch agent, not started by it: just start fresh
                    log("handoff: the older instance exited; starting fresh")
                    handoffFrom = nil
                    takeOver()
                } else {
                    log("handoff: the older instance exited before the takeover; exiting too")
                    exit(0)
                }
            }
            checkBinary()
            updatePause()
        }
        // The Dock and menu bar every 3 s, in case no notification came.
        every(3) { [self] in windows.forEach { $0.relayoutIfNeeded(art: art) } }
        // The sky and the clock's things on the farm once a minute; a new scene when
        // night falls or ends. Paused or not: the layers show it either way.
        every(60) { [self] in
            let night = isNightHour(Int(hourNow()))
            let holidayChanged = art.refreshHoliday() // a holiday began or ended: new scenes and menu-bar head
            if holidayChanged { onArt?(art) }
            if night != lastNight || holidayChanged {
                lastNight = night
                windows.forEach { $0.replaceScene(art: art) }
                broadcast?.replaceScene(art: art)
            } else {
                story.ingest(live: source.live) // the clock's own decisions (night, a record gone stale)
                windows.forEach { $0.scene.minute() }
                broadcast?.scene.minute()
            }
            logStats()
        }
        if settings.bool(forKey: "broadcast") { openBroadcast(activate: false) }
    }

    /// The store changed (or may have): what the scenes draw from it, re-read and applied.
    private func storeChanged(by how: String) {
        // Paused because nothing can be seen (covered, asleep, locked, or by hand): the store
        // is not even read; the scenes catch up the moment they run again.
        if let reason = pauseReason, reason != "idle" { storePending = true; return }
        storePending = false
        let t0 = Date()
        let changed = source.refresh()
        guard changed.farm || changed.live || changed.areas else { return }
        if changed.areas { story.noteAreas(source.areas) }
        story.ingest(live: source.live)
        // The windows on the Spaces showing now get it at once; the others (each Space has its
        // own window and scene) catch up within a few seconds, or as soon as their Space shows.
        for w in windows {
            if w.window.isOnActiveSpace { w.scene.apply(farm: source.farm, live: source.live); w.stale = false } else { w.stale = true }
        }
        broadcast?.scene.apply(farm: source.farm, live: source.live)
        if windows.contains(where: \.stale), !catchUpPending {
            catchUpPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.catchUp() }
        }
        lastChange = Date()
        updatePause()
        if latencyLog, let mtime = source.mtime {
            CATransaction.flush()
            let first = watcher?.firstEventAt ?? t0
            log(String(format: "store %@: write->event %.1f ms, event->read %.1f ms, apply %.1f ms, write->commit %.1f ms", how,
                       first.timeIntervalSince(mtime) * 1000, t0.timeIntervalSince(first) * 1000, Date().timeIntervalSince(t0) * 1000, Date().timeIntervalSince(mtime) * 1000))
        }
    }

    /// The story moved on by itself (a deadline): the windows showing now redraw, the others when their Space shows.
    private func storyChanged() {
        if let reason = pauseReason, reason != "idle" { return } // paused scenes catch up from the story when they run again
        for w in windows {
            if w.window.isOnActiveSpace { w.scene.apply(farm: source.farm, live: source.live); w.stale = false } else { w.stale = true }
        }
        broadcast?.scene.apply(farm: source.farm, live: source.live)
        lastChange = Date()
    }

    private var catchUpPending = false
    private var storePending = false
    private func catchUp() {
        catchUpPending = false
        for w in windows where w.stale { w.scene.apply(farm: source.farm, live: source.live); w.stale = false }
    }

    private func every(_ seconds: TimeInterval, _ block: @escaping () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in block() }
        timer.tolerance = seconds / 10
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    /// Valid new art: new scenes, and a new menu-bar icon.
    func useNewArt() {
        guard let next = artSource.art else { return }
        art = next
        windows.forEach { $0.replaceScene(art: next) }
        broadcast?.replaceScene(art: next)
        lastChange = Date()
        onArt?(next)
    }
    var onArt: ((Art) -> Void)?

    /// Per-Space mode: a desktop Space visited for the first time gets its own windows
    /// (one per screen), which then stay on it and move with it like its wallpaper.
    /// Full-screen Spaces get none (macOS covers the desktop level there anyway).
    func addWindowsForActiveSpace() {
        // A removed Space's windows are moved onto another Space: keep one per screen there.
        for screen in NSScreen.screens {
            let here = windows.filter { $0.screen == screen && $0.window.isOnActiveSpace }
            for extra in here.dropFirst() {
                log("per-space: two windows on this Space; closing \(extra.window.windowNumber)")
                extra.tearDown(); windows.removeAll { $0 === extra }
            }
        }
        for screen in NSScreen.screens where !windows.contains(where: { $0.screen == screen && $0.window.isOnActiveSpace }) {
            guard !activeSpaceIsFullScreen(screen) else { probeLog("per-space: active Space is full screen; no window"); continue }
            let w = DesktopWindow(screen: screen, art: art, farm: source.farm, live: source.live, story: story)
            windows.append(w)
            takeOver()
            log("per-space: new window \(w.window.windowNumber) for this Space (\(windows.count) in all)")
            if !isRunning { w.setRunning(false) }
            lastChange = Date(); updatePause()
        }
    }

    // MARK: The Broadcast Window (Broadcast.swift): open state is kept in settings, so a reload or Restart reopens it.

    func toggleBroadcast() { broadcast == nil ? openBroadcast() : closeBroadcast() }

    func openBroadcast(activate: Bool = true) {
        guard broadcast == nil else { return }
        let b = BroadcastWindow(art: art, farm: source.farm, live: source.live, story: story, activate: activate, follows: broadcastFollow)
        b.onClose = { [weak self, weak b] in
            guard let self, let b, broadcast === b else { return }
            closeBroadcast()
        }
        broadcast = b
        settings.set(true, forKey: "broadcast")
        if !isRunning { b.setRunning(false) }
        lastChange = Date(); updatePause()
        log("broadcast window opened")
    }

    func closeBroadcast() {
        guard let b = broadcast else { return }
        broadcast = nil
        settings.set(false, forKey: "broadcast")
        b.tearDown()
        updatePause()
        log("broadcast window closed")
    }

    func buildWindows() {
        let farm = source.farm, live = source.live
        let old = windows
        // Per-Space mode started on a full-screen Space: the first desktop Space visited gets the windows.
        windows = spacesMode == "per" && activeSpaceIsFullScreen() ? [] : NSScreen.screens.map { DesktopWindow(screen: $0, art: art, farm: farm, live: live, story: story) }
        // After the new ones are up: the old go, with their scenes and drawables.
        old.forEach { $0.tearDown() }
        lastChange = Date()
        // New scenes start running; paused again at once if they should be (their
        // layers show their first state either way, so a window is never empty).
        if !isRunning { windows.forEach { $0.setRunning(false) } }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updatePause()
            if windows.contains(where: \.isShown), shownSince == nil { shownSince = Date() }
        }
    }

    /// Runs while awake and unlocked, while some window is visible (unless JEB_NO_PAUSE),
    /// and while the store changed in the last two minutes or a session is live (never idle while the Broadcast Window is shown).
    private func updatePause() {
        let idle = broadcast?.isShown != true && Date().timeIntervalSince(lastChange) > idleSeconds && !windows.contains { $0.scene.sessionCount > 0 }
        let covered = !noPause && !windows.contains(where: \.isShown) && broadcast?.isShown != true
        let forced = env["JEB_FORCE_PAUSE"] == "1" // measuring only: paused from the start
        let run = !manualPause && !forced && !asleep && !locked && !idle && !covered
        pauseReason = run ? nil : forced ? "forced" : manualPause ? "by you" : asleep ? "asleep" : locked ? "locked" : idle ? "idle" : "covered"
        guard run != isRunning else { return }
        if run { story.tick() } // it moved on while the scenes stood still: they resume from where it is now
        isRunning = run
        windows.forEach { $0.setRunning(run) }
        broadcast?.setRunning(run)
        if run && storePending { DispatchQueue.main.async { [weak self] in self?.storeChanged(by: "resume") } }
        if run, let since = pausedSince { pausedSeconds += Date().timeIntervalSince(since); pausedSince = nil }
        if !run { pausedSince = Date() }
        log(run ? "resumed" : "paused (\(pauseReason ?? ""))")    }

    // MARK: Self-reload: a rebuilt binary takes over without a gap

    /// When the binary changes (and has stayed the same for one poll, so the build
    /// is done), start it. The new process draws its windows on top of these, then
    /// stops this one (`takeOver`), so the desktop is never empty and only one
    /// instance is left. If the new one fails, this one carries on.
    private func checkBinary() {
        guard let now = modified(executablePath), now != builtAt, now != triedBinary else { seenBinary = nil; return }
        guard now == seenBinary else { seenBinary = now; return }
        triedBinary = now
        startSuccessor(because: "binary rebuilt")
    }

    /// Starts this binary again; the new process takes over once it has drawn.
    func startSuccessor(because why: String) {
        let next = Process()
        next.executableURL = URL(fileURLWithPath: executablePath)
        next.arguments = Array(CommandLine.arguments.dropFirst())
        var environment = env
        environment["JEB_HANDOFF_FROM"] = String(getpid())
        next.environment = environment
        next.terminationHandler = { p in log("new binary (pid \(p.processIdentifier)) exited with \(p.terminationStatus); carrying on") }
        do {
            try next.run()
            log("\(why): started pid \(next.processIdentifier) to take over")
        } catch {
            log("\(why) but could not start: \(error)")
        }
    }

    /// Started by an older instance: once this one has drawn, stop it, and take the pid file.
    /// Per-Space mode started on a full-screen Space has no window yet: the older
    /// instance keeps the desktop Space covered until this one has its own window
    /// there (addWindowsForActiveSpace calls this again), so a rebuild never leaves
    /// the desktop showing the wallpaper on the next visit.
    func takeOver() {
        guard !tookOver else { return }
        guard let from = handoffFrom else {
            tookOver = true
            if let file = env["JEB_PID_FILE"] { try? "\(getpid())\n".write(toFile: file, atomically: true, encoding: .utf8) }
            return
        }
        guard !windows.isEmpty else { log("handoff: waiting for a desktop Space before taking over"); return }
        tookOver = true
        if let file = env["JEB_PID_FILE"] { try? "\(getpid())\n".write(toFile: file, atomically: true, encoding: .utf8) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Only ever an older JebDesktop (this build or an earlier one).
            var buffer = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(from, &buffer, UInt32(buffer.count)) > 0,
                  (String(cString: buffer) as NSString).lastPathComponent == (executablePath as NSString).lastPathComponent else {
                log("handoff: pid \(from) is not an older JebDesktop; leaving it")
                return
            }
            kill(from, SIGUSR1) // "handed over"
            log("handoff: took over from pid \(from)")
        }
    }

    /// The live records now read from the store (the menu looks for a session with the creative drops off).
    var liveRecords: [LiveRecord] { Array(source.live.values) }
    /// Save Screenshot and SIGUSR2: the paths of the PNGs saved (Bench.swift).
    func screenshots() throws -> [String] { try saveScreenshots(art: art, farm: source.farm, live: source.live, story: story) }

    /// A new frame rate: new scenes, whose animations ask for it.
    func applyRateToViews() { windows.forEach { $0.replaceScene(art: art) }; broadcast?.replaceScene(art: art) }

    func logStats() {
        let paused = pausedSeconds + (pausedSince.map { Date().timeIntervalSince($0) } ?? 0)
        let shown = shownSeconds + (shownSince.map { Date().timeIntervalSince($0) } ?? 0)
        shownSeconds = 0
        if shownSince != nil { shownSince = Date() }
        for (i, w) in windows.enumerated() {
            let wakes = w.scene.wakes - (statsWakes[ObjectIdentifier(w.scene)] ?? 0)
            statsWakes[ObjectIdentifier(w.scene)] = w.scene.wakes
            let cast = w.scene.castCount
            log(String(format: "screen %d: place %@, queue %d, %d sessions, %d store reads, %d scene updates, %d scene wakes, %d layers animated; paused %.0f s, in view %.0f s, of %.0f s; cast %d Jeb, %d Blue (%d/%d in the tree), %d place roots",
                       i, w.scene.placeKind, w.scene.queueLength, w.scene.sessionCount, source.reads, w.scene.updates, wakes, w.scene.animatedLayers, paused, shown, Date().timeIntervalSince(statsSince),
                       cast.jeb, cast.blue, cast.jebAll, cast.blueAll, w.scene.placeCount.roots))
        }
        pausedSeconds = 0
        if pausedSince != nil { pausedSince = Date() }
        statsSince = Date()
    }
    private var statsWakes: [ObjectIdentifier: Int] = [:]
}

// MARK: - main

/// The menu of the waiting mode (no art yet): two status lines and Quit.
final class WaitingMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        item.button?.title = "Jeb"
        let menu = NSMenu()
        menu.autoenablesItems = false
        for line in ["Waiting for art: hooks/pixel-art.ts not found", "Run ./install again from the clone"] {
            let i = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Jeb Desktop", action: #selector(quitDesktop), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func quitDesktop() {
        log("menu: quit")
        writeQuitMarker() // as StatusMenu's quit
        unlink(heartbeatFile)
        exit(0)
    }
}

/// No usable art. A bench/gate run (JEB_BENCH) or a hand-over child (JEB_HANDOFF_FROM) exits 1, as the updater relies
/// on it; under launchd that would be a restart loop, so otherwise wait for the art and re-exec when it appears.
/// JEB_BENCH with JEB_ART_WAIT_TEST=<seconds> polls headless instead (a test of the wait: no window, heartbeat or exec).
func waitForArt() -> Never {
    if env["JEB_BENCH"] != nil {
        guard let limit = env["JEB_ART_WAIT_TEST"].flatMap(Double.init) else { exit(1) }
        let end = Date(timeIntervalSinceNow: limit)
        while Date() < end {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
            if artSource.refresh() { log("art wait test: art found"); exit(0) }
        }
        log("art wait test: timed out")
        exit(1)
    }
    if env["JEB_HANDOFF_FROM"] != nil { exit(1) }
    startedByLaunchd()
    NSApplication.shared.setActivationPolicy(.accessory)
    let menu = WaitingMenu()
    let beat = Heartbeat()
    beat.state = { (false, "no art", 0) }
    beat.start()
    log("waiting for art at \(artPath)")
    var signalSources: [DispatchSourceSignal] = []
    signal(SIGUSR2, SIG_IGN) // a screenshot request has nothing to draw here (and must not kill it)
    for sig in [SIGTERM, SIGINT, SIGUSR1] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            log("signal \(sig): exiting\(sig == SIGUSR1 ? " (handed over)" : "")")
            unlink(heartbeatFile)
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
    let poll = Timer(timeInterval: 30, repeats: true) { _ in
        guard artSource.refresh() else { return }
        log("art found; restarting")
        // Same pid, so the heartbeat file stays; the new image rewrites it.
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) } + [nil]
        execv(path, &argv)
        log("restart failed (exec: \(String(cString: strerror(errno)))); exiting")
        unlink(heartbeatFile)
        exit(1)
    }
    RunLoop.main.add(poll, forMode: .common)
    withExtendedLifetime((menu, beat, signalSources, poll)) { NSApplication.shared.run() }
    exit(0)
}

let artSource = ArtSource(path: artPath)
// Icon export (tools/bundle.sh): write the .iconset's PNGs and exit. Before everything else that starts the
// app (hand-over, windows, status item, timers, heartbeat), so it never touches a running instance.
if let dir = env["JEB_ICONSET"] {
    guard artSource.refresh(), let art = artSource.art else { log("icon export: no usable art at \(artPath)"); exit(1) }
    art.holidayNames = { [] } // the bundle's icon is always the base head
    if let problem = exportIconset(art: art, to: dir) { log("icon export: \(problem)"); exit(1) }
    exit(0)
}
// Banner check (JEB_BANNER_CHECK=1): offscreen and by numbers, nothing else starts.
if env["JEB_BANNER_CHECK"] == "1" {
    guard artSource.refresh(), let art = artSource.art else { log("banner check: no usable art at \(artPath)"); exit(1) }
    exit(bannerCheck(art: art))
}
// Emoji export (jebctl emoji): same place and rules as the icon export; nothing else starts.
if let out = env["JEB_EMOJI"] {
    guard artSource.refresh(), let art = artSource.art else { log("emoji export: no usable art at \(artPath)"); exit(1) }
    let sprite = env["JEB_EMOJI_SPRITE"] ?? "jeb-idle"
    let delay = env["JEB_EMOJI_DELAY"].map { Double($0) }    // nil: unset (the default timing); .some(nil): not a number
    guard let rows = env["JEB_EMOJI_ROWS"].map({ Int($0) }) ?? 20, delay.map({ ($0 ?? 0) > 0 }) ?? true
    else { log("emoji export: JEB_EMOJI_ROWS must be a whole number and JEB_EMOJI_DELAY a positive number of seconds"); exit(1) }
    if let problem = exportEmoji(art: art, sprite: sprite, rows: rows, delay: delay ?? nil, to: out, report: { frames, bytes in
        if frames == 1 { log("emoji export: \(sprite) has one frame, so the GIF is static") }
        log("emoji export: \(out), \(frames) frame(s), \(bytes) bytes")
        if bytes > 128 * 1024 { log("emoji export: warning, \(bytes) bytes is over Slack's 128 KB limit") }
    }) { log("emoji export: \(problem)"); exit(1) }
    exit(0)
}
// Banner preview (JEB_NOTIFY_PREVIEW=1): each kind of banner once, then exit; nothing else starts.
if env["JEB_NOTIFY_PREVIEW"] == "1" {
    guard artSource.refresh(), let art = artSource.art else { log("notify preview: no usable art at \(artPath)"); exit(1) }
    // Prohibited, not accessory: a process started from a shell is made frontmost when it finishes launching, which would
    // take the keyboard from the app being typed in. A banner never needs to be active.
    NSApplication.shared.setActivationPolicy(.prohibited)
    let notifier = UpdateNotifier(art: { art }, show: true)
    notifier.preview { exit(0) }
    NSApplication.shared.run()
}
guard artSource.refresh(), let art = artSource.art else {
    log("no usable art at \(artPath)")
    waitForArt()
}
if let seconds = env["JEB_BENCH"].flatMap(Double.init) { // measuring only: no window, see Bench.swift
    if env["JEB_STORY_AUDIT"] == "1" { let source = StoreSource(); _ = source.refresh(); Story.audit(art: art, areas: source.areas); exit(0) }
    if env["JEB_HEARTBEAT_TEST"] == "1" { // the install hooks only (Heartbeat.swift): no window, five seconds
        startedByLaunchd()
        let beat = Heartbeat(); beat.waiting = { env["JEB_HEARTBEAT_WAITING"] == "1" }; beat.start()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 5)); exit(0)
    }
    let source = StoreSource(); _ = source.refresh()
    runBench(seconds: seconds, art: art, farm: source.farm, live: source.live, areas: source.areas)
}
startedByLaunchd()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let desktop = App(artSource: artSource, art: art)
desktop.start()
if env["JEB_PROBE"] == "1" { desktop.startProbe() }
let statusMenu = StatusMenu(app: desktop)
desktop.onArt = { statusMenu.setIcon(art: $0) }
/// The banner's look: the farm's night and winter, and the area camp drawn on the main screen (none anywhere else).
func bannerLook() -> BannerLook {
    BannerLook.now(area: desktop.windows.first { $0.screen == NSScreen.main }?.scene.areaLook)
}
let updateNotifier = UpdateNotifier(art: { desktop.art }, look: bannerLook)
updateNotifier.start()
statusMenu.onSample = { updateNotifier.preview {} }
AgentHeal.atStartup()       // a release install's dropped agents are loaded again, off the main thread
log("started (occlusion pause \(noPause ? "off" : "on"), idle pause after \(Int(idleSeconds)) s, art \(artPath))")

/// Stops cleanly (SIGUSR1: a newer instance has taken over; the menu's Quit).
func shutDown() -> Never {
    unlink(heartbeatFile)
    desktop.logStats()
    exit(0)
}

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGUSR1] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        log("signal \(sig): exiting\(sig == SIGUSR1 ? " (handed over)" : "")")
        shutDown()
    }
    source.resume()
    signalSources.append(source)
}

// SIGUSR2 (`jebctl screenshot`): save like the menu, then list the paths in JEB_HOME/screenshot-last (tmp + rename).
signal(SIGUSR2, SIG_IGN)
let shotSource = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
shotSource.setEventHandler {
    do {
        let paths = try desktop.screenshots()
        ensurePrivateDir(jebHome)
        writePrivate(paths.joined(separator: "\n") + "\n", to: jebHome + "/screenshot-last")
        log("signal: screenshot saved \(paths.count) file(s)")
    } catch { log("signal: screenshot failed: \(error)") }
}
shotSource.resume()
signalSources.append(shotSource)

app.run()
