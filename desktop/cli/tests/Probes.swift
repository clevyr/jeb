// The in-process probes the golden checker runs (jebhome and updater-status),
// so tests/run.sh can diff their output against desktop/tests/golden/runtime/probes/.
// The same keys in the same order; Python sets print as str(set) (pySet).
import Foundation

func fetchOutcome(_ body: () throws -> Json) -> Json {
    do { return try body() } catch let e as FetchError {
        return .object([("FetchError", .string(e.message)), ("status", e.status.map(Json.int) ?? .null)])
    } catch { return .string("\(error)") }
}

/// --probe jebhome --sb <sandbox> --stub <mach-o file> (JEB_RELEASE_BASE, HOME and JEB_REPO from the environment).
func jebhomeProbe(sb: String, stub: String) -> Json {
    var out = Json.object([("release_base", .object([("clevyr/jeb", .string(releaseBase("clevyr/jeb"))), ("x/y", .string(releaseBase("x/y")))]))])
    setEnvVar("JEB_RELEASE_BASE", nil)
    out.set("release_base_default", .string(releaseBase("clevyr/jeb")))
    setEnvVar("JEB_RELEASE_BASE", "file://" + sb + "/rel")
    out.set("paths", .object([("resolve", .string(resolveHome())), ("old_path", .string(oldPath())), ("new_path", .string(newPath())), ("jeb_dir", .string(jebDir())),
                             ("versions_dir", .string(versionsDir())), ("current_dir", .string(currentDir())), ("tools_dir", .string(toolsDir()))]))
    out.set("find_claude", findClaude().map(Json.string) ?? .null)
    out.set("read_bundle", .object([("current", readBundle(currentDir()) ?? .null), ("missing", readBundle("/nonexistent") ?? .null)]))
    let script = (envVar("JEB_REPO") ?? ".") + "/desktop/jebctl"
    out.set("macho_archs", .object([("stub", .string(pySet(machoArchs(stub)))), ("script", .string(pySet(machoArchs(script)))), ("missing", .string(pySet(machoArchs("/nonexistent"))))]))
    let base = releaseBase("clevyr/jeb"), dl = sb + "/dl"
    out.set("fetch", .object([
        ("latest_tag", fetchOutcome { .string(try latestTag(base)) }),
        ("feed_tags", .array(feedTags(base).map(Json.string))),
        ("fetch-missing", fetchOutcome { .string(try save(base + "/nope", to: dl, limit: 10)) }),
        ("fetch-toobig", fetchOutcome { .string(try save(base + "/latest", to: dl, limit: 2)) }),
        ("fetch-ok", fetchOutcome { .string(String(decoding: try fetch(base + "/latest", limit: 100), as: UTF8.self)) }),
    ]))
    return out
}

/// --probe updater-status (JEB_HOME from the environment).
func updaterStatusProbe() -> Json {
    setHome(resolveHome())
    let w = updateStatus
    w.source = "release"; w.final = false
    func doc() -> Json { Json.load(updateStatusPath) ?? .null }
    w.status("checking GitHub")
    let a = doc()
    w.status("downloading v1.5.0", "step 2", step: 2, steps: 5)
    let b = doc()
    w.final = true
    w.status("done", "updated to v1.5.0", result: "updated")
    let c = doc()
    return .object([("phase1", a), ("phase2", b), ("final", c), ("mode", fileMode(updateStatusPath).map(Json.string) ?? .null),
                    ("load_state_empty", loadUState()), ("bundle_stamp_missing", bundleStamp("/nonexistent").map(Json.string) ?? .null)])
}
