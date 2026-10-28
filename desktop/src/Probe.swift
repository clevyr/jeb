// Probe (desktop-dive only): logs, with ms wall-clock times, every notification
// relevant to Spaces, activation, occlusion, screens, sleep and lock, and the app's
// own render state at that moment and 0.1 / 0.3 / 0.6 / 1 / 2 s later: per window,
// visible / occlusion / on the active Space, the scene running or paused (its layer
// clock's speed) and how many layers it shows. The window-server side is
// measured outside the app (watch.swift), so this costs nothing between events.
// JEB_PROBE_LOG names the log file (default probe.log next to the binary).

import AppKit

func msNow() -> Double { Date().timeIntervalSince1970 * 1000 }

private let probeHandle: FileHandle? = {
    let path = env["JEB_PROBE_LOG"] ?? (executablePath as NSString).deletingLastPathComponent + "/probe.log"
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    let h = FileHandle(forWritingAtPath: path)
    h?.seekToEndOfFile()
    return h
}()
private let stampFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

let probing = env["JEB_PROBE"] == "1"
func probeLog(_ message: String) {
    guard probing else { return }
    let ms = msNow()
    probeHandle?.write(String(format: "%.0f %@ [%d] %@\n", ms, stampFormat.string(from: Date(timeIntervalSince1970: ms / 1000)), getpid(), message).data(using: .utf8)!)
}

extension App {
    func renderState() -> String {
        let ws = windows.map { w -> String in
            let o = w.window.occlusionState.contains(.visible) ? "vis" : "occ"
            return "#\(w.window.windowNumber)[\(w.window.isVisible ? "on" : "OFF") \(o) \(w.window.isOnActiveSpace ? "here" : "away") speed=\(w.scene.world.speed) layers=\(w.scene.world.sublayers?.count ?? 0)]"
        }.joined(separator: " ")
        return String(format: "%@ running=%@", ws, isRunning ? "y" : "n(\(pauseReason ?? ""))")
    }

    func startProbe() {
        probeLog("probe on: level \(desktopLevel.rawValue) spaces=\(spacesMode) reorder=\(reorderMode) animNone=\(env["JEB_ANIM_NONE"] ?? "0") noPause=\(noPause) calmFps=\(calmFps)")
        let report: (String) -> Void = { [weak self] what in
            guard let self else { return }
            probeLog("\(what) | \(renderState())")
            for d in [0.1, 0.3, 0.6, 1.0, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                    guard let self else { return }
                    probeLog("  +\(Int(d * 1000))ms after \(what.prefix(40)): \(renderState())")
                }
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: nil, object: nil, queue: .main) { n in
            let a = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName.map { " " + $0 } ?? ""
            let name = n.name.rawValue.replacingOccurrences(of: "NSWorkspace", with: "WS.")
            if name.contains("DidLaunch") || name.contains("WillLaunch") || name.contains("DidTerminate") { probeLog(name + a); return }
            report(name + a)
        }
        let nc = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didChangeOcclusionStateNotification, NSApplication.didChangeScreenParametersNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { n in report(n.name.rawValue.replacingOccurrences(of: "NSApplication", with: "App.")) }
        }
        // Everything posted about our own windows, except the per-event-loop update.
        nc.addObserver(forName: nil, object: nil, queue: .main) { [weak self] n in
            guard let self, let w = n.object as? NSWindow, windows.contains(where: { $0.window === w }) else { return }
            let name = n.name.rawValue
            if name == NSWindow.didUpdateNotification.rawValue || name.contains("Layout") { return }
            report(name.replacingOccurrences(of: "NSWindow", with: "Win.") + " #\(w.windowNumber)")
        }
        let dc = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
            dc.addObserver(forName: .init(name), object: nil, queue: .main) { _ in report(name) }
        }
    }
}
