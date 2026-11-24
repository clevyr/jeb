// Plugin: how Jeb's mod is registered with Claude Code, for install, uninstall and doctor.
// The mod goes through Claude Code's own plugin system (`claude plugin ...`): a local marketplace named "jeb" (the
// bundle's .claude-plugin/marketplace.json) and the plugin jeb@jeb. The only write to ~/.claude/settings.json is removing
// Jeb's own legacy CLAUDE_CODE_PLUGIN_DIRS entry (backup first); nothing here ever adds one (that was the git clone's
// dev mode, which is gone).
// CLAUDE_CODE_PLUGIN_DIRS (the settings "env" block) is a list of plugin folders split on ":"; entries are compared
// after expanduser/normpath.
import Foundation

let pluginDirsKey = "CLAUDE_CODE_PLUGIN_DIRS"
let pluginMarket = "jeb"
let pluginId = "jeb@jeb"
let oldPluginId = "jeb@inline"      // the id the mod had while it loaded through CLAUDE_CODE_PLUGIN_DIRS

/// A settings file that cannot be edited safely; the text is what the Python exited with.
struct SettingsError: Error, CustomStringConvertible {
    let description: String
}

func settingsPath() -> String { envVar("JEB_SETTINGS").flatMap { $0.isEmpty ? nil : $0 } ?? expandUser("~/.claude/settings.json") }
func backupDir() -> String { envVar("JEB_BACKUPS").flatMap { $0.isEmpty ? nil : $0 } ?? expandUser("~/.claude/backups/jeb") }

// ---- paths ----

/// os.path.normpath(os.path.abspath(os.path.expanduser(p.strip()))): absolute, without "." and ".." parts, links unresolved.
func normPath(_ p: String) -> String {
    var s = expandUser(p.trimmingCharacters(in: .whitespacesAndNewlines))
    if !s.hasPrefix("/") { s = FileManager.default.currentDirectoryPath + "/" + s }
    var parts: [Substring] = []
    for c in s.split(separator: "/") where c != "." {
        if c == ".." { _ = parts.popLast() } else { parts.append(c) }
    }
    return "/" + parts.joined(separator: "/")
}

/// Same folder: equal after expanduser/normpath, or the same inode (macOS volumes ignore case).
func sameDir(_ a: String, _ b: String) -> Bool {
    let x = normPath(a), y = normPath(b)
    if x == y { return true }
    var sa = stat(), sb = stat()
    return stat(x, &sa) == 0 && stat(y, &sb) == 0 && sa.st_dev == sb.st_dev && sa.st_ino == sb.st_ino
}

