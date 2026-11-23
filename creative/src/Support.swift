// Support: the run context (paths, clock, log), time through libc, the text shapes of the Python (printable, shown, lossy
// UTF-8, splitlines), regular expressions, the lstat walk that never follows a link, no-follow reads and copies, digests and
// the manifest. Foundation and CryptoKit only; names are not normalised and links are not followed (Darwin, not FileManager).
import CryptoKit
import Foundation

struct Abort: Error { let msg: String }

/// Python's repr of the error, as the log lines show it.
func describe(_ e: Error) -> String {
    if let a = e as? Abort { return "Abort(" + pyRepr(a.msg) + ")" }
    return "\(type(of: e))(" + pyRepr("\(e)") + ")"
}
func pyRepr(_ s: String) -> String { s.contains("'") && !s.contains("\"") ? "\"\(s)\"" : "'" + s.replacingOccurrences(of: "'", with: "\\'") + "'" }

/// The folders, the clock and the log sink of one run. The tests build it over temporary folders and read the log from root.
final class Ctx {
    var p: Paths
    var clock: () -> Date
    var echo: (String) -> Void
    init(_ p: Paths, clock: @escaping () -> Date = Date.init, echo: @escaping (String) -> Void = { print($0) }) {
        self.p = p; self.clock = clock; self.echo = echo
    }
    func stamp(_ fmt: String) -> String {
        var t = time_t(clock().timeIntervalSince1970), tmv = tm()
        localtime_r(&t, &tmv)
        var buf = [CChar](repeating: 0, count: 32)
        strftime(&buf, 32, fmt, &tmv)
        return String(cString: buf)
    }
    var buildID: String { stamp("%Y%m%d-%H%M%S") }
    /// One line of runs.log (0600) and the terminal; builder-controlled text is made printable first.
    func log(_ line: String) {
        mkdirp(p.root)
        let text = printable(line)
        let fd = open(p.log, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        if fd >= 0 { writeAll(fd, Array("\(stamp("%Y-%m-%d %H:%M:%S")) \(text)\n".utf8)); fchmod(fd, 0o600); close(fd) }
        echo(text)
    }
}

// ---- text ----

func printable(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.map { ($0.value >= 32 && $0.value < 127) || $0.value >= 160 ? $0 : "?" }))
}
func shown(_ s: String) -> String { String(String.UnicodeScalarView(printable(s).unicodeScalars.prefix(120))) }
func prefixChars(_ s: String, _ n: Int) -> String { String(String.UnicodeScalarView(s.unicodeScalars.prefix(n))) }
func suffixChars(_ s: String, _ n: Int) -> String { String(String.UnicodeScalarView(s.unicodeScalars.suffix(n))) }
func strip(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
func sortedBytes<S: Sequence>(_ a: S) -> [String] where S.Element == String { a.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) } }

/// bytes.decode("utf-8", errors="ignore"): invalid sequences are dropped.
func utf8Ignore(_ b: [UInt8]) -> String {
    var it = b.makeIterator(), dec = UTF8(), out = String.UnicodeScalarView()
    loop: while true {
        switch dec.decode(&it) {
        case .scalarValue(let s): out.append(s)
        case .emptyInput: break loop
        case .error: continue
        }
    }
    return String(out)
}

/// str.splitlines(): also splits on \r, \v, \f, \x1c-\x1e, \x85 and the Unicode line and paragraph separators.
func pySplitLines(_ s: String) -> [String] {
    var out: [String] = [], cur = String.UnicodeScalarView(), prevCR = false
    for u in s.unicodeScalars {
        if u == "\n" && prevCR { prevCR = false; continue }
        prevCR = u == "\r"
        if [0x0a, 0x0b, 0x0c, 0x0d, 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029].contains(u.value) { out.append(String(cur)); cur = .init() } else { cur.append(u) }
    }
    if !cur.isEmpty { out.append(String(cur)) }
    return out
}

/// str.isprintable(): no control, format, surrogate, private-use, unassigned or separator characters except a plain space.
func isPrintable(_ s: String) -> Bool {
    s.unicodeScalars.allSatisfy { u in
        if u == " " { return true }
        switch u.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator, .spaceSeparator: return false
        default: return true
        }
    }
}

