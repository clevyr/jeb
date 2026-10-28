import QuartzCore
import AppKit
let root = CALayer()
let box = CALayer(); root.addSublayer(box)
func make(_ n: Int, extraTime: Bool) -> CAKeyframeAnimation {
    let k = CAKeyframeAnimation(keyPath: "position"); k.values = (0..<n).map { NSValue(point: CGPoint(x: $0, y: 0)) }
    k.keyTimes = (0...(extraTime ? n : n - 1)).map { NSNumber(value: Double($0) / Double(extraTime ? n : n - 1)) }
    k.calculationMode = .discrete; k.duration = 5; k.repeatCount = .infinity; return k
}
CATransaction.begin()
box.add(make(10, extraTime: true), forKey: "a")
let c = CALayer(); root.addSublayer(c)
let f = CAKeyframeAnimation(keyPath: "contents"); f.values = [NSImage(size: NSSize(width: 1, height: 1)).cgImage(forProposedRect: nil, context: nil, hints: nil) as Any]; f.duration = 1
c.add(f, forKey: "f")
let g = CAAnimationGroup(); g.animations = [make(5, extraTime: true)]; g.duration = 5; g.repeatCount = .infinity; g.timeOffset = 2
let d = CALayer(); root.addSublayer(d); d.add(g, forKey: "g")
CATransaction.commit()
print("after commit", box.animationKeys() ?? [], c.animationKeys() ?? [], d.animationKeys() ?? [])
CATransaction.flush()
print("after flush", box.animationKeys() ?? [], c.animationKeys() ?? [], d.animationKeys() ?? [])
