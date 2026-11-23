// DiffTs: `jebart diff-ts <a.ts> <b.ts> [--only <prefix>]...` compares two pixel-art.ts files sprite by sprite (size
// and frames, by name), and, with no --only, the palette, colour and font lines too. It names every sprite that
// differs or is missing from one side. Used while porting, to check the Swift sprites against the Python's output.
import Foundation

struct TsSprite: Equatable { var w: Int, h: Int, frames: [String] }

struct ParsedTs {
    var header: [String] = []          // every line before the PIXEL_SPRITES entries
    var sprites: [String: TsSprite] = [:]
    var order: [String] = []
}

func parseTs(_ text: String) -> ParsedTs {
    var out = ParsedTs()
    var inSprites = false
    for line in text.components(separatedBy: "\n") {
        if !inSprites {
            out.header.append(line)
            if line.hasPrefix("export const PIXEL_SPRITES") { inSprites = true }
            continue
        }
        // `  'name': { w: 20, h: 48, frames: ['..', '..'] },`
        guard line.hasPrefix("  '"), let nameEnd = line.range(of: "': { w: ") else { continue }
        let name = String(line[line.index(line.startIndex, offsetBy: 3)..<nameEnd.lowerBound])
        let rest = line[nameEnd.upperBound...]
        let parts = rest.components(separatedBy: ", h: ")
        guard parts.count == 2, let w = Int(parts[0]) else { continue }
        let hAndFrames = parts[1].components(separatedBy: ", frames: [")
        guard hAndFrames.count == 2, let h = Int(hAndFrames[0]) else { continue }
        var list = hAndFrames[1]
        guard let close = list.range(of: "] },", options: .backwards) else { continue }
        list = String(list[..<close.lowerBound])
        let frames = list.isEmpty ? [] : list.components(separatedBy: ", ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
        if out.sprites[name] == nil { out.order.append(name) }
        out.sprites[name] = TsSprite(w: w, h: h, frames: frames)
    }
    return out
}

/// The lines that differ, ready to print: header lines when `only` is empty, then one per differing sprite.
func diffTs(_ a: ParsedTs, _ b: ParsedTs, only: [String]) -> [String] {
    var report: [String] = []
    if only.isEmpty && a.header != b.header { report.append("palette/colour/font lines differ") }
    func wanted(_ name: String) -> Bool { only.isEmpty || only.contains { name.hasPrefix($0) } }
    for name in a.order where wanted(name) {
        guard let other = b.sprites[name] else { report.append("only in first: \(name)"); continue }
        if a.sprites[name] != other { report.append("differs: \(name)") }
    }
    for name in b.order where wanted(name) && a.sprites[name] == nil { report.append("only in second: \(name)") }
    return report
}

/// The command: prints the differences and returns the exit status.
func diffTsCommand(_ args: [String]) -> Int32? {
    var files: [String] = [], only: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == "--only" {
            guard i + 1 < args.count else { return nil }
            only.append(args[i + 1]); i += 2
        } else { files.append(args[i]); i += 1 }
    }
    guard files.count == 2 else { return nil }
    var texts: [String] = []
    for f in files {
        guard let data = FileManager.default.contents(atPath: f) else {
            FileHandle.standardError.write(Data("jebart: cannot read \(f)\n".utf8))
            return 2
        }
        texts.append(String(decoding: data, as: UTF8.self))
    }
    let a = parseTs(texts[0]), b = parseTs(texts[1])
    let report = diffTs(a, b, only: only)
    for line in report { print(line) }
    let compared = Set(a.order.filter { n in only.isEmpty || only.contains { n.hasPrefix($0) } }).intersection(b.order).count
    print(report.isEmpty ? "identical (\(compared) sprites compared)" : "\(report.count) difference(s)")
    return report.isEmpty ? 0 : 1
}
