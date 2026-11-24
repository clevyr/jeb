// goldencheck: run the golden scenarios against the Swift tools and diff the produced files with desktop/tests/golden.
// Driven by desktop/tests/check.sh (which builds this, sets the environment and makes the temp folder):
//   goldencheck --root <repo> --tmp <T> --arch <arch> --only <prefix> --update 0|1 --render 0|1 --home <real home>
import Foundation

func parseArgs() -> Config {
    var a: [String: String] = [:]
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let k = it.next() {
        guard k.hasPrefix("--"), let v = it.next() else { fail("usage: goldencheck --root R --tmp T --arch A --only P --update 0|1 --render 0|1 --home H") }
        a[String(k.dropFirst(2))] = v
    }
    guard let root = a["root"], let tmp = a["tmp"], let arch = a["arch"], let home = a["home"] else {
        fail("missing --root/--tmp/--arch/--home")
    }
    return Config(root: root, tmp: tmp, arch: arch, out: tmp + "/out", gold: root + "/desktop/tests/golden", only: a["only"] ?? "",
                  update: a["update"] == "1", render: a["render"] == "1", realHome: home)
}

/// The goldens the comparison covers: everything under runtime/ and release/ except the notes and what another chunk owns.
func comparable(_ rel: String) -> Bool {
    if rel == "README.md" { return false }
    // art/: only what the art group produces (the Swift tool is the subject); the other files there are inputs of `jebart raster-check`
    if rel.hasPrefix("art/") && !(["art/generators.txt", "art/decoded-frames.imageio.json"].contains(rel)) { return false }
    if rel == "release/parity/compare.txt" && !config.render { return false }
    if !config.only.isEmpty && !rel.hasPrefix(config.only) { return false }
    return true
}

func skippedPrefix(_ rel: String) -> Bool {
    SKIPPED.contains { rel.hasPrefix($0.split(separator: ":")[0]) }
}

func compare() -> Int32 {
    let gold = config.gold, out = config.out
    let expected = walkFiles(gold).filter(comparable)
    let produced = Set(walkFiles(out).filter(comparable))
    var differ: [String] = [], missing: [String] = [], extra: [String] = []
    for rel in expected {
        if !produced.contains(rel) {
            if !skippedPrefix(rel) { missing.append(rel) }
            continue
        }
        if readBytes(gold + "/" + rel) != readBytes(out + "/" + rel) {
            differ.append(rel)
            let d = runProcess(["/usr/bin/diff", "-u", gold + "/" + rel, out + "/" + rel])
            print("--- \(rel) differs")
            print(d.stdout, terminator: d.stdout.hasSuffix("\n") ? "" : "\n")
        }
    }
    for rel in produced.sorted(by: pyLess) where !expected.contains(rel) { extra.append(rel) }
    for rel in missing { print("missing: \(rel) (in the goldens, not produced)") }
    for rel in extra { print("extra: \(rel) (produced, not in the goldens)") }
    let n = differ.count + missing.count + extra.count
    if n == 0 {
        print("check: goldens match (\(expected.count) files)")
        return 0
    }
    print("check: \(n) golden(s) DIFFER (\(differ.count) changed, \(missing.count) missing, \(extra.count) extra; \(expected.count) compared)")
    return 1
}

func update() {
    let gold = config.gold, out = config.out
    var n = 0
    for rel in walkFiles(out).filter(comparable) {
        if readBytes(gold + "/" + rel) != readBytes(out + "/" + rel) {
            copyFile(out + "/" + rel, gold + "/" + rel)
            print("updated: \(rel)")
            n += 1
        }
    }
    print("update: \(n) golden(s) written under desktop/tests/golden; review the diff")
}

config = parseArgs()
setupFixtures()
removeAll(config.out)
mkdirs(config.out)
for g in GROUPS where wanted(g.prefixes) {
    g.run()
}
if wanted(["art"]) { artScenario() }
for k in COUNTS.keys.sorted(by: pyLess) { print("  \(k): \(COUNTS[k]!)") }
for s in SKIPPED { print("  skipped: " + s) }
if config.update {
    update()
    exit(0)
}
exit(compare())
