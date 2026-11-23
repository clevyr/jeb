// RasterCheck: `jebart raster-check <raster-cases.json>` replays the fixture captured from Pillow. Each case draws its
// ops in order on a blank canvas of `size` (or on `canvas`) and must end with exactly the recorded pixels and the
// recorded sha256 of the RGBA bytes, or, for the six inverted boxes, with the ValueError Pillow raised. Prints a pass
// count per primitive and, for each failure, the case id and the first pixels that differ. The fixture's `about`
// block documents the fields.
import CryptoKit
import Foundation

private struct CaseFailure: Error { let why: String }

private func ints(_ v: Any?) throws -> [Int] {
    guard let a = v as? [Any] else { throw CaseFailure(why: "expected a list of numbers") }
    var out: [Int] = []
    for item in a {
        if let pair = item as? [Any] { out += try ints(pair); continue }
        guard let n = item as? NSNumber else { throw CaseFailure(why: "expected a number") }
        out.append(n.intValue)      // Pillow's C side truncates the same way
    }
    return out
}

private func pairs(_ v: Any?) throws -> [(Int, Int)] {
    let flat = try ints(v)
    guard flat.count % 2 == 0 else { throw CaseFailure(why: "odd number of coordinates") }
    return stride(from: 0, to: flat.count, by: 2).map { (flat[$0], flat[$0 + 1]) }
}

private func colour(_ v: Any?) throws -> RGBA {
    let c = try ints(v)
    guard c.count == 4, c.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { throw CaseFailure(why: "a colour is [r, g, b, a]") }
    return RGBA(UInt8(c[0]), UInt8(c[1]), UInt8(c[2]), UInt8(c[3]))
}

private func optionalColour(_ v: Any?) throws -> RGBA? { v == nil || v is NSNull ? nil : try colour(v) }

private func image(_ v: Any?) throws -> Raster {
    guard let d = v as? [String: Any], let rows = d["rgba"] as? [String] else { throw CaseFailure(why: "expected {size, rgba}") }
    let size = try ints(d["size"])
    guard size.count == 2, rows.count == size[1] else { throw CaseFailure(why: "rgba rows do not match the size") }
    var px: [RGBA] = []
    for row in rows {
        let u = Array(row.utf8)
        guard u.count == size[0] * 8 else { throw CaseFailure(why: "an rgba row does not match the width") }
        for i in stride(from: 0, to: u.count, by: 8) {
            guard let n = UInt32(String(decoding: u[i..<(i + 8)], as: UTF8.self), radix: 16) else { throw CaseFailure(why: "bad hex pixel") }
            px.append(RGBA(UInt8(n >> 24), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)))
        }
    }
    return Raster(size[0], size[1], pixels: px)
}

private func number(_ v: Any?) throws -> Float {
    guard let n = v as? NSNumber else { throw CaseFailure(why: "expected a number") }
    return n.floatValue
}

/// Runs one op. Returns the canvas to go on with (resize makes a new one) or the ValueError text Pillow would raise.
private func apply(_ op: [String: Any], to im: Raster) throws -> (Raster, String?) {
    guard let name = op["op"] as? String else { throw CaseFailure(why: "an op has no name") }
    func box() throws -> (Int, Int, Int, Int)? {
        let b = try ints(op["xy"])
        guard b.count == 4 else { throw CaseFailure(why: "a box is [x0, y0, x1, y1]") }
        return (b[0], b[1], b[2], b[3])
    }
    switch name {
    case "rectangle", "ellipse", "arc", "chord":
        guard let (x0, y0, x1, y1) = try box() else { break }
        if let why = Raster.boxError(x0, y0, x1, y1) { return (im, "ValueError: " + why) }
        switch name {
        case "rectangle": im.rectangle(x0, y0, x1, y1, fill: try optionalColour(op["fill"]), outline: try optionalColour(op["outline"]))
        case "ellipse": im.ellipse(x0, y0, x1, y1, fill: try optionalColour(op["fill"]), outline: try optionalColour(op["outline"]))
        case "arc":
            let width = try op["width"].map { try ints([$0])[0] } ?? 1
            im.arc(x0, y0, x1, y1, start: try number(op["start"]), end: try number(op["end"]), fill: try colour(op["fill"]), width: width)
        default: im.chord(x0, y0, x1, y1, start: try number(op["start"]), end: try number(op["end"]), fill: try colour(op["fill"]))
        }
    case "line":
        let width = try op["width"].map { try ints([$0])[0] } ?? 0
        im.line(try pairs(op["xy"]), fill: try colour(op["fill"]), width: width)
    case "point":
        im.points(try pairs(op["xy"]), fill: try colour(op["fill"]))
    case "polygon":
        im.polygon(try pairs(op["xy"]), fill: try optionalColour(op["fill"]), outline: try optionalColour(op["outline"]))
    case "alpha_composite":
        let dest = try ints(op["dest"])
        guard dest.count == 2 else { throw CaseFailure(why: "dest is [x, y]") }
        im.alphaComposite(try image(op["src"]), at: dest[0], dest[1])
    case "resize":
        let size = try ints(op["size"])
        guard size.count == 2, op["method"] as? String == "NEAREST" else { throw CaseFailure(why: "resize takes a size and NEAREST") }
        return (im.resized(size[0], size[1]), nil)
    default:
        throw CaseFailure(why: "unknown op \(name)")
    }
    return (im, nil)
}

