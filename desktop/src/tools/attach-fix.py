import os
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def edit(p, pairs):
    s = open(p).read()
    for old, new in pairs:
        assert s.count(old) == 1, (p, old, s.count(old))
        s = s.replace(old, new)
    open(p, 'w').write(s)


edit('FarmScene.swift', [
('''    init(art: Art, layout: Layout, farm: Farm) {
        self.art = art''', '''    /// Built straight into `host` (a layer already on screen, or under a renderer):
    /// Core Animation drops animations from a tree that is not attached anywhere
    /// when it commits, so the world goes into place before any animation is added.
    init(art: Art, layout: Layout, farm: Farm, in host: CALayer) {
        self.art = art'''),
('''            world.masksToBounds = true
            build()''', '''            world.masksToBounds = true
            host.addSublayer(world)
            build()'''),
('''    var wakes: Int { clock.fired }''', '''    var wakes: Int { clock.fired }

    /// How many layers have animations running (a check that they were not dropped).
    var animatedLayers: Int { world.sublayers?.filter { !($0.animationKeys() ?? []).isEmpty }.count ?? 0 }'''),
])
edit('main.swift', [
('''        scene = FarmScene(art: art, layout: layout, farm: farm)
        quiet { root.addSublayer(scene.world) }
        fit(layout)''', '''        scene = FarmScene(art: art, layout: layout, farm: farm, in: root)
        fit(layout)'''),
('''        let old = scene
        scene = FarmScene(art: art, layout: layout ?? old.layout, farm: old.farm)
        if !old.running { scene.setRunning(false) }
        old.tearDown()
        quiet {
            root.replaceSublayer(old.world, with: scene.world)
        }
        fit(scene.layout)''', '''        let old = scene
        // One transaction: the new world goes in over the old and the old comes out
        // in the same frame.
        CATransaction.begin()
        scene = FarmScene(art: art, layout: layout ?? old.layout, farm: old.farm, in: root)
        if !old.running { scene.setRunning(false) }
        old.tearDown()
        quiet { old.world.removeFromSuperlayer() }
        fit(scene.layout)
        CATransaction.commit()'''),
('''            log(String(format: "screen %d: %d passes so far, %d scene wakes; paused %.0f s, in view %.0f s, of %.0f s",
                       i, w.scene.passes, wakes, paused, shown, Date().timeIntervalSince(statsSince)))''', '''            log(String(format: "screen %d: %d passes so far, %d scene wakes, %d layers animated; paused %.0f s, in view %.0f s, of %.0f s",
                       i, w.scene.passes, wakes, w.scene.animatedLayers, paused, shown, Date().timeIntervalSince(statsSince)))'''),
])
s = open('Bench.swift').read()
a = s.index('    let root = CALayer()\n')
b = s.index('    let hz = Double(env["JEB_BENCH_FPS"]')
s = s[:a] + '''    let root = CALayer()
    quiet {
        root.bounds = CGRect(x: 0, y: 0, width: pxW, height: pxH) // device pixels here
        root.anchorPoint = .zero
        root.position = .zero
        root.backgroundColor = CGColor(gray: 0, alpha: 1)
        root.isOpaque = true
    }
    renderer.layer = root
    renderer.bounds = root.bounds
    let scene = FarmScene(art: art, layout: layout, farm: farm, in: root)
    quiet {
        let k = CGFloat(layout.scale)
        scene.world.transform = CATransform3DMakeScale(k, k, 1)
    }
    CATransaction.flush()
    log("bench: \\(scene.world.sublayers?.count ?? 0) layers, \\(scene.animatedLayers) animated")
''' + s[b:]
open('Bench.swift', 'w').write(s)
print("ok")
