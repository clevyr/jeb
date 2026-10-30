// jebctl: the one command a teammate runs. Inside a release bundle (<root>/desktop/bin/jebctl) and as a standalone copy
// it forwards every command to the installed Jeb's Python jebctl (python/bin/python3 -I desktop/jebctl). A standalone
// copy (~/.jeb/bin/jebctl, fetched with gh) also answers `install` itself: gh, GitHub sign-in, the newest release,
// its signature and hashes, the unpack, then the bundle's own install. Foundation and CryptoKit only; desktop/cli/build.sh.
import Foundation
import CryptoKit

let repo = "clevyr/jeb"
let ghVersion = "2.102.0"
let ghSHA = ["arm64": "da922c20d1792e5b2cbf375593d7a658acf034c12c84e007e71c76ef959c337e",
             "amd64": "b245f24eb2bf5f75b426b4c26da3651a107f8d5b6f4fddfbfccc5679041378b3"]
// Must equal the jeb-release line in desktop/release-signers (./release checks it) and the one in the jeb-install skill.
let signerLine = "anthony@clevyr.com namespaces=\"jeb-release\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrfSJyAm3dy3vkC1jKbk2YIxJk9BvoThi605ul1gMZC"
let signerWho = "anthony@clevyr.com"

let fm = FileManager.default
let env = ProcessInfo.processInfo.environment
let home = env["HOME"] ?? NSHomeDirectory()
let jebDir = home + "/.jeb"
let toolsDir = env["JEB_TOOLS_DIR"] ?? jebDir + "/bin"
let current = jebDir + "/current"
let usage = """
jebctl: manage Jeb on this Mac.
  jebctl install [--dry-run] [--no-agents] [--verbose]   set Jeb up (or update it when it is installed)
  jebctl update | doctor | status | uninstall ...         run against the installed Jeb
  jebctl --version
Jeb is not installed yet; run: jebctl install
"""

func say(_ s: String) { print(s); fflush(stdout) }
func die(_ s: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    exit(code)
}

func realExecutable() -> String {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buf = [CChar](repeating: 0, count: Int(size))
    _NSGetExecutablePath(&buf, &size)
    let p = String(cString: buf)
    if let r = realpath(p, nil) { defer { free(r) }; return String(cString: r) }
    return p
}

func isFile(_ p: String) -> Bool { fm.isExecutableFile(atPath: p) }
func exists(_ p: String) -> Bool { fm.fileExists(atPath: p) }

/// (python, jebctl script) of a Jeb tree rooted at root, when both are there.
func jebAt(_ root: String) -> (String, String)? {
    let py = root + "/python/bin/python3", script = root + "/desktop/jebctl"
    return isFile(py) && exists(script) ? (py, script) : nil
}

let exe = realExecutable()
// <root>/desktop/bin/jebctl: root is two levels above the folder holding the binary
let ownRoot = URL(fileURLWithPath: exe).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
let inBundle = jebAt(ownRoot) != nil

func execForward(_ python: String, _ script: String, _ args: [String]) -> Never {
    let argv = [python, "-I", script] + args
    var cargs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
    cargs.append(nil)
    execv(python, &cargs)
    die("jebctl: could not run \(python): \(String(cString: strerror(errno)))")
}

struct Result { var status: Int32; var out: String; var err: String }

