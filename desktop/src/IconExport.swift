import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The app icon's PNGs (JEB_ICONSET=<dir>, run by tools/bundle.sh): the ten files `iconutil` wants in an
/// .iconset, each a square transparent canvas with the menu-bar head (the top 20 rows of jeb-idle, as
/// StatusMenu.setIcon draws it) centred at the largest whole-number scale that fits in 85% of the
/// canvas; where even 1x does not fit it is scaled down, nearest-neighbour, to fit. Returns an error message, or nil.
func exportIconset(art: Art, to dir: String) -> String? {
    guard let head = art.image("jeb-idle", rows: 20, scale: 1) else { return "art has no jeb-idle sprite" }
    do { try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
    catch { return "cannot create \(dir): \(error.localizedDescription)" }
    for base in [16, 32, 128, 256, 512] {
        for factor in [1, 2] {
            let px = base * factor
            let name = "icon_\(base)x\(base)" + (factor == 2 ? "@2x" : "") + ".png"
            let fit = Double(px) * 0.85 / Double(max(head.width, head.height))
            let k = fit >= 1 ? Double(Int(fit)) : fit
            let dw = max(1, Int((Double(head.width) * k).rounded())), dh = max(1, Int((Double(head.height) * k).rounded()))
            guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "cannot make a \(px) px canvas" }
            ctx.interpolationQuality = .none
            ctx.draw(head, in: CGRect(x: (px - dw) / 2, y: (px - dh) / 2, width: dw, height: dh))
            guard let image = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir + "/" + name) as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { return "cannot write \(name)" }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { return "cannot write \(name)" }
        }
    }
    return nil
}
