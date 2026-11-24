// Support: what Parity, Day and Fake share: the folders a run works in, the clock (JEB_TEST_NOW pins it and a sleep then
// advances it instead of waiting, as the golden capture's runner did for the Python fake tool), local time through libc (mktime and
// localtime_r, so TZ decides as it did for the Python), child processes, regular expressions, and the Python text shapes
// the tools print (repr of strings, lists and tuples; %-style numbers). Foundation only. The ordered JSON value (Json)
// is desktop/cli/Json.swift, compiled in by build.sh; the literals below only make the fixtures table readable.
import Foundation

// ---- where things are ----

/// The folders of one run: src is desktop/src (fixtures, tools, modcopy), bin the desktop binary to drive.
struct Places {
    var src: String
    var bin: String?
    var fixtures: String { src + "/fixtures" }
    var out: String { src + "/fixtures/out" }
    var tools: String { src + "/tools" }
    /// The mod's art (JEB_MOD, else the repo's mod folder two levels above src).
    var art: String {
        let mod = environ("JEB_MOD").flatMap { $0.isEmpty ? nil : $0 } ?? parentDir(parentDir(src)) + "/mod"
        return mod + "/hooks/pixel-art.ts"
    }
    /// --bin, else JEB_BIN, else the given default; a relative name is looked up in src (os.path.join(HERE, ...)).
    func binary(default name: String) -> String {
        let b = bin ?? environ("JEB_BIN") ?? name
        return b.hasPrefix("/") ? b : src + "/" + b
    }
}

func environ(_ name: String) -> String? {
    guard let v = getenv(name) else { return nil }
    return String(cString: v)
}

func parentDir(_ p: String) -> String { (p as NSString).deletingLastPathComponent }

func isDir(_ p: String) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue
}

func makeDirs(_ p: String) { try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true) }

/// open(path, "w").write(text): a plain write (no temp file, the default mode), as the Python tools did for scratch files.
func writeFile(_ path: String, _ text: String) {
    if !FileManager.default.createFile(atPath: path, contents: Data(text.utf8)) { fail("could not write \(path)") }
}

/// tempfile.mkdtemp(prefix=...): a new private folder under TMPDIR.
func makeTempDir(_ prefix: String) -> String {
    var t = Array((NSTemporaryDirectory() as NSString).appendingPathComponent(prefix + "XXXXXX").utf8CString)
    guard mkdtemp(&t) != nil else { fail("could not make a temp folder") }
    return String(cString: t)
}

func errLine(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func fail(_ s: String, _ code: Int32 = 1) -> Never {
    errLine("jebgates: " + s)
    exit(code)
}

// ---- clock and local time ----

/// time.time() and time.sleep(): real, unless JEB_TEST_NOW pins the clock; a pinned clock only moves when something sleeps.
enum GateClock {
    private static var pinned: Double? = environ("JEB_TEST_NOW").flatMap(Double.init)
    static var now: Double { pinned ?? Date().timeIntervalSince1970 }
    static func sleep(_ seconds: Double) {
        if let t = pinned { pinned = t + seconds } else if seconds > 0 { usleep(useconds_t(seconds * 1_000_000)) }
    }
}

/// time.mktime((y, mo, d, h, mi, 0, 0, 0, -1)) * 1000: a local wall time (TZ) as epoch milliseconds.
func ms(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Int {
    var t = tm()
    t.tm_year = Int32(y - 1900); t.tm_mon = Int32(mo - 1); t.tm_mday = Int32(d); t.tm_hour = Int32(h); t.tm_min = Int32(mi)
    t.tm_isdst = -1
    return Int(mktime(&t)) * 1000
}

/// time.localtime(secs).
func localTime(_ secs: Double) -> tm {
    var s = time_t(secs.rounded(.down))
    var t = tm()
    localtime_r(&s, &t)
    return t
}

/// time.strftime("%Y-%m-%d", time.localtime(secs)).
func localDay(_ secs: Double) -> String {
    let t = localTime(secs)
    return String(format: "%04d-%02d-%02d", Int(t.tm_year) + 1900, Int(t.tm_mon) + 1, Int(t.tm_mday))
}

// ---- processes and patterns ----

/// subprocess.run(argv, capture_output=True, env=env).stdout: the program's stdout (stderr is dropped); a program that
/// cannot start prints nothing.
func capture(_ argv: [String], env: [String: String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: argv[0])
    p.arguments = Array(argv.dropFirst())
    p.environment = env
    let o = Pipe()
    p.standardOutput = o
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let d = o.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: d, as: UTF8.self)
}

/// os.environ with some variables set on top.
func environWith(_ extra: [String: String]) -> [String: String] {
    var e = ProcessInfo.processInfo.environment
    for (k, v) in extra { e[k] = v }
    return e
}

/// re.search: the groups of the first match (group 0 first; an unmatched group is ""), or nil.
func search(_ pattern: String, _ s: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
}

// ---- Python's text shapes ----

/// repr(str): single quotes, or double quotes when the text has a ' and no ".
func pyRepr(_ s: String) -> String {
    let q: Character = s.contains("'") && !s.contains("\"") ? "\"" : "'"
    var out = String(q)
    for c in s {
        switch c {
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case q: out += "\\" + String(c)
        default: out.append(c)
        }
    }
    return out + String(q)
}

/// repr of a list of strings: ['a', 'b'].
func pyRepr(_ a: [String]) -> String { "[" + a.map { pyRepr($0) }.joined(separator: ", ") + "]" }

/// repr of what json.load gave (a dict keeps its order): {'d': '2026-10-21', 'step': 6}, None, True.
func pyRepr(_ v: Json?) -> String {
    guard let v = v else { return "None" }
    switch v {
    case .null: return "None"
    case let .bool(b): return b ? "True" : "False"
    case let .int(i): return String(i)
    case let .double(d): return Json.pyFloat(d)
    case let .string(s): return pyRepr(s)
    case let .array(a): return "[" + a.map { pyRepr($0) }.joined(separator: ", ") + "]"
    case let .object(kv): return "{" + kv.map { pyRepr($0.0) + ": " + pyRepr($0.1) }.joined(separator: ", ") + "}"
    }
}

/// f"{x:.Nf}".
func fixed(_ x: Double, _ places: Int) -> String { String(format: "%.\(places)f", x) }

/// f"{s:N}": left-justified in a field of n.
func padded(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }

/// round(): half to even, as Python 3 rounds.
func pyRound(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }

// ---- Json literals (the fixtures table reads like the Python dicts it was ported from) ----

extension Json: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral,
                ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(integerLiteral v: Int) { self = .int(v) }
    init(stringLiteral v: String) { self = .string(v) }
    init(booleanLiteral v: Bool) { self = .bool(v) }
    init(nilLiteral: ()) { self = .null }
    init(arrayLiteral v: Json...) { self = .array(v) }
    init(dictionaryLiteral v: (String, Json)...) { self = .object(v) }

    /// dict.update(other): replaces in place, appends what is new.
    func updated(_ other: Json) -> Json {
        var out = self
        for (k, v) in other.object ?? [] { out.set(k, v) }
        return out
    }
}

func strings(_ a: [String]) -> Json { .array(a.map { .string($0) }) }
