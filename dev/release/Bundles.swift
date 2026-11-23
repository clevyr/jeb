// Bundles: Jeb-<tag>-macos-<arch>.zip (the tree, the prebuilt app and the native jebctl; bundle.json schema 2) and the
// signed manifest (./release bundle, and the end of a release).
import Foundation

/// What a bundle copies from the repo, beside app/, desktop/bin/jebctl and bundle.json (the fixtures: what the gates of
/// an update render; the skills: the doctor guide the README points at; .claude-plugin: the marketplace Claude Code
/// installs the mod from).
let tree = ["install", "uninstall", "LICENSE", "desktop/release-signers", "desktop/src/fixtures", "mod", ".claude-plugin", ".claude/skills"]
/// Globs under the bundle root that are dropped from the tree: the art sources and the band's pictures.
let prune = ["mod/art", "desktop/src/fixtures/band-out.txt", "desktop/src/fixtures/compare*.txt"]
/// What every bundle must hold, or no zip is made (the smoke gate of `jebctl apply` reads the manifest, the gates the art).
let required = ["install", "desktop/bin/jebctl", "desktop/release-signers", "desktop/src/fixtures/smoke.json", "mod", "mod/hooks/pixel-art.ts", ".claude-plugin/marketplace.json", "app/JebDesktop", "app/detect", "app/png2raw"]

