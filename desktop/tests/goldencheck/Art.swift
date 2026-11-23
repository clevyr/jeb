// Decodes the art generator's outputs with ImageIO and records them in the
// shape of desktop/tests/golden/art/decoded-frames.json.
//
// Prototype for the art half of the golden checker (plan Phase 0.3 / D4):
// every sheets/*.png, gifs/*.gif and scene*.png under a build dir, minus
// icon.png, as { size, format, frames: [{ ms, sha256 }], loop, file_sha256,
// file_bytes }, keys sorted, indent 1, like json.dumps(indent=1, sort_keys=True).
//
// Each frame is the composed frame CGImageSource hands back (ImageIO applies
// the GIF disposal), drawn into an 8-bit RGBA premultiplied-last context in
// device RGB without interpolation, hashed row-major 4 bytes per pixel with no
// padding. Fully transparent pixels therefore hash as (0,0,0,0); Pillow's
// RGBA conversion keeps the palette colour of a GIF's transparent index, so
// GIF hashes here differ from decoded-frames.json by design (see the README).
//
// The checker's main.swift calls artScenario() (below) for the `art` golden group; artDecodeMain(buildDir:outPath:)
// is the stand-alone entry point.

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct ArtFrame {
    var ms: Int?
    var sha256: String
}

struct ArtImage {
    var size: (Int, Int)
    var format: String       // Pillow's Image.format: "PNG" or "GIF"
    var frames: [ArtFrame]
    var loop: Int?
    var fileSha256: String
    var fileBytes: Int
}

enum ArtDecodeError: Error, CustomStringConvertible {
    case unreadable(String)
    case noFrame(String, Int)
    case noContext(String)

    var description: String {
        switch self {
        case .unreadable(let p): return "could not open \(p) with ImageIO"
        case .noFrame(let p, let i): return "could not decode frame \(i) of \(p)"
        case .noContext(let p): return "could not make a bitmap context for \(p)"
        }
    }
}

/// RGBA bytes of `image`, row-major, 4 bytes per pixel, no row padding.
func rgbaBytes(_ image: CGImage, path: String) throws -> Data {
    let w = image.width, h = image.height
    var bytes = Data(count: w * h * 4)
    try bytes.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
        guard let ctx = CGContext(
            data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw ArtDecodeError.noContext(path) }
        ctx.interpolationQuality = .none
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return bytes
}

func artDecode(path: String) throws -> ArtImage {
    let url = URL(fileURLWithPath: path)
    let fileData = try Data(contentsOf: url)
    guard let source = CGImageSourceCreateWithData(fileData as CFData, nil) else { throw ArtDecodeError.unreadable(path) }
    let type = CGImageSourceGetType(source) as String? ?? ""
    let format = type == "com.compuserve.gif" ? "GIF" : (type == "public.png" ? "PNG" : type)
    let count = CGImageSourceGetCount(source)
    var frames: [ArtFrame] = []
    var size = (0, 0)
    for i in 0..<count {
        guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { throw ArtDecodeError.noFrame(path, i) }
        if i == 0 { size = (image.width, image.height) }
        var ms: Int?
        if format == "GIF",
           let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
           let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            // Unclamped is the file's value; ImageIO's clamped DelayTime floors short delays to 0.1 s.
            let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as? Double
            if let d = delay { ms = Int((d * 1000).rounded()) }
        }
        frames.append(ArtFrame(ms: ms, sha256: sha256Hex(try rgbaBytes(image, path: path))))
    }
    var loop: Int?
    if format == "GIF",
       let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
       let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
        loop = gif[kCGImagePropertyGIFLoopCount] as? Int
    }
    return ArtImage(size: size, format: format, frames: frames, loop: loop,
                    fileSha256: sha256Hex(fileData), fileBytes: fileData.count)
}

/// The images decoded-frames.json covers: sheets/*.png, gifs/*.gif, then the
/// top-level *.png/*.gif except icon.png; keys are paths relative to the build dir.
func artImagePaths(buildDir: String) throws -> [String] {
    let fm = FileManager.default
    var rels: [String] = []
    for sub in ["sheets", "gifs", "."] {
        let dir = sub == "." ? buildDir : buildDir + "/" + sub
        for name in try fm.contentsOfDirectory(atPath: dir).sorted() {
            guard name.hasSuffix(".png") || name.hasSuffix(".gif") else { continue }
            if sub == "." && name == "icon.png" { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir + "/" + name, isDirectory: &isDir), !isDir.boolValue else { continue }
            rels.append(sub == "." ? name : sub + "/" + name)
        }
    }
    return rels
}

