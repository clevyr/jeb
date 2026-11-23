// Json: the writer against strings json.dumps printed (verified once with /usr/bin/python3 and frozen here), the
// reader's order keeping, and the golden probe/state fixtures round-tripped byte for byte.
import Foundation

let edge = Json.object([
    ("empty", .array([])), ("obj", .object([])),
    ("nest", .array([.int(1), .object([("d", .null), ("e", .array([.array([]), .object([])]))])])),
    ("f", .array([.double(1.5), .double(1e16), .double(1e-5), .double(100000.0), .double(-0.0), .double(0.0001), .double(1e15), .double(2.5e-4), .double(123456789.125), .double(1e22), .double(0.1)])),
    ("i", .array([.int(0), .int(-7), .int(123456789012345678)])),
    ("s", .string("é\u{7f}\"/\n\t\\ \u{1} 😀 日本")),
    ("b", .array([.bool(true), .bool(false)])),
    ("", .string("k")),
])
let edgeCompact = #"{"empty": [], "obj": {}, "nest": [1, {"d": null, "e": [[], {}]}], "f": [1.5, 1e+16, 1e-05, 100000.0, -0.0, 0.0001, 1000000000000000.0, 0.00025, 123456789.125, 1e+22, 0.1], "i": [0, -7, 123456789012345678], "s": "\u00e9\u007f\"/\n\t\\ \u0001 \ud83d\ude00 \u65e5\u672c", "b": [true, false], "": "k"}"#
let edgeIndent1 = "{\n \"empty\": [],\n \"obj\": {},\n \"nest\": [\n  1,\n  {\n   \"d\": null,\n   \"e\": [\n    [],\n    {}\n   ]\n  }\n ],\n \"f\": [\n  1.5,\n  1e+16,\n  1e-05,\n  100000.0,\n  -0.0,\n  0.0001,\n  1000000000000000.0,\n  0.00025,\n  123456789.125,\n  1e+22,\n  0.1\n ],\n \"i\": [\n  0,\n  -7,\n  123456789012345678\n ],\n \"s\": \"\\u00e9\\u007f\\\"/\\n\\t\\\\ \\u0001 \\ud83d\\ude00 \\u65e5\\u672c\",\n \"b\": [\n  true,\n  false\n ],\n \"\": \"k\"\n}"
let edgeIndent2 = "{\n  \"empty\": [],\n  \"obj\": {},\n  \"nest\": [\n    1,\n    {\n      \"d\": null,\n      \"e\": [\n        [],\n        {}\n      ]\n    }\n  ],\n  \"f\": [\n    1.5,\n    1e+16,\n    1e-05,\n    100000.0,\n    -0.0,\n    0.0001,\n    1000000000000000.0,\n    0.00025,\n    123456789.125,\n    1e+22,\n    0.1\n  ],\n  \"i\": [\n    0,\n    -7,\n    123456789012345678\n  ],\n  \"s\": \"\\u00e9\\u007f\\\"/\\n\\t\\\\ \\u0001 \\ud83d\\ude00 \\u65e5\\u672c\",\n  \"b\": [\n    true,\n    false\n  ],\n  \"\": \"k\"\n}"

/// The `## stdout` section of a golden file.
func goldenStdout(_ rel: String) -> String? {
    guard let repo = envVar("JEB_REPO"), let text = readFile(repo + "/desktop/tests/golden/" + rel) else { return nil }
    guard let a = text.range(of: "## stdout\n"), let b = text.range(of: "\n\n## stderr\n") else { return nil }
    return String(text[a.upperBound..<b.lowerBound])
}

func goldenSection(_ rel: String, _ title: String) -> String? {
    guard let repo = envVar("JEB_REPO"), let text = readFile(repo + "/desktop/tests/golden/" + rel) else { return nil }
    guard let a = text.range(of: "## \(title)\n") else { return nil }
    let rest = text[a.upperBound...]
    let end = rest.range(of: "\n\n## ")?.lowerBound ?? rest.endIndex
    return String(rest[..<end]).trimmingCharacters(in: .newlines)
}

