// Bench (measuring only, JEB_BENCH=<seconds>): renders the scene's layer tree
// offscreen with CARenderer into a Metal texture the size of the main screen, the
// way the window server's compositor does, and reports what it would have to do:
// how many frames had anything to redraw, the dirty area per frame, how long until
// the next change (nextFrameTime), and the CPU time the rendering took. No window
// is shown. JEB_BENCH_FPS sets the tick rate (default 60). JEB_BENCH_SCALE=1 renders
// at one texture pixel per scene pixel (for the parity fixtures: JEB_STORE_PATH a
// fixture store, JEB_NOW its moment, JEB_BENCH_PNG the picture: with JEB_BENCH=0.01 and
// JEB_BENCH_FREEZE=1 that is one PNG of a given moment, as `jebctl screenshot --fixture` runs it).
// Shooter is the one PNG path: the bench's pictures and the app's Save Screenshot.

import AppKit
import Metal
import QuartzCore

/// A layer tree rendered offscreen with CARenderer into a Metal texture, read back as a PNG.
final class Shooter {
    let queue: MTLCommandQueue, texture: MTLTexture, renderer: CARenderer
    let root = CALayer()
    let pxW: Int, pxH: Int

    init?(width: Int, height: Int) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared // read back for the PNG
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        self.queue = queue; self.texture = texture; pxW = width; pxH = height
        renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
        quiet {
            root.bounds = CGRect(x: 0, y: 0, width: width, height: height) // device pixels here
            root.anchorPoint = .zero
            root.position = .zero
            root.backgroundColor = CGColor(gray: 0, alpha: 1)
            root.isOpaque = true
        }
        renderer.layer = root
        renderer.bounds = root.bounds
    }

    /// The whole tree as it is now, written to `path`.
    func png(to path: String) throws {
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let cb = queue.makeCommandBuffer()!; cb.commit(); cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: pxW * pxH * 4)
        texture.getBytes(&bytes, bytesPerRow: pxW * 4, from: MTLRegionMake2D(0, 0, pxW, pxH), mipmapLevel: 0)
        // The texture's rows run bottom-up here: flip them for the picture.
        let row = pxW * 4
        for y in 0..<(pxH / 2) { for x in 0..<row { bytes.swapAt(y * row + x, (pxH - 1 - y) * row + x) } }
        let ctx = CGContext(data: &bytes, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: pxW * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        guard let image = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw ShotError("could not encode the PNG") }
        try png.write(to: URL(fileURLWithPath: path))
    }
}

struct ShotError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Where Save Screenshot writes: JEB_SHOT_DIR, else ~/Pictures/Jeb.
let screenshotDir = env["JEB_SHOT_DIR"] ?? NSHomeDirectory() + "/Pictures/Jeb"

