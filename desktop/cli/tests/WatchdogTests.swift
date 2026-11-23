// Watchdog: the pure pieces (fake process list, stale rule, cputime, interval class), and the telemetry sample under a
// scratch JEB_HOME: one CSV row from the heartbeat counters, and the 14-day prune by the pinned clock's date (the
// Python pruned by the real date). Nothing is signalled: the only process named is this test runner, through ps.
import Foundation

func watchdogTests(_ t: Tester) {
    let before = stateHome
    let home = t.scratch("watchdog") + "/Jeb"
    setHome(home)
    defer { setHome(before) }
    let exe = Watchdog.appExe
    let now = Clock.now

    t.test("watchdog: fake process list is filtered to the installed app and sorted oldest first") {
        let ps = try Watchdog.procs("200:\(now - 50):\(exe),100:\(now - 500):\(exe),300:\(now - 900):/elsewhere/JebDesktop")
        t.eq(ps.map { $0.pid }, [100, 200])
        t.eq(try Watchdog.procs("").count, 0)
        t.check((try? Watchdog.procs("x:1:\(exe)")) == nil, "a malformed entry did not throw")
    }
    t.test("watchdog: stale rule, cputime, interval class, lstart") {
        let p = Proc(pid: 100, start: now - 500, path: exe)
        t.eq(Watchdog.stalePids([p], [:]), [100], "no heartbeat, installed build, up 500 s")
        t.eq(Watchdog.stalePids([Proc(pid: 100, start: now - 60, path: exe)], [:]), [], "no heartbeat, up 60 s")
        t.eq(Watchdog.stalePids([Proc(pid: 100, start: now - 500, path: "/src/JebDesktop")], [:]), [], "no heartbeat, not in a bundle")
        t.eq(Watchdog.stalePids([p], [100: (waiting: false, age: 5.5)]), [100])
        t.eq(Watchdog.stalePids([p], [100: (waiting: false, age: 4.0)]), [])
        t.eq(Watchdog.cputimeSeconds("1:02:03.50"), 3723.5); t.eq(Watchdog.cputimeSeconds("0:01.25"), 1.25); t.eq(Watchdog.cputimeSeconds("x"), nil)
        t.eq(Watchdog.intervalClass(["tRun": 30, "tPass": 16, "tCov": 0, "tPause": 0], 30), "passing")
        t.eq(Watchdog.intervalClass(["tRun": 30, "tPass": 0, "tCov": 16, "tPause": 0], 30), "covered")
        t.eq(Watchdog.intervalClass(["tRun": 16, "tPass": 0, "tCov": 0, "tPause": 0], 30), "calm")
        t.eq(Watchdog.intervalClass(["tRun": 0, "tPass": 0, "tCov": 0, "tPause": 16], 30), "paused")
        t.eq(Watchdog.intervalClass(["tRun": 10, "tPass": 10, "tCov": 10, "tPause": 0], 30), "mixed")
        t.eq(parsePsLine("1 \(getuid()) Thu May 28 15:26:40 2026 /x")?.start, 1780000000, "TZ=America/Chicago expected")
        t.eq(parsePsLine("1 \(getuid()) Mon Jun  1 00:00:00 2026 /x")?.start, 1780290000)
    }
    t.test("watchdog: the telemetry prune keeps 14 days by the clock's date, not the real one") {
        // the pinned today is 2026-05-28: 13 and 14 days back stay, 15 goes; the real date would drop all three
        let tel = t.scratch("watchdog-prune")
        t.eq(Watchdog.isoDate(daysAgo: 0), "2026-05-28"); t.eq(Watchdog.isoDate(daysAgo: 14), "2026-05-14"); t.eq(Watchdog.isoDate(daysAgo: 28), "2026-04-30")
        for n in ["2026-05-15.csv", "2026-05-14.csv", "2026-05-13.csv", "2026-05-28.csv", "last.json", "2026-05-01.csv.bak", "notes-2026-05-01.csv"] { writeFile(tel + "/" + n, "x") }
        Watchdog.pruneTelemetry(tel)
        t.eq(((try? FileManager.default.contentsOfDirectory(atPath: tel)) ?? []).sorted(),
             ["2026-05-01.csv.bak", "2026-05-14.csv", "2026-05-15.csv", "2026-05-28.csv", "last.json", "notes-2026-05-01.csv"])
    }
    t.test("watchdog: sample writes one row and prunes the 15-day-old file") {
        let pid = getpid(), tel = Watchdog.telemetryDir
        let fake = "\(pid):\(now - 500):\(exe)"
        writeFile(Watchdog.beatsDir + "/\(pid)", #"{"waiting": false, "stamp": "20260527-190000", "sessions": 3, "tRun": 130.5, "tPass": 20, "tCov": 0, "tPause": 0}"#)
        writeFile(tel + "/footprint.json", #"{"pid": \#(pid), "at": \#(now - 60)}"#)      // fresh: `footprint` is not run
        writeFile(tel + "/2026-05-15.csv", telemetryCsvHeader)       // 13 days old
        writeFile(tel + "/2026-05-13.csv", telemetryCsvHeader)       // 15 days old
        // no previous sample: last.json only
        try Watchdog.sample(fake)
        let today = tel + "/2026-05-28.csv"
        t.check(!lexists(today), "a row without a previous sample")
        t.eq(Json.load(tel + "/last.json")?["c"]?.dumps(), #"{"tRun": 130.5, "tPass": 20, "tCov": 0, "tPause": 0}"#)
        t.eq(fileMode(tel + "/last.json"), "0o600"); t.eq(fileMode(tel), "0o700")
        t.check(lexists(tel + "/2026-05-13.csv"), "pruned without writing a row")
        // a previous sample 30 s back
        writeFile(tel + "/last.json", #"{"pid": \#(pid), "wall": \#(now - 30), "cpu": 0.0, "c": {"tRun": 100.5, "tPass": 0, "tCov": 0, "tPause": 0}}"#)
        try Watchdog.sample(fake)
        let lines = (readFile(today) ?? "").split(separator: "\n").map(String.init)
        t.eq(lines.count, 2); t.eq(lines.first.map { $0 + "\n" }, telemetryCsvHeader)
        t.check(reMatch(#"^1780000000,20260527-190000,\#(pid),30\.0,\d+\.\d\d,\d+\.\d,,3,passing$"#, lines.last ?? "") != nil, "row: \(lines.last ?? "")")
        t.eq(fileMode(today), "0o600")
        t.check(lexists(tel + "/2026-05-15.csv"), "the 13-day-old file was pruned")
        t.check(!lexists(tel + "/2026-05-13.csv"), "the 15-day-old file was kept")
        // a heartbeat that waits to take over: no row
        writeFile(Watchdog.beatsDir + "/\(pid)", #"{"waiting": true}"#)
        try Watchdog.sample(fake)
        t.eq((readFile(today) ?? "").split(separator: "\n").count, 2)
    }
    t.test("watchdog: usage errors exit 2, --help exits 0") {
        t.eq(Watchdog.main(["--nope"]), 2); t.eq(Watchdog.main(["--fake-procs"]), 2)
        t.check(Watchdog.help.hasPrefix("usage: watchdog.py [-h] [--dry-run] [--fake-procs FAKE_PROCS]\n"), "help text")
    }
}
