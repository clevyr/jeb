import os
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = 'FarmScene.swift'
s = open(p).read()
a = s.index('    private func run(_ a: CAAnimation, on layer: CALayer, key: String, pass: Bool = false, kind: String? = nil) {')
b = s.index('    // MARK: Building')
s = s[:a] + '''    /// Calm animations run on the scene's shared step clock: every calm keyframe
    /// falls on a multiple of `tick` seconds of scene time and every calm animation
    /// starts on one, so they all change together, at most 1/tick times a second,
    /// and the compositor has nothing to redraw between ticks. Passes run smoothly
    /// at the full rate instead.
    private func run(_ a: CAAnimation, on layer: CALayer, key: String, pass: Bool = false, kind: String? = nil) {
        if let kind, !animOn(kind) { return }
        a.preferredFrameRateRange = pass ? passRange : calmRange
        if !pass, let tick, a.beginTime == 0 {
            let now = world.convertTime(CACurrentMediaTime(), from: nil)
            a.beginTime = (now / tick).rounded(.down) * tick // the last tick (already begun, so no gap)
        }
        layer.add(a, forKey: key)
    }

    /// A time on the step clock (at least one tick), or as is when smooth.
    private func snap(_ t: Double) -> Double {
        guard let tick else { return t }
        return max(tick, (t / tick).rounded() * tick)
    }

    /// A sprite's frames in turn, `seconds` each (on the step clock unless a pass), forever.
    private func frames(_ name: String, every seconds: Double, pass: Bool = false) -> CAKeyframeAnimation {
        let images = art.images(name)
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = images
        a.keyTimes = (0...images.count).map { NSNumber(value: Double($0) / Double(images.count)) }
        a.calculationMode = .discrete
        a.duration = (pass ? seconds : snap(seconds)) * Double(images.count)
        a.repeatCount = .infinity
        return a
    }

    private func animate(_ layer: CALayer, _ name: String, every seconds: Double, key: String = "act", pass: Bool = false, kind: String? = nil) {
        run(frames(name, every: seconds, pass: pass), on: layer, key: key, pass: pass, kind: kind)
    }

    private func round(_ v: CGFloat, _ q: CGFloat) -> CGFloat { (v / q).rounded(.down) * q }

    /// A calm path, `p(t)` for t in 0..<duration, looping. Stepped: read on each
    /// tick of the step clock and rounded to `quantum`, as discrete keyframes (only
    /// where the stepped position changes). Smooth: linear keyframes ten times a
    /// second; `jumps` lists times where the path wraps (no interpolation across them).
    private func path(duration: Double, jumps: [Double] = [], _ p: (Double) -> CGPoint) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: "position")
        var values: [NSValue] = [], times: [NSNumber] = []
        var d = duration
        if let q = quantum, let tick {
            d = snap(duration)
            let n = Int((d / tick).rounded())
            var last: CGPoint?
            for i in 0..<n {
                let t = Double(i) * tick, v = p(t)
                let s = CGPoint(x: round(v.x, q), y: round(v.y, q))
                if s != last { values.append(NSValue(point: s)); times.append(NSNumber(value: t / d)); last = s }
            }
            times.append(1)
            a.calculationMode = .discrete
        } else {
            let hz = 10.0
            var cuts = jumps.sorted()
            for i in 0...Int(duration * hz) {
                let t = min(duration, Double(i) / hz)
                while let c = cuts.first, c <= t {
                    // Just before and at the wrap, so the move never crosses the screen.
                    values.append(NSValue(point: p(max(0, c - 0.0001)))); times.append(NSNumber(value: max(0, c - 0.0001) / duration))
                    values.append(NSValue(point: p(c))); times.append(NSNumber(value: c / duration))
                    cuts.removeFirst()
                }
                values.append(NSValue(point: p(t))); times.append(NSNumber(value: t / duration))
            }
            a.calculationMode = .linear
        }
        a.values = values
        a.keyTimes = times
        a.duration = d
        a.repeatCount = .infinity
        return a
    }

    /// A calm number (`keyPath`, `f(t)` for t in 0..<duration), looping: stepped,
    /// read on each tick and rounded to `step`; smooth, linear keyframes ten times a second.
    private func level(_ keyPath: String, duration: Double, step: Double, _ f: (Double) -> Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        var values: [NSNumber] = [], times: [NSNumber] = []
        var d = duration
        if let tick {
            d = snap(duration)
            var last: Double?
            for i in 0..<Int((d / tick).rounded()) {
                let t = Double(i) * tick, v = (f(t) / step).rounded() * step
                if v != last { values.append(NSNumber(value: v)); times.append(NSNumber(value: t / d)); last = v }
            }
            times.append(1)
            a.calculationMode = .discrete
        } else {
            for i in 0...Int(duration * 10) {
                let t = min(duration, Double(i) / 10)
                values.append(NSNumber(value: f(t))); times.append(NSNumber(value: t / duration))
            }
            a.calculationMode = .linear
        }
        a.values = values
        a.keyTimes = times
        a.duration = d
        a.repeatCount = .infinity
        return a
    }

    /// Opacity, stepped in eighths.
    private func fade(duration: Double, _ f: (Double) -> Double) -> CAKeyframeAnimation {
        level("opacity", duration: duration, step: 0.125, f)
    }

''' + s[b:]

