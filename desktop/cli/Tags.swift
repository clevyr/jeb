// Tags: release tags and what release-state.json remembers about them. A release tag is
// SemVer with a v (v1.2.0); pre-release tags are never followed. Tags rejected for their signature get another look
// once the pin changes; every other rejection sticks until retry-update clears it.
import Foundation

/// SemVer releases; pre-release tags are never followed (TAG_RE; the anchored form is Fetch.swift's isReleaseTag).
let tagPattern = #"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"#

/// Under this a rollback is refused: older releases are the Python-era ones, signed by a retired key.
let rollbackFloor = (1, 7, 0)

typealias TagKey = (Int, Int, Int)

/// (major, minor, patch) of a release tag, the sort key; nil for anything else.
func tagKey(_ t: String) -> TagKey? {
    // m[0] == t: fullmatch ($ alone also matches before a trailing newline)
    guard let m = reMatch("^" + tagPattern + "$", t), m[0] == t, let a = Int(m[1]), let b = Int(m[2]), let c = Int(m[3]) else { return nil }
    return (a, b, c)
}

func tagKeyJson(_ t: String) -> Json {
    tagKey(t).map { .array([.int($0.0), .int($0.1), .int($0.2)]) } ?? .null
}

/// Oldest first, by tagKey.
func sortedTags(_ tags: [String]) -> [String] {
    tags.compactMap { t in tagKey(t).map { (t, $0) } }.sorted { $0.1 < $1.1 }.map { $0.0 }
}

/// A git runner for the dev loop: the arguments after `git` (the caller pins -C), the result.
typealias GitRunner = ([String]) -> RunResult

/// Sorted oldest first: the v* release tags (of `git tag --list`, or --points-at HEAD with args). Dev loop only.
func releaseTags(_ args: [String] = [], git: GitRunner) -> [String] {
    sortedTags(fields(git(["tag", "--list", "v*"] + args).out))
}

/// The release tags at HEAD.
func headTags(git: GitRunner) -> [String] { releaseTags(["--points-at", "HEAD"], git: git) }

/// owner/name of the GitHub repo releases come from: the bundle's, else clevyr/jeb.
func releaseRepo() -> String {
    if let r = codeBundle()?["repo"]?.string, !r.isEmpty { return r }
    return "clevyr/jeb"
}

/// Tags newer than cur (nil: any) and not in skip, newest first, without the API: the latest release; only when that
/// one is in skip, the older ones from the releases feed (a bad release cannot block the real ones). Throws FetchError.
func newTags(cur: String?, skip: [String]) throws -> [String] {
    let base = releaseBase(releaseRepo())
    let curKey = cur.flatMap(tagKey)
    func ok(_ t: String) -> Bool {
        guard let k = tagKey(t) else { return false }
        if let c = curKey, !(k > c) { return false }
        return !skip.contains(t)
    }
    let latest = try latestTag(base)
    return skip.contains(latest) ? feedTags(base).filter(ok) : (ok(latest) ? [latest] : [])
}

// ---- release-state.json: failed tags ----

/// rs.failed as strings (a missing or null field is empty).
func failedList(_ rs: Json) -> [String] {
    rs["failed"]?.array?.compactMap { $0.string } ?? []
}

/// rs.failed minus the tags rejected only for their signature while a different pin was in place: those get another look.
func failedSkip(_ rs: Json) -> [String] {
    let pin = pinHash()
    let why = rs["failed_why"].flatMap { $0.object != nil ? $0 : nil } ?? .object([])
    return failedList(rs).filter { t in
        guard let w = why[t], w.object != nil else { return true }
        return !(w["why"]?.string == "signature" && w["pin"]?.string != pin)
    }
}

func markFailed(_ rs: inout Json, _ tag: String, kind: String) {
    var failed = rs["failed"]?.array ?? []
    if !failed.contains(.string(tag)) { failed.append(.string(tag)) }
    rs.set("failed", .array(failed))
    var why = rs["failed_why"].flatMap { $0.object != nil ? $0 : nil } ?? .object([])
    why.set(tag, .object([("why", .string(kind)), ("pin", .string(pinHash()))]))
    rs.set("failed_why", why)
}

func clearFailed(_ rs: inout Json, _ tag: String) {
    if var failed = rs["failed"]?.array, let i = failed.firstIndex(of: .string(tag)) {
        failed.remove(at: i)
        rs.set("failed", .array(failed))
    }
    if var why = rs["failed_why"], why.object != nil, why[tag] != nil {
        why.remove(tag)
        rs.set("failed_why", why)
    }
}

// ---- what is installed ----

/// The bundle this jebctl runs from (BUNDLE: <bundle>/bundle.json), nil in a source checkout or the dev build.
func codeBundle() -> Json? { readBundle((codeDir() as NSString).deletingLastPathComponent) }

/// ~/.jeb/current's bundle, else the one this jebctl runs from (an empty bundle.json object counts as none, as Python's `or` did).
func installedBundle() -> Json? {
    if let b = readBundle(currentDir()), b.object?.isEmpty == false { return b }
    return codeBundle()
}

/// The tag of ~/.jeb/current, else of the bundle this jebctl runs from.
func installedTag() -> String? { installedBundle()?["tag"]?.string }

/// rs.installed gains {tag, stamp (the updater's), at}; the last 20 are kept.
func recordInstalled(_ rs: inout Json, _ tag: String) {
    var list = rs["installed"]?.array ?? []
    list.append(.object([("tag", .string(tag)), ("stamp", loadUState()["stamp"] ?? .null), ("at", .int(Clock.epoch))]))
    rs.set("installed", .array(Array(list.suffix(20))))
}
