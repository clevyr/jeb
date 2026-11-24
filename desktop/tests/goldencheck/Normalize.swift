// Normalize.swift: the golden text rules (norm, path_subs, section, pretty_json) the goldens were frozen with and a JSON
// value that re-serializes the way Python's json.dumps does (sort_keys, indent=1, ", "/": " separators, ensure_ascii).
import CryptoKit
import Foundation

// MARK: - files

func readText(_ path: String) -> String? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return String(decoding: d, as: UTF8.self)
}

func readBytes(_ path: String) -> Data? {
    FileManager.default.contents(atPath: path)
}

func writeText(_ path: String, _ text: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: path, contents: Data(text.utf8)) else { fail("could not write \(path)") }
}

func mkdirs(_ path: String) {
    do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) } catch { fail("mkdir \(path): \(error)") }
}

func copyFile(_ from: String, _ to: String) {
    let fm = FileManager.default
    if fm.fileExists(atPath: to) { try? fm.removeItem(atPath: to) }
    do { try fm.copyItem(atPath: from, toPath: to) } catch { fail("copy \(from) -> \(to): \(error)") }
}

func removeAll(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

func isFile(_ path: String) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &d) && !d.boolValue
}

func isDir(_ path: String) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
}

func chmod(_ path: String, _ mode: Int) {
    try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
}

func listDir(_ path: String) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted(by: pyLess)
}

/// Every file under `root`, as relative paths, sorted (os.walk + relpath + sort).
func walkFiles(_ root: String) -> [String] {
    var out: [String] = []
    guard let e = FileManager.default.enumerator(atPath: root) else { return out }
    while let rel = e.nextObject() as? String {
        if isFile(root + "/" + rel) { out.append(rel) }
    }
    return out.sorted(by: pyLess)
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("goldencheck: " + msg + "\n").utf8))
    exit(1)
}

