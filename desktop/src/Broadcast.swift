// The Broadcast Window: an ordinary titled window showing the live farm scene, for Google Meet's
// "Present -> A window" (the desktop windows sit at the desktop level and cannot be picked).
//
// The tree is root (opaque, the sky colour) -> camera -> the FarmScene's world. The scene is built at a
// fixed size (1280x720 pt at 2x, no Dock or menu-bar insets), whatever the window's size; the window is a
// camera onto it, filling the whole window (full-size content view, transparent title bar; its frame is
// remembered as "JebBroadcast"). The camera is its own layer, not under the world's clock, so it keeps moving
// while the scene is paused. Its sublayerTransform is translate(-x, -y) in scene pixels then scale(p); the
// world's own transform and position stay FarmScene's. p = whole device pixels per scene pixel s / backingScaleFactor,
// so every pixel stays crisp; offsets are whole scene pixels, so whole device pixels too.
//
// Framing: everything on stage stays in frame. The subjects are every shown layer (not hidden, presentation opacity
// > 0, through its ancestors) that is a Strip part tagged (KVC "jebPart") jeb, blue, pup, bubble, events, trucks,
// truck, visit, walk, hands or fire, or named "jeb-"/"blue-" (the calm home pair); each counts as the union of its own
// and its shown descendants' presentation bounds, in world coordinates, so moving trucks and walks count, cut to the world (a truck parked off its edge is not on
// stage). Their union plus JEB_BROADCAST_PAD (default 6) scene px a side is the box; no subject: the stage strip's rect
// on a first fit, and otherwise the shot holds (a place fading in starts at opacity 0). s is the largest
// whole number in [s_min, s_max] at which the box fits the view: s_max = floor(window px height / JEB_BROADCAST_ROWS,
// default 96) is the tightest, s_min the largest whole s that fits the whole strip's width, both at least 1. The view's
// bottom sits 4 rows below the road (ground near the bottom edge) unless the box reaches lower; x centres the box,
// clamped to the scene. camX/camY/s are the target; the camera shows a current (x, y, ln s) that a 60 Hz Timer, running
// only while they differ, moves to it with a critically damped spring (SmoothDamp, per-axis velocity, ~0.35 s; ~0.2 s
// taking in something outside the view, ~0.6 s zooming in), so a moving subject is tracked without stopping; within a
// quarter pixel and all but stopped it snaps exactly to the target and stops.
// Every 0.25 s (only while the window is open and not miniaturized): anything of the box outside the view zooms out or
// pans at once (the target changes at once); a tighter s is taken only after fitting for 2.5 s running, never within
// 6 s of a zoom-out, and at most to twice the current s; a box fully inside but its centre over 20% of the view's width
// off-centre for 1.5 s running pans; else nothing moves. With follows off the target is the whole stage, fixed. First
// fit, a resize, a backing change, a deminiaturize, a new scene and the follow toggle jump without moving. JEB_BROADCAST_LOG=1
// logs "broadcast: box ... clipped" on a changed target or a clipped poll, and "broadcast: clipped [parts]" once a
// second while the shown view cuts a subject (once settled or 0.7 s after the target changed). Meet captures a
// window even when covered, so isShown ignores occlusion.

import AppKit
import QuartzCore

final class BroadcastWindow: NSObject, NSWindowDelegate {
    static let size = CGSize(width: 1280, height: 720) // the scene's size in points, at 2x
    let window: NSWindow
    let host: NSView
    let root = CALayer()
    let camera = CALayer()
    private(set) var scene: FarmScene
    var onClose: (() -> Void)?
    /// Whether the view tracks the action; off, it holds a fixed wide shot of the whole stage.
    var follows: Bool { didSet { if follows != oldValue { fit() } } }
    private let rows = max(8, Int(env["JEB_BROADCAST_ROWS"] ?? "") ?? 96)
    private let pad = CGFloat(max(0, Int(env["JEB_BROADCAST_PAD"] ?? "") ?? 6))
    private let logging = env["JEB_BROADCAST_LOG"] == "1"
    private static let actors: Set<String> = ["jeb", "blue", "pup", "bubble", "events", "trucks", "truck", "visit", "walk", "hands", "fire"]
    private var camX: CGFloat = 0, camY: CGFloat = 0 // the model's view origin, scene pixels
    private var viewW: CGFloat = 1, viewH: CGFloat = 1 // the view's size, scene pixels
    private var scale: CGFloat = 1 // points per scene pixel
    private var device = 1 // whole device pixels per scene pixel
    private var zoomInSince: Date?, tighter = 0 // a tighter scale that has fit since then (the loosest such)
    private var lastZoomOut = Date.distantPast, offSince: Date? // the last zoom-out; since when the box centre has been off-centre
    private var aimed = (x: CGFloat(0), y: CGFloat(0), s: 0), lastAim = Date.distantPast // the last target, and when it changed
    private var quick = false // the target takes in something outside the view: the faster spring
    private var curX: CGFloat = 0, curY: CGFloat = 0, curLog: CGFloat = 0 // what the camera shows: view origin, ln(points per scene pixel)
    private var velX: CGFloat = 0, velY: CGFloat = 0, velLog: CGFloat = 0
    private var lastTick = 0.0
    private var motion: Timer? // runs only while the current differs from the target
    private var lastTarget = "", lastClipLog = Date.distantPast
    private var timer: Timer?
    private var closing = false