private func strip(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

private func sha256(of path: String) -> String { sha256Hex(FileManager.default.contents(atPath: path) ?? Data()) }

private func size(of path: String) -> Int {
    var st = stat()
    return stat(path, &st) == 0 ? Int(st.st_size) : 0
}

/// The paths under root that a glob(3) pattern names.
private func globbed(_ root: String, _ pattern: String) -> [String] {
    var g = glob_t()
    defer { globfree(&g) }
    guard glob(root + "/" + pattern, 0, nil, &g) == 0 else { return [] }
    return (0..<Int(g.gl_pathc)).compactMap { g.gl_pathv[$0].map { String(cString: $0) } }
}

/// The repo files a bundle carries, at dest: `git archive ref` (a release), or the working tree's tracked and
/// unignored files; then the prune.
private func putTree(_ ref: String, _ dest: String, fromTree: Bool) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
    if fromTree {
        let files = git(["ls-files", "-co", "--exclude-standard", "--"] + tree).out.components(separatedBy: "\n")
        for f in files.sorted() where !f.isEmpty && isRegularFile(clone + "/" + f) {
            try? fm.createDirectory(atPath: (dest + "/" + f as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            do { try fm.copyItem(atPath: clone + "/" + f, toPath: dest + "/" + f) } catch { fail("could not copy \(f) into the bundle: \(error.localizedDescription)") }
        }
    } else {
        let tar = dest + ".tar"
        defer { unlink(tar) }
        if run([tool("git"), "-C", clone, "archive", "-o", tar, ref, "--"] + tree, capture: false).status != 0 { fail("git archive \(ref) failed") }
        if run([tool("tar"), "-x", "-C", dest, "-f", tar], capture: false).status != 0 { fail("could not unpack the git archive") }
    }
    for pattern in prune {
        for p in globbed(dest, pattern) { try? fm.removeItem(atPath: p) }
    }
}

/// True when sig signs manifest for `jeb-release` by a key in signers.
func signedBy(_ manifest: String, _ sig: String, signers: String) -> Bool {
    let r = run([tool("ssh-keygen"), "-Y", "find-principals", "-s", sig, "-f", signers])
    for who in fields(r.out) where run([tool("ssh-keygen"), "-Y", "verify", "-f", signers, "-I", who, "-n", "jeb-release", "-s", sig], stdin: manifest).status == 0 {
        return true
    }
    return false
}

/// time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) at the clock's time.
private func utcStamp() -> String {
    var secs = time_t(Clock.now.rounded(.down))
    var tm = tm()
    gmtime_r(&secs, &tm)
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", Int(tm.tm_year) + 1900, Int(tm.tm_mon) + 1, Int(tm.tm_mday), Int(tm.tm_hour), Int(tm.tm_min), Int(tm.tm_sec))
}

private func writeDoc(_ doc: Json, _ path: String) {
    if (try? (doc.dumps(indent: 2) + "\n").write(toFile: path, atomically: false, encoding: .utf8)) == nil { fail("could not write \(path)") }
}

/// Build Jeb-<tag>-macos-{arm64,x86_64}.zip plus the signed manifest and jebctl-macos in out; returns the paths to
/// upload (manifest, signature, zips, jebctl). appDir holds JebDesktop, detect, png2raw and the universal jebctl, which
/// each bundle carries as desktop/bin/jebctl. signers overrides the bundle's desktop/release-signers (tests: a
/// throwaway key). Self-verifies the signature against the bundle's own release-signers, the file an install pins.
func makeBundles(tag: String, ref: String, appDir: String, out: String, key: String, signers: String? = nil, fromTree: Bool = false) -> [String] {
    let fm = FileManager.default
    let version = String(tag.drop { $0 == "v" })
    let head = strip(git("rev-parse", fromTree ? "HEAD" : ref).out)
    let commit = head.isEmpty ? String(repeating: "0", count: 40) : head
    try? fm.createDirectory(atPath: out, withIntermediateDirectories: true)
    var tmpl = Array((((envVar("TMPDIR") ?? NSTemporaryDirectory()) as NSString).appendingPathComponent("jeb-bundle-XXXXXX")).utf8CString)
    guard mkdtemp(&tmpl) != nil else { fail("could not make a work folder for the bundles") }
    let work = String(cString: tmpl)
    scratch.append(work)
    defer { cleanScratch(work) }
    var bundles: [(String, Json)] = []
    var zips: [String] = []
    for arch in ["arm64", "x86_64"] {
        say("bundle \(arch):")
        let root = work + "/" + arch
        putTree(ref, root, fromTree: fromTree)
        do {
            if let s = signers {
                try? fm.removeItem(atPath: root + "/desktop/release-signers")
                try fm.createDirectory(atPath: root + "/desktop", withIntermediateDirectories: true)
                try fm.copyItem(atPath: s, toPath: root + "/desktop/release-signers")
            }
            try fm.copyItem(atPath: appDir, toPath: root + "/app")
            if !isRegularFile(root + "/app/jebctl") { fail("the app folder \(appDir) has no jebctl (the native build from desktop/cli); no bundle") }
            try fm.createDirectory(atPath: root + "/desktop/bin", withIntermediateDirectories: true)
            try fm.moveItem(atPath: root + "/app/jebctl", toPath: root + "/desktop/bin/jebctl")
        } catch { fail("could not lay out the \(arch) bundle: \(error.localizedDescription)") }
        writeDoc(.object([("schema", .int(2)), ("repo", .string(repo)), ("tag", .string(tag)), ("version", .string(version)), ("commit", .string(commit)), ("arch", .string(arch))]),
                 root + "/bundle.json")
        for need in required where !fm.fileExists(atPath: root + "/" + need) { fail("the \(arch) bundle lacks \(need)") }
        let name = "Jeb-\(tag)-macos-\(arch).zip"
        let zp = out + "/" + name
        unlink(zp)
        if run([tool("ditto"), "-c", "-k", "--norsrc", "--noextattr", root, zp], capture: false).status != 0 { fail("ditto could not make \(name)") }
        let sum = sha256(of: zp), bytes = size(of: zp)
        bundles.append((arch, .object([("name", .string(name)), ("sha256", .string(sum)), ("size", .int(bytes))])))
        zips.append(zp)
        say("  \(name): \(bytes / 1024) KB, sha256 \(sum.prefix(16))")
    }
    let ctl = out + "/jebctl-macos"
    try? fm.removeItem(atPath: ctl)
    if (try? fm.copyItem(atPath: appDir + "/jebctl", toPath: ctl)) == nil { fail("could not copy the staged jebctl to \(ctl)") }
    chmod(ctl, 0o755)
    if run([tool("codesign"), "--verify", ctl]).status != 0 { fail("the staged jebctl fails codesign --verify") }
    let ctlSum = sha256(of: ctl), ctlBytes = size(of: ctl)
    say("  jebctl-macos: \(ctlBytes / 1024) KB, sha256 \(ctlSum.prefix(16))")
    let man = out + "/Jeb-\(tag)-manifest.json"
    writeDoc(.object([("schema", .int(1)), ("repo", .string(repo)), ("tag", .string(tag)), ("version", .string(version)), ("commit", .string(commit)), ("created", .string(utcStamp())),
                      ("bundles", .object(bundles)), ("jebctl", .object([("name", .string("jebctl-macos")), ("sha256", .string(ctlSum)), ("size", .int(ctlBytes))]))]), man)
    let sig = man + ".sig"
    unlink(sig)
    if run([tool("ssh-keygen"), "-Y", "sign", "-f", key, "-n", "jeb-release", man], capture: false).status != 0 { fail("ssh-keygen could not sign the manifest") }
    if !signedBy(man, sig, signers: work + "/arm64/desktop/release-signers") {
        fail("the manifest signature does not verify against the bundle's own desktop/release-signers (namespace jeb-release); "
             + "is the signing key listed there with namespaces including jeb-release? (./release setup shows it)")
    }
    say("manifest signed and verified against the bundle's release-signers: \(man)")
    return [man, sig] + zips + [ctl]
}

/// ./release bundle --tag vX.Y.Z --out DIR [--ref REF] [--from-tree] [--app DIR] [--key K] [--signers F]
func bundleCmd(_ argv: [String]) -> Int32 {
    var opts: [String: String] = [:]
    var fromTree = false
    var i = 0
    while i < argv.count {
        let a = argv[i]
        if a == "--from-tree" {
            fromTree = true
            i += 1
        } else if ["--tag", "--out", "--ref", "--app", "--key", "--signers"].contains(a) && i + 1 < argv.count {
            opts[String(a.dropFirst(2))] = argv[i + 1]
            i += 2
        } else {
            say(usageText)
            return 2
        }
    }
    guard let tag = opts["tag"], let out = opts["out"], let m = reMatch(#"^v\d+\.\d+\.\d+$"#, tag), m[0] == tag else {
        say(usageText)
        return 2
    }
    let app = opts["app"] ?? gitPath("jeb-release-\(tag)") + "/stage"
    var isDir: ObjCBool = false
    if !FileManager.default.fileExists(atPath: app, isDirectory: &isDir) || !isDir.boolValue {
        fail("\(app) is not a folder (the app folder holds JebDesktop, detect, png2raw and jebctl)")
    }
    let paths = makeBundles(tag: tag, ref: opts["ref"] ?? "HEAD", appDir: app, out: out, key: opts["key"] ?? signingKey(), signers: opts["signers"], fromTree: fromTree)
    say("made:\n" + paths.map { "  " + $0 }.joined(separator: "\n"))
    return 0
}
