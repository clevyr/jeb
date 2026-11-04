// jebctl: the one command you run. Inside a release bundle (<root>/desktop/bin/jebctl) and as a standalone copy
// it forwards every command to the installed Jeb's Python jebctl (python/bin/python3 -I desktop/jebctl). A standalone
// copy (~/.jeb/bin/jebctl, fetched with curl) also answers `install` itself: the newest release (github.com/<repo>/releases/latest,
// a web redirect: no sign-in, no API), its signature and hashes, the unpack, then the bundle's own install. Foundation and CryptoKit only; desktop/cli/build.sh.
import Foundation
import CryptoKit

let repo = "clevyr/jeb"
// Must equal the jeb-release line in desktop/release-signers (./release checks it) and the one in the jeb-install skill.
let signerLine = "anthony@clevyr.com namespaces=\"jeb-release\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrfSJyAm3dy3vkC1jKbk2YIxJk9BvoThi605ul1gMZC"
let signerWho = "anthony@clevyr.com"

let fm = FileManager.default
let env = ProcessInfo.processInfo.environment
let home = env["HOME"] ?? NSHomeDirectory()
let jebDir = home + "/.jeb"
let current = jebDir + "/current"
let releases = { (b: String) in b.hasSuffix("/") ? String(b.dropLast()) : b }(env["JEB_RELEASE_BASE"] ?? "https://github.com/\(repo)/releases")
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

/// Runs a program. capture: collect stdout and stderr; otherwise they are inherited (the installs).
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

/// Collects one GET: redirects followed (never from https to anything else), the body refused past limit.
final class Grab: NSObject, URLSessionDataDelegate {
    let limit: Int
    var url: URL?, status = 0, data = Data(), why: String?
    let sem = DispatchSemaphore(value: 0)
    init(_ limit: Int) { self.limit = limit }
    func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest q: URLRequest, completionHandler done: @escaping (URLRequest?) -> Void) {
        done(task.currentRequest?.url?.scheme == "https" && q.url?.scheme != "https" ? nil : q)
    }
    func urlSession(_ s: URLSession, dataTask t: URLSessionDataTask, didReceive r: URLResponse, completionHandler done: @escaping (URLSession.ResponseDisposition) -> Void) {
        url = r.url
        status = (r as? HTTPURLResponse)?.statusCode ?? 200      // file:// answers no status
        done(status == 200 ? .allow : .cancel)
    }
    func urlSession(_ s: URLSession, dataTask t: URLSessionDataTask, didReceive d: Data) {
        data.append(d)
        if data.count > limit { why = "larger than \(limit) bytes"; t.cancel() }
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        if why == nil && status != 0 && status != 200 { why = status == 404 ? "not found (HTTP 404)" : "HTTP \(status)" }
        else if why == nil, let e = e { why = e.localizedDescription }
        sem.signal()
    }
}

func session(_ delegate: URLSessionDelegate? = nil) -> URLSession {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = 60; c.timeoutIntervalForResource = 900
    c.httpAdditionalHeaders = ["User-Agent": "jebctl/\(jebctlVersion)"]
    return URLSession(configuration: c, delegate: delegate, delegateQueue: nil)
}

/// GET url, redirects followed: (final URL, body, nil) or (final URL or nil, nil, reason); non-HTTP (file://) responses pass; body refused past limit.
func get(_ url: String, limit: Int) -> (URL?, Data?, String?) {
    guard let u = URL(string: url) else { return (nil, nil, "bad URL") }
    let g = Grab(limit), s = session(g)
    s.dataTask(with: u).resume()
    g.sem.wait()
    s.finishTasksAndInvalidate()
    return g.why == nil ? (g.url, g.data, nil) : (g.url, nil, g.why)
}