/// nil when the case passes, else what differs.
private func runCase(_ c: [String: Any]) -> String? {
    do {
        guard let ops = c["ops"] as? [[String: Any]] else { throw CaseFailure(why: "no ops") }
        var im: Raster
        if c["canvas"] != nil { im = try image(c["canvas"]) } else {
            let size = try ints(c["size"])
            guard size.count == 2 else { throw CaseFailure(why: "size is [w, h]") }
            im = Raster(size[0], size[1])
        }
        var raised: String?
        for op in ops {
            let (next, error) = try apply(op, to: im)
            im = next
            if let error = error { raised = error; break }
        }
        if let want = c["error"] as? String {
            return raised == want ? nil : "want the error \"\(want)\", got \(raised.map { "\"\($0)\"" } ?? "a drawing")"
        }
        if let raised = raised { return "raised \"\(raised)\" where Pillow drew" }
        guard let result = c["result"] as? [String: Any] else { throw CaseFailure(why: "neither result nor error") }
        let size = try ints(result["size"])
        guard size == [im.width, im.height] else { return "size \(im.width)x\(im.height), want \(size)" }

        var want: [RGBA]
        if let rows = result["mask"] as? [String] {
            let fill = try colour(ops.last?["fill"])
            want = []
            for row in rows { for ch in row.utf8 { want.append(ch == UInt8(ascii: "#") ? fill : .clear) } }
            guard want.count == im.pixels.count else { throw CaseFailure(why: "mask does not match the size") }
        } else {
            want = try image(result).pixels
        }
        var diffs: [String] = []
        var count = 0
        for (i, p) in im.pixels.enumerated() where p != want[i] {
            count += 1
            if diffs.count < 6 { diffs.append("(\(i % im.width),\(i / im.width)) got \(p.hex) want \(want[i].hex)") }
        }
        if count > 0 { return "\(count) pixel\(count == 1 ? "" : "s") differ: " + diffs.joined(separator: "; ") + (count > diffs.count ? "; ..." : "") }
        if let sha = result["sha256"] as? String {
            let got = SHA256.hash(data: Data(im.bytes)).map { String(format: "%02x", $0) }.joined()
            if got != sha { return "pixels match the rows but sha256 is \(got), want \(sha)" }
        }
        return nil
    } catch let e as CaseFailure {
        return "unusable case: \(e.why)"
    } catch {
        return "unusable case: \(error)"
    }
}

/// Exit status: 0 when every case passes, 1 otherwise, 2 when the file cannot be read.
func rasterCheck(_ path: String) -> Int32 {
    guard let data = FileManager.default.contents(atPath: path),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cases = root["cases"] as? [[String: Any]] else {
        FileHandle.standardError.write(Data("raster-check: cannot read cases from \(path)\n".utf8))
        return 2
    }
    var order: [String] = []
    var passed: [String: Int] = [:], total: [String: Int] = [:]
    var failures: [String] = []
    for c in cases {
        let id = c["id"] as? String ?? "?"
        let kind = String(id.split(separator: "-").first ?? "?")
        if total[kind] == nil { order.append(kind) }
        total[kind, default: 0] += 1
        if let why = runCase(c) { failures.append("FAIL \(id): \(why)") } else { passed[kind, default: 0] += 1 }
    }
    for f in failures { print(f) }
    for kind in order { print("\(kind): \(passed[kind] ?? 0) of \(total[kind] ?? 0)") }
    print("\(cases.count - failures.count) of \(cases.count) cases passed")
    return failures.isEmpty ? 0 : 1
}
