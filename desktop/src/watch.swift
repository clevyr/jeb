// watch: passive measurement helper for the JebDesktop window-switch dive.
//
// 1. Samples the WindowServer's on-screen window list at 60 Hz (CGWindowListCreate:
//    ids only, cheap) and logs, with ms wall-clock times, every change in the order
//    and on-screen state of the desktop-level windows (JebDesktop "J", the
//    WindowManager wallpaper "W", the full-screen backdrop "B", the display backstop
//    "S") plus Dock / WindowManager overlay windows and the frontmost big app owner.
//    Window titles of other apps are never logged.
// 2. Captures the composited display with ScreenCaptureKit at a tiny size
//    (1/5 of points, 60 fps, frames only on change). Each frame is classified on a
//    48x30 probe grid against reference captures of J, W and B (refreshed every 5 s):
//    the fraction of probes showing Jeb, the wallpaper, the backdrop, ambiguous, or
//    other. Frames where the real wallpaper shows are "gaps".
// 3. Around each window-list change or workspace notification, writes a contact
//    sheet of 1/10-scale thumbnails (illegible text) every 50 ms from -0.5 s to +2.5 s.
//
// Usage: watch <outdir>   (stop with SIGINT/SIGTERM)

import AppKit
import CoreMedia
import ScreenCaptureKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }
func stamp(_ ms: Double) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000)
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: d)
}

final class Out {
    let handle: FileHandle
    let lock = NSLock()
    init(_ name: String) {
        let url = outDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        handle = try! FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
    }
    func write(_ s: String) { lock.lock(); handle.write((s + "\n").data(using: .utf8)!); lock.unlock() }
}
let events = Out("events.log")
let metricsOut = Out("frames.csv")
func ev(_ s: String, at ms: Double = nowMs()) { events.write(String(format: "%.0f ", ms) + stamp(ms) + " " + s) }

// MARK: - Window list sampling

struct Info { let owner: String; let name: String; let layer: Int; let area: Double; let full: Bool }
var infoCache: [CGWindowID: Info] = [:]
let displayBounds = CGDisplayBounds(CGMainDisplayID())
let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))

func describe(_ ids: [CGWindowID]) {
    let missing = ids.filter { infoCache[$0] == nil }
    guard !missing.isEmpty else { return }
    var ptrs: [UnsafeRawPointer?] = missing.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    let arr = CFArrayCreate(nil, &ptrs, ptrs.count, nil)!
    let desc = (CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]]) ?? []
    for d in desc {
        guard let n = d[kCGWindowNumber as String] as? Int else { continue }
        let owner = d[kCGWindowOwnerName as String] as? String ?? "?"
        let keepName = ["WindowManager", "Window Server", "JebDesktop", "Dock"].contains(owner)
        let b = d[kCGWindowBounds as String] as? [String: Double] ?? [:]
        let w = b["Width"] ?? 0, h = b["Height"] ?? 0
        let full = w >= displayBounds.width && h >= displayBounds.height - 1
        infoCache[CGWindowID(n)] = Info(owner: owner, name: keepName ? (d[kCGWindowName as String] as? String ?? "") : "",
                                        layer: d[kCGWindowLayer as String] as? Int ?? 0, area: w * h / (displayBounds.width * displayBounds.height), full: full)
    }
    for id in missing where infoCache[id] == nil { infoCache[id] = Info(owner: "?", name: "", layer: 0, area: 0, full: false) }
}

func tag(_ id: CGWindowID, _ i: Info) -> String? {
    switch (i.owner, i.name) {
    case ("JebDesktop", _) where i.area > 0.9: return "J\(id)@\(i.layer - desktopLevel)"
    case ("WindowManager", "Wallpaper"): return "W\(id)@\(i.layer - desktopLevel)"
    case ("WindowManager", "Fullscreen Backdrop"): return "B\(id)@\(i.layer - desktopLevel)"
    case ("Window Server", let n) where n.contains("Backstop"): return "S@\(i.layer - desktopLevel)"
    case ("Dock", let n): return i.area > 0.5 ? "Dock[\(n.isEmpty ? "-" : n)]L\(i.layer)" : nil
    case ("WindowManager", let n): return i.area > 0.2 ? "WM[\(n.isEmpty ? "-" : n)]L\(i.layer)" : nil
    default: return nil
    }
}

