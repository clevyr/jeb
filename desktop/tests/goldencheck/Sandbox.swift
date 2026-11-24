// Sandbox.swift: the fixed inputs (keys, stub, fake tools, clock), the sandbox class of drive.py (one HOME with every path override
// under it, a file:// release tree, bundle trees, signed releases) and the process runner that drives the Swift tools.
import Foundation

let NOW = 1780000000
let PID = 4242
let FAKE_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
// the files of an installed schema 1 bundle (v1.6.0 and earlier) that the Swift jebctl never reads: placeholders keep the shape
let LEGACY_FILES = ["jebctl", "jebhome.py", "plugdirs.py", "updater.py", "watchdog.py"]
let BASE_ENV = ["TZ": "America/Chicago", "LC_ALL": "C", "LANG": "C"]
let pubOrder = ["old", "new", "other"]

struct Config {
    let root: String        // the repo
    let tmp: String         // T: everything lives under it
    let arch: String
    let out: String         // where the produced goldens go
    let gold: String        // desktop/tests/golden
    let only: String
    let update: Bool
    let render: Bool
    let realHome: String
    var desk: String { root + "/desktop" }
    var stub: String { tmp + "/stub" }
    var keys: [String: String] = [:]
    var pub: [String: String] = [:]
    var head = ""
    var headRule: Rule? = nil
    // the Swift binaries (check.sh builds them and passes the paths)
    var swiftJebctl: String { ProcessInfo.processInfo.environment["JEB_CHECK_JEBCTL"] ?? root + "/desktop/cli/jebctl" }
    var swiftRelease: String { ProcessInfo.processInfo.environment["JEB_CHECK_RELEASE"] ?? root + "/dev/release/release" }
    var swiftGates: String { ProcessInfo.processInfo.environment["JEB_CHECK_GATES"] ?? root + "/desktop/gates/jebgates" }
}

var config: Config!

func line(_ who: String, _ key: String, ns: String = "git,jeb-release") -> String {
    "\(who) namespaces=\"\(ns)\" \(config.pub[key]!)"
}
var OLD: String { line("old@example.com", "old") + "\n" }
var NEW3: String { OLD + line("jeb-release", "new") + "\n" }
var ONLY_NEW: String { line("jeb-release", "new") + "\n" }

// MARK: - processes

struct Result {
    let rc: Int32
    let stdout: String
    let stderr: String
}

