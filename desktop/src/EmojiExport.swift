import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Slack custom emoji (JEB_EMOJI=<out.gif>, jebctl emoji): an animated GIF of one sprite, every frame, on a 128 x 128
/// transparent canvas, centred at the largest whole-number scale that fits (nearest-neighbour; where even 1x does not fit
/// it is scaled down to fit), looping forever. `rows` > 0 keeps only the top rows of each frame (the menu bar's head is 20),
/// 0 the whole sprite. `delay` is each frame's time in seconds; nil gives jeb-idle the desktop's blink (frame 0 for 2.7 s,
/// frame 3 for 0.2 s, as FarmScene draws it) and any other sprite 0.5 s a frame. The sprite is looked up through Art, so an
/// active holiday's variant is used. Returns an error message, or nil; `report` gets the frame count and byte size.
func exportEmoji(art: Art, sprite: String, rows: Int, delay: Double?, to file: String, report: (Int, Int) -> Void) -> String? {
    guard art.has(sprite) else { return "art has no sprite \(sprite)" }
    let all = art.images(sprite)
    guard let first = all.first else { return "sprite \(sprite) has no frames" }
    let timeline: [(CGImage, Double)] = delay == nil && sprite == "jeb-idle" && all.count > 1
        ? [(all[0], 2.7), (all[min(3, all.count - 1)], 0.2)]
        : all.map { ($0, delay ?? 0.5) }
    // JEB_EMOJI_ROWS counts rows of the base sprite; a taller holiday variant takes its extra rows on top.
    let rows = rows > 0 ? art.headRows(sprite, rows) : rows
    guard rows >= 0, rows <= first.height else { return "rows must be 0 to \(first.height) for \(sprite)" }
    let size = 128
    let cropH = rows == 0 ? first.height : rows
    let fit = Double(size) / Double(max(first.width, cropH))
    let k = fit >= 1 ? Double(Int(fit)) : fit
    let dw = max(1, Int((Double(first.width) * k).rounded())), dh = max(1, Int((Double(cropH) * k).rounded()))
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: file) as CFURL, "com.compuserve.gif" as CFString, timeline.count, nil)
    else { return "cannot write \(file)" }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (frame, seconds) in timeline {
        guard let head = rows == 0 ? frame : frame.cropping(to: CGRect(x: 0, y: 0, width: frame.width, height: rows)),
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "cannot make a \(size) px canvas" }
        ctx.interpolationQuality = .none
        ctx.draw(head, in: CGRect(x: (size - dw) / 2, y: (size - dh) / 2, width: dw, height: dh))
        guard let image = ctx.makeImage() else { return "cannot draw a frame" }
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: seconds]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { return "cannot write \(file)" }
    let bytes = ((try? FileManager.default.attributesOfItem(atPath: file))?[.size] as? Int) ?? 0
    report(timeline.count, bytes)
    return nil
}
