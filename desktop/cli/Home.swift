// Home: where Jeb's desktop state lives, and the one-time move from the old folder.
// The state folder is ~/Library/Application Support/Jeb. Older installs keep it at ~/.claude/jeb-desktop until migrate()
// moves it (the old path then stays behind as a symlink, so the running app, its rollback versions and the LaunchAgents'
// log paths keep working). Also the install's shared lookups: the standard places ~/.jeb/bin (JEB_TOOLS_DIR),
// ~/.jeb/versions/<tag> (one unpacked release bundle) and ~/.jeb/current (a symlink to the live one; LaunchAgents and
// settings only name it), read_bundle, host_arch, macho_archs (a Mach-O header reader) and find_claude.
// Paths are computed at call time so tests can point $HOME elsewhere.
import Foundation

let labelPrefix = "com.jeb.desktop"

func jebDir() -> String { expandUser("~/.jeb") }
func toolsDir() -> String { envVar("JEB_TOOLS_DIR") ?? jebDir() + "/bin" }
func currentDir() -> String { jebDir() + "/current" }
func versionsDir() -> String { jebDir() + "/versions" }
func newPath() -> String { expandUser("~/Library/Application Support/Jeb") }
func oldPath() -> String { expandUser("~/.claude/jeb-desktop") }

/// root/bundle.json as an object (a release bundle), or nil (a git clone, or no readable JSON object).
func readBundle(_ root: String) -> Json? {
    guard let d = Json.load(root + "/bundle.json"), d.object != nil else { return nil }
    return d
}

/// arm64 or x86_64 by the hardware (a Rosetta shell reports x86_64 for itself).
func hostArch() -> String {
    let r = run(["/usr/sbin/sysctl", "-n", "hw.optional.arm64"])
    return r.status == 0 && r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "1" ? "arm64" : "x86_64"
}

let cpuTypes: [UInt32: String] = [0x0100000c: "arm64", 0x01000007: "x86_64"]

/// The architectures of a Mach-O file as a set of arm64 / x86_64 (other CPUs are ignored); empty when unreadable.
/// Fat files (0xcafebabe, 0xcafebabf) are big-endian, thin 64-bit files (0xfeedfacf) little-endian.
func machoArchs(_ path: String) -> Set<String> {
    guard let f = FileHandle(forReadingAtPath: path) else { return [] }
    defer { f.closeFile() }
    let head = f.readData(ofLength: 8)
    guard head.count == 8 else { return [] }
    func be(_ d: Data, _ i: Int) -> UInt32 { d.subdata(in: i..<i + 4).reduce(0) { $0 << 8 | UInt32($1) } }
    func le(_ d: Data, _ i: Int) -> UInt32 { d.subdata(in: i..<i + 4).reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    let magic = be(head, 0)
    if magic == 0xcafebabe || magic == 0xcafebabf {
        let n = Int(be(head, 4)), size = magic == 0xcafebabe ? 20 : 32
        guard n > 0 && n <= 20 else { return [] }
        let body = f.readData(ofLength: n * size)
        guard body.count == n * size else { return [] }
        return Set((0..<n).compactMap { cpuTypes[be(body, $0 * size)] })
    }
    guard le(head, 0) == 0xfeedfacf, let a = cpuTypes[le(head, 4)] else { return [] }
    return [a]
}

func isExecutableFile(_ p: String) -> Bool {
    var st = stat()
    return stat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG && access(p, X_OK) == 0
}

/// Claude Code's CLI: on PATH, or where its installers put it.
func findClaude() -> String? {
    for p in [expandUser("~/.local/bin/claude"), expandUser("~/.claude/local/claude"), "/opt/homebrew/bin/claude", "/usr/local/bin/claude"] where isExecutableFile(p) {
        return p
    }
    return which("claude")
}

/// shutil.which: the first executable named name on $PATH.
func which(_ name: String) -> String? {
    for d in (envVar("PATH") ?? "").split(separator: ":", omittingEmptySubsequences: false) {
        let p = (d.isEmpty ? "." : String(d)) + "/" + name
        if isExecutableFile(p) { return p }
    }
    return nil
}

// ---- the state folder ----

/// A directory that is not a symlink (os.path.isdir and not islink).
func isRealDir(_ p: String) -> Bool {
    var st = stat()
    return lstat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
}

/// os.path.lexists: the path exists, a dangling symlink included.
func lexists(_ p: String) -> Bool {
    var st = stat()
    return lstat(p, &st) == 0
}

/// JEB_HOME; else the new folder if it exists; else the old one if it is a real folder; else the new one.
func resolveHome() -> String {
    if let h = envVar("JEB_HOME"), !h.isEmpty { return h }
    let new = newPath(), old = oldPath()
    if FileManager.default.fileExists(atPath: new) { return new }
    return isRealDir(old) ? old : new
}

/// The old prefix replaced by the new one in every string of a plist value (strings, arrays and dictionaries).
func swapPrefix(_ v: Any, _ old: String, _ new: String) -> Any {
    if let s = v as? String { return s == old || s.hasPrefix(old + "/") ? new + s.dropFirst(old.count) : s }
    if let a = v as? [Any] { return a.map { swapPrefix($0, old, new) } }
    if let d = v as? [String: Any] { return d.mapValues { swapPrefix($0, old, new) } }
    return v
}

/// Rewrites one of our LaunchAgent plists (Label under com.jeb.desktop) from the old folder to the new; false when it
/// is not ours, unchanged or unreadable.
@discardableResult
func rewritePlist(_ path: String, _ old: String, _ new: String) -> Bool {
    guard let data = FileManager.default.contents(atPath: path),
          let doc = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          (doc["Label"] as? String ?? "").hasPrefix(labelPrefix) else { return false }
    guard let out = swapPrefix(doc, old, new) as? [String: Any], !NSDictionary(dictionary: out).isEqual(to: doc) else { return false }
    guard let bytes = try? PropertyListSerialization.data(fromPropertyList: out, format: .xml, options: 0) else { return false }
    let tmp = path + ".tmp"
    guard FileManager.default.createFile(atPath: tmp, contents: bytes, attributes: [.posixPermissions: 0o644]), rename(tmp, path) == 0 else {
        unlink(tmp)
        return false
    }
    return true
}

func rewritePlists(_ old: String, _ new: String) {
    for d in [new + "/launchd", agentsDir()] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: d) else { continue }
        for n in names.sorted() where n.hasPrefix(labelPrefix) && n.hasSuffix(".plist") {
            rewritePlist(d + "/" + n, old, new)
        }
    }
}