/// The non-blank ":"-separated entries of a CLAUDE_CODE_PLUGIN_DIRS value, as written.
func dirEntries(_ value: String?) -> [String] {
    (value ?? "").components(separatedBy: ":").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// True for a path under dir once both are resolved (dir itself excluded).
func isUnder(_ path: String, _ dir: String) -> Bool { pyRealpath(path).hasPrefix(pyRealpath(dir) + "/") }

// ---- settings.json ----

/// The settings object; an empty one when the file is missing. Throws for a file that is not a JSON object.
func loadSettings(_ path: String) throws -> Json {
    guard FileManager.default.fileExists(atPath: path) else { return .object([]) }
    let data: Json
    do { data = try Json.parse(FileManager.default.contents(atPath: path) ?? Data()) } catch {
        throw SettingsError(description: "\(path) is not valid JSON (\(error)); fix it first, nothing changed")
    }
    guard data.object != nil else { throw SettingsError(description: "\(path) is not a JSON object; nothing changed") }
    return data
}

/// The CLAUDE_CODE_PLUGIN_DIRS value of the settings, nil when there is none.
func currentDirs(_ data: Json) throws -> String? {
    guard let env = data["env"], !env.isNull else { return nil }
    guard env.object != nil else { throw SettingsError(description: "settings \"env\" is not an object; nothing changed") }
    guard let v = env[pluginDirsKey], !v.isNull else { return nil }
    guard let s = v.string else { throw SettingsError(description: "\(pluginDirsKey) is not a string in settings; nothing changed") }
    return s
}

/// What removing mod from value does: ("absent", value) when it is not listed, ("remove", the rest) when other entries
/// stay, ("drop", nil) when the key goes.
func planRemoval(_ value: String?, _ mod: String) -> (action: String, new: String?) {
    let parts = dirEntries(value)
    let mine = parts.filter { sameDir($0, mod) }
    if mine.isEmpty { return ("absent", value) }
    let rest = parts.filter { !mine.contains($0) }
    return rest.isEmpty ? ("drop", nil) : ("remove", rest.joined(separator: ":"))
}

/// A free name in the backups folder (created 0700): <stem>.<ext>, then <stem>-2.<ext> and so on, so two edits in one
/// second keep both backups.
func backupName(_ stem: String, _ ext: String) -> String {
    makePrivateDir(backupDir())
    let base = backupDir() + "/" + stem
    var dest = base + "." + ext, n = 1
    while FileManager.default.fileExists(atPath: dest) {
        n += 1
        dest = "\(base)-\(n).\(ext)"
    }
    return dest
}

/// shutil.copy2: the file's bytes (a link is followed) with its mode and times.
func copyFile2(_ src: String, _ dest: String) throws {
    try FileManager.default.copyItem(atPath: pyRealpath(src), toPath: dest)
}

/// Copies the settings file to the backups folder as settings.<stamp>.json; the copy's path.
func backupSettings(_ path: String) throws -> String {
    let dest = backupName("settings." + Clock.strftime("%Y%m%d-%H%M%S"), "json")
    try copyFile2(path, dest)
    return dest
}

/// json.dump(indent=2, ensure_ascii=False): the settings keep their own characters, only control characters stay escaped.
func settingsText(_ data: Json) -> String {
    let src = Array(data.dumps(indent: 2).utf16)
    var out: [UInt16] = []
    var i = 0
    func hex(_ at: Int) -> UInt16? {
        guard at + 6 <= src.count, src[at] == 0x5c, src[at + 1] == 0x75 else { return nil }
        return UInt16(String(decoding: src[at + 2..<at + 6], as: UTF16.self), radix: 16)
    }
    while i < src.count {
        guard src[i] == 0x5c, i + 1 < src.count else { out.append(src[i]); i += 1; continue }
        if let u = hex(i), u >= 0x7f {
            if (0xd800..<0xdc00).contains(u), let lo = hex(i + 6), (0xdc00..<0xe000).contains(lo) {
                out += [u, lo]
                i += 12
                continue
            }
            if !(0xd800..<0xe000).contains(u) {
                out.append(u)
                i += 6
                continue
            }
        }
        out += [src[i], src[i + 1]]     // any other escape (a lone surrogate included) stays as written
        i += 2
    }
    return String(decoding: out, as: UTF16.self) + "\n"
}

/// Removes mod from the settings' CLAUDE_CODE_PLUGIN_DIRS: the action ("absent", "remove" or "drop"). Backs the file up
/// before it writes; every other key keeps its place. A symlinked settings.json stays a symlink (the target is
/// rewritten), through a fresh 0600 temp file that takes the original's mode before any content is written.
@discardableResult
func removeDirsEntry(_ mod: String, dry: Bool, say: (String) -> Void) throws -> String {
    let path = settingsPath()
    var data = try loadSettings(path)
    let (action, new) = planRemoval(try currentDirs(data), mod)
    say("settings \(path): \(pluginDirsKey) \(action)" + ((new ?? "").isEmpty ? "" : " -> \(new!)"))
    if action == "absent" { return action }
    if dry {
        say("  (dry run: not written)")
        return action
    }
    say("  backup: " + (try backupSettings(path)))
    var env = data["env"] ?? .object([])
    if let n = new { env.set(pluginDirsKey, .string(n)) } else { env.remove(pluginDirsKey) }
    if env.object?.isEmpty ?? true { data.remove("env") } else { data.set("env", env) }
    let real = pyRealpath(path), tmp = real + ".jeb-tmp"
    unlink(tmp)                         // a stale (or planted) temp file never gets written through
    var st = stat()
    let mode: mode_t = stat(real, &st) == 0 ? st.st_mode & 0o7777 : 0o600
    let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard fd >= 0 else { throw posixError("open", tmp) }
    fchmod(fd, mode)
    let bytes = Array(settingsText(data).utf8)
    let wrote = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    let err = errno
    close(fd)
    guard wrote == bytes.count else { unlink(tmp); throw posixError("write", tmp, err) }
    guard rename(tmp, real) == 0 else { let e = errno; unlink(tmp); throw posixError("rename", real, e) }
    return action
}

/// removeDirsEntry for the commands: a settings file that cannot be edited ends the run with its reason.
@discardableResult
func removeEntry(_ mod: String, dry: Bool, say: (String) -> Void) -> String {
    do { return try removeDirsEntry(mod, dry: dry, say: say) } catch { die("\(error)") }
}

func removeEntries(_ entries: [String], dry: Bool, say: (String) -> Void) {
    for e in entries { removeEntry(e, dry: dry, say: say) }
}

/// The CLAUDE_CODE_PLUGIN_DIRS entries that are Jeb's own release install (under ~/.jeb: current, versions, repo).
func legacyEntries() -> [String] {
    guard let v = try? currentDirs(loadSettings(settingsPath())) else { return [] }
    return dirEntries(v).filter { isUnder(normPath($0), jebDir()) }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The entries actually listed in CLAUDE_CODE_PLUGIN_DIRS now, each once.
func presentEntries(_ entries: [String]) -> [String] {
    guard let v = try? currentDirs(loadSettings(settingsPath())) else { return [] }
    let parts = dirEntries(v)
    var out: [String] = []
    for e in entries where !out.contains(e) && parts.contains(where: { sameDir(e, $0) }) { out.append(e) }
    return out
}

/// The options set while the mod was jeb@inline (settings pluginConfigs, read only), as single-line strings.
func inlineOptions() -> [(String, String)] {
    guard let data = try? loadSettings(settingsPath()), let opts = data["pluginConfigs"]?[oldPluginId]?["options"]?.object else { return [] }
    var out: [(String, String)] = []
    for (k, v) in opts {
        let s: String
        switch v {
        case .bool(let b): s = b ? "true" : "false"
        case .string(let t): s = t
        case .int, .double: s = pyStr(v)
        default: continue
        }
        if !s.contains("\n") { out.append((k, s)) }
    }
    return out
}

// ---- Claude Code's plugin store ----

func storeDir() -> String { envVar("JEB_STORE_DIR").flatMap { $0.isEmpty ? nil : $0 } ?? expandUser("~/.claude/plugins/store") }

/// Claude Code's store file for a plugin id: the id with @ -> _, then the first 12 hex of its sha256.
func storeName(_ pid: String) -> String {
    pid.replacingOccurrences(of: "@", with: "_") + "-" + sha256Hex(Data(pid.utf8)).prefix(12) + ".json"
}

/// jeb@jeb's file; the jeb@inline one while that is all there is; else the new one (the mod creates it).
func storePath() -> String {
    let new = storeDir() + "/" + storeName(pluginId), old = storeDir() + "/" + storeName(oldPluginId)
    let fm = FileManager.default
    return !fm.fileExists(atPath: new) && fm.fileExists(atPath: old) ? old : new
}

/// Jeb's store files (jeb_jeb-*.json and jeb_inline-*.json), sorted.
func storeFiles() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: storeDir())) ?? [])
        .filter { ($0.hasPrefix("jeb_jeb-") || $0.hasPrefix("jeb_inline-")) && $0.hasSuffix(".json") }
        .map { storeDir() + "/" + $0 }.sorted()
}

