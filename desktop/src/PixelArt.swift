// The mod's generated hooks/pixel-art.ts, read as TEXT and never executed: the
// file is one the unattended builder can change, so nothing in it runs. Only its
// literal data is taken, by a strict line-by-line parser:
//
//   export const PIXEL_PALETTE: readonly number[] = [ ...JSON numbers... ]
//   export const PIXEL_COLOUR: Readonly<Record<string, number>> = { ...JSON... }
//   export const PIXEL_FONT: Readonly<Record<string, string>> = { ...JSON... }
//   export type PixelSprite = { w: number; h: number; frames: readonly string[] }
//   export const PIXEL_SPRITES: Readonly<Record<string, PixelSprite>> = {
//     'name': { w: 20, h: 40, frames: ['base64', 'base64'] },
//   }
//
// plus comments and blank lines. Any other line, a shape that does not fit, or a
// size past the caps rejects the whole file (the caller keeps the last good art).
// Frames are base64 (run, paletteIndex) byte pairs, row-major, as in decodeFrame.

import Foundation

struct Sprite { let w: Int, h: Int; let frames: [[UInt8]] }

struct PixelArt {
    let palette: [UInt32] // colour words (index 0 transparent)
    let colours: [String: Int]
    let font: [String: String]
    let sprites: [String: Sprite]
}

struct ArtError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

enum ArtLimits {
    static let fileBytes = 4 << 20, colours = 256, names = 512, glyphs = 128
    static let sprites = 600, side = 128, frames = 16, frameChars = 32_768
}

