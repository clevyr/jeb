// Jeb's store, read for three things only: the `farm` key, the `live:*` keys
// (one per running session, see the mod's hooks/live.ts) and the `areas` key (the
// projects' areas, see Area.swift). Every other key is
// skipped as bytes by a small scanner and never decoded, so nothing else in the
// file (the sessions' heartbeats among them) is ever parsed, kept or passed on.
//
// The file is watched with a kqueue vnode source (DispatchSource) that survives
// the mod's atomic replace: the store is written to a temporary file and renamed
// over the old one, so the watched inode is deleted or renamed away. On that, the
// source is re-opened on the new file. The folder is watched too (a rename into it
// is a write to the folder), so a replace is seen even if the file event is
// missed. Events are debounced by DEBOUNCE_MS, then the file is read once. A slow
// mtime poll (every 2 s, in main.swift) stays as a fallback.

import Foundation

/// The store file: JEB_STORE_PATH; else the plugin's own (jeb@jeb) when it exists, else the older jeb@inline one while that is all
/// there is, else jeb@jeb's (the mod creates it on its first run under Claude Code's plugin system).
func resolveStorePath() -> String {
    if let p = env["JEB_STORE_PATH"] { return p }
    let dir = env["JEB_STORE_DIR"] ?? NSHomeDirectory() + "/.claude/plugins/store"
    let new = dir + "/jeb_jeb-8dcd56be8054.json", old = dir + "/jeb_inline-129385bc4c17.json"
    let fm = FileManager.default
    return !fm.fileExists(atPath: new) && fm.fileExists(atPath: old) ? old : new
}

var storePath = resolveStorePath()

/// While on the older file, look again (one stat): the new one appearing switches the app over without a restart.
func refreshStorePath() {
    guard env["JEB_STORE_PATH"] == nil, storePath.hasSuffix("/jeb_inline-129385bc4c17.json") else { return }
    storePath = resolveStorePath()
}

enum StoreLimits {
    static let fileBytes = 8 << 20     // a bigger file is not read at all
    static let farmBytes = 2 << 20
    static let liveBytes = 32 << 10    // one live record (a drop happening's art included)
    static let liveRecords = 16        // live records read; the mod keeps at most 8
    static let areasBytes = 24 * 1536  // the areas object: 24 areas of about 1.5 KB at most
}

/// The parts of the store the desktop may read, as raw JSON bytes per key.
struct StoreSlices: Equatable {
    var farm: Data?
    var live: [String: Data] = [:] // token -> record bytes
    var areas: Data?
}

/// Splits the top level of a JSON object into keys and value byte ranges, and
/// keeps only `farm`, `live:<token>` and `areas` values. Other values are stepped over
/// (strings and brackets matched, nothing decoded). Returns nil for anything that
/// is not a well-formed top-level object.
func storeSlices(_ data: Data) -> StoreSlices? {
    guard data.count <= StoreLimits.fileBytes else { return nil }
    return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> StoreSlices? in
        let b = raw.bindMemory(to: UInt8.self)
        let n = b.count
        var i = 0
        func ws() { while i < n, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 } }
        // A string starting at i (on its quote): returns its raw content range, i past the closing quote.
        func string() -> Range<Int>? {
            guard i < n, b[i] == 0x22 else { return nil }
            i += 1
            let start = i
            while i < n {
                if b[i] == 0x5C { i += 2; continue }
                if b[i] == 0x22 { let r = start..<i; i += 1; return r }
                i += 1
            }
            return nil
        }
        // Steps over one value of any kind; nesting is capped.
        func skipValue() -> Bool {
            ws()
            guard i < n else { return false }
            switch b[i] {
            case 0x22: return string() != nil
            case 0x7B, 0x5B:
                var depth = 0
                while i < n {
                    let c = b[i]
                    if c == 0x22 { guard string() != nil else { return false }; continue }
                    if c == 0x7B || c == 0x5B { depth += 1; if depth > 64 { return false } }
                    if c == 0x7D || c == 0x5D { depth -= 1; if depth == 0 { i += 1; return true } }
                    i += 1
                }
                return false
            default:
                while i < n, b[i] != 0x2C, b[i] != 0x7D, b[i] != 0x5D, b[i] != 0x20, b[i] != 0x0A, b[i] != 0x0D, b[i] != 0x09 { i += 1 }
                return true
            }
        }
        ws()
        guard i < n, b[i] == 0x7B else { return nil }
        i += 1
        var out = StoreSlices()
        ws()
        if i < n, b[i] == 0x7D { return out }
        while i < n {
            ws()
            guard let keyRange = string() else { return nil }
            ws()
            guard i < n, b[i] == 0x3A else { return nil }
            i += 1
            ws()
            let valueStart = i
            guard skipValue() else { return nil }
            let valueRange = valueStart..<i
            // Keys are compared as raw bytes: a key with an escape in it is neither of ours.
            let key = String(decoding: UnsafeBufferPointer(rebasing: b[keyRange]), as: UTF8.self)
            if key == "farm" {
                if valueRange.count <= StoreLimits.farmBytes { out.farm = Data(UnsafeBufferPointer(rebasing: b[valueRange])) }
            } else if key == "areas" {
                if valueRange.count <= StoreLimits.areasBytes { out.areas = Data(UnsafeBufferPointer(rebasing: b[valueRange])) }
            } else if key.hasPrefix("live:") {
                let token = String(key.dropFirst(5))
                if isToken(token), valueRange.count <= StoreLimits.liveBytes, out.live.count < StoreLimits.liveRecords {
                    out.live[token] = Data(UnsafeBufferPointer(rebasing: b[valueRange]))
                }
            }
            ws()
            guard i < n else { return nil }
            if b[i] == 0x2C { i += 1; continue }
            if b[i] == 0x7D { return out }
            return nil
        }
        return nil
    }
}