/// Symlink old -> new; if something recreated old as a real folder meanwhile, fold it into new first.
@discardableResult
func linkBack(_ old: String, _ new: String, _ log: (String) -> Void) -> Bool {
    let fm = FileManager.default
    for _ in 0..<3 {
        if symlink(new, old) == 0 { return true }
        guard errno == EEXIST, isRealDir(old) else { break }
        let aside = new + "/migrate-leftovers"
        for n in (try? fm.contentsOfDirectory(atPath: old)) ?? [] {
            var dest = new + "/" + n
            if lexists(dest) {
                try? fm.createDirectory(atPath: aside, withIntermediateDirectories: true)
                dest = aside + "/" + n
                if lexists(dest) { dest += ".\(Clock.pid)" }
            }
            rename(old + "/" + n, dest)
        }
        rmdir(old)
    }
    log("could not link \(old) to \(new); the new folder is used regardless")
    return false
}

/// Move the old state folder to the new place once. Returns "n/a", "busy", "would move", "moved" or "failed".
func migrate(log: (String) -> Void, dry: Bool = false) -> String {
    if let h = envVar("JEB_HOME"), !h.isEmpty { return "n/a" }
    let new = newPath(), old = oldPath()
    if !isRealDir(old) || lexists(new) { return "n/a" }
    if dry {
        log("would move the state folder \(old) to \(new)")
        return "would move"
    }
    var fds: [Int32] = []
    defer { fds.forEach { close($0) } }
    for n in ["updater.lock", "release.lock"] {
        let fd = open(old + "/" + n, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd >= 0 { fds.append(fd) }
        if fd < 0 || flock(fd, LOCK_EX | LOCK_NB) != 0 {
            log("state folder move postponed: \(n) is held; the next run retries")
            return "busy"
        }
    }
    try? FileManager.default.createDirectory(atPath: (new as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    guard rename(old, new) == 0 else {
        log("could not move \(old) to \(new): \(String(cString: strerror(errno)))")
        return "failed"
    }
    linkBack(old, new, log)
    rewritePlists(old, new)
    log("moved the state folder to \(new); \(old) now links there")
    return "moved"
}
