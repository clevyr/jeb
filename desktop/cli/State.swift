// State: the files in the state folder that jebctl and the updater share (desktop/jebctl load_rstate/save_rstate/rlog,
// desktop/updater.py log/status/load_state/save_state/record/notify_finished/bundle_stamp). Every write is tmp+rename
// at mode 0600; the logs rotate once at 256 KB. The folder is set once from resolveHome() and re-pointed by setHome()
// after a migration, as the Python's set_home did.
import Foundation

var stateHome = resolveHome()

/// (Re)derive the paths that hang off the state folder.
func setHome(_ home: String) { stateHome = home }

var releaseStatePath: String { stateHome + "/release-state.json" }
var releaseLogPath: String { stateHome + "/release.log" }
var updateLogPath: String { stateHome + "/update.log" }
var updaterStatePath: String { stateHome + "/updater-state.json" }
var updateStatusPath: String { stateHome + "/update-status.json" }
var modeFilePath: String { stateHome + "/install-mode" }
var pinnedSignersPath: String { stateHome + "/release-signers" }      // pinned at install; follow trusts no other key
var appVersionsPath: String { stateHome + "/versions" }                // the updater's saved <stamp>.app folders

// ---- release-state.json (jebctl) ----

func loadRState() -> Json {
    Json.load(releaseStatePath) ?? .object([("failed", .array([])), ("checked", .null), ("last", .null)])
}

/// Skipped on a dry run; indent 1 like the Python's json.dump(rs, f, indent=1).
func saveRState(_ rs: Json) throws {
    if dryRun { return }
    try writeJson(rs, to: releaseStatePath, indent: 1)
}

// ---- updater-state.json (updater) ----

func loadUState() -> Json {
    Json.load(updaterStatePath) ?? .object([("built", .null), ("stamp", .null), ("rejected", .array([])), ("last", .null)])
}

func saveUState(_ st: Json) throws { try writeJson(st, to: updaterStatePath, indent: 1) }

func recordUState(_ st: inout Json, result: String, why: String, stamp: String? = nil, hash: String? = nil) throws {
    st.set("last", .object([("at", .int(Clock.epoch)), ("result", .string(result)), ("why", .string(why)),
                            ("stamp", stamp.map(Json.string) ?? .null), ("hash", hash.map(Json.string) ?? .null)]))
    try saveUState(st)
}

// ---- logs ----

/// One timestamped line appended at mode 0600; the file moves to .1 once it passes 256 KB. Newlines in msg become " | ".
func appendLog(_ path: String, _ msg: String) {
    makePrivateDir(stateHome)
    if let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int), size > 256 * 1024 {
        rename(path, path + ".1")
    }
    let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    guard fd >= 0 else { return }
    let bytes = Array((Clock.strftime("%Y-%m-%d %H:%M:%S ") + msg.replacingOccurrences(of: "\n", with: " | ") + "\n").utf8)
    _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    close(fd)
}

/// jebctl's rlog: said, then written to release.log (not on a dry run).
func rlog(_ msg: String) {
    say(msg)
    if dryRun { return }
    appendLog(releaseLogPath, msg)
}

/// The updater's log(): update.log only (its stdout is launchd's).
func ulog(_ msg: String) { appendLog(updateLogPath, msg) }

// ---- update-status.json (updater) ----

let finishedNotification = "com.jeb.desktop.update-finished"      // Darwin notification the app listens for (UpdateNotifier.swift)

@_silgen_name("notify_post") private func notify_post(_ name: UnsafePointer<CChar>) -> UInt32

/// Tells the running app (a Darwin notification) to read the final status; never raises. Off in the sandbox (JEB_NO_LAUNCHCTL).
func notifyFinished() {
    if noLaunchctl { return }
    _ = finishedNotification.withCString { notify_post($0) }
}

/// Writes update-status.json (atomic, 0600). Never fails: a status that cannot be written must not stop an update.
/// source: "dev" for the updater's own builds, "release" for the follower; final: whether finish() writes "done".
final class StatusWriter {
    var source = "dev"
    var final = true
    var clicked = false
    private var started: Int?
    var startedAt: Int? { started }
    private var finished = false

    func status(_ phase: String, _ detail: String = "", step: Int? = nil, steps: Int? = nil, result: String? = nil) {
        let now = Clock.epoch
        if started == nil { started = now }
        let firstDone = phase == "done" && !finished
        if phase == "done" { finished = true }
        let doc = Json.object([
            ("phase", .string(phase)), ("detail", .string(detail)), ("step", step.map(Json.int) ?? .null), ("steps", steps.map(Json.int) ?? .null),
            ("started", .int(started!)), ("at", .int(now)), ("result", result.map(Json.string) ?? .null), ("source", .string(source)),
            ("pid", .int(Int(Clock.pid))), ("clicked", .bool(clicked)),
        ])
        makePrivateDir(stateHome)
        try? writeJson(doc, to: updateStatusPath)
        if firstDone { notifyFinished() }
    }

    /// The final status of this run; the release follower writes its own instead.
    func finish(_ result: String, _ detail: String) {
        if final { status("done", String(detail.prefix(160)), result: result) }
    }
}

let updateStatus = StatusWriter()

/// CFBundleVersion of app/Contents/Info.plist, or nil.
func bundleStamp(_ app: String) -> String? {
    guard let d = FileManager.default.contents(atPath: app + "/Contents/Info.plist"),
          let doc = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return nil }
    return doc["CFBundleVersion"] as? String
}
