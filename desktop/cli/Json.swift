// Json: an insertion-ordered JSON value whose text matches Python's json.dumps byte for byte in the three shapes the
// Python used (indent=1 for state files and probes, indent=2, and the default compact `, `/`: ` form of json.dump), plus
// the reader (keys kept in file order, as a Python dict would) and the 0600 tmp+rename writes every state file uses.
// JSONSerialization is not used: it drops key order and prints numbers and escapes its own way.
import Foundation

indirect enum Json: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([Json])
    case object([(String, Json)])

    static func == (a: Json, b: Json) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.int(x), .int(y)): return x == y
        case let (.double(x), .double(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.array(x), .array(y)): return x == y
        case let (.object(x), .object(y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    // ---- reading fields ----

    subscript(key: String) -> Json? {
        if case let .object(kv) = self { return kv.first { $0.0 == key }?.1 }
        return nil
    }
    var string: String? { if case let .string(s) = self { return s }; return nil }
    var int: Int? {
        switch self {
        case let .int(i): return i
        case let .double(d): return d == d.rounded() && abs(d) < 1e15 ? Int(d) : nil
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case let .int(i): return Double(i)
        case let .double(d): return d
        default: return nil
        }
    }
    var bool: Bool? { if case let .bool(b) = self { return b }; return nil }
    var array: [Json]? { if case let .array(a) = self { return a }; return nil }
    var object: [(String, Json)]? { if case let .object(o) = self { return o }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }
    /// Python truthiness: null, false, 0, "", [] and {} are false.
    var truthy: Bool {
        switch self {
        case .null: return false
        case let .bool(b): return b
        case let .int(i): return i != 0
        case let .double(d): return d != 0
        case let .string(s): return !s.isEmpty
        case let .array(a): return !a.isEmpty
        case let .object(o): return !o.isEmpty
        }
    }

    /// dict assignment: replaces the value in place (keeping the key's position) or appends the key.
    mutating func set(_ key: String, _ value: Json) {
        guard case var .object(kv) = self else { self = .object([(key, value)]); return }
        if let i = kv.firstIndex(where: { $0.0 == key }) { kv[i].1 = value } else { kv.append((key, value)) }
        self = .object(kv)
    }

    mutating func remove(_ key: String) {
        guard case var .object(kv) = self else { return }
        kv.removeAll { $0.0 == key }
        self = .object(kv)
    }

    // ---- writing ----

    /// json.dumps(v, indent=indent): indent nil is the compact default (`, ` between items, `: ` after keys).
    func dumps(indent: Int? = nil) -> String {
        var out = ""
        write(into: &out, indent: indent, depth: 0)
        return out
    }

    private func write(into out: inout String, indent: Int?, depth: Int) {
        switch self {
        case .null: out += "null"
        case let .bool(b): out += b ? "true" : "false"
        case let .int(i): out += String(i)
        case let .double(d): out += Json.pyFloat(d)
        case let .string(s): out += Json.quote(s)
        case let .array(a):
            if a.isEmpty { out += "[]"; return }
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                Json.newline(into: &out, indent: indent, depth: depth + 1, first: i == 0)
                v.write(into: &out, indent: indent, depth: depth + 1)
            }
            Json.newline(into: &out, indent: indent, depth: depth, first: true)
            out += "]"
        case let .object(kv):
            if kv.isEmpty { out += "{}"; return }
            out += "{"
            for (i, (k, v)) in kv.enumerated() {
                if i > 0 { out += "," }
                Json.newline(into: &out, indent: indent, depth: depth + 1, first: i == 0)
                out += Json.quote(k) + ": "
                v.write(into: &out, indent: indent, depth: depth + 1)
            }
            Json.newline(into: &out, indent: indent, depth: depth, first: true)
            out += "}"
        }
    }

    /// Between items: a newline plus the indent, or the compact form's single space after the comma.
    private static func newline(into out: inout String, indent: Int?, depth: Int, first: Bool) {
        if let n = indent { out += "\n" + String(repeating: " ", count: n * depth) }
        else if !first { out += " " }
    }

    /// json's ensure_ascii string: everything outside space..~ is \uXXXX (astral characters as a surrogate pair).
    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.utf16 {
            switch u {
            case 0x22: out += "\\\""
            case 0x5c: out += "\\\\"
            case 0x0a: out += "\\n"
            case 0x0d: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0c: out += "\\f"
            case 0x20...0x7e: out.unicodeScalars.append(Unicode.Scalar(u)!)
            default: out += String(format: "\\u%04x", u)
            }
        }
        return out + "\""
    }

    /// float.__repr__: the shortest round-trip digits (Swift's description supplies them), laid out Python's way: plain
    /// decimal with a fraction for exponents -4 ... 15, else d.ddde+XX with a two-digit exponent.
    static func pyFloat(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        var s = "\(d)"
        let neg = s.hasPrefix("-")
        if neg { s.removeFirst() }
        var mant = s, exp = 0
        if let e = s.firstIndex(of: "e") { mant = String(s[..<e]); exp = Int(s[s.index(after: e)...]) ?? 0 }
        var digits = mant.replacingOccurrences(of: ".", with: "")
        var point = (mant.firstIndex(of: ".").map { mant.distance(from: mant.startIndex, to: $0) } ?? mant.count) + exp
        while digits.count > 1 && digits.hasPrefix("0") { digits.removeFirst(); point -= 1 }
        while digits.count > 1 && digits.hasSuffix("0") { digits.removeLast() }
        let sci = point - 1
        var out: String
        if digits == "0" { out = "0.0" }
        else if sci < -4 || sci >= 16 {
            out = (digits.count > 1 ? String(digits.first!) + "." + digits.dropFirst() : digits) + "e" + (sci < 0 ? "-" : "+") + String(format: "%02d", abs(sci))
        } else if point <= 0 { out = "0." + String(repeating: "0", count: -point) + digits }
        else if point >= digits.count { out = digits + String(repeating: "0", count: point - digits.count) + ".0" }
        else { out = String(digits.prefix(point)) + "." + String(digits.dropFirst(point)) }
        return (neg ? "-" : "") + out
    }

    // ---- parsing ----

    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    /// json.loads: objects keep their key order. Trailing data, comments and NaN literals are refused.
    static func parse(_ text: String) throws -> Json {
        var p = Parser(Array(text.utf8))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        guard p.i == p.b.count else { throw ParseError(description: "Extra data at byte \(p.i)") }
        return v
    }

    static func parse(_ data: Data) throws -> Json {
        guard let s = String(data: data, encoding: .utf8) else { throw ParseError(description: "not UTF-8") }
        return try parse(s)
    }

    /// The file's JSON, or nil when it is missing or not JSON (the Python's `except (OSError, ValueError)`).
    static func load(_ path: String) -> Json? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return try? parse(d)
    }

    private struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ bytes: [UInt8]) { b = bytes }

        mutating func skipSpace() { while i < b.count, [0x20, 0x09, 0x0a, 0x0d].contains(b[i]) { i += 1 } }

        func fail(_ what: String) -> ParseError { ParseError(description: "\(what) at byte \(i)") }

        mutating func value() throws -> Json {
            guard i < b.count else { throw fail("Expecting value") }
            switch b[i] {
            case 0x7b: return try object()
            case 0x5b: return try array()
            case 0x22: return .string(try string())
            case 0x74: try literal("true"); return .bool(true)
            case 0x66: try literal("false"); return .bool(false)
            case 0x6e: try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard i + w.count <= b.count, Array(b[i..<i + w.count]) == w else { throw fail("Expecting value") }
            i += w.count
        }

        mutating func object() throws -> Json {
            i += 1
            var kv: [(String, Json)] = []
            skipSpace()
            if i < b.count, b[i] == 0x7d { i += 1; return .object(kv) }
            while true {
                skipSpace()
                guard i < b.count, b[i] == 0x22 else { throw fail("Expecting property name enclosed in double quotes") }
                let k = try string()
                skipSpace()
                guard i < b.count, b[i] == 0x3a else { throw fail("Expecting ':' delimiter") }
                i += 1
                skipSpace()
                let v = try value()
                if let j = kv.firstIndex(where: { $0.0 == k }) { kv[j].1 = v } else { kv.append((k, v)) }    // a repeated key: the last wins, first position kept
                skipSpace()
                guard i < b.count else { throw fail("Expecting ',' delimiter") }
                if b[i] == 0x2c { i += 1; continue }
                if b[i] == 0x7d { i += 1; return .object(kv) }
                throw fail("Expecting ',' delimiter")
            }
        }

        mutating func array() throws -> Json {
            i += 1
            var out: [Json] = []
            skipSpace()
            if i < b.count, b[i] == 0x5d { i += 1; return .array(out) }
            while true {
                skipSpace()
                out.append(try value())
                skipSpace()
                guard i < b.count else { throw fail("Expecting ',' delimiter") }
                if b[i] == 0x2c { i += 1; continue }
                if b[i] == 0x5d { i += 1; return .array(out) }
                throw fail("Expecting ',' delimiter")
            }
        }

        mutating func string() throws -> String {
            i += 1
            var units: [UInt16] = []
            var raw: [UInt8] = []
            func flush() { if !raw.isEmpty { units += Array(String(decoding: raw, as: UTF8.self).utf16); raw = [] } }
            while true {
                guard i < b.count else { throw fail("Unterminated string") }
                let c = b[i]
                if c == 0x22 { i += 1; break }
                if c == 0x5c {
                    flush()
                    i += 1
                    guard i < b.count else { throw fail("Unterminated string") }
                    switch b[i] {
                    case 0x22: units.append(0x22)
                    case 0x5c: units.append(0x5c)
                    case 0x2f: units.append(0x2f)
                    case 0x62: units.append(0x08)
                    case 0x66: units.append(0x0c)
                    case 0x6e: units.append(0x0a)
                    case 0x72: units.append(0x0d)
                    case 0x74: units.append(0x09)
                    case 0x75:
                        guard i + 4 < b.count, let u = UInt16(String(decoding: b[i + 1...i + 4], as: UTF8.self), radix: 16) else { throw fail("Invalid \\uXXXX escape") }
                        units.append(u)
                        i += 4
                    default: throw fail("Invalid \\escape")
                    }
                    i += 1
                    continue
                }
                if c < 0x20 { throw fail("Invalid control character") }
                raw.append(c)
                i += 1
            }
            flush()
            return String(decoding: units, as: UTF16.self)
        }

        mutating func number() throws -> Json {
            let start = i
            if i < b.count, b[i] == 0x2d { i += 1 }
            var isInt = true
            while i < b.count {
                let c = b[i]
                if c >= 0x30 && c <= 0x39 { i += 1; continue }
                if c == 0x2e || c == 0x65 || c == 0x45 || c == 0x2b || c == 0x2d { isInt = false; i += 1; continue }
                break
            }
            let text = String(decoding: b[start..<i], as: UTF8.self)
            if isInt, let v = Int(text) { return .int(v) }
            if let v = Double(text), !text.isEmpty, text != "-" { return .double(v) }
            i = start
            throw fail("Expecting value")
        }
    }
}