/// Runs a program. capture: collect stdout and stderr; otherwise they are inherited (gh login, the installs).
/// stdin: a file to feed it.
@discardableResult
func run(_ path: String, _ args: [String], capture: Bool = true, stdin: String? = nil) -> Result {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let o = Pipe(), e = Pipe()
    if capture { p.standardOutput = o; p.standardError = e }
    if let s = stdin { p.standardInput = FileHandle(forReadingAtPath: s) }
    do { try p.run() } catch { return Result(status: 127, out: "", err: "\(error)") }
    var od = Data(), ed = Data()
    if capture {
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { ed = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        od = o.fileHandleForReading.readDataToEndOfFile()
        g.wait()
    }
    p.waitUntilExit()
    return Result(status: p.terminationStatus, out: String(decoding: od, as: UTF8.self), err: String(decoding: ed, as: UTF8.self))
}

func sha256(_ path: String) -> String? {
    guard let f = FileHandle(forReadingAtPath: path) else { return nil }
    defer { f.closeFile() }
    var h = SHA256()
    while true {
        let d = f.readData(ofLength: 1 << 20)
        if d.isEmpty { break }
        h.update(data: d)
    }
    return h.finalize().map { String(format: "%02x", $0) }.joined()
}

func hostArch() -> String {   // by the hardware: a Rosetta shell still reports x86_64 for itself
    let r = run("/usr/sbin/sysctl", ["-n", "hw.optional.arm64"])
    return r.status == 0 && r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "1" ? "arm64" : "x86_64"
}

func tempDir() -> String {
    let d = NSTemporaryDirectory() + "jebctl-" + UUID().uuidString
    try? fm.createDirectory(atPath: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return d
}

// ---- install ----

func step(_ s: String) { say("  " + s) }

func findGH() -> String? {
    [toolsDir + "/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: isFile)
}

func download(_ url: String, to dest: String) -> String? {
    guard let u = URL(string: url) else { return "bad URL" }
    var req = URLRequest(url: u)
    req.timeoutInterval = 120
    var out: String? = "no answer"
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err { out = err.localizedDescription }
        else if let h = resp as? HTTPURLResponse, h.statusCode != 200 { out = "HTTP \(h.statusCode)" }
        else if let d = data, (try? d.write(to: URL(fileURLWithPath: dest))) != nil { out = nil }
        else { out = "could not save the download" }
        sem.signal()
    }.resume()
    sem.wait()
    return out
}

/// gh by full path; downloads the pinned GitHub CLI into the tools folder when none is installed.
func ensureGH(dry: Bool) -> String {
    if let g = findGH() { step("GitHub CLI: \(g)"); return g }
    let arch = hostArch() == "arm64" ? "arm64" : "amd64"
    let name = "gh_\(ghVersion)_macOS_\(arch).zip"
    if dry { step("GitHub CLI: would download \(name) into \(toolsDir)"); return toolsDir + "/gh" }
    let tmp = tempDir()
    defer { try? fm.removeItem(atPath: tmp) }
    let zip = tmp + "/" + name
    if let why = download("https://github.com/cli/cli/releases/download/v\(ghVersion)/\(name)", to: zip) {
        die("jebctl: could not download the GitHub CLI (\(why)). Check the network and run again.")
    }
    guard sha256(zip) == ghSHA[arch] else { die("jebctl: the GitHub CLI download does not match its pinned SHA-256; refusing it.") }
    let x = tmp + "/x"
    guard run("/usr/bin/ditto", ["-x", "-k", zip, x]).status == 0,
          let en = fm.enumerator(atPath: x),
          let rel = en.compactMap({ $0 as? String }).first(where: { $0.hasSuffix("/bin/gh") || $0 == "bin/gh" }) else {
        die("jebctl: could not unpack the GitHub CLI.")
    }
    try? fm.createDirectory(atPath: toolsDir, withIntermediateDirectories: true)
    let dest = toolsDir + "/gh"
    try? fm.removeItem(atPath: dest)
    do { try fm.copyItem(atPath: x + "/" + rel, toPath: dest) } catch { die("jebctl: could not place gh in \(toolsDir): \(error.localizedDescription)") }
    chmod(dest, 0o755)
    step("GitHub CLI \(ghVersion): installed at \(dest) (SHA-256 checked)")
    return dest
}

func ensureSignedIn(_ gh: String, dry: Bool) {
    if dry && !isFile(gh) { step("GitHub sign-in: would check, and sign in through the browser if needed"); return }
    if run(gh, ["auth", "status"]).status == 0 { step("GitHub: signed in"); return }
    if dry { step("GitHub: not signed in; would run gh auth login --web"); return }
    step("GitHub: sign in with the code below (a browser window opens)")
    run(gh, ["auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web"], capture: false)
    if run(gh, ["auth", "status"]).status != 0 { die("jebctl: GitHub sign-in did not finish; run jebctl install again.") }
    step("GitHub: signed in")
}

func verifyRelease(_ dir: String, tag: String, arch: String) {
    let man = "\(dir)/Jeb-\(tag)-manifest.json", sig = man + ".sig", zip = "\(dir)/Jeb-\(tag)-macos-\(arch).zip"
    let signers = dir + "/signers"
    try? (signerLine + "\n").write(toFile: signers, atomically: true, encoding: .utf8)
    let v = run("/usr/bin/ssh-keygen", ["-Y", "verify", "-f", signers, "-I", signerWho, "-n", "jeb-release", "-s", sig], stdin: man)
    guard v.status == 0, v.out.contains("Good") else { die("jebctl: the release's signature does not verify against the pinned signer; refusing it.") }
    step("signature: Good (pinned signer)")
    guard let data = fm.contents(atPath: man),
          let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          doc["tag"] as? String == tag,
          let b = (doc["bundles"] as? [String: Any])?[arch] as? [String: Any],
          let want = b["sha256"] as? String, let size = b["size"] as? Int else { die("jebctl: the manifest is malformed or names another tag; refusing it.") }
    let have = (try? fm.attributesOfItem(atPath: zip)[.size] as? Int) ?? -1
    guard sha256(zip) == want, have == size else { die("jebctl: the download does not match the signed manifest; refusing it.") }
    step("sha256 and size: match the manifest")
}

func unpack(zip: String, tag: String) -> String {
    let dest = jebDir + "/versions/" + tag
    if exists(dest + "/bundle.json") && isFile(dest + "/python/bin/python3") { step("unpack: \(dest) is already there"); return dest }
    let part = jebDir + "/versions/.\(tag).part"
    try? fm.removeItem(atPath: part)
    try? fm.removeItem(atPath: dest)
    try? fm.createDirectory(atPath: jebDir + "/versions", withIntermediateDirectories: true)
    guard run("/usr/bin/ditto", ["-x", "-k", zip, part]).status == 0 else { try? fm.removeItem(atPath: part); die("jebctl: could not unpack the release.") }
    do { try fm.moveItem(atPath: part, toPath: dest) } catch { die("jebctl: could not place \(dest): \(error.localizedDescription)") }
    step("unpack: \(dest)")
    return dest
}

func install(_ args: [String]) -> Int32 {
    let known = ["--dry-run", "--no-agents", "--verbose"]
    if let bad = args.first(where: { !known.contains($0) }) { say("jebctl install: unknown option \(bad)\n" + usage); return 2 }
    let dry = args.contains("--dry-run")
    // a Jeb that is already installed updates itself
    if let (py, script) = jebAt(current) {
        say("Jeb is installed: updating it\(dry ? " (dry run)" : "")")
        if dry { step("would run jebctl update, then jebctl doctor"); return 0 }
        let rc = run(py, ["-I", script, "update"], capture: false).status
        run(py, ["-I", script, "doctor"], capture: false)
        return rc
    }
    // an older git-clone install converts itself through its own `follow`
    if let clone = [jebDir + "/repo", home + "/jeb"].first(where: { exists($0 + "/desktop/jebctl") }) {
        say("Jeb is installed as a git clone (\(clone)): converting it\(dry ? " (dry run)" : "")")
        if dry { step("would run /usr/bin/python3 -I \(clone)/desktop/jebctl follow (up to twice)"); return 0 }
        for _ in 0..<2 where !exists(current) {
            run("/usr/bin/python3", ["-I", clone + "/desktop/jebctl", "follow"], capture: false)
        }
        guard let (py, script) = jebAt(current) else {
            say("jebctl: the clone did not convert; run jebctl doctor, or ask Claude to repair Jeb.")
            return 1
        }
        run(py, ["-I", script, "doctor"], capture: false)
        return 0
    }
    say("Installing Jeb\(dry ? " (dry run)" : "")")
    let arch = hostArch()
    step("architecture: \(arch)")
    let gh = ensureGH(dry: dry)
    ensureSignedIn(gh, dry: dry)
    if dry {
        step("would find the newest release of \(repo), download its manifest, signature and \(arch) zip,")
        step("verify the signature and hashes, unpack into \(jebDir)/versions/<tag> and run the bundle's own install")
        say("Dry run only; nothing was changed.")
        return 0
    }
    let l = run(gh, ["release", "list", "-R", repo, "--exclude-drafts", "--exclude-pre-releases", "--limit", "1", "--json", "tagName", "--jq", ".[0].tagName"])
    let tag = l.out.trimmingCharacters(in: .whitespacesAndNewlines)
    guard l.status == 0, tag.range(of: #"^v\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
        die("jebctl: could not read the releases of \(repo); your GitHub account needs access to it.")
    }
    step("newest release: \(tag)")
    let tmp = tempDir()
    defer { try? fm.removeItem(atPath: tmp) }
    let man = "Jeb-\(tag)-manifest.json", zname = "Jeb-\(tag)-macos-\(arch).zip"
    let d = run(gh, ["release", "download", tag, "-R", repo, "-p", man, "-p", man + ".sig", "-p", zname, "-D", tmp])
    guard d.status == 0 else { die("jebctl: the download failed: \((d.err.split(separator: "\n").last).map(String.init) ?? "?")") }
    step("downloaded \(zname)")
    verifyRelease(tmp, tag: tag, arch: arch)
    let ver = unpack(zip: tmp + "/" + zname, tag: tag)
    step("running the bundle's install")
    return run(ver + "/python/bin/python3", ["-I", ver + "/install"] + args, capture: false).status
}

// ---- main ----

let argv = Array(CommandLine.arguments.dropFirst())
if argv == ["--version"] { say("jebctl \(jebctlVersion)"); exit(0) }

if !inBundle && argv.first == "install" {
    let rc = install(Array(argv.dropFirst()))
    exit(rc)
}

if let (py, script) = jebAt(ownRoot) ?? jebAt(current) { execForward(py, script, argv) }
if argv.isEmpty || argv == ["--help"] || argv == ["-h"] { say(usage); exit(argv.isEmpty ? 1 : 0) }
die("Jeb is not installed; run: jebctl install")
