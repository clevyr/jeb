// Watchdog: keeps exactly one JebDesktop running (desktop/watchdog.py; LaunchAgent com.jeb.desktop.watchdog, every 30 s).
//   - none running, no quit marker: write start-reason, `launchctl kickstart` the agent
//   - none running, quit marker: nothing (Quit stays quit until a login or `jebctl start`)
//   - two or more, and none waiting to take over (heartbeat "waiting"): SIGUSR1 to the newer ones
//   - one running whose heartbeat is stale (>5 s on two checks 10 s apart): TERM, then kickstart
// Stale checks are skipped within 60 s of a wake from sleep, or when this watchdog itself has not run for 90 s (the
// machine was asleep). Log: watchdog.log (0600, rotated at 256 KB).
// After the supervision it samples the one running JebDesktop (CPU, RSS, footprint every 10 min, the heartbeat counters)
// into telemetry/YYYY-MM-DD.csv (kept 14 days by the clock's date: the Python pruned by the real date); see sample().
// A telemetry error is logged and never changes the exit status. --sample-only runs just that.
// --dry-run logs to stdout and signals nothing; --fake-procs "pid:startEpoch:path,..." replaces ps.
// Only the installed app's executable is supervised: the JEB_SRC dev builds went with dev mode (plan D1).
import Foundation

enum Watchdog {
    struct Options {
        var dryRun = false
        var fakeProcs: String?
        var noRecheckWait = false
        var sampleOnly = false
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// argparse's --help for watchdog.py, byte for byte (golden usage/watchdog-help).
    static let help = """
        usage: watchdog.py [-h] [--dry-run] [--fake-procs FAKE_PROCS]
                           [--no-recheck-wait] [--sample-only]

        optional arguments:
          -h, --help            show this help message and exit
          --dry-run
          --fake-procs FAKE_PROCS
          --no-recheck-wait     tests: skip the 10 s between stale checks
          --sample-only         only the telemetry sample: no supervision, no signals

        """

    static let label = "com.jeb.desktop"
    static let stale = 5.0
    static let counters = ["tRun", "tPass", "tCov", "tPause"]
    static var dry = false

    static var logPath: String { stateHome + "/watchdog.log" }
    static var quitMarker: String { stateHome + "/quit" }
    static var beatsDir: String { stateHome + "/heartbeat" }
    static var telemetryDir: String { stateHome + "/telemetry" }
    static var appExe: String { appDir() + "/JebDesktop.app/Contents/MacOS/JebDesktop" }

    // ---- the command ----

    /// `jebctl watchdog ...`: the exit status.
    static func main(_ argv: [String]) -> Int32 {
        var o = Options()
        var i = 0
        func usage(_ why: String) -> Int32 {
            warn(help.components(separatedBy: "\n\n")[0] + "\nwatchdog.py: error: " + why)
            return 2
        }
        while i < argv.count {
            let a = argv[i]
            switch a {
            case "-h", "--help": print(help, terminator: ""); return 0
            case "--dry-run": o.dryRun = true
            case "--no-recheck-wait": o.noRecheckWait = true
            case "--sample-only": o.sampleOnly = true
            case "--fake-procs":
                guard i + 1 < argv.count else { return usage("argument --fake-procs: expected one argument") }
                i += 1
                o.fakeProcs = argv[i]
            default:
                if a.hasPrefix("--fake-procs=") { o.fakeProcs = String(a.dropFirst("--fake-procs=".count)) } else { return usage("unrecognized arguments: " + a) }
            }
            i += 1
        }
        dry = o.dryRun
        do {
            if o.sampleOnly {
                sampleSafely(o.fakeProcs)
                return 0
            }
            let rc = try supervise(o)
            if !dry && o.fakeProcs == nil { sampleSafely(nil) }
            return rc
        } catch {
            log("watchdog error: \(error)")
            return 1
        }
    }

    static func log(_ msg: String) {
        if dry {
            print(Clock.strftime("%Y-%m-%d %H:%M:%S ") + msg)
            return
        }
        appendLog(logPath, msg)
    }

    // ---- processes and heartbeats ----

