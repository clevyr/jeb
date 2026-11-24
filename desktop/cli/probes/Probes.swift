// The in-process probes the golden checker runs (PROBES in desktop/tests/goldencheck/Scenarios.swift),
// so `jebctl --probe <name>` prints the same JSON as desktop/tests/golden/runtime/probes/.
// The same keys in the same order; Python sets print as str(set) (pySet). spec is $JEB_PROBE_SPEC: the checker's
// sb (the sandbox root), pub (the throwaway public key), stub (a Mach-O file) and the probe's own inputs.
import Foundation

/// The probe's JSON, or nil for a name this build does not answer.
func runProbe(_ name: String, spec: Json) -> Json? {
    let sb = spec["sb"]?.string ?? "."
    switch name {
    case "jebhome": return jebhomeProbe(sb: sb, stub: spec["stub"]?.string ?? "/nonexistent")
    case "updater-status": return updaterStatusProbe()
    case "tag-order": return tagOrderProbe()
    case "failed-skip": return failedSkipProbe()
    case "signers-parse": return signersParseProbe(pub: spec["pub"]?.string ?? "")
    case "new-tags": return newTagsProbe()
    case "check-sandbox": return checkSandboxProbe()
    case "constants": return constantsProbe()
    case "verify-manifest": return verifyManifestProbe(cases: spec["cases"] ?? .object([]))
    case "plugdirs": return plugdirsProbe(sb: sb)
    case "write-plists": writePlists(stateHome + "/launchd"); return .object([])      // golden setup: the LaunchAgent plists
    default: return nil
    }
}

/// A Python-style str(set): {'arm64'} / set(); several members sorted (Python's order is hash-dependent).
func pySet(_ s: Set<String>) -> String {
    s.isEmpty ? "set()" : "{" + s.sorted().map { "'\($0)'" }.joined(separator: ", ") + "}"
}

func fetchOutcome(_ body: () throws -> Json) -> Json {
    do { return try body() } catch let e as FetchError {
        return .object([("FetchError", .string(e.message)), ("status", e.status.map(Json.int) ?? .null)])
    } catch { return .string("\(error)") }
}

