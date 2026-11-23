// State: the state files under a scratch JEB_HOME: defaults, atomic 0600 writes, the log rotation, the status writer
// against the updater-status golden, bundle_stamp.
import Foundation

func stateTests(_ t: Tester) {
    let home = t.scratch("state") + "/Jeb"
    setHome(home)

    t.test("state defaults and round trips") {
        t.eq(loadRState().dumps(), #"{"failed": [], "checked": null, "last": null}"#)
        t.eq(loadUState().dumps(), #"{"built": null, "stamp": null, "rejected": [], "last": null}"#)
        makePrivateDir(home)
        t.eq(fileMode(home), "0o700")
        var rs = loadRState(); rs.set("checked", .int(Clock.epoch))
        dryRun = true; try saveRState(rs); dryRun = false
        t.check(!lexists(releaseStatePath), "dry run wrote release-state.json")
        try saveRState(rs)
        t.eq(readFile(releaseStatePath), "{\n \"failed\": [],\n \"checked\": 1780000000,\n \"last\": null\n}")
        t.eq(fileMode(releaseStatePath), "0o600")
        var us = loadUState()
        try recordUState(&us, result: "updated", why: "new release", stamp: "123", hash: nil)
        t.eq(loadUState()["last"]?.dumps(), #"{"at": 1780000000, "result": "updated", "why": "new release", "stamp": "123", "hash": null}"#)
    }
    t.test("appendLog: timestamped 0600 lines, newlines folded, rotation past 256 KB") {
        let log = home + "/release.log"
        appendLog(log, "one\ntwo")
        t.eq(readFile(log), "2026-05-28 15:26:40 one | two\n")
        t.eq(fileMode(log), "0o600")
        dryRun = true; rlog("(a dry rlog says this and writes nothing)"); dryRun = false
        t.eq(readFile(log), "2026-05-28 15:26:40 one | two\n", "a dry rlog wrote")
        writeFile(log, String(repeating: "x", count: 256 * 1024 + 1))
        appendLog(log, "after")
        t.eq(readFile(log), "2026-05-28 15:26:40 after\n")
        t.eq(readFile(log + ".1")?.count, 256 * 1024 + 1)
        ulog("u")
        t.eq(readFile(updateLogPath), "2026-05-28 15:26:40 u\n")
    }
    t.test("StatusWriter matches the updater-status golden") {
        unlink(updaterStatePath)
        let w = StatusWriter()
        w.source = "release"; w.final = false
        w.status("checking GitHub")
        let a = readFile(updateStatusPath)
        w.status("downloading v1.5.0", "step 2", step: 2, steps: 5)
        let b = readFile(updateStatusPath)
        w.finish("updated", "not final yet")
        t.eq(readFile(updateStatusPath), b, "finish wrote while final was off")
        w.final = true
        w.status("done", "updated to v1.5.0", result: "updated")
        let c = readFile(updateStatusPath)
        let doc = Json.object([("phase1", try Json.parse(a ?? "")), ("phase2", try Json.parse(b ?? "")), ("final", try Json.parse(c ?? "")), ("mode", .string(fileMode(updateStatusPath) ?? "")),
                               ("load_state_empty", loadUState()), ("bundle_stamp_missing", bundleStamp("/nonexistent").map(Json.string) ?? .null)])
        t.eq(doc.dumps(indent: 1), goldenStdout("runtime/probes/updater-status.txt"))
        t.eq(a?.contains("\n"), false, "status docs are compact")
    }
    t.test("bundleStamp reads CFBundleVersion") {
        let app = t.scratch("stamp") + "/X.app"
        writeFile(app + "/Contents/Info.plist", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleVersion</key><string>20260528.1</string></dict></plist>")
        t.eq(bundleStamp(app), "20260528.1")
        writeFile(app + "/Contents/Info.plist", "junk")
        t.eq(bundleStamp(app), nil)
    }
}