    private static func layout() -> Layout {
        let r = CGRect(origin: .zero, size: size)
        return Layout(frame: r, visible: r, backing: 2)
    }

    init(art: Art, farm: Farm, live: [String: LiveRecord], story: Story, activate: Bool, follows: Bool = true) {
        self.follows = follows
        let sky = skyColours(hour: hourNow()).low
        let skyColour = NSColor(srgbRed: CGFloat(sky & 255) / 255, green: CGFloat(sky >> 8 & 255) / 255, blue: CGFloat(sky >> 16 & 255) / 255, alpha: 1)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Jeb" // hidden, but Meet's picker shows it
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.aspectRatio = NSSize(width: 16, height: 9) // the whole frame: the scene fills it, title bar and all, and Meet captures all of it
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.backgroundColor = skyColour
        root.backgroundColor = skyColour.cgColor
        root.isOpaque = true
        host = NSView(frame: NSRect(origin: .zero, size: Self.size))
        host.layer = root
        host.wantsLayer = true
        window.contentView = host
        camera.anchorPoint = .zero
        root.addSublayer(camera)
        scene = FarmScene(art: art, layout: Self.layout(), farm: farm, live: live, story: story, in: camera)
        super.init()
        window.delegate = self
        let restored = window.setFrameUsingName("JebBroadcast")
        window.setFrameAutosaveName("JebBroadcast")
        if !restored { window.setFrame(NSRect(origin: .zero, size: Self.size), display: false); window.center() }
        fit()
        // Opened from the menu: to the front. Reopened by a reload or Restart: shown without taking focus.
        if activate { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) } else { window.orderFront(nil) }
        startPolling()
    }

    /// Visible (even covered: Meet still captures it) and not minimized.
    var isShown: Bool { window.isVisible && !window.isMiniaturized }

    // MARK: Scene

    /// A new scene for new art, the night or a holiday: built whole, swapped in one transaction.
    func replaceScene(art: Art) {
        let old = scene
        CATransaction.begin()
        scene = FarmScene(art: art, layout: old.layout, farm: old.farm, live: old.live, story: old.story, in: camera)
        if !old.running { scene.setRunning(false) }
        old.tearDown()
        quiet { old.world.removeFromSuperlayer() }
        fit()
        CATransaction.commit()
    }

    func setRunning(_ run: Bool) { scene.setRunning(run) }

    func tearDown() {
        timer?.invalidate(); timer = nil
        stopMotion()
        window.delegate = nil
        scene.tearDown()
        quiet { scene.world.removeFromSuperlayer() }
        window.contentView = nil
        window.orderOut(nil)
        if !closing { window.close() }
    }

    // MARK: Camera

    private func startPolling() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.follow() }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private struct Subject { let rect: CGRect; let name: String }

    private var backing: CGFloat { window.backingScaleFactor }
    private var maxDevice: Int { max(1, Int((host.bounds.height * backing / CGFloat(rows)).rounded(.down))) }
    private var minDevice: Int {
        let strip = CGFloat(scene.valley.farmWidth) + 2 * pad
        return min(maxDevice, max(1, Int((host.bounds.width * backing / strip).rounded(.down))))
    }
    private var stageRect: CGRect {
        CGRect(x: CGFloat(scene.valley.farmX), y: CGFloat(scene.valley.road), width: CGFloat(scene.valley.farmWidth), height: CGFloat(bandHeight))
    }

    /// The padded box's bottom edge for a view that starts at the ground unless the box reaches lower.
    private func bottom(_ padded: CGRect) -> CGFloat { max(0, min(CGFloat(max(0, scene.valley.road - 4)), padded.minY)) }

    /// Whether the padded box fits a view `s` device pixels per scene pixel.
    private func fits(_ padded: CGRect, _ s: Int) -> Bool {
        let vw = host.bounds.width * backing / CGFloat(s), vh = host.bounds.height * backing / CGFloat(s)
        return padded.width <= vw && bottom(padded) + vh >= padded.maxY
    }

    private func bestDevice(_ padded: CGRect) -> Int {
        let lo = minDevice
        return stride(from: maxDevice, through: lo, by: -1).first { fits(padded, $0) } ?? lo
    }

    private func setDevice(_ s: Int) {
        device = s
        scale = CGFloat(s) / backing
        viewW = host.bounds.width / scale
        viewH = host.bounds.height / scale
    }

    /// Where the view's origin goes (at the current scale): centred on the box, bottom on the ground; clamped, whole pixels.
    private func origin(_ box: CGRect, _ padded: CGRect) -> (x: CGFloat, y: CGFloat) {
        let l = scene.layout
        return (clamp(box.midX - viewW / 2, view: viewW, total: CGFloat(l.width)), clamp(bottom(padded), view: viewH, total: CGFloat(l.height)))
    }

    private func clamp(_ v: CGFloat, view: CGFloat, total: CGFloat) -> CGFloat {
        (view >= total ? (total - view) / 2 : min(max(v, 0), total - view)).rounded()
    }

    /// The box of everything on stage (the stage strip when nothing is), and its padded form.
    private func boxes(_ subs: [Subject]) -> (box: CGRect, padded: CGRect) {
        let box = subs.reduce(CGRect.null) { $0.union($1.rect) }
        let b = box.isNull ? stageRect : box
        return (b, b.insetBy(dx: -pad, dy: -pad))
    }

    /// Sizes the view from the window and puts it on the stage's subjects (the whole stage unless following), jumping.
    private func fit() {
        let content = host.bounds.size
        guard content.width > 0, content.height > 0 else { return }
        quiet { root.frame = host.bounds; camera.frame = host.bounds }
        let (box, padded) = boxes(follows ? subjects() : [])
        setDevice(follows ? bestDevice(padded) : minDevice)
        zoomInSince = nil; offSince = nil; lastZoomOut = .distantPast
        let o = origin(box, padded)
        camX = o.x; camY = o.y
        aimed = (camX, camY, device); lastAim = .distantPast
        stopMotion()
        curX = camX; curY = camY; curLog = log(scale)
        velX = 0; velY = 0; velLog = 0
        render()
    }

    private func follow() {
        guard follows, window.isVisible, !window.isMiniaturized, host.bounds.width > 0 else { return }
        let subs = subjects()
        // Nothing shown (a place fading in starts at opacity 0): hold the shot rather than pull out to the whole stage.
        guard !subs.isEmpty else { zoomInSince = nil; offSince = nil; return }
        let (box, padded) = boxes(subs)
        let best = bestDevice(padded), now = Date()
        var target = device
        if best < device {
            target = best; lastZoomOut = now
        } else if best > device {
            tighter = zoomInSince == nil ? best : min(tighter, best)
            zoomInSince = zoomInSince ?? now
            if now.timeIntervalSince(zoomInSince!) >= 2.5, now.timeIntervalSince(lastZoomOut) >= 6 { target = min(tighter, device * 2) }
        } else {
            zoomInSince = nil
        }
        if target != device {
            let out = target < device
            setDevice(target); zoomInSince = nil; offSince = nil
            let o = origin(box, padded)
            aim(x: o.x, y: o.y, quick: out)
        } else {
            let world = CGRect(x: 0, y: 0, width: CGFloat(scene.layout.width), height: CGFloat(scene.layout.height))
            let need = padded.intersection(world).isNull ? padded : padded.intersection(world)
            let view = CGRect(x: camX, y: camY, width: viewW, height: viewH).insetBy(dx: -0.5, dy: -0.5)
            if !view.contains(need) {
                offSince = nil
                let o = origin(box, padded)
                aim(x: o.x, y: o.y, quick: true)
            } else if abs(box.midX - (camX + viewW / 2)) > 0.2 * viewW {
                offSince = offSince ?? now
                if now.timeIntervalSince(offSince!) >= 1.5 {
                    offSince = nil
                    let o = origin(box, padded)
                    aim(x: o.x, y: o.y)
                }
            } else {
                offSince = nil
            }
        }
        if logging { logFraming(subs, box) }
    }

    /// Sets the target (the scale is already set) and starts the motion toward it if the camera is not there.
    /// `quick`: something is outside the view (a zoom-out or a pan to take it in), so the faster spring.
    private func aim(x: CGFloat, y: CGFloat, quick: Bool = false) {
        camX = x; camY = y; self.quick = quick
        if aimed != (x, y, device) { aimed = (x, y, device); lastAim = Date() }
        guard motion == nil, !atTarget(settled: false) else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        motion = t
    }

    private func stopMotion() { motion?.invalidate(); motion = nil }

    /// Whether the camera shows the target (`settled`: and has all but stopped).
    private func atTarget(settled: Bool) -> Bool {
        let near = abs(curX - camX) < 0.25 && abs(curY - camY) < 0.25 && abs(curLog - log(scale)) < 0.002 // under half a pixel: the snap is not seen
        return near && (!settled || (abs(velX) < 0.5 && abs(velY) < 0.5 && abs(velLog) < 0.01))
    }

    /// One step of the motion: each axis moves toward its target on a critically damped spring (Unity's SmoothDamp).
    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTick, 0.1))
        lastTick = now
        guard dt > 0 else { return }
        let target = log(scale)
        let time: CGFloat = quick ? 0.2 : target - curLog > 0.001 ? 0.6 : 0.35 // taking something in is fastest, zooming in slowest
        curX = Self.damp(curX, camX, &velX, time, dt)
        curY = Self.damp(curY, camY, &velY, time, dt)
        curLog = Self.damp(curLog, target, &velLog, time, dt)
        if atTarget(settled: true) {
            stopMotion()
            curX = camX; curY = camY; curLog = target
            velX = 0; velY = 0; velLog = 0
        }
        render()
    }

    private static func damp(_ current: CGFloat, _ target: CGFloat, _ vel: inout CGFloat, _ time: CGFloat, _ dt: CGFloat) -> CGFloat {
        let omega = 2 / time, x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = current - target
        let temp = (vel + omega * change) * dt
        vel = (vel - omega * temp) * decay
        return target + (change + temp) * decay
    }

    /// Shows the current: translate(-x, -y) in scene pixels, then scale (exactly the target's once settled).
    private func render() {
        let s = motion == nil ? scale : exp(curLog)
        let t = CATransform3DConcat(CATransform3DMakeTranslation(-curX, -curY, 0), CATransform3DMakeScale(s, s, 1))
        quiet { camera.sublayerTransform = t }
    }

    /// JEB_BROADCAST_LOG: the target when it changes or something is clipped; the clipped parts once a second.
    private func logFraming(_ subs: [Subject], _ box: CGRect) {
        let now = Date()
        var clipped: [String] = []
        if motion == nil || now.timeIntervalSince(lastAim) > 0.7 {
            let s = motion == nil ? scale : exp(curLog)
            let view = CGRect(x: curX, y: curY, width: host.bounds.width / s, height: host.bounds.height / s).insetBy(dx: -0.5, dy: -0.5)
            clipped = subs.filter { !view.contains($0.rect) }.map(\.name)
        }
        let target = "\(device) \(camX) \(camY)"
        if target != lastTarget || !clipped.isEmpty {
            lastTarget = target
            let f = { (r: CGRect) in "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
            log("broadcast: box \(f(box)) view \(f(CGRect(x: camX, y: camY, width: viewW, height: viewH))) scale \(device) parts \(subs.map(\.name)) clipped \(clipped.isEmpty ? "no" : "yes")")
        }
        if !clipped.isEmpty, now.timeIntervalSince(lastClipLog) >= 1 {
            lastClipLog = now
            log("broadcast: clipped \(clipped)")
        }
    }

    /// The actors on stage, each with its presentation bounds (itself and shown descendants) in world coordinates.
    private func subjects() -> [Subject] {
        let world = scene.world.presentation() ?? scene.world
        var out: [Subject] = []
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(scene.layout.width), height: CGFloat(scene.layout.height))
        func shown(_ l: CALayer) -> CALayer? {
            let p = l.presentation() ?? l
            return p.isHidden || p.opacity <= 0 ? nil : p
        }
        func extent(_ l: CALayer, _ r: inout CGRect) {
            guard let p = shown(l) else { return }
            if p.bounds.width > 0, p.bounds.height > 0 { r = r.union(p.convert(p.bounds, to: world)) }
            for s in l.sublayers ?? [] { extent(s, &r) }
        }
        func walk(_ l: CALayer) {
            guard shown(l) != nil else { return }
            let part = l.value(forKey: "jebPart") as? String
            let named = l.name.map { $0.hasPrefix("jeb-") || $0.hasPrefix("blue-") } ?? false
            if part.map(Self.actors.contains) == true || named {
                var r = CGRect.null
                extent(l, &r)
                r = r.intersection(bounds) // only what is inside the world: a truck parked off its edge is not on stage
                if !r.isNull, r.width > 0, r.height > 0 { out.append(Subject(rect: r, name: part ?? l.name ?? "?")) }
                return
            }
            for s in l.sublayers ?? [] { walk(s) }
        }
        walk(scene.world)
        return out
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) { fit() }
    func windowDidChangeBackingProperties(_ notification: Notification) { fit() }
    func windowDidMiniaturize(_ notification: Notification) { timer?.invalidate(); timer = nil; stopMotion() }
    func windowDidDeminiaturize(_ notification: Notification) { startPolling(); fit() }

    func windowWillClose(_ notification: Notification) {
        closing = true
        timer?.invalidate(); timer = nil
        stopMotion()
        onClose?()
    }
}