def rep(old, new, n=1):
    global s
    assert s.count(old) == n, (old, s.count(old))
    s = s.replace(old, new)

rep('''    /// Calm motion is stepped at this many scene pixels (nil: smooth).
    private let quantum: CGFloat?''', '''    /// Calm motion is stepped at this many scene pixels, every `tick` seconds (nil: smooth).
    private let quantum: CGFloat?, tick: Double?''')
rep('''        case .smooth: quantum = nil
        }''', '''        case .smooth: quantum = nil
        }
        tick = quantum == nil ? nil : 1 / calmHz''')
# drop the hz: arguments to path()
import re
s = re.sub(r'path\(duration: ([^,]+?), hz: [^,)]+(, |\))', lambda m: 'path(duration: ' + m.group(1) + m.group(2), s)
rep('''            let size = CAKeyframeAnimation(keyPath: "transform.scale")
            let steps = quantum == nil ? [2.0, 3.75] : stride(from: 2.0, through: 3.75, by: 0.25).map { $0 }
            size.values = steps
            if quantum == nil {
                size.keyTimes = [0, 1]
            } else {
                size.keyTimes = (0...steps.count).map { NSNumber(value: Double($0) / Double(steps.count)) }
                size.calculationMode = .discrete
            }
            size.duration = life''', '''            let size = level("transform.scale", duration: life, step: 0.25) { t in 2 + 0.35 * t }
            size.repeatCount = 1''')
rep('''            group.timeOffset = life * Double(i) / Double(count) // spread over the cycle: already flowing''',
    '''            group.timeOffset = tick.map { t in (life * Double(i) / Double(count) / t).rounded() * t } ?? life * Double(i) / Double(count) // spread over the cycle: already flowing''')
rep('''            blink.values = [f[0], f[min(3, f.count - 1)]]
            blink.keyTimes = [0, NSNumber(value: 2.7 / 2.86), 1]
            blink.calculationMode = .discrete
            blink.duration = 2.86''', '''            let open = snap(2.7), shut = snap(0.16)
            blink.values = [f[0], f[min(3, f.count - 1)]]
            blink.keyTimes = [0, NSNumber(value: open / (open + shut)), 1]
            blink.calculationMode = .discrete
            blink.duration = open + shut''')
rep('''// Calm motion moves in whole steps (JEB_CALM_MOTION): `device` (default) one
// device pixel at a time, as discrete keyframes, so the compositor only has to
// redraw when something actually moves a pixel; `pixel` one art pixel at a time,
// as the terminal band does; `smooth` interpolated by Core Animation every frame.
// Passes always move smoothly.''', '''// Calm motion moves in whole steps on one shared step clock (calmHz ticks a second,
// see run()): `device` (JEB_CALM_MOTION, default) to the nearest device pixel,
// `pixel` to whole art pixels as the terminal band does, `smooth` interpolated by
// Core Animation every frame (no step clock). With every calm change on the same
// ticks, the compositor redraws only on those and sleeps between them; passes move
// smoothly at the full rate.''')
open(p, 'w').write(s)

p = 'main.swift'
s = open(p).read()
rep('''var fps = 60, calmFps = 30 // while something passes / otherwise
func applyRate() {
    fps = Int(env["JEB_FPS"] ?? "") ?? (rate == .thirty ? 30 : 60)
    calmFps = min(fps, Int(env["JEB_CALM_FPS"] ?? "") ?? (rate == .sixty ? 60 : 30))
}''', '''var fps = 60, calmFps = 30 // while something passes / otherwise
var calmHz = 10.0 // the calm step clock's ticks a second
func applyRate() {
    fps = Int(env["JEB_FPS"] ?? "") ?? (rate == .thirty ? 30 : 60)
    calmFps = min(fps, Int(env["JEB_CALM_FPS"] ?? "") ?? (rate == .sixty ? 60 : 30))
    // Adaptive: calm motion steps ten times a second (the art's own frame timings
    // are tenths), passes at 60; otherwise everything at the chosen rate.
    calmHz = min(Double(calmFps), Double(env["JEB_CALM_HZ"] ?? "") ?? (rate == .adaptive ? 10 : Double(calmFps)))
}''')
open(p, 'w').write(s)
print('ok')