/// jebhome: release_base, the paths, find_claude, read_bundle, macho_archs and the fetch helpers against <sb>/rel.
func jebhomeProbe(sb: String, stub: String) -> Json {
    var out = Json.object([("release_base", .object([("clevyr/jeb", .string(releaseBase("clevyr/jeb"))), ("x/y", .string(releaseBase("x/y")))]))])
    setEnvVar("JEB_RELEASE_BASE", nil)
    out.set("release_base_default", .string(releaseBase("clevyr/jeb")))
    setEnvVar("JEB_RELEASE_BASE", "file://" + sb + "/rel")
    out.set("paths", .object([("resolve", .string(resolveHome())), ("old_path", .string(oldPath())), ("new_path", .string(newPath())), ("jeb_dir", .string(jebDir())),
                             ("versions_dir", .string(versionsDir())), ("current_dir", .string(currentDir())), ("tools_dir", .string(toolsDir()))]))
    out.set("find_claude", findClaude().map(Json.string) ?? .null)
    out.set("read_bundle", .object([("current", readBundle(currentDir()) ?? .null), ("missing", readBundle("/nonexistent") ?? .null)]))
    let script = currentDir() + "/desktop/jebctl"      // the Python probe read its own script: a text file, so no arch
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

/// updater-status: three status() phases into update-status.json, its mode, load_state on nothing, a missing bundle_stamp.
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

func tagOrderProbe() -> Json {
    let tags = fields("v1.10.0 v1.2.0 v1.9.3 v2.0.0 v1.2.0-rc1 foo v1.2 v0.0.1 v01.2.3")
    return .object([("tag_key", .object(tags.map { ($0, tagKeyJson($0)) })), ("sorted", .array(sortedTags(tags).map(Json.string)))])
}

func failedSkipProbe() -> Json {
    func why(_ kind: String, _ pin: String) -> Json { .object([("why", .string(kind)), ("pin", .string(pin))]) }
    let pin = pinHash()
    let cases: [(String, Json)] = [
        ("no-failed", .object([("failed", .array([]))])),
        ("plain-list", .object([("failed", .array([.string("v1.5.0"), .string("v1.6.0")]))])),
        ("gates-same-pin", .object([("failed", .array([.string("v1.5.0")])), ("failed_why", .object([("v1.5.0", why("gates", pin))]))])),
        ("signature-same-pin", .object([("failed", .array([.string("v1.5.0")])), ("failed_why", .object([("v1.5.0", why("signature", pin))]))])),
        ("signature-other-pin", .object([("failed", .array([.string("v1.5.0")])), ("failed_why", .object([("v1.5.0", why("signature", "x"))]))])),
        ("mixed", .object([("failed", .array([.string("v1.5.0"), .string("v1.6.0"), .string("v1.7.0")])),
                           ("failed_why", .object([("v1.5.0", why("signature", "x")), ("v1.6.0", why("sha", "x")), ("v1.7.0", .string("junk"))]))])),
    ]
    var out = Json.object(cases.map { ($0.0, .array(failedSkip($0.1).map(Json.string))) })
    var rs = Json.object([("failed", .array([]))])
    markFailed(&rs, "v1.5.0", kind: "gates"); markFailed(&rs, "v1.5.0", kind: "sha"); markFailed(&rs, "v1.6.0", kind: "signature")
    // Python stored the same dict under both keys, so mark_failed prints the state after the clears too
    clearFailed(&rs, "v1.5.0"); clearFailed(&rs, "v9.9.9")
    out.set("mark_failed", rs)
    out.set("after_clear", rs)
    let data = FileManager.default.contents(atPath: pinnedSignersPath) ?? Data()
    out.set("pin_hash_is_sha256_of_pin_text", .bool(pinHash() == sha256Hex(data)))
    return out
}

func signersParseProbe(pub K: String) -> Json {
    let lines: [(String, String)] = [
        ("plain", "jeb-release \(K)"),
        ("ns-jeb", "jeb-release namespaces=\"jeb-release\" \(K)"),
        ("ns-both", "me@example.com namespaces=\"git,jeb-release\" \(K)"),
        ("ns-git-only", "me@example.com namespaces=\"git\" \(K)"),
        ("other-option", "me@example.com cert-authority namespaces=\"jeb-release\" \(K)"),
        ("valid-after", "me@example.com namespaces=\"jeb-release\",valid-after=\"20250101\" \(K)"),
        ("comment", "# a comment"),
        ("blank", ""),
        ("no-key", "jeb-release namespaces=\"jeb-release\""),
        ("ecdsa", "me ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGQ"),
        ("sk", "me sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA"),
    ]
    func L(_ n: String) -> String { lines.first { $0.0 == n }!.1 }
    let texts: [(String, String)] = [
        ("two-good", L("ns-jeb") + "\n" + L("ns-both") + "\n"),
        ("comment-and-good", "# c\n\n" + L("ns-jeb") + "\n"),
        ("git-only", L("ns-git-only") + "\n"),
        ("other-option", L("other-option") + "\n"),
        ("plain-no-ns", L("plain") + "\n"),
        ("empty", ""),
        ("only-comments", "# c\n"),
        ("mixed-bad", L("ns-jeb") + "\n" + L("ns-git-only") + "\n"),
    ]
    return .object([
        ("key_line", .object(lines.map { ($0.0, keyLine($0.1)?.json ?? .null) })),
        ("parse_signers", .object(texts.map { ($0.0, parseSigners($0.1).map { .array($0.map { $0.json }) } ?? .null) })),
    ])
}

func newTagsProbe() -> Json {
    var out = Json.object([])
    for (cur, skip) in [("v1.4.0", []), ("v1.4.0", ["v1.6.0"]), ("v1.6.0", []), (nil, []), ("v1.4.0", ["v1.6.0", "v1.5.0"]), ("v1.5.0", ["v1.6.0"])] as [(String?, [String])] {
        let tags = (try? newTags(cur: cur, skip: skip)) ?? []
        out.set("cur=\(cur ?? "None") skip=\(skip.isEmpty ? "-" : skip.joined(separator: ","))", .array(tags.map(Json.string)))
    }
    return out
}

func checkSandboxProbe() -> Json {
    var out = Json.object([("status", checkSandbox("status").map(Json.string) ?? .null), ("install", checkSandbox("install").map(Json.string) ?? .null)])
    setEnvVar("JEB_APP_DIR", "/Applications")
    out.set("app-dir-outside", checkSandbox("follow").map(Json.string) ?? .null)
    return out
}

/// Deviation #2: no INITIAL_VERSION or CC_RE (release-tool values) and no `labels_for dev` (dev mode is gone).
func constantsProbe() -> Json {
    .object([
        ("ALL_LABELS", .array(allLabels.map(Json.string))),
        ("MANIFEST_MAX", .int(manifestMax)),
        ("ROLLBACK_FLOOR", .array([.int(rollbackFloor.0), .int(rollbackFloor.1), .int(rollbackFloor.2)])),
        ("NOTE_GROUPS", .array(noteGroups.map { .array([.string($0.0), .string($0.1)]) })),
        ("CPU_TARGETS", .object(cpuTargets.map { ($0.0, .double($0.1)) })),
        ("RSS_TARGET", .double(rssTarget)),
        ("FP_TARGET", .double(fpTarget)),
        ("PATH", .string(sysPath)),
        ("TAG_RE", .string(tagPattern)),
        ("labels_for", .object([("release", .array(labelsFor("release").map(Json.string)))])),
        ("app_name", .string(appName("v1.5.0"))),
    ])
}

/// cases: {name: [manifest, sig, tag]} -> {name: null | [reason, kind]}.
func verifyManifestProbe(cases: Json) -> Json {
    .object((cases.object ?? []).map { name, c in
        let a = c.array ?? []
        return (name, verifyManifest(a[0].string ?? "", sig: a[1].string ?? "", tag: a[2].string ?? "")?.json ?? .null)
    })
}

/// plugdirs: the removal plan per value, the store and settings paths, norm, info, and the dry-run transcript of the
/// settings removal, register, sync and unregister. The Python's add half (remove=False) is gone with dev mode.
func plugdirsProbe(sb: String) -> Json {
    let mod = sb + "/home/.jeb/current/mod", src = sb + "/home/.jeb/current"
    func repr(_ v: String?) -> String { v.map { "'\($0)'" } ?? "None" }
    var plan = Json.object([])
    for v in [nil, "", mod, "/x/other", "/x/other:" + mod, mod + ":/x/other", mod + "/", "/x/a:/x/b"] as [String?] {
        let (action, new) = planRemoval(v, mod)
        plan.set("value=\(repr(v)) remove=True", .array([.string(action), new.map(Json.string) ?? .null]))
    }
    var out = Json.object([("plan", plan)])
    out.set("store_name", .object(["jeb@jeb", "inline", "a@b@c"].map { ($0, .string(storeName($0))) }))
    out.set("store_dir", .string(storeDir()))
    out.set("store_path", .string(storePath()))
    out.set("settings_path", .string(settingsPath()))
    out.set("backup_dir", .string(backupDir()))
    out.set("norm", .object(["~/x", "/a/b/../c", "rel"].map { ($0, .string(normPath($0))) }))
    let info = pluginInfo()
    out.set("info", .array([info.claude.map(Json.string) ?? .null, info.plugin ?? .null, info.market ?? .null]))
    var said: [String] = []
    let note: (String) -> Void = { said.append($0) }
    for value in [nil, "/x/other", mod, "/x/other:" + mod] as [String?] {
        try? FileManager.default.createDirectory(atPath: (settingsPath() as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let doc: Json = value.map { .object([("env", .object([(pluginDirsKey, .string($0))]))]) } ?? .object([])
        FileManager.default.createFile(atPath: settingsPath(), contents: Data(doc.dumps().utf8))
        said.append("--- settings env value \(repr(value)), remove=True")
        said.append("=> " + removeEntry(mod, dry: true, say: note))
    }
    unlink(settingsPath())
    said.append("--- register dry")
    said.append("=> " + registerPlugin(src, dry: true, say: note))
    said.append("--- register dry with an extra old entry")
    said.append("=> " + registerPlugin(src, dry: true, say: note, extra: ["/x/old"]))
    said.append("--- sync dry")
    said.append("=> " + (syncPlugin(dry: true, say: note) ? "True" : "False"))
    said.append("--- unregister dry (keep farm)")
    unregisterPlugin(purgeFarm: false, dry: true, say: note, source: src)
    said.append("=> None")
    said.append("--- unregister dry (purge farm)")
    unregisterPlugin(purgeFarm: true, dry: true, say: note, source: src)
    said.append("=> None")
    out.set("edit_register_dry_transcript", .array(said.map(Json.string)))
    return out
}