/// json.dumps(obj, indent=1, sort_keys=True) for the decoded-frames shape.
func artJSON(_ images: [(String, ArtImage)]) -> String {
    func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    func opt(_ v: Int?) -> String { v.map(String.init) ?? "null" }
    var out = "{\n"
    for (idx, (rel, im)) in images.sorted(by: { $0.0 < $1.0 }).enumerated() {
        out += " \(q(rel)): {\n"
        out += "  \"file_bytes\": \(im.fileBytes),\n"
        out += "  \"file_sha256\": \(q(im.fileSha256)),\n"
        out += "  \"format\": \(q(im.format)),\n"
        out += "  \"frames\": [\n"
        for (fi, f) in im.frames.enumerated() {
            out += "   {\n    \"ms\": \(opt(f.ms)),\n    \"sha256\": \(q(f.sha256))\n   }" + (fi + 1 < im.frames.count ? ",\n" : "\n")
        }
        out += "  ],\n"
        out += "  \"loop\": \(opt(im.loop)),\n"
        out += "  \"size\": [\n   \(im.size.0),\n   \(im.size.1)\n  ]\n"
        out += " }" + (idx + 1 < images.count ? ",\n" : "\n")
    }
    return out + "}\n"
}

/// Decodes every image under `buildDir` and writes the JSON to `outPath`.
/// Returns (images, frames) for the caller to report.
@discardableResult
func artDecodeMain(buildDir: String, outPath: String) throws -> (Int, Int) {
    var images: [(String, ArtImage)] = []
    for rel in try artImagePaths(buildDir: buildDir) {
        images.append((rel, try artDecode(path: buildDir + "/" + rel)))
    }
    try artJSON(images).write(toFile: outPath, atomically: true, encoding: .utf8)
    return (images.count, images.reduce(0) { $0 + $1.1.frames.count })
}

/// The art golden group (--impl swift): runs jebart as build.py and logo.py were run, then writes
/// art/generators.txt and art/decoded-frames.imageio.json under the output folder. File bytes of the GIFs and sheets
/// are not compared (the golden's file_bytes and file_sha256 come from Pillow's encoder), so those two fields are
/// taken from the golden itself; the decoded frames, sizes, delays and loop counts are the produced ones.
func artScenario() {
    if config.impl != .swift {
        print("  art: skipped (--impl python; build.py and logo.py are the reference, not a subject)")
        return
    }
    let jebart = ProcessInfo.processInfo.environment["JEB_CHECK_JEBART"] ?? config.root + "/art/jebart"
    let work = config.tmp + "/art-work"
    removeAll(work)
    mkdirs(work)
    func scrub(_ s: String) -> String { s.replacingOccurrences(of: work, with: "$WORK") }
    func block(_ s: String) -> String { s.isEmpty ? "(empty)" : scrub(s).trimmingCharacters(in: .newlines) }
    let ts = work + "/pixel-art.ts"
    let build = runProcess([jebart, "build", work, ts])
    let logo = runProcess([jebart, "logo", ts, work + "/logo", work + "/icon.png"])
    // the interpreter line records how the golden was captured (Python and Pillow); it is not an output
    let goldText = (readBytes(config.gold + "/art/generators.txt")).map { String(decoding: $0, as: UTF8.self) } ?? ""
    let lines = goldText.components(separatedBy: "\n")
    let interpreter = lines.count > 1 && lines[0] == "## interpreter" ? lines[1] : "jebart"
    var text = "## interpreter\n\(interpreter)\n\n"
    text += "## build.py rc\n\(build.rc)\n\n## build.py stdout\n\(block(build.stdout))\n\n## build.py stderr\n\(block(build.stderr))\n\n"
    text += "## logo.py rc\n\(logo.rc)\n\n## logo.py stdout\n\(block(logo.stdout))\n\n## logo.py stderr\n\(block(logo.stderr))\n\n"
    text += "## exact-byte outputs (the tracked file is the golden; this records that the generator still reproduces it)\n"
    for (rel, made) in [("mod/hooks/pixel-art.ts", ts), ("docs/logo.svg", work + "/logo/logo.svg"),
                        ("docs/logo.png", work + "/logo/logo.png"), ("mod/.claude-plugin/icon.png", work + "/icon.png")] {
        guard let data = readBytes(made) else { text += "\(rel): not produced\n"; continue }
        let same = readBytes(config.root + "/" + rel) == data
        text += "\(rel): sha256 \(sha256Hex(data))  \(data.count) bytes  tracked file \(same ? "same bytes" : "DIFFERENT")\n"
    }
    writeText(config.out + "/art/generators.txt", text + "\n")

    var fileFields: [String: [String: Any]] = [:]
    if let data = readBytes(config.gold + "/art/decoded-frames.imageio.json"),
       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] { fileFields = obj }
    var images: [(String, ArtImage)] = []
    do {
        for rel in try artImagePaths(buildDir: work) {
            var im = try artDecode(path: work + "/" + rel)
            if let want = fileFields[rel] {
                im.fileBytes = (want["file_bytes"] as? Int) ?? im.fileBytes
                im.fileSha256 = (want["file_sha256"] as? String) ?? im.fileSha256
            }
            images.append((rel, im))
        }
    } catch {
        print("art: \(error)")
    }
    writeText(config.out + "/art/decoded-frames.imageio.json", artJSON(images))
    COUNTS["art images"] = images.count
}
