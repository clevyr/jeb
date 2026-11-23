// Signers: the pinned release signers (JEB_HOME/release-signers, ssh allowed_signers format) and the manifest check
// (desktop/jebctl key_line, parse_signers, pin_signers, widen_signers, pin_hash, adopt_signers, verify_manifest).
// Trust on first install: the shipped desktop/release-signers is copied to the state folder and follow trusts no other
// key; the pin then moves with the signed releases (adopt). Signature checks shell out to ssh-keygen -Y, as the Python
// did; nothing here parses a key. The signerLines constant the standalone launcher pins stays in main.swift until the
// release tool (which checks it) moves to Swift.
import CryptoKit
import Foundation

let manifestMax = 64 << 10                  // the most a manifest or its signature may be (a manifest is under 1 KB)

/// The shipped desktop/release-signers beside this jebctl (REPO_SIGNERS): <bundle>/desktop/release-signers.
func repoSignersPath() -> String { codeDir() + "/release-signers" }

/// The desktop/ folder this jebctl runs from (the Python's CODE: realpath, since jebctl may run through a link).
func codeDir() -> String {
    let exe = pyRealpath(CommandLine.arguments[0].contains("/") ? CommandLine.arguments[0] : (which(CommandLine.arguments[0]) ?? CommandLine.arguments[0]))
    return ((exe as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
}

/// os.path.realpath: symlinks resolved as far as the path exists, the rest kept.
func pyRealpath(_ p: String) -> String {
    let abs = p.hasPrefix("/") ? p : FileManager.default.currentDirectoryPath + "/" + p
    if let r = realpath(abs, nil) { defer { free(r) }; return String(cString: r) }
    let ns = abs as NSString
    let parent = ns.deletingLastPathComponent, last = ns.lastPathComponent
    if parent.isEmpty || parent == abs { return ns.standardizingPath }
    return pyRealpath(parent) + "/" + last
}

/// open(path).read() in text mode: UTF-8 with universal newlines; nil when unreadable.
func readText(_ path: String) -> String? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
}

func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

/// str.split(): fields separated by runs of whitespace.
func fields(_ s: String) -> [String] { s.split(whereSeparator: { $0.isWhitespace }).map(String.init) }

/// str.splitlines() for the line shapes a signers file can have.
func splitLines(_ s: String) -> [String] {
    var lines = s.components(separatedBy: .newlines)
    if lines.last == "" { lines.removeLast() }
    return lines
}

// ---- allowed_signers lines ----

/// One key line: the key blob and, when the line carries a namespaces="..." option, its token index and the names.
struct KeyLine: Equatable {
    var blob: String
    var ns: Namespaces?
    struct Namespaces: Equatable {
        var index: Int
        var names: [String]
    }
    /// The probe's shape: [blob, null] or [blob, [index, [names]]].
    var json: Json { .array([.string(blob), ns.map { .array([.int($0.index), .array($0.names.map(Json.string))]) } ?? .null]) }
}

private func isKeyType(_ s: String) -> Bool { s.hasPrefix("ssh-") || s.hasPrefix("ecdsa-") || s.hasPrefix("sk-") }

/// (blob, namespaces or nil) of an allowed_signers line; nil for a comment, a blank or a line with no key.
func keyLine(_ line: String) -> KeyLine? {
    let t = fields(line)
    guard let first = t.first, !first.hasPrefix("#") else { return nil }
    guard let i = t.indices.first(where: { $0 > 0 && isKeyType(t[$0]) }), i + 1 < t.count else { return nil }
    var ns: KeyLine.Namespaces?
    for k in 1..<i {
        if let m = reMatch(#"^namespaces="([^"]*)"$"#, t[k]) {
            ns = .init(index: k, names: m[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty })
        }
    }
    return KeyLine(blob: t[i + 1], ns: ns)
}

struct Signer: Equatable {
    var principal: String, keyType: String, key: String
    var json: Json { .array([.string(principal), .string(keyType), .string(key)]) }
}

/// The lines of a usable release-signers file as (principal, keytype, key): at least one line, and every line
/// `principal namespaces="..." keytype base64` with jeb-release among its namespaces and no other option. Else nil.
func parseSigners(_ text: String) -> [Signer]? {
    var out: [Signer] = []
    for l in splitLines(text) {
        let t = fields(l)
        guard let first = t.first, !first.hasPrefix("#") else { continue }
        let i = t.indices.first { $0 > 0 && isKeyType(t[$0]) }
        guard let k = keyLine(l), let ns = k.ns, ns.names.contains("jeb-release"), i == 2, t.count == 4,
              reMatch(#"^[A-Za-z0-9+/=]+$"#, t[3]) != nil else { return nil }
        out.append(Signer(principal: t[0], keyType: t[2], key: t[3]))
    }
    return out.isEmpty ? nil : out
}

// ---- the pin ----

/// Trust on first install: copy the shipped release-signers to JEB_HOME unless one is pinned (repin replaces it).
func pinSigners(repin: Bool, from src: String = repoSignersPath()) {
    let pin = pinnedSignersPath
    guard isRegularFile(src) else {
        say("signers: no desktop/release-signers in this clone; " + (FileManager.default.fileExists(atPath: pin) ? "a pinned file is kept" : "updates stay off until one is pinned"))
        return
    }
    if FileManager.default.fileExists(atPath: pin) && !repin {
        detail("signers: \(pin) is already pinned (--repin replaces it)")
        return
    }
    detail("signers: pin \(src) -> \(pin)")
    if dryRun { return }
    makePrivateDir(stateHome)       // a fresh Mac has no HOME yet
    let data = FileManager.default.contents(atPath: src) ?? Data()
    do { try writePrivate(data, to: pin) } catch { die("jebctl: \(error)") }
}

/// A key that is already pinned gets the namespaces src (a shipped desktop/release-signers) lists for it, added to its
/// own, so an old pin signed for `git` also covers `jeb-release`. Never adds a key. True when the file changed.
@discardableResult
func widenSigners(_ src: String) -> Bool {
    guard let srcText = readText(src), let pinText = readText(pinnedSignersPath) else { return false }
    var want: [String: [String]] = [:]
    for l in splitLines(srcText) {
        if let k = keyLine(l), let ns = k.ns { want[k.blob] = ns.names }
    }
    var out: [String] = [], changed = false
    for var l in splitLines(pinText) {
        if let k = keyLine(l), let ns = k.ns, let add = want[k.blob] {
            let names = ns.names + add.filter { !ns.names.contains($0) }
            if names != ns.names {
                var t = fields(l)
                t[ns.index] = "namespaces=\"" + names.joined(separator: ",") + "\""
                l = t.joined(separator: " ")
                changed = true
            }
        }
        out.append(l)
    }
    if changed {
        detail("signers: widened the namespaces in \(pinnedSignersPath)")
        if !dryRun { try? writePrivate(out.joined(separator: "\n") + "\n", to: pinnedSignersPath) }
    }
    return changed
}

/// SHA-256 of the pinned signers file ("" when none).
func pinHash() -> String {
    FileManager.default.contents(atPath: pinnedSignersPath).map(sha256Hex) ?? ""
}

/// The pin follows the signed releases: when tag is newer than the release the pin was last adopted from
/// (rs.signers_from; none yet counts as older), the signers file src of that release replaces the pin (atomic, 0600).
/// Only for a release this process has verified; never at a fresh install. A src that does not parse into valid
/// jeb-release lines is ignored. True when adopted (or already matching).
@discardableResult
func adoptSigners(_ rs: inout Json, tag: String, src: String) -> Bool {
    guard let key = tagKey(tag) else { return false }
    if let cur = rs["signers_from"]?.string, let ck = tagKey(cur), key <= ck { return false }
    guard let text = readText(src) else { return false }
    guard parseSigners(text) != nil else {
        rlog("signers: \(tag)'s release-signers is not usable; the pin stays")
        return false
    }
    rs.set("signers_from", .string(tag))
    if pinHash() == sha256Hex(Data(text.utf8)) {
        rlog("signers: the pin already matches \(tag)'s")
        return true
    }
    rlog("signers: adopting the release-signers of \(tag)")
    if !dryRun {
        makePrivateDir((pinnedSignersPath as NSString).deletingLastPathComponent)
        try? writePrivate(text, to: pinnedSignersPath)
    }
    return true
}

// ---- the manifest ----

/// Why a manifest was refused: the reason and its kind (signature: retried once the pin changes; content: never).
struct Refusal: Equatable {
    var reason: String, kind: String
    var json: Json { .array([.string(reason), .string(kind)]) }
}

/// nil when the manifest is signed for `jeb-release` by a pinned signer and names this tag; else the refusal.
/// pin: the allowed_signers file to trust (default: the pin in the state folder; the standalone install passes the
/// signers built into jebctl, since nothing is pinned yet).
func verifyManifest(_ manifest: String, sig: String, tag: String, pin: String = pinnedSignersPath) -> Refusal? {
    guard isRegularFile(pin) else { return Refusal(reason: "no signers are pinned", kind: "signature") }
    let r = run(["/usr/bin/ssh-keygen", "-Y", "find-principals", "-s", sig, "-f", pin])
    let who = fields(r.out)
    guard r.status == 0, !who.isEmpty else { return Refusal(reason: "the manifest is not signed by a pinned signer", kind: "signature") }
    guard isRegularFile(manifest) else {
        return Refusal(reason: "the manifest signature does not verify for jeb-release: cannot read \(manifest)", kind: "signature")
    }
    var last = RunResult(status: 1, out: "", err: "")
    var good = false
    for p in who {
        last = run(["/usr/bin/ssh-keygen", "-Y", "verify", "-f", pin, "-I", p, "-n", "jeb-release", "-s", sig], stdin: manifest)
        if last.status == 0 { good = true; break }
    }
    guard good else {
        let line = splitLines(last.err.trimmingCharacters(in: .whitespacesAndNewlines)).last ?? "?"
        return Refusal(reason: "the manifest signature does not verify for jeb-release: " + String(line.prefix(150)), kind: "signature")
    }
    guard let doc = Json.load(manifest) else { return Refusal(reason: "the manifest is not valid JSON", kind: "content") }
    guard doc.object != nil, doc["tag"]?.string == tag else {
        let named = doc.object == nil ? "?" : pyStr(doc["tag"])
        return Refusal(reason: "the signed manifest names \(named), not \(tag) (replayed)", kind: "content")
    }
    return nil
}

/// str(value) of a JSON field the way an f-string shows it: None for a missing or null one.
func pyStr(_ v: Json?) -> String {
    switch v {
    case nil, .null?: return "None"
    case let .string(s)?: return s
    case let .bool(b)?: return b ? "True" : "False"
    case let other?: return other.dumps()
    }
}

func isRegularFile(_ p: String) -> Bool {
    var st = stat()
    return stat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
}
