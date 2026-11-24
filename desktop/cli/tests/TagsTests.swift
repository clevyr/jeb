// Tags: tag_key and the ordering, release_tags/head_tags over a canned git runner (the release-tags-canned golden),
// and what release-state.json remembers: failed tags against the pin, the installed list.
import Foundation

func tagsTests(_ t: Tester) {
    let home = t.scratch("tags") + "/Jeb"
    setHome(home)

    t.test("tagKey is a full match of vMAJOR.MINOR.PATCH") {
        func key(_ s: String) -> String { tagKeyJson(s).dumps() }
        t.eq(key("v1.2.3"), "[1, 2, 3]"); t.eq(key("v0.0.0"), "[0, 0, 0]"); t.eq(key("v10.20.30"), "[10, 20, 30]")
        for bad in ["", "v", "1.2.3", "V1.2.3", "v1.2", "v1.2.3.4", "v01.2.3", "v1.02.3", "v1.2.03", "v1.2.3-rc1", "v1.2.3+b", " v1.2.3", "v1.2.3 ", "v1.2.3\n", "xv1.2.3", "v1.2.x", "v-1.2.3"] {
            t.eq(key(bad), "null", String(reflecting: bad))
        }
    }
    t.test("rollbackFloor: the Python releases (1.6.x and older) are under it, 1.7.0 is not") {
        t.check(tagKey("v1.6.9")! < rollbackFloor, "1.6.x is refused")
        t.check(!(tagKey("v1.7.0")! < rollbackFloor), "1.7.0 is allowed")
    }
    t.test("sortedTags: by number, oldest first, anything else dropped") {
        t.eq(sortedTags(["v1.10.0", "v1.2.0", "foo", "v1.9.3", "v2.0.0", "v1.2", "v0.0.1", "v1.2.0-rc1"]), ["v0.0.1", "v1.2.0", "v1.9.3", "v1.10.0", "v2.0.0"])
        t.eq(sortedTags(["v1.0.10", "v1.0.9", "v1.0.9", "v0.99.99"]), ["v0.99.99", "v1.0.9", "v1.0.9", "v1.0.10"])
        t.eq(sortedTags([]), []); t.eq(sortedTags(["foo", "v1"]), [])
    }
    t.test("releaseTags and headTags with a canned git runner") {
        // the canned answers the Python probe patched git() with (PROBES["release-tags-canned"] in the golden checker)
        var asked: [[String]] = []
        let git: GitRunner = { a in
            asked.append(a)
            switch a.joined(separator: " ") {
            case "tag --list v*": return RunResult(status: 0, out: "v1.10.0\nv1.2.0\nfoo\nv1.9.3\nv2.0.0\nv1.2\n", err: "")
            case "tag --list v* --points-at HEAD": return RunResult(status: 0, out: "v1.9.3\nv1.2\n", err: "")
            default: return RunResult(status: 1, out: "", err: "unexpected")
            }
        }
        let doc = Json.object([("release_tags", .array(releaseTags(git: git).map(Json.string))), ("head_tags", .array(headTags(git: git).map(Json.string)))])
        t.eq(doc.dumps(), goldenStdout("runtime/probes/release-tags-canned.txt"))
        t.eq(asked, [["tag", "--list", "v*"], ["tag", "--list", "v*", "--points-at", "HEAD"]])
        t.eq(releaseTags(git: { _ in RunResult(status: 128, out: "", err: "fatal: not a git repository") }), [], "a failing git is no tags")
    }
    t.test("markFailed and clearFailed") {
        var rs = Json.object([("checked", .null)])
        markFailed(&rs, "v1.5.0", kind: "gates")
        t.eq(rs.dumps(), #"{"checked": null, "failed": ["v1.5.0"], "failed_why": {"v1.5.0": {"why": "gates", "pin": ""}}}"#, "no pin hashes to an empty string")
        writeFile(pinnedSignersPath, "pin\n")
        let pin = sha256Hex(Data("pin\n".utf8))
        t.eq(pinHash(), pin)
        markFailed(&rs, "v1.6.0", kind: "signature"); markFailed(&rs, "v1.5.0", kind: "sha")
        t.eq(rs["failed"]?.dumps(), #"["v1.5.0", "v1.6.0"]"#, "a tag is listed once")
        t.eq(rs["failed_why"]?.dumps(), "{\"v1.5.0\": {\"why\": \"sha\", \"pin\": \"\(pin)\"}, \"v1.6.0\": {\"why\": \"signature\", \"pin\": \"\(pin)\"}}", "the reason is replaced in place")
        clearFailed(&rs, "v9.9.9")
        t.eq(rs["failed"]?.dumps(), #"["v1.5.0", "v1.6.0"]"#, "clearing an unknown tag changes nothing")
        clearFailed(&rs, "v1.5.0")
        t.eq(rs.dumps(), "{\"checked\": null, \"failed\": [\"v1.6.0\"], \"failed_why\": {\"v1.6.0\": {\"why\": \"signature\", \"pin\": \"\(pin)\"}}}")
        var bare = Json.object([("failed", .array([.string("v1.5.0")])), ("failed_why", .null)])
        clearFailed(&bare, "v1.5.0")
        t.eq(bare.dumps(), #"{"failed": [], "failed_why": null}"#)
        var none = Json.object([])
        clearFailed(&none, "v1.5.0")
        t.eq(none.dumps(), "{}")
    }
    t.test("failedSkip: a signature rejection under another pin gets another look") {
        let pin = pinHash()
        func rs(_ why: String) -> Json { (try? Json.parse(#"{"failed": ["v1.5.0", "v1.6.0"], "failed_why": \#(why)}"#)) ?? .null }
        t.eq(failedSkip(rs("null")), ["v1.5.0", "v1.6.0"])
        t.eq(failedSkip(rs(#"{"v1.5.0": {"why": "signature", "pin": "\#(pin)"}}"#)), ["v1.5.0", "v1.6.0"], "same pin: still skipped")
        t.eq(failedSkip(rs(#"{"v1.5.0": {"why": "signature", "pin": "old"}, "v1.6.0": {"why": "sha", "pin": "old"}}"#)), ["v1.6.0"])
        t.eq(failedSkip(rs(#"{"v1.5.0": {"why": "signature"}, "v1.6.0": "junk"}"#)), ["v1.6.0"], "a missing pin is another pin")
        t.eq(failedSkip(.object([])), [])
        unlink(pinnedSignersPath)
        t.eq(failedSkip(rs(#"{"v1.5.0": {"why": "signature", "pin": ""}}"#)), ["v1.5.0", "v1.6.0"], "no pin then and none now")
    }
    t.test("recordInstalled keeps the last 20") {
        unlink(updaterStatePath)
        var rs = Json.object([("failed", .array([]))])
        recordInstalled(&rs, "v1.0.0")
        t.eq(rs.dumps(), #"{"failed": [], "installed": [{"tag": "v1.0.0", "stamp": null, "at": 1780000000}]}"#)
        writeFile(updaterStatePath, #"{"built": null, "stamp": "20260528.1", "rejected": [], "last": null}"#)
        for i in 1...24 { recordInstalled(&rs, "v1.0.\(i)") }
        let list = rs["installed"]?.array ?? []
        t.eq(list.count, 20)
        t.eq(list.first?.dumps(), #"{"tag": "v1.0.5", "stamp": "20260528.1", "at": 1780000000}"#)
        t.eq(list.last?["tag"]?.string, "v1.0.24")
        unlink(updaterStatePath)
    }
}
