// Status: `jebctl status` and `jebctl perf`. Ported from desktop/jebctl (perf_rows, percentile, perf_stats,
// perf_over, cmd_perf, perf_line, cmd_status, release_line). The numbers print as the Python's f-strings did:
// "%.2f" and "%.0f" round the stored double half-to-even on a tie, which is what C's printf does too.
import Foundation

// telemetry (written by the watchdog): the perf classes and their CPU targets, in the probe's order
let cpuTargets: [(String, Double)] = [("calm", 0.5), ("passing", 4.0), ("covered", 0.1)]
let rssTarget = 60.0
let fpTarget = 120.0

// ---- formatting ----

/// format(x, ".<digits>f").
func fixed(_ x: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", x) }

/// f"{s:<width}": padded on the right to width characters.
func ljust(_ s: String, _ width: Int) -> String { s + String(repeating: " ", count: max(0, width - s.unicodeScalars.count)) }

/// f"{s:>width}": padded on the left to width characters.
func rjust(_ s: String, _ width: Int) -> String { String(repeating: " ", count: max(0, width - s.unicodeScalars.count)) + s }

// ---- telemetry ----

struct PerfRow: Equatable {
    var epoch: Int
    var stamp: String
    var cpu: Double
    var rss: Double
    var fp: Double?
    var cls: String
}

let telemetryCsvHeader = "epoch,stamp,pid,interval_s,cpu_pct,rss_mb,footprint_mb,sessions,class\n"

/// One telemetry CSV line (epoch,stamp,..,cpu,rss,fp,..,class), or nil for a short or unreadable one.
func parsePerfRow(_ l: String) -> PerfRow? {
    let f = l.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
    func num(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces)) }
    guard f.count > 8, let epoch = Int(f[0].trimmingCharacters(in: .whitespaces)), let cpu = num(f[4]), let rss = num(f[5]) else { return nil }
    var fp: Double?
    if !f[6].isEmpty {
        guard let v = num(f[6]) else { return nil }
        fp = v
    }
    return PerfRow(epoch: epoch, stamp: f[1], cpu: cpu, rss: rss, fp: fp, cls: f[8])
}