func jsonTests(_ t: Tester) {
    t.test("json compact matches json.dumps") { t.eq(edge.dumps(), edgeCompact) }
    t.test("json indent=1 matches json.dumps") { t.eq(edge.dumps(indent: 1), edgeIndent1) }
    t.test("json indent=2 matches json.dumps") { t.eq(edge.dumps(indent: 2), edgeIndent2) }
    t.test("json parse keeps key order and values") {
        t.eq(try Json.parse(edgeCompact), edge)
        t.eq(try Json.parse(edgeIndent2), edge)
        let o = try Json.parse(#"{"z": 1, "a": {"y": [1, 2], "b": null}, "m": "x"}"#)
        t.eq(o.object?.map { $0.0 } ?? [], ["z", "a", "m"])
        t.eq(o["a"]?["y"]?.array?.compactMap { $0.int } ?? [], [1, 2])
        t.eq(try Json.parse(#""\ud83d\ude00""#), .string("😀"))
        t.eq(try Json.parse("[1e2, -0, 3.0]"), .array([.double(100), .int(0), .double(3)]))
    }
    t.test("json parse refuses junk") {
        for bad in ["", "{", "[1,]", "{\"a\" 1}", "nul", "[1] x", "\"a", "{'a': 1}"] {
            t.check((try? Json.parse(bad)) == nil, "accepted \(String(reflecting: bad))")
        }
    }
    t.test("json set/remove keep positions") {
        var o = Json.object([("a", .int(1)), ("b", .int(2))])
        o.set("a", .int(9)); o.set("c", .null); o.remove("b")
        t.eq(o.dumps(), #"{"a": 9, "c": null}"#)
        t.eq(Json.null.truthy, false); t.eq(Json.array([.null]).truthy, true); t.eq(Json.string("").truthy, false)
    }
    t.test("json float layout") {
        for (d, s) in [(1.0, "1.0"), (1e16, "1e+16"), (9999999999999998.0, "9999999999999998.0"), (1e-4, "0.0001"), (9.5e-5, "9.5e-05"), (1.5e300, "1.5e+300"), (-2.0, "-2.0"), (0.0, "0.0"), (1234.5678, "1234.5678")] as [(Double, String)] {
            t.eq(Json.pyFloat(d), s, "\(d)")
        }
    }
    t.test("golden probes re-serialize byte for byte with indent=1") {
        for g in ["runtime/probes/updater-status.txt", "runtime/probes/jebhome.txt", "runtime/probes/signers-parse.txt", "runtime/probes/constants.txt"] {
            guard let text = goldenStdout(g) else { t.fail("no golden \(g) (JEB_REPO unset?)"); continue }
            t.eq(try Json.parse(text).dumps(indent: 1), text, g)
        }
    }
    t.test("golden release-state sample re-serializes byte for byte") {
        guard let text = goldenSection("runtime/follow/ok.txt", "release-state.json") else { t.fail("no follow/ok.txt"); return }
        t.eq(try Json.parse(text).dumps(indent: 1), text)
    }
    t.test("writePrivate: 0600, tmp+rename, mode forced over a stale tmp") {
        let d = t.scratch("json"), p = d + "/f.json"
        writeFile(p + ".tmp", "stale", mode: 0o644)
        try writePrivate("hi\n", to: p)
        t.eq(readFile(p), "hi\n")
        t.eq(fileMode(p), "0o600")
        t.check(!FileManager.default.fileExists(atPath: p + ".tmp"), "tmp left behind")
        try writeJson(.object([("a", .int(1))]), to: p, indent: 1)
        t.eq(readFile(p), "{\n \"a\": 1\n}")
        t.eq(Json.load(p), .object([("a", .int(1))]))
        t.eq(Json.load(d + "/none.json"), nil)
        writeFile(d + "/bad.json", "{nope")
        t.eq(Json.load(d + "/bad.json"), nil)
        t.check((try? writePrivate("x", to: d + "/missing/dir/f")) == nil, "wrote into a missing folder")
    }
}