typealias WLCreate = @convention(c) (UInt32, UInt32) -> Unmanaged<CFArray>?
let windowListCreate = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreate")!, to: WLCreate.self)
var lastState = ""
var lastChangeMs = 0.0
var onTrigger: ((String, Double) -> Void)?
let sampleQueue = DispatchQueue(label: "wl", qos: .userInteractive)
var samples = 0, sampleCost = 0.0

func sample() {
    let t0 = nowMs()
    guard let raw = windowListCreate(CGWindowListOption.optionOnScreenOnly.rawValue, kCGNullWindowID)?.takeRetainedValue() else { return }
    let n = CFArrayGetCount(raw)
    var ids: [CGWindowID] = []
    ids.reserveCapacity(n)
    for i in 0..<n { ids.append(CGWindowID(UInt(bitPattern: CFArrayGetValueAtIndex(raw, i)))) }
    describe(ids)
    var parts: [String] = []
    var topApp = "-", fullApp = "-"
    for id in ids {
        guard let i = infoCache[id] else { continue }
        if i.layer == 0 {
            if topApp == "-" && i.area > 0.25 { topApp = i.owner }
            if fullApp == "-" && i.full { fullApp = i.owner }
        }
        if let t = tag(id, i) { parts.append(t) }
    }
    let state = parts.joined(separator: " > ") + " | top=\(topApp) fs=\(fullApp)"
    samples += 1; sampleCost += nowMs() - t0
    if state != lastState {
        let t = nowMs()
        ev("WL " + state + String(format: "   (+%.0f ms since last change)", t - lastChangeMs), at: t)
        lastState = state; lastChangeMs = t
        onTrigger?("WL", t)
    }
}

// MARK: - Screen capture and classification

let capW = Int(displayBounds.width / 5), capH = Int(displayBounds.height / 5)
let gridX = 48, gridY = 30
struct Frame { let ms: Double; let px: [UInt8]; let bpr: Int }
var ring: [Frame] = []
let capQueue = DispatchQueue(label: "cap", qos: .userInitiated)
var refs: [Character: [UInt8]] = [:] // per reference: RGB per probe
var inGap = false, gapStart = 0.0, gapMax = 0.0, lastClass = ""

func probes(_ px: UnsafePointer<UInt8>, bpr: Int, bgra: Bool) -> [UInt8] {
    var out = [UInt8](); out.reserveCapacity(gridX * gridY * 3)
    for gy in 0..<gridY { for gx in 0..<gridX {
        let x = (gx * 2 + 1) * capW / (gridX * 2), y = (gy * 2 + 1) * capH / (gridY * 2)
        let p = px + y * bpr + x * 4
        if bgra { out += [p[2], p[1], p[0]] } else { out += [p[0], p[1], p[2]] }
    } }
    return out
}

func classify(_ pr: [UInt8]) -> [Character: Double] {
    var counts: [Character: Int] = ["J": 0, "W": 0, "B": 0, "A": 0, "O": 0]
    let n = gridX * gridY
    for k in 0..<n {
        var best: [(Character, Int)] = []
        for (c, r) in refs {
            let d = max(abs(Int(pr[k*3]) - Int(r[k*3])), abs(Int(pr[k*3+1]) - Int(r[k*3+1])), abs(Int(pr[k*3+2]) - Int(r[k*3+2])))
            if d <= 20 { best.append((c, d)) }
        }
        if best.isEmpty { counts["O"]! += 1 }
        else if best.count == 1 { counts[best[0].0]! += 1 }
        else {
            best.sort { $0.1 < $1.1 }
            if best[1].1 - best[0].1 >= 8 { counts[best[0].0]! += 1 } else { counts["A"]! += 1 }
        }
    }
    return counts.mapValues { Double($0) / Double(n) }
}

