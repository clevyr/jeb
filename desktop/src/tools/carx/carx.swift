import AppKit
import Metal
import QuartzCore
let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 800, height: 600, mipmapped: false)
d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
let tex = device.makeTexture(descriptor: d)!
let r = CARenderer(mtlTexture: tex, options: [kCARendererMetalCommandQueue as String: queue])
let root = CALayer(); root.frame = CGRect(x: 0, y: 0, width: 800, height: 600); root.backgroundColor = .black
let box = CALayer(); box.frame = CGRect(x: 0, y: 0, width: 10, height: 10); box.backgroundColor = .white
root.addSublayer(box)
r.layer = root; r.bounds = root.bounds
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "basic"
let a: CAAnimation
if mode == "discrete" {
    let k = CAKeyframeAnimation(keyPath: "position"); k.values = (0..<10).map { NSValue(point: CGPoint(x: $0 * 10, y: 5)) }; k.keyTimes = (0...10).map { NSNumber(value: Double($0) / 10) }; k.calculationMode = .discrete; a = k
} else { let b = CABasicAnimation(keyPath: "position.x"); b.fromValue = 0; b.toValue = 700; a = b }
a.duration = 10; a.repeatCount = .infinity
if CommandLine.arguments.contains("now") { a.beginTime = CACurrentMediaTime() }
box.add(a, forKey: "x")
CATransaction.flush()
var dirty = 0, nexts: [Double] = []
for _ in 0..<120 {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 60))
    let now = CACurrentMediaTime()
    r.beginFrame(atTime: now, timeStamp: nil)
    let u = r.updateBounds()
    if !u.isEmpty { dirty += 1; r.addUpdate(u); r.render() }
    nexts.append(r.nextFrameTime() - now)
    r.endFrame()
}
print(mode, "dirty frames", dirty, "of 120; next-change deltas sample", nexts.prefix(8).map { String(format: "%.3f", $0) })