/// Save Screenshot and the jebctl trigger: what each screen draws now, rendered offscreen (never a screen capture:
/// no other app's windows, no permission) as jeb-<YYYYMMDD-HHMMSS>[-<n>].png, one per screen. The scene is built
/// the way replaceScene builds one (same art, farm, sessions and story, at the screen's layout) and held still.
func saveScreenshots(art: Art, farm: Farm, live: [String: LiveRecord], story: Story) throws -> [String] {
    try FileManager.default.createDirectory(atPath: screenshotDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
    let stamp = f.string(from: Date()), screens = NSScreen.screens
    guard !screens.isEmpty else { throw ShotError("no screens") }
    var paths: [String] = []
    for (i, screen) in screens.enumerated() {
        let s = screen.backingScaleFactor, layout = Layout(screen: screen)
        guard let shooter = Shooter(width: Int(screen.frame.width * s), height: Int(screen.frame.height * s)) else { throw ShotError("no Metal device") }
        let scene = FarmScene(art: art, layout: layout, farm: farm, live: live, story: story, in: shooter.root)
        defer { scene.tearDown() }
        scene.setRunning(false)
        quiet { scene.world.transform = CATransform3DMakeScale(CGFloat(layout.scale), CGFloat(layout.scale), 1) }
        CATransaction.flush()
        let path = screenshotDir + "/jeb-\(stamp)\(screens.count > 1 ? "-\(i + 1)" : "").png"
        try shooter.png(to: path)
        paths.append(path)
    }
    return paths
}

func runBench(seconds: Double, art: Art, farm: Farm, live: [String: LiveRecord], areas: Areas) -> Never {
    guard let screen = NSScreen.screens.first else { log("bench: no screen"); exit(1) }
    let layout = Layout(screen: screen)
    let s = screen.backingScaleFactor
    let unit = env["JEB_BENCH_SCALE"] == "1"
    let pxW = unit ? layout.width : Int(screen.frame.width * s), pxH = unit ? layout.height : Int(screen.frame.height * s)
    guard let shooter = Shooter(width: pxW, height: pxH) else { log("bench: no Metal device or texture"); exit(1) }
    let renderer = shooter.renderer, root = shooter.root
    let story = Story()
    story.noteAreas(areas)
    story.ingest(live: live)
    let scene = FarmScene(art: art, layout: layout, farm: farm, live: live, story: story, in: root)
    quiet {
        let k = unit ? 1 : CGFloat(layout.scale)
        scene.world.transform = CATransform3DMakeScale(k, k, 1)
    }
    // Fixtures: hold the scene exactly as it was built (passes do not move on before the picture).
    if env["JEB_BENCH_FREEZE"] == "1" { scene.setRunning(false) }
    CATransaction.flush()
    let cast = scene.castCount
    log("bench: \(scene.world.sublayers?.count ?? 0) layers, \(scene.animatedLayers) animated, cast \(cast.jeb) Jeb \(cast.blue) Blue (\(cast.jebAll)/\(cast.blueAll) in the tree)")
    // Where things are, for the parity check: the stage strip (scene pixels, bottom-left) and which place is on it.
    let place = scene.placeCount
    print("area theme \(scene.areaThemed ? 1 : 0) placed \(scene.areaPlaced)")
    print("geometry scene \(layout.width) \(layout.height) farm \(scene.valley.farmX) \(scene.valley.road) \(scene.valley.farmWidth) place \(scene.placeKind) roots \(place.roots) farm \(place.farm) camp \(place.camp) road \(place.road)")
    // The story as a scripted day or a fixture sees it (JEB_BENCH_STORY=1): one line a step, flushed.
    let t0 = CACurrentMediaTime()
    func step(_ tag: String) {
        guard env["JEB_BENCH_STORY"] == "1" else { return }
        let c = scene.castCount, p = scene.placeCount
        print(String(format: "step t=%.2f %@ cast=%d/%d tree=%d/%d roots=%d farm=%d camp=%d road=%d sessions=%d %@", CACurrentMediaTime() - t0, tag, c.jeb, c.blue, c.jebAll, c.blueAll,
                     p.roots, p.farm, p.camp, p.road, scene.sessionCount, story.debug))
        fflush(stdout)
    }
    step("start")
    // The store as the app watches it: changes land in the scene (JEB_BENCH_WATCH=1).
    let source = StoreSource(); _ = source.refresh()
    var watcher: StoreWatcher?
    if env["JEB_BENCH_WATCH"] == "1" {
        watcher = StoreWatcher(path: storePath) {
            let c = source.refresh()
            if c.farm || c.live || c.areas {
                if c.areas { story.noteAreas(source.areas) }
                story.ingest(live: source.live)
                scene.apply(farm: source.farm, live: source.live)
                step("store")
            }
        }
        watcher?.start()
        story.onChange = { scene.apply(farm: source.farm, live: source.live); step("story") }
    }
    // Pictures every JEB_BENCH_SHOT_EVERY seconds into JEB_BENCH_SHOTS (a folder), for a look at the dynamics.
    let shotDir = env["JEB_BENCH_SHOTS"], shotEvery = Double(env["JEB_BENCH_SHOT_EVERY"] ?? "") ?? 2
    var nextShot = CACurrentMediaTime() + shotEvery, shots = 0
    func shoot(_ path: String) { try? shooter.png(to: path) }
    let hz = Double(env["JEB_BENCH_FPS"] ?? "") ?? 60
    var frames = 0, dirtyFrames = 0, dirtyArea = 0.0, fullArea = Double(pxW * pxH)
    var nexts: [Double] = []
    var usage0 = rusage(); getrusage(RUSAGE_SELF, &usage0)
    var renderCPU = 0.0
    let tick = 1 / hz
    var next = t0
    while CACurrentMediaTime() - t0 < seconds {
        // Let the run loop run (the scene's callbacks: passes, acts).
        RunLoop.main.run(until: Date(timeIntervalSinceNow: max(0, next - CACurrentMediaTime())))
        next += tick
        let c0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let now = CACurrentMediaTime()
        renderer.beginFrame(atTime: now, timeStamp: nil)
        let dirty = renderer.updateBounds()
        frames += 1
        if !dirty.isEmpty {
            dirtyFrames += 1
            dirtyArea += Double(dirty.width * dirty.height)
            renderer.addUpdate(dirty)
            renderer.render()
        }
        let nt = renderer.nextFrameTime()
        renderer.endFrame()
        renderCPU += Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - c0) / 1e9
        nexts.append(nt.isInfinite ? 999 : max(0, nt - now))
        if let dir = shotDir, CACurrentMediaTime() >= nextShot {
            shots += 1
            shoot("\(dir)/shot-\(String(format: "%03d", shots)).png")
            nextShot += shotEvery
        }
    }
    _ = watcher
    let elapsed = CACurrentMediaTime() - t0
    if let out = env["JEB_BENCH_PNG"] { try? shooter.png(to: out) } // the last frame, for a look
    var usage1 = rusage(); getrusage(RUSAGE_SELF, &usage1)
    func secs(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
    let cpu = secs(usage1.ru_utime) + secs(usage1.ru_stime) - secs(usage0.ru_utime) - secs(usage0.ru_stime)
    let sorted = nexts.sorted()
    let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    let idleable = nexts.filter { $0 > tick * 1.5 }.count
    print(String(format: "bench %@: %.0f s at %.0f Hz: %d frames, %d with something to redraw (%.0f%%), dirty area avg %.1f%% of the screen when dirty; next change median %.3f s, %d frames could have been skipped; render CPU %.2f%%, process CPU %.2f%%",
                 animKinds.sorted().joined(separator: ","), elapsed, hz, frames, dirtyFrames, 100 * Double(dirtyFrames) / Double(max(1, frames)),
                 dirtyFrames == 0 ? 0 : 100 * dirtyArea / Double(dirtyFrames) / fullArea, median, idleable, 100 * renderCPU / elapsed, 100 * cpu / elapsed))
    exit(0)
}
