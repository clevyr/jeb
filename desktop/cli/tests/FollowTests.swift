// Follow: the one-version rule (pruneVersions' keep-set), the archive-member safety check, and `update`'s wait loop on the
// pinned clock (Clock.sleep advances JEB_TEST_NOW, so no test really waits).
import Foundation

func followTests(_ t: Tester) {
    func names(_ dir: String) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() }

    t.test("pruneVersions: only the folder current points to stays; partial downloads always go") {
        let oldHome = envVar("HOME")
        let h = t.scratch("prune") + "/home"
        setEnvVar("HOME", h)
        defer { setEnvVar("HOME", oldHome) }
        let vd = h + "/.jeb/versions"
        for n in ["v1.4.0", "v1.5.0", "v1.6.0", ".v1.7.0.partial", ".other"] { writeFile(vd + "/" + n + "/bundle.json", "{}") }
        try FileManager.default.createSymbolicLink(atPath: h + "/.jeb/current", withDestinationPath: vd + "/v1.5.0")
        pruneVersions()
        t.eq(names(vd), ["v1.5.0"], "only the live folder stays")
        // current does not resolve: nothing goes but the partial download
        for n in ["v1.4.0", ".v1.8.0.partial"] { writeFile(vd + "/" + n + "/bundle.json", "{}") }
        try FileManager.default.removeItem(atPath: h + "/.jeb/current")
        try FileManager.default.createSymbolicLink(atPath: h + "/.jeb/current", withDestinationPath: vd + "/gone")
        pruneVersions()
        t.eq(names(vd), ["v1.4.0", "v1.5.0"], "dangling current keeps every real version")
    }

    t.test("unsafeMemberReason: rejects links, absolute and .. names and escapes; allows plain members") {
        let dest = t.scratch("extract")
        let outside = t.scratch("extract-outside")
        try FileManager.default.createSymbolicLink(atPath: dest + "/link", withDestinationPath: outside)
        t.eq(unsafeMemberReason(name: "a/b.txt", regular: true, directory: false, dest: dest), nil)
        t.eq(unsafeMemberReason(name: "a", regular: false, directory: true, dest: dest), nil)
        t.check(unsafeMemberReason(name: "x", regular: false, directory: false, dest: dest) != nil, "a symlink or device member")
        t.check(unsafeMemberReason(name: "/etc/passwd", regular: true, directory: false, dest: dest) != nil, "absolute")
        t.check(unsafeMemberReason(name: "a/../../b", regular: true, directory: false, dest: dest) != nil, "..")
        t.check(unsafeMemberReason(name: "..", regular: false, directory: true, dest: dest) != nil, "bare ..")
        t.check(unsafeMemberReason(name: "link/evil", regular: true, directory: false, dest: dest) != nil, "through a symlink out of dest")
        t.eq(unsafeMemberReason(name: "a..b/c", regular: true, directory: false, dest: dest), nil, "a dotted name is not ..")
    }

    t.test("waitForUpdate: polls on the injected clock until the final line or the deadline") {
        let oldState = envVar("JEB_HOME")
        let state = t.scratch("wait") + "/state"
        setEnvVar("JEB_HOME", state)
        defer { setEnvVar("JEB_HOME", oldState); Clock.reload() }
        Clock.reload()
        let t0 = Clock.epoch
        // no status from this run: waits the whole window (wait / poll sleeps) and gives up
        writeFile(updateStatusPath, #"{"at": \#(t0 - 100), "phase": "done", "result": "updated", "detail": "old"}"#)
        let before = Clock.now
        t.eq(waitForUpdate(since: t0, wait: 10, poll: 2), 1)
        t.eq(Clock.now - before, 10, "slept exactly wait seconds in poll steps")
        // a final line from this run: returns at once, without sleeping
        for (res, rc) in [("updated", Int32(0)), ("up-to-date", 0), ("failed", 1)] {
            writeFile(updateStatusPath, #"{"at": \#(t0), "phase": "done", "result": "\#(res)", "detail": "x"}"#)
            let b = Clock.now
            t.eq(waitForUpdate(since: t0, wait: 10, poll: 2), rc, res)
            t.eq(Clock.now - b, 0, "no sleep for \(res)")
        }
        // the defaults are the shipped 30 minutes and 2 seconds
        t.eq(updateWait, 1800); t.eq(updatePoll, 2)
        writeFile(updateStatusPath, #"{"at": \#(t0 - 1), "phase": "fetch"}"#)
        let b2 = Clock.now
        t.eq(waitForUpdate(since: t0), 1)
        t.eq(Clock.now - b2, 1800, "default window")
    }
}
