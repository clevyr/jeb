// Tests for Agents.swift, Procs.swift and Status.swift: the perf numbers and how they print (the Python's percentile
// and f-string rounding), the telemetry and ps parsers, and the plists an install renders.
import Foundation

private func row(_ stamp: String, _ cls: String, _ cpu: Double, _ rss: Double, _ fp: Double? = nil, epoch: Int = 1780000000) -> PerfRow {
    PerfRow(epoch: epoch, stamp: stamp, cpu: cpu, rss: rss, fp: fp, cls: cls)
}

func statusTests(_ t: Tester) {
    t.test("percentile is the sorted value at p/100 * n, capped at the last") {
        t.eq(percentile([3], 50), 3)
        t.eq(percentile([3], 95), 3)
        t.eq(percentile([1, 2], 50), 2, "even count takes the upper middle")
        t.eq(percentile([5, 1, 4, 2, 3], 50), 3)
        t.eq(percentile([4, 1, 3, 2], 95), 4)
        t.eq(percentile((1...20).map(Double.init), 95), 20, "int(0.95 * 20) is 19")
        t.eq(percentile((1...21).map(Double.init), 95), 20, "int(0.95 * 21) is 19")
        t.eq(percentile((1...100).map(Double.init), 95), 96)
        t.eq(percentile((1...100).map(Double.init), 100), 100, "capped")
    }

    t.test("fixed rounds as Python's format: the stored double, half to even on a real tie") {
        t.eq(fixed(0.5, 0), "0")
        t.eq(fixed(1.5, 0), "2")
        t.eq(fixed(2.5, 0), "2")
        t.eq(fixed(73.5, 0), "74")
        t.eq(fixed(74.5, 0), "74")
        t.eq(fixed(0.125, 2), "0.12")
        t.eq(fixed(0.375, 2), "0.38")
        t.eq(fixed(2.675, 2), "2.67", "2.675 is stored a little under")
        t.eq(fixed(0.25, 1), "0.2")
        t.eq(fixed(0.35, 1), "0.3", "0.35 is stored a little under")
        t.eq(fixed(49, 1), "49.0")
        t.eq(fixed(-0.4, 0), "-0")
    }

    t.test("ljust and rjust pad to a width and never cut") {
        t.eq(ljust("calm", 8), "calm    ")
        t.eq(rjust("0.40", 10), "      0.40")
        t.eq(ljust("a-stamp-longer-than-16", 16), "a-stamp-longer-than-16")
        t.eq(rjust("-", 3), "  -")
    }

    t.test("parsePerfRow reads a watchdog CSV line and skips a short or unreadable one") {
        t.eq(parsePerfRow("1779999000,20260527-190000,1,2,0.40,49.0,89.0,x,calm"), PerfRow(epoch: 1779999000, stamp: "20260527-190000", cpu: 0.4, rss: 49, fp: 89, cls: "calm"))
        t.eq(parsePerfRow("1779999000,s,1,2,7,74,,x,passing,extra")?.fp, nil, "an empty footprint is none")
        t.check(parsePerfRow("1779999000,s,1,2,7,74,,x,passing") != nil, "empty footprint still a row")
        t.check(parsePerfRow("1779999000,s,1,2,7,74,,x") == nil, "no class column")
        t.check(parsePerfRow("soon,s,1,2,7,74,,x,calm") == nil, "epoch not a number")
        t.check(parsePerfRow("1779999000,s,1,2,fast,74,,x,calm") == nil, "cpu not a number")
        t.check(parsePerfRow("1779999000,s,1,2,7,74,big,x,calm") == nil, "footprint not a number")
        t.check(parsePerfRow("") == nil, "empty line")
    }

    t.test("perfRows keeps the rows in range, of one stamp when asked, from dated files only") {
        let home = t.scratch("perf-rows"), was = stateHome
        setHome(home); defer { setHome(was) }
        let now = Clock.epoch
        writeFile(home + "/telemetry/2026-05-27.csv", "epoch,stamp,a,b,cpu,rss,fp,c,class\n\(now - 7200),old,0,0,1,10,,x,calm\n\(now - 60),new,0,0,2,20,30,x,calm\nbroken line\n")
        writeFile(home + "/telemetry/2026-05-28.csv", "epoch,stamp,a,b,cpu,rss,fp,c,class\n\(now),new,0,0,3,40,,x,passing\n")
        writeFile(home + "/telemetry/notes.csv", "epoch,stamp,a,b,cpu,rss,fp,c,class\n\(now),new,0,0,9,99,,x,calm\n")
        t.eq(perfRows(3600).map { $0.cpu }, [2, 3])
        t.eq(perfRows(86400).map { $0.cpu }, [1, 2, 3])
        t.eq(perfRows(86400, stamp: "old").map { $0.cpu }, [1])
        t.eq(perfRows(86400, stamp: "nope").count, 0)
        t.eq(perfRows(60).map { $0.cpu }, [2, 3], "a row exactly at the edge counts")
    }

    t.test("perfStats and perfOver: median and p95 CPU, max RSS and footprint against the targets") {
        let calm = (1...10).map { row("s", "calm", Double($0) / 10, 40 + Double($0), 80 + Double($0)) }
        let st = perfStats(calm)
        t.eq(st, PerfStats(n: 10, median: 0.6, p95: 1.0, rss: 50, fp: 90))
        t.eq(perfOver("calm", st), ["CPU"])
        t.eq(perfOver("passing", st), [], "0.6 is under passing's 4.0")
        t.eq(perfOver("other", st), [], "a class without a CPU target")
        t.eq(perfOver("calm", PerfStats(n: 1, median: 0.5, p95: 0.5, rss: 60, fp: 120)), [], "at the target is not over")
        t.eq(perfOver("covered", PerfStats(n: 1, median: 0.11, p95: 0.11, rss: 60.1, fp: 120.5)), ["CPU", "RSS", "footprint"])
        t.eq(perfStats([row("s", "calm", 1, 2)]).fp, nil)
    }

    t.test("perfTable prints as `jebctl perf` did") {
        var rows = [row("20260526-120000", "covered", 0.05, 30, 50)]
        rows += [0.3, 0.3, 0.3, 0.4, 0.4, 0.4, 0.4, 0.5, 0.5, 0.5].map { row("20260527-190000", "calm", $0, 49, 89) }
        rows += [5, 6, 7, 8, 9].map { row("20260527-190000", "passing", $0, 74) }
        t.eq(perfTable(rows), [
            "stamp            class        n  cpu med %  cpu p95 %  max rss MB  max fp MB  flags",
            "20260526-120000  covered      1       0.05       0.05        30.0       50.0  ok",
            "20260527-190000  calm        10       0.40       0.50        49.0       89.0  ok",
            "20260527-190000  passing      5       7.00       9.00        74.0          -  OVER CPU/RSS",
        ])
        if let want = goldenStdout("runtime/status/perf-default.txt") {
            t.eq(perfTable(rows).joined(separator: "\n"), want, "the perf-default golden")
        } else {
            t.fail("no runtime/status/perf-default.txt golden")
        }
        t.eq(perfTable([row("20260526-120000", "calm", 9, 100, 200)])[1], "20260526-120000  calm         1       9.00       9.00       100.0      200.0  OVER CPU/RSS/footprint")
    }

    t.test("perfSummary is status's perf line") {
        t.eq(perfSummary([]), "perf (last hour): no samples")
        t.eq(perfSummary([row("s", "calm", 0.4, 49)]), "perf (last hour): calm median 0.40 % cpu, max rss 49 MB")
        t.eq(perfSummary([row("s", "passing", 1, 59.5)]), "perf (last hour): no calm samples, max rss 60 MB")
        t.eq(perfSummary([row("s", "passing", 1, 60.5)]), "perf (last hour): no calm samples, max rss 60 MB, over target: passing RSS", "60.5 prints half to even, and is over")
        t.eq(perfSummary([row("s", "calm", 0.4, 49), row("s", "passing", 7, 74), row("s", "covered", 0.2, 10, 130)]),
             "perf (last hour): calm median 0.40 % cpu, max rss 74 MB, over target: covered CPU/footprint, passing CPU/RSS")
    }

    t.test("labelsFor and plists: three release agents, every path under ~/.jeb/current") {
        t.eq(labelsFor("release"), ["com.jeb.desktop", "com.jeb.desktop.watchdog", "com.jeb.desktop.release"])
        let was = envVar("JEB_SRC")
        setEnvVar("JEB_SRC", nil); defer { setEnvVar("JEB_SRC", was) }
        let ps = plists()
        t.eq(ps.map { $0.label }, labelsFor("release"))
        let cur = currentDir()
        t.eq(ps[0].doc["ProgramArguments"] as? [String], [appDir() + "/JebDesktop.app/Contents/MacOS/JebDesktop"])
        t.eq(ps[1].doc["ProgramArguments"] as? [String], [cur + "/desktop/bin/jebctl", "watchdog"])
        t.eq(ps[2].doc["ProgramArguments"] as? [String], [cur + "/desktop/bin/jebctl", "follow"])
        for p in ps {
            t.eq(p.doc["Label"] as? String, p.label)
            t.eq(p.doc["LimitLoadToSessionType"] as? String, "Aqua")
            let env = p.doc["EnvironmentVariables"] as? [String: String] ?? [:]
            t.eq(env["JEB_MOD"], cur + "/mod")
            t.eq(env["JEB_SRC"], cur + "/desktop/src")
            t.eq(env["PATH"], sysPath)
            t.eq(env["JEB_START"], p.label == "com.jeb.desktop" ? "launchd" : nil)
        }
        t.eq(ps[1].doc["StartInterval"] as? Int, 30)
        t.eq(ps[2].doc["StartInterval"] as? Int, 21600)
        t.eq((ps[0].doc["KeepAlive"] as? [String: Bool])?["SuccessfulExit"], false)
    }

    t.test("writePlists writes readable 0644 XML plists, and nothing on a dry run") {
        let dest = t.scratch("plists") + "/launchd"
        let wasVerbose = verbose
        verbose = false; defer { verbose = wasVerbose; dryRun = false }
        dryRun = true
        writePlists(dest)
        t.check(!FileManager.default.fileExists(atPath: dest), "a dry run made the folder")
        dryRun = false
        writePlists(dest)
        for l in labelsFor("release") {
            let p = dest + "/" + l + ".plist"
            t.eq(fileMode(p), "0o644", l)
            let doc = FileManager.default.contents(atPath: p).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
            t.eq(doc?["Label"] as? String, l)
            t.check(readFile(p)?.hasPrefix("<?xml") == true, "\(l) is not XML")
        }
        t.check(!FileManager.default.fileExists(atPath: dest + "/com.jeb.desktop.update.plist"), "the update agent is gone")
    }

    t.test("installMode reads JEB_HOME/install-mode as the Python did") {
        let home = t.scratch("mode"), was = stateHome
        setHome(home); defer { setHome(was) }
        t.eq(installMode(), "dev", "missing")
        writeFile(home + "/install-mode", "release\n")
        t.eq(installMode(), "release")
        writeFile(home + "/install-mode", "other\n")
        t.eq(installMode(), "dev", "odd")
    }

    t.test("parsePsLine reads pid, uid, lstart and the path") {
        let p = parsePsLine("  4242   501 Fri May  8 09:05:07 2026 /Users/a b/Applications/JebDesktop.app/Contents/MacOS/JebDesktop")
        t.eq(p?.pid, 4242)
        t.eq(p?.uid, 501)
        t.eq(p?.path, "/Users/a b/Applications/JebDesktop.app/Contents/MacOS/JebDesktop")
        t.eq(p.map { Clock.strftime("%Y-%m-%d %H:%M:%S", $0.start) }, "2026-05-08 09:05:07", "a one-digit day is padded with a space")
        t.check(parsePsLine("PID UID STARTED COMMAND") == nil, "a header")
        t.check(parsePsLine("") == nil, "empty")
    }

    t.test("beatFiles reads the heartbeat of each pid file and skips the rest") {
        let home = t.scratch("beats"), was = stateHome
        setHome(home); defer { setHome(was) }
        t.eq(beatFiles().count, 0, "no folder")
        writeFile(home + "/heartbeat/100", #"{"stamp": "20260527-190000", "waiting": true}"#)
        writeFile(home + "/heartbeat/200", #"{"waiting": 0}"#)
        writeFile(home + "/heartbeat/300", "not json")
        writeFile(home + "/heartbeat/notes", "{}")
        let b = beatFiles()
        t.eq(b.keys.sorted(), [100, 200])
        t.eq(b[100]?.stamp, "20260527-190000")
        t.eq(b[100]?.waiting, true)
        t.eq(b[200]?.stamp, nil)
        t.eq(b[200]?.waiting, false)
    }

    t.test("waitPid: no pid is true at once, a gone pid is true, a live one gives up after 120 s of the clock") {
        t.check(waitPid([]), "no flag")
        t.check(waitPid(["prune-versions", "--wait-pid"]), "flag without a value")
        t.check(waitPid(["--wait-pid", "0"]), "pid 0")
        let gone = run(["/usr/bin/true"])
        t.eq(gone.status, 0)
        t.check(waitPid(["--wait-pid", "2147483646"]), "a pid that does not exist")
        if Clock.isPinned {
            let before = Clock.now
            t.check(!waitPid(["--wait-pid", String(getpid())]), "this process is still here")
            t.eq(Clock.now - before, 120, "240 sleeps of 0.5 s")
        }
    }

    t.test("the quit marker is a private file that says who wrote it") {
        let home = t.scratch("quit") + "/state", was = stateHome
        setHome(home); defer { setHome(was) }
        writeQuitMarker()
        t.eq(readFile(home + "/quit"), "jebctl\n")
        t.eq(fileMode(home + "/quit"), "0o600")
        t.eq(fileMode(home), "0o700")
    }

    t.test("pruneVersions keeps the folder current points to, and everything while current does not resolve") {
        let home = t.scratch("prune"), wasHome = envVar("HOME"), wasVerbose = verbose
        setEnvVar("HOME", home); verbose = false
        defer { setEnvVar("HOME", wasHome); verbose = wasVerbose; dryRun = false }
        let vd = versionsDir(), fm = FileManager.default
        for n in ["v1.4.0", "v1.5.0"] { writeFile(vd + "/" + n + "/bundle.json", "{}") }
        writeFile(vd + "/.v1.6.0.partial/x", "x")
        pruneVersions()
        t.eq((try? fm.contentsOfDirectory(atPath: vd))?.sorted(), ["v1.4.0", "v1.5.0"], "no current: only the partial goes")
        try? fm.createSymbolicLink(atPath: currentDir(), withDestinationPath: "versions/v1.5.0")
        writeFile(vd + "/.v1.6.0.partial/x", "x")
        dryRun = true
        pruneVersions()
        t.eq((try? fm.contentsOfDirectory(atPath: vd))?.sorted(), [".v1.6.0.partial", "v1.4.0", "v1.5.0"], "a dry run removes nothing")
        dryRun = false
        pruneVersions()
        t.eq((try? fm.contentsOfDirectory(atPath: vd))?.sorted(), ["v1.5.0"])
    }

    t.test("the help text lists the ported command set and nothing dev mode had") {
        for c in ["status", "doctor", "install", "uninstall", "follow", "rollback", "plists", "perf", "pause-updates", "watchdog"] {
            t.check(helpText.contains("\n  \(c) "), "no entry for \(c)")
        }
        for gone in ["--mode", "--build-from-source", "\n  release ", "JEB_SRC", "DEVELOPER_DIR", "Python", "git-clone"] {
            t.check(!helpText.contains(gone), "still mentions \(gone)")
        }
        t.check(helpText.hasSuffix("`current`.\n"), "ends with one newline, as the docstring did")
    }
}