final class Sink: NSObject, SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let ib = CMSampleBufferGetImageBuffer(sb) else { return }
        if let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
           let raw = att[.status] as? Int, raw != SCFrameStatus.complete.rawValue { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        let hostNow = CMClockGetTime(CMClockGetHostTimeClock())
        let ms = nowMs() - (CMTimeGetSeconds(hostNow) - CMTimeGetSeconds(pts)) * 1000
        CVPixelBufferLockBaseAddress(ib, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(ib, .readOnly) }
        let bpr = CVPixelBufferGetBytesPerRow(ib), h = CVPixelBufferGetHeight(ib)
        let base = CVPixelBufferGetBaseAddress(ib)!.assumingMemoryBound(to: UInt8.self)
        let px = Array(UnsafeBufferPointer(start: base, count: bpr * h))
        ring.append(Frame(ms: ms, px: px, bpr: bpr))
        while let f = ring.first, ms - f.ms > 4000 { ring.removeFirst() }
        guard !refs.isEmpty else { return }
        let c = classify(probes(base, bpr: bpr, bgra: true))
        let line = String(format: "%.0f,%.3f,%.3f,%.3f,%.3f,%.3f", ms, c["J"]!, c["W"]!, c["B"]!, c["A"]!, c["O"]!)
        metricsOut.write(line)
        let w = c["W"]!
        if w >= 0.05 && !inGap { inGap = true; gapStart = ms; gapMax = w; ev(String(format: "GAP start (wallpaper %.0f%%, jeb %.0f%%)", w * 100, c["J"]! * 100), at: ms) }
        else if inGap && w >= 0.05 { gapMax = max(gapMax, w) }
        else if inGap && w < 0.02 { inGap = false; ev(String(format: "GAP end after %.0f ms (max wallpaper %.0f%%; now jeb %.0f%%)", ms - gapStart, gapMax * 100, c["J"]! * 100), at: ms) }
        // A coarse class for the event log (changes only).
        let cls = c["J"]! > 0.3 ? "jeb" : w > 0.3 ? "wallpaper" : c["B"]! > 0.3 ? "backdrop" : "other"
        if cls != lastClass { ev(String(format: "SEE %@ (J %.0f W %.0f B %.0f A %.0f O %.0f)", cls, c["J"]! * 100, w * 100, c["B"]! * 100, c["A"]! * 100, c["O"]! * 100), at: ms); lastClass = cls }
        checkSheet(ms)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { ev("capture stopped: \(error)") }
}

// MARK: Contact sheets

var pending: [(t: Double, why: String)] = []
var lastSheet = 0.0, sheets = 0
let maxSheets = Int(ProcessInfo.processInfo.environment["WATCH_MAX_SHEETS"] ?? "") ?? 80

func requestSheet(_ why: String, at t: Double) {
    capQueue.async {
        guard sheets < maxSheets, t - lastSheet > 3000, !pending.contains(where: { abs($0.t - t) < 3000 }) else { return }
        pending.append((t, why))
    }
}

func checkSheet(_ ms: Double) {
    guard let p = pending.first, ms - p.t > 2600 else { return }
    pending.removeFirst()
    lastSheet = p.t; sheets += 1
    writeSheet(t: p.t, why: p.why)
}

func writeSheet(t: Double, why: String) {
    let tw = capW / 2, th = capH / 2, cols = 10, count = 60
    let rows = count / cols, labelH = 12
    let W = tw * cols, H = (th + labelH) * rows
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    ctx.setFillColor(gray: 0.15, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    for k in 0..<count {
        let at = t - 500 + Double(k) * 50
        // The latest frame at or before `at` (what was on screen then).
        guard let f = ring.last(where: { $0.ms <= at }) ?? ring.first else { continue }
        let data = f.px.withUnsafeBytes { Data($0) }
        guard let prov = CGDataProvider(data: data as CFData),
              let img = CGImage(width: capW, height: capH, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: f.bpr, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { continue }
        let col = k % cols, row = rows - 1 - k / cols
        let x = col * tw, y = row * (th + labelH)
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: x, y: y, width: tw, height: th))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        let label = String(format: "%+d", Int(at - t)) as NSString
        label.draw(at: NSPoint(x: x + 2, y: y + th), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
    }
    guard let out = ctx.makeImage() else { return }
    let name = "sheet-\(stamp(t).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: ".", with: "-"))-\(why).png"
    let rep = NSBitmapImageRep(cgImage: out)
    try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent(name))
    ev("SHEET \(name)")
}