// ---- regular expressions (ICU; Python `re` text) ----

private var rxCache: [String: NSRegularExpression] = [:]
func rx(_ pattern: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression {
    let key = "\(o.rawValue):\(pattern)"
    if let r = rxCache[key] { return r }
    let r = try! NSRegularExpression(pattern: pattern, options: o)
    rxCache[key] = r
    return r
}
/// re.findall as groups: one array per match, [0] the whole match, the rest the groups (nil if unset).
func rxAll(_ pattern: String, _ s: String, _ o: NSRegularExpression.Options = []) -> [[String?]] {
    let ns = s as NSString
    return rx(pattern, o).matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
        (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }
}
func rxFirst(_ pattern: String, _ s: String, _ o: NSRegularExpression.Options = []) -> [String?]? {
    rxAll(pattern, s, o).first
}
func rxCount(_ pattern: String, _ s: String) -> Int { rx(pattern).numberOfMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) }
/// re.fullmatch: the match must cover the whole string.
func rxFull(_ pattern: String, _ s: String) -> Bool {
    let len = (s as NSString).length
    return rx(pattern).firstMatch(in: s, options: .anchored, range: NSRange(location: 0, length: len))?.range.length == len
}
func rxReplace(_ pattern: String, _ s: String, _ with: String) -> String {
    rx(pattern).stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: with)
}

// ---- files ----

func lstatOf(_ path: String) -> stat? { var st = stat(); return lstat(path, &st) == 0 ? st : nil }
func lexists(_ path: String) -> Bool { lstatOf(path) != nil }
func isRegular(_ st: stat) -> Bool { st.st_mode & S_IFMT == S_IFREG }
func isDirMode(_ st: stat) -> Bool { st.st_mode & S_IFMT == S_IFDIR }
func isLinkMode(_ st: stat) -> Bool { st.st_mode & S_IFMT == S_IFLNK }
func isDir(_ p: String) -> Bool { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue }
func mkdirp(_ p: String) { try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true) }
func rmrf(_ p: String) { try? FileManager.default.removeItem(atPath: p) }
func readBytes(_ p: String) -> [UInt8]? { isDir(p) ? nil : FileManager.default.contents(atPath: p).map { [UInt8]($0) } }
func readText(_ p: String) -> String? { readBytes(p).map(utf8Ignore) }
func chmod600(_ p: String) { chmod(p, 0o600) }

func writeAll(_ fd: Int32, _ b: [UInt8]) {
    var off = 0
    while off < b.count { let n = b[off...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }; if n <= 0 { break }; off += n }
}
func readAll(_ fd: Int32, limit: Int = .max) -> [UInt8] {
    var out: [UInt8] = [], buf = [UInt8](repeating: 0, count: 1 << 16)
    while out.count < limit { let n = read(fd, &buf, min(buf.count, limit - out.count)); if n <= 0 { break }; out += buf[0..<n] }
    return out
}
/// A new file written whole, exclusively, no link followed.
func createFile(_ path: String, _ b: [UInt8], mode: mode_t = 0o644) throws {
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
    if fd < 0 { throw Abort(msg: "could not create \(shown(path)): \(String(cString: strerror(errno)))") }
    writeAll(fd, b); close(fd)
}

struct Entry { let rel, path: String; let st: stat }

/// Every entry under `root` (parents first), children sorted by name in code point order, by lstat; never follows a link.
func walk(_ root: String) throws -> [Entry] {
    var out: [Entry] = []
    func visit(_ folder: String, _ prefix: String) throws {
        guard let d = opendir(folder) else { throw Abort(msg: "cannot read \(shown(folder)): \(String(cString: strerror(errno)))") }
        var names: [String] = []
        while let e = readdir(d) {
            let n = withUnsafePointer(to: &e.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) } }
            if n != "." && n != ".." { names.append(n) }
        }
        closedir(d)
        for n in sortedBytes(names) {
            let path = folder + "/" + n
            guard let st = lstatOf(path) else { throw Abort(msg: "cannot stat \(shown(path))") }
            out.append(Entry(rel: prefix + n, path: path, st: st))
            if isDirMode(st) { try visit(path, prefix + n + "/") }
        }
    }
    try visit(root, "")
    return out
}

