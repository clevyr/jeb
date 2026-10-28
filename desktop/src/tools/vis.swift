// vis <seconds>: every second, the share of the main screen not covered by any
// on-screen window at the normal level or above (other than the menu bar and its
// items) or the Dock's full-screen overlay, i.e. where the desktop shows; prints the average and the samples.
import AppKit
let n = Int(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let screen = NSScreen.screens[0].frame
var shares: [Double] = []
for _ in 0..<n {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var rects: [CGRect] = []
    for w in list {
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
        // The Dock's window spans the screen but is clear outside the Dock itself.
        guard layer >= 0, layer < 24, owner != "Dock", owner != "Window Server", alpha > 0.01,
              let b = w[kCGWindowBounds as String] as? [String: Double] else { continue }
        rects.append(CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!))
    }
    var free = 0, all = 0
    for gy in 0..<60 { for gx in 0..<96 {
        let p = CGPoint(x: screen.width * (Double(gx) + 0.5) / 96, y: 25 + (screen.height - 25) * (Double(gy) + 0.5) / 60)
        all += 1
        if !rects.contains(where: { $0.contains(p) }) { free += 1 }
    } }
    shares.append(Double(free) / Double(all))
    Thread.sleep(forTimeInterval: 1)
}
print(String(format: "desktop uncovered avg %.0f%% (min %.0f%%, max %.0f%%)", 100 * shares.reduce(0, +) / Double(n), 100 * (shares.min() ?? 0), 100 * (shares.max() ?? 0)))