/// url into dest: downloadTask, HTTP 200 only, expectedContentLength (when known) and the file's size must equal size (nil: at most 1 MB),
/// URLSession's temp file moved to dest + ".part", renamed to dest last. nil or the reason ("not found (HTTP 404)", "HTTP n", localizedDescription).
func save(_ url: String, to dest: String, size: Int?) -> String? {
    guard let u = URL(string: url) else { return "bad URL" }
    var out: String? = "no answer"
    let sem = DispatchSemaphore(value: 0)
    session().downloadTask(with: u) { tmp, resp, err in
        defer { sem.signal() }
        if let err = err { out = err.localizedDescription; return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
        guard code == 200, let tmp = tmp else { out = code == 404 ? "not found (HTTP 404)" : "HTTP \(code)"; return }
        let have = (try? fm.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? -1
        let n = resp?.expectedContentLength ?? -1
        guard have >= 0, size.map({ have == $0 && (n < 0 || n == Int64($0)) }) ?? (have <= 1 << 20) else { out = "the size does not match what was expected"; return }
        let part = dest + ".part"
        try? fm.removeItem(atPath: part)
        do { try fm.moveItem(atPath: tmp.path, toPath: part); try? fm.removeItem(atPath: dest); try fm.moveItem(atPath: part, toPath: dest); out = nil }
        catch { try? fm.removeItem(atPath: part); out = "could not save the download" }
    }.resume()
    sem.wait()
    return out
}

/// The newest published tag: the final URL of <releases>/latest ends /tag/<tag>; a test server answers the bare tag (body <= 256 B).
func latestTag() -> (String?, String?) {
    let (u, body, why) = get(releases + "/latest", limit: 256)
    let ok = { (t: String) in t.range(of: #"^v\d+\.\d+\.\d+$"#, options: .regularExpression) != nil }
    if let t = u?.path.components(separatedBy: "/tag/").last, u?.path.contains("/tag/") == true, ok(t) { return (t, nil) }
    if let b = body, let t = String(data: b, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), ok(t) { return (t, nil) }
    return (nil, why ?? "no published release")
}

/// The signed manifest (checked against the pinned signer) and what it says about this Mac's zip.
func verifyManifest(_ dir: String, tag: String, arch: String) -> (sha: String, size: Int) {
    let man = "\(dir)/Jeb-\(tag)-manifest.json", sig = man + ".sig"
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
    return (want, size)
}

func checkZip(_ zip: String, sha: String, size: Int) {
    let have = (try? fm.attributesOfItem(atPath: zip)[.size] as? Int) ?? -1
    guard sha256(zip) == sha, have == size else { die("jebctl: the download does not match the signed manifest; refusing it.") }
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
    let (found, why) = env["JEB_RELEASE_TAG"].map { ($0, nil) } ?? latestTag()      // JEB_RELEASE_TAG: tests only; the signature still binds the tag
    guard let tag = found else {
        if why?.contains("404") == true { die("jebctl: \(releases) has no published release (HTTP 404; is the repository public?)") }
        die("jebctl: could not reach GitHub (\(why ?? "?")); check the network and run jebctl install again")
    }
    step("newest release: \(tag)")
    if dry {
        step("would download its manifest, signature and \(arch) zip from \(releases)/download/\(tag)/,")
        step("verify the signature and hashes, unpack into \(jebDir)/versions/<tag> and run the bundle's own install")
        say("Dry run only; nothing was changed.")
        return 0
    }
    let tmp = tempDir()
    defer { try? fm.removeItem(atPath: tmp) }
    let man = "Jeb-\(tag)-manifest.json", zname = "Jeb-\(tag)-macos-\(arch).zip"
    for n in [man, man + ".sig"] {
        if let why = save("\(releases)/download/\(tag)/\(n)", to: tmp + "/" + n, size: nil) { die("jebctl: could not download \(n) (\(why)).") }
    }
    let want = verifyManifest(tmp, tag: tag, arch: arch)
    if let why = save("\(releases)/download/\(tag)/\(zname)", to: tmp + "/" + zname, size: want.size) { die("jebctl: could not download \(zname) (\(why)).") }
    step("downloaded \(zname)")
    checkZip(tmp + "/" + zname, sha: want.sha, size: want.size)
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