func join(_ parts: String...) -> String {
    parts.dropFirst().reduce(parts[0]) { a, b in b.hasPrefix("/") ? b : (a.hasSuffix("/") ? a + b : a + "/" + b) }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Python's str ordering: by code point.
func pyLess(_ a: String, _ b: String) -> Bool {
    a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
}

// MARK: - paths (os.path.normpath / realpath)

func normPath(_ p: String) -> String {
    if p.isEmpty { return "." }
    let abs = p.hasPrefix("/")
    var parts: [String] = []
    for c in p.split(separator: "/", omittingEmptySubsequences: true) {
        if c == "." { continue }
        if c == ".." {
            if let last = parts.last, last != ".." { parts.removeLast() } else if !abs { parts.append("..") }
            continue
        }
        parts.append(String(c))
    }
    let s = parts.joined(separator: "/")
    if abs { return (p.hasPrefix("//") && !p.hasPrefix("///") ? "//" : "/") + s }
    return s.isEmpty ? "." : s
}

func realPath(_ p: String) -> String {
    guard let r = realpath(p, nil) else { return normPath(p) }
    defer { free(r) }
    return String(cString: r)
}

/// (path, token) for every spelling of each root: as given, normalized and resolved. Longest first (stable for ties).
func pathSubs(_ roots: [(String, String)]) -> [(String, String)] {
    var out: [(String, String)] = []
    var seen = Set<String>()
    for (root, token) in roots {
        for var p in [root, normPath(root), realPath(root)] {
            while p.hasSuffix("/") { p.removeLast() }
            if !p.isEmpty && !seen.contains(p) { seen.insert(p); out.append((p, token)) }
        }
    }
    return out.enumerated().sorted { a, b in
        a.element.0.utf8.count != b.element.0.utf8.count ? a.element.0.utf8.count > b.element.0.utf8.count : a.offset < b.offset
    }.map { $0.element }
}

// MARK: - norm

struct Rule {
    let re: NSRegularExpression
    let template: String
    init(_ pattern: String, _ template: String) {
        re = try! NSRegularExpression(pattern: pattern)
        self.template = template
    }
    func apply(_ s: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}

let fixedRules: [Rule] = [
    Rule(#"gui/\d+\b"#, "gui/\\$UID"),
    Rule(#"\b[0-9a-f]{64}\b"#, "\\$SHA256"),
    Rule(#"SHA256:[A-Za-z0-9+/]{43}"#, "\\$FINGERPRINT"),
    Rule(#"\((\d+)s\)"#, "(\\$Ns)"),
    Rule(#"\b\d+ (KB|MB)\b"#, "\\$N $1"),
    Rule(#"sha256 [0-9a-f]{16}\b"#, "sha256 \\$SHA16"),
]

func norm(_ text: String, _ sb: SB? = nil) -> String {
    let c = config!
    var roots: [(String, String)] = sb.map { [($0.root, "$SB")] } ?? []
    roots += [(c.tmp, "$T"), (c.root, "$REPO"), (c.realHome, "$REALHOME")]
    var subs = pathSubs(roots)
    for k in pubOrder { subs.append((c.pub[k]!, "$PUB_\(k)")) }
    for k in pubOrder { subs.append((c.pub[k]!.split(separator: " ")[1].description, "$PUBBLOB_\(k)")) }
    var s = text
    for (a, b) in subs { s = s.replacingOccurrences(of: a, with: b) }
    if let h = c.headRule { s = h.apply(s) }
    for r in fixedRules { s = r.apply(s) }
    s = s.replacingOccurrences(of: c.arch, with: "$ARCH")
    return s
}

func section(_ title: String, _ body: String) -> String {
    var b = body
    while b.hasSuffix("\n") { b.removeLast() }
    let blank = b.allSatisfy { $0.isWhitespace }
    return "## \(title)\n\(blank ? "(empty)" : b)\n\n"
}

func prettyJSON(_ text: String, _ sb: SB? = nil) -> String {
    let n = norm(text, sb)
    guard let v = try? JSON.parse(n) else { return "(not JSON) " + n }
    return v.dumps(indent: 1, sortKeys: true)
}

// MARK: - JSON (ordered, Python json.dumps shapes)

indirect enum JSON {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    struct ParseError: Error { let msg: String }

    subscript(_ key: String) -> JSON? {
        if case .object(let o) = self { return o.first { $0.0 == key }?.1 }
        return nil
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var arrayValue: [JSON]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [(String, JSON)]? { if case .object(let o) = self { return o }; return nil }

    /// Replace (or add) a key in an object, keeping order.
    func setting(_ key: String, _ value: JSON) -> JSON {
        guard case .object(var o) = self else { return self }
        if let i = o.firstIndex(where: { $0.0 == key }) { o[i].1 = value } else { o.append((key, value)) }
        return .object(o)
    }

    static func parse(_ text: String) throws -> JSON {
        var p = Parser(s: Array(text.unicodeScalars))
        p.ws()
        let v = try p.value()
        p.ws()
        if p.i != p.s.count { throw ParseError(msg: "trailing data") }
        return v
    }

    struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        mutating func ws() { while i < s.count, " \t\n\r".unicodeScalars.contains(s[i]) { i += 1 } }
        func peek() -> Unicode.Scalar? { i < s.count ? s[i] : nil }
        mutating func expect(_ lit: String) throws {
            for c in lit.unicodeScalars {
                guard i < s.count, s[i] == c else { throw ParseError(msg: "expected \(lit)") }
                i += 1
            }
        }
        mutating func value() throws -> JSON {
            guard let c = peek() else { throw ParseError(msg: "eof") }
            switch c {
            case "{":
                i += 1; ws()
                var o: [(String, JSON)] = []
                if peek() == "}" { i += 1; return .object(o) }
                while true {
                    ws()
                    guard peek() == "\"" else { throw ParseError(msg: "key") }
                    let k = try string()
                    ws(); try expect(":"); ws()
                    o.append((k, try value()))
                    ws()
                    if peek() == "," { i += 1; continue }
                    try expect("}")
                    return .object(o)
                }
            case "[":
                i += 1; ws()
                var a: [JSON] = []
                if peek() == "]" { i += 1; return .array(a) }
                while true {
                    ws()
                    a.append(try value())
                    ws()
                    if peek() == "," { i += 1; continue }
                    try expect("]")
                    return .array(a)
                }
            case "\"": return .string(try string())
            case "t": try expect("true"); return .bool(true)
            case "f": try expect("false"); return .bool(false)
            case "n": try expect("null"); return .null
            default:
                let start = i
                while i < s.count, "+-0123456789.eE".unicodeScalars.contains(s[i]) { i += 1 }
                let lit = String(String.UnicodeScalarView(s[start..<i]))
                if lit.isEmpty { throw ParseError(msg: "bad value") }
                if lit.contains(".") || lit.contains("e") || lit.contains("E") {
                    guard let d = Double(lit) else { throw ParseError(msg: "bad number") }
                    return .double(d)
                }
                guard let n = Int(lit) else { throw ParseError(msg: "bad int") }
                return .int(n)
            }
        }
        mutating func string() throws -> String {
            try expect("\"")
            var out = String.UnicodeScalarView()
            while true {
                guard i < s.count else { throw ParseError(msg: "unterminated string") }
                let c = s[i]; i += 1
                if c == "\"" { return String(out) }
                if c != "\\" { out.append(c); continue }
                guard i < s.count else { throw ParseError(msg: "bad escape") }
                let e = s[i]; i += 1
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "b": out.append("\u{8}")
                case "f": out.append("\u{c}")
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "u":
                    var code = try hex4()
                    if code >= 0xD800 && code < 0xDC00, i + 1 < s.count, s[i] == "\\", s[i + 1] == "u" {
                        i += 2
                        let lo = try hex4()
                        if lo >= 0xDC00 && lo < 0xE000 { code = 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00) }
                    }
                    out.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default: throw ParseError(msg: "bad escape")
                }
            }
        }
        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= s.count, let v = UInt32(String(String.UnicodeScalarView(s[i..<i + 4])), radix: 16) else { throw ParseError(msg: "bad \\u") }
            i += 4
            return v
        }
    }

    /// json.dumps: indent=nil gives the compact ", " / ": " form; indent=n the multi-line form.
    func dumps(indent: Int? = nil, sortKeys: Bool = false) -> String {
        var out = ""
        write(into: &out, indent: indent, sortKeys: sortKeys, level: 0)
        return out
    }

    private func write(into out: inout String, indent: Int?, sortKeys: Bool, level: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let n): out += String(n)
        case .double(let d): out += pyFloatRepr(d)
        case .string(let s): out += JSON.quote(s)
        case .array(let a):
            if a.isEmpty { out += "[]"; return }
            out += "["
            for (n, v) in a.enumerated() {
                if n > 0 { out += "," }
                if let ind = indent { out += "\n" + String(repeating: " ", count: ind * (level + 1)) } else if n > 0 { out += " " }
                v.write(into: &out, indent: indent, sortKeys: sortKeys, level: level + 1)
            }
            if let ind = indent { out += "\n" + String(repeating: " ", count: ind * level) }
            out += "]"
        case .object(let o):
            if o.isEmpty { out += "{}"; return }
            let items = sortKeys ? o.sorted { pyLess($0.0, $1.0) } : o
            out += "{"
            for (n, (k, v)) in items.enumerated() {
                if n > 0 { out += "," }
                if let ind = indent { out += "\n" + String(repeating: " ", count: ind * (level + 1)) } else if n > 0 { out += " " }
                out += JSON.quote(k) + ": "
                v.write(into: &out, indent: indent, sortKeys: sortKeys, level: level + 1)
            }
            if let ind = indent { out += "\n" + String(repeating: " ", count: ind * level) }
            out += "}"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{8}": out += "\\b"
            case "\u{c}": out += "\\f"
            default:
                if u.value < 0x20 || u.value > 0x7e {
                    if u.value > 0xFFFF {
                        let v = u.value - 0x10000
                        out += String(format: "\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                    } else {
                        out += String(format: "\\u%04x", u.value)
                    }
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }
}

/// Python's repr(float): shortest round-trip digits; Swift's description agrees on the digits and the exponent thresholds.
func pyFloatRepr(_ d: Double) -> String {
    if d.isNaN { return "NaN" }
    if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
    return d.description
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByNilLiteral {
    init(stringLiteral v: String) { self = .string(v) }
    init(integerLiteral v: Int) { self = .int(v) }
    init(booleanLiteral v: Bool) { self = .bool(v) }
    init(arrayLiteral e: JSON...) { self = .array(e) }
    init(nilLiteral: ()) { self = .null }
}

/// An ordered object literal: obj(("a", 1), ("b", "x")).
func obj(_ pairs: (String, JSON)...) -> JSON { .object(pairs) }
func obj(_ pairs: [(String, JSON)]) -> JSON { .object(pairs) }
func strs(_ a: [String]) -> JSON { .array(a.map { .string($0) }) }