func parsePixelArt(_ text: String) throws -> PixelArt {
    guard text.utf8.count <= ArtLimits.fileBytes else { throw ArtError("file over \(ArtLimits.fileBytes) bytes") }
    let palettePrefix = "export const PIXEL_PALETTE: readonly number[] = "
    let colourPrefix = "export const PIXEL_COLOUR: Readonly<Record<string, number>> = "
    let fontPrefix = "export const PIXEL_FONT: Readonly<Record<string, string>> = "
    let typeLine = "export type PixelSprite = { w: number; h: number; frames: readonly string[] }"
    let spritesOpen = "export const PIXEL_SPRITES: Readonly<Record<string, PixelSprite>> = {"
    let spriteLine = try NSRegularExpression(pattern: #"^  '([A-Za-z0-9_-]{1,40})': \{ w: ([0-9]{1,3}), h: ([0-9]{1,3}), frames: \[('[A-Za-z0-9+/=]*'(?:, '[A-Za-z0-9+/=]*')*)\] \},$"#)

    var palette: [UInt32]?, colours: [String: Int]?, font: [String: String]?
    var rawSprites: [(name: String, w: Int, h: Int, frames: [String])] = []
    var inSprites = false, spritesClosed = false

    func json<T>(_ body: Substring, as: T.Type, _ what: String) throws -> T {
        guard let value = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? T else { throw ArtError("\(what) is not the expected literal") }
        return value
    }

    for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let at = "line \(n + 1)"
        if inSprites {
            if line == "}" { inSprites = false; spritesClosed = true; continue }
            let s = String(line)
            guard let m = spriteLine.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), rawSprites.count < ArtLimits.sprites else {
                throw ArtError("\(at): not a sprite line, or too many sprites")
            }
            let group = { (i: Int) in String(s[Range(m.range(at: i), in: s)!]) }
            let frames = group(4).split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " '")) }
            rawSprites.append((group(1), Int(group(2))!, Int(group(3))!, frames))
            continue
        }
        if line.isEmpty || line.hasPrefix("//") || line == typeLine { continue }
        if line.hasPrefix(palettePrefix), palette == nil {
            let numbers = try json(line.dropFirst(palettePrefix.count), as: [NSNumber].self, "palette")
            guard (2...ArtLimits.colours).contains(numbers.count) else { throw ArtError("\(at): palette size \(numbers.count)") }
            palette = try numbers.enumerated().map { i, n in
                let rgb = n.intValue
                guard n.doubleValue == Double(rgb), (0...0xFFFFFF).contains(rgb) else { throw ArtError("\(at): bad colour \(n)") }
                return i == 0 ? 0 : word(rgb >> 16 & 255, rgb >> 8 & 255, rgb & 255)
            }
        } else if line.hasPrefix(colourPrefix), colours == nil {
            colours = try json(line.dropFirst(colourPrefix.count), as: [String: Int].self, "colour map")
        } else if line.hasPrefix(fontPrefix), font == nil {
            font = try json(line.dropFirst(fontPrefix.count), as: [String: String].self, "font")
        } else if line == spritesOpen, !spritesClosed, rawSprites.isEmpty {
            inSprites = true
        } else {
            throw ArtError("\(at): unexpected line")
        }
    }

    guard let palette, let colours, let font, spritesClosed else { throw ArtError("a PIXEL_* block is missing or unclosed") }
    guard colours.count <= ArtLimits.names, colours.allSatisfy({ k, v in k.count <= 32 && (0..<palette.count).contains(v) }) else {
        throw ArtError("colour map out of range")
    }
    guard font.count <= ArtLimits.glyphs, font.allSatisfy({ k, v in k.count == 1 && v.count == 15 && v.allSatisfy { $0 == "0" || $0 == "1" } }) else {
        throw ArtError("font glyphs are not 1 character to 15 bits")
    }

    var sprites: [String: Sprite] = [:]
    for s in rawSprites {
        guard sprites[s.name] == nil else { throw ArtError("sprite \(s.name) twice") }
        guard (1...ArtLimits.side).contains(s.w), (1...ArtLimits.side).contains(s.h), (1...ArtLimits.frames).contains(s.frames.count) else {
            throw ArtError("sprite \(s.name) is \(s.w)x\(s.h) with \(s.frames.count) frames")
        }
        sprites[s.name] = Sprite(w: s.w, h: s.h, frames: try s.frames.map { frame in
            guard frame.count <= ArtLimits.frameChars, let pairs = Data(base64Encoded: frame), pairs.count % 2 == 0 else {
                throw ArtError("sprite \(s.name): a frame is not base64 pairs")
            }
            // Runs of 1...255 of a palette index; the runs must cover the frame exactly.
            var pixels: [UInt8] = []
            pixels.reserveCapacity(s.w * s.h)
            for i in stride(from: 0, to: pairs.count, by: 2) {
                let run = Int(pairs[pairs.startIndex + i]), index = pairs[pairs.startIndex + i + 1]
                guard run > 0, Int(index) < palette.count, pixels.count + run <= s.w * s.h else {
                    throw ArtError("sprite \(s.name): a run is empty, past the palette or past the frame")
                }
                pixels.append(contentsOf: repeatElement(index, count: run))
            }
            guard pixels.count == s.w * s.h else { throw ArtError("sprite \(s.name): runs cover \(pixels.count) of \(s.w * s.h) pixels") }
            return pixels
        })
    }
    return PixelArt(palette: palette, colours: colours, font: font, sprites: sprites)
}

/// Watches the art file (by path, so a temp-and-rename replace is seen): re-parses
/// when its mtime or size changes, and hands over only art that parses.
final class ArtSource {
    let path: String
    private var stamp: (Date, Int)?
    private(set) var art: Art?

    init(path: String) { self.path = path }

    /// Re-parses now, changed or not (the menu's Reload art).
    func reload() -> Bool { stamp = nil; return refresh() }

    /// True when new, valid art was loaded.
    func refresh() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date, let size = (attrs[.size] as? NSNumber)?.intValue else { return false }
        if let stamp, stamp == (modified, size) { return false }
        stamp = (modified, size)
        guard size <= ArtLimits.fileBytes, let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            log("art \(path): unreadable; keeping the last good art")
            return false
        }
        do {
            let t0 = Date()
            let parsed = try parsePixelArt(text)
            art = Art(parsed)
            log(String(format: "art loaded: %d sprites, %d colours (%.0f ms)", parsed.sprites.count, parsed.palette.count, Date().timeIntervalSince(t0) * 1000))
            return true
        } catch {
            log("art \(path) rejected (\(error)); keeping the last good art")
            return false
        }
    }
}