/// Copies a store file to the backups folder as <name>.<stamp>.json; the copy's path.
@discardableResult
func backupStoreFile(_ f: String) throws -> String {
    makePrivateDir(backupDir())
    let dest = backupDir() + "/" + String((f as NSString).lastPathComponent.dropLast(5)) + "." + Clock.strftime("%Y%m%d-%H%M%S") + ".json"
    try? FileManager.default.removeItem(atPath: dest)
    try copyFile2(f, dest)
    return dest
}

// ---- the claude CLI ----

/// (exit status, output) of `claude plugin <args>`; (nil, reason) when claude is missing or does not answer in time.
/// The child never sees CLAUDE_CODE_PLUGIN_DIRS; input is fed to its stdin, which is /dev/null otherwise.
func claudePlugin(_ args: [String], timeout: Double = 120, input: String? = nil) -> (rc: Int32?, out: String) {
    guard let cl = findClaude() else { return (nil, "claude was not found") }
    return runPluginProcess(cl, args: ["plugin"] + args, timeout: timeout, input: input,
                            timedOut: "claude plugin \(args.joined(separator: " ")) timed out after \(Int(timeout)) seconds")
}

/// Runs exe with args under the claude CLI's rules (no CLAUDE_CODE_PLUGIN_DIRS, input on stdin when given); (status, output),
/// or (nil, timedOut) when it has not exited within timeout seconds. The exit is signalled by terminationHandler, set before
/// run(): waitUntilExit on a pool thread (no run loop) can miss the exit and the caller then hung with the child long gone.
func runPluginProcess(_ exe: String, args: [String], timeout: Double, input: String?, timedOut: String) -> (rc: Int32?, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.environment = ProcessInfo.processInfo.environment.filter { $0.key != pluginDirsKey }
    let o = Pipe(), e = Pipe(), i = Pipe()
    p.standardOutput = o
    p.standardError = e
    p.standardInput = input == nil ? FileHandle.nullDevice : i
    let exited = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in exited.signal() }
    do { try p.run() } catch { return (nil, error.localizedDescription) }
    var od = Data(), ed = Data()
    let g = DispatchGroup()
    g.enter(); DispatchQueue.global().async { od = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
    g.enter(); DispatchQueue.global().async { ed = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
    if let text = input {
        signal(SIGPIPE, SIG_IGN)
        try? i.fileHandleForWriting.write(contentsOf: Data(text.utf8))
        try? i.fileHandleForWriting.close()
    }
    let deadline = DispatchTime.now() + timeout
    if exited.wait(timeout: deadline) == .timedOut || g.wait(timeout: deadline) == .timedOut {
        kill(p.processIdentifier, SIGKILL)
        _ = exited.wait(timeout: .now() + 5)
        return (nil, timedOut)
    }
    return (p.terminationStatus, (String(decoding: od, as: UTF8.self) + String(decoding: ed, as: UTF8.self)).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// A `claude plugin ... --json` listing: its objects, or nil when the command failed or did not print a list.
func claudeList(_ args: [String]) -> [Json]? {
    let (rc, out) = claudePlugin(args + ["--json"])
    guard rc == 0, let list = (try? Json.parse(out))?.array else { return nil }
    return list.filter { $0.object != nil }
}

/// (claude's path, jeb@jeb's entry from `plugin list`, the "jeb" marketplace entry); the entries are nil when absent
/// or unreadable.
func pluginInfo() -> (claude: String?, plugin: Json?, market: Json?) {
    guard let cl = findClaude() else { return (nil, nil, nil) }
    let plugins = claudeList(["list"]), markets = claudeList(["marketplace", "list"])
    return (cl, plugins?.first { $0["id"]?.string == pluginId }, markets?.first { $0["name"]?.string == pluginMarket })
}

/// The last 200 characters of a command's output, for a one-line failure message.
func tail200(_ s: String) -> String { String(s.suffix(200)) }

/// The folder a marketplace entry points at ("path", else "installLocation"), nil when it names none.
func marketPath(_ mkt: Json) -> String? {
    for k in ["path", "installLocation"] {
        if let s = mkt[k]?.string, !s.isEmpty { return s }
    }
    return nil
}

/// Registers the mod with Claude Code: the "jeb" marketplace at source (a folder holding .claude-plugin/marketplace.json),
/// then jeb@jeb installed (options carried over from jeb@inline) or updated. Only once that worked are Jeb's legacy
/// CLAUDE_CODE_PLUGIN_DIRS entries (and extra, e.g. an old clone's) removed. Returns ok | no-claude | conflict | failed
/// (the legacy entry stays: Jeb keeps loading).
func registerPlugin(_ source: String, dry: Bool, say: (String) -> Void, extra: [String] = []) -> String {
    let (cl, plug, mkt) = pluginInfo()
    if cl == nil {
        say("claude was not found; the plugin is not registered (Jeb keeps loading the old way if it was)")
        return "no-claude"
    }
    if let m = mkt, !sameDir(marketPath(m) ?? "/nonexistent", source) {
        say("marketplace \"\(pluginMarket)\" already points at \(pyStr(m["path"])), not \(source); left alone")
        return "conflict"
    }
    if dry {
        say("would register \(pluginId) from \(source)" + (mkt == nil ? " (marketplace added)" : ""))
        return "ok"
    }
    if mkt == nil {
        let (rc, out) = claudePlugin(["marketplace", "add", source])
        if rc != 0 {
            say("claude plugin marketplace add failed: \(tail200(out))")
            return "failed"
        }
    }
    let old = storeDir() + "/" + storeName(oldPluginId), new = storeDir() + "/" + storeName(pluginId)
    if isRegularFile(old) && !FileManager.default.fileExists(atPath: new) {
        try? FileManager.default.createDirectory(atPath: storeDir(), withIntermediateDirectories: true)
        do { try copyFile2(old, new) } catch { die("cannot copy \(old) to \(new): \(error.localizedDescription)") }
        chmod(new, 0o600)               // the farm and live records move with the plugin id
        say("store: copied \((old as NSString).lastPathComponent) to \((new as NSString).lastPathComponent)")
    }
    let opts = inlineOptions()
    var rc: Int32?, out: String
    if plug != nil {
        (rc, out) = claudePlugin(["marketplace", "update", pluginMarket])
        if rc != 0 {
            say("claude plugin marketplace update failed: \(tail200(out))")
            return "failed"
        }
        (rc, out) = claudePlugin(["update", pluginId])
    } else {
        (rc, out) = claudePlugin(["install", pluginId, "--scope", "user"] + opts.flatMap { ["--config", "\($0.0)=\($0.1)"] })
    }
    if rc != 0 {
        say("claude plugin \(plug != nil ? "update" : "install") failed: \(tail200(out))")
        return "failed"
    }
    let legacy = presentEntries(legacyEntries() + extra.filter { !$0.isEmpty })
    if !legacy.isEmpty {
        removeEntries(legacy, dry: dry, say: say)
        say("moved Jeb off CLAUDE_CODE_PLUGIN_DIRS (settings backed up)")
    }
    if !opts.isEmpty && plug == nil && !legacy.isEmpty {
        // While the legacy entry was still listed, the same plugin loaded twice and --config was not applied: set the options now.
        (rc, out) = claudePlugin(["configure", pluginId, "--values-stdin"], input: Json.object(opts.map { ($0.0, .string($0.1)) }).dumps())
        say(rc == 0 ? "options carried over from jeb@inline" : "could not carry the options over: \(tail200(out))")
    }
    return "ok"
}

/// After an update: refresh the marketplace and jeb@jeb. True when both commands ran clean (or Jeb is not registered).
func syncPlugin(dry: Bool, say: (String) -> Void) -> Bool {
    let (cl, plug, _) = pluginInfo()
    if cl == nil || plug == nil { return true }
    if dry {
        say("would run: claude plugin marketplace update \(pluginMarket); claude plugin update \(pluginId)")
        return true
    }
    let a = claudePlugin(["marketplace", "update", pluginMarket])
    if a.rc != 0 { say("claude plugin marketplace update failed: \(tail200(a.out))") }
    let b = claudePlugin(["update", pluginId])
    if b.rc != 0 { say("claude plugin update failed: \(tail200(b.out))") }
    return a.rc == 0 && b.rc == 0
}

/// Uninstall jeb@jeb (its data kept unless purgeFarm) and remove the "jeb" marketplace when it is Jeb's own, then drop
/// Jeb's legacy CLAUDE_CODE_PLUGIN_DIRS entries. Jeb's store files are backed up first and put back if Claude Code
/// deleted one (unless purging).
func unregisterPlugin(purgeFarm: Bool, dry: Bool, say: (String) -> Void, source: String? = nil) {
    let files = storeFiles()
    var saved: [(String, Data)] = []
    for f in files {
        if let d = FileManager.default.contents(atPath: f) { saved.append((f, d)) }
    }
    if !dry {
        for f in files {
            do { try backupStoreFile(f) } catch { die("cannot back up \(f): \(error.localizedDescription)") }
        }
    }
    let (cl, plug, mkt) = pluginInfo()
    if cl == nil {
        say("claude was not found; the plugin was not uninstalled from Claude Code")
    } else {
        if plug != nil {
            say(dry ? "would uninstall " + pluginId : "uninstalling " + pluginId)
            if !dry {
                let (rc, out) = claudePlugin(["uninstall", pluginId] + (purgeFarm ? [] : ["--keep-data"]))
                if rc != 0 { say("claude plugin uninstall failed: \(tail200(out))") }
            }
        }
        let mp = mkt?["path"]?.string ?? ""
        if mkt != nil && (isUnder(mp, jebDir()) || (source.map { sameDir(mp, $0) } ?? false)) {
            say((dry ? "would remove" : "removing") + " marketplace \"\(pluginMarket)\"")
            if !dry {
                let (rc, out) = claudePlugin(["marketplace", "remove", pluginMarket])
                if rc != 0 { say("claude plugin marketplace remove failed: \(tail200(out))") }
            }
        } else if mkt != nil {
            say("marketplace \"\(pluginMarket)\" points at \(mp), not Jeb's; left alone")
        }
    }
    if !dry && !purgeFarm {
        for (f, data) in saved where !FileManager.default.fileExists(atPath: f) {
            let fd = open(f, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { die("cannot restore \(f): \(String(cString: strerror(errno)))") }
            _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
            say("restored " + (f as NSString).lastPathComponent)
        }
    }
    removeEntries(legacyEntries(), dry: dry, say: say)
}