// ---- files ----

/// Writes bytes to path through path.tmp and a rename, mode 0600 (os.open(O_CREAT|O_TRUNC, 0o600) + os.replace).
/// The mode is forced even when path.tmp already existed. Throws the errno text.
func writePrivate(_ data: Data, to path: String) throws {
    let tmp = path + ".tmp"
    let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    guard fd >= 0 else { throw posixError("open", tmp) }
    fchmod(fd, 0o600)
    let ok = data.withUnsafeBytes { p -> Bool in
        var off = 0
        while off < p.count {
            let n = write(fd, p.baseAddress! + off, p.count - off)
            if n <= 0 { return false }
            off += n
        }
        return true
    }
    let err = ok ? 0 : errno
    close(fd)
    guard ok else { unlink(tmp); throw posixError("write", tmp, err) }
    guard rename(tmp, path) == 0 else { let e = errno; unlink(tmp); throw posixError("rename", path, e) }
}

func writePrivate(_ text: String, to path: String) throws { try writePrivate(Data(text.utf8), to: path) }

/// json.dump(doc, f, indent=indent) into a 0600 file, atomically.
func writeJson(_ doc: Json, to path: String, indent: Int? = nil) throws {
    try writePrivate(doc.dumps(indent: indent), to: path)
}

/// os.makedirs(path, mode=0o700, exist_ok=True): the folder is created 0700; an existing one is left as it is.
func makePrivateDir(_ path: String) {
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
}

struct PosixError: Error, CustomStringConvertible {
    let op: String, path: String, code: Int32
    var reason: String { String(cString: strerror(code)) }
    var description: String { "\(op) \(path): \(reason)" }
}

func posixError(_ op: String, _ path: String, _ code: Int32? = nil) -> PosixError {
    PosixError(op: op, path: path, code: code ?? errno)
}

/// The file's mode bits as Python's oct(st_mode & 0o777), e.g. "0o600".
func fileMode(_ path: String) -> String? {
    var st = stat()
    guard stat(path, &st) == 0 else { return nil }
    return "0o" + String(Int(st.st_mode & 0o777), radix: 8)
}