/// subprocess.run(argv, env=env, capture_output=True, text=True, cwd=cwd): the child gets exactly `env` (nil = inherit).
@discardableResult
func runProcess(_ argv: [String], env: [String: String]? = nil, cwd: String? = nil, stdin: Data? = nil) -> Result {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: argv[0])
    p.arguments = Array(argv.dropFirst())
    if let env = env { p.environment = env }
    if let cwd = cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    let inPipe = Pipe()
    p.standardInput = inPipe
    do { try p.run() } catch {
        return Result(rc: 127, stdout: "", stderr: "goldencheck: cannot run \(argv[0]): \(error)\n")
    }
    if let stdin = stdin { inPipe.fileHandleForWriting.write(stdin) }
    try? inPipe.fileHandleForWriting.close()
    let g = DispatchGroup()
    var o = Data(), e = Data()
    g.enter(); DispatchQueue.global().async { o = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
    g.enter(); DispatchQueue.global().async { e = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
    g.wait()
    p.waitUntilExit()
    return Result(rc: p.terminationStatus, stdout: String(decoding: o, as: UTF8.self), stderr: String(decoding: e, as: UTF8.self))
}

func must(_ argv: [String], env: [String: String]? = nil, cwd: String? = nil) {
    let r = runProcess(argv, env: env, cwd: cwd)
    if r.rc != 0 { fail("\(argv.joined(separator: " ")) failed (\(r.rc)): \(r.stderr)") }
}

// MARK: - one-time setup: keys, stub, fake tools

func setupFixtures() {
    let t = config.tmp
    mkdirs(t + "/keys"); mkdirs(t + "/bin")
    for k in pubOrder {
        must(["/usr/bin/ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", k, "-f", t + "/keys/" + k])
        config.keys[k] = t + "/keys/" + k
        let pubText = readText(t + "/keys/" + k + ".pub") ?? ""
        config.pub[k] = pubText.split(whereSeparator: { $0 == " " || $0 == "\n" }).prefix(2).joined(separator: " ")
    }
    must(["/usr/bin/cc", "-arch", config.arch, "-o", config.stub, config.root + "/desktop/tests/stub.c"])
    for n in ["claude", "gh", "launchctl"] {
        writeText(t + "/bin/" + n, "#!/bin/sh\necho \"$0 $*\" >> \"$JEB_FAKE_LOG\"\ncase \"$*\" in \"plugin list --json\"|\"plugin marketplace list --json\") echo \"[]\";; esac\nexit 0\n")
        chmod(t + "/bin/" + n, 0o755)
    }
    writeText(t + "/bin/curl", "#!/bin/sh\necho \"curl: network is off in the golden capture\" >&2\nexit 7\n")
    chmod(t + "/bin/curl", 0o755)
    config.head = runProcess(["/usr/bin/git", "-C", config.root, "rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !config.head.isEmpty {
        config.headRule = Rule(NSRegularExpression.escapedPattern(for: String(config.head.prefix(7))) + "[0-9a-f]*", "\\$HEAD")
    }
}

// MARK: - which program a scenario means (the names are the Python files the goldens were captured from)

enum Tool {
    case jebctl      // desktop/jebctl  -> the jebctl binary
    case watchdog    // watchdog.py     -> jebctl watchdog
    case updater     // updater.py      -> jebctl apply
    case install     // ./install       -> the install sh shim of the bundle (execs desktop/bin/jebctl install)
    case uninstall   // ./uninstall     -> the uninstall sh shim
    case release     // ./release       -> dev/release/release
    case parity      // src/tools/parity.py -> jebgates parity
    case fake        // src/tools/fake.py   -> jebgates fake
}

/// The pinned clock/pid env for a Swift binary (plan 3.1); `noProcs` = no running processes.
func swiftTestEnv(noProcs: Bool) -> [String: String] {
    var e = ["JEB_TEST_NOW": String(NOW), "JEB_TEST_PID": String(PID)]
    if noProcs { e["JEB_TEST_NO_PROCS"] = "1" }
    return e
}

/// The argv for a Swift tool, or nil when it is not built.
/// The follow/rollback/update scenarios run the Swift jebctl from inside the live bundle.
var runInBundle = false

func swiftArgv(_ tool: Tool, _ argv: [String], scriptPath: String?) -> [String]? {
    let c = config!
    switch tool {
    case .jebctl: return isFile(c.swiftJebctl) ? [c.swiftJebctl] + argv : nil
    case .watchdog: return isFile(c.swiftJebctl) ? [c.swiftJebctl, "watchdog"] + argv : nil
    case .updater: return isFile(c.swiftJebctl) ? [c.swiftJebctl, "apply"] + argv : nil
    case .install, .uninstall:
        // inside an unpacked bundle: what the sh shim execs, the bundle's own desktop/bin/jebctl (the dev build is copied over
        // the stub).
        guard let path = scriptPath else { return nil }
        let root = (path as NSString).deletingLastPathComponent
        guard isFile(root + "/bundle.json") else { return [path] + argv }
        guard isFile(c.swiftJebctl) else { return nil }
        removeAll(root + "/desktop/bin/jebctl")
        copyFile(c.swiftJebctl, root + "/desktop/bin/jebctl")
        chmod(root + "/desktop/bin/jebctl", 0o755)
        return [root + "/desktop/bin/jebctl", tool == .install ? "install" : "uninstall"] + argv
    case .release: return isFile(c.swiftRelease) ? [c.swiftRelease] + argv : nil
    case .parity: return isFile(c.swiftGates) ? [c.swiftGates, "parity"] + argv : nil
    case .fake: return isFile(c.swiftGates) ? [c.swiftGates, "fake"] + argv : nil
    }
}

func notBuilt(_ tool: Tool) -> Result {
    Result(rc: 127, stdout: "", stderr: "goldencheck: no Swift binary for \(tool) yet (TODO)\n")
}

// MARK: - the sandbox

var sandboxN = 0

final class SB {
    let root, home, jeb, state, agents, rel, fake, stublog: String
    var env: [String: String]

    /// One sandbox: HOME and every path override under it (the layout of desktop/tests/bridge-sandbox.sh).
    init(_ name: String) {
        sandboxN += 1
        root = config.tmp + "/sb\(sandboxN)-\(name)"
        home = root + "/home"
        jeb = home + "/.jeb"
        state = home + "/Library/Application Support/Jeb"
        agents = home + "/Library/LaunchAgents"
        rel = root + "/rel"
        fake = root + "/fake.log"
        stublog = root + "/stub.log"
        for d in [state, agents, home + "/.local/bin", rel, home + "/Applications"] { mkdirs(d) }
        try? FileManager.default.createSymbolicLink(atPath: home + "/.local/bin/claude", withDestinationPath: config.tmp + "/bin/claude")
        writeText(fake, "")
        env = [
            "PATH": "\(config.tmp)/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home, "TMPDIR": root,
            "JEB_HOME": state, "JEB_APP_DIR": home + "/Applications", "JEB_LAUNCHAGENTS": agents, "JEB_BIN_DIR": home + "/.local/bin",
            "JEB_PROFILE": home + "/.zprofile", "JEB_SETTINGS": home + "/.claude/settings.json", "JEB_BACKUPS": home + "/.claude/backups",
            "JEB_STORE_DIR": home + "/.claude/plugins/data", "CLAUDE_CONFIG_DIR": home + "/.claude", "JEB_TOOLS_DIR": jeb + "/bin",
            "JEB_RELEASE_BASE": "file://" + rel, "JEB_NO_LAUNCHCTL": "1", "JEB_FAKE_LOG": fake, "JEB_STUB_LOG": stublog,
            "JEB_STUB_FLIP": jeb + "/current",
        ]
        precondition(home.hasPrefix(config.tmp) && !state.hasPrefix(NSHomeDirectory() + "/Library"), "sandbox escaped")
        mode("release")
    }

    func mode(_ m: String) {
        writeText(state + "/install-mode", m + "\n")
    }

    func bundleTree(_ root: String, _ tag: String, schema: Int = 2, signers: String? = nil, drop: [String] = [], nonmacho: Bool = false, scripts: Bool = false) {
        let v = String(tag.dropFirst())
        for d in ["desktop/bin", "desktop/src/fixtures", "mod/.claude-plugin", "mod/hooks", ".claude-plugin", "app"] { mkdirs(root + "/" + d) }
        writeText(root + "/bundle.json", obj(("schema", .int(schema)), ("repo", "clevyr/jeb"), ("tag", .string(tag)), ("version", .string(v)),
                                             ("commit", .string(String(repeating: "0", count: 40))), ("arch", .string(config.arch))).dumps())
        writeText(root + "/mod/.claude-plugin/plugin.json", obj(("name", "jeb"), ("version", .string(v))).dumps())
        writeText(root + "/.claude-plugin/marketplace.json", "{}")
        writeText(root + "/desktop/src/fixtures/smoke.json", "{}")      // the bundle shape release checks (Bundles.swift required)
        writeText(root + "/mod/hooks/pixel-art.ts", "\n")
        writeText(root + "/install", "#!/bin/sh\n")
        writeText(root + "/desktop/release-signers", signers ?? NEW3)
        for n in ["JebDesktop", "detect", "png2raw"] { copyFile(config.stub, root + "/app/" + n) }
        let ctl = root + "/desktop/bin/jebctl"
        if nonmacho { writeText(ctl, "#!/bin/sh\nexit 0\n") } else { copyFile(config.stub, ctl) }
        chmod(ctl, 0o755)
        if schema == 1 {
            for f in LEGACY_FILES { writeText(root + "/desktop/" + f, "# legacy placeholder\n") }
            mkdirs(root + "/python/bin")
            copyFile(config.stub, root + "/python/bin/python3")
        }
        if scripts {
            for f in ["install", "uninstall"] { copyFile(config.root + "/" + f, root + "/" + f) }
        }
        for rel in drop { removeAll(root + "/" + rel) }
    }

    @discardableResult
    func installBundle(_ tag: String, signers: String? = nil, pin: String?? = .some(nil), signersFrom: String? = nil, scripts: Bool = false, rs: JSON? = nil) -> String {
        let v = jeb + "/versions/" + tag
        bundleTree(v, tag, schema: 1, signers: signers, scripts: scripts)
        try? FileManager.default.createSymbolicLink(atPath: jeb + "/current", withDestinationPath: "versions/" + tag)
        // pin: .some(nil) means the default (OLD); .some(.some(x)) a text; .none (pass `pin: nil as String??`) no pin
        switch pin {
        case .some(.some(let text)): writePin(text)
        case .some(.none): writePin(OLD)
        case .none: break
        }
        var state = rs ?? defaultRS(tag: tag)
        if rs == nil, let sf = signersFrom { state = state.setting("signers_from", .string(sf)) }
        saveRS(state)
        latest(tag)
        return v
    }

    func writePin(_ text: String) {
        writeText(state + "/release-signers", text)
        chmod(state + "/release-signers", 0o600)
    }

    func saveRS(_ rs: JSON) {
        writeText(state + "/release-state.json", rs.dumps())
    }

    func loadRS() -> JSON {
        (try? JSON.parse(readText(state + "/release-state.json") ?? "")) ?? obj()
    }

    func latest(_ tag: String) {
        writeText(rel + "/latest", tag)
    }

    /// Publish tag in the file:// tree: zip, manifest, signature (throwaway key `key`), and `latest`.
    @discardableResult
    func release(_ tag: String, key: String = "new", schema: Int = 2, signers: String? = nil, flaw: String? = nil, manifestTag: String? = nil) -> (String, String) {
        let work = root + "/work-" + tag
        removeAll(work)
        bundleTree(work, tag, schema: schema, signers: signers, drop: flaw == "content" ? ["mod"] : [], nonmacho: flaw == "arch")
        let d = rel + "/download/" + tag
        mkdirs(d)
        let zname = "Jeb-\(tag)-macos-\(config.arch).zip"
        let zp = d + "/" + zname
        removeAll(zp)
        must(["/usr/bin/ditto", "-c", "-k", "--norsrc", "--noextattr", work, zp])
        let bytes = readBytes(zp) ?? Data()
        var sha = sha256Hex(bytes)
        var size = bytes.count
        if flaw == "sha" { sha = String(repeating: "0", count: 64) }
        if flaw == "size" { size -= 10 }
        let man = d + "/Jeb-\(tag)-manifest.json"
        let body = obj(("schema", 1), ("repo", "clevyr/jeb"), ("tag", .string(manifestTag ?? tag)), ("version", .string(String(tag.dropFirst()))),
                       ("bundles", obj((config.arch, obj(("name", .string(zname)), ("sha256", .string(sha)), ("size", .int(size)))))))
        writeText(man, flaw == "json" ? "{not json" : body.dumps())
        removeAll(man + ".sig")
        must(["/usr/bin/ssh-keygen", "-q", "-Y", "sign", "-f", config.keys[key]!, "-n", "jeb-release", man])
        latest(tag)
        return (man, man + ".sig")
    }

    // MARK: running

    func run(_ argv: [String], cwd: String? = nil, extra: [String: String] = [:]) -> Result {
        var e = BASE_ENV
        for (k, v) in env { e[k] = v }
        for (k, v) in extra { e[k] = v }
        return runProcess(argv, env: e, cwd: cwd ?? root)
    }

    /// Run a Jeb program: the built binary for `tool` with the clock/pid pinned by env. `probe` names an in-process probe
    /// (`jebctl --probe <name>`, its spec in JEB_PROBE_SPEC). `patches` nil means the default (no processes listed).
    func jc(_ argv: [String], tool: Tool = .jebctl, patches: [(String, JSON)]? = [], cwd: String? = nil, extra: [String: String] = [:], probe: String? = nil,
            specExtra: [(String, JSON)] = []) -> Result {
        var pt: [(String, JSON)] = patches == nil ? [] : [("running", true), ("notify", true)]
        for (k, v) in patches ?? [] { if let i = pt.firstIndex(where: { $0.0 == k }) { pt[i].1 = v } else { pt.append((k, v)) } }
        var a = probe.map { ["--probe", $0] } ?? []
        a += argv
        guard var full = swiftArgv(tool, a, scriptPath: nil) else { return notBuilt(tool) }
        if runInBundle, tool == .jebctl {
            // the dev build is copied over the live bundle's native jebctl (the stub)
            let live = URL(fileURLWithPath: jeb + "/current").resolvingSymlinksInPath().path
            removeAll(live + "/desktop/bin/jebctl")
            copyFile(config.swiftJebctl, live + "/desktop/bin/jebctl")
            chmod(live + "/desktop/bin/jebctl", 0o755)
            full[0] = live + "/desktop/bin/jebctl"
        }
        var ex = extra
        let noProcs = pt.first { $0.0 == "running" }?.1.boolValue ?? false
        for (k, v) in swiftTestEnv(noProcs: noProcs) { ex[k] = v }
        if probe != nil { ex["JEB_PROBE_SPEC"] = obj(specExtra).dumps() }
        return run(full, cwd: cwd, extra: ex)
    }

    /// Run one of the top-level scripts (./install, ./uninstall, ./release, updater.py --help ...) at `path` with `args`.
    func script(_ path: String, _ args: [String], tool: Tool, cwd: String? = nil, extra: [String: String] = [:]) -> Result {
        guard let full = swiftArgv(tool, args, scriptPath: path) else { return notBuilt(tool) }
        var ex = extra
        for (k, v) in swiftTestEnv(noProcs: true) { ex[k] = v }
        return run(full, cwd: cwd, extra: ex)
    }
}

extension JSON {
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
}

func defaultRS(tag: String) -> JSON {
    obj(("failed", []), ("checked", nil), ("last", nil), ("layout", "bundle"), ("installed", [obj(("tag", .string(tag)), ("stamp", nil), ("at", 1))]), ("bridge_reset", 1))
}

func plainSB(_ name: String, _ mode: String = "release") -> SB {
    let sb = SB(name)
    sb.mode(mode)
    return sb
}

func bundleSB(_ name: String, tag: String = "v1.4.0", signers: String? = nil, pin: String?? = .some(nil), signersFrom: String? = nil, scripts: Bool = false) -> SB {
    let sb = SB(name)
    sb.installBundle(tag, signers: signers, pin: pin, signersFrom: signersFrom, scripts: scripts)
    return sb
}

/// time.strftime("%Y-%m-%d", time.localtime(t)) under TZ=America/Chicago.
func chicagoDay(_ t: Int) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "America/Chicago")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
}