// MARK: References

func refreshRefs() {
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, err in
        guard let content else { ev("refs: no content \(String(describing: err))"); return }
        var targets: [(Character, SCWindow)] = []
        for w in content.windows {
            let owner = w.owningApplication?.applicationName ?? ""
            let title = w.title ?? ""
            if owner == "JebDesktop" && w.frame.width >= displayBounds.width && w.isOnScreen { targets.append(("J", w)) }
            else if title == "Wallpaper" && w.isOnScreen { targets.append(("W", w)) }
            else if title == "Fullscreen Backdrop" && w.isOnScreen { targets.append(("B", w)) }
        }
        for (c, w) in targets {
            let cfg = SCStreamConfiguration()
            cfg.width = capW; cfg.height = capH; cfg.showsCursor = false
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg) { img, err in
                guard let img else { return }
                guard let ctx = CGContext(data: nil, width: capW, height: capH, bitsPerComponent: 8, bytesPerRow: capW * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: capW, height: capH))
                let base = ctx.data!.assumingMemoryBound(to: UInt8.self)
                // CGContext rows are top-first in memory, as are capture frames.
                let pr = probes(base, bpr: capW * 4, bgra: false)
                capQueue.async {
                    if refs[c] == nil { ev("refs: have \(c) (window \(w.windowID))") }
                    refs[c] = pr
                }
            }
        }
    }
}

// MARK: - main

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

onTrigger = { why, t in requestSheet(why, at: t) }
let ws = NSWorkspace.shared.notificationCenter
for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification, NSWorkspace.screensDidWakeNotification,
             NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification] {
    ws.addObserver(forName: name, object: nil, queue: .main) { n in
        let t = nowMs()
        var extra = ""
        if let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { extra = " " + (a.localizedName ?? "?") }
        ev("NOTE \(name.rawValue.replacingOccurrences(of: "NSWorkspace", with: ""))\(extra)", at: t)
        requestSheet(name == NSWorkspace.activeSpaceDidChangeNotification ? "space" : "app", at: t)
    }
}
for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
    DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { _ in ev("NOTE \(name)") }
}
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in ev("NOTE screenParameters") }

let timer = DispatchSource.makeTimerSource(flags: .strict, queue: sampleQueue)
timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(1))
timer.setEventHandler { sample() }
timer.resume()

var stream: SCStream?
let sink = Sink()
SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, err in
    guard let content, let d = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { ev("capture: unavailable \(String(describing: err))"); return }
    let cfg = SCStreamConfiguration()
    cfg.width = capW; cfg.height = capH
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    cfg.showsCursor = false
    cfg.queueDepth = 6
    let s = SCStream(filter: SCContentFilter(display: d, excludingWindows: []), configuration: cfg, delegate: sink)
    do {
        try s.addStreamOutput(sink, type: .screen, sampleHandlerQueue: capQueue)
        s.startCapture { err in ev(err == nil ? "capture: started \(capW)x\(capH)" : "capture: failed \(err!)") }
        stream = s
    } catch { ev("capture: \(error)") }
}
refreshRefs()
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in refreshRefs() }
Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
    sampleQueue.async { ev(String(format: "STATS window-list samples %d, avg %.3f ms each", samples, sampleCost / Double(max(samples, 1)))); samples = 0; sampleCost = 0 }
}
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { ev("stopping"); stream?.stopCapture { _ in exit(0) }; DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) } }
    src.resume()
    signalSources.append(src)
}
ev("watch started: display \(Int(displayBounds.width))x\(Int(displayBounds.height)) pt, desktop level \(desktopLevel)")
app.run()