/// A live record's token: short lowercase hex or word characters only (it is never shown).
func isToken(_ s: String) -> Bool {
    (1...40).contains(s.utf8.count) && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D || $0 == 0x5F }
}

/// Watches the store file through atomic replaces; calls `onChange` (on the main
/// queue) at most once per DEBOUNCE_MS burst of events.
final class StoreWatcher {
    static let debounce = 0.008
    private var path: String
    private let onChange: () -> Void
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var pending = false
    private(set) var events = 0, reopens = 0
    /// When the first event of the burst being handled arrived (for the latency log).
    private(set) var firstEventAt: Date?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        openFile()
        openDir()
    }

    private func openFile() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return } // not there yet (mid-replace): the folder watch re-opens it
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib, .link, .revoke], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let mask = source.data
            if !mask.intersection([.delete, .rename, .revoke]).isEmpty {
                // Replaced: the inode we hold is gone from the path. Watch the new one.
                self.reopens += 1
                self.openFile()
            }
            self.fire()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    private func openDir() {
        let dir = (path as NSString).deletingLastPathComponent
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // The store moved to the plugin's own file: follow it.
            refreshStorePath()
            if storePath != self.path { self.path = storePath; self.watchedInode = 0; self.reopens += 1; self.openFile() }
            // An entry came or went: if our file source lost its file, pick the new one up.
            if self.fileSource == nil || !self.sameInode() { self.reopens += 1; self.openFile() }
            self.fire()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }

    private var watchedInode: ino_t = 0
    private func sameInode() -> Bool {
        var st = stat()
        guard stat(path, &st) == 0 else { return false }
        defer { watchedInode = st.st_ino }
        return watchedInode == 0 || watchedInode == st.st_ino
    }

    private func fire() {
        events += 1
        guard !pending else { return }
        pending = true
        firstEventAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce) { [weak self] in
            guard let self else { return }
            pending = false
            onChange()
        }
    }
}

/// Reads the store: the farm, the live records and the areas, each only when its bytes changed.
final class StoreSource {
    private var stamp: (Date, Int, UInt64)?
    private(set) var slices = StoreSlices()
    private(set) var farm = Farm()
    private(set) var live: [String: LiveRecord] = [:]
    private(set) var areas = Areas()
    private(set) var reads = 0

    /// Re-reads if the file changed (by mtime, size and inode) or `force`.
    /// Returns which parts changed.
    func refresh(force: Bool = false) -> (farm: Bool, live: Bool, areas: Bool) {
        refreshStorePath()
        var st = stat()
        guard stat(storePath, &st) == 0 else { return (false, false, false) }
        let mtime = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
        let next = (mtime, Int(st.st_size), UInt64(st.st_ino))
        if !force, let stamp, stamp == next { return (false, false, false) }
        stamp = next
        guard st.st_size <= StoreLimits.fileBytes, let data = FileManager.default.contents(atPath: storePath),
              let parts = storeSlices(data) else { return (false, false, false) }
        reads += 1
        var farmChanged = false, liveChanged = false, areasChanged = false
        if parts.farm != slices.farm {
            if let bytes = parts.farm, let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                let next = Farm(object)
                farmChanged = next != farm
                farm = next
            }
        }
        if parts.live != slices.live {
            var records: [String: LiveRecord] = [:]
            for (token, bytes) in parts.live {
                if let old = live[token], slices.live[token] == bytes { records[token] = old; continue }
                if let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let record = LiveRecord(object) {
                    records[token] = record
                }
            }
            liveChanged = records != live
            live = records
        }
        if parts.areas != slices.areas {
            // A missing, oversized or unreadable `areas` is no areas: every camp is then drawn plain.
            let object = parts.areas.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let next = object.map(readAreas) ?? Areas()
            areasChanged = next != areas
            areas = next
        }
        slices = parts
        return (farmChanged, liveChanged, areasChanged)
    }

    var mtime: Date? { stamp?.0 }
}