/// The telemetry rows of the last `seconds` (JEB_HOME/telemetry/<date>.csv, oldest file first), for one stamp or all.
func perfRows(_ seconds: Double, stamp: String? = nil) -> [PerfRow] {
    let d = stateHome + "/telemetry"
    let since = Clock.now - seconds
    var out: [PerfRow] = []
    for n in ((try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []).sorted() {
        guard reMatch(#"^\d{4}-\d\d-\d\d\.csv$"#, n) != nil, let data = FileManager.default.contents(atPath: d + "/" + n) else { continue }
        for l in String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).dropFirst() {
            guard let r = parsePerfRow(l), Double(r.epoch) >= since, stamp == nil || r.stamp == stamp else { continue }
            out.append(r)
        }
    }
    return out
}

/// The Python's percentile: the sorted value at index p/100 * n, capped at the last one (no interpolation).
func percentile(_ xs: [Double], _ p: Double) -> Double {
    let s = xs.sorted()
    return s[min(s.count - 1, Int(p / 100 * Double(s.count)))]
}

struct PerfStats: Equatable {
    var n: Int
    var median: Double
    var p95: Double
    var rss: Double
    var fp: Double?
}

/// rows must not be empty.
func perfStats(_ rows: [PerfRow]) -> PerfStats {
    let cpu = rows.map { $0.cpu }
    return PerfStats(n: rows.count, median: percentile(cpu, 50), p95: percentile(cpu, 95), rss: rows.map { $0.rss }.max() ?? 0, fp: rows.compactMap { $0.fp }.max())
}

/// What a class is over its target on: median CPU (the classes that have a target), max RSS, max footprint.
func perfOver(_ cls: String, _ st: PerfStats) -> [String] {
    var over: [String] = []
    if let target = cpuTargets.first(where: { $0.0 == cls })?.1, st.median > target { over.append("CPU") }
    if st.rss > rssTarget { over.append("RSS") }
    if let fp = st.fp, fp > fpTarget { over.append("footprint") }
    return over
}

/// The perf table: a header, then one line per stamp and class, both sorted.
func perfTable(_ rows: [PerfRow]) -> [String] {
    var out = ["\(ljust("stamp", 16)) \(ljust("class", 8)) \(rjust("n", 5)) \(rjust("cpu med %", 10)) \(rjust("cpu p95 %", 10)) \(rjust("max rss MB", 11)) \(rjust("max fp MB", 10))  flags"]
    for st in Set(rows.map { $0.stamp }).sorted() {
        for cls in Set(rows.filter { $0.stamp == st }.map { $0.cls }).sorted() {
            let s = perfStats(rows.filter { $0.stamp == st && $0.cls == cls })
            let over = perfOver(cls, s)
            out.append("\(ljust(st, 16)) \(ljust(cls, 8)) \(rjust(String(s.n), 5)) \(rjust(fixed(s.median, 2), 10)) \(rjust(fixed(s.p95, 2), 10)) \(rjust(fixed(s.rss, 1), 11)) "
                + "\(rjust(s.fp.map { fixed($0, 1) } ?? "-", 10))  \(over.isEmpty ? "ok" : "OVER " + over.joined(separator: "/"))")
        }
    }
    return out
}

func cmdPerf(_ args: [String]) {
    var days = 1.0
    var stamp: String?
    func usage() -> Never { die("usage: jebctl perf [--days N] [--stamp S]") }
    if let i = args.firstIndex(of: "--days") {
        guard i + 1 < args.count, let d = Double(args[i + 1].trimmingCharacters(in: .whitespaces)) else { usage() }
        days = d
    }
    if let i = args.firstIndex(of: "--stamp") {
        guard i + 1 < args.count else { usage() }
        stamp = args[i + 1]
    }
    let rows = perfRows(days * 86400, stamp: stamp)
    if rows.isEmpty { say("no telemetry samples in range"); return }
    for l in perfTable(rows) { say(l) }
}

/// status's one-line summary of an hour of rows.
func perfSummary(_ rows: [PerfRow]) -> String {
    if rows.isEmpty { return "perf (last hour): no samples" }
    let calm = rows.filter { $0.cls == "calm" }.map { $0.cpu }
    var over: [String] = []
    for c in Set(rows.map { $0.cls }).sorted() {
        let o = perfOver(c, perfStats(rows.filter { $0.cls == c }))
        if !o.isEmpty { over.append("\(c) \(o.joined(separator: "/"))") }
    }
    let head = calm.isEmpty ? "no calm samples" : "calm median \(fixed(percentile(calm, 50), 2)) % cpu"
    return "perf (last hour): \(head), max rss \(fixed(rows.map { $0.rss }.max() ?? 0, 0)) MB" + (over.isEmpty ? "" : ", over target: " + over.joined(separator: ", "))
}

func perfLine() -> String { perfSummary(perfRows(3600)) }

// ---- status ----

/// The release line of status and doctor: mode, the live bundle's tag, the pin, the last check and what failed.
func releaseLine() -> String {
    let rs = loadRState()
    let stamp = { (t: Double) in Clock.strftime("%Y-%m-%d %H:%M:%S", t) }
    let chk = rs["checked"].flatMap { $0.truthy ? $0.double : nil }.map(stamp) ?? "never"
    let pinned = isRegularFile(pinnedSignersPath)
    var out = "mode: \(installMode()); bundle \(installedTag() ?? "?"); signers \(pinned ? "pinned" : "NOT pinned (no updates)"); last release check \(chk)"
    if let last = rs["last"], last.truthy { out += ", last result \(pyStr(last["result"])) \(pyStr(last["tag"]))" }
    let failed = failedList(rs)
    if !failed.isEmpty { out += "; failed tags: " + failed.joined(separator: ", ") }
    return out
}

func cmdStatus() {
    let fm = FileManager.default
    let procs = running()
    let beats = beatFiles()
    var isDir: ObjCBool = false
    let hasApp = fm.fileExists(atPath: installedApp, isDirectory: &isDir) && isDir.boolValue
    say("installed app: \(hasApp ? installedApp : "none")" + (hasApp ? " (stamp \(bundleStamp(installedApp) ?? "None"))" : ""))
    say("running: \(procs.count)")
    for p in procs {
        let beat = beats[p.pid].map { "stamp \($0.stamp ?? "None")\($0.waiting ? " (waiting to take over)" : ""), heartbeat \(fixed($0.age, 1)) s old" }
        say("  pid \(p.pid) up \(Int(Clock.now - p.start)) s  " + (beat ?? "no heartbeat (not started by the install)"))
    }
    say("quit marker: " + (fm.fileExists(atPath: stateHome + "/quit") ? "yes (stays quit until login or `jebctl start`)" : "no"))
    say(perfLine())
    say("updates: " + (fm.fileExists(atPath: stateHome + "/updates-paused") ? "paused" : "on"))
    if let st = Json.load(updaterStatePath), st.object != nil {
        if let last = st["last"], last.truthy {
            let at = last["at"]?.double.map { Clock.strftime("%Y-%m-%d %H:%M:%S", $0) } ?? "None"
            let why = String((last["why"]?.string ?? "").unicodeScalars.prefix(300))
            say("last update: \(pyStr(last["result"])) \(pyStr(last["stamp"])) at \(at): \(why)")
        }
        say("rejected builds: \(st["rejected"]?.array?.count ?? 0)")
    } else {
        say("last update: none")
    }
    let vs = ((try? fm.contentsOfDirectory(atPath: appVersionsPath)) ?? []).filter { $0.hasSuffix(".app") }.sorted(by: >).map { String($0.dropLast(4)) }
    say("saved versions: " + (vs.isEmpty ? "none" : vs.joined(separator: ", ")))
    say("agents installed: " + labelsFor("release").map { l in
        "\(l.split(separator: ".").last.map(String.init) ?? l)=\(fm.fileExists(atPath: agentsDir() + "/" + l + ".plist") ? "yes" : "no")"
    }.joined(separator: ", "))
    say(releaseLine())
}