func isTypes(_ rel: String) -> Bool { Array(rel.split(separator: "/", omittingEmptySubsequences: false).prefix(2).map(String.init)) == C.typesDir }

/// A regular, singly linked file's text, or nil (links, FIFOs and the rest). At most `limit` bytes.
func readNoFollow(_ path: String, limit: Int = 200_000) -> String? {
    let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    if fd < 0 { return nil }
    defer { close(fd) }
    var st = stat()
    if fstat(fd, &st) != 0 || !isRegular(st) || st.st_nlink != 1 { return nil }
    return utf8Ignore(readAll(fd, limit: limit))
}

func copyFileNoFollow(_ src: String, _ dst: String) throws {
    let fd = open(src, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    if fd < 0 { throw Abort(msg: "not a plain file: \(shown(src))") }
    defer { close(fd) }
    var st = stat()
    if fstat(fd, &st) != 0 || !isRegular(st) || st.st_nlink != 1 { throw Abort(msg: "not a plain file: \(shown(src))") }
    try createFile(dst, readAll(fd))
}

/// Copy plain files and folders only, with normal modes; anything else aborts.
func copyNoFollow(_ src: String, _ dst: String) throws {
    mkdirp((dst as NSString).deletingLastPathComponent)
    if mkdir(dst, 0o755) != 0 { throw Abort(msg: "could not create \(shown(dst)): \(String(cString: strerror(errno)))") }
    for e in try walk(src) {
        let target = dst + "/" + e.rel
        if isDirMode(e.st) { if mkdir(target, 0o755) != 0 { throw Abort(msg: "could not create \(shown(e.rel))") } }
        else if isRegular(e.st) { try copyFileNoFollow(e.path, target) }
        else { throw Abort(msg: "not a plain file: \(shown(e.rel))") }
    }
}

func fileDigest(_ path: String) throws -> String {
    let fd = open(path, O_RDONLY)
    if fd < 0 { throw Abort(msg: "cannot read \(shown(path))") }
    defer { close(fd) }
    var h = SHA256(), buf = [UInt8](repeating: 0, count: 1 << 20)
    while true { let n = read(fd, &buf, buf.count); if n <= 0 { break }; h.update(data: buf[0..<n]) }
    return hex(h.finalize())
}
func hex<D: Sequence>(_ d: D) -> String where D.Element == UInt8 { d.map { String(format: "%02x", $0) }.joined() }
func sha256Hex(_ s: String) -> String { hex(SHA256.hash(data: Array(s.utf8))) }

/// sha256 of every file under `root`; anything that is not a file or folder is marked `special:<octal mode>`.
func manifest(_ root: String) throws -> [String: String] {
    var out: [String: String] = [:]
    for e in try walk(root) {
        if isRegular(e.st) { out[e.rel] = try fileDigest(e.path) }
        else if !isDirMode(e.st) { out[e.rel] = "special:" + String(e.st.st_mode, radix: 8) }
    }
    return out
}

/// The pinned tools' tree digest: L/D/F lines, byte-exact with the Python so the recorded digest verifies.
func treeDigest(_ root: String) throws -> String {
    var h = SHA256()
    for e in try walk(root) {
        let line: String
        if isLinkMode(e.st) { line = "L \(e.rel) \((try? FileManager.default.destinationOfSymbolicLink(atPath: e.path)) ?? "")\n" }
        else if isDirMode(e.st) { line = "D \(e.rel)\n" }
        else { line = "F \(e.rel) \(try fileDigest(e.path))\n" }
        h.update(data: Array(line.utf8))
    }
    return hex(h.finalize())
}

func treeSize(_ root: String) throws -> Int { try walk(root).filter { isRegular($0.st) }.reduce(0) { $0 + Int($1.st.st_size) } }
