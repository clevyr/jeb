// FrameCheck (`jebart check-frames <outdir> <expected.json>`): decode every PNG and GIF the build wrote with ImageIO and
// compare what a viewer sees with desktop/tests/golden/art/decoded-frames.imageio.json: size, format, frame count, each
// frame's delay and RGBA hash, and the loop count. File bytes are not compared (the GIF and sheet encoders differ from
// Pillow's), and neither are the PNG files' own hashes. Each frame is the composed frame ImageIO returns (GIF disposal
// applied), drawn into an 8-bit premultiplied RGBA bitmap without interpolation and hashed row by row.
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

private struct Decoded {
    var size: [Int]
    var format: String
    var frames: [(ms: Int?, sha: String)]
    var loop: Int?
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func rgbaBytes(_ image: CGImage) -> Data? {
    let w = image.width, h = image.height
    var bytes = Data(count: w * h * 4)
    let ok: Bool = bytes.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
        guard let ctx = CGContext(
            data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return false }
        ctx.interpolationQuality = .none
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? bytes : nil
}

private func decode(_ path: String) -> Decoded? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let type = CGImageSourceGetType(source) as String? ?? ""
    let format = type == "com.compuserve.gif" ? "GIF" : (type == "public.png" ? "PNG" : type)
    var frames: [(ms: Int?, sha: String)] = []
    var size = [0, 0]
    for i in 0..<CGImageSourceGetCount(source) {
        guard let image = CGImageSourceCreateImageAtIndex(source, i, nil), let bytes = rgbaBytes(image) else { return nil }
        if i == 0 { size = [image.width, image.height] }
        var ms: Int?
        if format == "GIF", let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
           let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            // the unclamped value is the file's; the plain one floors short delays to 0.1 s
            if let d = (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as? Double {
                ms = Int((d * 1000).rounded())
            }
        }
        frames.append((ms, sha256(bytes)))
    }
    var loop: Int?
    if format == "GIF", let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
       let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
        loop = gif[kCGImagePropertyGIFLoopCount] as? Int
    }
    return Decoded(size: size, format: format, frames: frames, loop: loop)
}

/// The images under `dir` the golden covers: sheets/*.png, gifs/*.gif and the top-level PNGs except icon.png.
private func imagePaths(_ dir: String) -> [String] {
    let fm = FileManager.default
    var rels: [String] = []
    for sub in ["sheets", "gifs", "."] {
        let folder = sub == "." ? dir : dir + "/" + sub
        for name in ((try? fm.contentsOfDirectory(atPath: folder)) ?? []).sorted() {
            guard name.hasSuffix(".png") || name.hasSuffix(".gif"), !(sub == "." && name == "icon.png") else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder + "/" + name, isDirectory: &isDir), !isDir.boolValue else { continue }
            rels.append(sub == "." ? name : sub + "/" + name)
        }
    }
    return rels
}

/// Returns the exit status: 0 when every file matches, 1 otherwise.
func checkFrames(outDir: String, expectedPath: String) -> Int32 {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: expectedPath)),
          let expected = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else {
        FileHandle.standardError.write(Data("jebart: cannot read \(expectedPath)\n".utf8))
        return 2
    }
    var bad: [String] = []
    let produced = imagePaths(outDir)
    for rel in expected.keys.sorted() where !produced.contains(rel) { bad.append("missing: \(rel)") }
    for rel in produced where expected[rel] == nil { bad.append("extra: \(rel)") }
    for rel in produced {
        guard let want = expected[rel] else { continue }
        guard let got = decode(outDir + "/" + rel) else { bad.append("\(rel): cannot decode"); continue }
        if let size = want["size"] as? [Int], size != got.size { bad.append("\(rel): size \(got.size), want \(size)") }
        if let format = want["format"] as? String, format != got.format { bad.append("\(rel): format \(got.format), want \(format)") }
        let wantFrames = (want["frames"] as? [[String: Any]]) ?? []
        if wantFrames.count != got.frames.count {
            bad.append("\(rel): \(got.frames.count) frames, want \(wantFrames.count)")
            continue
        }
        for (i, f) in wantFrames.enumerated() {
            if (f["sha256"] as? String) != got.frames[i].sha { bad.append("\(rel): frame \(i) pixels differ") }
            // a PNG has no delay (null); a GIF's is milliseconds
            let wantMs = f["ms"] as? Int
            if wantMs != got.frames[i].ms { bad.append("\(rel): frame \(i) delay \(got.frames[i].ms.map(String.init) ?? "none"), want \(wantMs.map(String.init) ?? "none")") }
        }
        let wantLoop = want["loop"] as? Int
        if wantLoop != got.loop { bad.append("\(rel): loop \(got.loop.map(String.init) ?? "none"), want \(wantLoop.map(String.init) ?? "none")") }
    }
    for line in bad.prefix(40) { print(line) }
    if bad.count > 40 { print("... and \(bad.count - 40) more") }
    print(bad.isEmpty ? "check-frames: \(produced.count) images match" : "check-frames: \(bad.count) difference(s) in \(produced.count) images")
    return bad.isEmpty ? 0 : 1
}
