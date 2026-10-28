// latency <store> <n>: write-to-screen latency of the store transport. Captures ONLY
// JebDesktop's own window (ScreenCaptureKit, desktop-independent window filter, frames
// kept in memory and dropped, nothing saved), then n times writes the scratch store the
// way the mod does (temp file, rename over) with a line toggled on or off in the one
// session's record, and waits for the first captured frame whose bubble area (left of
// the camp's Jeb in slot 0) changed. Prints each latency and the median.
import AppKit
import CoreMedia
import ScreenCaptureKit

let args = CommandLine.arguments
let store = args[1], n = Int(args.count > 2 ? args[2] : "20") ?? 20
let farm = (try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: store))) as! [String: Any])["farm"]!

final class Grabber: NSObject, SCStreamOutput {
    var lastSig: [UInt8] = []
    var waiting: (start: Double, done: (Double) -> Void)?
    let lock = NSLock()
    var box = CGRect.zero // in capture pixels, top-down
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = sb.imageBuffer else { return }
        let t = Date().timeIntervalSince1970 * 1000
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), row = CVPixelBufferGetBytesPerRow(pb)
        var sig: [UInt8] = []
        for y in stride(from: Int(box.minY), to: Int(box.maxY), by: 2) { for x in stride(from: Int(box.minX), to: Int(box.maxX), by: 3) { sig.append(base[y * row + x * 4 + 1]) } }
        lock.lock(); defer { lock.unlock() }
        if let w = waiting, !lastSig.isEmpty, sig != lastSig { waiting = nil; w.done(t - w.start) }
        lastSig = sig
    }
}

func write(line: Bool) -> Double {
    let now = Date().timeIntervalSince1970 * 1000
    var rec: [String: Any] = ["v": 1, "at": now, "frame": 0, "still": true]
    if line { rec["line"] = "Fine day for it."; rec["saidAt"] = now }
    let body: [String: Any] = ["farm": farm, "live:lat0": rec]
    let data = try! JSONSerialization.data(withJSONObject: body)
    let tmp = store + ".tmp"
    try! data.write(to: URL(fileURLWithPath: tmp))
    let t = Date().timeIntervalSince1970 * 1000
    rename(tmp, store)
    return t
}

let grab = Grabber()
var stream: SCStream?
SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, err in
    guard let content, let win = content.windows.first(where: { $0.owningApplication?.applicationName == "JebDesktop" && $0.frame.width > 500 }) else {
        print("no JebDesktop window: \(String(describing: err))"); exit(1)
    }
    let cfg = SCStreamConfiguration()
    let w = Int(win.frame.width) / 2, h = Int(win.frame.height) / 2 // a point a pixel / 2
    cfg.width = w; cfg.height = h
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    cfg.queueDepth = 3
    // The camp in slot 0 of a 428 x 277 scene: its bubble rows and the room left of its Jeb.
    let sx = Double(w) / 428, sy = Double(h) / 277
    grab.box = CGRect(x: 2 * sx, y: (277 - 123 + 1) * sy, width: 148 * sx, height: 18 * sy)
    let s = SCStream(filter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg, delegate: nil)
    try! s.addStreamOutput(grab, type: .screen, sampleHandlerQueue: DispatchQueue(label: "grab"))
    s.startCapture { e in
        if let e { print("capture: \(e)"); exit(1) }
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.5)
            var results: [Double] = []
            for i in 0..<n {
                let sem = DispatchSemaphore(value: 0)
                var got = -1.0
                let start = write(line: i % 2 == 0)
                grab.lock.lock(); grab.waiting = (start, { got = $0; sem.signal() }); grab.lock.unlock()
                if sem.wait(timeout: .now() + 3) == .timedOut { print("write \(i): no change seen in 3 s") } else { results.append(got); print(String(format: "write %d: %.1f ms", i, got)) }
                Thread.sleep(forTimeInterval: 1.2)
            }
            let sorted = results.sorted()
            if !sorted.isEmpty { print(String(format: "latency write->on-screen: median %.1f ms, min %.1f, max %.1f, n %d", sorted[sorted.count / 2], sorted.first!, sorted.last!, sorted.count)) }
            exit(0)
        }
    }
    stream = s
}
RunLoop.main.run()