    /// The running JebDesktop instances (the installed app only), oldest first.
    static func procs(_ fake: String?) throws -> [Proc] { try runningProcs(fake: fake, installedOnly: true) }

    static func readJson(_ path: String) -> Json {
        guard let j = Json.load(path), j.object != nil else { return .object([]) }
        return j
    }

    static func mtime(_ path: String) -> Double? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
    }

    /// The heartbeat files named by a pid.
    static func beatNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: beatsDir)) ?? []).filter { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// pid: (waiting, age in seconds); files of dead pids are removed.
    static func beats() -> [Int32: (waiting: Bool, age: Double)] {
        beatFiles(liveOnly: true, reap: !dry).mapValues { ($0.waiting, $0.age) }
    }

    static func wokeRecently() -> Bool {
        guard let m = reMatch(#"sec = (\d+)"#, run(["/usr/sbin/sysctl", "-n", "kern.waketime"]).out), let at = Double(m[1]) else { return false }
        let since = Clock.now - at
        return since > 0 && since < 60
    }

    static func kickstart() {
        let cmd = ["launchctl", "kickstart", "gui/\(getuid())/\(label)"]
        if dry {
            log("would run: " + cmd.joined(separator: " "))
            return
        }
        if noLaunchctl {
            log("kickstart: skipped (JEB_NO_LAUNCHCTL)")
            return
        }
        let r = launchctlRun(Array(cmd.dropFirst()))
        log("kickstart: exit \(r.status) \(String(r.err.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)))")
    }

    static func touch(_ path: String) {
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        if fd >= 0 { close(fd) }
        utimes(path, nil)
    }

    static func markWatchdogStart() throws {
        if dry { return }
        makePrivateDir(stateHome)
        let p = stateHome + "/start-reason"
        let fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { throw posixError("open", p) }
        _ = "watchdog\n".withCString { write(fd, $0, 9) }
        close(fd)
    }

    static func send(_ pid: Int32, _ sig: Int32, _ why: String) {
        let name = [SIGUSR1: "SIGUSR1", SIGTERM: "SIGTERM", SIGKILL: "SIGKILL"][sig] ?? "signal \(sig)"
        log("\(dry ? "would send" : "sending") \(name) to \(pid): \(why)")
        if !dry { kill(pid, sig) }
    }

    static func stalePids(_ running: [Proc], _ bs: [Int32: (waiting: Bool, age: Double)]) -> [Int32] {
        running.filter { p in
            // no heartbeat at all: only an installed build (inside a bundle) that has run a while is judged
            guard let b = bs[p.pid] else { return p.path.contains(".app/Contents/MacOS/") && Clock.now - p.start > 90 }
            return b.age > stale
        }.map { $0.pid }
    }

    /// run.log is launchd's stderr for the app (held open, append mode): keep the last 200 KB in run.log.1 and empty it past 1 MB.
    static func trimRunLog() {
        let p = stateHome + "/run.log"
        guard let size = (try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? Int, size > 1024 * 1024,
              let f = FileHandle(forReadingAtPath: p) else { return }
        f.seek(toFileOffset: UInt64(size - 200 * 1024))
        let tail = f.readDataToEndOfFile()
        f.closeFile()
        let fd = open(p + ".1", O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return }
        let ok = tail.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) == $0.count }
        close(fd)
        if ok { truncate(p, 0) }
    }

    // ---- supervision ----

    static func supervise(_ o: Options) throws -> Int32 {
        let ranfile = stateHome + "/watchdog.ran"
        let gap = mtime(ranfile).map { Clock.now - $0 } ?? 0
        if !dry {
            makePrivateDir(stateHome)
            touch(ranfile)
            trimRunLog()
        }
        let running = try procs(o.fakeProcs)
        let marker = FileManager.default.fileExists(atPath: quitMarker)
        if running.isEmpty {
            if marker { return 0 }
            let last = stateHome + "/watchdog.kick"
            if let m = mtime(last), Clock.now - m < 45 { return 0 }     // launchd is still starting one (or throttling a crash loop)
            log("none running, no quit marker: starting one")
            if !dry { touch(last) }
            try markWatchdogStart()
            kickstart()
            return 0
        }
        let bs = beats()
        if running.count >= 2 {
            if running.contains(where: { p in bs[p.pid].map { $0.waiting && $0.age < 60 } ?? false }) { return 0 }     // a handoff is in progress
            for p in running.dropFirst() {
                send(p.pid, SIGUSR1, "\(running.count) running and none waiting; keeping \(running[0].pid)")
            }
            return 0
        }
        if stalePids(running, bs).isEmpty { return 0 }
        let pid = running[0].pid
        if gap > 90 || wokeRecently() {
            log("heartbeat stale for pid \(pid), but the machine just woke; not acting")
            return 0
        }
        if !o.noRecheckWait && !dry { Clock.sleep(10) }
        let running2 = try procs(o.fakeProcs)
        if running2.map({ $0.pid }) != running.map({ $0.pid }) || wokeRecently() || stalePids(running2, beats()).isEmpty { return 0 }
        log("pid \(pid): heartbeat stale on two checks; restarting")
        send(pid, SIGTERM, "stale heartbeat")
        if !dry && o.fakeProcs == nil {
            var gone = false
            for _ in 0..<10 where !gone {
                Clock.sleep(0.5)
                gone = try procs(nil).isEmpty
            }
            if !gone {
                send(pid, SIGKILL, "did not stop in 5 s")
                Clock.sleep(1)
            }
        }
        if !FileManager.default.fileExists(atPath: quitMarker) {
            try markWatchdogStart()
            kickstart()
        }
        return 0
    }

    // ---- telemetry ----

    /// ps cputime ([[h:]m:]s.ss) in seconds.
    static func cputimeSeconds(_ text: String) -> Double? {
        var secs = 0.0
        for part in text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false) {
            guard let v = Double(part) else { return nil }
            secs = secs * 60 + v
        }
        return secs
    }

    /// `footprint <pid>` in MB, or nil when it prints no Footprint line. Given 30 s, then stopped.
    static func footprintMB(_ pid: Int32) throws -> Double? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")
        p.arguments = [String(pid)]
        let o = Pipe()
        p.standardOutput = o
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw Failure(description: "footprint: \(error.localizedDescription)") }
        var data = Data()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = o.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + 30) == .timedOut {
            p.terminate()      // our own child, never a JebDesktop
            throw Failure(description: "footprint \(pid) timed out after 30 seconds")
        }
        p.waitUntilExit()
        guard let m = reMatch(#"Footprint:\s*([\d.]+)\s*(KB|MB|GB)"#, String(decoding: data, as: UTF8.self)), let v = Double(m[1]) else { return nil }
        return v * (m[2] == "KB" ? 1.0 / 1024 : m[2] == "GB" ? 1024 : 1)
    }

    static func intervalClass(_ d: [String: Double], _ dt: Double) -> String {
        let half = dt / 2
        if d["tPass", default: 0] > half { return "passing" }
        if d["tCov", default: 0] > half { return "covered" }
        if d["tRun", default: 0] > half { return "calm" }
        return d["tPause", default: 0] > half ? "paused" : "mixed"
    }

    /// The date `days` before the clock's today, as YYYY-MM-DD (datetime.date arithmetic, by Clock.today).
    static func isoDate(daysAgo days: Int) -> String {
        let (y, m, d) = Clock.today
        var t = tm()
        t.tm_year = Int32(y - 1900); t.tm_mon = Int32(m - 1); t.tm_mday = Int32(d - days); t.tm_hour = 12
        var secs = timegm(&t)
        var out = tm()
        gmtime_r(&secs, &out)
        return String(format: "%04d-%02d-%02d", Int(out.tm_year) + 1900, Int(out.tm_mon) + 1, Int(out.tm_mday))
    }

    /// Removes the telemetry CSVs older than 14 days by the clock's date; every other file stays.
    static func pruneTelemetry(_ dir: String) {
        let cutoff = isoDate(daysAgo: 14)
        for n in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where reMatch(#"^\d{4}-\d\d-\d\d\.csv$"#, n) != nil && String(n.prefix(10)) < cutoff {
            unlink(dir + "/" + n)
        }
    }

    /// One row per run for the single running JebDesktop, from the cumulative CPU time and the heartbeat counters since
    /// the previous run (same pid, under 90 s apart).
    static func sample(_ fake: String?) throws {
        let running = try procs(fake)
        guard running.count == 1 else { return }
        let pid = running[0].pid
        let hbPath = beatsDir + "/\(pid)"
        let hb = readJson(hbPath)
        let hbAge = mtime(hbPath).map { Clock.now - $0 }
        if hb["waiting"]?.truthy ?? false || beatNames().contains(where: { readJson(beatsDir + "/" + $0)["waiting"]?.truthy ?? false }) {
            return               // a handoff is in progress
        }
        let ps = run(["/bin/ps", "-o", "cputime=,rss=", "-p", String(pid)]).out.split(whereSeparator: { $0.isWhitespace })
        guard ps.count == 2, let cpu = cputimeSeconds(String(ps[0])), let rssKB = Double(ps[1]) else { return }
        let now = Clock.now, rss = rssKB / 1024, tel = telemetryDir
        makePrivateDir(tel)
        guard chmod(tel, 0o700) == 0 else { throw posixError("chmod", tel) }
        let fpState = readJson(tel + "/footprint.json")
        var fp: Double?
        let fpAt = fpState["at"]?.double ?? 0
        if fpState["pid"]?.int != Int(pid) || now - fpAt >= 600 || fpAt > now {
            fp = try footprintMB(pid)
            try writePrivate(Json.object([("pid", .int(Int(pid))), ("at", .double(now))]).dumps(), to: tel + "/footprint.json")
        }
        var cur: [(String, Json)] = []
        if let age = hbAge, age < 10 {
            cur = counters.compactMap { k in hb[k].flatMap { v in v.bool == nil && v.double != nil ? (k, v) : nil } }
        }
        let prev = readJson(tel + "/last.json")
        try writePrivate(Json.object([("pid", .int(Int(pid))), ("wall", .double(now)), ("cpu", .double(cpu)), ("c", .object(cur))]).dumps(), to: tel + "/last.json")
        let dt = now - (prev["wall"]?.double ?? 0), prevCpu = prev["cpu"]?.double ?? 0
        guard prev["pid"]?.int == Int(pid), dt > 0, dt < 90, cpu >= prevCpu, cur.count == 4, prev["c"]?.object?.count == 4 else { return }
        var d: [String: Double] = [:]
        for (k, v) in cur {
            guard let was = prev["c"]?[k]?.double, let v = v.double, v - was >= 0 else { return }
            d[k] = v - was
        }
        let path = tel + "/" + Clock.strftime("%Y-%m-%d.csv", now)
        let new = !FileManager.default.fileExists(atPath: path)
        let stamp: String = hb["stamp"].map { $0.string ?? $0.dumps() } ?? ""
        var sessions = ""
        if case let .int(n)? = hb["sessions"] { sessions = String(n) }
        let row = "\(Int(now)),\(stamp),\(pid)," + String(format: "%.1f,%.2f,%.1f,", dt, (cpu - prevCpu) / dt * 100, rss)
            + (fp.map { String(format: "%.1f", $0) } ?? "") + ",\(sessions),\(intervalClass(d, dt))\n"
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw posixError("open", path) }
        let bytes = Array(((new ? telemetryCsvHeader : "") + row).utf8)
        let wrote = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        close(fd)
        guard wrote == bytes.count else { throw posixError("write", path) }
        pruneTelemetry(tel)
    }

    /// Telemetry never breaks supervision: an error is logged once per distinct message and swallowed.
    static func sampleSafely(_ fake: String?) {
        do { try sample(fake) } catch {
            let msg = "telemetry error: \(error)"
            let seen = stateHome + "/telemetry-error.txt"
            if FileManager.default.contents(atPath: seen).map({ String(decoding: $0, as: UTF8.self) }) != msg {
                log(msg)
                try? writePrivate(msg, to: seen)
            }
        }
    }
}
