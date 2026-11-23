// Key: the signing key (./release setup, and the unlock a release starts with). Releases are signed twice with one SSH
// key: git signs the tag and ssh-keygen -Y sign the manifest (namespace jeb-release). A release asks for the key's
// passphrase once, first, and holds the key in a private ssh-agent that ends with the run.
import Foundation

let setupKeyPath = "~/.ssh/jeb_signing"

private func isKeyType(_ s: String) -> Bool { s.hasPrefix("ssh-") || s.hasPrefix("ecdsa-") || s.hasPrefix("sk-") }

private var signingSetUp: Bool { cfg("gpg.format") == "ssh" && !cfg("user.signingkey").isEmpty }

/// 'ssh-... base64' from git config; exits with the config commands to run when something is missing.
func publicKey() -> String {
    let key = cfg("user.signingkey")
    if !signingSetUp {
        fail("signing is not set up for SSH. Run (with your own key):\n  git config gpg.format ssh\n  git config user.signingkey ~/.ssh/jeb_signing.pub")
    }
    var text: String
    if key.hasPrefix("key::") {
        text = String(key.dropFirst(5))
    } else {
        var path = expandUser(key)
        if !path.hasSuffix(".pub") && FileManager.default.fileExists(atPath: path + ".pub") { path += ".pub" }
        guard let t = readText(path) else { fail("cannot read the public key \(path) named by user.signingkey") }
        text = t
    }
    let f = fields(text)
    if f.count < 2 || !isKeyType(f[0]) {
        fail("user.signingkey is not an SSH public key (a .pub file, a private key with a .pub beside it, or key::ssh-...)")
    }
    return f[0] + " " + f[1]
}

/// ssh-keygen's fingerprint line for a 'keytype base64' text.
func fingerprint(_ line: String) -> String {
    let tmp = NSTemporaryDirectory() + "/jeb-release-key-\(getpid()).pub"
    defer { unlink(tmp) }
    guard (try? (line + "\n").write(toFile: tmp, atomically: true, encoding: .utf8)) != nil else { return "unreadable" }
    let out = run([tool("ssh-keygen"), "-lf", tmp]).out.trimmingCharacters(in: .whitespacesAndNewlines)
    return out.isEmpty ? "unreadable" : out
}

/// Make ~/.ssh/jeb_signing when missing and point this clone's git at it, unless signing is already set up.
private func configure() {
    if signingSetUp { return }
    let key = expandUser(setupKeyPath)
    if !FileManager.default.fileExists(atPath: key) {
        say("\(dryRun ? "would create" : "creating") the signing key \(key) (pick a passphrase and keep it, and back the key up)")
        if !dryRun {
            try? FileManager.default.createDirectory(atPath: (key as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if run([tool("ssh-keygen"), "-t", "ed25519", "-C", "jeb-release", "-f", key], capture: false).status != 0 {
                fail("ssh-keygen failed; nothing configured")
            }
        }
    }
    for (k, v) in [("gpg.format", "ssh"), ("user.signingkey", key)] {
        say("$ git config \(k) \(v)")
        if !dryRun && git("config", k, v).status != 0 { fail("could not set \(k)") }
    }
}

/// ./release setup: the key, git's signing config and desktop/release-signers (never overwritten).
func setup() -> Int32 {
    configure()
    if dryRun && !signingSetUp {
        say("would then write desktop/release-signers from that key")
        return 0
    }
    let key = publicKey()
    let line = "jeb-release namespaces=\"git,jeb-release\" \(key)"
    if let text = readText(signersPath) {
        let lines = splitLines(text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        say("\(signersPath) exists:")
        for l in lines { say("  " + fingerprint(fields(l).suffix(2).joined(separator: " "))) }
        if lines.contains(where: { $0.contains(key) }) {
            say("configured key is in it")
        } else {
            say("configured key is NOT in it (a release signed with it will not verify). Add this line, keeping the others:\n  " + line)
        }
        return 0
    }
    say("\(dryRun ? "would write" : "writing") \(signersPath):\n  \(line)\n  \(fingerprint(key))")
    if !dryRun {
        let fd = open(signersPath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard fd >= 0 else { fail("could not create \(signersPath): \(String(cString: strerror(errno)))") }
        let bytes = Array((line + "\n").utf8)
        let n = write(fd, bytes, bytes.count)
        close(fd)
        if n != bytes.count { fail("could not write \(signersPath)") }
        chmod(signersPath, 0o644)
    }
    say("Commit and push desktop/release-signers before the first release; installs pin it on first install and adopt it from newer signed releases.")
    return 0
}

/// Refuse when any tracked file holds a private key (release-signers is public keys only).
func noPrivateKeys() {
    let hits = fields(git("grep", "-l", "-I", "-E", "-e", "-----BEGIN [A-Z ]*PRIVATE KEY-----").out)
    if !hits.isEmpty { fail("a tracked file holds a private key; remove it from git before releasing: " + hits.joined(separator: ", ")) }
}

/// The private key git signs tags with (ssh-keygen -Y sign needs the private file, not the .pub).
func signingKey() -> String {
    let raw = cfg("user.signingkey")
    let k = expandUser(raw)
    if raw.isEmpty || k.hasPrefix("key::") { fail("user.signingkey must name a private key file to sign the manifest; run ./release setup") }
    let bare = String(k.dropLast(4))
    return k.hasSuffix(".pub") && FileManager.default.fileExists(atPath: bare) ? bare : k
}

/// The private ssh-agent of this run (0: none); the Ctrl-C handler ends it too.
var agentPid: pid_t = 0

/// Ask for the signing key's passphrase now, before the checks and builds: a private ssh-agent for this run holds the
/// key, and git (the tag) and ssh-keygen -Y sign (the manifest) sign through it. The key expires after 4 hours in case
/// the agent outlives a killed run.
func unlockKey() {
    let key = signingKey()
    let r = run([tool("ssh-agent"), "-s"])
    var found: [String: String] = [:]
    for m in reFindAll("(SSH_AUTH_SOCK|SSH_AGENT_PID)=([^;]+);", r.out) { found[m[1]] = m[2] }
    guard r.status == 0, let sock = found["SSH_AUTH_SOCK"], let pid = found["SSH_AGENT_PID"].flatMap({ pid_t($0) }), pid > 1 else {
        fail("could not start ssh-agent to hold the signing key")
    }
    setEnvVar("SSH_AUTH_SOCK", sock)
    setEnvVar("SSH_AGENT_PID", String(pid))
    agentPid = pid
    say("unlocking the signing key \(key)")
    if run([tool("ssh-add"), "-t", "4h", key], capture: false).status != 0 {
        lockKey()
        fail("the signing key was not unlocked; nothing was done")
    }
}

/// End this run's ssh-agent, and the key with it.
func lockKey() {
    if agentPid > 1 { kill(agentPid, SIGTERM) }
    agentPid = 0
}
